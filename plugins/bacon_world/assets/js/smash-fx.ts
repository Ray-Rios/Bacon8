// Smashing placed things (2026-10-30): build mode's smash toggle (X, or the build window's Smash
// button). Each click is a hit: the piece shakes and puffs dust, and after a few hits (more for bigger
// pieces) it shatters into its own bits, which fly, bounce on the ground, settle and sink away.
//
// How the bits are made, cheaply and without a single new shader:
//   * The piece's own triangles are sorted into a grid over its bounds (2x2x2 for small things,
//     3x3x3 for bigger ones). Each cell's triangles become one bit, so the bits carry the piece's
//     real textures and colours. The bits are shells (no inside faces), which flying fast and
//     sinking away hides. They are cut once per kind of piece and reused.
//   * Each bit is drawn as an InstancedMesh of one, with the piece's own material: the same shader
//     program the placed copies already use (an ordinary Mesh would need its own, built on the frame
//     of the smash: the stutter warmup.ts exists to prevent).
//   * Dust is a plain PointsMaterial, one of warmup.ts' stand-ins.
//
// The bits are only for show: each client makes its own, and nothing collides with them. Only the
// smash itself goes through the server (a build_delete with smash: true, the same permission as
// removing), which tells every client in the zone to shatter it, and Ctrl+Z still puts it back.
// Going further (pre-fractured models from Blender, real physics, damage that lasts) is in
// BACON_WORLD.md, "Smashing".
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';

const U = UNITS_PER_METRE;
const GRAVITY = 9.8; // m/s²
const REST_S = 4.0; // how long the bits lie there
const SINK_S = 1.2; // then they shrink away over this long
const MAX_BITS = 220; // at once, over every smash (the oldest go first)
const DUST_S = 1.4;

export interface SmashPart {
  geo: THREE.BufferGeometry;
  mat: THREE.Material | THREE.Material[];
  local: THREE.Matrix4;
}

/** How many hits a piece takes, by its size (metres): a candle 1, a barrel 2, a wall 4, a house 6. */
export function hitsFor(box: THREE.Box3): number {
  const s = box.getSize(new THREE.Vector3());
  const big = Math.max(s.x, s.y, s.z);
  return Math.max(1, Math.min(6, Math.round(1 + big / 1.2)));
}

interface Bit {
  geo: THREE.BufferGeometry;
  /** Where the bit's middle was in the part's (model's) frame. */
  center: THREE.Vector3;
  radius: number;
}

/**
 * Cuts a geometry (in the model's frame after `local`) into bits by a grid of n cells a side.
 * Pure geometry, no GPU work: unit-tested.
 */
export function cutIntoBits(src: THREE.BufferGeometry, local: THREE.Matrix4, n: number): Bit[] {
  const pos = src.getAttribute('position');
  if (!pos) return [];
  const index = src.getIndex();
  const vertCount = index ? index.count : pos.count;
  const tris = Math.floor(vertCount / 3);
  const vid = (t: number, k: number) => (index ? index.getX(t * 3 + k) : t * 3 + k);
  // triangle centres, in the model's frame, decide the cells
  const box = new THREE.Box3();
  const v = new THREE.Vector3();
  const centres = new Float32Array(tris * 3);
  for (let t = 0; t < tris; t++) {
    let cx = 0, cy = 0, cz = 0;
    for (let k = 0; k < 3; k++) {
      v.fromBufferAttribute(pos as THREE.BufferAttribute, vid(t, k)).applyMatrix4(local);
      cx += v.x;
      cy += v.y;
      cz += v.z;
    }
    centres[t * 3] = cx / 3;
    centres[t * 3 + 1] = cy / 3;
    centres[t * 3 + 2] = cz / 3;
    box.expandByPoint(v.set(cx / 3, cy / 3, cz / 3));
  }
  const size = box.getSize(new THREE.Vector3());
  const cellOf = (t: number) => {
    const c = (a: number, min: number, len: number) => (len > 1e-6 ? Math.min(n - 1, Math.max(0, Math.floor(((a - min) / len) * n))) : 0);
    return c(centres[t * 3], box.min.x, size.x) + n * (c(centres[t * 3 + 1], box.min.y, size.y) + n * c(centres[t * 3 + 2], box.min.z, size.z));
  };
  // which material each triangle draws with (multi-material parts keep their groups)
  const groupOf = new Int32Array(tris);
  for (const g of src.groups) {
    const from = Math.floor(g.start / 3), to = Math.min(tris, Math.floor((g.start + g.count) / 3));
    for (let t = from; t < to; t++) groupOf[t] = g.materialIndex ?? 0;
  }
  const cells = new Map<number, number[]>();
  for (let t = 0; t < tris; t++) {
    const c = cellOf(t);
    let list = cells.get(c);
    if (!list) cells.set(c, (list = []));
    list.push(t);
  }
  const names = Object.keys(src.attributes);
  const bits: Bit[] = [];
  for (const list of cells.values()) {
    if (src.groups.length) list.sort((a, b) => groupOf[a] - groupOf[b]);
    const g = new THREE.BufferGeometry();
    for (const name of names) {
      const attr = src.getAttribute(name) as THREE.BufferAttribute;
      const size = attr.itemSize;
      const out = new Float32Array(list.length * 3 * size);
      let o = 0;
      for (const t of list) {
        for (let k = 0; k < 3; k++) {
          const i = vid(t, k);
          out[o++] = attr.getX(i);
          if (size > 1) out[o++] = attr.getY(i);
          if (size > 2) out[o++] = attr.getZ(i);
          if (size > 3) out[o++] = attr.getW(i);
        }
      }
      g.setAttribute(name, new THREE.BufferAttribute(out, size));
    }
    if (src.groups.length) {
      let start = 0;
      while (start < list.length) {
        let end = start;
        while (end < list.length && groupOf[list[end]] === groupOf[list[start]]) end++;
        g.addGroup(start * 3, (end - start) * 3, groupOf[list[start]]);
        start = end;
      }
    }
    g.applyMatrix4(local);
    g.computeBoundingBox();
    const center = g.boundingBox!.getCenter(new THREE.Vector3());
    g.translate(-center.x, -center.y, -center.z);
    g.computeBoundingSphere();
    bits.push({ geo: g, center, radius: g.boundingSphere?.radius || 0.1 });
  }
  return bits;
}

interface Flying {
  obj: THREE.InstancedMesh;
  v: THREE.Vector3;
  spin: THREE.Vector3;
  radius: number;
  age: number;
  rest: number;
  scale0: THREE.Vector3;
}

interface Dust {
  pts: THREE.Points;
  vel: Float32Array;
  age: number;
}

const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _m = new THREE.Matrix4();

export class SmashFx {
  /** In the placed things' group (metres). */
  readonly group = new THREE.Group();
  private flying: Flying[] = [];
  private dust: Dust[] = [];
  private cut = new Map<string, Bit[][]>();

  /** `ground(x, z)`: the ground's height in metres (PlacedView.ground). */
  constructor(private ground: (x: number, z: number) => number) {
    this.group.name = 'SmashFx';
  }

  /** A hit that doesn't break it yet: a puff of dust where it was struck (metres). */
  hit(at: THREE.Vector3, size = 1) {
    this.puff(at, 14 + Math.round(size * 6), 1.2 + size * 0.4, '#B9A88A');
  }

  /**
   * Shatters a placed piece: `key` names its kind (the bits are cut once per kind), `matrix` is
   * the placement's (PlacedView.pieces), `power` how hard (1: a normal smash).
   */
  shatter(key: string, parts: SmashPart[], matrix: THREE.Matrix4, box: THREE.Box3, power = 1) {
    let cutParts = this.cut.get(key);
    if (!cutParts) {
      const size = box.getSize(new THREE.Vector3());
      const n = Math.max(size.x, size.y, size.z) < 1.0 ? 2 : 3;
      cutParts = parts.map((p) => cutIntoBits(p.geo, p.local, n));
      this.cut.set(key, cutParts);
    }
    const mid = box.getCenter(new THREE.Vector3());
    const scale = new THREE.Vector3();
    matrix.decompose(new THREE.Vector3(), new THREE.Quaternion(), scale);
    cutParts.forEach((bits, i) => {
      const mat = parts[i].mat as any;
      for (const bit of bits) {
        const obj = new THREE.InstancedMesh(bit.geo, mat, 1);
        obj.castShadow = true;
        obj.receiveShadow = true;
        obj.raycast = () => {};
        _m.copy(matrix).multiply(new THREE.Matrix4().makeTranslation(bit.center.x, bit.center.y, bit.center.z));
        _m.decompose(obj.position, obj.quaternion, obj.scale);
        const out = obj.position.clone().sub(mid);
        out.y = 0;
        if (out.lengthSq() < 1e-6) out.set(Math.random() - 0.5, 0, Math.random() - 0.5);
        out.normalize();
        const speed = (1.4 + Math.random() * 2.6) * power;
        const v = out.multiplyScalar(speed);
        v.y = (1.5 + Math.random() * 3.0) * power * (0.6 + 0.4 * Math.min(1, (obj.position.y - box.min.y) / Math.max(0.3, box.max.y - box.min.y)));
        const spin = new THREE.Vector3((Math.random() - 0.5) * 12, (Math.random() - 0.5) * 12, (Math.random() - 0.5) * 12);
        this.group.add(obj);
        this.flying.push({ obj, v, spin, radius: bit.radius * Math.max(scale.x, scale.y, scale.z), age: 0, rest: 0, scale0: obj.scale.clone() });
      }
    });
    // the oldest bits go first when there are too many
    while (this.flying.length > MAX_BITS) this.drop(this.flying.shift()!);
    const size = box.getSize(new THREE.Vector3());
    this.puff(mid.setY(box.min.y + size.y * 0.35), 40, 2 + Math.max(size.x, size.z) * 0.5, '#A89A82');
  }

  update(dt: number) {
    if (!this.flying.length && !this.dust.length) return;
    dt = Math.min(dt, 0.05);
    for (let i = this.flying.length - 1; i >= 0; i--) {
      const f = this.flying[i];
      f.age += dt;
      const o = f.obj;
      if (f.rest < 1) {
        f.v.y -= GRAVITY * dt;
        o.position.addScaledVector(f.v, dt);
        _q.setFromEuler(_e.set(f.spin.x * dt, f.spin.y * dt, f.spin.z * dt));
        o.quaternion.multiply(_q);
        const floor = this.ground(o.position.x, o.position.z) + f.radius * 0.35;
        if (o.position.y < floor) {
          o.position.y = floor;
          if (f.v.y < 0) f.v.y = -f.v.y * 0.28;
          f.v.x *= 0.55;
          f.v.z *= 0.55;
          f.spin.multiplyScalar(0.5);
          if (f.v.lengthSq() < 0.25) {
            f.rest = 1;
            f.age = Math.max(f.age, 0.6);
          }
        }
        // whatever happens, it has stopped by the time it should sink
        if (f.age > REST_S) f.rest = 1;
      }
      const sink = f.age - REST_S;
      if (sink > 0) {
        const k = Math.max(0, 1 - sink / SINK_S);
        o.scale.copy(f.scale0).multiplyScalar(k);
        if (k <= 0) {
          this.drop(f);
          this.flying.splice(i, 1);
        }
      }
    }
    for (let i = this.dust.length - 1; i >= 0; i--) {
      const d = this.dust[i];
      d.age += dt;
      const attr = d.pts.geometry.getAttribute('position') as THREE.BufferAttribute;
      const a = attr.array as Float32Array;
      for (let k = 0; k < a.length; k += 3) {
        a[k] += d.vel[k] * dt;
        a[k + 1] += d.vel[k + 1] * dt;
        a[k + 2] += d.vel[k + 2] * dt;
        d.vel[k] *= 0.94;
        d.vel[k + 1] = d.vel[k + 1] * 0.94 + 0.15 * dt;
        d.vel[k + 2] *= 0.94;
      }
      attr.needsUpdate = true;
      const m = d.pts.material as THREE.PointsMaterial;
      m.opacity = 0.55 * Math.max(0, 1 - d.age / DUST_S);
      m.size = (0.35 + d.age * 0.5) * U;
      if (d.age >= DUST_S) {
        this.group.remove(d.pts);
        d.pts.geometry.dispose();
        m.dispose();
        this.dust.splice(i, 1);
      }
    }
  }

  /** Everything flying now, gone (leaving the world). */
  clear() {
    for (const f of this.flying) this.drop(f);
    this.flying = [];
    for (const d of this.dust) {
      this.group.remove(d.pts);
      d.pts.geometry.dispose();
      (d.pts.material as THREE.Material).dispose();
    }
    this.dust = [];
  }

  private drop(f: Flying) {
    this.group.remove(f.obj);
    // the bit's geometry is the kind's, kept for the next smash; the material is the placed copies'
    f.obj.dispose();
  }

  private puff(at: THREE.Vector3, count: number, speed: number, color: string) {
    const pos = new Float32Array(count * 3);
    const vel = new Float32Array(count * 3);
    for (let i = 0; i < count; i++) {
      pos[i * 3] = at.x + (Math.random() - 0.5) * 0.3;
      pos[i * 3 + 1] = at.y + Math.random() * 0.3;
      pos[i * 3 + 2] = at.z + (Math.random() - 0.5) * 0.3;
      const a = Math.random() * Math.PI * 2, s = speed * (0.3 + Math.random() * 0.7);
      vel[i * 3] = Math.cos(a) * s;
      vel[i * 3 + 1] = Math.random() * speed * 0.6;
      vel[i * 3 + 2] = Math.sin(a) * s;
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    // a plain PointsMaterial: the same program as warmup.ts' stand-in (the Kraken's bubbles)
    const m = new THREE.PointsMaterial({ color, size: 0.35 * U, transparent: true, opacity: 0.55, depthWrite: false, sizeAttenuation: true });
    const pts = new THREE.Points(g, m);
    pts.frustumCulled = false;
    pts.raycast = () => {};
    this.group.add(pts);
    this.dust.push({ pts, vel, age: 0 });
  }
}
