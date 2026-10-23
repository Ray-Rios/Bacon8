// Drives a Bacon8 human's (or skeleton's) animation from what it is doing: moving
// (with real strafe and backpedal clips), holding weapons, swinging them with either
// hand, getting hit, dying.
//
// The body is split into four channels, each with its own clip and cross-fades:
//
//   lower  root, pelvis and legs            locomotion, or a standing attack's footwork
//   torso  spine, neck, head                locomotion, stance, attacks
//   armL   left clavicle and everything below    the off-hand item's pose, or locomotion
//   armR   right clavicle and everything below   the main-hand weapon's pose, or locomotion
//
// So a character can run (lower, torso) holding a sword (armR) and a shield (armL),
// and swing with one hand while the other keeps its guard. Within a channel the
// weights always add up to 1, so no bone ever blends toward the bind pose.
//
// Left-hand attacks are the right-hand clips mirrored at load time (the B8 skeleton
// is symmetric: local rotations mirror as (x, -y, -z, w), positions as (-x, y, z),
// and _l/_r swap; checked against the baked Spell_Simple_Shoot_Mirror, worst 0.004).
//
// Clip names are the B8 animation packs' (anims.json). Until the packs load, the 20
// clips in the body file stand in.
import * as THREE from '../../../../assets/js/vendor/three';

export type Channel = 'lower' | 'torso' | 'armL' | 'armR';
export type Hand = 'left' | 'right';
const CHANNELS: Channel[] = ['lower', 'torso', 'armL', 'armR'];
const ALL = new Set<Channel>(CHANNELS);

/** The animation set an item is held with (anims.json "sets"). */
export type GearSet =
  | 'unarmed' | 'sword_1h' | 'axe_1h' | 'blunt_1h' | 'dagger' | 'two_hand' | 'polearm' | 'staff'
  | 'shield' | 'torch' | 'lantern';

export interface Gear {
  set: GearSet;
  /** Two-handed weapons fill both hands. */
  hands: 1 | 2;
}

export interface MotionInput {
  /** Horizontal speed, m/s. */
  speed: number;
  /** Movement direction relative to where the character faces: +x right, +z forward (unit, or 0,0). */
  dirX: number;
  dirZ: number;
  grounded: boolean;
  crouch?: boolean;
  sprint?: boolean;
}

export interface AttackInfo {
  /** Seconds from now to the moment of impact. */
  hitIn: number;
  /** Seconds the swing occupies its hand. */
  duration: number;
  clip: string;
}

// ---------------------------------------------------------------------------
// Clips
// ---------------------------------------------------------------------------

export const LOCO = {
  idle: 'Idle_Loop',
  walk: 'Walk_Loop',
  walkBack: 'Walk_Bwd_Loop',
  jog: 'Jog_Fwd_Loop',
  jogBack: 'Jog_Bwd_Loop',
  sprint: 'Sprint_Loop',
  strafeL: 'Strafe_L_Walk_Loop',
  strafeR: 'Strafe_R_Walk_Loop',
  strafeLFast: 'Strafe_L_Jog_Loop',
  strafeRFast: 'Strafe_R_Jog_Loop',
  crouchIdle: 'Crouch_Idle_Loop',
  crouchWalk: 'Crouch_Fwd_Loop',
  jumpAir: 'Jump_Loop',
  jumpLand: 'Jump_Land',
  death: 'Death01',
  hit: 'Hit_Chest',
} as const;

// The speed (m/s) each locomotion clip was authored at, so playback matches the feet.
const NOMINAL: Record<string, number> = {
  Walk_Loop: 1.45, Walk_Bwd_Loop: 1.3, Jog_Fwd_Loop: 3.9, Jog_Bwd_Loop: 3.3, Sprint_Loop: 6.2,
  Strafe_L_Walk_Loop: 1.4, Strafe_R_Walk_Loop: 1.4, Strafe_L_Jog_Loop: 3.6, Strafe_R_Jog_Loop: 3.6,
  Crouch_Fwd_Loop: 1.3,
};

// Below this a character walks; above PACE.jogUpTo-ish (or Shift) it sprints.
export const WALK_UP_TO = 2.3;
export const SPRINT_FROM = 5.6;
export const IDLE_BELOW = 0.3;

// Stand-ins while the packs load (the body file's own clips).
const FALLBACK: Record<string, string[]> = {
  Walk_Bwd_Loop: ['Walk_Loop'], Jog_Bwd_Loop: ['Jog_Fwd_Loop'],
  Strafe_L_Walk_Loop: ['Walk_Loop'], Strafe_R_Walk_Loop: ['Walk_Loop'],
  Strafe_L_Jog_Loop: ['Jog_Fwd_Loop'], Strafe_R_Jog_Loop: ['Jog_Fwd_Loop'],
  TwoHand_Idle_Loop: ['Sword_Idle'], Spear_Idle_Loop: ['Sword_Idle'], Staff_Idle_Loop: ['Sword_Idle'],
  Dagger_Idle_Loop: ['Sword_Idle'], Idle_Shield_Loop: ['Idle_Loop'], Idle_Torch_Loop: ['Idle_Loop'],
  Idle_Lantern_Loop: ['Idle_Loop'],
  Sword_Regular_B: ['Sword_Regular_A'], Punch_Cross: ['Punch_Jab'], Melee_Hook: ['Punch_Jab'],
  Dagger_Stab: ['Sword_Regular_A'], Dagger_Slash: ['Sword_Regular_A'],
  TwoHand_Slash_A: ['Sword_Regular_A'], TwoHand_Slash_B: ['Sword_Regular_A'], TwoHand_Overhead: ['Sword_Regular_A'],
  Spear_Thrust_A: ['Sword_Regular_A'], Spear_Thrust_B: ['Sword_Regular_A'], Spear_Sweep: ['Sword_Regular_A'],
  Staff_Bonk: ['Sword_Regular_A'], Staff_Slam: ['Sword_Regular_A'], Shield_Dash: ['Punch_Jab'],
  Staff_Guard_Loop: ['Sword_Idle'], QStaff_Sweep: ['Sword_Regular_A'],
  Hit_Head: ['Hit_Chest'], Jump_Land: [],
};

/** A weapon pose, and its swings. `hit` is the impact time in seconds (measured on the clips). */
interface Swing { clip: string; hit: number; rec?: string; }
interface StanceDef { idle: string; light: Swing[]; heavy?: Swing; }

const SWORD: StanceDef = {
  idle: 'Sword_Idle',
  light: [
    { clip: 'Sword_Regular_A', hit: 0.23, rec: 'Sword_Regular_A_Rec' },
    { clip: 'Sword_Regular_B', hit: 0.25, rec: 'Sword_Regular_B_Rec' },
  ],
  heavy: { clip: 'Sword_Attack', hit: 0.87 },
};

export const STANCES: Record<GearSet, StanceDef> = {
  // Right hand: the cross and the hook; the left-hand jab is its own clip.
  unarmed: { idle: 'Idle_Loop', light: [{ clip: 'Punch_Cross', hit: 0.3 }, { clip: 'Melee_Hook', hit: 0.28 }], heavy: { clip: 'Kick_Front', hit: 0.45 } },
  sword_1h: SWORD,
  axe_1h: SWORD,
  blunt_1h: SWORD,
  dagger: { idle: 'Dagger_Idle_Loop', light: [{ clip: 'Dagger_Stab', hit: 0.2 }, { clip: 'Dagger_Slash', hit: 0.18 }], heavy: { clip: 'Sword_Attack', hit: 0.87 } },
  two_hand: { idle: 'TwoHand_Idle_Loop', light: [{ clip: 'TwoHand_Slash_A', hit: 0.37 }, { clip: 'TwoHand_Slash_B', hit: 0.33 }], heavy: { clip: 'TwoHand_Overhead', hit: 0.65 } },
  polearm: { idle: 'Spear_Idle_Loop', light: [{ clip: 'Spear_Thrust_B', hit: 0.34 }, { clip: 'Spear_Thrust_A', hit: 0.59 }], heavy: { clip: 'Spear_Sweep', hit: 0.37 } },
  // The quarterstaff (the only "staff" item) is two-handed: its guard and a two-handed sweep.
  // (Staff_Idle_Loop and Staff_Slam are the one-handed magic staff's, for when one exists.)
  staff: { idle: 'Staff_Guard_Loop', light: [{ clip: 'Staff_Bonk', hit: 0.44 }], heavy: { clip: 'QStaff_Sweep', hit: 0.5 } },
  // Off-hand items. Left-hand clips: the shield bash and the jab are authored for the
  // left; anything else held left swings the right-hand clips mirrored.
  shield: { idle: 'Idle_Shield_Loop', light: [{ clip: 'Shield_Dash', hit: 0.22 }] },
  torch: { idle: 'Idle_Torch_Loop', light: [{ clip: 'Sword_Regular_A', hit: 0.23 }] },
  lantern: { idle: 'Idle_Lantern_Loop', light: [{ clip: 'Punch_Jab', hit: 0.2 }] },
};

// Clips authored for the left hand (not mirrored when swung left).
const LEFT_HANDED = new Set(['Punch_Jab', 'Shield_Dash', 'Idle_Shield_Loop', 'Idle_Torch_Loop', 'Idle_Lantern_Loop']);
const UNARMED_LEFT: Swing[] = [{ clip: 'Punch_Jab', hit: 0.2 }, { clip: 'Melee_Hook', hit: 0.28 }];

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested)
// ---------------------------------------------------------------------------

/** Swaps a bone name's side: hand_l <-> hand_r. */
export function mirrorBoneName(name: string): string {
  if (name.endsWith('_l')) return name.slice(0, -2) + '_r';
  if (name.endsWith('_r')) return name.slice(0, -2) + '_l';
  return name;
}

/** Mirrors one keyframe value in place: quaternions (x, y, z, w) -> (x, -y, -z, w), positions -> (-x, y, z). */
export function mirrorValues(prop: string, values: ArrayLike<number> & { [i: number]: number }): void {
  if (prop === 'quaternion') {
    for (let i = 0; i < values.length; i += 4) {
      values[i + 1] = -values[i + 1];
      values[i + 2] = -values[i + 2];
    }
  } else if (prop === 'position') {
    for (let i = 0; i < values.length; i += 3) values[i] = -values[i];
  }
}

/**
 * The locomotion clip for a motion. `dirX/dirZ` are relative to the character's
 * facing, so a character facing the camera while moving sideways strafes, and one
 * moving away from where it faces backpedals.
 */
export function locomotionClip(m: MotionInput): string {
  if (m.crouch) return m.speed < IDLE_BELOW ? LOCO.crouchIdle : LOCO.crouchWalk;
  if (m.speed < IDLE_BELOW) return LOCO.idle;
  const fast = m.speed >= WALK_UP_TO;
  const len = Math.hypot(m.dirX, m.dirZ);
  // No direction known: assume forward.
  const ang = len < 1e-3 ? 0 : Math.atan2(m.dirX, m.dirZ); // 0 = forward, +pi/2 = right
  const deg = (ang * 180) / Math.PI;
  if (Math.abs(deg) <= 50) {
    if (m.sprint || m.speed >= SPRINT_FROM) return LOCO.sprint;
    return fast ? LOCO.jog : LOCO.walk;
  }
  if (Math.abs(deg) >= 130) return fast ? LOCO.jogBack : LOCO.walkBack;
  if (deg > 0) return fast ? LOCO.strafeRFast : LOCO.strafeR;
  return fast ? LOCO.strafeLFast : LOCO.strafeL;
}

/** Playback rate for a locomotion clip at a speed (1 for anything that isn't locomotion). */
export function locomotionRate(clip: string, speed: number): number {
  const n = NOMINAL[clip];
  if (!n) return 1;
  return Math.min(1.6, Math.max(0.6, speed / n));
}

/** Which bones make up each channel, from the skeleton (children of clavicle_l are armL, ...). */
export function channelOfBones(root: THREE.Object3D): Map<string, Channel> {
  const map = new Map<string, Channel>();
  const mark = (o: THREE.Object3D, ch: Channel) => o.traverse((c) => { if (c.name && !map.has(c.name)) map.set(c.name, ch); });
  const cl = root.getObjectByName('clavicle_l');
  const cr = root.getObjectByName('clavicle_r');
  if (cl) mark(cl, 'armL');
  if (cr) mark(cr, 'armR');
  const spine = root.getObjectByName('spine_01');
  if (spine) mark(spine, 'torso');
  root.traverse((c) => { if (c.name && !map.has(c.name)) map.set(c.name, 'lower'); });
  return map;
}

// ---------------------------------------------------------------------------
// A channel: actions cross-fading, weights summing to 1
// ---------------------------------------------------------------------------

class ChannelLayer {
  private entries: Array<{ action: THREE.AnimationAction; w: number }> = [];
  current: THREE.AnimationAction | null = null;
  key = '';
  private fade = 0.2;

  /**
   * Fades `action` in over `fade` seconds. `restartAt` (seconds into the clip)
   * restarts it there even if it is already playing (a second swing of the same
   * clip); without it a playing action carries on and a new one starts at 0.
   */
  play(key: string, action: THREE.AnimationAction, fade: number, restartAt?: number, phase?: number) {
    this.key = key;
    if (this.current === action && restartAt === undefined) return;
    this.current = action;
    this.fade = Math.max(0, fade);
    let e = this.entries.find((x) => x.action === action);
    if (!e) {
      e = { action, w: 0 };
      this.entries.push(e);
      action.setEffectiveWeight(0);
      action.reset();
      action.time = restartAt ?? phase ?? 0;
      action.play();
    } else if (restartAt !== undefined) {
      // A finished one-shot is paused on its last frame; reset() lets it run again.
      action.reset();
      action.time = restartAt;
      action.play();
    }
    if (this.fade === 0) {
      this.entries.forEach((x) => (x.w = x === e ? 1 : 0));
    }
  }

  update(dt: number) {
    if (!this.current) return;
    const cur = this.entries.find((x) => x.action === this.current)!;
    cur.w = this.fade <= 0 ? 1 : Math.min(1, cur.w + dt / this.fade);
    const others = this.entries.filter((x) => x !== cur);
    const sum = others.reduce((s, x) => s + x.w, 0);
    const scale = sum > 0 ? (1 - cur.w) / sum : 0;
    for (const o of others) o.w *= scale;
    this.entries = this.entries.filter((x) => {
      if (x !== cur && x.w < 0.002) {
        x.action.stop();
        x.action.setEffectiveWeight(0);
        return false;
      }
      return true;
    });
    // A lone current action must carry the full weight.
    if (this.entries.length === 1) cur.w = 1;
    for (const x of this.entries) x.action.setEffectiveWeight(x.w);
  }

  stopAll() {
    for (const x of this.entries) x.action.stop();
    this.entries = [];
    this.current = null;
    this.key = '';
  }
}

// ---------------------------------------------------------------------------
// The animator
// ---------------------------------------------------------------------------

interface Override {
  clip: string;
  mirror: boolean;
  channels: Set<Channel>;
  start: number;
  duration: number;
  rate: number;
  fadeIn: number;
  /** Hold the last frame (death). */
  hold?: boolean;
  /** Played after this one ends, on the same channels (a swing's recovery). */
  then?: { clip: string; mirror: boolean } | null;
  hand?: Hand;
  /** An attack: its legs give way to locomotion when the character moves. */
  swing?: boolean;
}

export class CharacterAnimator {
  readonly root: THREE.Object3D;
  readonly mixer: THREE.AnimationMixer;
  private clips = new Map<string, THREE.AnimationClip>();
  private parts = new Map<string, THREE.AnimationClip>();
  private actions = new Map<string, THREE.AnimationAction>();
  private layers: Record<Channel, ChannelLayer> = { lower: new ChannelLayer(), torso: new ChannelLayer(), armL: new ChannelLayer(), armR: new ChannelLayer() };
  private bones: Map<string, Channel>;
  private time = 0;
  private motion: MotionInput = { speed: 0, dirX: 0, dirZ: 1, grounded: true };
  private main: Gear | null = null;
  private off: Gear | null = null;
  private overrides: Override[] = [];
  private combo: Record<Hand, { n: number; at: number }> = { left: { n: 0, at: -9 }, right: { n: 0, at: -9 } };
  private airborneFor = 0;
  private dead = false;

  constructor(root: THREE.Object3D, mixer: THREE.AnimationMixer, clips: Iterable<THREE.AnimationClip>) {
    this.root = root;
    this.mixer = mixer;
    this.bones = channelOfBones(root);
    this.addClips(clips);
  }

  /** More clips (an animation pack finished loading). Same names replace the stand-ins. */
  addClips(clips: Iterable<THREE.AnimationClip>) {
    for (const c of clips) if (c?.name) this.clips.set(c.name, c);
    // Re-resolve: a channel playing a stand-in picks up the real clip on its next change.
    for (const ch of CHANNELS) this.layers[ch].key = '';
  }

  hasClip(name: string): boolean {
    return this.clips.has(name);
  }

  get isDead(): boolean {
    return this.dead;
  }

  /**
   * Which hands are empty and not punching: those relax their fingers (human-factory's
   * postAnimate); the clips' own fingers (fists, grips) show otherwise.
   */
  freeHands(): { l: boolean; r: boolean } {
    let l = !this.off && this.main?.hands !== 2;
    let r = !this.main;
    for (const o of this.overrides) {
      if (!o.swing) continue;
      if (o.channels.has('armL')) l = false;
      if (o.channels.has('armR')) r = false;
    }
    return { l, r };
  }

  /** What the hands hold (null: empty). A two-handed main weapon empties the off hand. */
  setGear(main: Gear | null, off: Gear | null) {
    this.main = main;
    this.off = main?.hands === 2 ? null : off;
  }

  setMotion(m: MotionInput) {
    this.motion = m;
  }

  /**
   * Swings with a hand. Returns the impact time and how long the hand is busy, or
   * null while dead. `heavy` is the stronger attack (a two-hander's right button).
   * `delay` (seconds) is the weapon's swing time: a clip longer than that is sped up.
   */
  attack(hand: Hand, heavy = false, delay?: number): AttackInfo | null {
    if (this.dead) return null;
    const twoHanded = this.main?.hands === 2;
    const gear = hand === 'right' || twoHanded ? this.main : this.off;
    const set: GearSet = gear?.set ?? 'unarmed';
    const def = STANCES[set];
    let swings = hand === 'left' && set === 'unarmed' ? UNARMED_LEFT : def.light;
    if (heavy && def.heavy) swings = [def.heavy];
    // Successive swings within 1.6 s walk through the set (a combo), then start over.
    const c = this.combo[twoHanded ? 'right' : hand];
    c.n = this.time - c.at < 1.6 ? c.n + 1 : 0;
    c.at = this.time;
    const swing = swings[c.n % swings.length];
    const name = this.resolve(swing.clip);
    if (!name) return null;
    const clip = this.clips.get(name)!;
    const mirror = hand === 'left' && !twoHanded && !LEFT_HANDED.has(swing.clip);
    let rate = 1;
    if (delay && clip.duration > delay * 0.95) rate = clip.duration / (delay * 0.95);
    // Standing still, the whole body swings (footwork); moving, the legs keep running.
    const moving = this.motion.speed >= IDLE_BELOW || !this.motion.grounded;
    const channels = new Set<Channel>(['torso']);
    // The swinging arm, and the other one too when it holds nothing or shares the weapon.
    channels.add(hand === 'left' ? 'armL' : 'armR');
    if (twoHanded) { channels.add('armL'); channels.add('armR'); }
    else if (hand === 'right' && !this.off) channels.add('armL');
    else if (hand === 'left' && !this.main) channels.add('armR');
    if (!moving) channels.add('lower');
    // A new swing on the same channels replaces the old one.
    this.overrides = this.overrides.filter((o) => o.hold || ![...o.channels].some((ch) => channels.has(ch)));
    const rec = swing.rec && this.clips.has(swing.rec) ? { clip: swing.rec, mirror } : null;
    this.overrides.push({ clip: name, mirror, channels, start: this.time, duration: clip.duration / rate, rate, fadeIn: 0.06, then: rec, hand, swing: true });
    return { hitIn: swing.hit / rate, duration: clip.duration / rate, clip: name };
  }

  /** A flinch on the upper body. */
  hit() {
    if (this.dead) return;
    const name = this.resolve(LOCO.hit);
    if (!name) return;
    // Don't interrupt a swing: only flinch the channels that are free.
    const busy = new Set<Channel>();
    this.overrides.forEach((o) => o.channels.forEach((ch) => busy.add(ch)));
    const channels = new Set<Channel>((['torso', 'armL', 'armR'] as Channel[]).filter((ch) => !busy.has(ch)));
    if (!channels.size) return;
    const clip = this.clips.get(name)!;
    this.overrides.push({ clip: name, mirror: false, channels, start: this.time, duration: clip.duration, rate: 1, fadeIn: 0.05 });
  }

  /** Plays a clip once on the whole body (an emote, looting, a cast). */
  oneShot(clipName: string, opts: { upperOnly?: boolean; mirror?: boolean; rate?: number } = {}): number {
    if (this.dead) return 0;
    const name = this.resolve(clipName);
    if (!name) return 0;
    const clip = this.clips.get(name)!;
    const rate = opts.rate ?? 1;
    const channels = opts.upperOnly ? new Set<Channel>(['torso', 'armL', 'armR']) : new Set(ALL);
    this.overrides = this.overrides.filter((o) => ![...o.channels].some((ch) => channels.has(ch)));
    this.overrides.push({ clip: name, mirror: !!opts.mirror, channels, start: this.time, duration: clip.duration / rate, rate, fadeIn: 0.12 });
    return clip.duration / rate;
  }

  die() {
    if (this.dead) return;
    this.dead = true;
    const name = this.resolve(LOCO.death);
    this.overrides = [];
    if (!name) return;
    const clip = this.clips.get(name)!;
    this.overrides.push({ clip: name, mirror: false, channels: new Set(ALL), start: this.time, duration: clip.duration, rate: 1, fadeIn: 0.15, hold: true });
  }

  /** Lies dead at once (a corpse seen on arrival). */
  dieInstantly() {
    this.die();
    const o = this.overrides[0];
    if (o) {
      o.start = this.time - o.duration;
      o.fadeIn = 0;
    }
  }

  revive() {
    this.dead = false;
    this.overrides = [];
  }

  update(dt: number) {
    this.time += dt;
    const m = this.motion;
    this.airborneFor = m.grounded ? 0 : this.airborneFor + dt;

    // Finished overrides fall away (or hand over to their follow-up).
    const next: Override[] = [];
    for (const o of this.overrides) {
      if (o.hold || this.time - o.start < o.duration) {
        next.push(o);
      } else if (o.then) {
        const name = this.resolve(o.then.clip);
        if (name) {
          const clip = this.clips.get(name)!;
          next.push({ clip: name, mirror: o.then.mirror, channels: o.channels, start: this.time, duration: clip.duration / o.rate, rate: o.rate, fadeIn: 0.05, hand: o.hand, swing: o.swing });
        }
      }
    }
    this.overrides = next;
    // Starting to move mid-swing hands the legs back to locomotion.
    if (this.motion.speed >= IDLE_BELOW || !this.motion.grounded) {
      for (const o of this.overrides) {
        if (o.swing && o.channels.has('lower')) {
          o.channels = new Set([...o.channels].filter((ch) => ch !== 'lower'));
        }
      }
    }

    // The base pose of each channel.
    const loco = locomotionClip(m);
    const moving = m.speed >= IDLE_BELOW;
    const air = !m.grounded && this.airborneFor > 0.12;
    const twoHanded = this.main?.hands === 2;
    const mainDef = this.main ? STANCES[this.main.set] : null;
    const offDef = this.off ? STANCES[this.off.set] : null;
    const legs = air ? LOCO.jumpAir : loco;
    const base: Record<Channel, { clip: string; mirror: boolean }> = {
      lower: { clip: legs, mirror: false },
      torso: { clip: legs, mirror: false },
      armL: { clip: legs, mirror: false },
      armR: { clip: legs, mirror: false },
    };
    if (!moving && !air && mainDef && !m.crouch) {
      // Standing with a weapon: its stance, whole body.
      for (const ch of CHANNELS) base[ch] = { clip: mainDef.idle, mirror: false };
    }
    if (mainDef) base.armR = { clip: mainDef.idle, mirror: false };
    if (twoHanded && mainDef) base.armL = { clip: mainDef.idle, mirror: false };
    if (offDef && this.off) {
      // The off hand's own pose; a one-handed weapon held left is its right pose mirrored.
      const authoredLeft = LEFT_HANDED.has(offDef.idle);
      base.armL = { clip: offDef.idle, mirror: !authoredLeft };
    }

    // Overrides win on their channels (latest first).
    const want = { ...base } as Record<Channel, { clip: string; mirror: boolean; o?: Override }>;
    for (const o of this.overrides) for (const ch of o.channels) want[ch] = { clip: o.clip, mirror: o.mirror, o };

    for (const ch of CHANNELS) {
      const w = want[ch];
      const name = this.resolve(w.clip);
      if (!name) continue;
      const key = `${name}|${w.mirror ? 'm' : ''}|${w.o ? w.o.start : ''}`;
      const layer = this.layers[ch];
      const action = this.action(name, ch, w.mirror);
      if (layer.key !== key) {
        if (w.o) {
          // One-shots hold their last frame while they fade out.
          action.setLoop(THREE.LoopOnce, 1);
          action.clampWhenFinished = true;
          action.timeScale = w.o.rate;
          layer.play(key, action, w.o.fadeIn, Math.max(0, (this.time - w.o.start) * w.o.rate));
        } else {
          action.setLoop(THREE.LoopRepeat, Infinity);
          action.clampWhenFinished = false;
          // Keep locomotion in step across channels and between directions.
          layer.play(key, action, 0.22, undefined, this.phaseFor(name, action));
        }
      }
      if (!w.o) action.timeScale = locomotionRate(name, m.speed);
      layer.update(dt);
    }
  }

  dispose() {
    for (const ch of CHANNELS) this.layers[ch].stopAll();
    this.mixer.stopAllAction();
    for (const a of this.actions.values()) this.mixer.uncacheAction(a.getClip(), this.root);
    for (const c of this.parts.values()) this.mixer.uncacheClip(c);
    this.actions.clear();
    this.parts.clear();
  }

  // -------------------------------------------------------------------------

  /** The clip to play for a name: itself, or a stand-in while the packs load. */
  private resolve(name: string): string | null {
    if (this.clips.has(name)) return name;
    for (const alt of FALLBACK[name] || []) if (this.clips.has(alt)) return alt;
    return this.clips.has(LOCO.idle) ? LOCO.idle : null;
  }

  // Where a locomotion clip should start so it stays in step with what already plays.
  private phaseFor(name: string, action: THREE.AnimationAction): number | undefined {
    const dur = action.getClip().duration;
    let best: THREE.AnimationAction | null = null;
    for (const ch of CHANNELS) {
      const cur = this.layers[ch].current;
      if (!cur || cur === action) continue;
      const c = cur.getClip();
      if (c.name.split('#')[0] === name) return (cur.time / c.duration) * dur;
      if (!best && NOMINAL[c.name.split('#')[0]] && NOMINAL[name]) best = cur;
    }
    if (best) return (best.time / best.getClip().duration) * dur;
    return undefined;
  }

  private action(name: string, ch: Channel, mirror: boolean): THREE.AnimationAction {
    const key = `${name}#${ch}${mirror ? '#m' : ''}`;
    let a = this.actions.get(key);
    if (!a) {
      a = this.mixer.clipAction(this.part(name, ch, mirror), this.root);
      this.actions.set(key, a);
    }
    return a;
  }

  // A clip cut down to one channel's bones (mirrored if asked), made once.
  private part(name: string, ch: Channel, mirror: boolean): THREE.AnimationClip {
    const key = `${name}#${ch}${mirror ? '#m' : ''}`;
    let c = this.parts.get(key);
    if (c) return c;
    const src = this.clips.get(name)!;
    const tracks: THREE.KeyframeTrack[] = [];
    for (const t of src.tracks) {
      const dot = t.name.lastIndexOf('.');
      const node = t.name.slice(0, dot);
      const prop = t.name.slice(dot + 1);
      if (prop === 'scale') continue; // the packs key scale at 1 throughout
      const target = mirror ? mirrorBoneName(node) : node;
      if ((this.bones.get(target) ?? 'lower') !== ch) continue;
      const tr = t.clone();
      tr.name = `${target}.${prop}`;
      if (mirror) {
        tr.values = tr.values.slice();
        mirrorValues(prop, tr.values);
      }
      tracks.push(tr);
    }
    c = new THREE.AnimationClip(key, src.duration, tracks);
    this.parts.set(key, c);
    return c;
  }
}
