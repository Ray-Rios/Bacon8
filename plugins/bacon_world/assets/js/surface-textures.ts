// Surface textures for Bacon World's untextured models. The village props, the
// building kit, the weapons and the skeleton have no UVs: every material is a plain
// colour named for what it is (M_Stone, M_RoofTile, W_Leather...). This adds detail
// to those materials by name, with real CC0 texture sets from ambientCG and Poly Haven
// (credits: /models/World/Textures/CREDITS.md), projected triplanar in the mesh's own
// space (metres), so no model needs UVs and nothing has to be re-exported.
//
// Two ways to use a set:
//   detail (the default) - the material keeps its colour; the texture adds its pattern,
//     variation, roughness and ambient occlusion around that colour (colour * tex / mean),
//     so the palette stays the art direction's.
//   own - the texture's own colours, times `tint` (the building kit's brick).
// Normal maps are blended in too (whiteout triplanar), except on skinned meshes, whose
// bind-pose normals don't follow the bones.
//
// Files: /models/World/Textures/<set>_c.webp (colour, sRGB), <set>_n.webp (normal,
// OpenGL), <set>_r.webp (R ambient occlusion, G roughness). Packed by the game
// repository's pipeline from library/textures; `SETS` holds each set's mean values.
//
// Players can turn it off (Esc menu, "Textures"): the setting is read once at start.
import * as THREE from '../../../../assets/js/vendor/three';
import { modelUrl } from './asset-url';

export const TEXTURE_BASE = '/models/World/Textures';
export const SURFACES_KEY = 'bacon_world:surfaces'; // on | off

type SetInfo = { mean: [number, number, number]; rough: number; ao: number };

/** Linear mean colour, mean roughness and mean AO of each packed set (from the packer). */
export const SETS: Record<string, SetInfo> = {
  stone_blocks: { mean: [0.1852, 0.1457, 0.0981], rough: 0.938, ao: 0.981 },
  stone_slates: { mean: [0.2654, 0.2182, 0.1411], rough: 0.522, ao: 0.446 },
  brick: { mean: [0.1485, 0.0922, 0.0755], rough: 0.532, ao: 0.781 },
  planks: { mean: [0.1349, 0.0627, 0.0189], rough: 0.284, ao: 0.988 },
  wood: { mean: [0.0536, 0.0348, 0.0277], rough: 0.544, ao: 1.0 },
  roof_slate: { mean: [0.1666, 0.1599, 0.1404], rough: 0.504, ao: 0.823 },
  roof_tile: { mean: [0.249, 0.1822, 0.1263], rough: 0.753, ao: 0.504 },
  thatch: { mean: [0.0902, 0.0806, 0.0676], rough: 0.894, ao: 0.703 },
  straw: { mean: [0.1566, 0.1231, 0.0888], rough: 0.697, ao: 0.608 },
  metal: { mean: [0.05, 0.05, 0.0503], rough: 0.355, ao: 1.0 },
  metal_worn: { mean: [0.5149, 0.5174, 0.5158], rough: 0.275, ao: 1.0 },
  rock: { mean: [0.1019, 0.0761, 0.0379], rough: 0.813, ao: 0.879 },
  grass: { mean: [0.1188, 0.1527, 0.0304], rough: 0.264, ao: 0.808 },
  forest_ground: { mean: [0.1455, 0.1024, 0.058], rough: 0.901, ao: 0.863 },
  plaza: { mean: [0.2045, 0.168, 0.112], rough: 0.619, ao: 0.912 },
  earth: { mean: [0.2099, 0.1592, 0.0912], rough: 0.676, ao: 0.843 },
  cloth: { mean: [0.1057, 0.1044, 0.1061], rough: 0.729, ao: 0.924 },
  canvas: { mean: [0.2303, 0.2235, 0.1743], rough: 0.819, ao: 0.744 },
  leather: { mean: [0.0101, 0.0096, 0.0094], rough: 0.371, ao: 1.0 },
  rope: { mean: [0.2003, 0.1494, 0.0787], rough: 0.651, ao: 1.0 },
  bark: { mean: [0.1792, 0.1181, 0.0419], rough: 0.905, ao: 0.559 },
  plaster: { mean: [0.5153, 0.5199, 0.4963], rough: 0.516, ao: 1.0 },
  dark_rock: { mean: [0.0788, 0.0913, 0.1052], rough: 0.651, ao: 0.928 },
  worn: { mean: [0.0931, 0.0949, 0.089], rough: 0.542, ao: 0.958 },
};

export type Surface = {
  set: string;
  /** Metres per texture tile, in the mesh's own space. */
  scale: number;
  /** Use the texture's own colours (times `tint`) instead of the material's. */
  own?: boolean;
  tint?: string;
  /** How much of the texture shows, 0..1 (default 1). */
  strength?: number;
  /** Normal map strength, 0..1 (default 1; 0 for none). */
  normal?: number;
  /** Large-scale variation that hides tiling on big flat ground. */
  antiTile?: boolean;
};

export type Family = 'kit' | 'props' | 'weapons' | 'mobs';

const wood = (scale: number, strength = 1): Surface => ({ set: 'wood', scale, strength });

/** Building kit pieces (B8_BuildKit.glb). */
export const KIT: Record<string, Surface> = {
  M_Stone: { set: 'stone_blocks', scale: 2.4 },
  M_DarkStone: { set: 'stone_slates', scale: 2.0 },
  M_Brick: { set: 'brick', scale: 2.0, own: true },
  M_Plank: { set: 'planks', scale: 2.0 },
  M_Wood: wood(1.2),
  M_DarkWood: wood(1.2),
  M_LightWood: wood(1.2),
  M_Slate: { set: 'roof_slate', scale: 2.0 },
  M_RoofTile: { set: 'roof_tile', scale: 2.0 },
  M_Thatch: { set: 'thatch', scale: 2.0 },
  M_Hay: { set: 'straw', scale: 1.0 },
  M_Iron: { set: 'metal', scale: 0.8, strength: 0.8 },
};

/** Village props (B8_Props.glb). */
export const PROPS: Record<string, Surface> = {
  M_Stone: { set: 'rock', scale: 1.6 },
  M_DarkStone: { set: 'dark_rock', scale: 1.2 },
  M_Coal: { set: 'dark_rock', scale: 0.5 },
  M_Wood: wood(1.0),
  M_DarkWood: wood(1.0),
  M_LightWood: wood(1.0),
  M_Plank: { set: 'planks', scale: 1.5 },
  M_Bark: { set: 'bark', scale: 1.5 },
  M_Hay: { set: 'straw', scale: 1.0 },
  M_RoofTile: { set: 'roof_tile', scale: 2.0 },
  M_Slate: { set: 'roof_slate', scale: 1.5 },
  M_Iron: { set: 'metal', scale: 0.6, strength: 0.8 },
  M_DarkSteel: { set: 'metal', scale: 0.6, strength: 0.8 },
  M_Steel: { set: 'metal_worn', scale: 0.6, strength: 0.7 },
  M_Gold: { set: 'metal_worn', scale: 0.5, strength: 0.6 },
  M_Brass: { set: 'metal_worn', scale: 0.5, strength: 0.6 },
  M_Canvas: { set: 'canvas', scale: 0.8 },
  M_Cloth: { set: 'cloth', scale: 0.5, strength: 0.8 },
  M_BlueCloth: { set: 'cloth', scale: 0.5, strength: 0.8 },
  M_GreenCloth: { set: 'cloth', scale: 0.5, strength: 0.8 },
  M_Leather: { set: 'leather', scale: 0.4, strength: 0.7 },
  M_RedLeather: { set: 'leather', scale: 0.4, strength: 0.7 },
  M_Rope: { set: 'rope', scale: 0.4 },
  M_Clay: { set: 'plaster', scale: 0.8, strength: 0.6 },
  M_Ceramic: { set: 'plaster', scale: 0.8, strength: 0.5 },
  M_Grass: { set: 'grass', scale: 1.0 },
  M_Dirt: { set: 'forest_ground', scale: 1.5 },
  M_Bone: { set: 'worn', scale: 0.5, strength: 0.5 },
};

/** Weapons (B8_Weapons.glb): small, so the tiles are small. */
export const WEAPONS: Record<string, Surface> = {
  W_Iron: { set: 'metal', scale: 0.35, strength: 0.8 },
  W_DarkSteel: { set: 'metal', scale: 0.35, strength: 0.8 },
  W_Steel: { set: 'metal_worn', scale: 0.35, strength: 0.7 },
  W_Gold: { set: 'metal_worn', scale: 0.3, strength: 0.6 },
  W_Brass: { set: 'metal_worn', scale: 0.3, strength: 0.6 },
  W_Bronze: { set: 'metal_worn', scale: 0.3, strength: 0.6 },
  W_Wood: wood(0.5),
  W_DarkWood: wood(0.5),
  W_LightWood: wood(0.5),
  W_Plank: { set: 'planks', scale: 0.6 },
  W_Bark: { set: 'bark', scale: 0.5 },
  W_Leather: { set: 'leather', scale: 0.25, strength: 0.7 },
  W_RedLeather: { set: 'leather', scale: 0.25, strength: 0.7 },
  W_Cloth: { set: 'cloth', scale: 0.2, strength: 0.8 },
  W_BlueCloth: { set: 'cloth', scale: 0.2, strength: 0.8 },
  W_Rope: { set: 'rope', scale: 0.2 },
  W_String: { set: 'rope', scale: 0.15, strength: 0.6 },
  W_Bone: { set: 'worn', scale: 0.3, strength: 0.5 },
};

/** Mobs (B8_Skeleton.glb). */
export const MOBS: Record<string, Surface> = {
  Skel_Bone: { set: 'worn', scale: 0.25 },
  // the goblins' and orcs' (2026-10-28, build_greenskins.py): what they wear
  Mob_Cloth: { set: 'cloth', scale: 0.3, strength: 0.9 },
  Mob_Leather: { set: 'leather', scale: 0.3, strength: 0.8 },
  Mob_Iron: { set: 'metal', scale: 0.3, strength: 0.8 },
  Mob_Bone: { set: 'worn', scale: 0.2, strength: 0.5 },
  Mob_Rope: { set: 'rope', scale: 0.2 },
};

const TABLES: Record<Family, Record<string, Surface>> = { kit: KIT, props: PROPS, weapons: WEAPONS, mobs: MOBS };

/** The surface for material `name` in `family`, or null to leave it plain. Glass,
 *  gems, potions, fire and paint stay plain. A ".001"-style suffix is ignored. */
export function surfaceFor(family: Family, name: string): Surface | null {
  const base = name.replace(/\.\d+$/, '');
  const s = TABLES[family]?.[base];
  return s && SETS[s.set] ? s : null;
}

// ---------------------------------------------------------------- runtime

let enabledCache: boolean | null = null;

/** Whether surface textures are on (Esc menu setting; read once). */
export function surfacesEnabled(): boolean {
  if (enabledCache === null) {
    let v: string | null = null;
    try {
      v = window.localStorage.getItem(SURFACES_KEY);
    } catch {
      v = null;
    }
    enabledCache = v !== 'off';
  }
  return enabledCache;
}

type Maps = { c: THREE.Texture; n: THREE.Texture; r: THREE.Texture };
const loads = new Map<string, Promise<Maps | null>>();
let loader: THREE.TextureLoader | null = null;

function loadTex(url: string, srgb: boolean): Promise<THREE.Texture> {
  loader = loader || new THREE.TextureLoader();
  return new Promise((resolve, reject) =>
    loader!.load(
      modelUrl(url),
      (t) => {
        t.wrapS = t.wrapT = THREE.RepeatWrapping;
        t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
        t.anisotropy = 4;
        resolve(t);
      },
      undefined,
      reject
    )
  );
}

function loadSet(set: string): Promise<Maps | null> {
  let p = loads.get(set);
  if (!p) {
    const base = `${TEXTURE_BASE}/${set}`;
    p = Promise.all([loadTex(`${base}_c.webp`, true), loadTex(`${base}_n.webp`, false), loadTex(`${base}_r.webp`, false)])
      .then(([c, n, r]) => ({ c, n, r }))
      .catch((err) => {
        console.warn('[surfaces] could not load', set, err);
        return null;
      });
    loads.set(set, p);
  }
  return p;
}

/** A texture set's three maps (colour, normal, roughness/AO), loaded once (terrain.ts paints with them). */
export function loadSurfaceSet(set: string): Promise<Maps | null> {
  return loadSet(set);
}

const VERT_HEAD = 'varying vec3 vB8Pos;\nvarying vec3 vB8Nrm;\n';
const FRAG_HEAD = `varying vec3 vB8Pos;
varying vec3 vB8Nrm;
uniform sampler2D b8C;
uniform sampler2D b8N;
uniform sampler2D b8R;
uniform float b8Scale;
uniform float b8Str;
uniform float b8NStr;
uniform float b8Own;
uniform vec3 b8Tint;
uniform vec3 b8Mean;
uniform vec2 b8Avg;
#ifdef B8_NORMALS
uniform mat3 normalMatrix;
#endif
vec3 b8Weights(vec3 n) {
  vec3 w = pow(abs(n), vec3(4.0));
  return w / max(w.x + w.y + w.z, 1e-4);
}
vec4 b8Tri(sampler2D t, vec3 p, vec3 w) {
  return texture2D(t, p.zy) * w.x + texture2D(t, p.xz) * w.y + texture2D(t, p.xy) * w.z;
}
`;

const MAP_CODE = `#include <map_fragment>
vec3 b8n0 = normalize(vB8Nrm);
vec3 b8w = b8Weights(b8n0);
vec3 b8p = vB8Pos / b8Scale;
vec3 b8c = b8Tri(b8C, b8p, b8w).rgb;
#ifdef B8_ANTITILE
  // a second, much larger and turned copy, as brightness only: breaks up the repeat
  vec3 b8q = vec3(b8p.x * 0.8 - b8p.z * 0.6, b8p.y, b8p.x * 0.6 + b8p.z * 0.8) * 0.137;
  vec3 b8m = b8Tri(b8C, b8q, b8w).rgb;
  b8c *= clamp(dot(b8m, vec3(0.333)) / max(dot(b8Mean, vec3(0.333)), 1e-3), 0.7, 1.3);
#endif
vec3 b8orm = b8Tri(b8R, b8p, b8w).rgb;
vec3 b8mul = mix(diffuseColor.rgb / max(b8Mean, vec3(1e-3)), b8Tint, b8Own);
diffuseColor.rgb = mix(diffuseColor.rgb, b8mul * b8c, b8Str);
diffuseColor.rgb *= mix(1.0, clamp(b8orm.r / max(b8Avg.y, 0.05), 0.35, 1.2), b8Str);
`;

const ROUGH_CODE = `#include <roughnessmap_fragment>
roughnessFactor = clamp(roughnessFactor * mix(1.0, clamp(b8orm.g / max(b8Avg.x, 0.05), 0.5, 1.5), b8Str), 0.04, 1.0);
`;

const NORMAL_CODE = `#include <normal_fragment_maps>
#ifdef B8_NORMALS
{
  vec3 tx = texture2D(b8N, b8p.zy).xyz * 2.0 - 1.0;
  vec3 ty = texture2D(b8N, b8p.xz).xyz * 2.0 - 1.0;
  vec3 tz = texture2D(b8N, b8p.xy).xyz * 2.0 - 1.0;
  tx = vec3(tx.xy + b8n0.zy, abs(tx.z) * b8n0.x);
  ty = vec3(ty.xy + b8n0.xz, abs(ty.z) * b8n0.y);
  tz = vec3(tz.xy + b8n0.xy, abs(tz.z) * b8n0.z);
  vec3 b8np = normalize(tx.zyx * b8w.x + ty.xzy * b8w.y + tz.xyz * b8w.z);
  b8np = normalize(mix(b8n0, b8np, b8NStr));
  normal = normalize(normalMatrix * b8np) * faceDirection;
}
#endif
`;

/** Patches `mat` (a MeshStandardMaterial) to show surface `s`, once its textures are in.
 *  Resolves true when applied. `skinned` turns the normal map off. */
export async function applySurface(mat: THREE.Material, s: Surface, skinned = false): Promise<boolean> {
  const m = mat as THREE.MeshStandardMaterial;
  if (!m || !(m as any).isMeshStandardMaterial || !surfacesEnabled() || m.userData.b8surface) return false;
  m.userData.b8surface = s;
  const maps = await loadSet(s.set);
  if (!maps) return false;
  const info = SETS[s.set];
  const tint = new THREE.Color(s.tint || '#FFFFFF');
  const normals = !skinned && (s.normal ?? 1) > 0;
  const uniforms = {
    b8C: { value: maps.c },
    b8N: { value: maps.n },
    b8R: { value: maps.r },
    b8Scale: { value: s.scale },
    b8Str: { value: s.strength ?? 1 },
    b8NStr: { value: s.normal ?? 1 },
    b8Own: { value: s.own ? 1 : 0 },
    b8Tint: { value: new THREE.Vector3(tint.r, tint.g, tint.b) },
    b8Mean: { value: new THREE.Vector3(...info.mean) },
    b8Avg: { value: new THREE.Vector2(info.rough, info.ao) },
  };
  const key = `b8surf:${normals ? 'n' : ''}${s.antiTile ? 'a' : ''}`;
  m.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    if (normals) shader.defines = { ...(shader.defines || {}), B8_NORMALS: '' };
    if (s.antiTile) shader.defines = { ...(shader.defines || {}), B8_ANTITILE: '' };
    shader.vertexShader = VERT_HEAD + shader.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\nvB8Pos = position;\nvB8Nrm = normal;');
    shader.fragmentShader = FRAG_HEAD + shader.fragmentShader
      .replace('#include <map_fragment>', MAP_CODE)
      .replace('#include <roughnessmap_fragment>', ROUGH_CODE)
      .replace('#include <normal_fragment_maps>', NORMAL_CODE);
  };
  m.customProgramCacheKey = () => key;
  m.needsUpdate = true;
  return true;
}

/** Applies the family's surfaces to every mesh material under `root` it knows. */
export function applySurfaces(root: THREE.Object3D, family: Family): void {
  if (!surfacesEnabled()) return;
  root.traverse((o: any) => {
    if (!o.isMesh) return;
    for (const mat of Array.isArray(o.material) ? o.material : [o.material]) {
      const s = mat && surfaceFor(family, mat.name || '');
      if (s) void applySurface(mat, s, !!o.isSkinnedMesh);
    }
  });
}
