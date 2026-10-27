// The hook's terrain (2026-10-26), mixed in like game-world.ts. The page carries the zone's
// terrain description (`data-terrain`, BaconWorld.Terrain.payload/1; null when the zone is flat);
// this loads the heights before the village is built, so every piece stands on the ground, then
// draws the terrain and tells everyone who needs the ground where it is: the controller (feet and
// camera), the creatures and merchants, the water and fishing.
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { loadHeightfield, TerrainView, type Heightfield, type TerrainInfo } from './terrain';

const U = UNITS_PER_METRE;
/** The camera's far plane over a terrain (scene units): the far ridges stay in view. */
const FAR = 7000;
/** The murk under the water. */
const UNDERWATER = 0x0b3440;

export const TerrainWorld = {
  /** Starts loading the terrain (once). `terrainReady` resolves to it, or null on flat ground. */
  initTerrain(this: any): Promise<Heightfield | null> {
    if (this.terrainReady) return this.terrainReady;
    let info: TerrainInfo | null = null;
    try {
      info = JSON.parse(this.el?.dataset?.terrain || 'null');
    } catch {
      info = null;
    }
    if (!info || !info.heights) {
      this.terrainReady = Promise.resolve(null);
      return this.terrainReady;
    }
    this.terrainReady = loadHeightfield(info)
      .then((hf: Heightfield) => {
        this.heightfield = hf;
        if (this.worldGroup) {
          this.terrainView = new TerrainView(hf);
          this.worldGroup.add(this.terrainView.group);
        }
        if (this.camera) {
          this.camera.far = FAR;
          this.camera.updateProjectionMatrix();
        }
        this.applyGround();
        return hf;
      })
      .catch((err: unknown) => {
        console.warn('[terrain] could not load; the ground stays flat', err);
        return null;
      });
    return this.terrainReady;
  },

  /** The ground under (x, z), scene units (0 while flat or loading). */
  groundAt(this: any, x: number, z: number): number {
    return this.heightfield ? this.heightfield.height(x, z) : 0;
  },

  /** Hands the ground to whoever stands on it (again after any of them is created). */
  applyGround(this: any) {
    const hf: Heightfield | null = this.heightfield || null;
    // feet: the ground, or the water's surface where it's too deep to stand (they swim there)
    this.controller?.setGround?.(
      hf ? (x: number, z: number) => hf.feet(x, z) : null,
      hf ? (x: number, z: number) => hf.surface(x, z) : null,
      hf ? (x: number, z: number) => hf.deep(x, z) : null,
      // the bottom, for diving (2026-10-27)
      hf ? (x: number, z: number) => hf.height(x, z) : null
    );
    if (this.mobsView) this.mobsView.ground = hf ? (x: number, z: number) => hf.surface(x, z) : null;
    if (this.npcsView) this.npcsView.ground = hf ? (x: number, z: number) => hf.height(x, z) : null;
    if (this.water) this.water.terrain = hf;
  },

  /** Per frame: the terrain's level of detail follows the camera; under water, murk. */
  tickTerrain(this: any) {
    if (this.terrainView && this.camera) this.terrainView.update(this.camera);
    this.tickUnderwater();
  },

  /**
   * The camera under the water's surface (a dive, 2026-10-27): the scene's fog and background turn
   * a murky blue-green and close in to ~15 m; back as they were when it comes up.
   */
  tickUnderwater(this: any) {
    const hf: Heightfield | null = this.heightfield || null;
    const cam = this.camera;
    const scene = this.scene;
    if (!cam || !scene) return;
    const p = cam.position;
    const under = !!hf && p.y < hf.surface(p.x, p.z) - 0.05 * U && p.y > hf.height(p.x, p.z);
    if (under === !!this.underwater) return;
    this.underwater = under;
    if (under) {
      this.aboveWater = { fog: scene.fog, background: scene.background };
      scene.fog = new THREE.FogExp2(UNDERWATER, 0.065 / U);
      scene.background = new THREE.Color(UNDERWATER);
    } else if (this.aboveWater) {
      scene.fog = this.aboveWater.fog;
      scene.background = this.aboveWater.background;
      this.aboveWater = null;
    }
  },

  teardownTerrain(this: any) {
    this.terrainView?.dispose();
    this.terrainView = null;
    this.heightfield = null;
    this.terrainReady = null;
    if (this.camera) {
      this.camera.far = 1000;
      this.camera.updateProjectionMatrix();
    }
  },

  /** A point on the ground (scene units), for rings and markers. */
  onGround(this: any, x: number, z: number, lift = 0): THREE.Vector3 {
    return new THREE.Vector3(x, this.groundAt(x, z) + lift * U, z);
  },
};
