// Builds Bacon8 humans from an Appearance: the body GLB (skeleton, body, garments, eyes,
// brows, lashes, 20 clips), hair and facial hair GLBs bound to the same bones, morph
// targets for the shape sliders, tinted materials, and body regions hidden under clothes.
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

export const HUMANS_BASE = '/models/Humans';

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
          clips: gltf.animations || [],
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
          .then((g: any) => (g.animations || []) as THREE.AnimationClip[])
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

  hiddenRegions(asset: BodyAsset, a: Appearance): number[] {
    const hides: Record<string, number[]> = asset.manifest?.hides || DEFAULT_HIDES;
    const o = a.outfit;
    return [...(hides[o.top.id] || []), ...(hides[o.bottom.id] || []), ...(hides[o.shoes.id] || [])];
  }

  async create(appearance: Appearance | unknown, fallbackBody: Body = 'male'): Promise<HumanInstance> {
    const a = normalizeAppearance(appearance, fallbackBody);
    const asset = await this.loadBody(a.body);
    const inst = new HumanInstance(this, asset, a);
    await inst.apply(a, true);
    return inst;
  }
}

const GARMENTS = ['Top_Tee', 'Top_Tank', 'Top_LongSleeve', 'Bottom_Shorts', 'Bottom_Pants', 'Shoes_Sneakers', 'Shoes_Boots'];

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
    for (const g of GARMENTS) {
      const n = this.model.getObjectByName(`${tag}_${g}`);
      if (n) this.garments.set(g, n);
    }
    // tops are drawn over the trousers' waistband where the two touch
    for (const [name, mats] of this.materials) {
      if (!name.startsWith('Top_')) continue;
      for (const m of mats) {
        m.polygonOffset = true;
        m.polygonOffsetFactor = -1.5;
        m.polygonOffsetUnits = -3;
      }
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

    // garments and the body regions under them
    const o = a.outfit;
    for (const [id, node] of this.garments) node.visible = id === o.top.id || id === o.bottom.id || id === o.shoes.id;
    const hidden = this.factory.hiddenRegions(this.asset, a);
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

    // colours
    this.tint('Skin', a.skin);
    this.tint('Iris', a.eyes);
    this.tint('Brows', browColor(a));
    this.tint(`${o.top.id}_Main`, o.top.main);
    this.tint(`${o.top.id}_Trim`, o.top.trim);
    this.tint(`${o.bottom.id}_Main`, o.bottom.main);
    this.tint(`${o.bottom.id}_Trim`, o.bottom.trim);
    this.tint(`${o.shoes.id}_Upper`, o.shoes.upper);
    this.tint(`${o.shoes.id}_Sole`, o.shoes.sole);
    this.tint(`${o.shoes.id}_Laces`, o.shoes.laces);

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
