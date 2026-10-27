// Builds Bacon8 humans from an Appearance: the body GLB (skeleton, body, garments, eyes,
// brows, lashes, 20 clips), hair and facial hair GLBs bound to the same bones, morph
// targets for the shape sliders, tinted materials, and body regions hidden under clothes.
// What it wears comes from its gear (setWorn, wardrobe.ts), not from the look.
//
// On top of the animation (postAnimate, after the mixer): the bones some morphs move
// (Shoulders_Broad moves the arms), a relaxed hand when a hand is empty, and the body's
// posture correction (the manifest's "posture": the female's pelvis tilted back a little).
//
// Files (served from the models volume, see BaconWorld.Models.human_assets/0):
//   /models/Humans/Male.glb, Female.glb            bodies (meshopt-compressed)
//   /models/Humans/Hair/<file>.glb                 hair and facial hair styles
//   /models/Humans/Hair/icons/<file>.png           style thumbnails for the creator
// The manifests (Male.json, Female.json, Hair/hair_manifest.json) reach the client through
// the LiveView (data-human-assets), because /models only serves runtime formats.
//
// Sharing: every instance of a body shares geometry with the template (per outfit, the
// body's index buffer drops the triangles hidden under the clothes; one per combination,
// cached here). Each instance has its own materials (tints) and morph influences.
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, MeshoptDecoder, SkeletonUtils } from '../../../../assets/js/vendor/three-loaders';
import { Appearance, Body, browColor, morphWeights, normalizeAppearance } from './appearance';
import { UNITS_PER_METRE } from './controls-math';
import { modelUrl } from './asset-url';
import { item as catalogItem } from './items';
import { twoHandPose, type TwoHandPose } from './two-hand';
import {
  Gear, KEEP_TRANSLATION, WornGarment, approach, boneOffsets, designFiles, gearKey, hiddenFor, relaxedCurl, relaxedSpread, wornGarments,
} from './wardrobe';

export const HUMANS_BASE = '/models/Humans';

/**
 * The shipped animation packs' forearm twist bones are wrong in many clips (every
 * authored weapon clip, a few library ones): the pipeline halved the hand's roll without
 * wrapping it, so a hand turned -44 degrees put its twist bone at +158 and the forearm
 * wrung like a towel (most visibly holding daggers). A twist bone holds about half the
 * hand's roll, at most 90 degrees (the library clips' retarget gives it up to 117), so a
 * track that goes past 120 is rebuilt from the hand's track as half its wrapped roll.
 * Fixed in the pipeline too (b8_anim.twist_forearm); harmless once the packs are rebuilt.
 */
export function fixForearmTwist(clips: THREE.AnimationClip[]): THREE.AnimationClip[] {
  const LIMIT = (120 * Math.PI) / 180;
  const roll = (y: number, w: number) => {
    const a = 2 * Math.atan2(y, w);
    return a > Math.PI ? a - 2 * Math.PI : a < -Math.PI ? a + 2 * Math.PI : a;
  };
  for (const c of clips) {
    for (const side of ['l', 'r']) {
      const ti = c.tracks.findIndex((t) => t.name === `lowerarm_twist_01_${side}.quaternion`);
      const hand = c.tracks.find((t) => t.name === `hand_${side}.quaternion`);
      if (ti < 0 || !hand) continue;
      const tv = c.tracks[ti].values;
      let bad = false;
      for (let i = 0; i < tv.length && !bad; i += 4) bad = Math.abs(roll(tv[i + 1], tv[i + 3])) > LIMIT;
      if (!bad) continue;
      const hv = hand.values;
      const out = new Float32Array(hv.length);
      for (let i = 0; i < hv.length; i += 4) {
        const half = roll(hv[i + 1], hv[i + 3]) * 0.5;
        out[i + 1] = Math.sin(half / 2);
        out[i + 3] = Math.cos(half / 2);
      }
      c.tracks[ti] = new THREE.QuaternionKeyframeTrack(c.tracks[ti].name, Array.from(hand.times), Array.from(out));
    }
  }
  return clips;
}

export interface StyleEntry {
  id: string;
  label: string;
  file: string;
  icon?: string;
  morphs?: string[];
  material?: string;
  opacity?: number;
}

export interface HumanAssets {
  bodies?: Partial<Record<'Male' | 'Female', any>>; // B8_<Body>.json manifests
  hair?: Partial<Record<'Male' | 'Female', { hair: StyleEntry[]; facial?: StyleEntry[]; aliases?: Record<string, string> }>>;
}

interface BodyAsset {
  tag: 'Male' | 'Female';
  scene: THREE.Object3D;
  clips: THREE.AnimationClip[];
  manifest: any;
  bodyGeo: THREE.BufferGeometry | null;
}

const TAG: Record<Body, 'Male' | 'Female'> = { male: 'Male', female: 'Female' };

/**
 * The clips key every bone's translation at its rest value. Only the root, the pelvis and the
 * weapon grips really move; the rest are dropped, so the bones the morphs move (and the
 * posture correction) aren't put back every frame.
 */
export function stripTranslations(clips: THREE.AnimationClip[]): THREE.AnimationClip[] {
  for (const c of clips) {
    c.tracks = c.tracks.filter((t) => {
      const dot = t.name.lastIndexOf('.');
      return t.name.slice(dot + 1) !== 'position' || KEEP_TRANSLATION.has(t.name.slice(0, dot));
    });
  }
  return clips;
}

// Region ids hidden under each garment, used when the manifest isn't available.
const DEFAULT_HIDES: Record<string, number[]> = {
  Top_Tee: [1, 2, 4], Top_Tank: [2], Top_LongSleeve: [1, 2, 4, 5, 6],
  Bottom_Shorts: [3, 8], Bottom_Pants: [3, 8, 9, 10, 11],
  Shoes_Sneakers: [12], Shoes_Boots: [12, 14, 11],
};

export class HumanFactory {
  private loader: GLTFLoader;
  private bodies = new Map<Body, Promise<BodyAsset>>();
  private parts = new Map<string, Promise<THREE.Object3D | null>>();
  private packs = new Map<string, Promise<THREE.AnimationClip[]>>();
  private filtered = new WeakMap<THREE.BufferGeometry, Map<string, THREE.BufferGeometry>>();
  private textures = new Map<string, Promise<THREE.Texture | null>>();
  assets: HumanAssets;

  constructor(assets: HumanAssets = {}) {
    this.loader = new GLTFLoader();
    this.loader.setMeshoptDecoder(MeshoptDecoder);
    this.assets = assets || {};
  }

  setAssets(assets: HumanAssets | null | undefined) {
    if (assets) this.assets = assets;
  }

  styles(body: Body): { hair: StyleEntry[]; facial: StyleEntry[]; aliases: Record<string, string> } {
    const s = this.assets.hair?.[TAG[body]];
    return { hair: s?.hair || [], facial: body === 'male' ? s?.facial || [] : [], aliases: s?.aliases || {} };
  }

  /** A style by id, or by an id it replaced (looks saved before the style set changed). */
  findStyle(list: StyleEntry[], id: string, aliases: Record<string, string> = {}): StyleEntry | null {
    if (id === 'none') return null;
    return list.find((s) => s.id === id) || (aliases[id] ? list.find((s) => s.id === aliases[id]) : undefined) || null;
  }

  iconUrl(entry: StyleEntry): string | null {
    return entry.icon ? modelUrl(`${HUMANS_BASE}/Hair/${entry.icon}`) : null;
  }

  private load(url: string): Promise<any> {
    return new Promise((resolve, reject) => this.loader.load(modelUrl(url), resolve, undefined, reject));
  }

  loadBody(body: Body): Promise<BodyAsset> {
    let p = this.bodies.get(body);
    if (!p) {
      const tag = TAG[body];
      p = this.load(`${HUMANS_BASE}/${tag}.glb`).then((gltf: any) => {
        const scene: THREE.Object3D = gltf.scene;
        const bodyMesh = scene.getObjectByName(`${tag}_Body`) as THREE.SkinnedMesh | undefined;
        return {
          tag,
          scene,
          clips: fixForearmTwist(stripTranslations(gltf.animations || [])),
          manifest: this.assets.bodies?.[tag] || null,
          bodyGeo: bodyMesh ? (bodyMesh.geometry as THREE.BufferGeometry) : null,
        } as BodyAsset;
      });
      this.bodies.set(body, p);
      p.catch(() => this.bodies.delete(body));
    }
    return p;
  }

  /**
   * The B8 animation packs for a body (Core: locomotion, strafes, reactions, social;
   * Combat: every weapon stance and swing), loaded once and shared by everyone with
   * that body. A missing pack resolves to no clips: the body's own 20 stand in.
   * The skeleton creatures share the male's (they are rigged on his armature).
   */
  loadAnimPacks(body: Body | 'Male' | 'Female'): Promise<THREE.AnimationClip[]> {
    const tag = body === 'male' || body === 'Male' ? 'Male' : 'Female';
    const dir = `${HUMANS_BASE}/Anims`;
    let p = this.packs.get(tag);
    if (!p) {
      const one = (pack: string) =>
        this.load(`${dir}/B8_${tag}_Anims_${pack}.glb`)
          .then((g: any) => fixForearmTwist(stripTranslations((g.animations || []) as THREE.AnimationClip[])))
          .catch((err) => {
            console.warn('[humans] animation pack failed to load', tag, pack, err);
            return [] as THREE.AnimationClip[];
          });
      p = Promise.all([one('Core'), one('Combat')]).then(([a, b]) => [...a, ...b]);
      this.packs.set(tag, p);
    }
    return p;
  }

  /** Loads (once) a hair / facial hair GLB and returns its scene (template). */
  loadPart(file: string): Promise<THREE.Object3D | null> {
    let p = this.parts.get(file);
    if (!p) {
      p = this.load(`${HUMANS_BASE}/Hair/${file}`).then((g: any) => g.scene as THREE.Object3D).catch((err) => {
        console.warn('[humans] part failed to load', file, err);
        return null;
      });
      this.parts.set(file, p);
    }
    return p;
  }

  /** A wardrobe texture (packed data: no colour space, glTF's UV orientation), loaded once. */
  texture(rel: string): Promise<THREE.Texture | null> {
    let p = this.textures.get(rel);
    if (!p) {
      p = new Promise((resolve) => {
        new THREE.TextureLoader().load(
          modelUrl(`${HUMANS_BASE}/${rel}`),
          (t) => {
            t.flipY = false;
            t.colorSpace = THREE.NoColorSpace;
            t.anisotropy = 4;
            resolve(t);
          },
          undefined,
          () => {
            console.warn('[humans] wardrobe texture failed to load', rel);
            resolve(null);
          }
        );
      });
      this.textures.set(rel, p);
    }
    return p;
  }

  /** The body geometry with the triangles under `hidden` regions removed (cached). */
  bodyGeometry(asset: BodyAsset, hidden: number[]): THREE.BufferGeometry | null {
    return asset.bodyGeo ? this.filteredGeometry(asset.bodyGeo, hidden) : null;
  }

  /**
   * A mesh's geometry without the triangles whose three corners are all in `hidden` regions
   * (vertex attribute `_region`): the skin under clothes, and the parts of a garment under
   * another (trousers under a shirt's hem or a boot). Cached per template and hidden set.
   */
  filteredGeometry(tpl: THREE.BufferGeometry, hidden: number[]): THREE.BufferGeometry {
    let cache = this.filtered.get(tpl);
    if (!cache) {
      cache = new Map();
      this.filtered.set(tpl, cache);
    }
    const key = [...new Set(hidden)].sort((a, b) => a - b).join(',');
    const hit = cache.get(key);
    if (hit) return hit;
    const region = tpl.getAttribute('_region') as THREE.BufferAttribute | undefined;
    const index = tpl.getIndex();
    let geo: THREE.BufferGeometry;
    if (!region || !index || key === '') {
      geo = tpl;
    } else {
      const hide = new Set(hidden);
      const src = index.array as ArrayLike<number>;
      const keep: number[] = [];
      const groups: { start: number; count: number; materialIndex?: number }[] = [];
      const ranges = tpl.groups.length ? tpl.groups : [{ start: 0, count: src.length, materialIndex: undefined }];
      for (const r of ranges) {
        const start = keep.length;
        const end = Math.min(src.length, r.start + r.count);
        for (let i = r.start; i + 2 < end; i += 3) {
          const a = src[i], b = src[i + 1], c = src[i + 2];
          if (hide.has(Math.round(region.getX(a))) && hide.has(Math.round(region.getX(b))) && hide.has(Math.round(region.getX(c)))) continue;
          keep.push(a, b, c);
        }
        groups.push({ start, count: keep.length - start, materialIndex: r.materialIndex });
      }
      if (keep.length === src.length) {
        geo = tpl;
      } else {
        geo = new THREE.BufferGeometry();
        for (const name of Object.keys(tpl.attributes)) geo.setAttribute(name, tpl.attributes[name]);
        geo.morphAttributes = tpl.morphAttributes;
        geo.morphTargetsRelative = tpl.morphTargetsRelative;
        const Arr = (index.array as any).constructor;
        geo.setIndex(new THREE.BufferAttribute(new Arr(keep), 1));
        if (tpl.groups.length) for (const g of groups) geo.addGroup(g.start, g.count, g.materialIndex);
        if (tpl.boundingBox) geo.boundingBox = tpl.boundingBox.clone();
        if (tpl.boundingSphere) geo.boundingSphere = tpl.boundingSphere.clone();
        geo.name = `${tpl.name || 'Mesh'}#${key}`;
      }
    }
    cache.set(key, geo);
    return geo;
  }

  hiddenRegions(asset: BodyAsset, garments: string[]): number[] {
    return hiddenFor(garments, asset.manifest?.hides || DEFAULT_HIDES);
  }

  async create(appearance: Appearance | unknown, fallbackBody: Body = 'male', gear?: Gear | null): Promise<HumanInstance> {
    const a = normalizeAppearance(appearance, fallbackBody);
    const asset = await this.loadBody(a.body);
    const inst = new HumanInstance(this, asset, a);
    if (gear) inst.setWorn(gear);
    await inst.apply(a, true);
    return inst;
  }
}

// Garments a body file may hold (the manifest's "garments" lists its own).
const GARMENTS = ['Top_Tee', 'Top_Tank', 'Top_LongSleeve', 'Bottom_Shorts', 'Bottom_Pants', 'Shoes_Sneakers', 'Shoes_Boots',
  'Under_Top_Contour', 'Under_Top_Band', 'Under_Bottom'];
// Polygon offsets (factor, units) so layers that touch draw in order: underwear over skin,
// trousers over underwear, tops over the trousers' waistband.
const LAYER_OFFSET: Array<[string, number, number]> = [['Under_', -1, -1], ['Bottom_', -1, -2], ['Top_', -1.5, -3]];

const PATCHED = 'b8wardrobe1';

/** Makes a wardrobe material draw a packed design texture in the item's colours. */
function wardrobeMaterial(m: THREE.MeshStandardMaterial) {
  if ((m.userData as any).b8u) return (m.userData as any).b8u;
  const u = {
    b8Main: { value: new THREE.Color(1, 1, 1) },
    b8Trim: { value: new THREE.Color(1, 1, 1) },
    b8Accent: { value: new THREE.Color(1, 1, 1) },
    b8Gain: { value: Number((m.userData as any)?.tint_gain) || 1.25 },
  };
  (m.userData as any).b8u = u;
  m.color.set(0xffffff);
  m.alphaTest = 0.5;
  m.alphaToCoverage = true;
  m.transparent = false;
  m.side = THREE.DoubleSide;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, u);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform vec3 b8Main;\nuniform vec3 b8Trim;\nuniform vec3 b8Accent;\nuniform float b8Gain;')
      .replace('#include <map_fragment>', `#ifdef USE_MAP
  vec4 b8t = texture2D( map, vMapUv );
  diffuseColor.rgb *= mix( mix( b8Main, b8Accent, b8t.b ), b8Trim, b8t.g ) * ( b8t.r * b8Gain );
  diffuseColor.a *= b8t.a;
#endif`);
  };
  m.customProgramCacheKey = () => PATCHED;
  return u;
}

const _q = new THREE.Quaternion();
const _w1 = new THREE.Vector3(), _w2 = new THREE.Vector3(), _w3 = new THREE.Vector3(), _w4 = new THREE.Vector3();
const _w5 = new THREE.Vector3(), _w6 = new THREE.Vector3(), _w7 = new THREE.Vector3();
const _rq = new THREE.Quaternion(), _rw = new THREE.Quaternion(), _rp = new THREE.Quaternion();

/** Turns `bone` in the world by the rotation taking `from` to `to` (unit vectors), keeping its children's world positions in step. */
function rotateWorld(bone: THREE.Object3D, from: THREE.Vector3, to: THREE.Vector3) {
  _rq.setFromUnitVectors(from, to);
  bone.getWorldQuaternion(_rw);
  _rw.premultiply(_rq);
  if (bone.parent) bone.parent.getWorldQuaternion(_rp);
  else _rp.identity();
  bone.quaternion.copy(_rp.invert().multiply(_rw));
  bone.updateWorldMatrix(false, true);
}
const RIDE_SPREAD_DEG = 32;

/** Turns a bone about a world axis by `angle` (radians), keeping its children's local poses. */
function turnWorld(bone: THREE.Object3D, axis: THREE.Vector3, angle: number) {
  if (!angle) return;
  if (bone.parent) bone.parent.updateWorldMatrix(true, false);
  _rq.setFromAxisAngle(axis, angle);
  bone.getWorldQuaternion(_rw);
  _rw.premultiply(_rq);
  if (bone.parent) bone.parent.getWorldQuaternion(_rp);
  else _rp.identity();
  bone.quaternion.copy(_rp.invert().multiply(_rw));
  bone.updateWorldMatrix(false, true);
}

/**
 * The off hand's turn on a two-hander's haft relative to the weapon's own frame (about the haft):
 * weapon_l is the mirror of weapon_r, so a left fist holding the same frame wraps the haft the
 * other way round (2026-10-27, measured in the harness).
 */
const TWO_HAND_LEFT_TURN = new THREE.Quaternion();

/**
 * An arm onto a wrist position: the elbow toward `pole` (world), the upper arm turned so the elbow
 * is a true hinge (the forearm bends about the bones' own +X, as the rig's rest pose does), the
 * hand at world rotation `handQ`, and the forearm's roll shared half with its twist bone.
 */
/** Lifts a clavicle (up to 22 degrees) as the hand it carries goes above the shoulder. */
function shrug(cl: THREE.Object3D, ua: THREE.Object3D, W: THREE.Vector3, up: THREE.Vector3) {
  cl.updateWorldMatrix(true, false);
  ua.updateWorldMatrix(false, false);
  const C = cl.getWorldPosition(new THREE.Vector3());
  const A = ua.getWorldPosition(new THREE.Vector3());
  const span = A.distanceTo(C) * 3.2; // about an arm's length
  const k = THREE.MathUtils.clamp(new THREE.Vector3().subVectors(W, A).dot(up) / span, 0, 1);
  if (k <= 0) return;
  const out = new THREE.Vector3().subVectors(A, C).normalize();
  const axis = new THREE.Vector3().crossVectors(out, up);
  if (axis.lengthSq() < 1e-8) return;
  turnWorld(cl, axis.normalize(), THREE.MathUtils.degToRad(22) * k);
}

function solveArm(
  ua: THREE.Object3D,
  la: THREE.Object3D,
  hand: THREE.Object3D,
  tw: THREE.Object3D | null,
  W: THREE.Vector3,
  pole: THREE.Vector3,
  handQ: THREE.Quaternion,
  utw: THREE.Object3D | null = null,
  uaRest?: THREE.Quaternion
) {
  ua.parent?.updateWorldMatrix(true, false);
  ua.updateWorldMatrix(false, true);
  const A = ua.getWorldPosition(new THREE.Vector3());
  const B = la.getWorldPosition(new THREE.Vector3());
  const C = hand.getWorldPosition(new THREE.Vector3());
  const l1 = A.distanceTo(B), l2 = B.distanceTo(C);
  const to = new THREE.Vector3().subVectors(W, A);
  const d = THREE.MathUtils.clamp(to.length(), Math.abs(l1 - l2) + 1e-4, (l1 + l2) * 0.999);
  const u = to.normalize();
  const pl = pole.clone().addScaledVector(u, -pole.dot(u));
  if (pl.lengthSq() < 1e-8) pl.set(0, -1, 0).addScaledVector(u, -u.y);
  pl.normalize();
  const a = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
  const h = Math.sqrt(Math.max(0, l1 * l1 - a * a));
  const Bn = A.clone().addScaledVector(u, a).addScaledVector(pl, h);
  const Wn = A.clone().addScaledVector(u, d);
  const uy = new THREE.Vector3().subVectors(Bn, A).normalize();
  const f = new THREE.Vector3().subVectors(Wn, Bn).normalize();
  const uz = f.clone().addScaledVector(uy, -f.dot(uy));
  if (uz.lengthSq() < 1e-8) uz.copy(pl).multiplyScalar(-1).addScaledVector(uy, pl.dot(uy));
  uz.normalize();
  const ux = new THREE.Vector3().crossVectors(uy, uz).normalize();
  const upperQ = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(ux, uy, uz));
  const parentQ = ua.parent ? ua.parent.getWorldQuaternion(new THREE.Quaternion()) : new THREE.Quaternion();
  ua.quaternion.copy(parentQ.invert().multiply(upperQ));
  la.quaternion.setFromAxisAngle(new THREE.Vector3(1, 0, 0), Math.acos(THREE.MathUtils.clamp(uy.dot(f), -1, 1)));
  ua.updateWorldMatrix(false, true);
  const laQ = la.getWorldQuaternion(new THREE.Quaternion());
  hand.quaternion.copy(laQ.invert().multiply(handQ));
  hand.updateWorldMatrix(false, true);
  if (tw) {
    const q = hand.quaternion;
    const roll = new THREE.Quaternion(0, q.y, 0, q.w).normalize();
    tw.quaternion.identity().slerp(roll, 0.5);
    tw.updateWorldMatrix(false, true);
  }
  // the upper arm's roll away from its rest: the shoulder's twist bone takes half of it back, so
  // the deltoid doesn't wring
  if (utw && uaRest) {
    const d = uaRest.clone().invert().multiply(ua.quaternion);
    const roll = new THREE.Quaternion(0, d.y, 0, d.w).normalize();
    utw.quaternion.identity().slerp(roll.invert(), 0.5);
    utw.updateWorldMatrix(false, true);
  }
}

/**
 * (2026-10-27: only the fishing pole still uses these and twoHandGrip; every other two-hander is
 * driven by two-hand.ts through twoHandDrive.)
 * Two-handed guards (2026-10-26): where the right hand's grip (weapon_r) is held and which way the
 * weapon points, while a two-hander is held and not swinging. The library clips' idles hold
 * two-handers at the waist, hugging the body: on the male the greatsword, axe and maul lay across
 * his hips, the staff ran through his legs and the spear folded his left arm. Units: the body's
 * pelvis-to-neck height (so it fits any body), from the pelvis; x the body's left, y up, z
 * forward. `dir` is the haft's direction from the grip toward the head (+Y of the weapon). By
 * weapon model first, then by stance set. The left hand then takes the haft at the clip's spacing
 * (twoHandGrip).
 */
export const TWO_HAND_GUARDS: Record<string, { at: [number, number, number]; dir: [number, number, number] }> = {
  // a sword's middle guard: hands before the navel, the blade rising toward the foe's throat
  two_hand: { at: [-0.06, 0.42, 0.62], dir: [0.12, 0.62, 0.78] },
  // axe and maul at the ready: the haft across the body, the head up by the left shoulder
  BattleAxe: { at: [-0.16, 0.34, 0.56], dir: [0.5, 0.78, 0.38] },
  Maul: { at: [-0.16, 0.34, 0.56], dir: [0.5, 0.78, 0.38] },
  // spear and halberd: the rear hand at the right hip, the point forward and a little up
  polearm: { at: [-0.42, 0.3, 0.22], dir: [0.14, 0.26, 0.95] },
  // the staff across the body, clear of it
  staff: { at: [-0.3, 0.38, 0.6], dir: [0.6, 0.78, 0.0] },
  // a fishing pole held out over the water, the tip up (2026-10-26)
  FishingPole: { at: [-0.16, 0.42, 0.62], dir: [0.06, 0.6, 0.8] },
};

/**
 * Two-bone IK: turns `ua` and `la` so the wrist (`hand`) reaches `W`, the elbow bending toward
 * `pole` (a world direction: elbows go down and out, never up through the chest).
 */
function ik2(ua: THREE.Object3D, la: THREE.Object3D, hand: THREE.Object3D, W: THREE.Vector3, pole: THREE.Vector3) {
  const A = ua.getWorldPosition(new THREE.Vector3());
  const B = la.getWorldPosition(new THREE.Vector3());
  const C = hand.getWorldPosition(new THREE.Vector3());
  const l1 = A.distanceTo(B), l2 = B.distanceTo(C);
  const to = new THREE.Vector3().subVectors(W, A);
  const d = THREE.MathUtils.clamp(to.length(), Math.abs(l1 - l2) + 1e-4, (l1 + l2) * 0.999);
  const u = to.normalize();
  const p = pole.clone().addScaledVector(u, -pole.dot(u));
  if (p.lengthSq() < 1e-8) p.set(0, -1, 0).addScaledVector(u, -u.y);
  p.normalize();
  const a = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
  const h = Math.sqrt(Math.max(0, l1 * l1 - a * a));
  const Bn = A.clone().addScaledVector(u, a).addScaledVector(p, h);
  rotateWorld(ua, new THREE.Vector3().subVectors(B, A).normalize(), Bn.sub(A).normalize());
  const B2 = la.getWorldPosition(new THREE.Vector3()), C2 = hand.getWorldPosition(new THREE.Vector3());
  rotateWorld(la, new THREE.Vector3().subVectors(C2, B2).normalize(), new THREE.Vector3().subVectors(W, B2).normalize());
}

/** Moves `cur` toward `target` (degrees) at `rate` degrees per second. */
function approachDeg(cur: number, target: number, rate: number, dt: number): number {
  const step = rate * dt;
  return cur < target ? Math.min(target, cur + step) : Math.max(target, cur - step);
}

export class HumanInstance {
  readonly root: THREE.Group;
  readonly model: THREE.Object3D;
  readonly clips: THREE.AnimationClip[];
  readonly body: Body;
  appearance: Appearance;
  private bones = new Map<string, THREE.Bone>();
  private armature: THREE.Object3D;
  private bodyMesh: THREE.SkinnedMesh | null;
  private garments = new Map<string, THREE.Object3D>();
  private baseGeometry = new Map<THREE.Mesh, THREE.BufferGeometry>();
  private materials = new Map<string, THREE.MeshStandardMaterial[]>();
  private hair: { file: string; obj: THREE.Object3D } | null = null;
  private facial: { file: string; obj: THREE.Object3D } | null = null;
  private applying: Promise<void> = Promise.resolve();
  private disposed = false;
  /** What it wears (setWorn) and the garments that shows. */
  private gear: Gear = {};
  private worn: WornGarment[] = [];
  private wornKey = '';
  // rest pose, for the bones the morphs move and the corrections after the animation
  private restPos = new Map<string, THREE.Vector3>();
  private restQuat = new Map<string, THREE.Quaternion>();
  private parentInv = new Map<string, THREE.Matrix3>();
  private moved = new Map<string, THREE.Vector3>();
  private posture: {
    q: THREE.Quaternion;
    qi: THREE.Quaternion;
    children: THREE.Bone[];
    spine: Array<{ bone: THREE.Bone; q: THREE.Quaternion }>;
  } | null = null;
  // the shoulders brought forward (and down) after the animation: the library clips draw
  // the clavicles back about 30 degrees, which on a body with long clavicles (the male) puts
  // the arms behind the torso
  private shoulders: Array<{ bone: THREE.Bone; q: THREE.Quaternion }> = [];
  // riding: thighs turned out by RIDE_SPREAD_DEG, eased in and out
  private rideThighs: Array<{ bone: THREE.Bone; axis: THREE.Vector3; sgn: number }> = [];
  private riding = false;
  private rideW = 0;
  private gripW = 0; // the two-handed off-hand grip (twoHandGrip), eased in and out
  private guardW = 0; // the two-handed guard (twoHandGuard), eased in and out
  private twoW = 0; // the two-handed drive (twoHandDrive, two-hand.ts), eased in and out
  private twoPose: TwoHandPose | null = null;
  private guard: { at: [number, number, number]; dir: [number, number, number] } | null = null;
  // where this frame's clip put the left grip along the haft, before any correction moved
  // the arms (readClipGrip); twoHandGrip puts the hand back there
  private clipGrip: { t: number; miss: number } | null = null;
  private touched = new Set<THREE.Object3D>();
  // posture.arm_out {<what the arm does>: [upper arm, forearm, keep hand?]}: degrees out from
  // the body, per arm, eased toward the entry for what it is doing (armSets: 'free', a gear
  // set such as 'torch', 'two_hand', 'swing'); with keep hand 1 a holding hand keeps its
  // orientation, else it turns with the arm
  private armOut: Record<string, number[]> = {};
  private arms: Record<'l' | 'r', { ua: THREE.Bone; la: THREE.Bone; hand: THREE.Bone; uAxis: THREE.Vector3; lAxis: THREE.Vector3; sgn: number; cur: [number, number]; freeHand: THREE.Quaternion | null } | null> = { l: null, r: null };
  private fingers: Array<{ bone: THREE.Bone; side: 'l' | 'r'; relaxed: THREE.Quaternion }> = [];
  private handW = { l: 1, r: 1 };
  // What postAnimate last wrote to each bone, and what it found there: a bone no clip
  // keyed this frame still holds our output, and must start again from what we found
  // (or the correction compounds, 7 degrees a frame, until she stands on her head).
  private applied = new Map<THREE.Object3D, { found: THREE.Quaternion; wrote: THREE.Quaternion }>();

  constructor(private factory: HumanFactory, private asset: BodyAsset, a: Appearance) {
    this.body = a.body;
    this.appearance = a;
    this.clips = asset.clips;
    this.model = SkeletonUtils.clone(asset.scene);
    this.root = new THREE.Group();
    this.root.name = `Human_${asset.tag}`;
    this.root.add(this.model);
    const tag = asset.tag;
    this.armature = this.model.getObjectByName(`B8_${tag}`) || this.model;
    this.bodyMesh = (this.model.getObjectByName(`${tag}_Body`) as THREE.SkinnedMesh) || null;
    this.model.traverse((o: any) => {
      if (o.isBone) this.bones.set(o.name, o);
      if (o.isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
        o.frustumCulled = false;
        o.material = this.own(o.material);
      }
    });
    const names = new Set([...GARMENTS, ...Object.keys(asset.manifest?.garments || {})]);
    for (const g of names) {
      const n = this.model.getObjectByName(`${tag}_${g}`);
      if (n) {
        this.garments.set(g, n);
        n.visible = false;
      }
    }
    for (const [name, mats] of this.materials) {
      const lay = LAYER_OFFSET.find(([p]) => name.startsWith(p));
      if (!lay) continue;
      for (const m of mats) {
        m.polygonOffset = true;
        m.polygonOffsetFactor = lay[1];
        m.polygonOffsetUnits = lay[2];
      }
    }
    this.captureRest();
  }

  // The skeleton as cloned is at rest: remember it.
  private captureRest() {
    this.model.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(this.model.matrixWorld).invert();
    const m = new THREE.Matrix4();
    for (const [name, b] of this.bones) {
      this.restPos.set(name, b.position.clone());
      this.restQuat.set(name, b.quaternion.clone());
      if (b.parent) {
        m.multiplyMatrices(inv, b.parent.matrixWorld);
        this.parentInv.set(name, new THREE.Matrix3().setFromMatrix4(m).invert());
      }
    }
    // relaxed fingers: rest x the knuckle drawn in (local Z) x a curl about each joint's own X
    const X = new THREE.Vector3(1, 0, 0);
    const Z = new THREE.Vector3(0, 0, 1);
    // a body may tune its own (manifest `posture.relaxed_hand`, the same table as wardrobe.ts's
    // RELAXED; `posture` is what BaconWorld.Models passes the client)
    const relax = this.asset.manifest?.posture?.relaxed_hand || undefined;
    for (const [name, b] of this.bones) {
      const deg = relaxedCurl(name, relax);
      if (deg == null) continue;
      const q = this.restQuat.get(name)!.clone()
        .multiply(new THREE.Quaternion().setFromAxisAngle(Z, THREE.MathUtils.degToRad(relaxedSpread(name, relax))))
        .multiply(new THREE.Quaternion().setFromAxisAngle(X, THREE.MathUtils.degToRad(deg)));
      this.fingers.push({ bone: b, side: name.endsWith('_l') ? 'l' : 'r', relaxed: q });
    }
    // posture: the pelvis turned about her side-to-side axis (positive tucks it under) with
    // the legs kept where they were. With `spine_deg` [lumbar, mid, chest] each spine bone
    // also turns by its amount, same sense (positive leans its top back). The female's
    // [-24, -9, 9] with a 24-degree tuck keeps the lumbar where it was and flattens the joint
    // above the pelvis (no S-curve or crease). Without spine_deg the whole spine is kept.
    const posture = this.asset.manifest?.posture || {};
    const tilt = Number(posture.pelvis_tilt_deg) || 0;
    const spineDeg: number[] | null = Array.isArray(posture.spine_deg) ? posture.spine_deg.map(Number) : null;
    const pelvis = this.bones.get('pelvis');
    const axisIn = (b: THREE.Object3D, x: number, y: number, z: number) => {
      m.multiplyMatrices(inv, b.matrixWorld);
      const wq = new THREE.Quaternion().setFromRotationMatrix(m);
      return new THREE.Vector3(x, y, z).applyQuaternion(wq.invert()).normalize();
    };
    const sideAxis = (b: THREE.Object3D) => axisIn(b, 1, 0, 0);
    // posture.clavicle_deg [forward, down]: each clavicle turned about the body's up axis
    // (positive brings the shoulder forward) and its forward axis (positive lowers it)
    const clav = Array.isArray(posture.clavicle_deg) ? posture.clavicle_deg.map(Number) : [Number(posture.clavicle_deg) || 0, 0];
    for (const side of ['l', 'r'] as const) {
      const b = this.bones.get(`clavicle_${side}`);
      const fwd = clav[0] || 0;
      const down = clav[1] || 0;
      if (!b || (!fwd && !down)) continue;
      const sgn = side === 'l' ? -1 : 1; // +X is the body's left
      const q = new THREE.Quaternion()
        .setFromAxisAngle(axisIn(b, 0, 1, 0), sgn * THREE.MathUtils.degToRad(fwd))
        .multiply(new THREE.Quaternion().setFromAxisAngle(axisIn(b, 0, 0, 1), sgn * THREE.MathUtils.degToRad(down)));
      this.shoulders.push({ bone: b, q });
    }
    // riding (setRiding): the thighs apart, astride the mount (the sitting clip has them together)
    for (const side of ['l', 'r'] as const) {
      const th = this.bones.get(`thigh_${side}`);
      if (th) this.rideThighs.push({ bone: th, axis: axisIn(th, 0, 0, 1), sgn: side === 'l' ? 1 : -1 });
    }
    // posture.free_hand_deg [x, y, z]: an empty hand turned about its own axes (the right
    // hand's; the left mirrors y and z), on top of the relaxed fingers
    const fh = Array.isArray(posture.free_hand_deg) ? posture.free_hand_deg.map(Number) : null;
    if ((posture.arm_out && typeof posture.arm_out === 'object') || fh) {
      for (const [k, v] of Object.entries((posture.arm_out || {}) as Record<string, unknown>)) {
        if (Array.isArray(v)) this.armOut[k] = v.map(Number);
      }
      for (const side of ['l', 'r'] as const) {
        const ua = this.bones.get(`upperarm_${side}`);
        const la = this.bones.get(`lowerarm_${side}`);
        const hand = this.bones.get(`hand_${side}`);
        if (!ua || !la || !hand || la.parent !== ua || hand.parent !== la) continue;
        // out = about the body's forward axis, away from the body (+X is the body's left)
        const m = side === 'l' ? -1 : 1;
        const freeHand = fh
          ? new THREE.Quaternion().setFromEuler(new THREE.Euler(THREE.MathUtils.degToRad(fh[0] || 0), m * THREE.MathUtils.degToRad(fh[1] || 0), m * THREE.MathUtils.degToRad(fh[2] || 0)))
          : null;
        this.arms[side] = { ua, la, hand, uAxis: axisIn(ua, 0, 0, 1), lAxis: axisIn(la, 0, 0, 1), sgn: side === 'l' ? 1 : -1, cur: [0, 0], freeHand };
      }
    }
    if ((tilt || spineDeg) && pelvis) {
      const q = new THREE.Quaternion().setFromAxisAngle(sideAxis(pelvis), -THREE.MathUtils.degToRad(tilt));
      const keep = spineDeg ? ['thigh_l', 'thigh_r'] : ['spine_01', 'thigh_l', 'thigh_r'];
      const children = keep.map((n) => this.bones.get(n)).filter((b): b is THREE.Bone => !!b && b.parent === pelvis);
      const spine = spineDeg
        ? ['spine_01', 'spine_02', 'spine_03']
            .map((n, i) => ({ bone: this.bones.get(n), deg: spineDeg[i] || 0 }))
            .filter((s): s is { bone: THREE.Bone; deg: number } => !!s.bone && s.deg !== 0)
            .map((s) => ({ bone: s.bone, q: new THREE.Quaternion().setFromAxisAngle(sideAxis(s.bone), -THREE.MathUtils.degToRad(s.deg)) }))
        : [];
      this.posture = { q, qi: q.clone().invert(), children, spine };
    }
  }

  /** Clones a material for this instance and indexes it by name (role). */
  private own(m: THREE.Material | THREE.Material[]): any {
    if (Array.isArray(m)) return m.map((x) => this.own(x));
    const c = (m as THREE.MeshStandardMaterial).clone();
    const list = this.materials.get(c.name) || [];
    list.push(c);
    this.materials.set(c.name, list);
    return c;
  }

  /**
   * Sets a role's colour. Textured roles multiply their texture by it: the skin's texture is
   * neutral grey on average, so its material carries a gain (glTF extras "tint_gain") that
   * makes texture x colour come out at the chosen tone.
   */
  private tint(name: string, hex: string) {
    for (const m of this.materials.get(name) || []) {
      m.color.set(hex);
      const gain = Number((m.userData as any)?.tint_gain) || 1;
      if (gain !== 1) m.color.multiplyScalar(gain);
    }
  }

  /** Applies a look. A different body needs a new instance (see HumanFactory.create). */
  apply(next: Appearance | unknown, first = false): Promise<void> {
    const a = normalizeAppearance(next, this.body);
    this.applying = this.applying.then(() => this.applyNow(a, first)).catch((err) => console.warn('[humans] apply failed', err));
    return this.applying;
  }

  private async applyNow(a: Appearance, first: boolean) {
    if (this.disposed) return;
    const prev = this.appearance;
    this.appearance = a;
    this.root.scale.setScalar(UNITS_PER_METRE * a.height);

    // clothes (from the gear) and the regions under them
    this.dress();

    // colours
    this.tint('Skin', a.skin);
    this.tint('Iris', a.eyes);
    this.tint('Brows', browColor(a));

    // hair and facial hair (swap only when the style changes)
    const styles = this.factory.styles(this.body);
    const want = (list: StyleEntry[], id: string) => this.factory.findStyle(list, id, styles.aliases);
    const hairEntry = want(styles.hair, a.hair.style);
    const facialEntry = this.body === 'male' ? want(styles.facial, a.facial.style) : null;
    if (first || !prev || prev.hair.style !== a.hair.style || !this.hair !== !hairEntry) {
      this.hair = await this.swapPart(this.hair, hairEntry);
    }
    if (first || !prev || prev.facial.style !== a.facial.style || !this.facial !== !facialEntry) {
      this.facial = await this.swapPart(this.facial, facialEntry);
    }
    if (this.disposed) return;
    this.tintPart(this.hair, a.hair.color);
    this.tintPart(this.facial, a.facial.color || a.hair.color);

    // morph targets on every mesh that has them (body, garments, facial hair)
    const w = morphWeights(a);
    this.root.traverse((m: any) => {
      if (!m.isMesh || !m.morphTargetDictionary || !m.morphTargetInfluences) return;
      for (const [name, i] of Object.entries(m.morphTargetDictionary as Record<string, number>)) {
        m.morphTargetInfluences[i] = w[name] || 0;
      }
    });
    this.moveBones(w);
  }

  /**
   * What it wears: item ids by slot (BaconWorld.Inventory's gear; hands are ignored here).
   * Shows those garments, hides what they cover, and colours them.
   */
  setWorn(gear: Gear | null | undefined) {
    this.gear = { ...(gear || {}) };
    this.worn = wornGarments(this.body, this.gear, (id) => catalogItem(id) as any);
    const key = this.worn.map((g) => `${g.garment}:${g.design}:${JSON.stringify(g.colors)}`).join('|');
    if (key === this.wornKey) return;
    this.wornKey = key;
    this.dress();
  }

  /** The gear last given to setWorn. */
  getWorn(): Gear {
    return { ...this.gear };
  }

  private dress() {
    if (this.disposed) return;
    const shown = new Set(this.worn.map((g) => g.garment));
    for (const [id, node] of this.garments) node.visible = shown.has(id);
    const hidden = this.factory.hiddenRegions(this.asset, [...shown].filter((g) => this.garments.has(g)));
    if (this.bodyMesh) {
      const geo = this.factory.bodyGeometry(this.asset, hidden);
      if (geo && this.bodyMesh.geometry !== geo) this.bodyMesh.geometry = geo;
    }
    // a garment worn under another loses the part the other covers
    for (const node of this.garments.values()) {
      if (!node.visible) continue;
      node.traverse((m: any) => {
        if (!m.isMesh) return;
        let base = this.baseGeometry.get(m);
        if (!base) {
          base = m.geometry as THREE.BufferGeometry;
          this.baseGeometry.set(m, base);
        }
        const geo = this.factory.filteredGeometry(base, hidden);
        if (m.geometry !== geo) m.geometry = geo;
      });
    }
    for (const g of this.worn) {
      const c = g.colors;
      if (g.design) {
        void this.applyDesign(g);
      } else if (g.garment.startsWith('Shoes_')) {
        if (c.upper) this.tint(`${g.garment}_Upper`, c.upper);
        if (c.sole) this.tint(`${g.garment}_Sole`, c.sole);
        if (c.laces) this.tint(`${g.garment}_Laces`, c.laces);
      } else {
        if (c.main) this.tint(`${g.garment}_Main`, c.main);
        this.tint(`${g.garment}_Trim`, c.trim || c.main || '#FFFFFF');
      }
    }
  }

  // A garment made from the body: its design texture, tinted with the item's colours.
  private async applyDesign(g: WornGarment) {
    const mats = this.materials.get(g.garment) || [];
    if (!mats.length || !g.design) return;
    const dir = this.asset.manifest?.wardrobe?.dir || 'Wardrobe';
    const files = designFiles(dir, g.garment, g.design);
    const [mask, normal] = await Promise.all([this.factory.texture(files.mask), this.factory.texture(files.normal)]);
    if (this.disposed) return;
    // a newer look may have replaced this design while the textures loaded
    const now = this.worn.find((x) => x.garment === g.garment);
    if (!now || now.design !== g.design || now.item !== g.item) return;
    for (const m of mats) {
      const u = wardrobeMaterial(m);
      u.b8Main.value.set(g.colors.main || '#FFFFFF');
      u.b8Trim.value.set(g.colors.trim || g.colors.main || '#FFFFFF');
      u.b8Accent.value.set(g.colors.accent || g.colors.main || '#FFFFFF');
      const changed = m.map !== mask || m.normalMap !== normal;
      m.map = mask;
      m.normalMap = normal;
      if (changed) m.needsUpdate = true;
    }
  }

  // The bones the morphs move (manifest "joint_offsets", model space): each bone's rest
  // position plus its own move less its parent's, in the parent's frame.
  private moveBones(w: Record<string, number>) {
    const D = boneOffsets(this.asset.manifest?.joint_offsets, w);
    const names = new Set([...Object.keys(D), ...this.moved.keys()]);
    const v = new THREE.Vector3();
    for (const name of names) {
      const b = this.bones.get(name);
      const rest = this.restPos.get(name);
      if (!b || !rest) continue;
      const d = D[name] || [0, 0, 0];
      const pd = (b.parent && (D as any)[b.parent.name]) || [0, 0, 0];
      v.set(d[0] - pd[0], d[1] - pd[1], d[2] - pd[2]);
      const inv = this.parentInv.get(name);
      if (inv) v.applyMatrix3(inv);
      b.position.copy(rest).add(v);
      if (v.lengthSq() > 0) this.moved.set(name, v.clone());
      else this.moved.delete(name);
    }
  }

  /**
   * After the mixer each frame: the posture correction, and relaxed fingers on the hands
   * that hold nothing (`free.l`, `free.r`; a punch closes them again).
   */
  postAnimate(
    dt: number,
    free: { l: boolean; r: boolean } = { l: true, r: true },
    armSets?: { l: string; r: string; two?: boolean; set?: string; twoSwing?: { name: string; x: number } | null }
  ) {
    this.touched.clear();
    this.clipGrip = armSets?.two ? this.readClipGrip() : null;
    if (this.posture) {
      const pelvis = this.bones.get('pelvis')!;
      this.fromAnimated(pelvis);
      pelvis.quaternion.multiply(this.posture.q);
      this.wrote(pelvis);
      for (const c of this.posture.children) {
        this.fromAnimated(c);
        c.quaternion.premultiply(this.posture.qi);
        this.wrote(c);
        const base = this.restPos.get(c.name)!.clone();
        const mv = this.moved.get(c.name);
        if (mv) base.add(mv);
        c.position.copy(base.applyQuaternion(this.posture.qi));
      }
      for (const s of this.posture.spine) {
        this.fromAnimated(s.bone);
        s.bone.quaternion.multiply(s.q);
        this.wrote(s.bone);
      }
    }
    for (const s of this.shoulders) {
      this.fromAnimated(s.bone);
      s.bone.quaternion.multiply(s.q);
      this.wrote(s.bone);
    }
    this.handW.l = approach(this.handW.l, free.l ? 1 : 0, 6, dt);
    this.handW.r = approach(this.handW.r, free.r ? 1 : 0, 6, dt);
    for (const side of ['l', 'r'] as const) {
      const a = this.arms[side];
      if (!a) continue;
      const doing = armSets ? armSets[side] : free[side] ? 'free' : 'held';
      const want = this.armOut[doing] || [0, 0];
      a.cur[0] = approachDeg(a.cur[0], want[0] || 0, 90, dt);
      a.cur[1] = approachDeg(a.cur[1], want[1] || 0, 90, dt);
      this.fromAnimated(a.ua);
      this.fromAnimated(a.la);
      this.fromAnimated(a.hand);
      if (a.cur[0] || a.cur[1]) {
        const ua0 = a.ua.quaternion.clone();
        const handWorld = ua0.clone().multiply(a.la.quaternion).multiply(a.hand.quaternion); // in the clavicle's frame
        a.ua.quaternion.multiply(_q.setFromAxisAngle(a.uAxis, a.sgn * THREE.MathUtils.degToRad(a.cur[0])));
        a.la.quaternion.multiply(_q.setFromAxisAngle(a.lAxis, a.sgn * THREE.MathUtils.degToRad(a.cur[1])));
        if (!free[side] && want[2]) a.hand.quaternion.copy(a.ua.quaternion.clone().multiply(a.la.quaternion).invert().multiply(handWorld));
      }
      const hw = this.handW[side];
      if (a.freeHand && hw > 0.001) a.hand.quaternion.multiply(_q.identity().slerp(a.freeHand, hw));
      this.wrote(a.ua);
      this.wrote(a.la);
      this.wrote(a.hand);
    }
    // A two-hander (2026-10-27): the weapon is placed by two-hand.ts (its guard, or the swing under
    // way) and both arms are put on it. The fishing pole keeps the older guard and grip.
    const held = this.bones.get('weapon_r')?.children.find((c) => c.userData.b8Weapon)?.userData.b8Weapon as string | undefined;
    const fishing = held === 'FishingPole';
    const drive = armSets?.two && !fishing ? twoHandPose(armSets.set || '', armSets.twoSwing) : null;
    if (drive) this.twoPose = drive;
    this.twoW = approach(this.twoW, drive ? 1 : 0, 8, dt);
    if (this.twoW > 0.001 && this.twoPose) this.twoHandDrive(this.twoPose, this.twoW);
    const guard = fishing && armSets?.two ? this.guardFor(armSets.set) : null;
    if (guard) this.guard = guard;
    this.guardW = approach(this.guardW, guard ? 1 : 0, 6, dt);
    if (this.guardW > 0.001 && this.guard) this.twoHandGuard(this.guard, this.guardW);
    this.gripW = approach(this.gripW, fishing && armSets?.two ? 1 : 0, 8, dt);
    if (this.gripW > 0.001) this.twoHandGrip(this.gripW);
    this.rideW = approach(this.rideW, this.riding ? 1 : 0, 3, dt);
    if (this.rideW > 0.001) {
      for (const t of this.rideThighs) {
        this.fromAnimated(t.bone);
        t.bone.quaternion.multiply(_q.setFromAxisAngle(t.axis, t.sgn * THREE.MathUtils.degToRad(RIDE_SPREAD_DEG * this.rideW)));
        this.wrote(t.bone);
      }
    }
    for (const f of this.fingers) {
      const w = f.side === 'l' ? this.handW.l : this.handW.r;
      this.fromAnimated(f.bone);
      if (w > 0.001) f.bone.quaternion.slerp(f.relaxed, w);
      this.wrote(f.bone);
    }
  }

  /**
   * Two-handed weapons: the off hand onto the haft. The clips place the hands for the
   * library's mannequin; each body's own proportions (the male's longer clavicles and arms)
   * and its posture put them apart (2026-10-24: the male's spear, maul and staff all missed
   * his left hand). A two-bone IK moves the left wrist so the grip (weapon_l) lands on the
   * line of the main hand's weapon (weapon_r's +Y) where the clip itself had it along the haft
   * (readClipGrip, measured before the corrections; 2026-10-25), or at the weapon's HOLD.off
   * when the clip's left hand isn't on the haft, then turns the hand so the grip runs along
   * the haft. Blended in and out by `w`.
   */
  /**
   * The clip's own two-handed grip: how far along the haft (weapon_r's +Y, scene units) its
   * left grip sits from the right, and how far off the haft line. Read from the animated pose,
   * before the posture, shoulder and arm corrections move the arms apart (2026-10-25: the
   * male's clips hold every two-hander with the left grip within 1 mm of the haft; the
   * corrections then put it 10-20 cm off, and a fixed HOLD.off put it on the wrong side of
   * the right hand or out of reach).
   */
  /**
   * Puts a two-hander where `p` says (two-hand.ts) and both arms on it, blended in by `w`: the torso
   * turns and leans, the weapon's frame is built from its haft and edge directions, each hand is
   * turned so its weapon bone matches that frame (weapon_r at the grip, weapon_l `HOLD.off` up the
   * haft), and each arm reaches its wrist with solveArm (a true hinge at the elbow, the elbow
   * toward its pole).
   */
  private twoHandDrive(p: TwoHandPose, w: number) {
    const b = (n: string) => this.bones.get(n);
    const pelvis = b('pelvis'), neck = b('neck_01'), wr = b('weapon_r'), wl = b('weapon_l');
    const spine = ['spine_01', 'spine_02', 'spine_03'].map(b).filter(Boolean) as THREE.Object3D[];
    const R = { cl: b('clavicle_r'), ua: b('upperarm_r'), la: b('lowerarm_r'), hand: b('hand_r'), tw: b('lowerarm_twist_01_r'), utw: b('upperarm_twist_01_r') };
    const L = { cl: b('clavicle_l'), ua: b('upperarm_l'), la: b('lowerarm_l'), hand: b('hand_l'), tw: b('lowerarm_twist_01_l'), utw: b('upperarm_twist_01_l') };
    if (!pelvis || !neck || !wr || !wl || !R.ua || !R.la || !R.hand || !L.ua || !L.la || !L.hand) return;
    const extra = [R.cl, L.cl, R.tw, L.tw, R.utw, L.utw].filter(Boolean) as THREE.Object3D[];
    const all = [...spine, R.ua, R.la, R.hand, L.ua, L.la, L.hand, ...extra];
    for (const x of all) this.fromAnimated(x);
    const q0 = all.map((x) => x.quaternion.clone());
    this.root.updateWorldMatrix(true, true);
    const rootQ = this.root.getWorldQuaternion(new THREE.Quaternion());
    const P = pelvis.getWorldPosition(new THREE.Vector3());
    const S = neck.getWorldPosition(new THREE.Vector3()).distanceTo(P);
    const up = new THREE.Vector3(0, 1, 0).applyQuaternion(rootQ);
    const left = new THREE.Vector3(1, 0, 0).applyQuaternion(rootQ);
    // the torso: a third of the turn and the lean in each spine bone
    const twist = THREE.MathUtils.degToRad(p.twist ?? 0);
    const lean = THREE.MathUtils.degToRad(p.lean ?? 0);
    for (const sb of spine) {
      turnWorld(sb, up, twist / spine.length);
      turnWorld(sb, left, lean / spine.length);
    }
    // the body's frame, turned with the torso
    const frame = new THREE.Quaternion().setFromAxisAngle(up, twist).multiply(rootQ);
    const v = (a: [number, number, number]) => new THREE.Vector3(a[0], a[1], a[2]).applyQuaternion(frame);
    const grip = v(p.grip).multiplyScalar(S).add(P);
    const Y = v(p.dir).normalize();
    const Z = v(p.edge);
    Z.addScaledVector(Y, -Z.dot(Y));
    if (Z.lengthSq() < 1e-8) Z.copy(v([0, 0, 1])).addScaledVector(Y, -v([0, 0, 1]).dot(Y));
    Z.normalize();
    const X = new THREE.Vector3().crossVectors(Y, Z).normalize();
    const Wq = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(X, Y, Z));
    // the right hand: weapon_r on the grip
    const sR = new THREE.Vector3().setFromMatrixScale(R.hand.matrixWorld).x;
    const HqR = Wq.clone().multiply(wr.quaternion.clone().invert());
    const wristR = grip.clone().sub(wr.position.clone().multiplyScalar(sR).applyQuaternion(HqR));
    if (R.cl) shrug(R.cl, R.ua, wristR, up);
    solveArm(R.ua, R.la, R.hand, R.tw || null, wristR, v(p.poleR ?? [-0.55, -1, -0.3]), HqR, R.utw || null, this.restQuat.get('upperarm_r'));
    // the left hand: weapon_l up the haft (HOLD.off metres; the bone's scale turns them into units)
    const perMetre = new THREE.Vector3().setFromMatrixScale(wr.matrixWorld).y;
    const off = typeof wr.userData.b8OffGrip === 'number' ? wr.userData.b8OffGrip : 0.3;
    const gripL = grip.clone().addScaledVector(Y, off * perMetre);
    const sL = new THREE.Vector3().setFromMatrixScale(L.hand.matrixWorld).x;
    const HqL = Wq.clone().multiply(TWO_HAND_LEFT_TURN).multiply(wl.quaternion.clone().invert());
    const wristL = gripL.sub(wl.position.clone().multiplyScalar(sL).applyQuaternion(HqL));
    if (L.cl) shrug(L.cl, L.ua, wristL, up);
    solveArm(L.ua, L.la, L.hand, L.tw || null, wristL, v(p.poleL ?? [0.55, -1, -0.3]), HqL, L.utw || null, this.restQuat.get('upperarm_l'));
    if (w < 0.999) all.forEach((x, i) => x.quaternion.copy(q0[i].slerp(x.quaternion, w)));
    for (const x of all) this.wrote(x);
  }

  /** The guard for what the right hand holds: by its weapon model, else by stance set. */
  private guardFor(set?: string) {
    const wr = this.bones.get('weapon_r');
    const model = wr?.children.find((c) => c.userData.b8Weapon)?.userData.b8Weapon as string | undefined;
    return (model && TWO_HAND_GUARDS[model]) || (set && TWO_HAND_GUARDS[set]) || null;
  }

  /** A direction in the character's own frame (x its left, y up, z forward) as a world direction. */
  private bodyDir(x: number, y: number, z: number) {
    return new THREE.Vector3(x, y, z).normalize().applyQuaternion(this.root.getWorldQuaternion(new THREE.Quaternion()));
  }

  /**
   * Puts the right hand's grip where the guard says and the weapon along its direction (the
   * right arm by IK, the hand turned), blended in by `w`. The left hand follows (twoHandGrip).
   */
  private twoHandGuard(g: { at: [number, number, number]; dir: [number, number, number] }, w: number) {
    const ua = this.bones.get('upperarm_r'), la = this.bones.get('lowerarm_r'), hand = this.bones.get('hand_r');
    const wr = this.bones.get('weapon_r'), pelvis = this.bones.get('pelvis'), neck = this.bones.get('neck_01');
    if (!ua || !la || !hand || !wr || !pelvis || !neck) return;
    this.fromAnimated(ua);
    this.fromAnimated(la);
    this.fromAnimated(hand);
    const q0 = [ua.quaternion.clone(), la.quaternion.clone(), hand.quaternion.clone()];
    this.root.updateWorldMatrix(true, true);
    const P = pelvis.getWorldPosition(new THREE.Vector3());
    const S = neck.getWorldPosition(new THREE.Vector3()).distanceTo(P);
    const rootQ = this.root.getWorldQuaternion(new THREE.Quaternion());
    const at = new THREE.Vector3(...g.at).multiplyScalar(S).applyQuaternion(rootQ).add(P);
    const D = this.bodyDir(...g.dir);
    const pole = this.bodyDir(-0.55, -1, -0.3); // the right elbow: down, out, a little back
    const y = new THREE.Vector3();
    for (let pass = 0; pass < 3; pass++) {
      rotateWorld(hand, y.setFromMatrixColumn(wr.matrixWorld, 1).normalize(), D);
      const off = wr.getWorldPosition(new THREE.Vector3()).sub(hand.getWorldPosition(new THREE.Vector3()));
      ik2(ua, la, hand, at.clone().sub(off), pole);
    }
    rotateWorld(hand, y.setFromMatrixColumn(wr.matrixWorld, 1).normalize(), D);
    if (w < 0.999) {
      ua.quaternion.copy(q0[0].slerp(ua.quaternion, w));
      la.quaternion.copy(q0[1].slerp(la.quaternion, w));
      hand.quaternion.copy(q0[2].slerp(hand.quaternion, w));
    }
    this.wrote(ua);
    this.wrote(la);
    this.wrote(hand);
  }

  private readClipGrip(): { t: number; miss: number } | null {
    const wl = this.bones.get('weapon_l'), wr = this.bones.get('weapon_r');
    if (!wl || !wr) return null;
    // the arms and everything above them as the clip left them (fromAnimated also marks them,
    // so the corrections below start from the same values)
    for (const b of [wl, wr]) {
      for (let p: THREE.Object3D | null = b.parent; p && p !== this.root; p = p.parent) if ((p as any).isBone) this.fromAnimated(p);
    }
    wl.updateWorldMatrix(true, false);
    wr.updateWorldMatrix(true, false);
    const O = new THREE.Vector3().setFromMatrixPosition(wr.matrixWorld);
    const D = new THREE.Vector3().setFromMatrixColumn(wr.matrixWorld, 1).normalize();
    const rel = new THREE.Vector3().setFromMatrixPosition(wl.matrixWorld).sub(O);
    const t = rel.dot(D);
    return { t, miss: rel.addScaledVector(D, -t).length() };
  }

  private twoHandGrip(w: number) {
    const ua = this.bones.get('upperarm_l'), la = this.bones.get('lowerarm_l'), hand = this.bones.get('hand_l');
    const wl = this.bones.get('weapon_l'), wr = this.bones.get('weapon_r');
    if (!ua || !la || !hand || !wl || !wr) return;
    this.fromAnimated(ua);
    this.fromAnimated(la);
    this.fromAnimated(hand);
    const q0 = [ua.quaternion.clone(), la.quaternion.clone(), hand.quaternion.clone()];
    wr.updateWorldMatrix(true, false);
    ua.updateWorldMatrix(true, true);
    const O = wr.getWorldPosition(new THREE.Vector3());
    const D = new THREE.Vector3().setFromMatrixColumn(wr.matrixWorld, 1).normalize();
    const A = new THREE.Vector3(), B = new THREE.Vector3(), C = new THREE.Vector3(), G = new THREE.Vector3();
    const read = () => {
      ua.getWorldPosition(A); la.getWorldPosition(B); hand.getWorldPosition(C); wl.getWorldPosition(G);
    };
    read();
    const l1 = A.distanceTo(B), l2 = B.distanceTo(C);
    // where on the haft: the weapon's own grip (items.ts HOLD.off, metres along it; the
    // bone's scale turns metres into the scene's units), or, for a weapon without one, as
    // far from the main hand as the clip had the hands apart
    const perMetre = _w1.setFromMatrixColumn(wr.matrixWorld, 1).length();
    const off = wr.userData.b8OffGrip;
    const clip = this.clipGrip;
    let t: number;
    // the clip's spacing when its left hand is on the haft; the weapon's HOLD.off otherwise
    if (clip && clip.miss < 0.08 * perMetre) t = clip.t;
    else if (typeof off === 'number') t = off * perMetre;
    else {
      const rel = _w1.subVectors(G, O);
      t = (rel.dot(D) < 0 ? -1 : 1) * Math.min(Math.max(rel.length(), 0.42 * l2), 2.4 * l2);
    }
    for (let pass = 0; pass < 2; pass++) {
      // where the wrist goes: the grip on the haft, the hand's own offset kept
      const W = _w2.copy(O).addScaledVector(D, t).sub(G).add(C);
      // the elbow stays in its plane
      const to = _w3.subVectors(W, A);
      const d = THREE.MathUtils.clamp(to.length(), Math.abs(l1 - l2) + 1e-4, (l1 + l2) * 0.999);
      const u = to.normalize();
      // the elbow down, out and a little back (2026-10-26: keeping it in the clip's plane let it
      // swing up and fold the arm across the chest on the spear)
      const pole = _w4.copy(this.bodyDir(0.55, -1, -0.3));
      pole.addScaledVector(u, -pole.dot(u));
      if (pole.lengthSq() < 1e-10) pole.set(0, -1, 0).addScaledVector(u, -u.y);
      pole.normalize();
      const a = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
      const h = Math.sqrt(Math.max(0, l1 * l1 - a * a));
      const Bn = _w5.copy(A).addScaledVector(u, a).addScaledVector(pole, h);
      rotateWorld(ua, _w6.subVectors(B, A).normalize(), _w7.subVectors(Bn, A).normalize());
      read();
      rotateWorld(la, _w6.subVectors(C, B).normalize(), _w7.subVectors(W, B).normalize());
      read();
      // the grip along the haft, thumb toward the head (unless the clip has the fist
      // turned well the other way: then the other way, not a wrist wrung through 180)
      const gy = _w6.setFromMatrixColumn(wl.matrixWorld, 1).normalize();
      const want = _w7.copy(D).multiplyScalar(gy.dot(D) < -0.5 ? -1 : 1);
      rotateWorld(hand, gy.clone(), want);
      read();
    }
    if (w < 0.999) {
      ua.quaternion.copy(q0[0].slerp(ua.quaternion, w));
      la.quaternion.copy(q0[1].slerp(la.quaternion, w));
      hand.quaternion.copy(q0[2].slerp(hand.quaternion, w));
    }
    this.wrote(ua);
    this.wrote(la);
    this.wrote(hand);
  }

  // Puts back what the animation left in a bone if nothing has keyed it since our last write.
  private fromAnimated(bone: THREE.Object3D) {
    // a bone one correction already started from this frame keeps that correction
    if (this.touched.has(bone)) return;
    this.touched.add(bone);
    const a = this.applied.get(bone);
    if (a && bone.quaternion.equals(a.wrote)) bone.quaternion.copy(a.found);
    if (a) a.found.copy(bone.quaternion);
    else this.applied.set(bone, { found: bone.quaternion.clone(), wrote: new THREE.Quaternion() });
  }

  private wrote(bone: THREE.Object3D) {
    this.applied.get(bone)!.wrote.copy(bone.quaternion);
  }

  private tintPart(part: { obj: THREE.Object3D } | null, hex: string) {
    if (!part) return;
    part.obj.traverse((m: any) => {
      if (!m.isMesh) return;
      for (const mat of Array.isArray(m.material) ? m.material : [m.material]) {
        if (!mat.color) continue;
        mat.color.set(hex);
        // painted hair textures are grey around a set mean: the gain brings texture x colour to the colour
        const gain = Number(mat.userData?.tint_gain) || 1;
        if (gain !== 1) mat.color.multiplyScalar(gain);
      }
    });
  }

  private async swapPart(cur: { file: string; obj: THREE.Object3D } | null, entry: StyleEntry | null) {
    if (cur && entry && cur.file === entry.file) return cur;
    if (cur) {
      cur.obj.parent?.remove(cur.obj);
      cur.obj.traverse((m: any) => m.isMesh && (Array.isArray(m.material) ? m.material : [m.material]).forEach((x: any) => x.dispose()));
    }
    if (!entry) return null;
    const tpl = await this.factory.loadPart(entry.file);
    if (!tpl || this.disposed) return null;
    const group = new THREE.Group();
    group.name = `Part_${entry.id}`;
    tpl.traverse((src: any) => {
      if (!src.isSkinnedMesh) return;
      const bones = src.skeleton.bones.map((b: THREE.Bone) => this.bones.get(b.name));
      if (bones.some((b: any) => !b)) return;
      const mesh = new THREE.SkinnedMesh(src.geometry, (Array.isArray(src.material) ? src.material : [src.material]).map((m: any) => m.clone()));
      if (!Array.isArray(src.material)) mesh.material = (mesh.material as any)[0];
      mesh.name = src.name;
      if (src.morphTargetDictionary) {
        mesh.morphTargetDictionary = { ...src.morphTargetDictionary };
        mesh.morphTargetInfluences = new Array((src.morphTargetInfluences || []).length).fill(0);
      }
      const opacity = entry.opacity;
      for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
        // hair cards are alpha-tested: with MSAA, alpha to coverage softens their edges
        if ((m as any).alphaTest > 0) (m as any).alphaToCoverage = true;
        // the scalp decal under a style lies just off the skin: keep it in front of the skin
        if ((m as any).userData?.decal) {
          (m as any).polygonOffset = true;
          (m as any).polygonOffsetFactor = -1;
          (m as any).polygonOffsetUnits = -4;
        }
        if (opacity != null && opacity < 1) {
          (m as any).transparent = true;
          (m as any).opacity = opacity;
          (m as any).depthWrite = false;
        }
      }
      mesh.castShadow = true;
      mesh.frustumCulled = false;
      mesh.bind(new THREE.Skeleton(bones, src.skeleton.boneInverses), src.bindMatrix);
      group.add(mesh);
    });
    this.armature.add(group);
    return { file: entry.file, obj: group };
  }

  /** Bone by name (for attaching weapons to weapon_r / weapon_l). */
  bone(name: string): THREE.Bone | undefined {
    return this.bones.get(name);
  }

  /** On a mount: thighs apart, astride it (eased in and out). */
  setRiding(on: boolean) {
    this.riding = on;
  }

  /** Moves the body within its root: onto a mount's seat, or back on its feet (null). */
  setSeat(p: THREE.Vector3 | null) {
    if (p) this.model.position.copy(p);
    else this.model.position.set(0, 0, 0);
  }

  dispose() {
    this.disposed = true;
    this.root.parent?.remove(this.root);
    for (const list of this.materials.values()) list.forEach((m) => m.dispose());
    for (const part of [this.hair, this.facial]) {
      part?.obj.traverse((m: any) => m.isMesh && (Array.isArray(m.material) ? m.material : [m.material]).forEach((x: any) => x.dispose()));
    }
    this.materials.clear();
  }
}
