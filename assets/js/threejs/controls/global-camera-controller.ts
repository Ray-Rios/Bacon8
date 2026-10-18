// Global Camera Controller Hook for Phoenix LiveView
// Provides camera controls on any page, even without 3D scenes

import * as THREE from 'three';
import { CameraController } from './camera-controller';

export const GlobalCameraController = {
  camera: null as THREE.PerspectiveCamera | null,
  controller: null as CameraController | null,
  activeScene: null as any,
  isLoggedIn: false,
  animationId: null as number | null,
  controlElement: null as HTMLElement | null,
  _isMounted: false,

  mounted(this: any) {
    // Prevent duplicate mounting
    if (this._isMounted) {
      console.log('🎥 Global Camera Controller already mounted, skipping');
      return;
    }
    this._isMounted = true;
    
    console.log('🎥 Global Camera Controller mounted');

    // Check if user is logged in by looking for user data
    const bodyElement = document.getElementById('global-glass-theme');
    this.isLoggedIn = bodyElement?.dataset?.user !== undefined;

    // Prepare a camera now; we'll bind the controller to the proper element (scene canvas or control layer)
    this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 2000);
    this.camera.position.set(0, 0, 0);

    // Always create global camera controls for the entire site
    this.controller = new CameraController(this.camera); // No element = document.body with smart event handling
    
    // Enable auto-rotation for a nice idle effect (rotates after 3 seconds of no interaction)
    this.controller.setAutoRotate(true, 0.0005);
    
    console.log('🎮 Global camera controls enabled for entire site with auto-rotation');

    // If there's also a specific control layer (for gradient/solid backgrounds), we can use that too
    const controlLayer = document.getElementById('camera-control-canvas');
    if (controlLayer) {
      // For now, keep the global controls as primary
      console.log('📍 Found additional control layer, but using global controls');
    }

    // Start animation loop for camera updates (runs even if controller not yet attached)
    this.startAnimationLoop();

    // Listen for scene initialization to take control of their cameras
    this._sceneInitHandler = (event: any) => {
      if (event.detail && event.detail.scene && event.detail.camera) {
        console.log('🎬 Scene initialized, updating camera reference');
        this.activeScene = event.detail.scene;
        
        // Update the camera reference in the existing controller
        // IMPORTANT: Keep the controller attached to document.body so it receives
        // mouse events even when clicking over UI elements on top of the canvas
        if (this.controller) {
          // Update the camera that the controller manipulates
          this.controller.camera = event.detail.camera;
          console.log('🔄 Updated controller camera reference to scene camera');
        } else {
          // If no controller exists (shouldn't happen), create one on document.body
          this.camera = event.detail.camera;
          this.controller = new CameraController(this.camera); // document.body
          this.controller.setAutoRotate(true, 0.0005);
          console.log('🎮 Camera controller created for 3D scene with auto-rotation');
        }
        
        // Also store the camera reference
        this.camera = event.detail.camera;

        // Enable camera controls for all users on all pages with 3D scenes
        console.log('✅ Camera controls active for 3D scene');
      }
    };
    window.addEventListener('scene-initialized', this._sceneInitHandler);
    
    // Check if a scene has already been initialized before this hook mounted
    this.checkForExistingScene();

    // Listen for camera state requests from other components
    this._cameraStateHandler = (event: any) => {
      if (event.detail && typeof event.detail.callback === 'function') {
        event.detail.callback({
          position: this.camera.position.clone(),
          rotation: {
            x: this.controller ? this.controller.getRotationX() : 0,
            y: this.controller ? this.controller.getRotationY() : 0
          }
        });
      }
    };
    window.addEventListener('request-camera-state', this._cameraStateHandler);

    console.log('✅ Global camera controller initialized');
  },

  updated(this: any) {
    // No action needed on update since we use phx-update="ignore"
    console.log('🔄 Global Camera Controller updated (no action needed)');
  },

  checkForExistingScene(this: any) {
    // Look for an already-initialized scene (in case scene mounted before this controller)
    const canvas = document.getElementById('global-background-canvas');
    if (canvas && (canvas as any)._threeJSHook) {
      const hook = (canvas as any)._threeJSHook;
      if (hook.camera) {
        console.log('🔍 Found existing scene, updating camera reference');
        this.activeScene = hook;
        this.camera = hook.camera;
        if (this.controller) {
          this.controller.camera = hook.camera;
        }
      }
    }
  },

  createGlobalControlLayer(this: any) {
    // Create a full-screen overlay for camera controls when no 3D scene exists
    const controlLayer = document.createElement('div');
    controlLayer.id = 'global-camera-control-layer';
    controlLayer.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      z-index: 0;
      pointer-events: auto;
      cursor: grab;
    `;
    controlLayer.style.cursor = 'grab';
    
    document.body.appendChild(controlLayer);
    this.controlElement = controlLayer;
    this.controller = new CameraController(this.camera, this.controlElement);
    
    console.log('🎮 Global camera control layer created for entire page');
  },

  startAnimationLoop(this: any) {
    const animate = () => {
      this.animationId = requestAnimationFrame(animate);
      
      if (this.controller) {
        this.controller.update();
      }
    };
    animate();
  },

  destroyed(this: any) {
    console.log('🗑️ Global Camera Controller destroyed');
    
    this._isMounted = false;
    
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }
    
    if (this.controller && typeof this.controller.dispose === 'function') {
      this.controller.dispose();
      this.controller = null;
    }
    
    // Remove window event listeners
    if (this._sceneInitHandler) {
      window.removeEventListener('scene-initialized', this._sceneInitHandler);
      this._sceneInitHandler = null;
    }
    if (this._cameraStateHandler) {
      window.removeEventListener('request-camera-state', this._cameraStateHandler);
      this._cameraStateHandler = null;
    }
  }
};