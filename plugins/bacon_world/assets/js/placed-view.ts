// What is in the world as placements (BaconWorld.Building, 2026-10-28): everything players put there
// in build mode and, once the server has seeded them, the village and the creature camps the code
// used to lay out. Props and building pieces are drawn from the village's own GLBs (P_<Id>, K_<Id>,
// and world-dressing.ts' X_Plinth), **instanced**: one InstancedMesh per part of each kind of piece,
// so the village's ~350 pieces cost a draw call per kind, not per piece. Creature spawns and NPCs get
// markers that only show in build mode (the creatures and the people are mobs-view.ts's and
// npcs-view.ts's).
//
// Everything here is in metres: the group sits in the village's group, scaled by UNITS_PER_METRE.
// A placement turns about the vertical (`rot`) and has a size (`scale`, or `data.s` [x, y, z] for the
// village's stretched pieces: gables, crags).
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { applySurface, surfaceFor, type Family } from './surface-textures';
import type { Collider } from './world-dressing';

const U = UNITS_PER_METRE;

export interface Placement {
  id: string;
  asset: string;
  x: number;
  y: number;
  z: number;
  rot: number;
  scale: number;
  data: Record<string, any>;
  npc?: any;
}

/** Where a template comes from: the village's loaded pieces (world-dressing.ts). */
export interface TemplateSource {
  template(name: string): THREE.Object3D | null;
  ready(): Promise<void>;
  /** Lamps and braziers glow at night (world-dressing.ts' tick). */
  addGlow?(mat: THREE.Material): void;
}

/** True for a placement drawn with a model (a prop or building piece), not a spawn or an NPC. */
export function isModel(asset: string): boolean {
  return /^[PKX]_/.test(asset);
}

/** A placement's size on each axis. */
export function sizeOf(p: { scale: number; data?: Record<string, any> }): [number, number, number] {
  const s = p.data?.s;
  if (Array.isArray(s) && s.length === 3 && s.every((v) => typeof v === 'number' && v > 0)) return [s[0], s[1], s[2]];
  const k = p.scale || 1;
  return [k, k, k];
}

/** Whether a piece blocks walking, and how (pure; unit-tested). */
export function colliderShape(asset: string, box: { min: { x: number; y: number; z: number }; max: { x: number; y: number; z: number } }):
  | { kind: 'none' }
  | { kind: 'circle'; r: number }
  | { kind: 'box'; hx: number; hz: number; cx: number; cz: number }
  | { kind: 'gate'; hx: number; hz: number; gap: number } {
  const name = asset.replace(/^[PKX]_/, '');
  const h = box.max.y - box.min.y;
  const sx = box.max.x - box.min.x;
  const sz = box.max.z - box.min.z;
  // walked on, over or under: floors, foundations, stairs, roofs, rugs, plates, ladders, doors left
  // open; and the soft things (bushes, grass, mushrooms, a bedroll)
  if (/^(Floor|Foundation|Stairs|Roof|Ladder|Door|Rug|PressurePlate|GrassTuft|Mushrooms|Shutters|Window|Bush|BushFlowers|Bedroll|Candle|Candelabra)/.test(name)) return { kind: 'none' };
  if (h < 0.35 || Math.max(sx, sz) < 0.2) return { kind: 'none' };
  // a wall with a way through it: two sides, the middle open
  if (/(Door|Gateway|Gate)$/.test(name) || name === 'Arch_Stone' || name === 'Fence_Gate') return { kind: 'gate', hx: sx / 2, hz: Math.max(sz / 2, 0.12), gap: Math.min(1.3, sx * 0.45) };
  // trees: the trunk, not the crown
  if (/^Tree/.test(name)) return { kind: 'circle', r: 0.35 };
  // round things
  if (/^(Barrel|BarrelWater|Rock|Boulder|Stump|Well|Cauldron|ClayPot|Amphora|Brazier|LampPost|Statue|Haystack|Bucket|Campfire|Waystone|Pillar)/.test(name)) {
    return { kind: 'circle', r: Math.max(0.15, Math.min(sx, sz) * 0.5) };
  }
  return { kind: 'box', hx: sx / 2, hz: sz / 2, cx: (box.max.x + box.min.x) / 2, cz: (box.max.z + box.min.z) / 2 };
}

interface Part {
  geo: THREE.BufferGeometry;
  mat: THREE.Material | THREE.Material[];
  local: THREE.Matrix4;
}

// The copies' bounds are computed by three.js on the first raycast and then kept: a piece placed or
// moved outside them could not be clicked (2026-10-30: "buildable objects cannot be selected to be
// moved"). Every write forgets them, so the next pick measures again.
function stale(im: THREE.InstancedMesh) {
  im.boundingSphere = null;
  im.boundingBox = null;
}

/** Every copy of one kind of piece: an InstancedMesh per part, slot n = placement ids[n]. */
interface Bucket {
  asset: string;
  parts: Part[];
  meshes: THREE.InstancedMesh[];
  ids: string[];
  cap: number;
  box: THREE.Box3;
}

interface Entry {
  p: Placement;
  /** The bucket and slot of a model; null for a marker. */
  bucket: Bucket | null;
  marker: THREE.Object3D | null;
  cols: Collider[];
  hidden: boolean;
}

const MARKER_MOB = new THREE.MeshBasicMaterial({ color: '#E2533A', transparent: true, opacity: 0.55, depthWrite: false });
const MARKER_NPC = new THREE.MeshBasicMaterial({ color: '#8FD3FF', transparent: true, opacity: 0.55, depthWrite: false });
const MARKER_STONE = new THREE.MeshBasicMaterial({ color: '#B98CFF', transparent: true, opacity: 0.22, depthWrite: false, side: THREE.DoubleSide });
const MARKER_PICK = new THREE.MeshBasicMaterial({ visible: false });
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);
const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _v = new THREE.Vector3();
const _s = new THREE.Vector3();
const Y = new THREE.Vector3(0, 1, 0);
const X = new THREE.Vector3(1, 0, 0);
const _qt = new THREE.Quaternion();

export class PlacedView {
  /** In the village's group (metres). */
  readonly group = new THREE.Group();
  private entries = new Map<string, Entry>();
  private buckets = new Map<string, Bucket>();
  private prepared = new Map<string, THREE.Object3D>();
  private shapes = new Map<string, THREE.Box3>();
  private mats = new Map<string, THREE.Material>();
  private showMarkers = false;
  private rings = new Map<string, THREE.Object3D>();
  /** The ground under (x, z), metres (terrain.ts; 0 while flat). */
  ground: (x: number, z: number) => number = () => 0;
  /** Colliders changed: the hook rebuilds the walking ones. */
  onColliders: (() => void) | null = null;
  private colsDirty = false;

  constructor(private source: TemplateSource) {
    this.group.name = 'Placed';
  }

  // ---------------------------------------------------------------- the list

  async setAll(list: Placement[]) {
    const keep = new Set(list.map((p) => p.id));
    for (const id of [...this.entries.keys()]) if (!keep.has(id)) this.remove(id, true);
    await this.source.ready();
    for (const p of list) this.put(p, true);
    this.onColliders?.();
  }

  /** A placement, new or changed (the server's word). */
  put(p: Placement, quiet = false) {
    let e = this.entries.get(p.id);
    if (e && e.p.asset !== p.asset) {
      this.remove(p.id, true);
      e = undefined;
    }
    if (!e) {
      e = { p, bucket: null, marker: null, cols: [], hidden: false };
      this.entries.set(p.id, e);
      if (isModel(p.asset)) {
        const b = this.bucketFor(p.asset);
        if (b) {
          b.ids.push(p.id);
          this.grow(b);
          e.bucket = b;
        }
      } else {
        e.marker = this.markerFor(p);
        this.group.add(e.marker);
        e.marker.visible = this.showMarkers;
      }
    }
    e.p = p;
    if (e.bucket) {
      this.writeSlot(e.bucket, e.bucket.ids.indexOf(p.id), e.hidden ? null : p);
      e.cols = this.collidersFor(p);
    } else if (e.marker) {
      this.poseMarker(e.marker, p);
    }
    this.syncRing(p);
    if (!quiet) this.onColliders?.();
  }

  remove(id: string, quiet = false) {
    const e = this.entries.get(id);
    if (!e) return;
    if (e.bucket) {
      const b = e.bucket;
      const slot = b.ids.indexOf(id);
      const last = b.ids.length - 1;
      if (slot >= 0) {
        // the last copy moves into the gap
        if (slot !== last) {
          b.ids[slot] = b.ids[last];
          const moved = this.entries.get(b.ids[slot]);
          if (moved) this.writeSlot(b, slot, moved.hidden ? null : moved.p);
        }
        b.ids.pop();
        for (const m of b.meshes) {
          m.count = b.ids.length;
          stale(m);
        }
      }
    }
    if (e.marker) this.group.remove(e.marker);
    const ring = this.rings.get(id);
    if (ring) {
      this.group.remove(ring);
      this.rings.delete(id);
    }
    this.entries.delete(id);
    if (!quiet) this.onColliders?.();
  }

  get(id: string): Placement | null {
    return this.entries.get(id)?.p ?? null;
  }

  all(): Placement[] {
    return [...this.entries.values()].map((e) => e.p);
  }

  /** Hides one while it is held (the ghost stands in for it). */
  setHidden(id: string, hidden: boolean) {
    const e = this.entries.get(id);
    if (!e) return;
    e.hidden = hidden;
    if (e.bucket) this.writeSlot(e.bucket, e.bucket.ids.indexOf(id), hidden ? null : e.p);
    if (e.marker) e.marker.visible = !hidden && this.showMarkers;
  }

  /** Build mode shows the spawn and NPC markers, and the binding stones' circles. */
  setMarkers(on: boolean) {
    this.showMarkers = on;
    for (const e of this.entries.values()) if (e.marker) e.marker.visible = on && !e.hidden;
    for (const r of this.rings.values()) r.visible = on;
  }

  /** A spawn's or NPC's marker (for its name in build mode), or null. */
  markerOf(id: string): THREE.Object3D | null {
    return this.entries.get(id)?.marker ?? null;
  }

  /** Colliders for walking (world units), every placement's. */
  colliders(): Collider[] {
    const out: Collider[] = [];
    for (const e of this.entries.values()) if (!e.hidden) for (const c of e.cols) out.push(scaleCollider(c));
    return out;
  }

  /** The placement under a ray (models, and markers while they show), or null. */
  pick(raycaster: THREE.Raycaster): string | null {
    const targets: THREE.Object3D[] = [];
    for (const b of this.buckets.values()) if (b.ids.length) targets.push(...b.meshes);
    for (const e of this.entries.values()) if (e.marker && e.marker.visible) targets.push(e.marker);
    const hits = raycaster.intersectObjects(targets, true);
    for (const hit of hits) {
      const b = hit.object.userData.bucket as Bucket | undefined;
      if (b && hit.instanceId !== undefined) {
        const id = b.ids[hit.instanceId];
        if (id && !this.entries.get(id)?.hidden) return id;
        continue;
      }
      const id = hit.object.userData.placementId as string | undefined;
      if (id) return id;
    }
    return null;
  }

  /**
   * What a placed model is made of, for smashing it (smash-fx.ts): its parts (geometry, material,
   * place in the model) and the placement's own matrix, in this group's metres. Null for a marker.
   */
  pieces(id: string): { parts: { geo: THREE.BufferGeometry; mat: THREE.Material | THREE.Material[]; local: THREE.Matrix4 }[]; matrix: THREE.Matrix4; box: THREE.Box3 } | null {
    const e = this.entries.get(id);
    if (!e?.bucket || e.hidden) return null;
    const [sx, sy, sz] = sizeOf(e.p);
    const matrix = new THREE.Matrix4().compose(new THREE.Vector3(e.p.x, e.p.y, e.p.z), new THREE.Quaternion().setFromAxisAngle(Y, e.p.rot), new THREE.Vector3(sx, sy, sz));
    return { parts: e.bucket.parts, matrix, box: e.bucket.box.clone().applyMatrix4(matrix) };
  }

  /** Draws a placement nudged by (dx, dz) metres and tipped by `tilt` radians (a smash hit); jiggle(id, 0, 0, 0) puts it back. */
  jiggle(id: string, dx: number, dz: number, tilt: number) {
    const e = this.entries.get(id);
    if (!e?.bucket || e.hidden) return;
    this.writeSlot(e.bucket, e.bucket.ids.indexOf(id), { ...e.p, x: e.p.x + dx, z: e.p.z + dz }, tilt);
  }

  /** How many draw calls the placed models take (one per part of each kind present). */
  drawCalls(): number {
    let n = 0;
    for (const b of this.buckets.values()) if (b.ids.length) n += b.meshes.length;
    return n;
  }

  // ---------------------------------------------------------------- ghosts

  /** A see-through copy of an asset for the cursor to carry (green: may place; red: may not). */
  ghost(asset: string, data: Record<string, any> = {}): THREE.Object3D {
    let g: THREE.Object3D;
    if (isModel(asset)) {
      g = this.prepare(asset)?.clone(true) || new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0));
    } else {
      g = this.markerFor({ id: 'ghost', asset, x: 0, y: 0, z: 0, rot: 0, scale: 1, data });
    }
    const mat = new THREE.MeshBasicMaterial({ color: '#7CFF8A', transparent: true, opacity: 0.45, depthWrite: false });
    g.traverse((o: any) => {
      if (o.isMesh) {
        o.material = mat;
        o.castShadow = false;
        o.raycast = () => {};
      }
    });
    g.userData.ghostMat = mat;
    g.renderOrder = 10;
    return g;
  }

  /** Lays a ghost (or anything) where a placement would stand. */
  pose(o: THREE.Object3D, p: { x: number; y: number; z: number; rot: number; scale: number; data?: Record<string, any> }) {
    o.position.set(p.x, p.y, p.z);
    o.rotation.set(0, p.rot, 0);
    const [sx, sy, sz] = sizeOf(p);
    o.scale.set(sx, sy, sz);
  }

  /** A spawn's ring follows its radius. */
  poseMarker(o: THREE.Object3D, p: Placement) {
    this.pose(o, { ...p, scale: 1, data: {} });
    const ring = o.getObjectByName('ring');
    const r = Math.max(0.8, Number(p.data?.radius) || 0);
    if (ring) ring.scale.set(r, 1, r);
  }

  /** The extent of an asset's model (metres, its own frame), or null. */
  extent(asset: string): THREE.Box3 | null {
    if (!isModel(asset)) return null;
    this.prepare(asset);
    return this.shapes.get(asset) ?? null;
  }

  // ---------------------------------------------------------------- internals

  /** The piece's template, at the origin, with its materials prepared once (surface textures). */
  private prepare(asset: string): THREE.Object3D | null {
    let tpl = this.prepared.get(asset);
    if (tpl) return tpl;
    const src = this.source.template(asset);
    if (!src) return null;
    // the piece's own transform relative to its parent is part of its shape (a quantized GLB keeps
    // each mesh's dequantisation there; world-dressing.ts merges the same way)
    src.updateWorldMatrix(true, false);
    const local = new THREE.Matrix4();
    if (src.parent) local.copy(src.parent.matrixWorld).invert();
    local.multiply(src.matrixWorld);
    const inner = src.clone(true);
    local.decompose(inner.position, inner.quaternion, inner.scale);
    tpl = new THREE.Group();
    tpl.add(inner);
    const family: Family = asset.startsWith('P_') ? 'props' : 'kit';
    tpl.traverse((o: any) => {
      if (!o.isMesh) return;
      const swap = (m: THREE.Material) => {
        const key = `${family}:${m.name || m.uuid}`;
        let mm = this.mats.get(key);
        if (!mm) {
          mm = (m as THREE.MeshStandardMaterial).clone();
          const s = surfaceFor(family, mm.name || '');
          if (s) void applySurface(mm, s);
          const em = (mm as any).emissive as THREE.Color | undefined;
          if (em && em.r + em.g + em.b > 0.01) this.source.addGlow?.(mm);
          this.mats.set(key, mm);
        }
        return mm;
      };
      o.material = Array.isArray(o.material) ? o.material.map(swap) : swap(o.material);
    });
    tpl.updateMatrixWorld(true);
    this.shapes.set(asset, new THREE.Box3().setFromObject(tpl));
    this.prepared.set(asset, tpl);
    return tpl;
  }

  private bucketFor(asset: string): Bucket | null {
    let b = this.buckets.get(asset);
    if (b) return b;
    const tpl = this.prepare(asset);
    if (!tpl) return null;
    const parts: Part[] = [];
    tpl.traverse((o: any) => {
      if (o.isMesh) parts.push({ geo: o.geometry, mat: o.material, local: o.matrixWorld.clone() });
    });
    b = { asset, parts, meshes: [], ids: [], cap: 0, box: this.shapes.get(asset)! };
    this.buckets.set(asset, b);
    return b;
  }

  // Room for every copy: a bigger InstancedMesh per part when the bucket fills (the matrices copied).
  private grow(b: Bucket) {
    if (b.ids.length <= b.cap) {
      for (const m of b.meshes) m.count = b.ids.length;
      return;
    }
    const cap = Math.max(8, b.cap * 2, b.ids.length);
    const fresh = b.parts.map((part, i) => {
      const im = new THREE.InstancedMesh(part.geo, part.mat as any, cap);
      im.castShadow = true;
      im.receiveShadow = true;
      // the copies spread over the whole zone: no culling by the template's small bounds
      im.frustumCulled = false;
      im.userData.bucket = b;
      im.name = `Placed_${b.asset}_${i}`;
      const old = b.meshes[i];
      if (old) {
        for (let k = 0; k < b.cap; k++) {
          old.getMatrixAt(k, _m);
          im.setMatrixAt(k, _m);
        }
        this.group.remove(old);
        old.dispose();
      }
      im.count = b.ids.length;
      this.group.add(im);
      return im;
    });
    b.meshes = fresh;
    b.cap = cap;
  }

  private writeSlot(b: Bucket, slot: number, p: Placement | null, tilt = 0) {
    if (slot < 0) return;
    if (p) {
      const [sx, sy, sz] = sizeOf(p);
      _q.setFromAxisAngle(Y, p.rot);
      if (tilt) _q.multiply(_qt.setFromAxisAngle(X, tilt));
      _m.compose(_v.set(p.x, p.y, p.z), _q, _s.set(sx, sy, sz));
    }
    b.parts.forEach((part, i) => {
      const im = b.meshes[i];
      if (!im) return;
      im.setMatrixAt(slot, p ? new THREE.Matrix4().multiplyMatrices(_m, part.local) : ZERO);
      im.instanceMatrix.needsUpdate = true;
      stale(im);
    });
  }

  private collidersFor(p: Placement): Collider[] {
    const box = this.shapes.get(p.asset);
    if (!box) return [];
    const [sx, , sz] = sizeOf(p);
    const c = colliderShape(p.asset, box);
    const cs = Math.cos(p.rot), sn = Math.sin(p.rot);
    // local (lx, lz) to world: three.js turns +x toward -z for a positive yaw
    const at = (lx: number, lz: number) => ({ x: p.x + lx * sx * cs + lz * sz * sn, z: p.z - lx * sx * sn + lz * sz * cs });
    switch (c.kind) {
      case 'none':
        return [];
      case 'circle':
        return [{ kind: 'circle', x: p.x, z: p.z, r: c.r * Math.max(sx, sz) }];
      case 'box': {
        const m = at(c.cx, c.cz);
        return [{ kind: 'box', x: m.x, z: m.z, hx: c.hx * sx, hz: c.hz * sz, rot: p.rot }];
      }
      case 'gate': {
        const side = (c.hx - c.gap / 2) / 2;
        const off = c.gap / 2 + side;
        return [-1, 1].map((k) => {
          const m = at(k * off, 0);
          return { kind: 'box' as const, x: m.x, z: m.z, hx: side * sx, hz: c.hz * sz, rot: p.rot };
        });
      }
    }
  }

  // A binding stone shows its no-build circle in build mode (BaconWorld.Building.binding_radius/0).
  private syncRing(p: Placement) {
    if (p.asset !== 'P_Waystone') return;
    let ring = this.rings.get(p.id);
    if (!ring) {
      ring = new THREE.Mesh(new THREE.RingGeometry(BINDING_RADIUS_M - 0.6, BINDING_RADIUS_M, 128).rotateX(-Math.PI / 2), MARKER_STONE);
      ring.name = 'BindingRing';
      ring.visible = this.showMarkers;
      this.rings.set(p.id, ring);
      this.group.add(ring);
    }
    ring.position.set(p.x, p.y + 0.15, p.z);
  }

  // A creature spawn: a red ring on the ground (its radius) and a post; an NPC: a blue post.
  private markerFor(p: Placement): THREE.Object3D {
    const g = new THREE.Group();
    const mob = p.asset.startsWith('mob:');
    const mat = mob ? MARKER_MOB : MARKER_NPC;
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 2.2, 8).translate(0, 1.1, 0), mat);
    const head = new THREE.Mesh(mob ? new THREE.ConeGeometry(0.35, 0.5, 4).rotateX(Math.PI).translate(0, 2.6, 0) : new THREE.SphereGeometry(0.28, 10, 8).translate(0, 2.5, 0), mat);
    const arrow = new THREE.Mesh(new THREE.ConeGeometry(0.18, 0.5, 6).rotateX(Math.PI / 2).translate(0, 0.15, 0.55), mat);
    g.add(post, head, arrow);
    if (mob) {
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.94, 1.0, 48).rotateX(-Math.PI / 2).translate(0, 0.06, 0), mat);
      ring.name = 'ring';
      g.add(ring);
    }
    // an easy thing to click: a fat invisible post
    const pick = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.5, 3, 8).translate(0, 1.5, 0), MARKER_PICK);
    g.add(pick);
    g.traverse((o) => (o.userData.placementId = p.id));
    g.visible = this.showMarkers;
    return g;
  }
}

/** The no-build circle round a binding stone (m): BaconWorld.Building's. */
export const BINDING_RADIUS_M = 100;

function scaleCollider(c: Collider): Collider {
  if (c.kind === 'circle') return { ...c, x: c.x * U, z: c.z * U, r: c.r * U };
  if (c.kind === 'box') return { ...c, x: c.x * U, z: c.z * U, hx: c.hx * U, hz: c.hz * U };
  return { ...c, x: c.x * U, z: c.z * U, rx: c.rx * U, rz: c.rz * U };
}
