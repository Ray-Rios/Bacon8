// Third-Person Character Controller
import * as THREE from '../../../../assets/js/vendor/three';

export interface ControllerConfig {
  moveSpeed: number;
  runSpeed: number;
  turnSpeed: number;
  jumpForce: number;
  gravity: number;
  cameraDistance: number;
  cameraHeight: number;
  cameraSmoothing: number;
  // When true, disables gravity and enables 3D flight controls
  flyMode: boolean;
}

export class CharacterController {
  private character: THREE.Object3D;
  private camera: THREE.Camera;
  private terrain: THREE.Mesh | null = null;
  
  // Movement state
  private velocity: THREE.Vector3 = new THREE.Vector3();
  private isGrounded: boolean = true;
  private isMoving: boolean = false;
  private isRunning: boolean = false;
  private isCrouching: boolean = false;
  
  // Camera state
  private cameraAngle: number = 0;
  private cameraPitch: number = 0.3;
  private cameraTarget: THREE.Vector3 = new THREE.Vector3();
  
  // Input state
  private keys: { [key: string]: boolean } = {};
  private mouseButtons: { [key: number]: boolean } = {};
  private mouseDelta: { x: number; y: number } = { x: 0, y: 0 };
  
  // Config
  private config: ControllerConfig;
  
  // Callbacks
  private onPositionUpdate?: (x: number, y: number, z: number, rotation: number) => void;

  constructor(
    character: THREE.Object3D,
    camera: THREE.Camera,
    config: Partial<ControllerConfig> = {}
  ) {
    this.character = character;
    this.camera = camera;
    
    this.config = {
      moveSpeed: config.moveSpeed || 5.0,
      runSpeed: config.runSpeed || 10.0,
      turnSpeed: config.turnSpeed || 2.0,
      jumpForce: config.jumpForce || 8.0,
      gravity: config.gravity || 20.0,
      cameraDistance: config.cameraDistance || 10,
      cameraHeight: config.cameraHeight || 3,
      cameraSmoothing: config.cameraSmoothing || 0.1,
      flyMode: config.flyMode ?? false
    };

    this.setupEventListeners();
  }

  private setupEventListeners(): void {
    // Keyboard
    document.addEventListener('keydown', this.onKeyDown.bind(this));
    document.addEventListener('keyup', this.onKeyUp.bind(this));
    
    // Mouse
    document.addEventListener('mousedown', this.onMouseDown.bind(this));
    document.addEventListener('mouseup', this.onMouseUp.bind(this));
    document.addEventListener('mousemove', this.onMouseMove.bind(this));
    
    // Context menu disable (for right-click)
    document.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  private onKeyDown(event: KeyboardEvent): void {
    const target = event.target as HTMLElement | null;
    if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return;
    this.keys[event.code] = true;
  }

  private onKeyUp(event: KeyboardEvent): void {
    // Always clear on keyup to prevent stuck-key issues when focus changes mid-press
    this.keys[event.code] = false;
  }

  private onMouseDown(event: MouseEvent): void {
    this.mouseButtons[event.button] = true;
  }

  private onMouseUp(event: MouseEvent): void {
    this.mouseButtons[event.button] = false;
    this.mouseDelta = { x: 0, y: 0 };
  }

  private onMouseMove(event: MouseEvent): void {
    if (this.mouseButtons[2]) { // Right mouse button
      this.mouseDelta.x += event.movementX;
      this.mouseDelta.y += event.movementY;
    }
  }

  /**
   * Instantly teleport the character and snap the camera to the new position,
   * bypassing the smooth lerp. Call this for respawn / server corrections.
   */
  teleportTo(x: number, y: number, z: number, heading: number = 0): void {
    this.character.position.set(x, y, z);
    this.character.rotation.y = heading;
    this.velocity.set(0, 0, 0);

    // Calculate the camera target at this position and snap to it immediately
    const charRot = heading + this.cameraAngle;
    const offsetX = Math.sin(charRot) * this.config.cameraDistance;
    const offsetZ = Math.cos(charRot) * this.config.cameraDistance;
    const offsetY = this.config.cameraHeight + Math.sin(this.cameraPitch) * this.config.cameraDistance;
    this.camera.position.set(x + offsetX, y + offsetY, z + offsetZ);
    this.cameraTarget.set(x, y + this.config.cameraHeight / 2, z);
    this.camera.lookAt(this.cameraTarget);
  }

  /**
   * Update character and camera every frame
   */
  update(deltaTime: number): void {
    this.handleMovement(deltaTime);
    this.handleCamera(deltaTime);
    if (!this.config.flyMode) {
      this.handleGravity(deltaTime);
    }
    
    // Notify position updates (throttled)
    if (this.onPositionUpdate && this.isMoving) {
      this.onPositionUpdate(
        this.character.position.x,
        this.character.position.y,
        this.character.position.z,
        this.character.rotation.y
      );
    }
  }

  private handleMovement(deltaTime: number): void {
    const forward = this.keys['KeyW'] || false;
    const backward = this.keys['KeyS'] || false;
    const left = this.keys['KeyA'] || false;
    const right = this.keys['KeyD'] || false;
  const jump = this.keys['Space'] || false;
  const descend = this.keys['ControlLeft'] || this.keys['ShiftRight'] || false;
    const run = this.keys['ShiftLeft'] || false;
    const crouch = this.keys['KeyC'] || false;
    
    this.isRunning = run;
    this.isCrouching = crouch;
    
    const speed = this.isRunning ? this.config.runSpeed : this.config.moveSpeed;
  const rightMouseHeld = this.mouseButtons[2] || false;
    
    const movement = new THREE.Vector3();
    this.isMoving = false;
    
    // Classic MMO controls:
    // - W/S: Move forward/backward
    // - A/D alone: Turn left/right
    // - Right-click + A/D: Strafe left/right
    // - Right-click + drag: Rotate camera
    
    if (forward) {
      movement.z += 1;
      this.isMoving = true;
    }
    if (backward) {
      movement.z -= 1;
      this.isMoving = true;
    }
    
    // Strafing (only with right-click)
    if (rightMouseHeld) {
      if (left) {
        movement.x -= 1;
        this.isMoving = true;
      }
      if (right) {
        movement.x += 1;
        this.isMoving = true;
      }
    } else {
      // Turning in place (without right-click)
      if (left) {
        this.character.rotation.y += this.config.turnSpeed * deltaTime;
      }
      if (right) {
        this.character.rotation.y -= this.config.turnSpeed * deltaTime;
      }
    }
    
    // Normalize diagonal movement
    if (movement.length() > 0) {
      movement.normalize();
    }
    
    // Apply character rotation to movement
    const characterRotation = new THREE.Matrix4();
    characterRotation.makeRotationY(this.character.rotation.y);
    movement.applyMatrix4(characterRotation);
    
    if (this.config.flyMode) {
      // In fly mode, add vertical control and ignore ground constraints
      if (jump) {
        movement.y += 1;
        this.isMoving = true;
      }
      if (descend) {
        movement.y -= 1;
        this.isMoving = true;
      }
      if (movement.length() > 0) movement.normalize();
      this.character.position.addScaledVector(movement, speed * deltaTime);
      this.isGrounded = false;
      this.velocity.set(0, 0, 0);
    } else {
      // Apply movement on XZ plane
      this.character.position.x += movement.x * speed * deltaTime;
      this.character.position.z += movement.z * speed * deltaTime;
      
      // Jumping (grounded only)
      if (jump && this.isGrounded) {
        this.velocity.y = this.config.jumpForce;
        this.isGrounded = false;
      }
    }
  }

  private handleCamera(_deltaTime: number): void {
    // Camera rotation with right mouse button
    if (this.mouseButtons[2]) {
      this.cameraAngle -= this.mouseDelta.x * 0.003;
      this.cameraPitch -= this.mouseDelta.y * 0.003;
      
      // Clamp pitch
      this.cameraPitch = Math.max(-Math.PI / 3, Math.min(Math.PI / 3, this.cameraPitch));
      
      this.mouseDelta = { x: 0, y: 0 };
    }
    
    // Calculate camera position (third-person behind character)
    const characterRotation = this.character.rotation.y + this.cameraAngle;
    
    const offsetX = Math.sin(characterRotation) * this.config.cameraDistance;
    const offsetZ = Math.cos(characterRotation) * this.config.cameraDistance;
    const offsetY = this.config.flyMode
      ? Math.sin(this.cameraPitch) * this.config.cameraDistance
      : this.config.cameraHeight + Math.sin(this.cameraPitch) * this.config.cameraDistance;
    
    const targetCameraPos = new THREE.Vector3(
      this.character.position.x + offsetX,
      this.character.position.y + offsetY,
      this.character.position.z + offsetZ
    );
    
    // Smooth camera movement
    this.camera.position.lerp(targetCameraPos, this.config.cameraSmoothing);
    
    // Look at character
    this.cameraTarget.copy(this.character.position);
    this.cameraTarget.y += this.config.flyMode ? 0 : this.config.cameraHeight / 2;
    this.camera.lookAt(this.cameraTarget);
  }

  private handleGravity(deltaTime: number): void {
    if (!this.isGrounded) {
      this.velocity.y -= this.config.gravity * deltaTime;
    }
    
    this.character.position.y += this.velocity.y * deltaTime;
    
    // Ground collision
    const groundHeight = this.getGroundHeight(
      this.character.position.x,
      this.character.position.z
    );
    
    if (this.character.position.y <= groundHeight) {
      this.character.position.y = groundHeight;
      this.velocity.y = 0;
      this.isGrounded = true;
    }
  }

  private getGroundHeight(x: number, z: number): number {
    if (this.config.flyMode) return this.character.position.y; // no ground snap in fly mode
    if (!this.terrain) {
      return 0;
    }
    
    // Raycast down from character position
    const raycaster = new THREE.Raycaster();
    const origin = new THREE.Vector3(x, 1000, z);
    const direction = new THREE.Vector3(0, -1, 0);
    
    raycaster.set(origin, direction);
    const intersects = raycaster.intersectObject(this.terrain, false);
    
    if (intersects.length > 0) {
      return intersects[0].point.y;
    }
    
    return 0;
  }

  /**
   * Set terrain for collision detection
   */
  setTerrain(terrain: THREE.Mesh): void {
    this.terrain = terrain;
  }

  /**
   * Set position update callback for server sync
   */
  setPositionCallback(callback: (x: number, y: number, z: number, rotation: number) => void): void {
    this.onPositionUpdate = callback;
  }

  /**
   * Movement state snapshot for animation/state sync.
   */
  getMovementState(): { isMoving: boolean; isRunning: boolean; isGrounded: boolean; isCrouching: boolean } {
    return {
      isMoving: this.isMoving,
      isRunning: this.isRunning,
      isGrounded: this.isGrounded,
      isCrouching: this.isCrouching
    };
  }

  /**
   * Get current position for /loc command
   */
  getPosition(): { x: number; y: number; z: number } {
    return {
      x: Math.round(this.character.position.x * 10) / 10,
      y: Math.round(this.character.position.y * 10) / 10,
      z: Math.round(this.character.position.z * 10) / 10
    };
  }

  /**
   * Warp to position (/warp command)
   */
  warpTo(x: number, y: number, z: number): void {
    this.character.position.set(x, y, z);
    this.velocity.set(0, 0, 0);
    this.isGrounded = false;
    console.log(`📍 Warped to: ${x}, ${y}, ${z}`);
  }

  /**
   * Cleanup
   */
  dispose(): void {
    document.removeEventListener('keydown', this.onKeyDown.bind(this));
    document.removeEventListener('keyup', this.onKeyUp.bind(this));
    document.removeEventListener('mousedown', this.onMouseDown.bind(this));
    document.removeEventListener('mouseup', this.onMouseUp.bind(this));
    document.removeEventListener('mousemove', this.onMouseMove.bind(this));
  }
}

export default CharacterController;
