export const BackgroundUpdater = {
  mounted(this: any) {
    console.log('BackgroundUpdater hook mounted');

    // Listen for background updates from LiveView
    const handleBackgroundUpdate = (data: any) => {
      console.log('Updating background:', data);
      this.updateBackground(data);

      // If this is a global update, dispatch a window event for all components
      if (data.global) {
        window.dispatchEvent(new CustomEvent('background-update', { detail: data }));
      }
    };

    this.handleEvent("update_background", handleBackgroundUpdate);
    this.handleEvent("background_update", handleBackgroundUpdate);

    // Listen for global background updates from other components
    window.addEventListener('background-update', (event: any) => {
      this.updateBackground(event.detail);
    });
  },

  updateBackground(data: any) {
    const backgroundType = data.background;
    const customData = data.custom_data || {};

    console.log('🖼️ Updating background:', { type: backgroundType, customData });

    // Find the global background canvas
    const canvas = document.getElementById('global-background-canvas');
    if (!canvas) {
      console.warn('⚠️ Global background canvas not found');
      return;
    }

    // Clean up any existing 3D scene
    this.cleanup3DScene(canvas);

    if (backgroundType === 'gradient') {
      // Apply gradient background
      const startColor = customData.gradient_start || '#3B82F6';
      const endColor = customData.gradient_end || '#9333EA';
      const gradient = `linear-gradient(135deg, ${startColor}, ${endColor})`;
      canvas.style.background = gradient;
      canvas.removeAttribute('data-static-scene');
      canvas.setAttribute('data-bg-type', 'gradient');
      canvas.style.pointerEvents = 'none';
      
      // Force reflow
      void canvas.offsetHeight;
      
      this.ensureCameraControlCanvas();
      console.log('✅ Gradient applied:', { startColor, endColor });

    } else if (backgroundType === 'solid') {
      // Apply solid color background
      const color = customData.solid_color || '#0F172A';
      canvas.style.background = color;
      canvas.removeAttribute('data-static-scene');
      canvas.setAttribute('data-bg-type', 'solid');
      canvas.style.pointerEvents = 'none';
      
      // Force reflow
      void canvas.offsetHeight;
      
      this.ensureCameraControlCanvas();
      console.log('✅ Solid color applied:', color);

    } else {
      // Apply 3D scene background
      const hookName = this.getHookName(backgroundType);
      canvas.setAttribute('data-static-scene', hookName);
      canvas.style.background = ''; // Clear any CSS background
      canvas.setAttribute('data-bg-type', '3d');
      canvas.style.pointerEvents = 'auto';
      
      this.removeCameraControlCanvas();
      this.initialize3DScene(canvas, hookName);
      console.log('✅ 3D scene applied:', hookName);
    }
  },

  cleanup3DScene(canvas: HTMLElement) {
    // Clean up any existing Three.js scene
    if ((canvas as any)._threeJSHook) {
      const hook = (canvas as any)._threeJSHook;
      console.log('🧹 Cleaning up 3D scene:', (canvas as any)._currentSceneName);
      
      if (typeof hook.destroyed === 'function') {
        try {
          hook.destroyed.call(hook);
        } catch (e) {
          console.error('Error destroying scene:', e);
        }
      }
      (canvas as any)._threeJSHook = null;
      (canvas as any)._currentSceneName = null;
    }
  },

  ensureCameraControlCanvas() {
    let cameraCanvas = document.getElementById('camera-control-canvas');
    if (!cameraCanvas) {
      cameraCanvas = document.createElement('div');
      cameraCanvas.id = 'camera-control-canvas';
      cameraCanvas.setAttribute('data-static-scene', 'HomeGalaxyScene');
      cameraCanvas.className = 'fixed inset-0 z-0 pointer-events-auto opacity-0';
      document.body.appendChild(cameraCanvas);
    }
  },

  removeCameraControlCanvas() {
    const cameraCanvas = document.getElementById('camera-control-canvas');
    if (cameraCanvas) {
      cameraCanvas.remove();
    }
  },

  getHookName(backgroundType: string): string {
    switch (backgroundType) {
      case 'galaxy': return 'HomeGalaxyScene';
      case 'nebula': return 'NebulaScene';
      case 'starfield': return 'StarfieldScene';
      case 'void': return 'VoidScene';
      default: return 'HomeGalaxyScene';
    }
  },

  initialize3DScene(canvas: HTMLElement, hookName: string) {
    // This will trigger the static scene initializer in app.ts
    // The scene will be mounted automatically by the existing system
    console.log('Initializing 3D scene:', hookName);
  }
};