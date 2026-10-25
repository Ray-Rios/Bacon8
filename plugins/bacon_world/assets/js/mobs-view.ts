// The creatures the zone runs (BaconWorld.Mobs.Zone), drawn on the client: skeletons
// (/models/Mobs/B8_Skeleton.glb, rigid on the MakeHuman male's armature since 2026-10-24,
// so they share his animation packs, /models/Humans/Anims/B8_Male_Anims_*) holding the weapons they will drop, with EverQuest names over
// their heads coloured by how tough they are to you.
//
// The server sends a snapshot on entering ("fetch_mobs"), events as they happen
// ("mob_events": spawn, aggro, attack, damaged, died, corpse, gone) and positions
// with velocities five times a second ("mob_motion"); between updates a creature
// is extrapolated along its velocity and eased toward that, so it doesn't stutter.
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, MeshoptDecoder, SkeletonUtils } from '../../../../assets/js/vendor/three-loaders';
import { modelUrl } from './asset-url';
import { applySurfaces } from './surface-textures';
import { CharacterAnimator } from './anim-driver';
import { UNITS_PER_METRE } from './controls-math';
import type { HumanFactory } from './human-factory';
import { WeaponModels, gearOf, holdItem } from './items';
import { Nameplates, conColor } from './nameplates';
import { DRAGON_HIT_AT, DRAGON_MOVE_CLIP, DragonFactory, DragonRig, FireBreath } from './dragon-view';

export const MOBS_BASE = '/models/Mobs';
const MODELS: Record<string, string> = {
  decaying_skeleton: 'B8_Skeleton.glb',
  skeleton: 'B8_Skeleton.glb',
  skeleton_warrior: 'B8_Skeleton.glb',
};
// Kinds drawn with the dragon (dragon-view.ts) instead of a skeleton on the male's packs.
const DRAGONS = new Set(['baconator']);
// Size by kind (the warriors are a little bigger).
const SCALE: Record<string, number> = { decaying_skeleton: 0.97, skeleton: 1.0, skeleton_warrior: 1.07 };

export interface MobView {
  id: string;
  kind: string;
  name: string;
  level: number;
  hp: number;
  max_hp: number;
  x: number;
  z: number;
  h: number;
  state: string;
  weapon: string | null;
  offhand: string | null;
  target: string | null;
  corpse: { owner: string | null; empty: boolean } | null;
  boss?: boolean;
  scale?: number;
}

export interface MobEvent {
  t: 'spawn' | 'aggro' | 'attack' | 'damaged' | 'died' | 'gone' | 'corpse' | 'cast' | 'rooted';
  /** rooted: for how long (ms). */
  ms?: number;
  /** attack and cast: what the creature does ("bite", "claw", "tail", "breath"). */
  move?: string;
  id?: string;
  mob?: MobView;
  target?: string;
  hit?: boolean;
  damage?: number;
  by?: string;
  crit?: boolean;
  hp?: number;
  max_hp?: number;
  killer?: string | null;
  corpse?: { owner: string | null; empty: boolean } | null;
  looter?: string | null;
}

export interface MobEntry {
  view: MobView;
  root: THREE.Group;
  model: THREE.Object3D | null;
  mixer: THREE.AnimationMixer | null;
  animator: CharacterAnimator | null;
  /** The dragon's rig and its fire, for the dragon kinds. */
  dragon: DragonRig | null;
  fire: FireBreath | null;
  proxy: THREE.Mesh;
  net: { x: number; z: number; h: number; vx: number; vz: number; at: number };
  speed: number;
  rise: number; // seconds left of rising out of the ground (0 = done)
  sink: number; // seconds left of sinking away (-1 = not sinking)
  heightU: number;
}

const PROXY_STANDING = new THREE.CylinderGeometry(0.38, 0.38, 1.85, 8).translate(0, 0.92, 0);
const PROXY_LYING = new THREE.BoxGeometry(0.8, 0.5, 2.2).translate(0, 0.25, 0);
// The dragon at full size (metres; scaled with it): its body and neck, not the tail's end.
const PROXY_DRAGON = new THREE.BoxGeometry(4.2, 5.6, 13).translate(0, 2.8, 1.2);
const PROXY_DRAGON_LYING = new THREE.BoxGeometry(5, 3, 13).translate(0, 1.5, 1.2);
const PROXY_MAT = new THREE.MeshBasicMaterial({ visible: false });

export class MobsView {
  readonly group = new THREE.Group();
  readonly nameplateIds = new Set<string>();
  /** Called for every event after the view has applied it (sounds, text, chat). */
  onEvent: ((e: MobEvent, mob: MobEntry | undefined) => void) | null = null;
  /** A creature's swing lands now (its animation reached the impact). */
  onSwingLanded: ((e: MobEvent, mob: MobEntry) => void) | null = null;
  /** The dragon's voice, breath, wing beats and footfalls, from where it is (lobby-audio.ts kinds). */
  onSound: ((kind: string, at: THREE.Vector3, gain?: number) => void) | null = null;

  private mobs = new Map<string, MobEntry>();
  private loader: GLTFLoader;
  private templates = new Map<string, Promise<THREE.Object3D | null>>();
  private clips: Promise<THREE.AnimationClip[]>;
  private pending: Array<{ at: number; fn: () => void }> = [];
  private time = 0;
  private dragons = new DragonFactory();

  constructor(
    private humans: HumanFactory,
    private weapons: WeaponModels,
    private nameplates: Nameplates,
    private me: () => { id: string | null; level: number; targetId: string | null }
  ) {
    this.group.name = 'Mobs';
    this.loader = new GLTFLoader();
    this.loader.setMeshoptDecoder(MeshoptDecoder);
    this.clips = humans.loadAnimPacks('Male');
  }

  // ---------------------------------------------------------------- updates from the server

  /** The full list (on entering the zone): adds, updates and removes. */
  setAll(list: MobView[]) {
    const keep = new Set(list.map((m) => m.id));
    for (const id of [...this.mobs.keys()]) if (!keep.has(id)) this.remove(id);
    for (const v of list) {
      const e = this.mobs.get(v.id);
      if (e) this.applyView(e, v);
      else this.add(v, false);
    }
  }

  motion(list: Array<[string, number, number, number, number, number]>) {
    const now = this.time;
    for (const [id, x, z, h, vx, vz] of list) {
      const e = this.mobs.get(id);
      if (!e || e.view.state === 'dead') continue;
      e.net = { x, z, h, vx, vz, at: now };
    }
  }

  event(ev: MobEvent) {
    const id = ev.id ?? ev.mob?.id;
    let e = id ? this.mobs.get(id) : undefined;
    switch (ev.t) {
      case 'spawn':
        if (ev.mob) {
          if (e) this.remove(ev.mob.id);
          e = this.add(ev.mob, true);
        }
        break;
      case 'aggro':
        if (e) {
          e.view.target = ev.target ?? null;
          if (e.dragon && e.view.state !== 'dead') {
            e.dragon.play('Roar');
            const at = e.root.position;
            setTimeout(() => this.onSound?.('dragon_roar', at, 1), 250);
          }
        }
        break;
      case 'attack':
        if (e && e.view.state !== 'dead') {
          const entry = e;
          if (e.dragon) {
            // the breath's burn comes after its cast (the clip is already playing)
            if (ev.move === 'breath') {
              this.onSwingLanded?.(ev, entry);
              break;
            }
            const clip = DRAGON_MOVE_CLIP[ev.move || 'bite'] || 'Bite';
            e.dragon.play(clip, { rate: 1.15 });
            if (Math.random() < 0.6) this.onSound?.('dragon_growl', e.root.position, 0.8);
            this.pending.push({ at: this.time + (DRAGON_HIT_AT[clip] ?? 0.5) / 1.15, fn: () => this.onSwingLanded?.(ev, entry) });
            break;
          }
          const info = e.animator?.attack('right', false, 2.0);
          const at = this.time + (info?.hitIn ?? 0.3);
          this.pending.push({ at, fn: () => this.onSwingLanded?.(ev, entry) });
        }
        break;
      case 'cast':
        if (e?.dragon && ev.move === 'breath' && e.view.state !== 'dead') {
          e.dragon.play('Breath');
          const entry = e;
          this.pending.push({ at: this.time + 0.7, fn: () => this.onSound?.('dragon_breath', entry.root.position, 1) });
          // the flame from the blast in the clip (0.3 of 2.6 s) to its end
          this.pending.push({ at: this.time + 0.8, fn: () => entry.fire?.start(1.35) });
        }
        break;
      case 'damaged':
        if (e) {
          if (typeof ev.hp === 'number') e.view.hp = ev.hp;
          if (typeof ev.max_hp === 'number') e.view.max_hp = ev.max_hp;
          if ((ev.damage ?? 0) > 0 && (ev.hp ?? 1) > 0) e.animator?.hit();
          // a boss flinches now and then, not at every scratch
          if (e.dragon && (ev.damage ?? 0) > 0 && (ev.hp ?? 1) > 0 && Math.random() < 0.15) {
            e.dragon.play('Hit');
            this.onSound?.('dragon_hurt', e.root.position, 0.9);
          }
        }
        break;
      case 'died':
        if (e) {
          e.view.state = 'dead';
          e.view.hp = 0;
          e.view.target = null;
          e.view.corpse = { owner: ev.killer ?? null, empty: false };
          e.animator?.die();
          if (e.dragon) {
            this.onSound?.('dragon_roar', e.root.position, 0.8);
            const at = e.root.position;
            setTimeout(() => this.onSound?.('land_hard', at, 1), 1400);
          }
          e.dragon?.die();
          e.proxy.geometry = e.dragon ? PROXY_DRAGON_LYING : PROXY_LYING;
        }
        break;
      case 'corpse':
        if (e && ev.corpse !== undefined) e.view.corpse = ev.corpse;
        break;
      case 'gone':
        if (e) e.sink = 1.4;
        break;
    }
    this.onEvent?.(ev, e);
  }

  /** Every creature, live or dead. */
  all(): IterableIterator<MobEntry> {
    return this.mobs.values();
  }

  // ---------------------------------------------------------------- per frame

  update(dt: number) {
    this.time += dt;
    if (this.pending.length) {
      const due = this.pending.filter((p) => p.at <= this.time);
      this.pending = this.pending.filter((p) => p.at > this.time);
      due.forEach((p) => p.fn());
    }
    const me = this.me();
    const U = UNITS_PER_METRE;
    for (const [id, e] of [...this.mobs]) {
      // Position: extrapolate the last update (at most 0.35 s), then ease toward it.
      const n = e.net;
      if (e.view.state !== 'dead') {
        const ahead = Math.min(0.35, this.time - n.at);
        const tx = n.x + n.vx * ahead;
        const tz = n.z + n.vz * ahead;
        const k = 1 - Math.exp(-dt * 10);
        const px = e.root.position.x;
        const pz = e.root.position.z;
        e.root.position.x += (tx - px) * k;
        e.root.position.z += (tz - pz) * k;
        const moved = Math.hypot(e.root.position.x - px, e.root.position.z - pz) / Math.max(dt, 1e-4) / U;
        e.speed += (moved - e.speed) * Math.min(1, dt * 8);
        // Face the way the server says, smoothly.
        const want = n.h;
        let d = want - e.root.rotation.y;
        while (d > Math.PI) d -= Math.PI * 2;
        while (d < -Math.PI) d += Math.PI * 2;
        e.root.rotation.y += d * Math.min(1, dt * 10);
        // Movement relative to facing, for strafes and backpedals.
        const sp = Math.hypot(n.vx, n.vz);
        let dirX = 0;
        let dirZ = 1;
        if (sp > 1e-3) {
          const hh = e.root.rotation.y;
          dirZ = (n.vx * Math.sin(hh) + n.vz * Math.cos(hh)) / sp;
          dirX = (-n.vx * Math.cos(hh) + n.vz * Math.sin(hh)) / sp;
        }
        e.animator?.setMotion({ speed: e.speed < 0.15 ? 0 : e.speed, dirX, dirZ, grounded: true });
      }
      // Rising out of the ground, or sinking into it.
      if (e.rise > 0) {
        e.rise = Math.max(0, e.rise - dt);
        e.root.position.y = -1.9 * U * (e.rise / 1.4) ** 2;
      }
      if (e.sink >= 0) {
        e.sink -= dt;
        e.root.position.y = -0.9 * U * (1 - Math.max(0, e.sink) / 1.4);
        if (e.sink <= 0) {
          this.remove(id);
          continue;
        }
      }
      e.animator?.update(dt);
      e.mixer?.update(dt);
      e.dragon?.update(dt);
      e.fire?.update(dt);
      // The name: con colour, a corpse in grey.
      const plateId = `mob:${id}`;
      const dead = e.view.state === 'dead';
      this.nameplates.set(
        plateId,
        e.root,
        { name: dead ? `${e.view.name}'s corpse` : e.view.name, color: dead ? '#B9B2A6' : conColor(e.view.level - me.level, me.level) },
        { height: dead ? (e.dragon ? 2.6 * (e.view.scale ?? 1) * U : 0.6 * U) : e.heightU, target: me.targetId === id }
      );
    }
  }

  // ---------------------------------------------------------------- queries

  get(id: string): MobEntry | undefined {
    return this.mobs.get(id);
  }

  entries(): MobEntry[] {
    return [...this.mobs.values()];
  }

  /** The creature (or corpse) under a ray. */
  pick(raycaster: THREE.Raycaster): string | null {
    const proxies = [...this.mobs.values()].map((e) => e.proxy);
    const hit = raycaster.intersectObjects(proxies, false)[0];
    return (hit?.object.userData.mobId as string) || null;
  }

  /** The nearest corpse within `range` world units of a point. */
  nearestCorpse(x: number, z: number, range: number): MobEntry | null {
    let best: MobEntry | null = null;
    let bd = range;
    for (const e of this.mobs.values()) {
      if (e.view.state !== 'dead' || e.sink >= 0) continue;
      const d = Math.hypot(e.root.position.x - x, e.root.position.z - z);
      if (d <= bd) {
        bd = d;
        best = e;
      }
    }
    return best;
  }

  /** Living creatures, nearest first (Tab targeting). */
  living(x: number, z: number, range: number): MobEntry[] {
    return [...this.mobs.values()]
      .filter((e) => e.view.state !== 'dead' && Math.hypot(e.root.position.x - x, e.root.position.z - z) <= range)
      .sort((a, b) => Math.hypot(a.root.position.x - x, a.root.position.z - z) - Math.hypot(b.root.position.x - x, b.root.position.z - z));
  }

  clear() {
    for (const id of [...this.mobs.keys()]) this.remove(id);
    this.pending = [];
  }

  // ---------------------------------------------------------------- internals

  private template(kind: string): Promise<THREE.Object3D | null> {
    const file = MODELS[kind] || 'B8_Skeleton.glb';
    let p = this.templates.get(file);
    if (!p) {
      p = new Promise((resolve) => {
        this.loader.load(
          modelUrl(`${MOBS_BASE}/${file}`),
          (g: any) => {
            applySurfaces(g.scene, 'mobs');
            resolve(g.scene);
          },
          undefined,
          (err: unknown) => {
            console.warn('[mobs] model failed to load', file, err);
            resolve(null);
          }
        );
      });
      this.templates.set(file, p);
    }
    return p;
  }

  private add(v: MobView, rise: boolean): MobEntry {
    const root = new THREE.Group();
    root.name = `mob:${v.id}`;
    root.position.set(v.x, 0, v.z);
    root.rotation.y = v.h;
    const dragon = DRAGONS.has(v.kind);
    const scale = dragon ? v.scale ?? 1 : SCALE[v.kind] ?? 1;
    const proxy = new THREE.Mesh(
      dragon ? (v.state === 'dead' ? PROXY_DRAGON_LYING : PROXY_DRAGON) : v.state === 'dead' ? PROXY_LYING : PROXY_STANDING,
      PROXY_MAT
    );
    proxy.userData.mobId = v.id;
    proxy.scale.setScalar(UNITS_PER_METRE * scale);
    root.add(proxy);
    this.group.add(root);
    const e: MobEntry = {
      view: { ...v },
      root,
      model: null,
      mixer: null,
      animator: null,
      dragon: null,
      fire: null,
      proxy,
      net: { x: v.x, z: v.z, h: v.h, vx: 0, vz: 0, at: this.time },
      speed: 0,
      rise: rise ? 1.4 : 0,
      sink: -1,
      heightU: dragon ? (7.6 * scale + 0.6) * UNITS_PER_METRE : (1.8 * scale + 0.3) * UNITS_PER_METRE,
    };
    if (rise) root.position.y = -1.9 * UNITS_PER_METRE;
    this.mobs.set(v.id, e);
    this.nameplateIds.add(`mob:${v.id}`);
    void this.dress(e, scale);
    return e;
  }

  // Loads the model, then the animations and the weapons, into an entry.
  private async dress(e: MobEntry, scale: number) {
    if (DRAGONS.has(e.view.kind)) {
      const rig = await this.dragons.create(scale);
      if (!rig || this.mobs.get(e.view.id) !== e) {
        rig?.dispose();
        return;
      }
      e.root.add(rig.root);
      e.dragon = rig;
      rig.onCycle = (kind, strength) => this.onSound?.(kind === 'wing' ? 'wing_flap' : 'dragon_step', e.root.position, strength);
      e.model = rig.model;
      const head = rig.model.getObjectByName('head');
      if (rig.mouth && head) e.fire = new FireBreath(this.group, rig.mouth, head, 17 * scale * UNITS_PER_METRE, 1.6 * scale * UNITS_PER_METRE);
      if (e.view.state === 'dead') rig.die(true);
      return;
    }
    const tpl = await this.template(e.view.kind);
    if (!tpl || this.mobs.get(e.view.id) !== e) return;
    const model = SkeletonUtils.clone(tpl) as THREE.Object3D;
    model.scale.setScalar(UNITS_PER_METRE * scale);
    model.traverse((o: any) => {
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
        // Animated bones move outside the bind-pose bounds.
        o.frustumCulled = false;
      }
    });
    e.root.add(model);
    e.model = model;
    e.mixer = new THREE.AnimationMixer(model);
    e.animator = new CharacterAnimator(model, e.mixer, []);
    const clips = await this.clips;
    if (this.mobs.get(e.view.id) !== e) return;
    e.animator.addClips(clips);
    this.applyGear(e);
    if (e.view.state === 'dead') e.animator.dieInstantly();
  }

  private applyGear(e: MobEntry) {
    if (!e.model || e.dragon) return;
    const twoHanded = gearOf(e.view.weapon)?.hands === 2;
    e.animator?.setGear(gearOf(e.view.weapon), twoHanded ? null : gearOf(e.view.offhand));
    void holdItem(this.weapons, e.model, 'main', e.view.weapon);
    void holdItem(this.weapons, e.model, 'off', twoHanded ? null : e.view.offhand);
  }

  private applyView(e: MobEntry, v: MobView) {
    const wasDead = e.view.state === 'dead';
    const gearChanged = e.view.weapon !== v.weapon || e.view.offhand !== v.offhand;
    e.view = { ...v };
    e.net = { x: v.x, z: v.z, h: v.h, vx: 0, vz: 0, at: this.time };
    if (gearChanged) this.applyGear(e);
    if (v.state === 'dead' && !wasDead) {
      e.animator?.dieInstantly();
      e.dragon?.die(true);
      e.proxy.geometry = e.dragon ? PROXY_DRAGON_LYING : PROXY_LYING;
    } else if (v.state !== 'dead' && wasDead) {
      e.animator?.revive();
      e.dragon?.revive();
      e.proxy.geometry = e.dragon ? PROXY_DRAGON : PROXY_STANDING;
    }
  }

  private remove(id: string) {
    const e = this.mobs.get(id);
    if (!e) return;
    this.group.remove(e.root);
    e.animator?.dispose();
    e.dragon?.dispose();
    e.fire?.dispose();
    // Geometry and materials are shared with the template and the weapons file.
    this.mobs.delete(id);
    this.nameplateIds.delete(`mob:${id}`);
    this.nameplates.remove(`mob:${id}`);
  }
}
