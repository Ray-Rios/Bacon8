// A character's look: body, shape sliders, colours and hair. Stored by the server in the
// character's settings["appearance"] (BaconWorld.Appearance validates it the same way
// normalizeAppearance does here) and applied by human-factory.ts. Clothes aren't part of
// the look: they are items the character wears (wardrobe.ts).
//
// Shape sliders map onto the Bacon8 humans' morph targets (blend shapes). Bipolar
// sliders drive a pair: weight -1..1 -> Weight_Thin / Weight_Heavy.

export type Body = 'male' | 'female';

export interface Appearance {
  v: 1;
  body: Body;
  height: number; // 0.92 .. 1.08 (times the body's own height)
  shape: Record<ShapeKey, number>;
  skin: string;
  eyes: string;
  brows: string | null; // null: follows the hair colour
  hair: { style: string; color: string };
  facial: { style: string; color: string }; // male only ("none" for female)
}

export type ShapeKey =
  | 'weight' | 'muscle' | 'shoulders' | 'waist' | 'belly' | 'hips'
  | 'chest' | 'chest_height' | 'chest_spacing' | 'chest_shape'
  | 'glutes' | 'glute_lift' | 'arms' | 'thighs' | 'calves'
  | 'face' | 'jaw' | 'nose';

/** Where a slider sits in the creator: body sections, Black Desert style, or the face tab. */
export type ShapeGroup = 'Body' | 'Chest' | 'Glutes' | 'Arms and legs' | 'Face';

export interface ShapeSpec {
  key: ShapeKey;
  label: string;
  min: number;
  max: number;
  // morph names driven by the negative and positive halves of the slider
  neg?: string;
  pos: string;
  tab: 'body' | 'face';
  group: ShapeGroup;
  bodies?: Body[];
  ends?: [string, string];
  /** How far a random look may push it (default 0.8 of the range). */
  rand?: number;
}

// The female's body sliders follow Black Desert's creator: the chest, the glutes, the waist and
// the limbs each have their own (morphs from the pipeline's mhf_morphs.py, stage G). The male
// gets them when he is rebuilt the same way; until then they're female-only.
const F: Body[] = ['female'];
export const SHAPES: ShapeSpec[] = [
  { key: 'weight', label: 'Build', min: -1, max: 1, neg: 'Weight_Thin', pos: 'Weight_Heavy', tab: 'body', group: 'Body', ends: ['Slim', 'Heavy'] },
  { key: 'muscle', label: 'Muscle', min: 0, max: 1, pos: 'Muscle', tab: 'body', group: 'Body', ends: ['Soft', 'Toned'] },
  { key: 'shoulders', label: 'Shoulders', min: 0, max: 1, pos: 'Shoulders_Broad', tab: 'body', group: 'Body', ends: ['Narrow', 'Broad'] },
  { key: 'waist', label: 'Waist', min: -1, max: 1, neg: 'Waist_Narrow', pos: 'Waist_Wide', tab: 'body', group: 'Body', bodies: F, ends: ['Narrow', 'Wide'], rand: 0.4 },
  { key: 'belly', label: 'Belly', min: 0, max: 1, pos: 'Belly', tab: 'body', group: 'Body', ends: ['Flat', 'Round'] },
  { key: 'hips', label: 'Hips', min: 0, max: 1, pos: 'Hips_Wide', tab: 'body', group: 'Body', ends: ['Narrow', 'Wide'] },
  { key: 'chest', label: 'Size', min: -1, max: 1, neg: 'Breasts_Small', pos: 'Breasts_Large', tab: 'body', group: 'Chest', bodies: F, ends: ['Small', 'Full'] },
  { key: 'chest_height', label: 'Height', min: -1, max: 1, neg: 'Chest_Low', pos: 'Chest_High', tab: 'body', group: 'Chest', bodies: F, ends: ['Low', 'High'], rand: 0.4 },
  { key: 'chest_spacing', label: 'Spacing', min: -1, max: 1, neg: 'Chest_Close', pos: 'Chest_Wide', tab: 'body', group: 'Chest', bodies: F, ends: ['Close', 'Wide'], rand: 0.4 },
  { key: 'chest_shape', label: 'Shape', min: -1, max: 1, neg: 'Chest_Round', pos: 'Chest_Perky', tab: 'body', group: 'Chest', bodies: F, ends: ['Round', 'Perky'], rand: 0.5 },
  { key: 'glutes', label: 'Size', min: -1, max: 1, neg: 'Glutes_Small', pos: 'Glutes_Large', tab: 'body', group: 'Glutes', ends: ['Small', 'Full'] },
  { key: 'glute_lift', label: 'Lift', min: 0, max: 1, pos: 'Glutes_Lift', tab: 'body', group: 'Glutes', bodies: F, ends: ['Natural', 'Lifted'], rand: 0.5 },
  { key: 'arms', label: 'Arms', min: -1, max: 1, neg: 'Arms_Slim', pos: 'Arms_Thick', tab: 'body', group: 'Arms and legs', bodies: F, ends: ['Slim', 'Thick'], rand: 0.4 },
  { key: 'thighs', label: 'Thighs', min: -1, max: 1, neg: 'Thighs_Slim', pos: 'Thighs_Thick', tab: 'body', group: 'Arms and legs', bodies: F, ends: ['Slim', 'Thick'], rand: 0.4 },
  { key: 'calves', label: 'Calves', min: -1, max: 1, neg: 'Calves_Slim', pos: 'Calves_Thick', tab: 'body', group: 'Arms and legs', bodies: F, ends: ['Slim', 'Thick'], rand: 0.4 },
  { key: 'face', label: 'Face', min: 0, max: 1, pos: 'Face_Full', tab: 'face', group: 'Face', ends: ['Lean', 'Full'] },
  { key: 'jaw', label: 'Jaw', min: 0, max: 1, pos: 'Jaw_Wide', tab: 'face', group: 'Face', ends: ['Soft', 'Wide'] },
  { key: 'nose', label: 'Nose', min: 0, max: 1, pos: 'Nose_Large', tab: 'face', group: 'Face', ends: ['Small', 'Large'] },
];

export const HEIGHT_RANGE: [number, number] = [0.92, 1.08];

// Palettes (sRGB hex). The colour pickers also accept any custom colour.
export const SKIN_TONES = [
  '#F6D7C3', '#EFC3A4', '#E5B08C', '#D9A07A', '#C68E6E', '#B57A55',
  '#A0673F', '#8A5534', '#73452A', '#5C3621', '#472918', '#33200F',
];
export const EYE_COLORS = ['#3B2416', '#5A3D26', '#7A5A2E', '#9A7B3A', '#5E7A3C', '#3E6E58', '#6B7B86', '#3D6FA8', '#7FB2E5', '#6E4A9E', '#B23A3A', '#C9A227'];
export const HAIR_COLORS = [
  '#0E0B0A', '#2B1E14', '#4A3020', '#6E4A2E', '#8E5A35', '#7A2E1C',
  '#B5552B', '#C98A50', '#D8B26E', '#EAD6A8', '#8C8C8C', '#E8E4DC',
  '#2E5BD8', '#E05A9E', '#7A4BD1', '#2FA36B',
];

export const BODY_MODEL: Record<Body, string> = { male: '/models/Humans/Male.glb', female: '/models/Humans/Female.glb' };

const HEX = /^#[0-9a-fA-F]{6}$/;
const STYLE = /^[A-Za-z0-9_]{1,32}$/;

export function bodyFromModelPath(path: string | null | undefined): Body {
  return /female/i.test(path || '') ? 'female' : 'male';
}

export function isHumanModel(path: string | null | undefined): boolean {
  return /\/models\/Humans\/(Male|Female)\.glb$/i.test(path || '');
}

export function defaultAppearance(body: Body = 'male'): Appearance {
  const shape = {} as Record<ShapeKey, number>;
  for (const s of SHAPES) shape[s.key] = 0;
  return {
    v: 1,
    body,
    height: 1,
    shape,
    skin: '#C68E6E',
    eyes: '#5A3D26',
    brows: null,
    hair: { style: body === 'male' ? 'CrewCut' : 'Lob', color: '#2B1E14' },
    facial: { style: 'none', color: '#2B1E14' },
  };
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const num = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
const color = (v: unknown, d: string) => (typeof v === 'string' && HEX.test(v) ? v.toUpperCase() : d);
const style = (v: unknown, d: string) => (typeof v === 'string' && (v === 'none' || STYLE.test(v)) ? v : d);
const round3 = (v: number) => Math.round(v * 1000) / 1000;

/** Anything (server JSON, old characters, user input) -> a complete, valid Appearance. */
export function normalizeAppearance(raw: unknown, fallbackBody: Body = 'male'): Appearance {
  const r: any = raw && typeof raw === 'object' ? raw : {};
  const body: Body = r.body === 'female' || r.body === 'male' ? r.body : fallbackBody;
  const d = defaultAppearance(body);
  const shape = {} as Record<ShapeKey, number>;
  for (const s of SHAPES) shape[s.key] = round3(clamp(num(r.shape?.[s.key], 0), s.min, s.max));
  // sliders for the other body stay at 0 (the male has no chest or stage-G morphs yet)
  for (const s of SHAPES) if (s.bodies && !s.bodies.includes(body)) shape[s.key] = 0;
  return {
    v: 1,
    body,
    height: round3(clamp(num(r.height, 1), HEIGHT_RANGE[0], HEIGHT_RANGE[1])),
    shape,
    skin: color(r.skin, d.skin),
    eyes: color(r.eyes, d.eyes),
    brows: r.brows == null ? null : color(r.brows, d.hair.color),
    hair: { style: style(r.hair?.style, d.hair.style), color: color(r.hair?.color, d.hair.color) },
    facial: body === 'female' ? { style: 'none', color: color(r.facial?.color, d.facial.color) } : { style: style(r.facial?.style, 'none'), color: color(r.facial?.color, d.facial.color) },
  };
}

/** Morph target name -> influence (0..1) for an appearance. */
export function morphWeights(a: Appearance): Record<string, number> {
  const out: Record<string, number> = {};
  for (const s of SHAPES) {
    if (s.bodies && !s.bodies.includes(a.body)) continue;
    const v = a.shape[s.key] || 0;
    if (s.neg) out[s.neg] = Math.max(0, -v);
    out[s.pos] = Math.max(0, s.min < 0 ? v : v);
  }
  return out;
}

/** A darker, slightly desaturated shade (eyebrows from hair, trims from mains). */
export function shade(hex: string, k: number): string {
  const n = parseInt(hex.slice(1), 16);
  const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => Math.round(clamp(c * k, 0, 255)));
  return '#' + ch.map((c) => c.toString(16).padStart(2, '0')).join('').toUpperCase();
}

export function browColor(a: Appearance): string {
  return a.brows || shade(a.hair.color, a.hair.color === '#E8E4DC' || a.hair.color === '#EAD6A8' ? 0.8 : 0.85);
}

/** Stable short key for caching / change detection. */
export function appearanceKey(a: Appearance): string {
  return JSON.stringify(a);
}

// Seeded random (mulberry32) so a "randomise" can be reproduced in tests.
export function rng(seed: number) {
  let t = seed >>> 0;
  return () => {
    t += 0x6d2b79f5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

/** A random, plausible look. hairStyles: ids available for the body (from the hair manifest). */
export function randomAppearance(body: Body, hairStyles: string[], facialStyles: string[], seed = Date.now()): Appearance {
  const r = rng(seed);
  const any = <T>(xs: T[]): T => xs[Math.floor(r() * xs.length) % xs.length];
  const a = defaultAppearance(body);
  const tri = () => (r() + r() + r()) / 3; // centre-weighted 0..1
  a.height = round3(HEIGHT_RANGE[0] + tri() * (HEIGHT_RANGE[1] - HEIGHT_RANGE[0]));
  for (const s of SHAPES) {
    if (s.bodies && !s.bodies.includes(body)) continue;
    const k = s.rand ?? 0.8;
    const v = s.min < 0 ? (tri() * 2 - 1) * k : Math.pow(r(), 1.6) * k;
    a.shape[s.key] = round3(v);
  }
  a.skin = any(SKIN_TONES);
  a.eyes = any(EYE_COLORS.slice(0, 10));
  const natural = HAIR_COLORS.slice(0, 12);
  a.hair = { style: hairStyles.length ? any(hairStyles) : a.hair.style, color: r() < 0.12 ? any(HAIR_COLORS.slice(12)) : any(natural) };
  a.facial = { style: body === 'male' && facialStyles.length && r() < 0.45 ? any(facialStyles) : 'none', color: a.hair.color };
  return a;
}
