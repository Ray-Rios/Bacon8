import * as THREE from 'three';

export class CameraController {
  public camera: THREE.PerspectiveCamera;  // Public so GlobalCameraController can update it
  private renderer: THREE.WebGLRenderer | null = null;
  private element: HTMLElement;
  private controls: any;
  private isMouseDown: boolean = false;
  private lastMouseX: number = 0;
  private lastMouseY: number = 0;
  private mouseSensitivity: number = 0.002;
  private keys: { [key: string]: boolean } = {};
  private moveSpeed: number = 0.1;
  private isEnabled: boolean = true;
  private autoRotate: boolean = false;
  private autoRotateSpeed: number = 0.0005;
  private lastInteractionTime: number = Date.now();

  // bound handlers (so we can remove them later)
  private _onMouseDown: any;
  private _onMouseMove: any;
  private _onMouseUp: any;
  private _onMouseWheel: any;
  private _onKeyDown: any;
  private _onKeyUp: any;

  constructor(camera: THREE.PerspectiveCamera, rendererOrElement?: any, controls?: any) {
    this.camera = camera;
    this.controls = controls;

    // Accept either a WebGLRenderer (with domElement) or a raw HTMLElement (canvas)
    if (rendererOrElement && typeof rendererOrElement === 'object' && 'domElement' in rendererOrElement) {
      this.renderer = rendererOrElement as THREE.WebGLRenderer;
      this.element = (this.renderer as THREE.WebGLRenderer).domElement as HTMLElement;
    } else if (rendererOrElement instanceof HTMLElement) {
      this.element = rendererOrElement;
    } else {
      // Fallback to whole document body: global controls
      this.element = document.body;
    }

    this.initEventListeners();
  }

  private initEventListeners(): void {
    // Bind handlers once so we can remove them later
    this._onMouseDown = this.onMouseDown.bind(this);
    this._onMouseMove = this.onMouseMove.bind(this);
    this._onMouseUp = this.onMouseUp.bind(this);
    this._onMouseWheel = this.onMouseWheel.bind(this);
    this._onKeyDown = this.onKeyDown.bind(this);
    this._onKeyUp = this.onKeyUp.bind(this);

    try {
      // Mouse events
      if (this.element && this.element.addEventListener) {
        this.element.addEventListener('mousedown', this._onMouseDown);
        this.element.addEventListener('mousemove', this._onMouseMove);
        this.element.addEventListener('mouseup', this._onMouseUp);
        this.element.addEventListener('wheel', this._onMouseWheel);
        // Prevent context menu on right-click within the element
        this.element.addEventListener('contextmenu', (e) => e.preventDefault());
      }
    } catch (err) {
      // Defensive: element may be missing in some environments
      console.warn('CameraController: failed to attach element listeners', err);
    }

    // Keyboard events (document-level)
    document.addEventListener('keydown', this._onKeyDown);
    document.addEventListener('keyup', this._onKeyUp);
  }

  private onMouseDown(event: MouseEvent): void {
    if (!this.isEnabled) return;

    // Check if the target is a UI element that should handle its own interactions
    const target = event.target as HTMLElement;
    if (this.shouldIgnoreMouseEvent(target)) {
      return; // Let the UI element handle this event
    }

    this.isMouseDown = true;
    this.lastMouseX = event.clientX;
    this.lastMouseY = event.clientY;
    this.lastInteractionTime = Date.now();

    // Prevent text selection and default behaviors
    event.preventDefault();
  }

  private onMouseMove(event: MouseEvent): void {
    if (!this.isEnabled || !this.isMouseDown) return;

    // Check if we moved over a UI element during drag
    const target = event.target as HTMLElement;
    if (this.shouldIgnoreMouseEvent(target)) {
      // Release mouse capture if we moved over a UI element
      this.isMouseDown = false;
      return;
    }

    const deltaX = event.clientX - this.lastMouseX;
    const deltaY = event.clientY - this.lastMouseY;

    // Rotate camera around Y axis (left/right)
    this.camera.rotation.y -= deltaX * this.mouseSensitivity;

    // Rotate camera around X axis (up/down) with limits
    this.camera.rotation.x -= deltaY * this.mouseSensitivity;
    this.camera.rotation.x = Math.max(-Math.PI / 2, Math.min(Math.PI / 2, this.camera.rotation.x));

    this.lastMouseX = event.clientX;
    this.lastMouseY = event.clientY;
    this.lastInteractionTime = Date.now();
  }

  private onMouseUp(_event: MouseEvent): void {
    this.isMouseDown = false;
  }

  private onMouseWheel(event: WheelEvent): void {
    if (!this.isEnabled) return;

    // Zoom in/out
    const zoomSpeed = 0.1;
    const direction = event.deltaY > 0 ? 1 : -1;
    this.camera.position.z += direction * zoomSpeed;

    // Limit zoom
    this.camera.position.z = Math.max(1, Math.min(10, this.camera.position.z));

    this.lastInteractionTime = Date.now();
    event.preventDefault();
  }

  private onKeyDown(event: KeyboardEvent): void {
    if (!this.isEnabled) return;
    this.keys[event.code] = true;
    this.lastInteractionTime = Date.now();
  }

  private onKeyUp(event: KeyboardEvent): void {
    if (!this.isEnabled) return;
    this.keys[event.code] = false;
  }

  update(_deltaTime?: number): void {
    if (!this.isEnabled) return;

    // Auto-rotate if enabled and no recent interaction (3 seconds)
    const timeSinceInteraction = Date.now() - this.lastInteractionTime;
    if (this.autoRotate && timeSinceInteraction > 3000) {
      this.camera.rotation.y += this.autoRotateSpeed;
    }

    // Handle keyboard movement
    if (this.keys['KeyW'] || this.keys['ArrowUp']) {
      this.camera.position.z -= this.moveSpeed;
      this.lastInteractionTime = Date.now();
    }
    if (this.keys['KeyS'] || this.keys['ArrowDown']) {
      this.camera.position.z += this.moveSpeed;
      this.lastInteractionTime = Date.now();
    }
    if (this.keys['KeyA'] || this.keys['ArrowLeft']) {
      this.camera.position.x -= this.moveSpeed;
      this.lastInteractionTime = Date.now();
    }
    if (this.keys['KeyD'] || this.keys['ArrowRight']) {
      this.camera.position.x += this.moveSpeed;
      this.lastInteractionTime = Date.now();
    }
    if (this.keys['KeyQ']) {
      this.camera.position.y += this.moveSpeed;
      this.lastInteractionTime = Date.now();
    }
    if (this.keys['KeyE']) {
      this.camera.position.y -= this.moveSpeed;
      this.lastInteractionTime = Date.now();
    }
  }

  enable(): void {
    this.isEnabled = true;
  }

  disable(): void {
    this.isEnabled = false;
    this.isMouseDown = false;
    // Clear all keys
    this.keys = {};
  }

  private shouldIgnoreMouseEvent(target: HTMLElement): boolean {
    // Ignore mouse events on interactive UI elements
    const interactiveTags = ['BUTTON', 'INPUT', 'SELECT', 'TEXTAREA', 'A', 'LABEL'];
    const interactiveClasses = ['phx-click', 'phx-submit', 'phx-change', 'phx-value', 'clickable'];
    
    // Check tag name
    if (interactiveTags.includes(target.tagName)) {
      return true;
    }
    
    // Check for Phoenix LiveView attributes
    if (target.hasAttribute('phx-click') || target.hasAttribute('phx-submit') || 
        target.hasAttribute('phx-change') || target.hasAttribute('phx-value')) {
      return true;
    }
    
    // Check for clickable classes
    for (const className of interactiveClasses) {
      if (target.classList.contains(className)) {
        return true;
      }
    }
    
    // Check parent elements (up to 3 levels) for interactive elements
    let parent = target.parentElement;
    let depth = 0;
    while (parent && depth < 3) {
      if (interactiveTags.includes(parent.tagName) || 
          parent.hasAttribute('phx-click') || parent.hasAttribute('phx-submit') || 
          parent.hasAttribute('phx-change') || parent.hasAttribute('phx-value')) {
        return true;
      }
      parent = parent.parentElement;
      depth++;
    }
    
    return false;
  }

  // Exposed API
  public setMoveSpeed(speed: number): void {
    this.moveSpeed = speed;
  }

  public setAutoRotate(enabled: boolean, speed?: number): void {
    this.autoRotate = enabled;
    if (speed !== undefined) {
      this.autoRotateSpeed = speed;
    }
  }

  public getRotationX(): number {
    return this.camera.rotation.x;
  }

  public getRotationY(): number {
    return this.camera.rotation.y;
  }

  dispose(): void {
    // Remove event listeners (use stored bound references)
    try {
      if (this.element && this._onMouseDown) {
        this.element.removeEventListener('mousedown', this._onMouseDown);
      }
      if (this.element && this._onMouseMove) {
        this.element.removeEventListener('mousemove', this._onMouseMove);
      }
      if (this.element && this._onMouseUp) {
        this.element.removeEventListener('mouseup', this._onMouseUp);
      }
      if (this.element && this._onMouseWheel) {
        this.element.removeEventListener('wheel', this._onMouseWheel);
      }
    } catch (err) {
      console.warn('CameraController: failed to remove element listeners', err);
    }

    if (this._onKeyDown) document.removeEventListener('keydown', this._onKeyDown);
    if (this._onKeyUp) document.removeEventListener('keyup', this._onKeyUp);
  }
}
