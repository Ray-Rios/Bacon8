// Garment parts (2026-11-01): clothes that are their own skinned GLBs
// (/models/Humans/Garments/<Body>/<item>.glb, library/pipeline/scripts/b8_garments.py), loaded
// and bound to the body's bones like the hair. This file holds the pure parts: the cover sets
// (which body vertices a garment hides), triangle filtering, and the fabric materials.
//
// A part GLB carries, in its mesh node's extras "b8_part": {id, layer, cover}. `cover` is a voxel
// set over the body in its rest pose (glTF metres): origin `o`, cell size `c`, dims `d`, and the
// occupied cells run-length coded (`rle`: alternating runs starting with empty cells, as base-128
// varints, base64). A body vertex in an occupied cell is under the garment. Each garment vertex
// has the skin point it sits on (attribute _ANCHOR), so an inner layer hides where an outer one
// covers the same skin.
//
// Materials: each glTF material's extras "b8" names its role (which item colour tints it), its
// fabric (Humans/Fabrics/<fabric>_c|_n|_r.webp, b8_fabrics.py) and shading hints; the three.js
// side is garment-materials.ts.
export interface CoverSpec {
  o: number[];
  c: number;
  d: number[];
  rle: string;
  n?: number;
}

export interface Cover {
  o: [number, number, number];
  c: number;
  d: [number, number, number];
  bits: Uint8Array;
}

export interface PartMeta {
  id?: string;
  layer?: number;
  cover?: CoverSpec | null;
  hair?: string | null;
  /** Heels (b8_heels.py, 2026-11-01): point each foot `deg` toes-down (the toes stay flat) and lift the body `rise` metres. */
  heel?: { deg: number; rise: number } | null;
}

export interface FabricMeta {
  role?: string;
  fabric?: string;
  gain?: number;
  sheen?: number;
  sheenRough?: number;
  rough?: number;
  metal?: number;
  natural?: boolean;
  alpha?: boolean;
  lace?: boolean;
  normal?: boolean;
  roughMap?: boolean;
  opacity?: number;
  ds?: number;
  normalScale?: number;
}

function b64(s: string): Uint8Array {
  if (typeof atob === 'function') {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  // node (tests)
  return new Uint8Array((globalThis as any).Buffer.from(s, 'base64'));
}

/** Decodes a cover set (null for none or a malformed one). */
export function decodeCover(spec: CoverSpec | null | undefined): Cover | null {
  if (!spec || !spec.rle || !Array.isArray(spec.d) || spec.d.length !== 3) return null;
  const d: [number, number, number] = [spec.d[0] | 0, spec.d[1] | 0, spec.d[2] | 0];
  const total = d[0] * d[1] * d[2];
  if (!(total > 0) || total > 64_000_000) return null;
  const bits = new Uint8Array(total);
  const bytes = b64(spec.rle);
  let pos = 0;
  let on = false;
  let i = 0;
  while (i < bytes.length && pos <= total) {
    let run = 0;
    let mul = 1;
    for (;;) {
      const b = bytes[i++];
      run += (b & 0x7f) * mul;
      if (!(b & 0x80) || i >= bytes.length) break;
      mul *= 128;
    }
    if (on) bits.fill(1, pos, Math.min(total, pos + run));
    pos += run;
    on = !on;
  }
  return { o: [spec.o[0], spec.o[1], spec.o[2]], c: spec.c, d, bits };
}

/** True when the point (rest pose, glTF metres) is under the cover. */
export function covered(c: Cover, x: number, y: number, z: number): boolean {
  const i = Math.floor((x - c.o[0]) / c.c);
  const j = Math.floor((y - c.o[1]) / c.c);
  const k = Math.floor((z - c.o[2]) / c.c);
  if (i < 0 || j < 0 || k < 0 || i >= c.d[0] || j >= c.d[1] || k >= c.d[2]) return false;
  return c.bits[(i * c.d[1] + j) * c.d[2] + k] === 1;
}

/** Per-vertex flags: 1 where any of the covers hides the point (xyz triples). */
export function coverMask(points: ArrayLike<number>, count: number, covers: Cover[], stride = 3): Uint8Array {
  const out = new Uint8Array(count);
  if (!covers.length) return out;
  for (let v = 0; v < count; v++) {
    const x = points[v * stride], y = points[v * stride + 1], z = points[v * stride + 2];
    for (const c of covers) {
      if (covered(c, x, y, z)) {
        out[v] = 1;
        break;
      }
    }
  }
  return out;
}

/**
 * The triangles to keep: a triangle goes when its three corners are in hidden regions, or all
 * three are masked. Returns null when nothing is dropped.
 */
export function keepTriangles(
  index: ArrayLike<number>,
  ranges: Array<{ start: number; count: number; materialIndex?: number }>,
  region: ((v: number) => number) | null,
  hidden: Set<number>,
  mask: Uint8Array | null
): { index: number[]; groups: Array<{ start: number; count: number; materialIndex?: number }> } | null {
  const keep: number[] = [];
  const groups: Array<{ start: number; count: number; materialIndex?: number }> = [];
  const useRegion = !!region && hidden.size > 0;
  for (const r of ranges) {
    const start = keep.length;
    const end = Math.min(index.length, r.start + r.count);
    for (let i = r.start; i + 2 < end; i += 3) {
      const a = index[i], b = index[i + 1], c = index[i + 2];
      if (useRegion && hidden.has(region!(a)) && hidden.has(region!(b)) && hidden.has(region!(c))) continue;
      if (mask && mask[a] && mask[b] && mask[c]) continue;
      keep.push(a, b, c);
    }
    groups.push({ start, count: keep.length - start, materialIndex: r.materialIndex });
  }
  return keep.length === index.length ? null : { index: keep, groups };
}

/** Parses the extras JSON a material or node carries (a string or an object). */
export function parseMeta<T>(v: unknown): T | null {
  if (!v) return null;
  if (typeof v === 'object') return v as T;
  if (typeof v === 'string') {
    try {
      return JSON.parse(v) as T;
    } catch {
      return null;
    }
  }
  return null;
}

/** The colour a fabric role takes from an item's colours (hex), or null to keep it white. */
export function roleColor(meta: FabricMeta, colors: Record<string, string>): string {
  const role = meta.role || 'main';
  if (colors[role]) return colors[role];
  if (meta.natural || role === 'metal') return '#FFFFFF';
  return colors.main || '#FFFFFF';
}

/**
 * A cover grown by `r` cells in every direction (separable max filter). Inner garments are tested
 * against the grown cover: the build marks a cell only when all the skin in it is under the
 * garment, which is right for skin (no holes at the garment's edge) but leaves an inner layer
 * peeking through the gaps.
 */
export function dilateCover(c: Cover, r = 2): Cover {
  const [nx, ny, nz] = c.d;
  let a = c.bits;
  const idx = (i: number, j: number, k: number) => (i * ny + j) * nz + k;
  for (let axis = 0; axis < 3; axis++) {
    const b = new Uint8Array(a.length);
    for (let i = 0; i < nx; i++)
      for (let j = 0; j < ny; j++)
        for (let k = 0; k < nz; k++) {
          if (!a[idx(i, j, k)]) continue;
          for (let s = -r; s <= r; s++) {
            const ii = axis === 0 ? i + s : i, jj = axis === 1 ? j + s : j, kk = axis === 2 ? k + s : k;
            if (ii < 0 || jj < 0 || kk < 0 || ii >= nx || jj >= ny || kk >= nz) continue;
            b[idx(ii, jj, kk)] = 1;
          }
        }
    a = b;
  }
  return { o: c.o, c: c.c, d: c.d, bits: a };
}
