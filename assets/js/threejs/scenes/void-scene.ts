// Void Scene - Minimal dark space with subtle static stars
import * as THREE from 'three';
import { CameraController } from '../controls/camera-controller';

interface VoidSceneHook {
  el: HTMLElement;
  scene: THREE.Scene | null;
  camera: THREE.PerspectiveCamera | null;
  renderer: THREE.WebGLRenderer | null;
  stars: THREE.Points | null;
  animationId: number | null;
  time: number;
  cameraController: CameraController | null;
}

export const VoidScene = {
  el: null as any,
  scene: null as THREE.Scene | null,
  camera: null as THREE.PerspectiveCamera | null,
  renderer: null as THREE.WebGLRenderer | null,
  stars: null as THREE.Points | null,
  animationId: null as number | null,
  time: 0,
  cameraController: null as CameraController | null,

  mounted(this: VoidSceneHook) {
    console.log('🌑 Void Scene mounting...');
    
    try {
      this.initScene();
      this.createStarField();
      this.startAnimation();
      this.setupResize();
      console.log('✅ Void scene initialized successfully');
    } catch (error) {
      console.error('❌ Failed to initialize void scene:', error);
    }
  },

  initScene(this: VoidSceneHook) {
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
    this.scene.background = new THREE.Color(0x000000); // Pure black void

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

  createStarField(this: VoidSceneHook) {
    if (!this.scene) return;

    // Very few stars for minimal aesthetic
    const starCount = 150;
    const positions = new Float32Array(starCount * 3);
    const colors = new Float32Array(starCount * 3);
    const sizes = new Float32Array(starCount);

    for (let i = 0; i < starCount; i++) {
      const i3 = i * 3;
      
      // Distant, evenly spaced stars
      const radius = 500 + Math.random() * 500;
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos((Math.random() * 2) - 1);
      
      positions[i3] = radius * Math.sin(phi) * Math.cos(theta);
      positions[i3 + 1] = radius * Math.sin(phi) * Math.sin(theta);
      positions[i3 + 2] = radius * Math.cos(phi);

      // Dim white stars only, no colors
      const brightness = 0.4 + Math.random() * 0.3; // Very dim
      colors[i3] = brightness;
      colors[i3 + 1] = brightness;
      colors[i3 + 2] = brightness;

      sizes[i] = Math.random() * 0.8 + 0.3; // Small stars
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geometry.setAttribute('size', new THREE.BufferAttribute(sizes, 1));

    const material = new THREE.PointsMaterial({
      size: 1.5,
      vertexColors: true,
      transparent: true,
      opacity: 0.5, // Very subtle
      sizeAttenuation: true,
      blending: THREE.NormalBlending, // No additive, just normal blend
      depthWrite: false
    });

    this.stars = new THREE.Points(geometry, material);
    this.scene.add(this.stars);
  },

  startAnimation(this: VoidSceneHook) {
    const animate = () => {
      this.animationId = requestAnimationFrame(animate);
      
      this.time += 0.0005; // Very slow time progression

      if (this.scene && this.camera && this.renderer && this.stars) {
        // Extremely slow rotation - almost imperceptible
        this.stars.rotation.y += 0.00005;
        this.stars.rotation.x += 0.00003;

        // Subtle twinkling effect
        const sizes = this.stars.geometry.attributes.size.array as Float32Array;
        for (let i = 0; i < sizes.length; i++) {
          // Only occasionally twinkle a star
          if (Math.random() > 0.995) {
            const baseSize = 0.3 + Math.random() * 0.8;
            sizes[i] = baseSize * (0.8 + Math.random() * 0.4);
          }
        }
        this.stars.geometry.attributes.size.needsUpdate = true;

        // Camera controller is now handled globally

        this.renderer.render(this.scene, this.camera);
      }
    };

    animate();
  },

  setupResize(this: VoidSceneHook) {
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

  destroyed(this: VoidSceneHook) {
    console.log('🗑️ Void scene destroyed');
    
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
