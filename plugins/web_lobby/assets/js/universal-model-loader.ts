// Universal Model Loader for GLTF and FBX with fallbacks
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, FBXLoader } from '../../../../assets/js/vendor/three-loaders';

export interface ModelInfo {
  name: string;
  path: string;
  format: 'gltf' | 'fbx' | 'glb';
  scale?: number;
  position?: THREE.Vector3;
  rotation?: THREE.Euler;
}

export interface LoadedModelAsset {
  model: THREE.Object3D;
  animations: THREE.AnimationClip[];
  mixer?: THREE.AnimationMixer;
  format: string;
}

export class UniversalModelLoader {
  private gltfLoader: GLTFLoader;
  private fbxLoader: FBXLoader;
  private loadedAssets: Map<string, LoadedModelAsset> = new Map();
  private loadingPromises: Map<string, Promise<LoadedModelAsset>> = new Map();

  constructor() {
    this.gltfLoader = new GLTFLoader();
    this.fbxLoader = new FBXLoader();
    console.log('📦 Universal Model Loader initialized');
  }

  /**
   * Load a model automatically detecting format
   */
  async loadModel(path: string): Promise<LoadedModelAsset> {
    // Check cache
    if (this.loadedAssets.has(path)) {
      console.log(`✅ Returning cached model: ${path}`);
      return this.loadedAssets.get(path)!;
    }

    // Check if already loading
    if (this.loadingPromises.has(path)) {
      console.log(`⏳ Waiting for model already loading: ${path}`);
      return this.loadingPromises.get(path)!;
    }

    // Detect format from extension
    const format = this.detectFormat(path);
    
    console.log(`🔄 Loading ${format.toUpperCase()} model: ${path}`);

    let loadPromise: Promise<LoadedModelAsset>;

    switch (format) {
      case 'gltf':
      case 'glb':
        loadPromise = this.loadGLTF(path);
        break;
      case 'fbx':
        loadPromise = this.loadFBX(path);
        break;
      default:
        loadPromise = Promise.reject(new Error(`Unsupported format: ${format}`));
    }

    // Store loading promise
    this.loadingPromises.set(path, loadPromise);

    try {
      const asset = await loadPromise;
      this.loadedAssets.set(path, asset);
      this.loadingPromises.delete(path);
      console.log(`✅ Successfully loaded model: ${path}`);
      return asset;
    } catch (error) {
      this.loadingPromises.delete(path);
      console.error(`❌ Failed to load model ${path}:`, error);
      
      // Try fallback to simple cube
      return this.createFallbackModel(path);
    }
  }

  /**
   * Load GLTF/GLB model
   */
  private async loadGLTF(path: string): Promise<LoadedModelAsset> {
    return new Promise((resolve, reject) => {
      this.gltfLoader.load(
        path,
        (gltf) => {
          const model = gltf.scene;
          const animations = this.normalizeAnimationClips(gltf.animations || []);
          this.standardizeModelForMMO(model);

          resolve({
            model,
            animations,
            format: 'gltf'
          });
        },
        (progress) => {
          const percent = (progress.loaded / progress.total) * 100;
          console.log(`Loading GLTF: ${Math.round(percent)}%`);
        },
        (error) => {
          reject(error);
        }
      );
    });
  }

  /**
   * Load FBX model
   */
  private async loadFBX(path: string): Promise<LoadedModelAsset> {
    return new Promise((resolve, reject) => {
      this.fbxLoader.load(
        path,
        (fbx) => {
          const model = fbx;
          const animations = this.normalizeAnimationClips(fbx.animations || []);
          this.standardizeModelForMMO(model);

          resolve({
            model,
            animations,
            format: 'fbx'
          });
        },
        (progress) => {
          const percent = (progress.loaded / progress.total) * 100;
          console.log(`Loading FBX: ${Math.round(percent)}%`);
        },
        (error) => {
          reject(error);
        }
      );
    });
  }

  /**
   * Create fallback model when loading fails
   */
  private createFallbackModel(originalPath: string): LoadedModelAsset {
    console.warn(`⚠️ Creating fallback cube for: ${originalPath}`);
    
    const geometry = new THREE.BoxGeometry(1, 2, 1);
    const material = new THREE.MeshStandardMaterial({ 
      color: 0x888888,
      roughness: 0.7,
      metalness: 0.3
    });
    const mesh = new THREE.Mesh(geometry, material);
    mesh.castShadow = true;
    mesh.receiveShadow = true;

    return {
      model: mesh,
      animations: [],
      format: 'fallback'
    };
  }

  private standardizeModelForMMO(model: THREE.Object3D): void {
    model.traverse((child) => {
      if (!(child as THREE.Mesh).isMesh) return;

      const mesh = child as THREE.Mesh;
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      mesh.frustumCulled = true;

      const normalizeMaterial = (mat: THREE.Material) => {
        const material = mat as THREE.MeshStandardMaterial;
        if ((material as any).map) {
          const tex = (material as any).map as THREE.Texture;
          tex.colorSpace = THREE.SRGBColorSpace;
          tex.needsUpdate = true;
        }

        if (material.transparent && material.side === THREE.FrontSide) {
          material.side = THREE.DoubleSide;
        }

        material.needsUpdate = true;
      };

      if (Array.isArray(mesh.material)) {
        mesh.material.forEach((mat) => normalizeMaterial(mat));
      } else if (mesh.material) {
        normalizeMaterial(mesh.material);
      }
    });
  }

  private normalizeAnimationClips(clips: THREE.AnimationClip[]): THREE.AnimationClip[] {
    return clips
      .filter((clip) => clip && clip.tracks && clip.tracks.length > 0)
      .map((clip, index) => {
        if (!clip.name || clip.name.trim() === '') {
          clip.name = `clip_${index}`;
        }
        return clip;
      });
  }

  /**
   * Detect model format from file extension
   */
  private detectFormat(path: string): 'gltf' | 'fbx' | 'glb' | 'unknown' {
    const ext = path.toLowerCase().split('.').pop();
    
    switch (ext) {
      case 'gltf':
        return 'gltf';
      case 'glb':
        return 'glb';
      case 'fbx':
        return 'fbx';
      default:
        return 'unknown';
    }
  }

  /**
   * Load all models from a directory (attempts both GLTF and FBX)
   */
  async loadFromDirectory(
    basePath: string, 
    modelNames: string[]
  ): Promise<Map<string, LoadedModelAsset>> {
    const results = new Map<string, LoadedModelAsset>();
    
    for (const name of modelNames) {
      // Try GLTF first, then FBX
      const paths = [
        `${basePath}/${name}.gltf`,
        `${basePath}/${name}.glb`,
        `${basePath}/${name}.fbx`
      ];

      let loaded = false;
      for (const path of paths) {
        try {
          const asset = await this.loadModel(path);
          results.set(name, asset);
          loaded = true;
          break;
        } catch {
          // Try next format
          continue;
        }
      }

      if (!loaded) {
        console.warn(`⚠️ Could not load model ${name} in any format`);
        // Add fallback
        results.set(name, this.createFallbackModel(name));
      }
    }

    return results;
  }

  /**
   * Clone a loaded model for instancing
   */
  cloneModel(asset: LoadedModelAsset): THREE.Object3D {
    const clone = asset.model.clone();
    
    // Clone materials to prevent shared state
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const mesh = child as THREE.Mesh;
        if (Array.isArray(mesh.material)) {
          mesh.material = mesh.material.map(mat => mat.clone());
        } else {
          mesh.material = mesh.material.clone();
        }
      }
    });

    return clone;
  }

  /**
   * Create animation mixer for a model instance
   */
  createMixer(model: THREE.Object3D, animations: THREE.AnimationClip[]): THREE.AnimationMixer | null {
    if (animations.length === 0) {
      return null;
    }

    const mixer = new THREE.AnimationMixer(model);
    return mixer;
  }

  /**
   * Get list of available creature models
   */
  getAvailableCreatures(): string[] {
    return [
      'Aligator', 'Armadillo', 'Badger', 'Bear', 'Beaver',
      'Bighorn', 'Bison', 'Boar', 'Bull', 'Cat', 'Chicken',
      'Chipmunk', 'Condor', 'Coyote', 'Crab', 'Crow', 'Deer',
      'Doe', 'Donkey', 'Eagle', 'Egret', 'Elk', 'Fox', 'Goat',
      'Goose', 'Hawk', 'Heron', 'Iguana', 'Mammoth', 'Moose',
      'Owl', 'Owlbear', 'Panther', 'Pig', 'Possum', 'Raccoon',
      'Rat', 'Rooster', 'Seagull', 'Sheep', 'Skunk', 'Squirrel',
      'Turkey', 'Vulture', 'Woodpecker'
    ];
  }

  /**
   * Clear cache
   */
  clearCache(): void {
    this.loadedAssets.forEach(asset => {
      asset.model.traverse((child) => {
        if ((child as THREE.Mesh).isMesh) {
          const mesh = child as THREE.Mesh;
          mesh.geometry.dispose();
          if (Array.isArray(mesh.material)) {
            mesh.material.forEach(mat => mat.dispose());
          } else {
            mesh.material.dispose();
          }
        }
      });
    });

    this.loadedAssets.clear();
    this.loadingPromises.clear();
    console.log('🗑️ Model cache cleared');
  }

  /**
   * Dispose resources
   */
  dispose(): void {
    this.clearCache();
  }
}

export default UniversalModelLoader;
