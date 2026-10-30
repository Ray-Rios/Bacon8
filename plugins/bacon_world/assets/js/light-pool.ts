// The world's effect lights (2026-10-30): one pool for every effect, created when the world is
// and never leaving the scene.
//
// three.js builds every lit material's shader for the number of lights in the scene. Adding a light
// (a fireball's glow, a dragon's breath) or removing one makes every material in the village and on
// every character recompile: the game freezes for seconds. Spells learnt this on 2026-10-26 and got
// their own pool of three (spell-fx.ts); the dragons' fire breath still added a light the first time
// a drake breathed (and removed it on dispose), which is the long first-breath freeze. Now there is
// one pool: these lights are always in the scene, at intensity 0 when nobody is using them, so the
// count never changes. (`visible = false` would change it too.)
//
// An effect asks for a light and goes without one when all are busy.
import * as THREE from '../../../../assets/js/vendor/three';

export const POOLED_LIGHTS = 4;

export class LightPool {
  private static current: LightPool | null = null;
  private lights: THREE.PointLight[] = [];
  private busy = new Set<THREE.PointLight>();

  private constructor(readonly scene: THREE.Object3D, n: number) {
    for (let i = 0; i < n; i++) {
      const l = new THREE.PointLight(0xffffff, 0, 1, 1.6);
      l.name = `PooledLight${i}`;
      this.lights.push(l);
      scene.add(l);
    }
  }

  /** The world scene's pool, created on first call (call it before anything compiles). */
  static install(scene: THREE.Object3D, n = POOLED_LIGHTS): LightPool {
    if (LightPool.current && LightPool.current.scene === scene) return LightPool.current;
    LightPool.current = new LightPool(scene, n);
    return LightPool.current;
  }

  /** The installed pool, or null (an effect then goes without a light). */
  static get(): LightPool | null {
    return LightPool.current;
  }

  /** A pooled light, lit and placed, or null when all are busy. */
  take(color: THREE.ColorRepresentation, intensity: number, distance: number): THREE.PointLight | null {
    const l = this.lights.find((x) => !this.busy.has(x));
    if (!l) return null;
    this.busy.add(l);
    l.color.set(color);
    l.intensity = intensity;
    l.distance = distance;
    return l;
  }

  give(l: THREE.PointLight | null | undefined) {
    if (!l) return;
    l.intensity = 0;
    this.busy.delete(l);
  }

  /** Every light back, dark. */
  reset() {
    for (const l of this.lights) this.give(l);
  }
}
