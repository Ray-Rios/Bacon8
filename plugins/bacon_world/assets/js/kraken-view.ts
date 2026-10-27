// The Kraken (/models/Mobs/B8_Kraken.glb, built by library/pipeline/scripts/build_kraken.py,
// 2026-10-27): the boss in the middle of Crater Lake and the Abyssal Kraken mount, one model.
//
// The file has no clips: this animates the rig itself, every frame, from a few layers.
//   * idle: every arm and tentacle writhes on its own phase, the tips curling; the mantle sways;
//   * swimming: the arms gather toward the maw's axis into a spear and ripple, the mantle pulses;
//   * on land (a mount out of the water): it heaves itself up on its lower arms;
//   * one-shots (play(name), as DragonRig's): "lash", "slam", "grab", "squeeze", "ink",
//     "maelstrom", "roar", "Hit", "Death" (it sinks), each a short timeline over chosen chains;
//   * the eyes (their own bones) turn to look at `lookAt`;
//   * the photophores (the skin's emission map) pulse, brighter when it's angry.
//
// The API mirrors DragonRig's (root, model, saddle, mouth, play, die, revive, update, seatIn,
// dispose, onCycle), so mounts.ts and mobs-view.ts can hold either. The effects here: InkCloud
// (a cone of black ink from the maw) and Maelstrom (a whirlpool on the water round it).
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, MeshoptDecoder, SkeletonUtils } from '../../../../assets/js/vendor/three-loaders';
import { modelUrl } from './asset-url';
import { UNITS_PER_METRE } from './controls-math';

export const KRAKEN_GLB = '/models/Mobs/B8_Kraken.glb';

/** When a move's blow lands (seconds into its one-shot). */
export const KRAKEN_HIT_AT: Record<string, number> = { lash: 0.55, slam: 0.85, grab: 0.0, squeeze: 0.2, ink: 0.0, maelstrom: 0.0 };

type Template = { scene: THREE.Object3D };

export class KrakenFactory {
  private loader: GLTFLoader;
  private tpl: Promise<Template | null> | null = null;

  constructor() {
    this.loader = new GLTFLoader();
    this.loader.setMeshoptDecoder(MeshoptDecoder);
  }

  load(): Promise<Template | null> {
    if (!this.tpl) {
      this.tpl = new Promise((resolve) => {
        this.loader.load(
          modelUrl(KRAKEN_GLB),
          (g: any) => resolve({ scene: g.scene }),
          undefined,
          (err: unknown) => {
            console.warn('[kraken] model failed to load', err);
            resolve(null);
          }
        );
      });
    }
    return this.tpl;
  }

  /** A new kraken `scale` times full size (the mantle stands ~11 m out of the water at 1). */
  async create(scale: number): Promise<KrakenRig | null> {
    const t = await this.load();
    if (!t) return null;
    return new KrakenRig(t, scale);
  }
}

interface Chain {
  name: string;
  kind: 'arm' | 'tent';
  /** 0..1 round the crown; `up` > 0 for the upper arms. */
  index: number;
  up: number;
  bones: THREE.Object3D[];
  rest: THREE.Quaternion[];
  /** Per bone, in its own frame: curling toward the maw's axis (the oral side), and sideways. */
  curlAx: THREE.Vector3[];
  swayAx: THREE.Vector3[];
  /** this frame's angles, built up by the layers */
  curl: number[];
  sway: number[];
}

interface Shot {
  name: string;
  t: number;
  dur: number;
  hold: boolean;
}

const SHOT_DUR: Record<string, number> = { lash: 1.1, slam: 1.5, grab: 1.4, squeeze: 0.9, ink: 1.2, maelstrom: 2.6, roar: 1.6, Hit: 0.5, Death: 5.0 };
const ALIAS: Record<string, string> = { Roar: 'roar', hit: 'Hit', death: 'Death', Bite: 'lash', Claw: 'lash', TailSwipe: 'slam', Breath: 'ink' };

const smooth = (a: number, b: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
/** 0 -> 1 -> 0 over [a, d], flat between b and c. */
const env = (t: number, a: number, b: number, c: number, d: number) => smooth(a, b, t) * (1 - smooth(c, d, t));

export class KrakenRig {
  readonly root = new THREE.Group();
  readonly model: THREE.Object3D;
  readonly scale: number;
  readonly saddle: THREE.Object3D | null;
  readonly mouth: THREE.Object3D | null;
  readonly head: THREE.Object3D | null;
  /** unused (it can't fly); kept so a mount can treat every rig alike */
  flying = false;
  /** In the water (the boss always; a mount when its rider is in deep water). */
  inWater = true;
  dead = false;
  /** Somewhere to stare at (world space), or null. */
  lookAt: THREE.Vector3 | null = null;
  /** Called at each swimming stroke (the mantle's pulse), like DragonRig's wing beats. */
  onCycle: ((kind: 'wing' | 'step' | 'stroke', strength: number) => void) | null = null;

  private chains: Chain[] = [];
  private mantle: Array<{ bone: THREE.Object3D; rest: THREE.Quaternion; ax: THREE.Vector3 }> = [];
  private eyes: Array<{ bone: THREE.Object3D; rest: THREE.Quaternion }> = [];
  private maw: { bone: THREE.Object3D; rest: THREE.Quaternion } | null = null;
  private materials: THREE.Material[] = [];
  private skin: THREE.MeshStandardMaterial[] = [];
  private eyeMats: THREE.MeshStandardMaterial[] = [];
  private time = 0;
  private shot: Shot | null = null;
  private rage = 0;
  private last = new THREE.Vector3();
  private seen = false;
  private speed = 0;
  private strokePhase = 0;
  private strokeAt = 0;
  private swimK = 0;
  private landK = 0;
  private spin = 0;
  private lift = 0;
  private tmpQ = new THREE.Quaternion();
  private tmpV = new THREE.Vector3();

  constructor(t: Template, scale: number) {
    this.scale = scale;
    this.model = SkeletonUtils.clone(t.scene) as THREE.Object3D;
    this.model.scale.setScalar(UNITS_PER_METRE * scale);
    this.root.name = 'Kraken';
    this.root.add(this.model);
    this.model.traverse((o: any) => {
      if (!o.isMesh) return;
      o.castShadow = true;
      o.receiveShadow = true;
      o.frustumCulled = false;
      const own = (m: THREE.Material) => {
        const c = (m as THREE.MeshStandardMaterial).clone();
        this.materials.push(c);
        const role = (c.name || '').replace(/^Kraken_/, '').toLowerCase();
        if (role === 'skin') this.skin.push(c);
        if (role === 'eye') this.eyeMats.push(c);
        return c;
      };
      o.material = Array.isArray(o.material) ? o.material.map(own) : own(o.material);
    });
    this.saddle = this.model.getObjectByName('saddle') || null;
    this.mouth = this.model.getObjectByName('mouth') || null;
    this.head = this.model.getObjectByName('head') || null;
    this.rigUp();
  }

  // Each chain bone's curl and sway axes, in its own frame, from the rest pose: curling turns
  // the bone toward the maw's axis (the side its suckers are on).
  private rigUp() {
    this.root.updateMatrixWorld(true);
    const mawB = this.model.getObjectByName('maw');
    const headB = this.head;
    const axisP = new THREE.Vector3();
    const fwd = new THREE.Vector3(0, 0, 1);
    if (mawB) mawB.getWorldPosition(axisP);
    const names: string[] = [];
    for (let i = 1; i <= 8; i++) names.push(`arm_${i}`);
    names.push('tent_l', 'tent_r');
    names.forEach((name, ci) => {
      const bones: THREE.Object3D[] = [];
      for (let k = 1; k <= 20; k++) {
        const b = this.model.getObjectByName(`${name}_${String(k).padStart(2, '0')}`);
        if (!b) break;
        bones.push(b);
      }
      if (!bones.length) return;
      const pos = bones.map((b) => b.getWorldPosition(new THREE.Vector3()));
      const c: Chain = {
        name,
        kind: name.startsWith('arm') ? 'arm' : 'tent',
        index: ci < 8 ? ci / 8 : ci === 8 ? 0.71 : 0.79,
        up: 0,
        bones,
        rest: bones.map((b) => b.quaternion.clone()),
        curlAx: [],
        swayAx: [],
        curl: bones.map(() => 0),
        sway: bones.map(() => 0),
      };
      const rel = pos[0].clone().sub(axisP);
      c.up = rel.y / Math.max(rel.length(), 1e-6);
      bones.forEach((b, k) => {
        const T = (k + 1 < pos.length ? pos[k + 1].clone().sub(pos[k]) : pos[k].clone().sub(pos[k - 1])).normalize();
        // toward the axis through the maw (along +z, the way it faces)
        const toAxis = axisP.clone().add(fwd.clone().multiplyScalar(pos[k].clone().sub(axisP).dot(fwd))).sub(pos[k]);
        let O = toAxis.sub(T.clone().multiplyScalar(toAxis.dot(T)));
        if (O.lengthSq() < 1e-8) O = new THREE.Vector3(0, 1, 0);
        O.normalize();
        const curl = new THREE.Vector3().crossVectors(T, O).normalize();
        const qi = b.getWorldQuaternion(new THREE.Quaternion()).invert();
        c.curlAx.push(curl.applyQuaternion(qi).normalize());
        c.swayAx.push(O.clone().applyQuaternion(qi).normalize());
      });
      this.chains.push(c);
    });
    for (let k = 1; k <= 5; k++) {
      const b = this.model.getObjectByName(`mantle_0${k}`);
      if (!b) continue;
      const qi = b.getWorldQuaternion(new THREE.Quaternion()).invert();
      this.mantle.push({ bone: b, rest: b.quaternion.clone(), ax: new THREE.Vector3(1, 0, 0).applyQuaternion(qi).normalize() });
    }
    for (const n of ['eye_l', 'eye_r']) {
      const b = this.model.getObjectByName(n);
      if (b) this.eyes.push({ bone: b, rest: b.quaternion.clone() });
    }
    if (mawB) this.maw = { bone: mawB, rest: mawB.quaternion.clone() };
    void headB;
  }

  has(name: string): boolean {
    return (ALIAS[name] ?? name) in SHOT_DUR;
  }

  duration(name: string): number {
    return SHOT_DUR[ALIAS[name] ?? name] ?? 0;
  }

  /** A one-shot (seconds it lasts). `hold` keeps its end (death). */
  play(name: string, opts: { rate?: number; hold?: boolean; fade?: number } = {}): number {
    const n = ALIAS[name] ?? name;
    const d = SHOT_DUR[n];
    if (!d || (this.dead && n !== 'Death')) return 0;
    const rate = opts.rate ?? 1;
    this.shot = { name: n, t: 0, dur: d / rate, hold: !!opts.hold };
    if (n !== 'Hit') this.rage = 1;
    return d / rate;
  }

  die(instant = false) {
    this.dead = true;
    this.play('Death', { hold: true });
    if (instant && this.shot) this.shot.t = this.shot.dur;
  }

  revive() {
    this.dead = false;
    this.shot = null;
    this.model.position.y = 0;
  }

  /** Per frame: the layers, then the bones. */
  update(dt: number) {
    this.time += dt;
    const U = UNITS_PER_METRE;
    const p = this.root.getWorldPosition(this.tmpV);
    if (this.seen && dt > 0) {
      const v = Math.hypot(p.x - this.last.x, p.z - this.last.z) / dt / U;
      this.speed += (Math.min(v, 60) - this.speed) * Math.min(1, dt * 2);
    }
    this.last.copy(p);
    this.seen = true;
    this.rage = Math.max(0, this.rage - dt * 0.12);
    if (this.shot) {
      this.shot.t += dt;
      if (this.shot.t >= this.shot.dur && !this.shot.hold) this.shot = null;
    }
    const t = this.time;
    const s = this.scale;
    // swimming: how fast for its size (a full stride at ~6 body-lengths... about 9 m/s full size)
    // (eased slowly, with a dead band: the creature view's small corrections to where it is read as
    // speed, and the arms and the mantle wobbled with them, 2026-10-27)
    const fast = Math.max(0, this.speed - 0.4 * Math.max(s, 0.25)) / (6 * Math.max(s, 0.25));
    const swimWant = this.inWater ? Math.min(1, fast) : 0;
    this.swimK += (swimWant - this.swimK) * Math.min(1, dt * 1.2);
    this.landK += ((this.inWater ? 0 : 1) - this.landK) * Math.min(1, dt * 2);
    const swim = this.swimK;
    const land = this.landK;
    // the stroke's phase runs at its own pace (a phase of time x a changing rate jumped wildly)
    this.strokeAt += dt * (2.2 + 2.5 * swim);

    // --- the arms and tentacles ---
    for (const c of this.chains) {
      const n = c.bones.length;
      const ph = c.index * Math.PI * 2 * 1.37;
      for (let k = 0; k < n; k++) {
        const f = (k + 1) / n;
        let curl = 0.1 * Math.sin(t * 0.9 + ph - k * 0.55) * (0.35 + f) + 0.05 * f * f;
        let sway = 0.08 * Math.cos(t * 0.7 + ph * 1.3 - k * 0.5) * (0.35 + f);
        if (c.kind === 'tent') {
          curl *= 0.7;
          sway *= 0.7;
        }
        // swimming: gather into a spear, rippling
        if (swim > 0) {
          curl += swim * (k === 0 ? 0.62 : k === 1 ? 0.18 : -0.035) + swim * 0.09 * Math.sin(t * 5 - k * 0.8 + ph);
          sway *= 1 - 0.6 * swim;
        }
        // on land: heaved up on the lower arms, the upper ones held back
        if (land > 0) curl += land * (c.up < -0.2 ? (k === 0 ? -0.5 : k < 3 ? 0.08 : 0.02) : k === 0 ? -0.15 : 0);
        c.curl[k] = curl;
        c.sway[k] = sway;
      }
    }
    // --- the mantle ---
    let mantleBend = 0.03 * Math.sin(t * 0.6);
    const stroke = Math.sin(this.strokeAt);
    mantleBend += swim * 0.05 * stroke;
    // a stroke at the top of each pulse
    const sp = this.strokeAt / (Math.PI * 2);
    if (swim > 0.2 && Math.floor(sp) !== Math.floor(this.strokePhase)) this.onCycle?.('stroke', swim);
    this.strokePhase = sp;
    let mawOpen = 0.05 + 0.04 * Math.sin(t * 0.8);
    let sink = 0;
    let spin = 0;

    // --- the one-shot ---
    const sh = this.shot;
    if (sh) {
      const x = sh.t / sh.dur;
      const upper = (c: Chain) => c.kind === 'arm' && c.up > 0.3;
      switch (sh.name) {
        case 'lash': {
          // (2026-10-27: the first cut picked arms that didn't exist, so nothing moved.) The two
          // upper arms rear back and whip down in front; the side arms sweep across.
          const wind = env(x, 0.0, 0.3, 0.4, 0.5);
          const whip = env(x, 0.4, 0.55, 0.68, 1.0);
          this.chains.forEach((c) => {
            if (c.kind !== 'arm') return;
            const n = c.bones.length;
            if (c.up > 0.5) {
              c.bones.forEach((_b, k) => {
                const f = (k + 1) / n;
                c.curl[k] += (-0.2 * wind + 0.3 * whip) * (0.3 + f);
              });
            } else if (Math.abs(c.up) <= 0.5) {
              const side = c.index < 0.5 ? 1 : -1;
              c.bones.forEach((_b, k) => {
                const f = (k + 1) / n;
                c.sway[k] += 0.18 * (whip - wind) * (0.3 + f) * side;
                c.curl[k] += 0.08 * whip * (0.3 + f);
              });
            }
          });
          mantleBend += -0.05 * wind + 0.08 * whip;
          mawOpen += 0.25 * env(x, 0.3, 0.5, 0.6, 0.9);
          break;
        }
        case 'slam': {
          const raise = env(x, 0.0, 0.45, 0.5, 0.6);
          const down = env(x, 0.5, 0.6, 0.75, 1.0);
          this.chains.forEach((c) => {
            if (!upper(c)) return;
            c.bones.forEach((_b, k) => {
              const f = (k + 1) / c.bones.length;
              c.curl[k] += (k < 3 ? -0.45 : -0.12) * raise + (k < 3 ? 0.55 : 0.2) * down * (0.5 + f);
            });
          });
          mantleBend += -0.08 * raise + 0.1 * down;
          break;
        }
        case 'grab':
        case 'squeeze': {
          // the hunting tentacles shoot out straight, then coil round what they caught
          const out = sh.name === 'grab' ? env(x, 0.0, 0.25, 0.45, 0.6) : 0;
          const coil = sh.name === 'grab' ? env(x, 0.45, 0.65, 0.9, 1.0) : env(x, 0.0, 0.3, 0.7, 1.0);
          this.chains.forEach((c) => {
            if (c.kind !== 'tent') return;
            c.bones.forEach((_b, k) => {
              const f = (k + 1) / c.bones.length;
              c.curl[k] = c.curl[k] * (1 - out) + (k === 0 ? 0.25 : -0.02) * out + (f > 0.6 ? 0.55 : 0.05) * coil;
              c.sway[k] *= 1 - out;
            });
          });
          mawOpen += 0.3 * coil;
          break;
        }
        case 'ink': {
          // a heave: the mantle contracts forward, the arms flare, the maw gapes
          const k1 = env(x, 0.0, 0.2, 0.5, 0.9);
          this.chains.forEach((c) =>
            c.bones.forEach((_b, k) => {
              c.curl[k] += k === 0 ? -0.3 * k1 : 0;
            })
          );
          mantleBend += 0.12 * k1;
          mawOpen += 0.5 * k1;
          break;
        }
        case 'maelstrom': {
          // it spins, arms flung wide and lashing
          const k1 = env(x, 0.0, 0.25, 0.75, 1.0);
          spin = k1;
          this.chains.forEach((c, ci) =>
            c.bones.forEach((_b, k) => {
              const f = (k + 1) / c.bones.length;
              c.curl[k] += (k === 0 ? -0.35 : 0.06 * Math.sin(t * 9 + ci + k)) * k1;
              c.sway[k] += 0.22 * k1 * f;
            })
          );
          mawOpen += 0.4 * k1;
          break;
        }
        case 'roar': {
          const k1 = env(x, 0.0, 0.2, 0.7, 1.0);
          this.chains.forEach((c) =>
            c.bones.forEach((_b, k) => {
              c.curl[k] += (k === 0 ? -0.4 : 0.02 * Math.sin(t * 14 + k)) * k1;
            })
          );
          mantleBend -= 0.1 * k1;
          mawOpen += 0.9 * k1;
          break;
        }
        case 'Hit': {
          const k1 = env(x, 0.0, 0.15, 0.3, 1.0);
          this.chains.forEach((c) => c.bones.forEach((_b, k) => (c.curl[k] += 0.08 * k1)));
          mantleBend += 0.06 * k1;
          break;
        }
        case 'Death': {
          // the arms go slack, it rolls and sinks
          const k1 = smooth(0, 0.5, x);
          this.chains.forEach((c) =>
            c.bones.forEach((_b, k) => {
              c.curl[k] = c.curl[k] * (1 - k1) + (k === 0 ? -0.25 : 0.04) * k1;
              c.sway[k] *= 1 - k1;
            })
          );
          mawOpen = 0.6 * k1;
          sink = smooth(0.15, 1.0, x);
          break;
        }
      }
    }

    // --- apply ---
    for (const c of this.chains) {
      for (let k = 0; k < c.bones.length; k++) {
        const b = c.bones[k];
        b.quaternion.copy(c.rest[k]);
        b.quaternion.multiply(this.tmpQ.setFromAxisAngle(c.curlAx[k], c.curl[k]));
        b.quaternion.multiply(this.tmpQ.setFromAxisAngle(c.swayAx[k], c.sway[k]));
      }
    }
    this.mantle.forEach((m, i) => {
      m.bone.quaternion.copy(m.rest).multiply(this.tmpQ.setFromAxisAngle(m.ax, mantleBend * (0.6 + i * 0.25)));
    });
    if (this.maw) this.maw.bone.quaternion.copy(this.maw.rest);
    if (this.maw) this.maw.bone.scale.setScalar(1 + Math.min(0.6, mawOpen) * 0.35);
    // spinning in its maelstrom, sinking when dead, up on its arms on land
    this.spin += spin * dt * 7.5;
    if (!spin) this.spin *= Math.max(0, 1 - dt * 3);
    this.model.rotation.y = this.spin;
    this.lift += (land * 1.1 - this.lift) * Math.min(1, dt * 3);
    this.model.position.y = (this.lift - sink * 9) * U * s;
    this.model.rotation.z = sink * 0.7;
    this.updateEyes();
    // the photophores: a slow pulse with a flicker, brighter in anger
    const glow = (0.55 + 0.35 * Math.sin(t * 1.3) + 0.1 * Math.sin(t * 7.3) * Math.sin(t * 2.1)) * (1 + 1.6 * this.rage) * (this.dead ? Math.max(0, 1 - (this.shot?.t ?? 9) / 3) : 1);
    for (const m of this.skin) m.emissiveIntensity = glow;
    for (const m of this.eyeMats) m.emissiveIntensity = (this.dead ? 0.1 : 1.0 + 0.8 * this.rage) * (0.9 + 0.1 * Math.sin(t * 3.1));
  }

  private updateEyes() {
    if (!this.eyes.length) return;
    const up = new THREE.Vector3(0, 1, 0);
    for (const e of this.eyes) {
      e.bone.quaternion.copy(e.rest);
      if (!this.lookAt || this.dead) continue;
      e.bone.updateMatrixWorld(true);
      const local = e.bone.worldToLocal(this.lookAt.clone()).normalize();
      // bones point along +y: turn +y toward the target, at most ~40 degrees
      const q = this.tmpQ.setFromUnitVectors(up, local);
      const ang = 2 * Math.acos(Math.min(1, Math.abs(q.w)));
      if (ang > 0.7) q.slerp(new THREE.Quaternion(), 1 - 0.7 / ang);
      e.bone.quaternion.multiply(q);
    }
  }

  /** The seat's position in `space`'s frame (for the rider), or null. */
  seatIn(space: THREE.Object3D, out = new THREE.Vector3()): THREE.Vector3 | null {
    if (!this.saddle) return null;
    this.saddle.getWorldPosition(out);
    return space.worldToLocal(out);
  }

  dispose() {
    this.root.removeFromParent();
    for (const m of this.materials) m.dispose();
    this.materials = [];
  }
}

// ---------------------------------------------------------------------------
// Ink: a cone of black, oily cloud from the maw that lingers and spreads.
// ---------------------------------------------------------------------------

let INK_TEX: THREE.Texture | null = null;

function inkTexture(): THREE.Texture {
  if (INK_TEX) return INK_TEX;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const grd = g.createRadialGradient(32, 32, 2, 32, 32, 31);
  grd.addColorStop(0, 'rgba(6,2,10,0.95)');
  grd.addColorStop(0.45, 'rgba(14,6,22,0.7)');
  grd.addColorStop(0.8, 'rgba(20,10,30,0.25)');
  grd.addColorStop(1, 'rgba(20,10,30,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, 64, 64);
  INK_TEX = new THREE.CanvasTexture(c);
  return INK_TEX;
}

export class InkCloud {
  readonly points: THREE.Points;
  private n = 220;
  private pos: Float32Array;
  private vel: Float32Array;
  private age: Float32Array;
  private life = 4.5;
  private emitting = 0;
  private next = 0;
  private tmp = new THREE.Vector3();
  private dir = new THREE.Vector3();

  /** From `mouth`, along where `facing` (the kraken's root) looks; `reach` and `size` scene units. */
  constructor(private scene: THREE.Object3D, private mouth: THREE.Object3D, private facing: THREE.Object3D, private reach: number, size: number) {
    this.pos = new Float32Array(this.n * 3);
    this.vel = new Float32Array(this.n * 3);
    this.age = new Float32Array(this.n).fill(99);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    const mat = new THREE.PointsMaterial({ size, map: inkTexture(), transparent: true, depthWrite: false, opacity: 0.9, sizeAttenuation: true, color: 0xffffff });
    this.points = new THREE.Points(geo, mat);
    this.points.frustumCulled = false;
    this.points.name = 'Ink';
    scene.add(this.points);
  }

  start(seconds: number) {
    this.emitting = seconds;
  }

  update(dt: number) {
    this.mouth.getWorldPosition(this.tmp);
    this.facing.getWorldDirection(this.dir);
    const speed = this.reach / 1.4;
    if (this.emitting > 0) {
      this.emitting -= dt;
      this.next -= dt;
      while (this.next <= 0) {
        this.next += 1 / 200;
        const i = this.age.findIndex((a) => a >= this.life);
        if (i < 0) break;
        this.age[i] = 0;
        this.pos.set([this.tmp.x, this.tmp.y, this.tmp.z], i * 3);
        const s = speed * (0.6 + Math.random() * 0.6);
        const spread = 0.75;
        this.vel[i * 3] = (this.dir.x + (Math.random() - 0.5) * spread) * s;
        this.vel[i * 3 + 1] = (Math.random() - 0.3) * 0.25 * s;
        this.vel[i * 3 + 2] = (this.dir.z + (Math.random() - 0.5) * spread) * s;
      }
    }
    let live = 0;
    for (let i = 0; i < this.n; i++) {
      if (this.age[i] >= this.life) {
        this.pos[i * 3 + 1] = -1e6;
        continue;
      }
      live++;
      this.age[i] += dt;
      const drag = Math.exp(-dt * 1.6);
      this.vel[i * 3] *= drag;
      this.vel[i * 3 + 1] *= drag;
      this.vel[i * 3 + 2] *= drag;
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
    }
    const m = this.points.material as THREE.PointsMaterial;
    m.opacity = live ? 0.85 : 0;
    (this.points.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
  }

  dispose() {
    this.scene.remove(this.points);
    this.points.geometry.dispose();
    (this.points.material as THREE.Material).dispose();
  }
}

// ---------------------------------------------------------------------------
// The maelstrom: a whirlpool on the water round the kraken, and spray spiralling in.
// ---------------------------------------------------------------------------

let SWIRL_TEX: THREE.Texture | null = null;

function swirlTexture(): THREE.Texture {
  if (SWIRL_TEX) return SWIRL_TEX;
  const S = 256;
  const c = document.createElement('canvas');
  c.width = c.height = S;
  const g = c.getContext('2d')!;
  const img = g.createImageData(S, S);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const dx = (x + 0.5) / S * 2 - 1;
      const dy = (y + 0.5) / S * 2 - 1;
      const r = Math.hypot(dx, dy);
      const a = Math.atan2(dy, dx);
      // spiral arms of foam over dark water, a black eye in the middle
      const arm = 0.5 + 0.5 * Math.sin(a * 5 + Math.log(r + 0.02) * 9);
      const foam = Math.pow(arm, 6) * Math.min(1, r * 3) * (1 - r);
      const dark = (1 - Math.min(1, r * 1.4)) * 0.9;
      const alpha = r > 1 ? 0 : Math.min(1, 0.35 * (1 - r) + foam * 0.9 + dark * 0.6) * Math.min(1, (1 - r) * 4);
      const i = (y * S + x) * 4;
      img.data[i] = 40 + 200 * foam;
      img.data[i + 1] = 60 + 190 * foam;
      img.data[i + 2] = 70 + 180 * foam;
      img.data[i + 3] = 255 * alpha;
    }
  }
  g.putImageData(img, 0, 0);
  SWIRL_TEX = new THREE.CanvasTexture(c);
  return SWIRL_TEX;
}

export class Maelstrom {
  readonly mesh: THREE.Mesh;
  private left = 0;
  private total = 1;
  private spray: THREE.Points;
  private sp: Float32Array;
  private sa: Float32Array; // angle, radius, height per particle
  private n = 160;

  /** A whirlpool `radius` scene units round `centre` (it follows it), at the water's height `y()`. */
  constructor(private scene: THREE.Object3D, private centre: THREE.Object3D, private radius: number, private y: () => number) {
    const mat = new THREE.MeshBasicMaterial({ map: swirlTexture(), transparent: true, depthWrite: false, opacity: 0 });
    this.mesh = new THREE.Mesh(new THREE.CircleGeometry(1, 64).rotateX(-Math.PI / 2), mat);
    this.mesh.renderOrder = 3;
    this.mesh.visible = false;
    scene.add(this.mesh);
    this.sp = new Float32Array(this.n * 3);
    this.sa = new Float32Array(this.n * 3);
    for (let i = 0; i < this.n; i++) {
      this.sa[i * 3] = Math.random() * Math.PI * 2;
      this.sa[i * 3 + 1] = Math.random();
      this.sa[i * 3 + 2] = Math.random();
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.sp, 3));
    this.spray = new THREE.Points(
      geo,
      new THREE.PointsMaterial({ color: 0xd8eef0, size: radius * 0.04, transparent: true, opacity: 0, depthWrite: false, sizeAttenuation: true })
    );
    this.spray.frustumCulled = false;
    scene.add(this.spray);
  }

  start(seconds: number) {
    this.left = this.total = seconds;
  }

  update(dt: number) {
    if (this.left <= 0) {
      this.mesh.visible = false;
      (this.spray.material as THREE.PointsMaterial).opacity = 0;
      return;
    }
    this.left -= dt;
    const x = 1 - this.left / this.total;
    const k = smooth(0, 0.15, x) * (1 - smooth(0.8, 1, x));
    const c = this.centre.getWorldPosition(new THREE.Vector3());
    const wy = this.y();
    this.mesh.visible = true;
    this.mesh.position.set(c.x, wy + 0.05 * UNITS_PER_METRE, c.z);
    this.mesh.scale.setScalar(this.radius * (0.4 + 0.6 * k));
    this.mesh.rotation.y -= dt * 2.4;
    (this.mesh.material as THREE.MeshBasicMaterial).opacity = 0.9 * k;
    for (let i = 0; i < this.n; i++) {
      // spiral inward, rising a little
      this.sa[i * 3] -= dt * (2.0 + 3.0 * (1 - this.sa[i * 3 + 1]));
      this.sa[i * 3 + 1] -= dt * 0.35;
      if (this.sa[i * 3 + 1] < 0.05) this.sa[i * 3 + 1] = 1;
      const r = this.sa[i * 3 + 1] * this.radius;
      this.sp[i * 3] = c.x + Math.cos(this.sa[i * 3]) * r;
      this.sp[i * 3 + 1] = wy + (0.2 + 1.2 * this.sa[i * 3 + 2] * (1 - this.sa[i * 3 + 1])) * UNITS_PER_METRE;
      this.sp[i * 3 + 2] = c.z + Math.sin(this.sa[i * 3]) * r;
    }
    (this.spray.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    (this.spray.material as THREE.PointsMaterial).opacity = 0.8 * k;
  }

  dispose() {
    this.scene.remove(this.mesh);
    this.scene.remove(this.spray);
    this.mesh.geometry.dispose();
    (this.mesh.material as THREE.Material).dispose();
    this.spray.geometry.dispose();
    (this.spray.material as THREE.Material).dispose();
  }
}
