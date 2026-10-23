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
import {
  Gear, KEEP_TRANSLATION, WornGarment, approach, boneOffsets, designFiles, gearKey, hiddenFor, relaxedCurl, wornGarments,
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
   */
  loadAnimPacks(body: Body | 'Male' | 'Female'): Promise<THREE.AnimationClip[]> {
    const tag = body === 'male' || body === 'Male' ? 'Male' : 'Female';
    let p = this.packs.get(tag);
    if (!p) {
      const one = (pack: string) =>
        this.load(`${HUMANS_BASE}/Anims/B8_${tag}_Anims_${pack}.glb`)
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
  private posture: { q: THREE.Quaternion; qi: THREE.Quaternion; children: THREE.Bone[] } | null = null;
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
    // relaxed fingers: rest x a curl about each joint's own X
    const X = new THREE.Vector3(1, 0, 0);
    for (const [name, b] of this.bones) {
      const deg = relaxedCurl(name);
      if (deg == null) continue;
      const q = this.restQuat.get(name)!.clone().multiply(new THREE.Quaternion().setFromAxisAngle(X, THREE.MathUtils.degToRad(deg)));
      this.fingers.push({ bone: b, side: name.endsWith('_l') ? 'l' : 'r', relaxed: q });
    }
    // posture: the pelvis turned back about her side-to-side axis; its spine and legs kept where they were
    const tilt = Number(this.asset.manifest?.posture?.pelvis_tilt_deg) || 0;
    const pelvis = this.bones.get('pelvis');
    if (tilt && pelvis) {
      m.multiplyMatrices(inv, pelvis.matrixWorld);
      const wq = new THREE.Quaternion().setFromRotationMatrix(m);
      const axis = new THREE.Vector3(1, 0, 0).applyQuaternion(wq.clone().invert()).normalize();
      const q = new THREE.Quaternion().setFromAxisAngle(axis, -THREE.MathUtils.degToRad(tilt));
      const children = ['spine_01', 'thigh_l', 'thigh_r'].map((n) => this.bones.get(n)).filter((b): b is THREE.Bone => !!b && b.parent === pelvis);
      this.posture = { q, qi: q.clone().invert(), children };
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
  postAnimate(dt: number, free: { l: boolean; r: boolean } = { l: true, r: true }) {
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
    }
    this.handW.l = approach(this.handW.l, free.l ? 1 : 0, 6, dt);
    this.handW.r = approach(this.handW.r, free.r ? 1 : 0, 6, dt);
    for (const f of this.fingers) {
      const w = f.side === 'l' ? this.handW.l : this.handW.r;
      this.fromAnimated(f.bone);
      if (w > 0.001) f.bone.quaternion.slerp(f.relaxed, w);
      this.wrote(f.bone);
    }
  }

  // Puts back what the animation left in a bone if nothing has keyed it since our last write.
  private fromAnimated(bone: THREE.Object3D) {
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
