// The sea round the island and the lakes (2026-10-26). The server describes them
// (BaconWorld.Water, sent with fetch_mobs as `water`, in scene units); this draws them and
// answers the questions fishing asks: what water is at a point, is someone standing by it,
// where would a line facing this way land. The pure functions mirror the server's checks
// (BaconWorld.Water.near/3, cast/4) so the client only asks for what the server will allow.
//
// Drawn: a sand beach sloping into the sea all round the grass, the sea out to the horizon
// with moving ripples and a line of foam, and each lake with a muddy bank, reeds and lily pads.
// The bobber and the line (FishingView) float on the same water.
//
// With a terrain (terrain.ts, BaconWorld.Terrain; 2026-10-26) the server sends the sea's level
// (`sea`) and the layout gets the loaded heightfield (`terrain`): the sea, the crater lake and the
// ponds are wherever the ground is below that level, one water plane draws them all, the terrain
// makes its own beaches, and the walkable world is the map, no deeper than wading. The Millpond
// (an ellipse in `lakes`) stays as it was.
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { applySurface, surfacesEnabled } from './surface-textures';

const U = UNITS_PER_METRE;

export interface Lake { id: string; name: string; x: number; z: number; rx: number; rz: number }
/** What the water rules need from a terrain (terrain.ts's Heightfield has it). */
export interface WaterTerrain {
  water(x: number, z: number): { kind: WaterKind; name: string } | null;
  walkable(x: number, z: number): boolean;
  inside(x: number, z: number): boolean;
}
export interface WaterLayout {
  shore: number;
  walk_radius: number;
  bank: number;
  cast_reach: number;
  lakes: Lake[];
  /** The sea's height with a terrain (scene units); null or absent on the old island. */
  sea?: number | null;
  /** The loaded terrain (set by the client, never sent). */
  terrain?: WaterTerrain | null;
}
export type WaterKind = 'lake' | 'ocean';

/** 1 on a lake's edge, less inside, more outside. */
export function lakeScale(l: Lake, x: number, z: number): number {
  return Math.hypot((x - l.x) / l.rx, (z - l.z) / l.rz);
}

/** Distance from a point outside a lake to its edge (along the line from its middle); 0 inside. */
export function lakeDistance(l: Lake, x: number, z: number): number {
  const f = lakeScale(l, x, z);
  const d = Math.hypot(x - l.x, z - l.z);
  return f <= 1 ? 0 : d - d / f;
}

/** The water at a point, or null on land. */
export function waterKindAt(w: WaterLayout, x: number, z: number): WaterKind | null {
  if (w.lakes.some((l) => lakeScale(l, x, z) <= 1)) return 'lake';
  if (w.terrain) return w.terrain.water(x, z)?.kind ?? null;
  return Math.hypot(x, z) > w.shore ? 'ocean' : null;
}

/** The name of the water at a point ("the Millpond", "Crater Lake", "the sea"), or null. */
export function waterNameAt(w: WaterLayout, x: number, z: number): string | null {
  const lake = w.lakes.find((l) => lakeScale(l, x, z) <= 1);
  if (lake) return lake.name;
  if (w.terrain) return w.terrain.water(x, z)?.name ?? null;
  return Math.hypot(x, z) > w.shore ? 'the sea' : null;
}

/** The height of the water's surface at a point on water (scene units). */
export function waterYAt(w: WaterLayout, x: number, z: number): number {
  if (w.lakes.some((l) => lakeScale(l, x, z) <= 1)) return 0.03 * U;
  return w.sea ?? SEA_Y;
}

// The middle and points round circles of radius r and r / 2 (BaconWorld.Water's ring/3).
function ring(x: number, z: number, r: number): Array<[number, number]> {
  const out: Array<[number, number]> = [[x, z]];
  for (let i = 0; i < 16; i++) for (const rr of [r, r / 2]) out.push([x + rr * Math.cos((i * Math.PI) / 8), z + rr * Math.sin((i * Math.PI) / 8)]);
  return out;
}

/** The water within `within` of a point on land (a lake before the sea), or null. */
export function nearWater(w: WaterLayout, x: number, z: number, within: number): WaterKind | null {
  if (w.lakes.some((l) => lakeDistance(l, x, z) <= within)) return 'lake';
  if (w.terrain) {
    for (const [px, pz] of ring(x, z, within)) {
      const k = w.terrain.water(px, pz)?.kind;
      if (k) return k;
    }
    return null;
  }
  return Math.hypot(x, z) >= w.shore - within ? 'ocean' : null;
}

/**
 * Where a line cast from (px, pz) facing (dirX, dirZ) lands: the first point on water of the
 * kind the caster stands by, about six metres out if it can be, within reach. Null when the
 * caster isn't by water or faces away from it.
 */
export function castSpot(w: WaterLayout, px: number, pz: number, dirX: number, dirZ: number): { x: number; z: number; kind: WaterKind } | null {
  const kind = nearWater(w, px, pz, w.bank);
  if (!kind) return null;
  const len = Math.hypot(dirX, dirZ) || 1;
  const ux = dirX / len, uz = dirZ / len;
  for (const m of [6, 5, 7, 4.5, 8, 4, 9, 3.5, 3, 2.5, 2]) {
    const d = m * U;
    if (d > w.cast_reach - 0.25 * U) continue;
    const x = px + ux * d, z = pz + uz * d;
    if (waterKindAt(w, x, z) === kind) return { x, z, kind };
  }
  return null;
}

/**
 * Keeps a move from (fromX, fromZ) to (x, z) in the world. With a terrain: people swim, so only
 * the map's margin stops them (sliding along it where it can; someone already outside moves
 * freely, so they can always get back). Without: clamped to the island's shallows.
 */
export function keepOnLand(w: WaterLayout, x: number, z: number, fromX: number, fromZ: number): { x: number; z: number } {
  const t = w.terrain;
  if (!t) return clampToIsland(w, x, z);
  if (t.inside(x, z) || !t.inside(fromX, fromZ)) return { x, z };
  if (t.inside(x, fromZ)) return { x, z: fromZ };
  if (t.inside(fromX, z)) return { x: fromX, z };
  return { x: fromX, z: fromZ };
}

/** Keeps a point on the island: no further out than the shallows. */
export function clampToIsland(w: WaterLayout, x: number, z: number): { x: number; z: number } {
  const r = Math.hypot(x, z);
  if (r <= w.walk_radius) return { x, z };
  const k = w.walk_radius / r;
  return { x: x * k, z: z * k };
}

/** The lakes as colliders (nobody walks on water). */
export function lakeColliders(w: WaterLayout): Array<{ kind: 'ellipse'; x: number; z: number; rx: number; rz: number }> {
  return w.lakes.map((l) => ({ kind: 'ellipse' as const, x: l.x, z: l.z, rx: l.rx, rz: l.rz }));
}

// ------------------------------------------------------------------------------- drawing

/** A tileable ripple normal map (sums of waves with whole periods across the tile). */
function rippleNormals(seed: number): THREE.CanvasTexture {
  const N = 256;
  const c = document.createElement('canvas');
  c.width = c.height = N;
  const g = c.getContext('2d')!;
  const img = g.createImageData(N, N);
  let s = seed >>> 0;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const waves = Array.from({ length: 9 }, () => ({ kx: Math.round(rnd() * 8 - 4) || 1, ky: Math.round(rnd() * 8 - 4) || 2, ph: rnd() * Math.PI * 2, a: 0.4 + rnd() }));
  const h = (x: number, y: number) => waves.reduce((acc, w) => acc + w.a * Math.sin(((w.kx * x + w.ky * y) / N) * Math.PI * 2 + w.ph), 0);
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const dx = h(x + 1, y) - h(x - 1, y), dy = h(x, y + 1) - h(x, y - 1);
      const nx = -dx * 2.2, ny = -dy * 2.2, nz = 1;
      const l = Math.hypot(nx, ny, nz);
      const i = (y * N + x) * 4;
      img.data[i] = ((nx / l) * 0.5 + 0.5) * 255;
      img.data[i + 1] = ((ny / l) * 0.5 + 0.5) * 255;
      img.data[i + 2] = ((nz / l) * 0.5 + 0.5) * 255;
      img.data[i + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

function waterMaterial(color: string, normals: THREE.Texture, opacity: number, scale: number): THREE.MeshStandardMaterial {
  return new THREE.MeshStandardMaterial({
    color,
    roughness: 0.09,
    metalness: 0.05,
    normalMap: normals,
    normalScale: new THREE.Vector2(scale, scale),
    transparent: true,
    opacity,
    envMapIntensity: 1.2,
  });
}

/** The beach: a ring sloping from the grass's edge down under the sea (planar UVs, 4 m). */
function beachGeometry(shore: number, inner: number, outer: number): THREE.BufferGeometry {
  const rings = 48, segs = 256;
  const pos: number[] = [], uv: number[] = [], idx: number[] = [];
  for (let i = 0; i <= rings; i++) {
    const t = i / rings;
    const r = inner + (outer - inner) * Math.pow(t, 1.6);
    const m = (r - shore) / U; // metres past the waterline
    const y = (m <= 0 ? -0.07 * (1 + m / ((shore - inner) / U)) : -0.07 - Math.min(5, m * 0.11 + m * m * 0.0009)) * U;
    for (let j = 0; j <= segs; j++) {
      const a = (j / segs) * Math.PI * 2;
      const x = Math.sin(a) * r, z = Math.cos(a) * r;
      pos.push(x, y, z);
      uv.push(x / (4 * U), z / (4 * U));
    }
  }
  for (let i = 0; i < rings; i++) {
    for (let j = 0; j < segs; j++) {
      const a = i * (segs + 1) + j, b = a + segs + 1;
      idx.push(a, b, a + 1, a + 1, b, b + 1); // counter-clockwise from above: faces up
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

function rng(seed: number) {
  let t = seed >>> 0;
  return () => {
    t += 0x6d2b79f5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

/** Ripples ride at this many scene units a second. */
const DRIFT = 0.012;
const SEA_Y = -0.06 * U;

export class WaterView {
  readonly group = new THREE.Group();
  private sea: THREE.MeshStandardMaterial;
  private lakeMats: THREE.MeshStandardMaterial[] = [];
  private foam: THREE.MeshBasicMaterial;
  private foamMesh: THREE.Mesh | null = null;
  private seaMesh: THREE.Mesh;
  private seaY = SEA_Y;
  private t = 0;

  constructor(private layout: WaterLayout) {
    this.group.name = 'Water';
    const w = layout;
    if (w.sea != null) {
      // a terrain: one plane at the sea's level is the sea, the crater lake and the ponds (the
      // ground hides it everywhere else); the terrain has its own beaches
      const seaNormals = rippleNormals(7);
      seaNormals.repeat.set(1100, 1100);
      this.sea = waterMaterial('#1F5F78', seaNormals, 0.9, 0.55);
      this.seaMesh = new THREE.Mesh(new THREE.PlaneGeometry(13000 * U, 13000 * U, 1, 1).rotateX(-Math.PI / 2), this.sea);
      this.seaY = w.sea;
      this.seaMesh.position.y = w.sea;
      this.group.add(this.seaMesh);
      this.foam = new THREE.MeshBasicMaterial({ visible: false });
      for (const l of w.lakes) this.addLake(l);
      return;
    }
    // the beach, from under the grass's edge (world-dressing.ts: grass to 9 m inside the shore)
    const sandMat = new THREE.MeshStandardMaterial({ color: '#CDB892', roughness: 1 });
    // (surfaces tile in the mesh's own space, here scene units)
    if (surfacesEnabled()) void applySurface(sandMat, { set: 'earth', scale: 3 * U, antiTile: true });
    const beach = new THREE.Mesh(beachGeometry(w.shore, w.shore - 9.6 * U, w.shore + 220 * U), sandMat);
    beach.position.y = -0.004 * U;
    beach.receiveShadow = true;
    this.group.add(beach);
    // the sea, to the horizon
    const seaNormals = rippleNormals(7);
    seaNormals.repeat.set(900, 900);
    this.sea = waterMaterial('#1F5F78', seaNormals, 0.9, 0.55);
    this.seaMesh = new THREE.Mesh(new THREE.RingGeometry(w.shore - 3 * U, 5200 * U, 256, 1), this.sea);
    this.seaMesh.rotation.x = -Math.PI / 2;
    this.seaMesh.position.y = SEA_Y;
    this.group.add(this.seaMesh);
    // foam where the swell meets the sand: the beach drops only 7 cm over its first 9.6 m, so the
    // waterline (sea at -6 cm, +-1.8 cm) wanders between 3.6 m inside the shore and the shore itself
    this.foam = new THREE.MeshBasicMaterial({ color: '#F2F7F7', transparent: true, opacity: 0.35, depthWrite: false });
    const foam = new THREE.Mesh(new THREE.RingGeometry(w.shore - 2.8 * U, w.shore - 0.2 * U, 256, 1), this.foam);
    foam.rotation.x = -Math.PI / 2;
    foam.position.y = SEA_Y + 0.012 * U;
    this.foamMesh = foam;
    this.group.add(foam);
    for (const l of w.lakes) this.addLake(l);
  }

  private addLake(l: Lake) {
    const r = rng(l.id.length * 977 + 13);
    // the muddy bank
    const mud = new THREE.MeshStandardMaterial({ color: '#6B5A3E', roughness: 1, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
    if (surfacesEnabled()) void applySurface(mud, { set: 'earth', scale: 2.5 * U, antiTile: true });
    // (the ellipse is built at size, not scaled: surfaces tile in the mesh's own space)
    const bank = new THREE.Mesh(new THREE.CircleGeometry(1, 72).scale(l.rx + 1.8 * U, l.rz + 1.8 * U, 1), mud);
    bank.rotation.x = -Math.PI / 2;
    bank.position.set(l.x, 0.008 * U, l.z);
    bank.receiveShadow = true;
    this.group.add(bank);
    // the water, darker and stiller than the sea
    const normals = rippleNormals(31);
    normals.repeat.set(Math.round((l.rx / U) / 2), Math.round((l.rz / U) / 2));
    const mat = waterMaterial('#24493E', normals, 0.93, 0.32);
    // the bank is pulled forward in depth (polygonOffset, to beat the grass), so the water is pulled further
    mat.polygonOffset = true; mat.polygonOffsetFactor = -4; mat.polygonOffsetUnits = -4;
    this.lakeMats.push(mat);
    const water = new THREE.Mesh(new THREE.CircleGeometry(1, 72), mat);
    water.rotation.x = -Math.PI / 2;
    water.scale.set(l.rx, l.rz, 1);
    water.position.set(l.x, 0.03 * U, l.z);
    this.group.add(water);
    // reeds in clumps round the edge (not on the east bank, where the angler stands)
    const reedGeo = new THREE.ConeGeometry(0.018 * U, 1, 4).translate(0, 0.5, 0);
    const reedMat = new THREE.MeshStandardMaterial({ color: '#6F7D3A', roughness: 0.9 });
    const spots: THREE.Matrix4[] = [];
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * Math.PI * 2 + r() * 0.3;
      if (Math.abs(Math.atan2(Math.sin(a - Math.PI / 2), Math.cos(a - Math.PI / 2))) < 0.5) continue; // east (+x)
      const edge = 0.96 + r() * 0.1;
      const cx = l.x + Math.sin(a) * l.rx * edge, cz = l.z + Math.cos(a) * l.rz * edge;
      const n = 7 + Math.floor(r() * 8);
      for (let i = 0; i < n; i++) {
        const h = (0.8 + r() * 0.9) * U;
        const m = new THREE.Matrix4().compose(
          new THREE.Vector3(cx + (r() - 0.5) * 0.9 * U, 0, cz + (r() - 0.5) * 0.9 * U),
          new THREE.Quaternion().setFromEuler(new THREE.Euler((r() - 0.5) * 0.25, r() * 6.28, (r() - 0.5) * 0.25)),
          new THREE.Vector3(1, h, 1),
        );
        spots.push(m);
      }
    }
    const reeds = new THREE.InstancedMesh(reedGeo, reedMat, spots.length);
    spots.forEach((m, i) => reeds.setMatrixAt(i, m));
    reeds.castShadow = true;
    this.group.add(reeds);
    // lily pads
    const padGeo = new THREE.CircleGeometry(0.22 * U, 10, 0.5, Math.PI * 1.75).rotateX(-Math.PI / 2);
    const padMat = new THREE.MeshStandardMaterial({ color: '#3F6E2E', roughness: 0.6, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -6, polygonOffsetUnits: -6 });
    const pads = new THREE.InstancedMesh(padGeo, padMat, 18);
    for (let i = 0; i < 18; i++) {
      const a = r() * Math.PI * 2, d = 0.45 + r() * 0.45;
      const s = 0.7 + r() * 0.8;
      pads.setMatrixAt(i, new THREE.Matrix4().compose(
        new THREE.Vector3(l.x + Math.sin(a) * l.rx * d, 0.035 * U, l.z + Math.cos(a) * l.rz * d),
        new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), r() * 6.28),
        new THREE.Vector3(s, 1, s),
      ));
    }
    this.group.add(pads);
  }

  tick(dt: number) {
    this.t += dt;
    const t = this.t;
    if (this.sea.normalMap) this.sea.normalMap.offset.set(t * DRIFT, t * DRIFT * 0.6);
    this.seaMesh.position.y = this.seaY + Math.sin(t * 0.55) * 0.018 * U;
    if (this.foamMesh) this.foamMesh.position.y = this.seaMesh.position.y + 0.012 * U; // rides the swell, never under it
    this.foam.opacity = 0.26 + 0.14 * (0.5 + 0.5 * Math.sin(t * 0.9));
    for (const m of this.lakeMats) if (m.normalMap) m.normalMap.offset.set(t * DRIFT * 0.35, -t * DRIFT * 0.2);
  }

  dispose() {
    this.group.parent?.remove(this.group);
    this.group.traverse((o: any) => {
      o.geometry?.dispose?.();
    });
  }
}

// ------------------------------------------------------------------------------- the line

/**
 * The bobber and the line while fishing: cast in an arc to the spot, bobbing on the water; a
 * bite pulls it under in jerks; reeling in takes it away.
 */
export class FishingView {
  private bobber: THREE.Group;
  private line: THREE.Line;
  private linePos: Float32Array;
  private rings: Array<{ mesh: THREE.Mesh; t: number }> = [];
  private ringGeo = new THREE.RingGeometry(0.8, 1, 24).rotateX(-Math.PI / 2);
  private ringMat = new THREE.MeshBasicMaterial({ color: '#E8F2F2', transparent: true, opacity: 0.5, depthWrite: false });
  private state: 'idle' | 'flying' | 'floating' | 'biting' = 'idle';
  private from = new THREE.Vector3();
  private to = new THREE.Vector3();
  private t = 0;
  private waterY = 0;

  constructor(private parent: THREE.Object3D) {
    this.bobber = new THREE.Group();
    const top = new THREE.Mesh(new THREE.SphereGeometry(0.06 * U, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshStandardMaterial({ color: '#D8332A', roughness: 0.4 }));
    const bottom = new THREE.Mesh(new THREE.SphereGeometry(0.06 * U, 12, 8, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), new THREE.MeshStandardMaterial({ color: '#F2F2EE', roughness: 0.4 }));
    const stick = new THREE.Mesh(new THREE.CylinderGeometry(0.006 * U, 0.006 * U, 0.08 * U, 5).translate(0, 0.08 * U, 0), new THREE.MeshStandardMaterial({ color: '#222222' }));
    this.bobber.add(top, bottom, stick);
    this.bobber.visible = false;
    this.linePos = new Float32Array(16 * 3);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.linePos, 3));
    this.line = new THREE.Line(geo, new THREE.LineBasicMaterial({ color: '#DDE3E3', transparent: true, opacity: 0.7 }));
    this.line.frustumCulled = false;
    this.line.visible = false;
    parent.add(this.bobber, this.line);
  }

  get active() {
    return this.state !== 'idle';
  }

  /** Casts from `tip` (the rod's end) to a spot on the water at height `waterY`. */
  cast(tip: THREE.Vector3, x: number, z: number, waterY: number) {
    this.from.copy(tip);
    this.to.set(x, waterY, z);
    this.waterY = waterY;
    this.t = 0;
    this.state = 'flying';
    this.bobber.visible = this.line.visible = true;
  }

  bite() {
    if (this.state === 'floating') {
      this.state = 'biting';
      this.t = 0;
      this.splash(0.5);
    }
  }

  reel() {
    this.state = 'idle';
    this.bobber.visible = this.line.visible = false;
  }

  /** Per frame; `tip` is where the rod's end is now. Returns true when the bobber just landed. */
  update(dt: number, tip: THREE.Vector3 | null): boolean {
    let landed = false;
    this.t += dt;
    if (this.state === 'flying') {
      const k = Math.min(1, this.t / 0.55);
      this.bobber.position.lerpVectors(this.from, this.to, k);
      this.bobber.position.y += Math.sin(k * Math.PI) * 1.4 * U;
      if (k >= 1) {
        this.state = 'floating';
        this.t = 0;
        this.splash(0.35);
        landed = true;
      }
    } else if (this.state === 'floating') {
      this.bobber.position.copy(this.to);
      this.bobber.position.y = this.waterY + Math.sin(this.t * 2.4) * 0.012 * U;
    } else if (this.state === 'biting') {
      // pulled under in jerks
      const jerk = Math.max(0, Math.sin(this.t * 13)) * 0.09 * U + 0.03 * U;
      this.bobber.position.copy(this.to);
      this.bobber.position.y = this.waterY - jerk;
      if (Math.random() < dt * 3) this.splash(0.3);
    }
    if (this.line.visible && tip) {
      // the line sags between the tip and the bobber
      const b = this.bobber.position;
      for (let i = 0; i < 16; i++) {
        const k = i / 15;
        const sag = Math.sin(k * Math.PI) * (this.state === 'biting' ? 0.05 : 0.35) * U;
        this.linePos[i * 3] = tip.x + (b.x - tip.x) * k;
        this.linePos[i * 3 + 1] = tip.y + (b.y - tip.y) * k - sag;
        this.linePos[i * 3 + 2] = tip.z + (b.z - tip.z) * k;
      }
      (this.line.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    }
    this.rings = this.rings.filter((r) => {
      r.t += dt;
      const k = r.t / 0.9;
      r.mesh.scale.setScalar((0.12 + k * 0.6) * U);
      (r.mesh.material as THREE.MeshBasicMaterial).opacity = 0.5 * (1 - k);
      if (k >= 1) {
        this.parent.remove(r.mesh);
        (r.mesh.material as THREE.Material).dispose?.();
        return false;
      }
      return true;
    });
    return landed;
  }

  private splash(size: number) {
    const mesh = new THREE.Mesh(this.ringGeo, this.ringMat.clone());
    mesh.position.set(this.to.x, this.waterY + 0.01 * U, this.to.z);
    mesh.scale.setScalar(size * U);
    this.parent.add(mesh);
    this.rings.push({ mesh, t: 0 });
  }

  dispose() {
    this.reel();
    this.parent.remove(this.bobber, this.line);
    for (const r of this.rings) this.parent.remove(r.mesh);
    this.rings = [];
  }
}

/** Where water stands at a point, in scene units (the bobber floats there). */
export function waterLevel(kind: WaterKind): number {
  return kind === 'lake' ? 0.03 * U : SEA_Y;
}
