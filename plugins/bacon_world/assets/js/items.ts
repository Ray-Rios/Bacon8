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
import { makeArrowModel, makeGrillFork } from './crafted';

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
  /** An icon of the plugin's own (/plugins/bacon_world/icons/...), for items with none on the models volume. */
  icon_url?: string | null;
  /** How a worn item is drawn on each body (wardrobe.ts), and its colours. */
  wear?: Record<string, { garment: string; design?: string } | null> | null;
  colors?: Record<string, string> | null;
  /** A bow (2026-10-28): shoots endless arrows out to `reach` (BaconWorld.Melee). */
  ranged?: boolean;
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
  if (it?.icon_url) return it.icon_url;
  if (it?.icon_path) return modelUrl(`/models/${it.icon_path}`);
  return it?.icon ? modelUrl(`${ICONS_BASE}/W_${it.icon}.png`) : null;
}

/** EverQuest's names for the worn slots. */
export const SLOT_NAMES: Record<string, string> = {
  main: 'Primary', off: 'Secondary', head: 'Head', under_top: 'Undershirt', under_bottom: 'Underwear',
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
  return { set: it.set, hands: it.hands, model: it.model ?? null };
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
    lines.push(it.ranged ? `Range: ${Math.round(it.reach)} m (arrows never run out)` : `Reach: ${it.reach.toFixed(1)} m`);
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
 *  - `off`: **two-handers only**: where the left hand grips, metres along the haft (+Y, toward
 *    the head) from the right hand's grip (negative: below it). Since 2026-10-27 the two-handed
 *    arms follow the weapon (two-hand.ts, human-factory.ts `twoHandDrive`) and this is where the
 *    left hand goes, always. Keep one on every new two-hander, on the haft (the file's extents,
 *    less `y`).
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
  // the rod: right hand at the reel, left on the butt below it (2026-10-27)
  FishingPole: { off: -0.17 },
  Scimitar: { roll: 180 },
  Cutlass: { roll: 180 },
  Axe: { roll: 180 },
  WarHammer: { roll: 180 },
  // in the weapons file, not yet items
  Hatchet: { roll: 180 },
  Machete: { roll: 180 },
  BuilderHammer: { roll: 180 },
};

/**
 * Things held like weapons but drawn in code, not in the weapons file (the same space: metres,
 * +Y from the grip toward the tip). A child named `RodTip` marks where a fishing line hangs.
 */
const PROCEDURAL: Record<string, () => THREE.Object3D> = {
  // 2026-10-29: the starter piercing weapon (crafted.ts)
  GrillFork: () => makeGrillFork(),
  Bow: () => makeBow('Bow'),
  ShortBow: () => makeBow('ShortBow'),
  Longbow: () => makeBow('Longbow'),
  // 2026-10-26: fishing (water.ts, fishing-world.ts)
  FishingPole: () => {
    const g = new THREE.Group();
    const cork = new THREE.MeshStandardMaterial({ color: '#B58E5E', roughness: 0.95 });
    const blank = new THREE.MeshStandardMaterial({ color: '#3B2A1D', roughness: 0.45 });
    const metal = new THREE.MeshStandardMaterial({ color: '#A2A8AE', roughness: 0.35, metalness: 0.8 });
    const grip = new THREE.Mesh(new THREE.CylinderGeometry(0.017, 0.02, 0.36, 10), cork);
    grip.position.y = -0.02;
    const rod = new THREE.Mesh(new THREE.CylinderGeometry(0.0032, 0.0115, 1.95, 8), blank);
    rod.position.y = 0.16 + 1.95 / 2;
    const reel = new THREE.Mesh(new THREE.CylinderGeometry(0.032, 0.032, 0.026, 16), metal);
    reel.rotation.z = Math.PI / 2;
    reel.position.set(0, 0.03, 0.05);
    const foot = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.05, 0.03), metal);
    foot.position.set(0, 0.03, 0.025);
    g.add(grip, rod, reel, foot);
    for (const y of [0.62, 1.08, 1.48, 1.82, 2.08]) {
      const ring = new THREE.Mesh(new THREE.TorusGeometry(0.007, 0.0016, 4, 10), metal);
      ring.position.set(0, y, 0.012);
      g.add(ring);
    }
    const tip = new THREE.Object3D();
    tip.name = 'RodTip';
    tip.position.y = 2.11;
    g.add(tip);
    g.traverse((o: any) => {
      if (o.isMesh) o.castShadow = true;
    });
    return g;
  },
};

// ---------------------------------------------------------------------------
// Bows (2026-10-28): drawn in code, held in the LEFT hand (the library's Bow_* clips hold the bow in
// the left fist, arm out, and draw the string to the right cheek). In weapon_l's frame +Y runs up
// the bow and +Z points at the target, so the limbs bend toward -Z and the string lies behind the
// grip. Each frame (onBeforeRender) the string's middle follows the right hand while it is close
// to it (drawing), and an arrow sits nocked on it; let go, it snaps back.

export interface BowShape {
  /** Half the bow's length, grip to tip (m). */
  half: number;
  /** How far the tips sit behind the grip (m), and the string at rest (brace height). */
  tipBack: number;
  /** A recurve's tips flick forward again. */
  recurve: number;
  /** Limb width and thickness at the grip (m). */
  width: number;
  wood: string;
  dark: string;
  grip: string;
}

export const BOWS: Record<string, BowShape> = {
  Bow: { half: 0.74, tipBack: 0.14, recurve: 0.0, width: 0.032, wood: '#7A5230', dark: '#3E2716', grip: '#5B3B24' },
  // the goblins': short, crude, recurved
  ShortBow: { half: 0.56, tipBack: 0.11, recurve: 0.05, width: 0.03, wood: '#6B5A38', dark: '#2E2618', grip: '#4A3520' },
  // the orcs' prize: tall pale ash with dark horn tips
  Longbow: { half: 0.92, tipBack: 0.16, recurve: 0.0, width: 0.035, wood: '#C2A57A', dark: '#2A211A', grip: '#6B4428' },
};

/** A point on a bow's limb at s (0 = grip, 1 = tip; +-1 for the upper and lower limb), metres. */
export function bowLimb(b: BowShape, s: number): { y: number; z: number } {
  const t = Math.abs(s);
  // bent back toward the archer (a curve), flicked forward at the tips on a recurve
  const z = -b.tipBack * t * t + b.recurve * Math.max(0, (t - 0.75) / 0.25) ** 2;
  return { y: Math.sign(s || 1) * b.half * t, z };
}

/** Where the string's middle goes: the drawing hand (bow space), if it is near, else at rest (pure; tested). */
export function nockPoint(b: BowShape, hand: { x: number; y: number; z: number } | null): { x: number; y: number; z: number; drawn: number } {
  const rest = { x: 0, y: 0, z: bowLimb(b, 1).z, drawn: 0 };
  if (!hand) return rest;
  const back = rest.z - hand.z;
  // the hand behind the bow, near its middle, within a long draw: it holds the string
  if (back > 0.04 && back < 0.95 && Math.abs(hand.y) < 0.35 && Math.abs(hand.x) < 0.3) {
    return { x: hand.x * 0.6, y: hand.y * 0.6, z: hand.z, drawn: Math.min(1, back / 0.7) };
  }
  return rest;
}

function makeBow(model: string): THREE.Object3D {
  const b = BOWS[model];
  const g = new THREE.Group();
  const wood = new THREE.MeshStandardMaterial({ color: b.wood, roughness: 0.55 });
  const dark = new THREE.MeshStandardMaterial({ color: b.dark, roughness: 0.5 });
  const leather = new THREE.MeshStandardMaterial({ color: b.grip, roughness: 0.9 });
  wood.name = 'W_Wood';
  leather.name = 'W_Leather';
  // the limbs: a tapered tube along the curve, flattened front to back
  const n = 24;
  const pts: THREE.Vector3[] = [];
  for (let i = 0; i <= n; i++) {
    const s = -1 + (2 * i) / n;
    const p = bowLimb(b, s);
    pts.push(new THREE.Vector3(0, p.y, p.z));
  }
  const curve = new THREE.CatmullRomCurve3(pts);
  const tube = new THREE.TubeGeometry(curve, 48, 1, 8, false);
  // taper toward the tips and flatten (the tube's radius is 1: scale each ring about the curve)
  const P = tube.attributes.position;
  const segs = 48;
  for (let i = 0; i <= segs; i++) {
    const c = curve.getPointAt(i / segs);
    const t = Math.abs(i / segs - 0.5) * 2;
    const w = b.width * (1 - 0.55 * t);
    for (let j = 0; j <= 8; j++) {
      const k = i * 9 + j;
      if (k >= P.count) continue;
      const dx = P.getX(k) - c.x, dy = P.getY(k) - c.y, dz = P.getZ(k) - c.z;
      P.setXYZ(k, c.x + dx * w * 0.5, c.y + dy * w * 0.35, c.z + dz * w * 0.35);
    }
  }
  tube.computeVertexNormals();
  g.add(new THREE.Mesh(tube, wood));
  // the grip: a leather wrap round the middle; an arrow rest
  const grip = new THREE.Mesh(new THREE.CylinderGeometry(b.width * 0.62, b.width * 0.62, 0.13, 10), leather);
  g.add(grip);
  const rest = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.012, 0.03), dark);
  rest.position.set(b.width * 0.35, 0.075, 0.0);
  g.add(rest);
  // horn nocks at the tips
  for (const s of [-1, 1]) {
    const p = bowLimb(b, s);
    const tip = new THREE.Mesh(new THREE.ConeGeometry(b.width * 0.32, 0.05, 6), dark);
    tip.position.set(0, p.y + s * 0.02, p.z);
    if (s < 0) tip.rotation.x = Math.PI;
    g.add(tip);
  }
  // the string: three points, the middle one moves
  const top = bowLimb(b, 1), bot = bowLimb(b, -1);
  const sgeo = new THREE.BufferGeometry();
  sgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([0, top.y, top.z, 0, 0, top.z, 0, bot.y, bot.z]), 3));
  const string = new THREE.Line(sgeo, new THREE.LineBasicMaterial({ color: '#E8E0C8' }));
  string.frustumCulled = false;
  g.add(string);
  // the nocked arrow (shown while drawn): shaft, head, fletching; its nock at its origin, pointing +Z
  const arrow = makeArrow();
  arrow.visible = false;
  g.add(arrow);
  const tmp = new THREE.Vector3();
  const inv = new THREE.Matrix4();
  let hand: THREE.Object3D | null | undefined;
  string.onBeforeRender = () => {
    if (hand === undefined || (hand && !hand.parent)) {
      // the same character's right grip: the first ancestor (going up the arm to the spine)
      // whose bones include one
      hand = null;
      for (let up = g.parent; up && !hand; up = up.parent) {
        if (up.type === 'Scene') break;
        hand = up.getObjectByName('weapon_r') || null;
      }
    }
    let local: { x: number; y: number; z: number } | null = null;
    if (hand) {
      hand.getWorldPosition(tmp);
      g.updateWorldMatrix(true, false);
      inv.copy(g.matrixWorld).invert();
      tmp.applyMatrix4(inv);
      local = { x: tmp.x, y: tmp.y, z: tmp.z };
    }
    const k = nockPoint(b, local);
    const A = sgeo.attributes.position as THREE.BufferAttribute;
    A.setXYZ(1, k.x, k.y, k.z);
    A.needsUpdate = true;
    arrow.visible = k.drawn > 0.25;
    if (arrow.visible) {
      // from the nock over the arrow rest
      arrow.position.set(k.x, k.y, k.z);
      tmp.set(b.width * 0.35 - k.x, 0.075 - k.y, 0.02 - k.z).normalize();
      arrow.quaternion.setFromUnitVectors(PLUS_Z, tmp);
    }
  };
  g.traverse((o: any) => {
    if (o.isMesh) o.castShadow = true;
  });
  return g;
}

/** An arrow (metres): its nock at the origin, pointing +Z, 0.75 m long. */
/** The arrow the bows shoot (2026-10-29: the site's hat-shot arrow; crafted.ts), along +Z, nock at 0. */
export function makeArrow(): THREE.Group {
  return makeArrowModel();
}

const PLUS_Z = new THREE.Vector3(0, 0, 1);


/** True for a model held in the left hand even as the main weapon (the bows). */
export function heldLeft(model: string | null | undefined): boolean {
  return !!model && !!BOWS[model];
}

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
    const make = PROCEDURAL[model] as (() => THREE.Object3D) | undefined;
    const scene = make ? null : await this.load();
    const tpl = make ? null : scene?.getObjectByName(`W_${model}`);
    if (!make && !tpl) return null;
    const copy = make ? make() : tpl!.clone(true);
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
  const right = root.getObjectByName('weapon_r');
  const left = root.getObjectByName('weapon_l');
  const want = item(itemId)?.model || null;
  // a bow is the main weapon but sits in the left hand (heldLeft)
  const bone = hand === 'main' && !heldLeft(want) ? right : left;
  if (!bone || !right || !left) return;
  const token = `${hand}:${itemId ?? ''}`;
  const key = hand === 'main' ? 'b8WantedMain' : 'b8WantedOff';
  root.userData[key] = token;
  // what this hand's slot shows now, on either bone (each copy knows its slot)
  const mine = () => [...right.children, ...left.children].filter((c) => c.userData.b8Weapon && (c.userData.b8Slot ?? (c.parent === right ? 'main' : 'off')) === hand);
  const old = mine();
  if (old.length === 1 && old[0].userData.b8Weapon === want && old[0].parent === bone) return;
  const fresh = want ? await models.create(want) : null;
  // A newer request may have come in while loading.
  if (root.userData[key] !== token) return;
  mine().forEach((c) => c.parent?.remove(c));
  if (fresh) {
    fresh.userData.b8Slot = hand;
    bone.add(fresh);
  }
  // the off hand's grip on a two-hander (HOLD.off), read by human-factory.ts twoHandGrip
  if (hand === 'main') right.userData.b8OffGrip = want && !heldLeft(want) ? HOLD[want]?.off ?? null : null;
}
