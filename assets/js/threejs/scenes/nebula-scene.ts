// Nebula Scene - Colorful gas clouds with gentle motion and glow effects
import * as THREE from 'three';
import { CameraController } from '../controls/camera-controller';

interface NebulaSceneHook {
  el: HTMLElement;
  scene: THREE.Scene | null;
  camera: THREE.PerspectiveCamera | null;
  renderer: THREE.WebGLRenderer | null;
  nebulaClouds: THREE.Points[];
  stars: THREE.Points | null;
  animationId: number | null;
  time: number;
  cameraController: CameraController | null;
}

export const NebulaScene = {
  el: null as any,
  scene: null as THREE.Scene | null,
  camera: null as THREE.PerspectiveCamera | null,
  renderer: null as THREE.WebGLRenderer | null,
  nebulaClouds: [] as THREE.Points[],
  stars: null as THREE.Points | null,
  animationId: null as number | null,
  time: 0,
  cameraController: null as CameraController | null,

  mounted(this: NebulaSceneHook) {
    console.log('🌫️ Nebula Scene mounting...');
    
    try {
      this.initScene();
      this.createStarField();
      this.createNebulaClouds();
      this.startAnimation();
      this.setupResize();
      console.log('✅ Nebula scene initialized successfully');
    } catch (error) {
      console.error('❌ Failed to initialize nebula scene:', error);
    }
  },

  initScene(this: NebulaSceneHook) {
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
    this.scene.background = new THREE.Color(0x050010); // Deep purple-black

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

  createStarField(this: NebulaSceneHook) {
    if (!this.scene) return;

    const starCount = 800;
    const positions = new Float32Array(starCount * 3);
    const colors = new Float32Array(starCount * 3);
    const sizes = new Float32Array(starCount);

    for (let i = 0; i < starCount; i++) {
      const i3 = i * 3;
      
      const radius = 300 + Math.random() * 700;
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos((Math.random() * 2) - 1);
      
      positions[i3] = radius * Math.sin(phi) * Math.cos(theta);
      positions[i3 + 1] = radius * Math.sin(phi) * Math.sin(theta);
      positions[i3 + 2] = radius * Math.cos(phi);

      // Dim white/blue stars
      colors[i3] = 0.8 + Math.random() * 0.2;
      colors[i3 + 1] = 0.8 + Math.random() * 0.2;
      colors[i3 + 2] = 0.9 + Math.random() * 0.1;

      sizes[i] = Math.random() * 1.5 + 0.5;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geometry.setAttribute('size', new THREE.BufferAttribute(sizes, 1));

    const material = new THREE.PointsMaterial({
      size: 2,
      vertexColors: true,
      transparent: true,
      opacity: 0.6,
      sizeAttenuation: true,
      blending: THREE.AdditiveBlending,
      depthWrite: false
    });

    this.stars = new THREE.Points(geometry, material);
    this.scene.add(this.stars);
  },

  createNebulaClouds(this: NebulaSceneHook) {
    if (!this.scene) return;

    // Create multiple layers of nebula clouds with different colors
    const cloudLayers = [
      { color: new THREE.Color(0xff1493), count: 400, radius: 500, speed: 0.3 }, // Deep pink
      { color: new THREE.Color(0x9370db), count: 350, radius: 600, speed: 0.2 }, // Purple
      { color: new THREE.Color(0x4169e1), count: 300, radius: 700, speed: 0.25 }, // Royal blue
      { color: new THREE.Color(0xff69b4), count: 250, radius: 550, speed: 0.35 }, // Hot pink
    ];

    cloudLayers.forEach(layer => {
      const positions = new Float32Array(layer.count * 3);
      const colors = new Float32Array(layer.count * 3);
      const sizes = new Float32Array(layer.count);

      for (let i = 0; i < layer.count; i++) {
        const i3 = i * 3;
        
        // Create cloud-like distribution
        const theta = Math.random() * Math.PI * 2;
        const phi = Math.acos((Math.random() * 2) - 1);
        const radius = layer.radius * (0.5 + Math.random() * 0.5);
        
        positions[i3] = radius * Math.sin(phi) * Math.cos(theta);
        positions[i3 + 1] = radius * Math.sin(phi) * Math.sin(theta);
        positions[i3 + 2] = radius * Math.cos(phi);

        // Color with some variation
        const colorVariation = 0.8 + Math.random() * 0.4;
        colors[i3] = layer.color.r * colorVariation;
        colors[i3 + 1] = layer.color.g * colorVariation;
        colors[i3 + 2] = layer.color.b * colorVariation;

        // Larger particles for cloud effect
        sizes[i] = 3 + Math.random() * 8;
      }

      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
      geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
      geometry.setAttribute('size', new THREE.BufferAttribute(sizes, 1));

      const material = new THREE.PointsMaterial({
        size: 15,
        vertexColors: true,
        transparent: true,
        opacity: 0.4,
        sizeAttenuation: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false
      });

      const cloud = new THREE.Points(geometry, material);
      (cloud as any).rotationSpeed = layer.speed;
      this.nebulaClouds.push(cloud);
      this.scene!.add(cloud);
    });
  },

  startAnimation(this: NebulaSceneHook) {
    const animate = () => {
      this.animationId = requestAnimationFrame(animate);
      
      this.time += 0.001;

      if (this.scene && this.camera && this.renderer) {
        // Gentle rotation of nebula clouds
        this.nebulaClouds.forEach((cloud, index) => {
          cloud.rotation.y += (cloud as any).rotationSpeed * 0.0005;
          cloud.rotation.x += (cloud as any).rotationSpeed * 0.0003;
          
          // Subtle pulsing effect
          const scale = 1 + Math.sin(this.time * 2 + index) * 0.05;
          cloud.scale.set(scale, scale, scale);
        });

        // Very slow star rotation
        if (this.stars) {
          this.stars.rotation.y += 0.0001;
        }

        // Camera controller is now handled globally

        this.renderer.render(this.scene, this.camera);
      }
    };

    animate();
  },

  setupResize(this: NebulaSceneHook) {
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

  destroyed(this: NebulaSceneHook) {
    console.log('🗑️ Nebula scene destroyed');
    
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
