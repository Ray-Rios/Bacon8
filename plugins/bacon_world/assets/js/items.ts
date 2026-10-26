// The item catalogue (BaconWorld.Items, sent by the LiveView in data-item-catalog) and
// the weapon models that go with it: /models/Weapons/B8_Weapons.glb holds one node
// W_<model> per weapon, written in bone space (origin = the grip, +Y along the
// handle, +Z the striking side, metres), so a clone parented to the weapon_r or
// weapon_l bone sits in the hand as is. Icons: /models/Weapons/icons/W_<icon>.png.
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, MeshoptDecoder } from '../../../../assets/js/vendor/three-loaders';
import { modelUrl } from './asset-url';
import { applySurfaces } from './surface-textures';
import type { Gear, GearSet } from './anim-driver';

export const WEAPONS_GLB = '/models/Weapons/B8_Weapons.glb';
export const ICONS_BASE = '/models/Weapons/icons';

export interface ItemDef {
  name: string;
  kind: 'weapon' | 'shield' | 'light' | 'armor' | 'junk';
  /** Hands ('main', 'off') or a worn slot ('under_top', 'under_bottom', 'chest', 'legs', 'feet'). */
  slots: string[];
  hands: 1 | 2;
  set: GearSet | null;
  skill: string | null;
  dmg: number;
  dly: number;
  reach: number;
  ac: number;
  stack: number;
  value: number;
  model: string | null;
  icon: string | null;
  /** The icon file under /models (weapons: Weapons/icons/W_<model>.png; clothes: Humans/Wardrobe/icons/<id>.png). */
  icon_path?: string | null;
  /** How a worn item is drawn on each body (wardrobe.ts), and its colours. */
  wear?: Record<string, { garment: string; design?: string } | null> | null;
  colors?: Record<string, string> | null;
}

export type Catalog = Record<string, ItemDef>;

let catalog: Catalog = {};

export function setCatalog(c: unknown) {
  catalog = c && typeof c === 'object' ? (c as Catalog) : {};
}

export function item(id: string | null | undefined): ItemDef | null {
  return (id && catalog[id]) || null;
}

export function iconUrl(id: string | null | undefined): string | null {
  const it = item(id);
  if (it?.icon_path) return modelUrl(`/models/${it.icon_path}`);
  return it?.icon ? modelUrl(`${ICONS_BASE}/W_${it.icon}.png`) : null;
}

/** EverQuest's names for the worn slots. */
export const SLOT_NAMES: Record<string, string> = {
  main: 'Primary', off: 'Secondary', under_top: 'Undershirt', under_bottom: 'Underwear',
  chest: 'Chest', legs: 'Legs', feet: 'Feet',
};

/** True for things that are worn rather than held. */
export function isWearable(id: string | null | undefined): boolean {
  return item(id)?.kind === 'armor';
}

/** What a hand holds, for the animator. */
export function gearOf(id: string | null | undefined): Gear | null {
  const it = item(id);
  if (!it || !it.set) return null;
  return { set: it.set, hands: it.hands };
}

/** Copper as EverQuest money: "1p 2g 3s 4c" (10 copper = 1 silver, ...). */
export function money(copper: number): string {
  let c = Math.max(0, Math.floor(copper || 0));
  const p = Math.floor(c / 1000);
  c -= p * 1000;
  const g = Math.floor(c / 100);
  c -= g * 100;
  const s = Math.floor(c / 10);
  c -= s * 10;
  const parts: string[] = [];
  if (p) parts.push(`${p}p`);
  if (g) parts.push(`${g}g`);
  if (s) parts.push(`${s}s`);
  if (c || !parts.length) parts.push(`${c}c`);
  return parts.join(' ');
}

/** The same in words, for the chat log ("1 silver and 4 copper"). */
export function moneyWords(copper: number): string {
  let c = Math.max(0, Math.floor(copper || 0));
  const names = [['platinum', 1000], ['gold', 100], ['silver', 10], ['copper', 1]] as const;
  const parts: string[] = [];
  for (const [n, v] of names) {
    const k = Math.floor(c / v);
    c -= k * v;
    if (k) parts.push(`${k} ${n}`);
  }
  if (!parts.length) return 'nothing';
  return parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;
}

/** The EverQuest-style item description lines. */
export function describe(id: string): string[] {
  const it = item(id);
  if (!it) return [];
  const lines: string[] = [];
  if (it.kind === 'junk') {
    lines.push('Stackable' + (it.stack > 1 ? ` (${it.stack})` : ''));
  } else if (it.kind === 'armor') {
    lines.push(`Slot: ${it.slots.map((x) => SLOT_NAMES[x] || x).join(', ')}`);
    if (it.ac) lines.push(`AC: ${it.ac}`);
    lines.push(it.slots.includes('under_top') || it.slots.includes('under_bottom') ? 'Worn under clothes and armour' : 'Cloth');
  } else {
    const slot = it.hands === 2 ? 'Primary (two-handed)' : it.slots.length === 2 ? 'Primary, Secondary' : it.slots[0] === 'off' ? 'Secondary' : 'Primary';
    lines.push(`Slot: ${slot}`);
    if (it.skill) lines.push(`Skill: ${it.skill}`);
    if (it.dmg) lines.push(`DMG: ${it.dmg}   DLY: ${it.dly}`);
    if (it.ac) lines.push(`AC: ${it.ac}`);
    lines.push(`Reach: ${it.reach.toFixed(1)} m`);
  }
  lines.push(`Value: ${money(it.value)}`);
  return lines;
}

/**
 * How a model sits in the hand, where the file's own origin isn't right (metres and
 * degrees, in the weapon's frame: +Y along the handle, +Z the striking side).
 *  - `y`: slides the model along its handle, so the hand holds it this far from the origin
 *    toward the butt. The long-hafted two-handers are held near the end of the haft, not
 *    at their middle (2026-10-23: the battle axe's haft hung between her legs).
 *  - `roll`: turns it about the handle. The one-handed swings (STANCES' sword_1h, axe_1h
 *    and blunt_1h all use the library's sword clips) lead with the weapon bone's -Z, while
 *    the weapons file puts the striking side on +Z (build_weapons2.py), so **every
 *    one-handed weapon with a single striking side needs roll 180**: an edge on one side, an
 *    axe bit, a hammer face (2026-10-23: the scimitar cut with its back; 2026-10-24: the hand
 *    axe's bit faced backward). Double-edged and round heads (swords, mace, morning star,
 *    club) look the same either way. The two-handed swings were refitted to +Z, so the
 *    two-handers need none. Add any new one-hander here when it joins the catalogue.
 *  - `off`: **two-handers only, a fallback**: where the left hand grips, metres along the haft
 *    (+Y, toward the head) from the right hand's grip, used only when a clip's left hand isn't
 *    on the haft. human-factory.ts `twoHandGrip` otherwise keeps the clip's own spacing
 *    (2026-10-25: forcing these values every frame put the male's left hand on the wrong side
 *    of the right on the axe, maul and greatsword, and out of reach on the spear and halberd).
 *    Keep one on every new two-hander, on the haft (the file's extents, less `y`).
 */
export const HOLD: Record<string, { y?: number; roll?: number; off?: number }> = {
  // haft -0.20..0.70 from the hand, head beyond: left hand a third of the way up
  BattleAxe: { y: 0.35, off: 0.32 },
  Maul: { y: 0.35, off: 0.32 },
  // the hilt runs -0.25..0.11: left hand below the right, at the pommel end
  Greatsword: { off: -0.13 },
  // long shafts held in their lower half, the left hand up the shaft
  Spear: { off: 0.45 },
  Halberd: { off: 0.42 },
  // the staff is held at its middle, hands half a metre apart
  Quarterstaff: { y: 0.25, off: 0.5 },
  Scimitar: { roll: 180 },
  Cutlass: { roll: 180 },
  Axe: { roll: 180 },
  WarHammer: { roll: 180 },
  // in the weapons file, not yet items
  Hatchet: { roll: 180 },
  Machete: { roll: 180 },
  BuilderHammer: { roll: 180 },
};

/** Loads the weapons file once and hands out clones of its nodes. */
export class WeaponModels {
  private loader: GLTFLoader;
  private scene: Promise<THREE.Object3D | null> | null = null;

  constructor() {
    this.loader = new GLTFLoader();
    this.loader.setMeshoptDecoder(MeshoptDecoder);
  }

  private load(): Promise<THREE.Object3D | null> {
    if (!this.scene) {
      this.scene = new Promise((resolve) => {
        this.loader.load(
          modelUrl(WEAPONS_GLB),
          (g: any) => {
            g.scene.traverse((o: any) => {
              if (o.isMesh) {
                o.castShadow = true;
                o.receiveShadow = false;
              }
            });
            applySurfaces(g.scene, 'weapons');
            resolve(g.scene);
          },
          undefined,
          (err: unknown) => {
            console.warn('[items] weapons failed to load', err);
            resolve(null);
          }
        );
      });
    }
    return this.scene;
  }

  /** A copy of weapon `model` (shares geometry and materials with the template). */
  async create(model: string): Promise<THREE.Object3D | null> {
    const scene = await this.load();
    const tpl = scene?.getObjectByName(`W_${model}`);
    if (!tpl) return null;
    const copy = tpl.clone(true);
    const hold = HOLD[model] || {};
    copy.position.set(0, hold.y || 0, 0);
    copy.quaternion.setFromAxisAngle(new THREE.Vector3(0, 1, 0), THREE.MathUtils.degToRad(hold.roll || 0));
    copy.userData.b8Weapon = model;
    return copy;
  }
}

/**
 * Puts `itemId`'s model in a character's hand (replacing what was there), or
 * empties the hand. `root` is the character root; the hand is its weapon_r
 * (main) or weapon_l (off) bone. Resolves when the model is in place.
 */
export async function holdItem(models: WeaponModels, root: THREE.Object3D, hand: 'main' | 'off', itemId: string | null): Promise<void> {
  const bone = root.getObjectByName(hand === 'main' ? 'weapon_r' : 'weapon_l');
  if (!bone) return;
  const want = item(itemId)?.model || null;
  const token = `${hand}:${itemId ?? ''}`;
  bone.userData.b8Wanted = token;
  const old = bone.children.filter((c) => c.userData.b8Weapon);
  if (old.length === 1 && old[0].userData.b8Weapon === want) return;
  const fresh = want ? await models.create(want) : null;
  // A newer request may have come in while loading.
  if (bone.userData.b8Wanted !== token) return;
  bone.children.filter((c) => c.userData.b8Weapon).forEach((c) => bone.remove(c));
  if (fresh) bone.add(fresh);
  // the off hand's grip on a two-hander (HOLD.off), read by human-factory.ts twoHandGrip
  if (hand === 'main') bone.userData.b8OffGrip = want ? HOLD[want]?.off ?? null : null;
}
