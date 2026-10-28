// The B8 rat (2026-10-28; library/pipeline/scripts/build_rat.py): the giant rats and the plague
// rats. Its own small rig and six clips (Idle, Walk, Run, Bite, Hit, Death); this picks the gait
// from the speed, lays the one-shots over it, and lies it down when it dies. A plague rat is the same
// model, bigger, its fur sickly and its eyes glowing.
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, MeshoptDecoder, SkeletonUtils } from '../../../../assets/js/vendor/three-loaders';
import { modelUrl } from './asset-url';
import { UNITS_PER_METRE } from './controls-math';

export const RAT_GLB = '/models/Mobs/B8_Rat.glb';
const U = UNITS_PER_METRE;

/** When a bite lands, seconds into its clip (Bite: the lunge peaks at 0.4 of 0.6 s). */
export const RAT_HIT_AT = 0.26;

// The speed (m/s) each gait was keyed at, so the feet keep up.
const WALK_MPS = 0.9;
const RUN_MPS = 3.4;

/** The gait for a speed (m/s): pure, tested. */
export function ratGait(speed: number): { clip: 'Idle' | 'Walk' | 'Run'; rate: number } {
  if (speed < 0.12) return { clip: 'Idle', rate: 1 };
  if (speed < 1.8) return { clip: 'Walk', rate: Math.max(0.5, Math.min(2.2, speed / WALK_MPS)) };
  return { clip: 'Run', rate: Math.max(0.6, Math.min(1.8, speed / RUN_MPS)) };
}

export class RatFactory {
  private loader = new GLTFLoader();
  private tpl: Promise<{ scene: THREE.Object3D; clips: THREE.AnimationClip[] } | null> | null = null;

  constructor() {
    this.loader.setMeshoptDecoder(MeshoptDecoder);
  }

  private load() {
    if (!this.tpl) {
      this.tpl = new Promise((resolve) => {
        this.loader.load(
          modelUrl(RAT_GLB),
          (g: any) => resolve({ scene: g.scene, clips: g.animations || [] }),
          undefined,
          (err: unknown) => {
            console.warn('[rats] model failed to load', err);
            resolve(null);
          }
        );
      });
    }
    return this.tpl;
  }

  async create(scale: number, plague: boolean): Promise<RatRig | null> {
    const t = await this.load();
    if (!t) return null;
    return new RatRig(SkeletonUtils.clone(t.scene) as THREE.Object3D, t.clips, scale, plague);
  }
}

export class RatRig {
  readonly root = new THREE.Group();
  readonly model: THREE.Object3D;
  private mixer: THREE.AnimationMixer;
  private actions = new Map<string, THREE.AnimationAction>();
  private gait: THREE.AnimationAction | null = null;
  private shot: THREE.AnimationAction | null = null;
  private dead = false;
  private mats: THREE.Material[] = [];

  constructor(model: THREE.Object3D, clips: THREE.AnimationClip[], scale: number, plague: boolean) {
    this.model = model;
    model.scale.setScalar(U * scale);
    model.traverse((o: any) => {
      if (!o.isMesh) return;
      o.castShadow = true;
      o.receiveShadow = true;
      o.frustumCulled = false;
      if (plague) {
        const m = (o.material as THREE.MeshStandardMaterial).clone();
        if (/Fur|Leg/.test(m.name)) m.color.multiply(new THREE.Color('#B4C27A'));
        if (/Eye/.test(m.name)) {
          m.emissive = new THREE.Color('#FF3A1A');
          m.emissiveIntensity = 1.6;
        }
        o.material = m;
        this.mats.push(m);
      }
    });
    this.root.add(model);
    this.mixer = new THREE.AnimationMixer(model);
    for (const c of clips) this.actions.set(c.name, this.mixer.clipAction(c));
    this.setSpeed(0);
  }

  /** Walks, runs or stands, by its speed (m/s). */
  setSpeed(mps: number) {
    if (this.dead) return;
    const g = ratGait(mps);
    const a = this.actions.get(g.clip);
    if (!a) return;
    a.timeScale = g.rate;
    if (a === this.gait) return;
    a.reset();
    a.setLoop(THREE.LoopRepeat, Infinity);
    a.play();
    if (this.gait) this.gait.crossFadeTo(a, 0.2, false);
    a.setEffectiveWeight(1);
    this.gait = a;
  }

  /** A bite or a flinch, over the gait. Returns its length (s). */
  play(name: 'Bite' | 'Hit'): number {
    if (this.dead) return 0;
    const a = this.actions.get(name);
    if (!a) return 0;
    this.shot?.stop();
    a.reset();
    a.setLoop(THREE.LoopOnce, 1);
    a.clampWhenFinished = false;
    a.setEffectiveWeight(1);
    a.fadeIn(0.06);
    a.play();
    this.shot = a;
    return a.getClip().duration;
  }

  die(instant = false) {
    if (this.dead) return;
    this.dead = true;
    const a = this.actions.get('Death');
    if (!a) return;
    this.mixer.stopAllAction();
    a.reset();
    a.setLoop(THREE.LoopOnce, 1);
    a.clampWhenFinished = true;
    a.play();
    if (instant) a.time = a.getClip().duration;
    this.gait = null;
    this.shot = null;
  }

  revive() {
    if (!this.dead) return;
    this.dead = false;
    this.mixer.stopAllAction();
    this.gait = null;
    this.setSpeed(0);
  }

  update(dt: number) {
    if (this.shot && !this.shot.isRunning()) {
      this.shot.stop();
      this.shot = null;
    }
    this.mixer.update(dt);
  }

  dispose() {
    this.mixer.stopAllAction();
    this.root.parent?.remove(this.root);
    for (const m of this.mats) m.dispose();
  }
}
