// Two-handed weapons, driven by the weapon (2026-10-27).
//
// The library's two-handed clips never fitted our bodies: held, the weapons lay across the hips
// or ran through the legs; swung, the off hand left the haft and the arms twisted and folded
// (the owner, three times). So the arms no longer come from clips at all while a two-hander is
// held. Each pose here says where the weapon is: the main hand's grip (`grip`, in the body's own
// frame: x its left, y up, z forward, in units of its pelvis-to-neck height, from the pelvis),
// which way the haft points (`dir`, grip toward the head) and which way the edge faces (`edge`:
// the weapon's +Z, the blade's edge or the axe's bit), plus how far the torso turns and leans.
// human-factory.ts (twoHandDrive) puts the weapon there, then both arms on it with an IK that
// keeps each elbow a true hinge and each hand turned by the weapon itself (so a wrist can't wring
// through 180), and splits the forearm's roll with its twist bone.
//
// A swing is a few such poses over its length (0..1), eased between; `hit` is when it lands. The
// legs keep their clip (standing, locomotion, or the old swing's footwork).

export type V3 = [number, number, number];

export interface TwoHandPose {
  grip: V3;
  dir: V3;
  edge: V3;
  /** The torso's turn (degrees, + toward its left) and lean (+ forward). */
  twist?: number;
  lean?: number;
  /** Where each elbow points (the body's frame); defaults down, out and back. */
  poleR?: V3;
  poleL?: V3;
}

export interface TwoHandSwing {
  hit: number;
  keys: Array<{ at: number; pose: TwoHandPose }>;
}

export interface TwoHandSet {
  guard: TwoHandPose;
  light: string[];
  heavy: string;
  swings: Record<string, TwoHandSwing>;
}

const DOWN_OUT_R: V3 = [-0.55, -1, -0.3];
const DOWN_OUT_L: V3 = [0.55, -1, -0.3];
const OUT_R: V3 = [-1, -0.2, -0.2];
const OUT_L: V3 = [1, -0.2, -0.2];

// Swords, axes and mauls: a middle guard; a falling diagonal cut, a rising one, and an overhead.
const BLADE_GUARD: TwoHandPose = { grip: [-0.06, 0.45, 0.62], dir: [0.1, 0.65, 0.75], edge: [0, -0.75, 0.65] };

const BLADE: TwoHandSet = {
  guard: BLADE_GUARD,
  light: ['cut_down', 'cut_up'],
  heavy: 'overhead',
  swings: {
    // from over the right shoulder down across to the left hip
    cut_down: {
      hit: 0.5,
      keys: [
        { at: 0, pose: BLADE_GUARD },
        { at: 0.32, pose: { grip: [-0.42, 1.05, 0.22], dir: [-0.35, 0.72, -0.6], edge: [0.55, 0.45, 0.7], twist: -28, lean: -4, poleR: OUT_R, poleL: DOWN_OUT_L } },
        { at: 0.5, pose: { grip: [-0.04, 0.72, 0.78], dir: [0.55, 0.15, 0.82], edge: [0.6, -0.7, -0.35], twist: 4, lean: 8 } },
        { at: 0.68, pose: { grip: [0.32, 0.3, 0.5], dir: [0.8, -0.5, -0.1], edge: [0.1, -0.35, -0.95], twist: 30, lean: 12 } },
        { at: 1, pose: BLADE_GUARD },
      ],
    },
    // from low on the left up across to high on the right
    cut_up: {
      hit: 0.5,
      keys: [
        { at: 0, pose: BLADE_GUARD },
        { at: 0.32, pose: { grip: [0.3, 0.3, 0.45], dir: [0.75, -0.55, -0.2], edge: [0.2, -0.3, 0.92], twist: 26, lean: 8 } },
        { at: 0.5, pose: { grip: [0.0, 0.7, 0.78], dir: [-0.55, 0.3, 0.78], edge: [-0.55, 0.75, -0.3], twist: 0, lean: 4 } },
        { at: 0.68, pose: { grip: [-0.38, 1.0, 0.35], dir: [-0.65, 0.65, -0.3], edge: [-0.2, 0.3, 0.92], twist: -26, lean: -2, poleR: OUT_R } },
        { at: 1, pose: BLADE_GUARD },
      ],
    },
    // up over the head, then straight down in front
    overhead: {
      hit: 0.6,
      keys: [
        { at: 0, pose: BLADE_GUARD },
        { at: 0.4, pose: { grip: [-0.05, 2.0, 0.8], dir: [0, 0.35, -0.94], edge: [0, 0.94, 0.35], twist: -6, lean: -10, poleR: OUT_R, poleL: OUT_L } },
        { at: 0.52, pose: { grip: [-0.03, 1.6, 0.8], dir: [0, 0.75, 0.66], edge: [0, -0.66, 0.75], twist: -2, lean: 4, poleR: OUT_R, poleL: OUT_L } },
        { at: 0.62, pose: { grip: [-0.02, 0.62, 0.8], dir: [0, -0.3, 0.95], edge: [0, -0.95, -0.3], twist: 0, lean: 18 } },
        { at: 0.8, pose: { grip: [-0.02, 0.48, 0.72], dir: [0, -0.5, 0.86], edge: [0, -0.86, -0.5], twist: 0, lean: 16 } },
        { at: 1, pose: BLADE_GUARD },
      ],
    },
  },
};

// Spears and halberds: the rear hand at the right hip, the point forward; two thrusts and a sweep.
const POLE_GUARD: TwoHandPose = { grip: [-0.36, 0.35, 0.22], dir: [0.12, 0.25, 0.96], edge: [0.96, 0.05, -0.12], twist: -12 };

const POLE: TwoHandSet = {
  guard: POLE_GUARD,
  light: ['thrust', 'thrust_high'],
  heavy: 'sweep',
  swings: {
    thrust: {
      hit: 0.45,
      keys: [
        { at: 0, pose: POLE_GUARD },
        { at: 0.3, pose: { grip: [-0.42, 0.38, -0.05], dir: [0.1, 0.2, 0.97], edge: [0.97, 0.05, -0.1], twist: -22, lean: -4 } },
        { at: 0.45, pose: { grip: [-0.16, 0.5, 0.72], dir: [0.06, 0.12, 0.99], edge: [0.99, 0, -0.06], twist: 2, lean: 14 } },
        { at: 0.62, pose: { grip: [-0.18, 0.48, 0.66], dir: [0.06, 0.12, 0.99], edge: [0.99, 0, -0.06], twist: 0, lean: 12 } },
        { at: 1, pose: POLE_GUARD },
      ],
    },
    thrust_high: {
      hit: 0.45,
      keys: [
        { at: 0, pose: POLE_GUARD },
        { at: 0.3, pose: { grip: [-0.4, 0.55, -0.02], dir: [0.1, 0.4, 0.91], edge: [0.99, 0, -0.1], twist: -20, lean: -6 } },
        { at: 0.45, pose: { grip: [-0.14, 0.85, 0.7], dir: [0.05, 0.3, 0.95], edge: [0.99, 0, -0.05], twist: 4, lean: 10, poleR: OUT_R } },
        { at: 0.62, pose: { grip: [-0.16, 0.8, 0.64], dir: [0.05, 0.3, 0.95], edge: [0.99, 0, -0.05], twist: 2, lean: 8, poleR: OUT_R } },
        { at: 1, pose: POLE_GUARD },
      ],
    },
    // the head swept from the right round to the left at chest height
    sweep: {
      hit: 0.55,
      keys: [
        { at: 0, pose: POLE_GUARD },
        { at: 0.35, pose: { grip: [-0.4, 0.5, 0.22], dir: [-0.35, 0.1, 0.93], edge: [0.93, 0.05, 0.35], twist: -45, lean: -2 } },
        { at: 0.55, pose: { grip: [-0.1, 0.55, 0.5], dir: [0.1, 0.12, 0.98], edge: [0.98, -0.05, -0.1], twist: 0, lean: 8 } },
        { at: 0.72, pose: { grip: [0.12, 0.52, 0.4], dir: [0.8, 0.08, 0.6], edge: [0.6, -0.05, -0.8], twist: 34, lean: 10 } },
        { at: 1, pose: POLE_GUARD },
      ],
    },
  },
};

// The quarterstaff: held across the body at its middle; a jab with the top end and a swing.
const STAFF_GUARD: TwoHandPose = { grip: [-0.28, 0.45, 0.55], dir: [0.6, 0.75, 0.25], edge: [0, -0.3, 0.95] };

const STAFF: TwoHandSet = {
  guard: STAFF_GUARD,
  light: ['jab'],
  heavy: 'swing',
  swings: {
    jab: {
      hit: 0.45,
      keys: [
        { at: 0, pose: STAFF_GUARD },
        { at: 0.3, pose: { grip: [-0.3, 0.42, 0.3], dir: [0.5, 0.45, 0.74], edge: [0, -0.85, 0.52], twist: -14 } },
        { at: 0.45, pose: { grip: [-0.15, 0.6, 0.72], dir: [0.3, 0.3, 0.9], edge: [0, -0.95, 0.31], twist: 6, lean: 12 } },
        { at: 1, pose: STAFF_GUARD },
      ],
    },
    swing: {
      hit: 0.52,
      keys: [
        { at: 0, pose: STAFF_GUARD },
        { at: 0.35, pose: { grip: [-0.42, 0.75, 0.3], dir: [0.45, 0.85, -0.25], edge: [0.3, 0.1, 0.95], twist: -30, lean: -6, poleR: OUT_R } },
        { at: 0.52, pose: { grip: [-0.1, 0.65, 0.7], dir: [0.85, -0.1, 0.5], edge: [0.5, -0.1, -0.86], twist: 6, lean: 10 } },
        { at: 0.7, pose: { grip: [0.15, 0.45, 0.55], dir: [0.8, -0.45, -0.3], edge: [-0.3, -0.2, -0.93], twist: 28, lean: 12 } },
        { at: 1, pose: STAFF_GUARD },
      ],
    },
  },
};

/** By stance set (anim-driver.ts GearSet). */
export const TWO_HAND_SETS: Record<string, TwoHandSet> = { two_hand: BLADE, polearm: POLE, staff: STAFF };

/** How long a swing takes (s) for a weapon's swing time (`delay`, s). */
export function twoHandDuration(delay: number | undefined, heavy: boolean): number {
  const d = Math.min(1.7, Math.max(0.75, (delay ?? 1.6) * 0.85));
  return heavy ? Math.min(2.0, d * 1.15) : d;
}

const ease = (t: number) => t * t * (3 - 2 * t);

function lerp3(a: V3, b: V3, t: number): V3 {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

function norm(v: V3): V3 {
  const l = Math.hypot(v[0], v[1], v[2]) || 1;
  return [v[0] / l, v[1] / l, v[2] / l];
}

/** Two poses blended (`t` 0..1): positions lerped, directions lerped and renormalised. */
export function blendPose(a: TwoHandPose, b: TwoHandPose, t: number): TwoHandPose {
  return {
    grip: lerp3(a.grip, b.grip, t),
    dir: norm(lerp3(norm(a.dir), norm(b.dir), t)),
    edge: norm(lerp3(norm(a.edge), norm(b.edge), t)),
    twist: (a.twist ?? 0) + ((b.twist ?? 0) - (a.twist ?? 0)) * t,
    lean: (a.lean ?? 0) + ((b.lean ?? 0) - (a.lean ?? 0)) * t,
    poleR: norm(lerp3(a.poleR ?? DOWN_OUT_R, b.poleR ?? DOWN_OUT_R, t)),
    poleL: norm(lerp3(a.poleL ?? DOWN_OUT_L, b.poleL ?? DOWN_OUT_L, t)),
  };
}

/** The pose `x` (0..1) of the way through a swing. */
export function swingPose(s: TwoHandSwing, x: number): TwoHandPose {
  const k = s.keys;
  if (x <= k[0].at) return blendPose(k[0].pose, k[0].pose, 0);
  for (let i = 0; i + 1 < k.length; i++) {
    if (x <= k[i + 1].at) {
      const t = (x - k[i].at) / Math.max(1e-6, k[i + 1].at - k[i].at);
      return blendPose(k[i].pose, k[i + 1].pose, ease(t));
    }
  }
  const last = k[k.length - 1].pose;
  return blendPose(last, last, 0);
}

/** The pose for a set: its guard, or `swing` `x` of the way through. */
export function twoHandPose(set: string, swing?: { name: string; x: number } | null): TwoHandPose | null {
  const s = TWO_HAND_SETS[set];
  if (!s) return null;
  const sw = swing && s.swings[swing.name];
  return sw ? swingPose(sw, swing!.x) : blendPose(s.guard, s.guard, 0);
}
