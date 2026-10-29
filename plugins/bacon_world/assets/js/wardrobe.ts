// What a Bacon8 human wears, and the small corrections drawn on top of its animation.
//
// Clothes are items (BaconWorld.Items, kind "armor"): underwear in "under_top" and
// "under_bottom", cloth armour in "chest", "legs" and "feet". An item's `wear` says which
// garment of each body shows it and, for the garments made from the body itself
// (Under_Top_Contour, Under_Top_Band, Under_Bottom, Top_Tank, Bottom_Shorts, Bottom_Pants on
// the female), which design: a packed texture Humans/Wardrobe/<garment>__<design>.webp
// (R shading, G trim, B accent, A coverage) tinted with the item's colours. The other
// garments (MakeHuman's T-shirt, sweater and shoes; all of the male's) tint their
// <Garment>_Main/_Trim (_Upper/_Sole/_Laces) materials as before.
//
// Pure functions here (unit-tested); human-factory.ts does the three.js side.
import type { Body } from './appearance';

export type GearSlot = 'main' | 'off' | 'head' | 'under_top' | 'under_bottom' | 'chest' | 'legs' | 'feet';
export type Gear = Partial<Record<GearSlot, string | null>>;
// 'head' (2026-10-29) holds hats, which go on the head bone (crafted.ts wearHat), not garments
export const WORN_SLOTS: GearSlot[] = ['head', 'under_top', 'under_bottom', 'chest', 'legs', 'feet'];

/** What every character starts out wearing (BaconWorld.Items.starter_wear/0). */
export const STARTER_GEAR: Gear = { under_top: 'linen_bikini_top', under_bottom: 'linen_bikini_bottom' };

export interface WearDef {
  garment: string;
  design?: string;
}

export interface WearableItem {
  slots: string[];
  wear?: Partial<Record<Body, WearDef | null>> | null;
  colors?: Record<string, string> | null;
}

export interface WornGarment {
  slot: GearSlot;
  item: string;
  garment: string;
  design: string | null;
  colors: Record<string, string>;
}

/**
 * The garments a body shows for what it wears, inner layers first. Two items can't show
 * the same garment: the outer one wins (the male's underwear bottoms are his shorts, so
 * trousers or shorts over them replace them).
 */
export function wornGarments(body: Body, gear: Gear | null | undefined, item: (id: string) => WearableItem | null): WornGarment[] {
  const out: WornGarment[] = [];
  for (const slot of WORN_SLOTS) {
    const id = gear?.[slot];
    if (!id) continue;
    const it = item(id);
    const w = it?.wear?.[body];
    if (!it || !w || !w.garment) continue;
    const g: WornGarment = { slot, item: id, garment: w.garment, design: w.design || null, colors: { ...(it.colors || {}) } };
    const dup = out.findIndex((x) => x.garment === g.garment);
    if (dup >= 0) out.splice(dup, 1);
    out.push(g);
  }
  return out;
}

/** Region ids hidden under a set of garments (the manifest's `hides`). */
export function hiddenFor(garments: string[], hides: Record<string, number[]> | null | undefined): number[] {
  const set = new Set<number>();
  for (const g of garments) for (const r of hides?.[g] || []) set.add(r);
  return [...set].sort((a, b) => a - b);
}

/** The wardrobe texture of a design (relative to /models/Humans). */
export function designFiles(dir: string, garment: string, design: string): { mask: string; normal: string } {
  return { mask: `${dir}/${garment}__${design}.webp`, normal: `${dir}/${garment}__${design}_n.webp` };
}

/** A stable key for change detection. */
export function gearKey(g: Gear | null | undefined): string {
  const slots: GearSlot[] = ['main', 'off', ...WORN_SLOTS];
  return slots.map((s) => `${s}=${g?.[s] || ''}`).join(';');
}

// ---------------------------------------------------------------------------
// Bones the morphs move
// ---------------------------------------------------------------------------

/**
 * Some morphs move whole limbs (Shoulders_Broad moves each arm out by ~3 cm). The body file
 * keeps only the rest of the change in its morph targets; the bones are moved by the same
 * amount here, so a hand curls about its own knuckles. Returns {bone: [x, y, z]} in model
 * space (metres) for the given morph weights.
 */
export function boneOffsets(offsets: Record<string, Record<string, number[]>> | null | undefined, weights: Record<string, number>): Record<string, [number, number, number]> {
  const out: Record<string, [number, number, number]> = {};
  for (const [morph, bones] of Object.entries(offsets || {})) {
    const w = weights[morph] || 0;
    if (!w) continue;
    for (const [bone, v] of Object.entries(bones)) {
      const o = out[bone] || (out[bone] = [0, 0, 0]);
      o[0] += v[0] * w;
      o[1] += v[1] * w;
      o[2] += v[2] * w;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Hands at rest
// ---------------------------------------------------------------------------

// A relaxed hand: each joint curled about its local X (the B8 skeleton's curl axis), more
// toward the little finger, and each finger drawn in toward the middle one about the
// knuckle's local Z (the rest pose spreads them like a claw). Degrees: curl at the three
// joints, then the knuckle's spread (mirrored on the left). The thumb's curl also brings
// it in alongside the index. The library clips hold fists; an empty hand that isn't
// punching takes this instead. Tuned in the harness, 2026-10-23; the curl roughly halved
// and the thumb opened the same day (the owner: "curled in too much", not an idle hand).
export type RelaxedHand = Record<string, number[]>;

const RELAXED: RelaxedHand = {
  index: [15, 14, 6, 6],
  middle: [18, 17, 7, 1],
  ring: [21, 20, 8, -4],
  pinky: [24, 22, 9, -8],
  thumb: [12, 6, 3, 0],
};

const FINGER = /^(thumb|index|middle|ring|pinky)_0([123])_([lr])$/;

/** Degrees of curl for a finger bone (thumb_02_l, index_03_r, ...) in the relaxed hand, or null. */
export function relaxedCurl(bone: string, table: RelaxedHand = RELAXED): number | null {
  const m = FINGER.exec(bone);
  if (!m) return null;
  return (table[m[1]] || RELAXED[m[1]])[Number(m[2]) - 1] ?? 0;
}

/** Degrees a knuckle (`*_01_*`) turns about its local Z toward the middle finger (0 for other joints). */
export function relaxedSpread(bone: string, table: RelaxedHand = RELAXED): number {
  const m = FINGER.exec(bone);
  if (!m || m[2] !== '1') return 0;
  return ((table[m[1]] || RELAXED[m[1]])[3] ?? 0) * (m[3] === 'l' ? -1 : 1);
}

/** Moves `cur` toward `target` at `rate` per second (both 0..1). */
export function approach(cur: number, target: number, rate: number, dt: number): number {
  const step = rate * dt;
  return cur < target ? Math.min(target, cur + step) : Math.max(target, cur - step);
}

/** Bones whose translation the animation clips may key (everything else stays where the rig puts it). */
export const KEEP_TRANSLATION = new Set(['root', 'pelvis', 'weapon_l', 'weapon_r']);
