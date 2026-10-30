// The B8 dragon (/models/Mobs/B8_Dragon.glb, built by library/pipeline/scripts/build_dragon.py):
// Baconator the boss and the dragon mounts are the same model and rig, scaled and tinted.
//
// DragonFactory loads the file once; each DragonRig is a clone with its own materials
// (for the tint), mixer and clips. The rig chooses its own locomotion clip from how fast
// its parent moves (on the ground: Idle, Walk, Run; in the air: Hover, Fly, Glide), so
// mobs-view.ts and mounts.ts only say whether it flies and ask for one-shots (Bite,
// Claw, TailSwipe, Breath, Roar, Hit, Death).
import * as THREE from '../../../../assets/js/vendor/three';
import { LightPool } from './light-pool';
import { GLTFLoader, MeshoptDecoder, SkeletonUtils } from '../../../../assets/js/vendor/three-loaders';
import { modelUrl } from './asset-url';
import { UNITS_PER_METRE } from './controls-math';

export const DRAGON_GLB = '/models/Mobs/B8_Dragon.glb';

/** A mount's colours (BaconWorld.Mounts `colors`). The model's colour is in its textures
 * (Dragon_Skin, Dragon_Membrane, Dragon_Eye); a mount turns their hue to these. */
export interface DragonColors {
  scales?: string;
  belly?: string;
  membrane?: string;
  horn?: string;
  eye?: string;
}

// Paces of the clips at full size (m/s), for their playback rate.
const WALK_REF = 3.4;
const RUN_REF = 8.5;
const FLY_REF = 14.0;

// How long the attack clips take to land (seconds at rate 1), measured on the clips.
export const DRAGON_HIT_AT: Record<string, number> = { Bite: 0.5, Claw: 0.55, TailSwipe: 0.62, Breath: 1.05 };
export const DRAGON_MOVE_CLIP: Record<string, string> = { bite: 'Bite', claw: 'Claw', tail: 'TailSwipe', breath: 'Breath' };

// The boss's own colours, as the textures have them: a mount rotates the hue (and scales
// saturation and lightness) from these to its own.
const BOSS_HUE: Record<string, string> = { skin: '#A33416', membrane: '#5E1A10', eye: '#FF5A10' };
const ROLE_KEY: Record<string, keyof DragonColors> = { skin: 'scales', membrane: 'membrane', eye: 'eye' };

const HUE_GLSL = `
uniform vec3 b8Hue;
vec3 b8Shift(vec3 c, vec3 k) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  vec3 hsv = vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
  hsv.x = fract(hsv.x + k.x);
  hsv.y = clamp(hsv.y * k.y, 0.0, 1.0);
  hsv.z = hsv.z * k.z;
  vec3 r = clamp(abs(fract(hsv.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
  return hsv.z * mix(vec3(1.0), r, hsv.y);
}
`;

/** Rotate a textured material's colours from `from` to `to` (hue; saturation and value scaled). */
export function hueShift(m: THREE.MeshStandardMaterial, from: string, to: string) {
  const a = { h: 0, s: 0, l: 0 };
  const b = { h: 0, s: 0, l: 0 };
  new THREE.Color(from).getHSL(a);
  new THREE.Color(to).getHSL(b);
  const k = new THREE.Vector3(b.h - a.h, Math.min(2, b.s / Math.max(a.s, 0.01)), Math.min(2.5, Math.max(0.3, b.l / Math.max(a.l, 0.01))));
  // one program per shift: a program three reuses doesn't run onBeforeCompile again, and
  // the material would go without its uniform
  const uniform = { value: k };
  m.userData.b8Hue = uniform;
  m.onBeforeCompile = (sh: any) => {
    sh.uniforms.b8Hue = uniform;
    sh.fragmentShader = HUE_GLSL + sh.fragmentShader
      .replace('#include <map_fragment>', '#include <map_fragment>\n  diffuseColor.rgb = b8Shift(diffuseColor.rgb, b8Hue);')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n  totalEmissiveRadiance = b8Shift(totalEmissiveRadiance, b8Hue);');
  };
  const key = 'b8hue:' + k.toArray().map((x: number) => x.toFixed(3)).join(',');
  m.customProgramCacheKey = () => key;
  m.needsUpdate = true;
}

type Template = { scene: THREE.Object3D; clips: THREE.AnimationClip[] };

export class DragonFactory {
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
          modelUrl(DRAGON_GLB),
          (g: any) => resolve({ scene: g.scene, clips: (g.animations || []) as THREE.AnimationClip[] }),
          undefined,
          (err: unknown) => {
            console.warn('[dragon] model failed to load', err);
            resolve(null);
          }
        );
      });
    }
    return this.tpl;
  }

  /** A new dragon `scale` times full size (about 16.7 m nose to tail at 1). */
  async create(scale: number, colors?: DragonColors): Promise<DragonRig | null> {
    const t = await this.load();
    if (!t) return null;
    return new DragonRig(t, scale, colors);
  }
}

export class DragonRig {
  readonly root = new THREE.Group();
  readonly model: THREE.Object3D;
  readonly scale: number;
  /** The rider's seat and the mouth (bones of the rig). */
  readonly saddle: THREE.Object3D | null;
  readonly mouth: THREE.Object3D | null;
  flying = false;
  dead = false;

  private mixer: THREE.AnimationMixer;
  private actions = new Map<string, THREE.AnimationAction>();
  private base: string | null = null;
  private shot: { name: string; action: THREE.AnimationAction; until: number; hold: boolean } | null = null;
  private time = 0;
  private last = new THREE.Vector3();
  private seen = false;
  private speed = 0; // m/s, eased
  private climb = 0; // m/s, eased
  private materials: THREE.Material[] = [];
  /**
   * Called at each wing beat (flying or hovering: the middle of the downstroke) and each
   * footfall (walking or running), so the owner can sound them. `strength` 0..1.
   */
  onCycle: ((kind: 'wing' | 'step', strength: number) => void) | null = null;
  private cyclePhase = 0;
  private cycleClip = '';

  constructor(t: Template, scale: number, colors?: DragonColors) {
    this.scale = scale;
    this.model = SkeletonUtils.clone(t.scene) as THREE.Object3D;
    this.model.scale.setScalar(UNITS_PER_METRE * scale);
    this.root.name = 'Dragon';
    this.root.add(this.model);
    this.model.traverse((o: any) => {
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
        o.frustumCulled = false; // animated bones leave the bind-pose bounds
        if (colors) {
          o.material = Array.isArray(o.material) ? o.material.map((m: THREE.Material) => this.tinted(m, colors)) : this.tinted(o.material, colors);
        }
      }
    });
    this.saddle = this.model.getObjectByName('saddle') || null;
    this.mouth = this.model.getObjectByName('mouth') || null;
    this.mixer = new THREE.AnimationMixer(this.model);
    for (const c of t.clips) this.actions.set(c.name, this.mixer.clipAction(c));
    this.setBase('Idle_Loop', 0);
  }

  private tinted(m: THREE.Material, colors: DragonColors): THREE.Material {
    const role = (m.name || '').replace(/^Dragon_/, '').toLowerCase();
    const hex = colors[(ROLE_KEY[role] ?? role) as keyof DragonColors];
    if (!hex) return m;
    const c = (m as THREE.MeshStandardMaterial).clone();
    if (BOSS_HUE[role] && (c.map || c.emissiveMap)) {
      hueShift(c, BOSS_HUE[role], hex);
    } else {
      c.color.set(hex);
      if (role === 'eye') c.emissive?.set(hex);
    }
    this.materials.push(c);
    return c;
  }

  has(name: string): boolean {
    return this.actions.has(name);
  }

  /** Seconds a one-shot lasts at rate 1 (0 if the clip is missing). */
  duration(name: string): number {
    return this.actions.get(name)?.getClip().duration ?? 0;
  }

  private setBase(name: string, fade = 0.35) {
    if (this.base === name) return;
    const next = this.actions.get(name);
    if (!next) return;
    const prev = this.base ? this.actions.get(this.base) : null;
    next.reset();
    next.setLoop(THREE.LoopRepeat, Infinity);
    next.enabled = true;
    next.setEffectiveWeight(1);
    if (prev && fade > 0 && !this.shot) next.crossFadeFrom(prev, fade, true);
    else if (prev) prev.stop();
    next.play();
    this.base = name;
  }

  /** A one-shot over the locomotion (it fades back when done). `hold` keeps the last frame (death). */
  play(name: string, opts: { rate?: number; hold?: boolean; fade?: number } = {}): number {
    const a = this.actions.get(name);
    if (!a) return 0;
    const rate = opts.rate ?? 1;
    if (this.shot && this.shot.action !== a) this.shot.action.fadeOut(0.15);
    a.reset();
    a.setLoop(THREE.LoopOnce, 1);
    a.clampWhenFinished = true;
    a.timeScale = rate;
    a.enabled = true;
    a.setEffectiveWeight(1);
    a.fadeIn(opts.fade ?? 0.15);
    a.play();
    const base = this.base ? this.actions.get(this.base) : null;
    base?.fadeOut(opts.fade ?? 0.15);
    const dur = a.getClip().duration / rate;
    this.shot = { name, action: a, until: this.time + dur, hold: !!opts.hold };
    return dur;
  }

  die(instant = false) {
    this.dead = true;
    const d = this.play('Death', { hold: true, fade: instant ? 0 : 0.2 });
    if (instant && this.shot) this.shot.action.time = d;
  }

  revive() {
    this.dead = false;
    if (this.shot) this.shot.action.fadeOut(0.3);
    this.shot = null;
    const b = this.base;
    this.base = null;
    this.setBase(b || 'Idle_Loop', 0.3);
  }

  /** Per frame: locomotion from how the parent moves, then the mixer. */
  update(dt: number) {
    this.time += dt;
    const U = UNITS_PER_METRE;
    const p = new THREE.Vector3();
    this.root.getWorldPosition(p);
    if (this.seen && dt > 0) {
      const v = Math.hypot(p.x - this.last.x, p.z - this.last.z) / dt / U;
      const vy = (p.y - this.last.y) / dt / U;
      const k = Math.min(1, dt * 6);
      this.speed += (Math.min(v, 60) - this.speed) * k;
      this.climb += (Math.max(-30, Math.min(30, vy)) - this.climb) * k;
    }
    this.last.copy(p);
    this.seen = true;

    if (this.shot && !this.shot.hold && this.time >= this.shot.until) {
      this.shot.action.fadeOut(0.25);
      this.shot = null;
      const b = this.base ? this.actions.get(this.base) : null;
      if (b) {
        b.enabled = true;
        b.fadeIn(0.25);
        b.play();
      }
    }
    if (!this.dead) {
      const s = this.scale;
      let name: string;
      let rate = 1;
      if (this.flying) {
        if (this.speed < 2.5 * Math.max(s, 0.3)) name = 'Hover_Loop';
        else if (this.climb < -2 && this.speed > 6) name = 'Glide_Loop';
        else {
          name = 'Fly_Loop';
          rate = THREE.MathUtils.clamp(0.8 + this.climb * 0.04, 0.7, 1.4);
        }
      } else if (this.speed < 0.35) {
        name = 'Idle_Loop';
      } else if (this.speed < WALK_REF * s * 1.6) {
        name = 'Walk_Loop';
        rate = THREE.MathUtils.clamp(this.speed / (WALK_REF * s), 0.5, 2.2);
      } else {
        name = 'Run_Loop';
        rate = THREE.MathUtils.clamp(this.speed / (RUN_REF * s), 0.6, 2.4);
      }
      if (!this.shot) this.setBase(name);
      else if (this.base !== name) {
        // switch underneath the one-shot, quietly
        const prev = this.base ? this.actions.get(this.base) : null;
        prev?.stop();
        this.base = null;
        this.setBase(name, 0);
        this.actions.get(name)?.setEffectiveWeight(0);
      }
      const a = this.base ? this.actions.get(this.base) : null;
      if (a) a.timeScale = rate;
    }
    this.mixer.update(dt);
    this.cycleSounds();
  }

  // Wing beats and footfalls from where the locomotion loop is in its cycle. The flight
  // loops lift the wings to the top a quarter of the way in (build_dragon.py: the wing's
  // roll is -(bias + amp sin t)), so the downstroke's push of air is just before halfway.
  private cycleSounds() {
    const name = this.base;
    const a = name ? this.actions.get(name) : null;
    if (!this.onCycle || this.dead || !a || !name) return;
    const d = a.getClip().duration;
    if (!(d > 0)) return;
    const ph = (((a.time % d) + d) % d) / d;
    if (name !== this.cycleClip) {
      this.cycleClip = name;
      this.cyclePhase = ph;
      return;
    }
    const crossed = (m: number) => (ph >= this.cyclePhase ? this.cyclePhase < m && m <= ph : this.cyclePhase < m || m <= ph);
    if (name === 'Fly_Loop' || name === 'Hover_Loop') {
      if (crossed(0.42)) this.onCycle('wing', name === 'Hover_Loop' ? 1 : 0.8);
    } else if (name === 'Walk_Loop' || name === 'Run_Loop') {
      const s = Math.min(1, this.speed / (RUN_REF * Math.max(this.scale, 0.3)));
      if (crossed(0.02) || crossed(0.52)) this.onCycle('step', 0.45 + 0.55 * s);
    }
    this.cyclePhase = ph;
  }

  /** The seat's position in `space`'s frame (for the rider), or null. */
  seatIn(space: THREE.Object3D, out = new THREE.Vector3()): THREE.Vector3 | null {
    if (!this.saddle) return null;
    this.saddle.getWorldPosition(out);
    return space.worldToLocal(out);
  }

  dispose() {
    this.mixer.stopAllAction();
    this.root.removeFromParent();
    for (const m of this.materials) m.dispose();
    this.materials = [];
  }
}

// ---------------------------------------------------------------------------
// Fire breath: additive sprites streaming from the mouth for a while.
// ---------------------------------------------------------------------------

let FLAME_TEX: THREE.Texture | null = null;
// One flame material per size, made once and never disposed (a new material of a kind is a shader
// to build; disposing the last one throws the program away).
const FLAME_MATS = new Map<number, THREE.PointsMaterial>();
function flameMaterial(size: number): THREE.PointsMaterial {
  let m = FLAME_MATS.get(size);
  if (!m) {
    m = new THREE.PointsMaterial({
      size,
      map: flameTexture(),
      vertexColors: true,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      sizeAttenuation: true,
    });
    FLAME_MATS.set(size, m);
  }
  return m;
}

function flameTexture(): THREE.Texture {
  if (FLAME_TEX) return FLAME_TEX;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d')!;
  const grd = g.createRadialGradient(32, 32, 2, 32, 32, 30);
  grd.addColorStop(0, 'rgba(255,250,220,1)');
  grd.addColorStop(0.25, 'rgba(255,200,80,0.95)');
  grd.addColorStop(0.6, 'rgba(240,90,20,0.5)');
  grd.addColorStop(1, 'rgba(120,20,0,0)');
  g.fillStyle = grd;
  g.fillRect(0, 0, 64, 64);
  FLAME_TEX = new THREE.CanvasTexture(c);
  return FLAME_TEX;
}

export class FireBreath {
  readonly points: THREE.Points;
  private n = 260;
  private pos: Float32Array;
  private col: Float32Array;
  private vel: Float32Array;
  private age: Float32Array;
  private life = 0.9;
  private emitting = 0; // seconds left to emit
  private next = 0;
  /** A light from the world's pool while the flame burns (light-pool.ts), else none. */
  private light: THREE.PointLight | null = null;
  private tmp = new THREE.Vector3();
  private dir = new THREE.Vector3();
  private back = new THREE.Vector3();

  /** `head` and `mouth`: the head bone and the mouth bone (the flame runs from one past the other). */
  constructor(private scene: THREE.Object3D, private mouth: THREE.Object3D, private head: THREE.Object3D, private reach: number, size: number) {
    this.pos = new Float32Array(this.n * 3);
    this.col = new Float32Array(this.n * 3);
    this.vel = new Float32Array(this.n * 3);
    this.age = new Float32Array(this.n).fill(99);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.col, 3));
    this.points = new THREE.Points(geo, flameMaterial(size));
    this.points.frustumCulled = false;
    this.points.name = 'FireBreath';
    // NO LIGHT OF ITS OWN (2026-10-30): adding one to the scene made every lit material recompile,
    // which was the long freeze on a drake's first breath. It borrows a pooled one while it burns.
    scene.add(this.points);
  }

  /** Breathe for `seconds`. */
  start(seconds: number) {
    this.emitting = seconds;
    if (!this.light) this.light = LightPool.get()?.take(0xff8a30, 0, this.reach * 0.9) ?? null;
  }

  get active(): boolean {
    return this.emitting > 0 || this.age.some((a) => a < this.life);
  }

  update(dt: number) {
    this.mouth.getWorldPosition(this.tmp);
    this.head.getWorldPosition(this.back);
    this.dir.copy(this.tmp).sub(this.back).normalize();
    const speed = this.reach / this.life;
    if (this.emitting > 0) {
      this.emitting -= dt;
      this.next -= dt;
      const per = 1 / 280;
      while (this.next <= 0) {
        this.next += per;
        let i = this.age.findIndex((a) => a >= this.life);
        if (i < 0) break;
        this.age[i] = 0;
        this.pos[i * 3] = this.tmp.x;
        this.pos[i * 3 + 1] = this.tmp.y;
        this.pos[i * 3 + 2] = this.tmp.z;
        const s = speed * (0.75 + Math.random() * 0.5);
        const spread = 0.22;
        this.vel[i * 3] = (this.dir.x + (Math.random() - 0.5) * spread) * s;
        this.vel[i * 3 + 1] = (this.dir.y + (Math.random() - 0.5) * spread) * s;
        this.vel[i * 3 + 2] = (this.dir.z + (Math.random() - 0.5) * spread) * s;
      }
    }
    let lit = 0;
    for (let i = 0; i < this.n; i++) {
      if (this.age[i] >= this.life) {
        this.col[i * 3] = this.col[i * 3 + 1] = this.col[i * 3 + 2] = 0;
        continue;
      }
      this.age[i] += dt;
      const k = this.age[i] / this.life;
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt + k * 0.8 * dt; // embers rise
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      const f = Math.max(0, 1 - k);
      this.col[i * 3] = 1.0 * f;
      this.col[i * 3 + 1] = (0.75 - 0.5 * k) * f;
      this.col[i * 3 + 2] = (0.35 - 0.33 * k) * f;
      lit++;
    }
    (this.points.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    (this.points.geometry.attributes.color as THREE.BufferAttribute).needsUpdate = true;
    if (this.light) {
      this.light.position.copy(this.tmp).addScaledVector(this.dir, this.reach * 0.3);
      this.light.intensity = this.emitting > 0 ? 40 + Math.random() * 25 : Math.max(0, this.light.intensity - dt * 120);
      // burnt out: the light goes back to the pool
      if (!lit && this.emitting <= 0) {
        LightPool.get()?.give(this.light);
        this.light = null;
      }
    }
  }

  dispose() {
    this.scene.remove(this.points);
    LightPool.get()?.give(this.light);
    this.light = null;
    this.points.geometry.dispose();
    // the material is shared (flameMaterial) and kept
  }
}
