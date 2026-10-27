// Third-person controls: RaysSpaceSim's on-foot movement (ARSSCharacter, Unreal's
// third-person template) with EverQuest-style mouse handling. The maths and the
// numbers live in controls-math.ts.
//
//   Left-click the game   lock the pointer: free look, the character turns to
//                         face where it moves
//   Mouse buttons, locked attack, Black Desert style: left button the left hand,
//                         right button the right hand (held: keeps swinging).
//                         The character turns to face where the camera looks.
//   Left drag             with the cursor free: turn the camera around the character
//                         (it keeps facing its way); letting go doesn't lock the pointer
//   Right button held     with the cursor free: mouselook (EverQuest steering).
//                         The camera turns and the character keeps facing the
//                         camera's direction: W runs, S backpedals (slower), A/D
//                         strafe, diagonals turn the body 45 degrees.
//   Ctrl                  free the cursor; again, mouse-look on again
//   Esc                   free the cursor and ask the scene for its game menu
//   WASD / arrows         move relative to the camera; Shift sprints, C crouches,
//                         Space jumps; the wheel zooms
//   On a mount (setMount) the mount's speeds; one that flies takes off on a Space
//                         double-tap (RaysSpaceSim's), and again lands. Flying: W/S
//                         along the camera (look down to dive), A/D strafe, Space
//                         climbs, C dives, Shift boosts; touching down lands.
//
// Mouse-look over remote desktop: see mouse-filter.ts.
import * as THREE from '../../../../assets/js/vendor/three';
import {
  CAMERA,
  CHARACTER_HEIGHT_UNITS,
  FLIGHT,
  MOVE,
  PACE,
  SENSITIVITY,
  UNITS_PER_METRE,
  applyMouseLook,
  approachVelocity,
  cameraPosition,
  flightTarget,
  isDoubleTap,
  facingYaw,
  LOCK_LOSS_SETTLE_MS,
  lockLossWasEsc,
  moveDirection,
  stepVelocity,
  turnToward,
  zoomDistance,
  type Vec2,
} from './controls-math';
import { MouseFilter, jumpLimit, type Move } from './mouse-filter';

export interface ControllerOptions {
  /** The renderer's canvas: mouse look, zoom and pointer lock happen here. */
  canvas: HTMLCanvasElement;
  /** Asked before requesting pointer lock (false while dead or in the menu). */
  canLock?: () => boolean;
  /**
   * Asked before a left click with the cursor free grabs the mouse: false keeps the
   * cursor (the click opens a window that needs it, such as looting a corpse).
   */
  lockOnClick?: (event: MouseEvent) => boolean;
  /** Told when pointer lock starts or ends, to show the hint or the centre dot. */
  onPointerLockChange?: (locked: boolean) => void;
  /** The browser refused the lock (Chrome waits ~1 s after Esc): ask for another click. */
  onPointerLockError?: () => void;
  /**
   * Esc pressed ('key': toggle the menu), or the lock lost without us releasing
   * it ('lock-lost': the browser kept the Esc; open the menu).
   */
  onEscape?: (reason: 'key' | 'lock-lost') => void;
  /** The character's height in scene units, for the camera pivot. */
  characterHeight?: number;
  /**
   * Keeps the character out of solid things: given where it would stand (scene
   * units), returns where it may. Applied right after moving, before the camera
   * is placed and the position is reported.
   */
  /** Walls and the world's edge: where a move from (fromX, fromZ) to (x, z) ends up. */
  collide?: (x: number, z: number, fromX: number, fromZ: number) => { x: number; z: number };
  /** While flying high (no walls): the world's edge only. */
  bounds?: (x: number, z: number, fromX: number, fromZ: number) => { x: number; z: number };
  /** A mouse button went down with the pointer locked: swing that hand. */
  onAttack?: (hand: 'left' | 'right') => void;
}

export type MovementState = {
  isMoving: boolean;
  isRunning: boolean;
  isSprinting: boolean;
  isGrounded: boolean;
  isCrouching: boolean;
  /** On a flying mount, in the air (mounts.ts). */
  isFlying: boolean;
  /** Horizontal speed, m/s. */
  speed: number;
  /** Vertical speed, m/s (+ up). */
  verticalSpeed: number;
  /** Movement direction relative to where the character faces: +x right, +z forward (unit, or 0). */
  dirX: number;
  dirZ: number;
};

// Facing the camera, moving backwards is slower (EverQuest and WoW backpedal).
const BACKPEDAL = 0.6;

const MOVEMENT_CODES = new Set([
  'KeyW', 'KeyA', 'KeyS', 'KeyD',
  'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
  'Space', 'ShiftLeft', 'ShiftRight', 'KeyC',
]);

// The page as Chrome sees it, for the mouse filter.
const page = () => ({
  width: window.innerWidth || 1,
  height: window.innerHeight || 1,
  dpr: window.devicePixelRatio || 1,
});

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
  private groundFn: ((x: number, z: number) => number) | null = null;
  private surfaceFn: ((x: number, z: number) => number) | null = null;
  private raycaster = new THREE.Raycaster();

  // Physics, in metres and seconds (converted at the scene boundary).
  private velocity: Vec2 = { x: 0, z: 0 };
  private verticalSpeed = 0;
  private isGrounded = true;
  private isCrouching = false;
  private isSprinting = false;
  private speed = 0;

  // Riding (mounts.ts): the mount's speeds, and flying
  private mount: { groundSpeed: number; flySpeed: number; flies: boolean; pivot: number } | null = null;
  private flying = false;
  private flyVel = { x: 0, y: 0, z: 0 };
  private lastSpaceMs = -1e9;
  private footDistance: number | null = null;

  // Camera: yaw psi = 0 looks along +Z; look pitch < 0 looks down. The mouse turns it
  // directly, with no easing.
  private yaw = 0;
  private lookPitch = -15 * (Math.PI / 180);
  private distance: number = CAMERA.distance;
  private pivotY: number | null = null;

  // Settings (the game menu)
  private sensitivity: number = SENSITIVITY.default;
  private invertY = false;

  // Input
  private keys = new Set<string>();
  private inputEnabled = true;
  private steering = false; // right button held (cursor free): mouselook, character faces the camera
  // left button held (cursor free): where it went down, and whether it has moved enough to
  // orbit the camera; a drag's click must not lock the pointer
  private leftDown: { x: number; y: number } | null = null;
  private orbiting = false;
  private dragEndAt = -1e9;
  private attackHeld = { left: false, right: false }; // mouse buttons held with the pointer locked
  private faceCameraUntil = 0; // ms (performance.now): after a swing the character faces the camera
  private skipNextMouseMove = false;
  private releasingLock = false; // we asked for the lock to go (Ctrl, chat, menu, death)
  private wasLocked = false; // the lock state the last pointerlockchange saw
  // When the window last lost focus or was hidden, and when PrintScreen was last pressed (ms,
  // performance.now): a lock lost then was a screenshot tool or another window, not Esc.
  private lastAwayMs = -1e9;
  private lastPrintMs = -1e9;
  private disposed = false;
  // Mouse-look with the pointer locked goes through the remote-desktop filter.
  private mouseFilter = new MouseFilter(page);
  private cursor: Move | null = null; // the free cursor's last position, from the page's middle

  // Bound once, so dispose() removes the same functions it added.
  private readonly handleKeyDown = (e: KeyboardEvent) => this.onKeyDown(e);
  private readonly handleKeyUp = (e: KeyboardEvent) => this.onKeyUp(e);
  private readonly handleBlur = () => {
    this.lastAwayMs = performance.now();
    this.clearInput();
  };
  private readonly handleVisibility = () => {
    if (!document.hidden) return;
    this.lastAwayMs = performance.now();
    this.clearInput();
  };
  private readonly handleMouseDown = (e: MouseEvent) => this.onMouseDown(e);
  private readonly handleWindowMouseUp = (e: MouseEvent) => this.onMouseUp(e);
  private readonly handlePointerMove = (e: PointerEvent) => this.onPointerMove(e);
  private readonly handleWheel = (e: WheelEvent) => this.onWheel(e);
  private readonly handleClick = (e: MouseEvent) => this.onClick(e);
  private readonly handleContextMenu = (e: MouseEvent) => e.preventDefault();
  private readonly handlePointerLockChange = () => this.onPointerLockChange();
  private readonly handlePointerLockError = () => this.options.onPointerLockError?.();

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
    document.addEventListener('pointerlockerror', this.handlePointerLockError);
    window.addEventListener('blur', this.handleBlur);
    // Mouse buttons start on the canvas; moves and releases are followed on the
    // window, so a drag that slides off the canvas keeps turning the camera and
    // a release anywhere ends it.
    this.canvas.addEventListener('mousedown', this.handleMouseDown);
    window.addEventListener('mouseup', this.handleWindowMouseUp);
    window.addEventListener('pointermove', this.handlePointerMove);
    this.canvas.addEventListener('wheel', this.handleWheel, { passive: false });
    this.canvas.addEventListener('click', this.handleClick);
    this.canvas.addEventListener('contextmenu', this.handleContextMenu);
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  private onKeyDown(event: KeyboardEvent): void {
    if (event.code === 'PrintScreen') {
      this.lastPrintMs = performance.now();
      return;
    }
    if (isEditable(event.target)) return;

    if (event.code === 'ControlLeft' || event.code === 'ControlRight') {
      // A toggle (held, the key repeats: only the first press counts).
      if (event.repeat) return;
      if (this.isPointerLocked()) this.releasePointerLock();
      else {
        window.getSelection?.()?.removeAllRanges();
        this.requestPointerLock();
      }
      return;
    }
    // Ctrl/Cmd with a movement key is a browser shortcut (Ctrl+A selects the page,
    // Ctrl+S and Ctrl+D open dialogs): keep it in the game.
    if ((event.ctrlKey || event.metaKey) && MOVEMENT_CODES.has(event.code)) event.preventDefault();
    if (event.code === 'Escape') {
      this.releasePointerLock();
      this.options.onEscape?.('key');
      return;
    }

    if (!this.inputEnabled || !MOVEMENT_CODES.has(event.code)) return;
    if (event.code === 'Space' && !event.repeat && this.mount?.flies) {
      const now = performance.now();
      if (isDoubleTap(this.lastSpaceMs, now)) {
        this.setFlying(!this.flying);
        this.lastSpaceMs = -1e9;
      } else {
        this.lastSpaceMs = now;
      }
    }
    this.keys.add(event.code);
    // Space and the arrows would scroll the page.
    if (event.code === 'Space' || event.code.startsWith('Arrow')) event.preventDefault();
  }

  private onKeyUp(event: KeyboardEvent): void {
    // Windows hands the page only the key-up of PrintScreen
    if (event.code === 'PrintScreen') this.lastPrintMs = performance.now();
    // Always clear, even from an input: a key held when focus moved must not stick.
    this.keys.delete(event.code);
  }

  private onMouseDown(event: MouseEvent): void {
    if (!this.inputEnabled) return;
    if (this.isPointerLocked()) {
      // Mouse-look on: the buttons are the hands.
      const hand = event.button === 0 ? 'left' : event.button === 2 ? 'right' : null;
      if (!hand) return;
      this.attackHeld[hand] = true;
      this.options.onAttack?.(hand);
      return;
    }
    if (event.button === 2) {
      this.steering = true;
      this.skipNextMouseMove = true;
    }
    if (event.button === 0) {
      this.leftDown = { x: event.clientX, y: event.clientY };
      this.orbiting = false;
    }
    this.cursor = { x: event.clientX - window.innerWidth / 2, y: event.clientY - window.innerHeight / 2 };
  }

  private onMouseUp(event: MouseEvent): void {
    if (event.button === 2) {
      this.steering = false;
      this.attackHeld.right = false;
    }
    if (event.button === 0) {
      this.attackHeld.left = false;
      if (this.orbiting) this.dragEndAt = performance.now();
      this.leftDown = null;
      this.orbiting = false;
    }
  }

  /** True just after a left drag with the cursor free ended: its click isn't a click. */
  wasDrag(): boolean {
    return performance.now() - this.dragEndAt < 300;
  }

  /** True while that hand's button is held with the pointer locked (swing again when ready). */
  isAttackHeld(hand: 'left' | 'right'): boolean {
    return this.attackHeld[hand] && this.isPointerLocked() && this.inputEnabled;
  }

  /** Turn to face where the camera looks for a while (a swing goes where you look). */
  faceCamera(ms: number): void {
    this.faceCameraUntil = Math.max(this.faceCameraUntil, performance.now() + ms);
    // Snap most of the way now, so the swing doesn't start sideways.
    this.character.rotation.y = turnToward(this.character.rotation.y, this.yaw, Math.PI * 0.75);
  }

  /** The camera's yaw (where a swing aims). */
  getYaw(): number {
    return this.yaw;
  }

  /** Mouse-look statistics for the game menu: moves seen, and remote-desktop jumps repaired. */
  mouseStats(): { moves: number; repaired: number; remoteDesktop: boolean } {
    const f = this.mouseFilter;
    return { moves: f.moves, repaired: f.repaired, remoteDesktop: f.remoteDesktop };
  }

  private onPointerMove(event: PointerEvent): void {
    const locked = this.isPointerLocked();
    if (!locked) this.cursor = { x: event.clientX - window.innerWidth / 2, y: event.clientY - window.innerHeight / 2 };
    if (!this.inputEnabled) return;
    if (!locked && this.leftDown && !this.orbiting) {
      // A left drag with the cursor free orbits the camera once it has moved a few pixels.
      if ((event.buttons & 1) === 0) this.leftDown = null;
      else if (Math.hypot(event.clientX - this.leftDown.x, event.clientY - this.leftDown.y) > 4) {
        this.orbiting = true;
        this.skipNextMouseMove = true;
      }
    }
    if (this.orbiting && !locked && (event.buttons & 1) === 0) {
      this.orbiting = false;
      this.leftDown = null;
    }
    if (!locked && !this.steering && !this.orbiting) return;
    // A missed mouseup (released outside the window) must not leave us steering.
    if (this.steering && !locked && (event.buttons & 2) === 0) {
      this.steering = false;
      return;
    }
    for (const move of this.movesIn(event)) {
      if (this.skipNextMouseMove) {
        // The first move after the lock starts or ends, or steering starts, can be a jump.
        this.skipNextMouseMove = false;
        continue;
      }
      let dx = move.movementX || 0;
      let dy = move.movementY || 0;
      if (locked) {
        // Chrome moves a locked cursor back to the middle near the edges: over remote
        // desktop that comes out as jumps, which the filter turns back into the hand's moves.
        const m = this.mouseFilter.filter(dx, dy);
        dx = m.x;
        dy = m.y;
      } else {
        // A free cursor is never moved for us: its moves are real. Skip the odd glitch.
        const lim = jumpLimit(window.innerWidth, window.innerHeight);
        if (Math.abs(dx) > lim.x || Math.abs(dy) > lim.y) continue;
      }
      const look = applyMouseLook(this.yaw, this.lookPitch, dx, dy, this.sensitivity, this.invertY);
      this.yaw = look.yaw;
      this.lookPitch = look.lookPitch;
    }
  }

  // Each mouse report in a pointer event: browsers deliver several at once, merged, once
  // a frame; the separate reports let the filter see each one. If a browser's separate
  // reports don't add up to the merged one, the merged one is used.
  private movesIn(event: PointerEvent): Array<{ movementX: number; movementY: number }> {
    const parts = typeof event.getCoalescedEvents === 'function' ? event.getCoalescedEvents() : [];
    if (parts.length > 1) {
      let x = 0;
      let y = 0;
      for (const p of parts) {
        x += p.movementX || 0;
        y += p.movementY || 0;
      }
      if (Math.abs(x - (event.movementX || 0)) <= 1 && Math.abs(y - (event.movementY || 0)) <= 1) return parts;
    }
    return [event];
  }

  private onWheel(event: WheelEvent): void {
    event.preventDefault();
    // mounted, the camera may pull further back (the dragon is big)
    this.distance = this.mount
      ? Math.min(FLIGHT.maxCameraDistance, Math.max(CAMERA.minDistance * 2, this.distance * Math.exp(event.deltaY * 0.001)))
      : zoomDistance(this.distance, event.deltaY);
  }

  private onClick(event: MouseEvent): void {
    if (event.button !== 0 || this.isPointerLocked()) return;
    // The end of a camera drag isn't a click.
    if (this.wasDrag()) return;
    if (event.target !== this.canvas) return;
    if (this.options.lockOnClick && !this.options.lockOnClick(event)) return;
    this.requestPointerLock();
  }

  private onPointerLockChange(): void {
    const locked = this.isPointerLocked();
    // A lock taken and released at once (a click that opened a window) can deliver both
    // events after the release: each then reads "unlocked". Only a real change counts,
    // or the second one looks like the browser taking the lock (Esc) and opens the menu.
    if (locked === this.wasLocked) return;
    this.wasLocked = locked;
    // The first move after the lock starts or ends can be a jump across the screen.
    this.skipNextMouseMove = true;
    // The locked cursor starts where the free one was.
    this.mouseFilter.reset(locked ? this.cursor : null);
    if (!locked && !this.releasingLock) {
      // We didn't let go: the browser did. On Esc (it keeps that key to itself while locked)
      // that is the menu; but a screenshot tool (Win+Shift+S, PrintScreen) or another window
      // taking focus drops the lock too (2026-10-26: every screenshot opened the menu). Look
      // again a moment later, when the window has lost focus if that is what happened.
      this.clearInput();
      const lostAt = performance.now();
      setTimeout(() => {
        if (this.disposed || this.isPointerLocked()) return;
        const esc = lockLossWasEsc({
          lostAtMs: lostAt,
          nowMs: performance.now(),
          lastAwayMs: this.lastAwayMs,
          lastPrintMs: this.lastPrintMs,
          hidden: document.hidden,
          focused: document.hasFocus(),
        });
        if (esc) this.options.onEscape?.('lock-lost');
      }, LOCK_LOSS_SETTLE_MS);
    }
    this.releasingLock = false;
    this.options.onPointerLockChange?.(locked);
  }

  /** Lock the pointer for free look (call from a click: browsers require a gesture). */
  requestPointerLock(): void {
    if (this.isPointerLocked() || !this.inputEnabled) return;
    if (this.options.canLock && !this.options.canLock()) return;
    try {
      // Chrome returns a promise, and rejects if asked again too soon after Esc.
      const result = this.canvas.requestPointerLock() as unknown as Promise<void> | undefined;
      if (result && typeof result.catch === 'function') {
        result.catch(() => this.options.onPointerLockError?.());
      }
    } catch (_e) {
      // Not available (an iframe without permission): right-drag still works.
      this.options.onPointerLockError?.();
    }
  }

  isPointerLocked(): boolean {
    return document.pointerLockElement === this.canvas;
  }

  /** Give the cursor back (Ctrl, chat, the menu, death). */
  releasePointerLock(): void {
    if (!this.isPointerLocked()) return;
    this.releasingLock = true;
    document.exitPointerLock();
  }

  /** Stop or resume reading movement keys and the mouse (the game menu is open). */
  setInputEnabled(enabled: boolean): void {
    this.inputEnabled = enabled;
    if (!enabled) {
      this.clearInput();
      this.releasePointerLock();
    }
  }

  /** Mouse sensitivity multiplier (SENSITIVITY.min..max) and inverted Y, from the game menu. */
  setMouseSettings(sensitivity: number, invertY: boolean): void {
    this.sensitivity = Math.min(SENSITIVITY.max, Math.max(SENSITIVITY.min, sensitivity));
    this.invertY = invertY;
  }

  private clearInput(): void {
    this.keys.clear();
    this.steering = false;
    this.orbiting = false;
    this.leftDown = null;
    this.attackHeld.left = false;
    this.attackHeld.right = false;
  }

  // ---------------------------------------------------------------------------
  // Per frame
  // ---------------------------------------------------------------------------

  update(deltaTime: number): void {
    // A slow frame (remote desktop, a busy machine) still moves the character its
    // full distance, in steps of at most 50 ms; only a stalled tab (over 0.25 s) is cut short.
    const dt = Math.min(deltaTime, 0.25);
    const p = this.character.position;
    const before = { x: p.x, y: p.y, z: p.z, heading: this.character.rotation.y };

    const steps = Math.max(1, Math.ceil(dt / 0.05));
    for (let i = 0; i < steps; i++) this.updateMovement(dt / steps);
    this.updateCamera(dt);

    const changed = p.x !== before.x || p.y !== before.y || p.z !== before.z || this.character.rotation.y !== before.heading;
    if (this.onPositionUpdate && changed) {
      this.onPositionUpdate(p.x, p.y, p.z, this.character.rotation.y);
    }
  }

  private held(...codes: string[]): boolean {
    return codes.some((c) => this.keys.has(c));
  }

  /** Facing the camera: steering, or just after a swing. */
  private facingCamera(): boolean {
    return this.steering || performance.now() < this.faceCameraUntil;
  }

  private updateMovement(dt: number): void {
    if (this.flying) {
      this.updateFlight(dt);
      return;
    }
    const input = {
      forward: this.held('KeyW', 'ArrowUp'),
      back: this.held('KeyS', 'ArrowDown'),
      left: this.held('KeyA', 'ArrowLeft'),
      right: this.held('KeyD', 'ArrowRight'),
    };
    const dir = moveDirection(input, this.yaw);
    const hasInput = dir.x !== 0 || dir.z !== 0;
    const fwd = (input.forward ? 1 : 0) - (input.back ? 1 : 0);
    const facingCamera = this.facingCamera();

    this.isCrouching = this.held('KeyC') && this.isGrounded && !this.mount;
    this.isSprinting = this.held('ShiftLeft', 'ShiftRight') && !this.isCrouching && !(facingCamera && fwd < 0);
    let maxSpeed = this.isCrouching ? MOVE.crouchSpeed : this.isSprinting ? MOVE.sprintSpeed : MOVE.jogSpeed;
    // A mount runs at its own pace (sprinting half as fast again).
    if (this.mount) maxSpeed = this.mount.groundSpeed * (this.isSprinting ? 1.5 : 1);
    if (facingCamera && fwd < 0) maxSpeed *= BACKPEDAL;

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

    if (facingCamera) {
      // Mouselook: the character faces where the camera looks; A/D strafe, S
      // backpedals. On a diagonal the body turns 45 degrees into it (forward-left
      // faces forward-left; back-left faces forward-right and backpedals).
      const moveYaw = facingYaw(dir);
      const face = !hasInput || fwd === 0 ? this.yaw : fwd > 0 ? moveYaw : moveYaw + Math.PI;
      this.character.rotation.y = turnToward(this.character.rotation.y, face, MOVE.turnRate * 2 * dt);
    } else if (hasInput) {
      // Free look: face the way we move (bOrientRotationToMovement), not the camera.
      this.character.rotation.y = turnToward(this.character.rotation.y, facingYaw(dir), MOVE.turnRate * dt);
    }

    // Jump (grounded only), gravity, and the ground.
    if (this.held('Space') && this.isGrounded) {
      this.verticalSpeed = MOVE.jumpSpeed;
      this.isGrounded = false;
    }
    if (!this.isGrounded) this.verticalSpeed -= MOVE.gravity * dt;

    const pos = this.character.position;
    const fromX = pos.x;
    const fromZ = pos.z;
    pos.x += this.velocity.x * UNITS_PER_METRE * dt;
    pos.z += this.velocity.z * UNITS_PER_METRE * dt;
    pos.y += this.verticalSpeed * UNITS_PER_METRE * dt;

    // Walls, stalls, trees: slide along them. Velocity becomes what we actually
    // covered, so running straight into a wall stops the jog instead of
    // animating on the spot.
    if (this.options.collide && dt > 0) {
      const ok = this.options.collide(pos.x, pos.z, fromX, fromZ);
      if (ok.x !== pos.x || ok.z !== pos.z) {
        pos.x = ok.x;
        pos.z = ok.z;
        const vx = (pos.x - fromX) / UNITS_PER_METRE / dt;
        const vz = (pos.z - fromZ) / UNITS_PER_METRE / dt;
        const moved = Math.hypot(vx, vz);
        const scale = moved > this.speed && moved > 0 ? this.speed / moved : 1;
        this.velocity = { x: vx * scale, z: vz * scale };
        this.speed = Math.hypot(this.velocity.x, this.velocity.z);
      }
    }

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

  // Flying: no gravity; the velocity follows flightTarget(). Touching the ground lands.
  private updateFlight(dt: number): void {
    const m = this.mount!;
    const input = {
      forward: this.held('KeyW', 'ArrowUp'),
      back: this.held('KeyS', 'ArrowDown'),
      left: this.held('KeyA', 'ArrowLeft'),
      right: this.held('KeyD', 'ArrowRight'),
      up: this.held('Space'),
      down: this.held('KeyC'),
      boost: this.held('ShiftLeft', 'ShiftRight'),
    };
    this.isSprinting = input.boost;
    this.isCrouching = false;
    const target = flightTarget(input, this.yaw, this.lookPitch, m.flySpeed);
    this.flyVel = approachVelocity(this.flyVel, target, FLIGHT.response, dt);
    this.velocity = { x: this.flyVel.x, z: this.flyVel.z };
    this.verticalSpeed = this.flyVel.y;
    this.speed = Math.hypot(this.flyVel.x, this.flyVel.z);
    // the mount faces the way it flies (or where the camera looks while hovering)
    const face = this.speed > 1.5 ? Math.atan2(this.flyVel.x, this.flyVel.z) : this.yaw;
    this.character.rotation.y = turnToward(this.character.rotation.y, face, MOVE.turnRate * 0.35 * dt);

    const pos = this.character.position;
    const fromX = pos.x;
    const fromZ = pos.z;
    pos.x += this.flyVel.x * UNITS_PER_METRE * dt;
    pos.z += this.flyVel.z * UNITS_PER_METRE * dt;
    pos.y += this.flyVel.y * UNITS_PER_METRE * dt;
    const ground = this.groundHeight(pos.x, pos.z);
    // near the ground the village's walls still count
    const near = pos.y - ground < 3 * UNITS_PER_METRE;
    const fence = near ? this.options.collide : this.options.bounds;
    if (fence) {
      const ok = fence(pos.x, pos.z, fromX, fromZ);
      pos.x = ok.x;
      pos.z = ok.z;
      if (dt > 0) this.velocity = { x: (pos.x - fromX) / UNITS_PER_METRE / dt, z: (pos.z - fromZ) / UNITS_PER_METRE / dt };
    }
    const top = ground + FLIGHT.maxAltitude * UNITS_PER_METRE;
    if (pos.y > top) {
      pos.y = top;
      this.flyVel.y = Math.min(0, this.flyVel.y);
    }
    if (pos.y <= ground) {
      pos.y = ground;
      // coming down onto the ground lands; skimming it level doesn't
      if (this.flyVel.y < -0.5 || !input.up) {
        this.setFlying(false);
        this.isGrounded = true;
      }
      this.flyVel.y = Math.max(0, this.flyVel.y);
    }
    this.isGrounded = !this.flying;
  }

  private setFlying(on: boolean): void {
    if (on === this.flying) return;
    if (on && !this.mount?.flies) return;
    this.flying = on;
    if (on) {
      this.flyVel = { x: this.velocity.x, y: FLIGHT.takeoffSpeed, z: this.velocity.z };
      this.isGrounded = false;
    } else {
      // keep the momentum: fall the rest of the way (a mount lands softly)
      this.verticalSpeed = Math.min(0, this.flyVel.y);
      this.isGrounded = false;
    }
  }

  /** Climbs on (a mount's speeds; `pivot` its rider's head height, scene units) or off (null). */
  setMount(spec: { groundSpeed: number; flySpeed: number; flies: boolean; pivot: number } | null): void {
    this.mount = spec;
    if (!spec) {
      this.flying = false;
      if (this.footDistance !== null) this.distance = this.footDistance;
      this.footDistance = null;
      this.isGrounded = false;
      return;
    }
    if (this.footDistance === null) this.footDistance = this.distance;
    this.distance = Math.max(this.distance, FLIGHT.cameraDistance);
    this.pivotY = null;
  }

  get isMounted(): boolean {
    return !!this.mount;
  }

  get isFlying(): boolean {
    return this.flying;
  }

  private updateCamera(dt: number): void {
    const height = this.mount ? this.mount.pivot : this.options.characterHeight ?? CHARACTER_HEIGHT_UNITS;
    const feet = this.character.position;
    const targetPivotY = feet.y + height * CAMERA.pivotHeight;
    // Smooth only the pivot's height, to soften jump bobbing; the orbit itself
    // follows the mouse with no lag, as in RaysSpaceSim.
    this.pivotY = this.pivotY === null ? targetPivotY : this.pivotY + (targetPivotY - this.pivotY) * (1 - Math.exp(-dt * 12));
    const pivot = { x: feet.x, y: this.pivotY, z: feet.z };

    const cam = cameraPosition(pivot, this.yaw, this.lookPitch, this.distance * UNITS_PER_METRE);
    const floor = (this.surfaceFn ? this.surfaceFn(cam.x, cam.z) : this.groundHeight(cam.x, cam.z)) + CAMERA.minHeightAboveGround * UNITS_PER_METRE;
    this.camera.position.set(cam.x, Math.max(cam.y, floor), cam.z);
    this.camera.lookAt(pivot.x, pivot.y, pivot.z);
  }

  private groundHeight(x: number, z: number): number {
    if (this.groundFn) return this.groundFn(x, z);
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

  /**
   * The ground from a heightfield (terrain.ts): `ground` under the feet, `surface` (the ground or
   * the water's top) under the camera. Null: back to flat.
   */
  setGround(ground: ((x: number, z: number) => number) | null, surface: ((x: number, z: number) => number) | null = null): void {
    this.groundFn = ground;
    this.surfaceFn = surface;
  }

  setPositionCallback(callback: (x: number, y: number, z: number, rotation: number) => void): void {
    this.onPositionUpdate = callback;
  }

  getMovementState(): MovementState {
    const isMoving = this.speed >= PACE.idleBelow;
    // Velocity in the character's own frame (yaw h faces (sin h, cos h); its right is (-cos h, sin h)).
    const h = this.character.rotation.y;
    let dirX = 0;
    let dirZ = 0;
    if (this.speed > 1e-3) {
      dirZ = (this.velocity.x * Math.sin(h) + this.velocity.z * Math.cos(h)) / this.speed;
      dirX = (-this.velocity.x * Math.cos(h) + this.velocity.z * Math.sin(h)) / this.speed;
    }
    return {
      dirX,
      dirZ,
      isMoving,
      isRunning: isMoving && !this.isCrouching,
      isSprinting: isMoving && this.isGrounded && (this.isSprinting || this.speed > PACE.jogUpTo),
      isGrounded: this.isGrounded,
      isCrouching: this.isCrouching,
      isFlying: this.flying,
      speed: this.speed,
      verticalSpeed: this.verticalSpeed,
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
    this.disposed = true;
    this.releasePointerLock();
    document.removeEventListener('keydown', this.handleKeyDown);
    document.removeEventListener('keyup', this.handleKeyUp);
    document.removeEventListener('visibilitychange', this.handleVisibility);
    document.removeEventListener('pointerlockchange', this.handlePointerLockChange);
    document.removeEventListener('pointerlockerror', this.handlePointerLockError);
    window.removeEventListener('blur', this.handleBlur);
    this.canvas.removeEventListener('mousedown', this.handleMouseDown);
    window.removeEventListener('mouseup', this.handleWindowMouseUp);
    window.removeEventListener('pointermove', this.handlePointerMove);
    this.canvas.removeEventListener('wheel', this.handleWheel);
    this.canvas.removeEventListener('click', this.handleClick);
    this.canvas.removeEventListener('contextmenu', this.handleContextMenu);
    this.clearInput();
  }
}

export default CharacterController;
