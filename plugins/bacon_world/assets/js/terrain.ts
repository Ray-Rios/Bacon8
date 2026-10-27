// The zone's ground (2026-10-26): a World Creator heightfield, turned into game files by
// library/pipeline/scripts/terrain_build.py and described by the server (BaconWorld.Terrain,
// sent with fetch_mobs as `terrain`, in scene units). The server reads the same heights, so both
// agree on where the ground and the water are.
//
// Heightfield: the heights (2 m apart) and the water bodies (4 m apart), with the questions the
// game asks: how high is the ground here, is this water, which, may someone walk here.
// TerrainView: the ground drawn as 32 x 32 chunks of 128 m, each in a level of detail that
// follows the camera (2 m between vertices close by, up to 32 m far off), with skirts hiding the
// seams between levels, and a shader that paints it by slope and height: grass, dirt on the
// steeper bits, rock on cliffs, sand at the waterline, snow on the peaks.
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { modelUrl } from './asset-url';
import { loadSurfaceSet, surfacesEnabled } from './surface-textures';

const U = UNITS_PER_METRE;

/** What the server says about the terrain (BaconWorld.Terrain.payload/1): scene units. */
export interface TerrainInfo {
  zone: string;
  name: string;
  heights: string; // /models URL of the packed heights
  water: string; // /models URL of the water bodies
  samples: number;
  water_samples: number;
  size: number;
  x0: number;
  z0: number;
  lo: number;
  step: number;
  sea: number;
  margin: number;
  wade: number;
  lakes: Array<{ label: number; id: string; name: string }>;
}

export type TerrainWater = { kind: 'ocean' | 'lake'; id: string; name: string };

/**
 * Unpacks terrain_build.py's `_hd.bin`: int16 2-D differences, high bytes then low bytes.
 * d[i][j] = k[i][j] - k[i][j-1] (d[i][0] = k[i][0]); stored e = d[i][j] - d[i-1][j] for i, j >= 1.
 */
export function decodeHeights(enc: Uint8Array, n: number): Uint16Array {
  const count = n * n;
  if (enc.length !== count * 2) throw new Error(`terrain: ${enc.length} bytes, expected ${count * 2}`);
  const k = new Uint16Array(count);
  const prev = new Int32Array(n); // d of the row above
  for (let i = 0; i < n; i++) {
    let acc = 0;
    for (let j = 0; j < n; j++) {
      const at = i * n + j;
      let e = (enc[at] << 8) | enc[count + at];
      if (e & 0x8000) e -= 0x10000;
      const d = i > 0 && j > 0 ? e + prev[j] : e;
      prev[j] = d;
      acc = j === 0 ? d : acc + d;
      k[at] = acc;
    }
  }
  return k;
}

export class Heightfield {
  readonly cell: number; // scene units between height samples
  private readonly wcell: number;

  constructor(readonly info: TerrainInfo, readonly k: Uint16Array, readonly labels: Uint8Array | null) {
    this.cell = info.size / (info.samples - 1);
    this.wcell = info.size / (info.water_samples - 1);
  }

  /** The height of sample (i, j) (column i from the west, row j from the north), scene units. */
  sample(i: number, j: number): number {
    const n = this.info.samples;
    i = i < 0 ? 0 : i >= n ? n - 1 : i;
    j = j < 0 ? 0 : j >= n ? n - 1 : j;
    return this.info.lo + this.k[j * n + i] * this.info.step;
  }

  /**
   * The ground's height at (x, z), scene units: on the same two triangles per cell the mesh draws
   * (split from its north-west to its south-east corner), so feet sit on what is drawn.
   */
  height(x: number, z: number): number {
    const n = this.info.samples;
    let gx = (x - this.info.x0) / this.cell;
    let gz = (z - this.info.z0) / this.cell;
    gx = gx < 0 ? 0 : gx > n - 1 ? n - 1 : gx;
    gz = gz < 0 ? 0 : gz > n - 1 ? n - 1 : gz;
    const i = Math.min(Math.floor(gx), n - 2);
    const j = Math.min(Math.floor(gz), n - 2);
    const fx = gx - i, fz = gz - j;
    const a = this.sample(i, j), b = this.sample(i + 1, j), c = this.sample(i, j + 1), d = this.sample(i + 1, j + 1);
    return fx >= fz ? a + (b - a) * fx + (d - b) * fz : a + (d - c) * fx + (c - a) * fz;
  }

  /** The ground's normal at (x, z) from the heights round it (world space). */
  normal(x: number, z: number, out = new THREE.Vector3()): THREE.Vector3 {
    const c = this.cell;
    return out.set(this.height(x - c, z) - this.height(x + c, z), 2 * c, this.height(x, z - c) - this.height(x, z + c)).normalize();
  }

  /** The ground, or the water's surface over water: what someone stands or floats on. */
  surface(x: number, z: number): number {
    return Math.max(this.height(x, z), this.info.sea);
  }

  /** Water at (x, z): the sea, a named lake, or null on land (BaconWorld.Terrain.water/3). */
  water(x: number, z: number): TerrainWater | null {
    if (this.height(x, z) >= this.info.sea) return null;
    let label = 1;
    if (this.labels) {
      const n = this.info.water_samples;
      const i = Math.round((x - this.info.x0) / this.wcell);
      const j = Math.round((z - this.info.z0) / this.wcell);
      for (const [di, dj] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]) {
        const ii = i + di, jj = j + dj;
        if (ii < 0 || jj < 0 || ii >= n || jj >= n) continue;
        const l = this.labels[jj * n + ii];
        if (l) {
          label = l;
          break;
        }
      }
    }
    const lake = this.info.lakes.find((l) => l.label === label);
    return lake ? { kind: 'lake', id: lake.id, name: lake.name } : { kind: 'ocean', id: 'sea', name: 'the sea' };
  }

  /** Deeper than wading: someone here swims (BaconWorld.Terrain.deep?/3). */
  deep(x: number, z: number): boolean {
    return this.height(x, z) < this.info.sea - this.info.wade;
  }

  /** Where feet go: the ground, or the water's surface where it's too deep to stand (swimming). */
  feet(x: number, z: number): number {
    return this.deep(x, z) ? this.info.sea : this.height(x, z);
  }

  /** Inside the map, `margin` from its edges. */
  inside(x: number, z: number): boolean {
    const { x0, z0, size, margin } = this.info;
    return x >= x0 + margin && z >= z0 + margin && x <= x0 + size - margin && z <= z0 + size - margin;
  }

  /** Where someone on foot may be: inside, and no deeper in water than wading. */
  walkable(x: number, z: number): boolean {
    return this.inside(x, z) && this.height(x, z) >= this.info.sea - this.info.wade;
  }
}

/** Fetches and unpacks the terrain the server described. */
export async function loadHeightfield(info: TerrainInfo): Promise<Heightfield> {
  const get = async (url: string) => {
    const res = await fetch(modelUrl(url));
    if (!res.ok) throw new Error(`terrain: ${url} answered ${res.status}`);
    return new Uint8Array(await res.arrayBuffer());
  };
  const [enc, labels] = await Promise.all([get(info.heights), get(info.water).catch(() => null)]);
  const k = decodeHeights(enc, info.samples);
  const w = labels && labels.length === info.water_samples * info.water_samples ? labels : null;
  return new Heightfield(info, k, w);
}

// ------------------------------------------------------------------------------- drawing

const CHUNK = 64; // cells per chunk side (128 m)
const STEPS = [1, 2, 4, 8, 16, 32];
/** Distance (m) from the camera within which each step is used. */
const LOD_M = [180, 360, 720, 1400, 2600];

type Chunk = { ci: number; cj: number; mesh: THREE.Mesh; step: number; geos: Map<number, THREE.BufferGeometry>; minX: number; maxX: number; minZ: number; maxZ: number };

const indexCache = new Map<number, THREE.BufferAttribute>();

/** The index buffer for a chunk `m` quads across: the grid, then a skirt round its four edges. */
function chunkIndex(m: number): THREE.BufferAttribute {
  let attr = indexCache.get(m);
  if (attr) return attr;
  const v = m + 1;
  const idx: number[] = [];
  for (let j = 0; j < m; j++) {
    for (let i = 0; i < m; i++) {
      const a = j * v + i, b = a + 1, c = a + v, d = c + 1;
      // split north-west to south-east (Heightfield.height/2 follows the same split)
      idx.push(a, c, d, a, d, b);
    }
  }
  // skirts: each edge's vertices again, lower (edge e's copy starts at v*v + e*v)
  const top = (e: number, t: number) => (e === 0 ? t : e === 1 ? t * v + m : e === 2 ? m * v + (m - t) : (m - t) * v);
  for (let e = 0; e < 4; e++) {
    const base = v * v + e * v;
    for (let t = 0; t < m; t++) {
      const a = top(e, t), b = top(e, t + 1), c = base + t, d = base + t + 1;
      idx.push(a, b, c, b, d, c); // facing out of the chunk, towards the neighbour that may show the gap
    }
  }
  attr = new THREE.BufferAttribute(new Uint32Array(idx), 1);
  indexCache.set(m, attr);
  return attr;
}

const VERT = `varying vec3 vTPos;
varying vec3 vTNrm;
`;
const FRAG = `varying vec3 vTPos;
varying vec3 vTNrm;
uniform sampler2D tGrass;
uniform sampler2D tDirt;
uniform sampler2D tRock;
uniform sampler2D tSand;
uniform vec4 tMeans; // mean brightness of grass, dirt, rock, sand
uniform float tSea;
uniform float tU;
float tLum(vec3 c) { return dot(c, vec3(0.333)); }
// a texture at two scales: the close one, its brightness varied by a large turned copy
vec3 tPlanar(sampler2D t, vec2 p, float s, float mean) {
  vec3 a = texture2D(t, p / s).rgb;
  vec3 b = texture2D(t, mat2(0.8, -0.6, 0.6, 0.8) * p / (s * 7.3)).rgb;
  return a * clamp(tLum(b) / max(mean, 1e-3), 0.65, 1.35);
}
vec3 tTri(sampler2D t, vec3 p, vec3 n, float s) {
  vec3 w = pow(abs(n), vec3(4.0));
  w /= max(w.x + w.y + w.z, 1e-4);
  return texture2D(t, p.zy / s).rgb * w.x + texture2D(t, p.xz / s).rgb * w.y + texture2D(t, p.xy / s).rgb * w.z;
}
`;
const PAINT = `#include <map_fragment>
{
  vec3 n = normalize(vTNrm);
  float up = n.y;
  float hm = (vTPos.y - tSea) / tU; // metres above the sea
  vec2 p = vTPos.xz;
  // a slow wobble so the bands between grounds aren't contour lines
  float wob = texture2D(tGrass, p / (190.0 * tU)).g - 0.5;
  float rock = smoothstep(0.80 + wob * 0.06, 0.66, up);
  float dirt = (1.0 - rock) * smoothstep(0.95, 0.85 + wob * 0.1, up);
  // sand only on the strip the waves reach, and on the shallows' floor
  float sand = (1.0 - rock) * (1.0 - smoothstep(0.4, 1.6 + wob * 1.2, hm));
  float snow = smoothstep(440.0, 540.0, hm + wob * 90.0) * (1.0 - 0.55 * rock);
  float grass = max(0.0, 1.0 - rock - dirt - sand);
  vec3 cg = tPlanar(tGrass, p, 3.0 * tU, tMeans.x) * vec3(0.92, 1.0, 0.82);
  vec3 cd = tPlanar(tDirt, p, 2.6 * tU, tMeans.y);
  vec3 cs = tPlanar(tSand, p, 2.2 * tU, tMeans.w) * vec3(1.55, 1.38, 1.05);
  vec3 cr = tTri(tRock, vTPos, n, 7.0 * tU) * vec3(0.95, 0.93, 0.9);
  vec3 c = cg * grass + cd * dirt + cs * sand + cr * rock;
  c = mix(c, vec3(0.93, 0.95, 1.0) * mix(0.82, 1.08, tLum(cr) / max(tMeans.z, 1e-3) * 0.5), snow);
  diffuseColor.rgb *= c;
}
`;

/** The terrain's material: painted from the surface sets once they load (plain green before). */
function terrainMaterial(sea: number): THREE.MeshStandardMaterial {
  const mat = new THREE.MeshStandardMaterial({ color: '#6F8A4E', roughness: 0.95, metalness: 0 });
  if (!surfacesEnabled()) return mat;
  void Promise.all(['grass', 'forest_ground', 'rock', 'earth'].map((s) => loadSurfaceSet(s))).then(([g, d, r, s]) => {
    if (!g || !d || !r || !s) return;
    const lum = (t: THREE.Texture) => {
      const img: any = t.image;
      if (!img || !img.width) return 0.3;
      try {
        const c = document.createElement('canvas');
        c.width = c.height = 16;
        const x = c.getContext('2d')!;
        x.drawImage(img, 0, 0, 16, 16);
        const px = x.getImageData(0, 0, 16, 16).data;
        let sum = 0;
        for (let i = 0; i < px.length; i += 4) sum += (px[i] + px[i + 1] + px[i + 2]) / 3;
        return sum / (px.length / 4) / 255;
      } catch {
        return 0.3;
      }
    };
    const uniforms = {
      tGrass: { value: g.c },
      tDirt: { value: d.c },
      tRock: { value: r.c },
      tSand: { value: s.c },
      tMeans: { value: new THREE.Vector4(lum(g.c), lum(d.c), lum(r.c), lum(s.c)) },
      tSea: { value: sea },
      tU: { value: U },
    };
    mat.color.set('#FFFFFF');
    mat.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, uniforms);
      shader.vertexShader = VERT + shader.vertexShader.replace(
        '#include <begin_vertex>',
        '#include <begin_vertex>\nvTPos = (modelMatrix * vec4(position, 1.0)).xyz;\nvTNrm = normalize(mat3(modelMatrix) * normal);'
      );
      shader.fragmentShader = FRAG + shader.fragmentShader.replace('#include <map_fragment>', PAINT);
    };
    mat.customProgramCacheKey = () => 'b8terrain';
    mat.needsUpdate = true;
  });
  return mat;
}

export class TerrainView {
  readonly group = new THREE.Group();
  private chunks: Chunk[] = [];
  private mat: THREE.MeshStandardMaterial;
  private n: number;

  constructor(private hf: Heightfield) {
    this.group.name = 'Terrain';
    this.mat = terrainMaterial(hf.info.sea);
    this.n = hf.info.samples - 1;
    const per = Math.ceil(this.n / CHUNK);
    const c = hf.cell;
    for (let cj = 0; cj < per; cj++) {
      for (let ci = 0; ci < per; ci++) {
        const mesh = new THREE.Mesh(undefined, this.mat);
        mesh.name = `Terrain_${ci}_${cj}`;
        mesh.receiveShadow = true;
        mesh.matrixAutoUpdate = false;
        const minX = hf.info.x0 + ci * CHUNK * c, minZ = hf.info.z0 + cj * CHUNK * c;
        this.chunks.push({ ci, cj, mesh, step: 0, geos: new Map(), minX, minZ, maxX: minX + CHUNK * c, maxZ: minZ + CHUNK * c });
        this.group.add(mesh);
      }
    }
  }

  private geometry(ch: Chunk, step: number): THREE.BufferGeometry {
    let g = ch.geos.get(step);
    if (g) return g;
    const hf = this.hf;
    const m = CHUNK / step, v = m + 1, c = hf.cell;
    const i0 = ch.ci * CHUNK, j0 = ch.cj * CHUNK;
    const pos = new Float32Array((v * v + 4 * v) * 3);
    const nor = new Float32Array((v * v + 4 * v) * 3);
    const nrm = (i: number, j: number, at: number) => {
      // from the fine samples (the same light at every level of detail)
      const x = hf.sample(i - 1, j) - hf.sample(i + 1, j), z = hf.sample(i, j - 1) - hf.sample(i, j + 1), y = 2 * c;
      const l = Math.hypot(x, y, z);
      nor[at] = x / l;
      nor[at + 1] = y / l;
      nor[at + 2] = z / l;
    };
    for (let b = 0; b < v; b++) {
      for (let a = 0; a < v; a++) {
        const i = Math.min(i0 + a * step, this.n), j = Math.min(j0 + b * step, this.n);
        const at = (b * v + a) * 3;
        pos[at] = hf.info.x0 + i * c;
        pos[at + 1] = hf.sample(i, j);
        pos[at + 2] = hf.info.z0 + j * c;
        nrm(i, j, at);
      }
    }
    // skirts: down a little inside the map (hides the seams between levels), down to below the
    // sea along the map's own edge (so the world doesn't look cut off from a mount)
    const per = Math.ceil(this.n / CHUNK);
    const edgeOfMap = [ch.cj === 0, ch.ci === per - 1, ch.cj === per - 1, ch.ci === 0];
    const top = (e: number, t: number) => (e === 0 ? t : e === 1 ? t * v + m : e === 2 ? m * v + (m - t) : (m - t) * v);
    const drop = step * c * 1.5 + U;
    const floor = hf.info.sea - 60 * U;
    for (let e = 0; e < 4; e++) {
      for (let t = 0; t < v; t++) {
        const src = top(e, t) * 3, at = (v * v + e * v + t) * 3;
        pos[at] = pos[src];
        pos[at + 1] = edgeOfMap[e] ? Math.min(pos[src + 1] - drop, floor) : pos[src + 1] - drop;
        pos[at + 2] = pos[src + 2];
        nor[at] = nor[src];
        nor[at + 1] = nor[src + 1];
        nor[at + 2] = nor[src + 2];
      }
    }
    g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    g.setIndex(chunkIndex(m));
    g.computeBoundingSphere();
    ch.geos.set(step, g);
    return g;
  }

  /** Per frame: each chunk's level of detail from its distance to the camera. */
  update(camera: THREE.Camera) {
    const cx = camera.position.x, cz = camera.position.z;
    for (const ch of this.chunks) {
      const dx = Math.max(ch.minX - cx, 0, cx - ch.maxX), dz = Math.max(ch.minZ - cz, 0, cz - ch.maxZ);
      const d = Math.hypot(dx, dz) / U;
      let k = 0;
      while (k < LOD_M.length && d > LOD_M[k]) k++;
      const step = STEPS[k];
      if (step === ch.step) continue;
      ch.mesh.geometry = this.geometry(ch, step);
      ch.step = step;
      // keep the neighbouring levels (walking back and forth), free the rest
      for (const [s, g] of ch.geos) {
        if (s < step / 2 || s > step * 2) {
          g.dispose();
          ch.geos.delete(s);
        }
      }
    }
  }

  dispose() {
    this.group.parent?.remove(this.group);
    for (const ch of this.chunks) for (const g of ch.geos.values()) g.dispose();
    this.chunks = [];
    this.mat.dispose();
  }
}
