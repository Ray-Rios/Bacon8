// What players put in the world in build mode (BaconWorld.Building, 2026-10-28): props and
// building pieces drawn from the village's own GLBs (P_<Id>, K_<Id>, the templates
// world-dressing.ts loaded), with the colliders they need, plus markers for the creature spawns
// and NPCs, which only show in build mode (the creatures and the people themselves are
// mobs-view.ts's and npcs-view.ts's).
//
// Everything here is in metres: the group sits in the village's group, which is scaled by
// UNITS_PER_METRE. Copies share their template's geometry and one prepared material per
// template material (surface textures applied once), so a hundred barrels cost a hundred draw
// calls of one material, not a hundred materials.
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
}

interface Entry {
  p: Placement;
  obj: THREE.Object3D | null;
  marker: THREE.Object3D | null;
  cols: Collider[];
}

// A template's extent (metres, its own frame), measured once.
interface Shape {
  box: THREE.Box3;
}

/** Whether a piece blocks walking, and how (pure; unit-tested). */
export function colliderShape(asset: string, box: { min: { x: number; y: number; z: number }; max: { x: number; y: number; z: number } }):
  | { kind: 'none' }
  | { kind: 'circle'; r: number }
  | { kind: 'box'; hx: number; hz: number; cx: number; cz: number }
  | { kind: 'gate'; hx: number; hz: number; gap: number } {
  const name = asset.replace(/^[PK]_/, '');
  const h = box.max.y - box.min.y;
  const sx = box.max.x - box.min.x;
  const sz = box.max.z - box.min.z;
  // walked on, over or under: floors, foundations, stairs, roofs, rugs, plates, ladders, doors left open
  if (/^(Floor|Foundation|Stairs|Roof|Ladder|Door|Rug|PressurePlate|GrassTuft|Mushrooms|Shutters|Window)/.test(name)) return { kind: 'none' };
  if (h < 0.35 || Math.max(sx, sz) < 0.2) return { kind: 'none' };
  // a wall with a way through it: two sides, the middle open
  if (/(Door|Gateway|Gate)$/.test(name) || name === 'Arch_Stone' || name === 'Fence_Gate') return { kind: 'gate', hx: sx / 2, hz: Math.max(sz / 2, 0.12), gap: Math.min(1.3, sx * 0.45) };
  // trees: the trunk, not the crown
  if (/^Tree/.test(name)) return { kind: 'circle', r: 0.35 };
  if (/^(Bush|BushFlowers)$/.test(name)) return { kind: 'circle', r: Math.min(sx, sz) * 0.35 };
  // round things
  if (/^(Barrel|BarrelWater|Rock|Boulder|Stump|Well|Cauldron|ClayPot|Amphora|Brazier|LampPost|Statue|Haystack|Bucket|Campfire|Waystone|Pillar)/.test(name)) {
    return { kind: 'circle', r: Math.max(0.15, Math.min(sx, sz) * 0.5) };
  }
  return { kind: 'box', hx: sx / 2, hz: sz / 2, cx: (box.max.x + box.min.x) / 2, cz: (box.max.z + box.min.z) / 2 };
}

const MARKER_MOB = new THREE.MeshBasicMaterial({ color: '#E2533A', transparent: true, opacity: 0.55, depthWrite: false });
const MARKER_NPC = new THREE.MeshBasicMaterial({ color: '#8FD3FF', transparent: true, opacity: 0.55, depthWrite: false });
const MARKER_PICK = new THREE.MeshBasicMaterial({ visible: false });

export class PlacedView {
  /** In the village's group (metres). */
  readonly group = new THREE.Group();
  private entries = new Map<string, Entry>();
  private prepared = new Map<string, THREE.Object3D>();
  private shapes = new Map<string, Shape>();
  private mats = new Map<string, THREE.Material>();
  private showMarkers = false;
  /** The ground under (x, z), metres (terrain.ts; 0 while flat). */
  ground: (x: number, z: number) => number = () => 0;
  /** Colliders changed: the hook rebuilds the walking ones. */
  onColliders: (() => void) | null = null;

  constructor(private source: TemplateSource) {
    this.group.name = 'Placed';
  }

  // ---------------------------------------------------------------- the list

  async setAll(list: Placement[]) {
    const keep = new Set(list.map((p) => p.id));
    for (const id of [...this.entries.keys()]) if (!keep.has(id)) this.remove(id);
    await this.source.ready();
    for (const p of list) this.put(p);
    this.onColliders?.();
  }

  /** A placement, new or changed (the server's word). */
  put(p: Placement) {
    let e = this.entries.get(p.id);
    if (!e) {
      e = { p, obj: null, marker: null, cols: [] };
      this.entries.set(p.id, e);
    }
    const assetChanged = e.p.asset !== p.asset;
    e.p = p;
    if (assetChanged && e.obj) {
      this.group.remove(e.obj);
      e.obj = null;
    }
    if (isModel(p.asset)) {
      if (!e.obj) {
        const o = this.instance(p.asset);
        if (o) {
          o.userData.placementId = p.id;
          o.traverse((c) => (c.userData.placementId = p.id));
          e.obj = o;
          this.group.add(o);
        }
      }
      if (e.obj) this.pose(e.obj, p);
      e.cols = this.collidersFor(p);
    } else {
      if (!e.marker) {
        e.marker = this.markerFor(p);
        this.group.add(e.marker);
      }
      this.poseMarker(e.marker, p);
      e.marker.visible = this.showMarkers;
    }
    this.onColliders?.();
  }

  remove(id: string) {
    const e = this.entries.get(id);
    if (!e) return;
    if (e.obj) this.group.remove(e.obj);
    if (e.marker) this.group.remove(e.marker);
    this.entries.delete(id);
    this.onColliders?.();
  }

  get(id: string): Placement | null {
    return this.entries.get(id)?.p ?? null;
  }

  all(): Placement[] {
    return [...this.entries.values()].map((e) => e.p);
  }

  /** A spawn's or NPC's marker (for its name in build mode), or null. */
  markerOf(id: string): THREE.Object3D | null {
    return this.entries.get(id)?.marker ?? null;
  }

  /** Hides one while it is held (the ghost stands in for it). */
  setHidden(id: string, hidden: boolean) {
    const e = this.entries.get(id);
    if (!e) return;
    if (e.obj) e.obj.visible = !hidden;
    if (e.marker) e.marker.visible = !hidden && this.showMarkers;
  }

  /** Build mode shows the spawn and NPC markers. */
  setMarkers(on: boolean) {
    this.showMarkers = on;
    for (const e of this.entries.values()) if (e.marker) e.marker.visible = on;
  }

  /** Colliders for walking (world units), every placement's. */
  colliders(): Collider[] {
    const out: Collider[] = [];
    for (const e of this.entries.values()) for (const c of e.cols) out.push(scaleCollider(c));
    return out;
  }

  /** The placement under a ray (models, and markers while they show), or null. */
  pick(raycaster: THREE.Raycaster): string | null {
    const targets: THREE.Object3D[] = [];
    for (const e of this.entries.values()) {
      if (e.obj && e.obj.visible) targets.push(e.obj);
      if (e.marker && e.marker.visible) targets.push(e.marker);
    }
    const hit = raycaster.intersectObjects(targets, true)[0];
    return (hit?.object.userData.placementId as string) || null;
  }

  // ---------------------------------------------------------------- ghosts

  /** A see-through copy of an asset for the cursor to carry (green: may place; red: may not). */
  ghost(asset: string, data: Record<string, any> = {}): THREE.Object3D {
    let g: THREE.Object3D;
    if (isModel(asset)) {
      g = this.instance(asset) || new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0));
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
  pose(o: THREE.Object3D, p: { x: number; y: number; z: number; rot: number; scale: number }) {
    o.position.set(p.x, p.y, p.z);
    o.rotation.set(0, p.rot, 0);
    o.scale.setScalar(p.scale || 1);
  }

  /** A spawn's ring follows its radius. */
  poseMarker(o: THREE.Object3D, p: Placement) {
    this.pose(o, { ...p, scale: 1 });
    const ring = o.getObjectByName('ring');
    const r = Math.max(0.8, Number(p.data?.radius) || 0);
    if (ring) ring.scale.set(r, 1, r);
  }

  /** The extent of an asset's model (metres, its own frame), or null. */
  extent(asset: string): THREE.Box3 | null {
    if (!isModel(asset)) return null;
    this.instance(asset);
    return this.shapes.get(asset)?.box ?? null;
  }

  // ---------------------------------------------------------------- internals

  private instance(asset: string): THREE.Object3D | null {
    let tpl = this.prepared.get(asset);
    if (!tpl) {
      const src = this.source.template(asset);
      if (!src) return null;
      // the piece's own transform relative to its parent is part of its shape (a quantized GLB
      // keeps each mesh's dequantisation there; world-dressing.ts merges the same way)
      src.updateWorldMatrix(true, false);
      const local = new THREE.Matrix4();
      if (src.parent) local.copy(src.parent.matrixWorld).invert();
      local.multiply(src.matrixWorld);
      const inner = src.clone(true);
      local.decompose(inner.position, inner.quaternion, inner.scale);
      tpl = new THREE.Group();
      tpl.add(inner);
      const family: Family = asset.startsWith('K_') ? 'kit' : 'props';
      tpl.traverse((o: any) => {
        if (!o.isMesh) return;
        o.castShadow = true;
        o.receiveShadow = true;
        const swap = (m: THREE.Material) => {
          const key = `${family}:${m.name || m.uuid}`;
          let mm = this.mats.get(key);
          if (!mm) {
            mm = (m as THREE.MeshStandardMaterial).clone();
            const s = surfaceFor(family, mm.name || '');
            if (s) void applySurface(mm, s);
            this.mats.set(key, mm);
          }
          return mm;
        };
        o.material = Array.isArray(o.material) ? o.material.map(swap) : swap(o.material);
      });
      tpl.updateMatrixWorld(true);
      const box = new THREE.Box3().setFromObject(tpl);
      this.shapes.set(asset, { box });
      this.prepared.set(asset, tpl);
    }
    return tpl.clone(true);
  }

  private collidersFor(p: Placement): Collider[] {
    const shape = this.shapes.get(p.asset);
    if (!shape) return [];
    const s = p.scale || 1;
    const c = colliderShape(p.asset, shape.box);
    const cs = Math.cos(p.rot), sn = Math.sin(p.rot);
    // local (lx, lz) to world: three.js turns +x toward -z for a positive yaw
    const at = (lx: number, lz: number) => ({ x: p.x + (lx * cs + lz * sn) * s, z: p.z + (-lx * sn + lz * cs) * s });
    switch (c.kind) {
      case 'none':
        return [];
      case 'circle':
        return [{ kind: 'circle', x: p.x, z: p.z, r: c.r * s }];
      case 'box': {
        const m = at(c.cx, c.cz);
        return [{ kind: 'box', x: m.x, z: m.z, hx: c.hx * s, hz: c.hz * s, rot: p.rot }];
      }
      case 'gate': {
        const side = (c.hx - c.gap / 2) / 2;
        const off = c.gap / 2 + side;
        return [-1, 1].map((k) => {
          const m = at(k * off, 0);
          return { kind: 'box' as const, x: m.x, z: m.z, hx: side * s, hz: c.hz * s, rot: p.rot };
        });
      }
    }
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

/** True for a placement drawn with a model (a prop or building piece), not a spawn or an NPC. */
export function isModel(asset: string): boolean {
  return /^[PK]_/.test(asset);
}

function scaleCollider(c: Collider): Collider {
  if (c.kind === 'circle') return { ...c, x: c.x * U, z: c.z * U, r: c.r * U };
  if (c.kind === 'box') return { ...c, x: c.x * U, z: c.z * U, hx: c.hx * U, hz: c.hz * U };
  return { ...c, x: c.x * U, z: c.z * U, rx: c.rx * U, rz: c.rz * U };
}
