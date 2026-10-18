// Simple Full-Screen Galaxy Scene with Drifting Stars
import * as THREE from 'three';
import { CameraController } from './controls/camera-controller';

interface GalaxySceneHook {
  el: HTMLElement;
  scene: THREE.Scene | null;
  camera: THREE.PerspectiveCamera | null;
  renderer: THREE.WebGLRenderer | null;
  stars: THREE.Points | null;
  animationId: number | null;
  time: number;
  cameraController: CameraController | null;
}

export const HomeGalaxyScene = {
  el: null as any,
  scene: null as THREE.Scene | null,
  camera: null as THREE.PerspectiveCamera | null,
  renderer: null as THREE.WebGLRenderer | null,
  stars: null as THREE.Points | null,
  animationId: null as number | null,
  time: 0,
  cameraController: null as CameraController | null,

  mounted(this: GalaxySceneHook) {
    console.log('🌌 Home Galaxy Scene mounting...');
    
    try {
      this.initScene();
      this.createStarField();
      this.startAnimation();
      this.setupResize();
      console.log('✅ Galaxy scene initialized successfully');
    } catch (error) {
      console.error('❌ Failed to initialize galaxy scene:', error);
    }
  },

  initScene(this: GalaxySceneHook) {
    // Create canvas
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

    // Get actual dimensions from the parent container
    const width = this.el.clientWidth || window.innerWidth;
    const height = this.el.clientHeight || window.innerHeight;

    // Scene setup
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x000002); // Very dark space

    // Camera setup
    this.camera = new THREE.PerspectiveCamera(
      75, 
      width / height, 
      0.1, 
      2000
    );
    this.camera.position.set(0, 0, 0);

    // Renderer setup
    this.renderer = new THREE.WebGLRenderer({ 
      canvas, 
      antialias: true,
      alpha: false 
    });
    this.renderer.setSize(width, height, false);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    
    // Don't create our own camera controller - let GlobalCameraController handle it
    // Just notify that a scene has been initialized
    window.dispatchEvent(new CustomEvent('scene-initialized', {
      detail: { scene: this, camera: this.camera, canvas: canvas }
    }));
  },

  createStarField(this: GalaxySceneHook) {
    if (!this.scene) return;

    const starCount = 2000;
    const positions = new Float32Array(starCount * 3);
    const colors = new Float32Array(starCount * 3);
    const sizes = new Float32Array(starCount);

    // Create star positions in a 3D space around the camera
    for (let i = 0; i < starCount; i++) {
      const i3 = i * 3;
      
      // Random positions in a large sphere around the camera
      const radius = 200 + Math.random() * 800;
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos((Math.random() * 2) - 1);
      
      positions[i3] = radius * Math.sin(phi) * Math.cos(theta);
      positions[i3 + 1] = radius * Math.sin(phi) * Math.sin(theta);
      positions[i3 + 2] = radius * Math.cos(phi);

      // Star colors - mix of white, blue, and purple tints
      const colorChoice = Math.random();
      if (colorChoice < 0.7) {
        // White stars
        colors[i3] = 1;
        colors[i3 + 1] = 1;
        colors[i3 + 2] = 1;
      } else if (colorChoice < 0.85) {
        // Blue stars
        colors[i3] = 0.7;
        colors[i3 + 1] = 0.8;
        colors[i3 + 2] = 1;
      } else {
        // Purple stars
        colors[i3] = 1;
        colors[i3 + 1] = 0.7;
        colors[i3 + 2] = 1;
      }

      // Random star sizes
      sizes[i] = Math.random() * 3 + 1;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geometry.setAttribute('size', new THREE.BufferAttribute(sizes, 1));

    // Star material with vertex colors
    const material = new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 }
      },
      vertexShader: `
        attribute float size;
        varying vec3 vColor;
        uniform float time;
        
        void main() {
          vColor = color;
          vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
          
          // Add subtle twinkling by varying size
          float twinkle = sin(time * 2.0 + position.x * 0.01) * 0.3 + 0.7;
          gl_PointSize = size * twinkle * (300.0 / -mvPosition.z);
          gl_Position = projectionMatrix * mvPosition;
        }
      `,
      fragmentShader: `
        varying vec3 vColor;
        
        void main() {
          // Create circular stars
          float dist = distance(gl_PointCoord, vec2(0.5));
          if (dist > 0.5) discard;
          
          float alpha = 1.0 - (dist * 2.0);
          alpha = pow(alpha, 2.0);
          
          gl_FragColor = vec4(vColor, alpha);
        }
      `,
      transparent: true,
      vertexColors: true,
      blending: THREE.AdditiveBlending
    });

    this.stars = new THREE.Points(geometry, material);
    this.scene.add(this.stars);
  },

  startAnimation(this: GalaxySceneHook) {
    const animate = () => {
      this.animationId = requestAnimationFrame(animate);      // Ensure canvas always matches window size
      if (this.renderer) {
        const width = window.innerWidth;
        const height = window.innerHeight;
        const canvas = this.renderer.domElement;
        if (canvas.width !== width || canvas.height !== height) {
          this.renderer.setSize(width, height, false);
          if (this.camera) {
            this.camera.aspect = width / height;
            this.camera.updateProjectionMatrix();
          }
        }
      }

      this.time += 0.01;
      
      if (this.stars && this.stars.material) {
        (this.stars.material as THREE.ShaderMaterial).uniforms.time.value = this.time;
      }

      // Camera controller is now handled globally, no need to update here

      if (this.renderer && this.scene && this.camera) {
        this.renderer.render(this.scene, this.camera);
      }
    };
    
    animate();
  },

  setupResize(this: GalaxySceneHook) {
    const handleResize = () => {
      if (this.camera && this.renderer) {
        const width = window.innerWidth;
        const height = window.innerHeight;
        this.camera.aspect = width / height;
        this.camera.updateProjectionMatrix();
        this.renderer.setSize(width, height, false);
      }
    };

    window.addEventListener('resize', handleResize);
    // Call once to ensure correct size on mount
    handleResize();
  },

  updated(this: GalaxySceneHook) {
    // No updates needed
  },

  destroyed(this: GalaxySceneHook) {
    console.log('🗑️ Galaxy scene cleanup');
    try { console.trace('Galaxy scene destroyed at:'); } catch {
      // Ignore trace errors
    }
    
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    // Camera controller is now managed globally, don't dispose it here

    if (this.stars) {
      this.stars.geometry.dispose();
      (this.stars.material as THREE.Material).dispose();
    }

    if (this.renderer) {
      this.renderer.dispose();
      this.renderer.domElement.remove();
    }

    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.stars = null;
    this.cameraController = null;
  }
};