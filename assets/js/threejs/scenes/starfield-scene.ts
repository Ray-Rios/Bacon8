// Starfield Scene - Classic scrolling stars with hyperspace effect
import * as THREE from 'three';
import { CameraController } from '../controls/camera-controller';

interface StarfieldSceneHook {
  el: HTMLElement;
  scene: THREE.Scene | null;
  camera: THREE.PerspectiveCamera | null;
  renderer: THREE.WebGLRenderer | null;
  stars: THREE.Points | null;
  animationId: number | null;
  time: number;
  cameraController: CameraController | null;
}

export const StarfieldScene = {
  el: null as any,
  scene: null as THREE.Scene | null,
  camera: null as THREE.PerspectiveCamera | null,
  renderer: null as THREE.WebGLRenderer | null,
  stars: null as THREE.Points | null,
  animationId: null as number | null,
  time: 0,
  cameraController: null as CameraController | null,

  mounted(this: StarfieldSceneHook) {
    console.log('⭐ Starfield Scene mounting...');
    
    try {
      this.initScene();
      this.createStarField();
      this.startAnimation();
      this.setupResize();
      console.log('✅ Starfield scene initialized successfully');
    } catch (error) {
      console.error('❌ Failed to initialize starfield scene:', error);
    }
  },

  initScene(this: StarfieldSceneHook) {
    const canvas = document.createElement('canvas');
    canvas.style.cssText = `
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      display: block;
      pointer-events: auto;
    `;
    this.el.appendChild(canvas);

    const width = this.el.clientWidth || window.innerWidth;
    const height = this.el.clientHeight || window.innerHeight;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x000000); // Pure black
    this.scene.fog = new THREE.Fog(0x000000, 100, 1500); // Add depth fog

    this.camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 2000);
    this.camera.position.set(0, 0, 0);

    this.renderer = new THREE.WebGLRenderer({ 
      canvas, 
      antialias: true,
      alpha: false 
    });
    this.renderer.setSize(width, height, false);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    
    // Don't create our own camera controller - let GlobalCameraController handle it
    window.dispatchEvent(new CustomEvent('scene-initialized', {
      detail: { scene: this, camera: this.camera, canvas: canvas }
    }));
  },

  createStarField(this: StarfieldSceneHook) {
    if (!this.scene) return;

    const starCount = 4000;
    const positions = new Float32Array(starCount * 3);
    const colors = new Float32Array(starCount * 3);
    const sizes = new Float32Array(starCount);
    const velocities = new Float32Array(starCount);

    for (let i = 0; i < starCount; i++) {
      const i3 = i * 3;
      
      // Distribute stars in a cone shape ahead of camera
      const spread = 600;
      positions[i3] = (Math.random() - 0.5) * spread;     // X
      positions[i3 + 1] = (Math.random() - 0.5) * spread; // Y
      positions[i3 + 2] = -Math.random() * 1500 - 100;    // Z (in front of camera)

      // White/blue-white stars
      const colorChoice = Math.random();
      if (colorChoice > 0.8) {
        // Blue-white stars (20%)
        colors[i3] = 0.8 + Math.random() * 0.2;
        colors[i3 + 1] = 0.9 + Math.random() * 0.1;
        colors[i3 + 2] = 1.0;
      } else {
        // Pure white stars (80%)
        colors[i3] = 1.0;
        colors[i3 + 1] = 1.0;
        colors[i3 + 2] = 1.0;
      }

      sizes[i] = Math.random() * 2 + 0.5;
      velocities[i] = 2 + Math.random() * 3; // Varying speeds
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geometry.setAttribute('size', new THREE.BufferAttribute(sizes, 1));
    geometry.setAttribute('velocity', new THREE.BufferAttribute(velocities, 1));

    const material = new THREE.PointsMaterial({
      size: 3,
      vertexColors: true,
      transparent: true,
      opacity: 0.9,
      sizeAttenuation: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false
    });

    this.stars = new THREE.Points(geometry, material);
    this.scene.add(this.stars);
  },

  startAnimation(this: StarfieldSceneHook) {
    const animate = () => {
      this.animationId = requestAnimationFrame(animate);
      
      this.time += 0.016; // Assuming ~60fps

      if (this.scene && this.camera && this.renderer && this.stars) {
        const positions = this.stars.geometry.attributes.position.array as Float32Array;
        const velocities = this.stars.geometry.attributes.velocity.array as Float32Array;
        const sizes = this.stars.geometry.attributes.size.array as Float32Array;

        for (let i = 0; i < positions.length / 3; i++) {
          const i3 = i * 3;
          
          // Move stars toward camera (increase Z)
          positions[i3 + 2] += velocities[i];

          // If star passed camera, reset to far distance
          if (positions[i3 + 2] > 100) {
            positions[i3] = (Math.random() - 0.5) * 600;
            positions[i3 + 1] = (Math.random() - 0.5) * 600;
            positions[i3 + 2] = -1500;
            velocities[i] = 2 + Math.random() * 3;
          }

          // Make stars appear larger as they get closer (hyperspace effect)
          const distance = Math.abs(positions[i3 + 2]);
          const sizeFactor = Math.max(1, (1500 - distance) / 1500 * 3);
          sizes[i] = (Math.random() * 2 + 0.5) * sizeFactor;
        }

        this.stars.geometry.attributes.position.needsUpdate = true;
        this.stars.geometry.attributes.size.needsUpdate = true;

        // Camera controller is now handled globally

        this.renderer.render(this.scene, this.camera);
      }
    };

    animate();
  },

  setupResize(this: StarfieldSceneHook) {
    const handleResize = () => {
      if (!this.camera || !this.renderer || !this.el) return;

      const width = this.el.clientWidth || window.innerWidth;
      const height = this.el.clientHeight || window.innerHeight;

      this.camera.aspect = width / height;
      this.camera.updateProjectionMatrix();
      this.renderer.setSize(width, height, false);
    };

    window.addEventListener('resize', handleResize);
  },

  destroyed(this: StarfieldSceneHook) {
    console.log('🗑️ Starfield scene destroyed');
    
    if (this.animationId !== null) {
      cancelAnimationFrame(this.animationId);
    }

    // Camera controller is now managed globally

    if (this.renderer) {
      this.renderer.dispose();
    }

    if (this.scene) {
      this.scene.traverse((object) => {
        if ((object as any).geometry) {
          (object as any).geometry.dispose();
        }
        if ((object as any).material) {
          (object as any).material.dispose();
        }
      });
    }

    this.cameraController = null;
    this.el.innerHTML = '';
  }
};
