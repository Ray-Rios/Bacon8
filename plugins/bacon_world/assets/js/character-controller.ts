// Third-person controls with RaysSpaceSim's on-foot feel (ARSSCharacter: Unreal's
// third-person template). An orbit camera on a boom follows the mouse; WASD and
// the arrows move relative to the camera; the character turns to face where it
// moves. The maths and the numbers live in controls-math.ts.
import * as THREE from '../../../../assets/js/vendor/three';
import {
  CAMERA,
  CHARACTER_HEIGHT_UNITS,
  MOVE,
  PACE,
  UNITS_PER_METRE,
  clampLookPitch,
  cameraPosition,
  facingYaw,
  moveDirection,
  stepVelocity,
  turnToward,
  zoomDistance,
  type Vec2,
} from './controls-math';

export interface ControllerOptions {
  /** The renderer's canvas: mouse look, zoom and pointer lock happen here. */
  canvas: HTMLCanvasElement;
  /** Asked before requesting pointer lock (false while chatting or dead). */
  canLock?: () => boolean;
  /** Told when pointer lock starts or ends, to show the hint or the centre dot. */
  onPointerLockChange?: (locked: boolean) => void;
  /** The character's height in scene units, for the camera pivot. */
  characterHeight?: number;
}

export type MovementState = {
  isMoving: boolean;
  isRunning: boolean;
  isSprinting: boolean;
  isGrounded: boolean;
  isCrouching: boolean;
  /** Horizontal speed, m/s. */
  speed: number;
};

const MOVEMENT_CODES = new Set([
  'KeyW', 'KeyA', 'KeyS', 'KeyD',
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'Space', 'ShiftLeft', 'ShiftRight', 'KeyC',
]);

// Browsers can report one huge movementX/Y as pointer lock starts or ends.
const MAX_MOUSE_DELTA = 300;

function isEditable(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  if (!el || !el.tagName) return false;
  return ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName) || el.isContentEditable;
}

export class CharacterController {
  private character: THREE.Object3D;
  private camera: THREE.Camera;
  private canvas: HTMLCanvasElement;
  private options: ControllerOptions;
  private terrain: THREE.Mesh | null = null;
  private raycaster = new THREE.Raycaster();

  // Physics, in metres and seconds (converted at the scene boundary).
  private velocity: Vec2 = { x: 0, z: 0 };
  private verticalSpeed = 0;
  private isGrounded = true;
  private isCrouching = false;
  private isSprinting = false;
  private speed = 0;

  // Camera: yaw psi = 0 looks along +Z; look pitch < 0 looks down.
  private yaw = 0;
  private lookPitch = -15 * (Math.PI / 180);
  private distance: number = CAMERA.distance;
  private pivotY: number | null = null;

  // Input
  private keys = new Set<string>();
  private rightDragging = false;
  private skipNextMouseMove = false;

  // Bound once, so dispose() removes the same functions it added.
  private readonly handleKeyDown = (e: KeyboardEvent) => this.onKeyDown(e);
  private readonly handleKeyUp = (e: KeyboardEvent) => this.onKeyUp(e);
  private readonly handleBlur = () => this.keys.clear();
  private readonly handleVisibility = () => { if (document.hidden) this.keys.clear(); };
  private readonly handleMouseDown = (e: MouseEvent) => this.onMouseDown(e);
  private readonly handleMouseUp = (e: MouseEvent) => this.onMouseUp(e);
  private readonly handleMouseMove = (e: MouseEvent) => this.onMouseMove(e);
  private readonly handleWheel = (e: WheelEvent) => this.onWheel(e);
  private readonly handleClick = (e: MouseEvent) => this.onClick(e);
  private readonly handleContextMenu = (e: MouseEvent) => e.preventDefault();
  private readonly handlePointerLockChange = () => this.onPointerLockChange();

  private onPositionUpdate?: (x: number, y: number, z: number, rotation: number) => void;

  constructor(character: THREE.Object3D, camera: THREE.Camera, options: ControllerOptions) {
    this.character = character;
    this.camera = camera;
    this.canvas = options.canvas;
    this.options = options;
    // Start behind the character, looking where it faces.
    this.yaw = character.rotation.y;

    document.addEventListener('keydown', this.handleKeyDown);
    document.addEventListener('keyup', this.handleKeyUp);
    document.addEventListener('visibilitychange', this.handleVisibility);
    document.addEventListener('pointerlockchange', this.handlePointerLockChange);
    window.addEventListener('blur', this.handleBlur);
    this.canvas.addEventListener('mousedown', this.handleMouseDown);
    this.canvas.addEventListener('mouseup', this.handleMouseUp);
    this.canvas.addEventListener('mousemove', this.handleMouseMove);
    this.canvas.addEventListener('wheel', this.handleWheel, { passive: false });
    this.canvas.addEventListener('click', this.handleClick);
    this.canvas.addEventListener('contextmenu', this.handleContextMenu);
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  private onKeyDown(event: KeyboardEvent): void {
    if (isEditable(event.target)) return;
    if (!MOVEMENT_CODES.has(event.code)) return;
    this.keys.add(event.code);
    // Space and the arrows would scroll the page.
    if (event.code === 'Space' || event.code.startsWith('Arrow')) event.preventDefault();
  }

  private onKeyUp(event: KeyboardEvent): void {
    // Always clear, even from an input: a key held when focus moved must not stick.
    this.keys.delete(event.code);
  }

  private onMouseDown(event: MouseEvent): void {
    if (event.button === 2 && !this.isPointerLocked()) {
      this.rightDragging = true;
      this.skipNextMouseMove = true;
    }
  }

  private onMouseUp(event: MouseEvent): void {
    if (event.button === 2) this.rightDragging = false;
  }

  private onMouseMove(event: MouseEvent): void {
    if (!this.isPointerLocked() && !this.rightDragging) return;
    if (this.skipNextMouseMove) {
      this.skipNextMouseMove = false;
      return;
    }
    const dx = event.movementX || 0;
    const dy = event.movementY || 0;
    if (Math.abs(dx) > MAX_MOUSE_DELTA || Math.abs(dy) > MAX_MOUSE_DELTA) return;

    // Mouse right turns the view right (psi decreases); mouse up looks up.
    this.yaw -= dx * CAMERA.mouseSensitivity;
    this.lookPitch = clampLookPitch(this.lookPitch - dy * CAMERA.mouseSensitivity);
  }

  private onWheel(event: WheelEvent): void {
    event.preventDefault();
    this.distance = zoomDistance(this.distance, event.deltaY);
  }

  private onClick(event: MouseEvent): void {
    if (event.button !== 0 || this.isPointerLocked()) return;
    if (event.target !== this.canvas) return;
    if (this.options.canLock && !this.options.canLock()) return;

    try {
      // Chrome returns a promise (and rejects if asked again too soon after Esc).
      const result = this.canvas.requestPointerLock() as unknown as Promise<void> | undefined;
      if (result && typeof result.catch === 'function') result.catch(() => {});
    } catch (_e) {
      // Not available (an iframe without permission): right-drag still works.
    }
  }

  private onPointerLockChange(): void {
    const locked = this.isPointerLocked();
    // The first move after the lock starts or ends can be a jump across the screen.
    this.skipNextMouseMove = true;
    if (locked) this.rightDragging = false;
    this.options.onPointerLockChange?.(locked);
  }

  isPointerLocked(): boolean {
    return document.pointerLockElement === this.canvas;
  }

  /** Give the cursor back (chat opened, character died). */
  releasePointerLock(): void {
    if (this.isPointerLocked()) document.exitPointerLock();
  }

  // ---------------------------------------------------------------------------
  // Per frame
  // ---------------------------------------------------------------------------

  update(deltaTime: number): void {
    const dt = Math.min(deltaTime, 0.1); // a stalled tab mustn't fling the character
    const before = { x: this.character.position.x, y: this.character.position.y, z: this.character.position.z, heading: this.character.rotation.y };

    this.updateMovement(dt);
    this.updateCamera(dt);

    const p = this.character.position;
    const changed = p.x !== before.x || p.y !== before.y || p.z !== before.z || this.character.rotation.y !== before.heading;
    if (this.onPositionUpdate && changed) {
      this.onPositionUpdate(p.x, p.y, p.z, this.character.rotation.y);
    }
  }

  private held(...codes: string[]): boolean {
    return codes.some((c) => this.keys.has(c));
  }

  private updateMovement(dt: number): void {
    const dir = moveDirection(
      {
        forward: this.held('KeyW', 'ArrowUp'),
        back: this.held('KeyS', 'ArrowDown'),
        left: this.held('KeyA', 'ArrowLeft'),
        right: this.held('KeyD', 'ArrowRight'),
      },
      this.yaw
    );
    const hasInput = dir.x !== 0 || dir.z !== 0;

    this.isCrouching = this.held('KeyC') && this.isGrounded;
    this.isSprinting = this.held('ShiftLeft', 'ShiftRight') && !this.isCrouching;
    const maxSpeed = this.isCrouching ? MOVE.crouchSpeed : this.isSprinting ? MOVE.sprintSpeed : MOVE.jogSpeed;

    const control = this.isGrounded ? 1 : MOVE.airControl;
    const braking = this.isGrounded ? MOVE.brakingGround : MOVE.brakingAir;
    this.velocity = stepVelocity(
      this.velocity,
      { x: dir.x * maxSpeed, z: dir.z * maxSpeed },
      hasInput,
      MOVE.acceleration * control,
      braking,
      dt
    );
    this.speed = Math.hypot(this.velocity.x, this.velocity.z);

    // Face the way we move (bOrientRotationToMovement), not the camera.
    if (hasInput) {
      this.character.rotation.y = turnToward(this.character.rotation.y, facingYaw(dir), MOVE.turnRate * dt);
    }

    // Jump (grounded only), gravity, and the ground.
    if (this.held('Space') && this.isGrounded) {
      this.verticalSpeed = MOVE.jumpSpeed;
      this.isGrounded = false;
    }
    if (!this.isGrounded) this.verticalSpeed -= MOVE.gravity * dt;

    const pos = this.character.position;
    pos.x += this.velocity.x * UNITS_PER_METRE * dt;
    pos.z += this.velocity.z * UNITS_PER_METRE * dt;
    pos.y += this.verticalSpeed * UNITS_PER_METRE * dt;

    const ground = this.groundHeight(pos.x, pos.z);
    if (pos.y <= ground) {
      pos.y = ground;
      this.verticalSpeed = 0;
      this.isGrounded = true;
    } else if (this.isGrounded && pos.y - ground > 0.05) {
      // Walked off a ledge.
      this.isGrounded = false;
    }
  }

  private updateCamera(dt: number): void {
    const height = this.options.characterHeight ?? CHARACTER_HEIGHT_UNITS;
    const feet = this.character.position;
    const targetPivotY = feet.y + height * CAMERA.pivotHeight;
    // Smooth only the pivot's height, to soften jump bobbing; the orbit itself
    // follows the mouse with no lag, as in RaysSpaceSim.
    this.pivotY = this.pivotY === null ? targetPivotY : this.pivotY + (targetPivotY - this.pivotY) * (1 - Math.exp(-dt * 12));
    const pivot = { x: feet.x, y: this.pivotY, z: feet.z };

    const cam = cameraPosition(pivot, this.yaw, this.lookPitch, this.distance * UNITS_PER_METRE);
    const floor = this.groundHeight(cam.x, cam.z) + CAMERA.minHeightAboveGround * UNITS_PER_METRE;
    this.camera.position.set(cam.x, Math.max(cam.y, floor), cam.z);
    this.camera.lookAt(pivot.x, pivot.y, pivot.z);
  }

  private groundHeight(x: number, z: number): number {
    if (!this.terrain) return 0;
    this.raycaster.set(new THREE.Vector3(x, 1000, z), new THREE.Vector3(0, -1, 0));
    const hits = this.raycaster.intersectObject(this.terrain, false);
    return hits.length > 0 ? hits[0].point.y : 0;
  }

  // ---------------------------------------------------------------------------
  // API used by the scene
  // ---------------------------------------------------------------------------

  /** Respawn or server correction: move there at rest, camera behind the new heading. */
  teleportTo(x: number, y: number, z: number, heading: number = 0): void {
    this.character.position.set(x, y, z);
    this.character.rotation.y = heading;
    this.velocity = { x: 0, z: 0 };
    this.verticalSpeed = 0;
    this.speed = 0;
    this.yaw = heading;
    this.pivotY = null;
    this.updateCamera(0);
  }

  setTerrain(terrain: THREE.Mesh): void {
    this.terrain = terrain;
  }

  setPositionCallback(callback: (x: number, y: number, z: number, rotation: number) => void): void {
    this.onPositionUpdate = callback;
  }

  getMovementState(): MovementState {
    const isMoving = this.speed >= PACE.idleBelow;
    return {
      isMoving,
      isRunning: isMoving && !this.isCrouching,
      isSprinting: isMoving && this.isGrounded && (this.isSprinting || this.speed > PACE.jogUpTo),
      isGrounded: this.isGrounded,
      isCrouching: this.isCrouching,
      speed: this.speed,
    };
  }

  /** Current position for /loc. */
  getPosition(): { x: number; y: number; z: number } {
    return {
      x: Math.round(this.character.position.x * 10) / 10,
      y: Math.round(this.character.position.y * 10) / 10,
      z: Math.round(this.character.position.z * 10) / 10,
    };
  }

  /** /warp: move there and fall to the ground. */
  warpTo(x: number, y: number, z: number): void {
    this.character.position.set(x, y, z);
    this.velocity = { x: 0, z: 0 };
    this.verticalSpeed = 0;
    this.isGrounded = false;
  }

  dispose(): void {
    this.releasePointerLock();
    document.removeEventListener('keydown', this.handleKeyDown);
    document.removeEventListener('keyup', this.handleKeyUp);
    document.removeEventListener('visibilitychange', this.handleVisibility);
    document.removeEventListener('pointerlockchange', this.handlePointerLockChange);
    window.removeEventListener('blur', this.handleBlur);
    this.canvas.removeEventListener('mousedown', this.handleMouseDown);
    this.canvas.removeEventListener('mouseup', this.handleMouseUp);
    this.canvas.removeEventListener('mousemove', this.handleMouseMove);
    this.canvas.removeEventListener('wheel', this.handleWheel);
    this.canvas.removeEventListener('click', this.handleClick);
    this.canvas.removeEventListener('contextmenu', this.handleContextMenu);
    this.keys.clear();
  }
}

export default CharacterController;
