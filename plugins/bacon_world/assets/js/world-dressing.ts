// Bacon World's lobby village: grass, a cobbled plaza with a well, market stalls,
// houses built from the B8 building kit, trees, lamps, a camp, a training yard and a
// farm patch, all from the B8 props and kit GLBs. Static pieces are merged into one
// mesh per material (a few dozen draw calls for the whole village).
//
// Files (models volume): /models/World/B8_Props.glb, /models/World/B8_BuildKit.glb
// (one node per piece: P_<Id>, K_<Id>; Y-up, metres, origin at the bottom centre, front +Z).
//
// The layout is in metres; the group is scaled by UNITS_PER_METRE like the characters.
// colliders() gives circles and boxes (world units) the client keeps players out of.
import * as THREE from '../../../../assets/js/vendor/three';
import { GLTFLoader, MeshoptDecoder, RoomEnvironment } from '../../../../assets/js/vendor/three-loaders';
import { UNITS_PER_METRE } from './controls-math';
import { modelUrl } from './asset-url';
import { Family, Surface, applySurface, surfaceFor, surfacesEnabled } from './surface-textures';

export const WORLD_BASE = '/models/World';

export type Collider =
  | { kind: 'circle'; x: number; z: number; r: number }
  | { kind: 'box'; x: number; z: number; hx: number; hz: number; rot: number };

type Placement = { name: string; m: THREE.Matrix4 };

const D2R = Math.PI / 180;

function rng(seed: number) {
  let t = seed >>> 0;
  return () => {
    t += 0x6d2b79f5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

/** Rotation that turns a piece's front (+Z) toward (tx, tz) from (x, z), in degrees. */
function face(x: number, z: number, tx = 0, tz = 0) {
  return Math.atan2(tx - x, tz - z) / D2R;
}

export class WorldDressing {
  readonly group = new THREE.Group();
  private loader: GLTFLoader;
  private placements: Placement[] = [];
  private cols: Collider[] = [];
  private templates = new Map<string, THREE.Object3D>();
  private glow: THREE.MeshStandardMaterial[] = [];
  private hemi: THREE.HemisphereLight;
  private env: THREE.Texture | null = null;
  private built: Promise<void> | null = null;
  private campsDone = false;

  constructor(private scene: THREE.Scene, private renderer: THREE.WebGLRenderer) {
    this.loader = new GLTFLoader();
    this.loader.setMeshoptDecoder(MeshoptDecoder);
    this.group.name = 'WorldDressing';
    this.group.scale.setScalar(UNITS_PER_METRE);
    this.hemi = new THREE.HemisphereLight('#CFE3FF', '#4A5A3A', 0.6);
  }

  private load(url: string): Promise<THREE.Object3D | null> {
    return new Promise((resolve) => this.loader.load(modelUrl(url), (g: any) => resolve(g.scene), undefined, (err) => {
      console.warn('[world] could not load', url, err);
      resolve(null);
    }));
  }

  /** Builds the village into `parent` (the hook's world group). Safe to call more than once. */
  build(parent: THREE.Object3D): Promise<void> {
    if (!this.built) this.built = this.buildOnce(parent);
    return this.built;
  }

  private async buildOnce(parent: THREE.Object3D): Promise<void> {
    parent.add(this.group);
    this.scene.add(this.hemi);
    this.group.add(this.ground());
    const [props, kit] = await Promise.all([this.load(`${WORLD_BASE}/B8_Props.glb`), this.load(`${WORLD_BASE}/B8_BuildKit.glb`)]);
    for (const [root, family] of [[props, 'props'], [kit, 'kit']] as Array<[THREE.Object3D | null, Family]>) {
      root?.traverse((o: any) => {
        if (/^[PK]_/.test(o.name) && !this.templates.has(o.name)) this.templates.set(o.name, o);
        // which texture table the merged material uses (props and kit share names)
        if (o.isMesh) for (const m of Array.isArray(o.material) ? o.material : [o.material]) m.userData.b8family = family;
      });
    }
    if (!this.templates.size) return;
    // a plain stone plinth under each house (cheaper than four foundation pieces)
    const stone = this.firstMaterial('K_Foundation_Stone') || this.firstMaterial('K_Wall_Stone');
    if (stone) {
      const g = new THREE.BoxGeometry(6.4, 0.5, 6.4).translate(0, 0.05, 0);
      this.templates.set('X_Plinth', new THREE.Mesh(g, stone));
    }
    this.layout();
    this.merge();
    if (!this.env) {
      const pm = new THREE.PMREMGenerator(this.renderer);
      this.env = pm.fromScene(new RoomEnvironment(), 0.04).texture;
      pm.dispose();
    }
    this.scene.environment = this.env;
  }

  private firstMaterial(name: string): THREE.Material | null {
    let found: THREE.Material | null = null;
    this.templates.get(name)?.traverse((o: any) => {
      if (!found && o.isMesh) found = Array.isArray(o.material) ? o.material[0] : o.material;
    });
    return found;
  }

  colliders(): Collider[] {
    const U = UNITS_PER_METRE;
    return this.cols.map((c) => (c.kind === 'circle' ? { ...c, x: c.x * U, z: c.z * U, r: c.r * U } : { ...c, x: c.x * U, z: c.z * U, hx: c.hx * U, hz: c.hz * U }));
  }

  /** Keeps a point (world units) of radius r out of the colliders; returns the corrected x/z. */
  static pushOut(cols: Collider[], x: number, z: number, r: number): { x: number; z: number } {
    for (let pass = 0; pass < 2; pass++) {
      for (const c of cols) {
        if (c.kind === 'circle') {
          const dx = x - c.x, dz = z - c.z;
          const min = c.r + r;
          const d2 = dx * dx + dz * dz;
          if (d2 < min * min) {
            const d = Math.sqrt(d2) || 1e-6;
            x = c.x + (dx / d) * min;
            z = c.z + (dz / d) * min;
          }
        } else {
          // into the box's frame (three.js rotation about +Y by rot), push out along
          // the shallower axis, and back
          const cs = Math.cos(c.rot), sn = Math.sin(c.rot);
          const ux = (x - c.x) * cs - (z - c.z) * sn;
          const uz = (x - c.x) * sn + (z - c.z) * cs;
          const ex = c.hx + r, ez = c.hz + r;
          if (Math.abs(ux) < ex && Math.abs(uz) < ez) {
            const px = ex - Math.abs(ux), pz = ez - Math.abs(uz);
            let nx = ux, nz = uz;
            if (px < pz) nx = Math.sign(ux || 1) * ex;
            else nz = Math.sign(uz || 1) * ez;
            x = c.x + nx * cs + nz * sn;
            z = c.z - nx * sn + nz * cs;
          }
        }
      }
    }
    return { x, z };
  }

  /** Per frame: fog and fill light follow the sky; lamps glow at night. */
  tick(daylight: number) {
    const bg = this.scene.background;
    if (bg instanceof THREE.Color) {
      if (!this.scene.fog) this.scene.fog = new THREE.Fog(bg.clone(), 70 * UNITS_PER_METRE, 190 * UNITS_PER_METRE);
      (this.scene.fog as THREE.Fog).color.copy(bg);
      this.hemi.color.copy(bg).lerp(new THREE.Color('#FFFFFF'), 0.55);
    }
    const d = Math.min(1, Math.max(0, daylight));
    this.hemi.intensity = 0.25 + 0.75 * d;
    (this.scene as any).environmentIntensity = 0.12 + 0.35 * d;
    for (const m of this.glow) m.emissiveIntensity = (m.userData.base || 1) * (0.6 + 1.6 * (1 - d));
  }

  dispose() {
    this.group.parent?.remove(this.group);
    this.scene.remove(this.hemi);
    if (this.scene.environment === this.env) this.scene.environment = null;
    this.scene.fog = null;
    this.group.traverse((o: any) => {
      o.geometry?.dispose?.();
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m: any) => { m.map?.dispose?.(); m.dispose?.(); });
    });
    this.env?.dispose();
    this.env = null;
  }

  // ---------------------------------------------------------------- placing

  private put(name: string, x: number, z: number, rotDeg = 0, y = 0, sx = 1, sy = 1, sz = 1) {
    const full = name.startsWith('P_') || name.startsWith('K_') ? name : `P_${name}`;
    if (!this.templates.has(full)) return;
    const m = new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), rotDeg * D2R), new THREE.Vector3(sx, sy, sz));
    this.placements.push({ name: full, m });
  }

  private prop(name: string, x: number, z: number, rotDeg = 0, r = 0.4, y = 0, s = 1) {
    this.put(name, x, z, rotDeg, y, s, s, s);
    if (r > 0) this.cols.push({ kind: 'circle', x, z, r: r * s });
  }

  private box(x: number, z: number, hx: number, hz: number, rotDeg: number) {
    this.cols.push({ kind: 'box', x, z, hx, hz, rot: rotDeg * D2R });
  }

  /** A 2 x 2 cell house (6 x 6 m) facing +Z before `rot`, centred at (cx, cz). */
  private house(cx: number, cz: number, rot: number, o: { wall: 'Wood' | 'Stone'; roof: 'Thatch' | 'Tile' | 'Shingle'; chimney?: boolean; seed?: number }) {
    const R = new THREE.Matrix4().makeRotationY(rot * D2R);
    const T = new THREE.Matrix4().makeTranslation(cx, 0, cz);
    const base = T.multiply(R);
    const at = (name: string, x: number, y: number, z: number, r = 0, sx = 1) => {
      if (!this.templates.has(name)) return;
      const local = new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), r * D2R), new THREE.Vector3(sx, 1, 1));
      this.placements.push({ name, m: base.clone().multiply(local) });
    };
    const fl = 0.3; // floor level above the ground
    const H = 3;
    const w = o.wall;
    at('X_Plinth', 0, 0, 0);
    // front (+Z): window, door; back: window, plain; sides: window, plain
    at(`K_Wall_${w}_Window`, -1.5, fl, 3);
    at(`K_Wall_${w}_Door`, 1.5, fl, 3);
    at('K_Door_Wood', 0.9, fl, 3.0);
    at('K_Shutters_Wood', -1.5, fl, 3.0);
    at(`K_Wall_${w}_Window`, -1.5, fl, -3, 180);
    at(`K_Wall_${w}`, 1.5, fl, -3, 180);
    at(`K_Wall_${w}_Window`, 3, fl, -1.5, 90);
    at(`K_Wall_${w}`, 3, fl, 1.5, 90);
    at(`K_Wall_${w}`, -3, fl, -1.5, -90);
    at(`K_Wall_${w}_Window`, -3, fl, 1.5, -90);
    if (w === 'Wood') for (const x of [-3, 3]) for (const z of [-3, 3]) at('K_Pillar_Wood', x, fl, z);
    // roof: two slopes meeting over z = 0, gables at both ends
    const roof = `K_Roof_${o.roof === 'Shingle' ? 'Tile' : o.roof}`;
    for (const x of [-1.5, 1.5]) {
      at(roof, x, fl + H, 1.5);
      at(roof, x, fl + H, -1.5, 180);
      at('K_Roof_Ridge', x, fl + H + 1.5, 0);
    }
    at(`K_Wall_${w}_Gable`, 3, fl + H, 0, 90, 2);
    at(`K_Wall_${w}_Gable`, -3, fl + H, 0, -90, 2);
    if (o.chimney) at('K_Chimney_Stone', 2.2, fl, -1.2);
    // a step and a lantern by the door
    const step = new THREE.Vector3(1.5, 0, 3.6).applyMatrix4(base);
    this.put('P_LanternProp', step.x, step.z, rot, 0);
    this.box(cx, cz, 3.25, 3.25, rot);
  }

  // ---------------------------------------------------------------- the village

  private layout() {
    const r = rng(20261021);
    // plaza: the well (north of the spawn), benches, lamps
    this.prop('Well', 0, -9, 0, 1.0);
    for (const a of [-35, 35]) {
      const x = Math.sin(a * D2R) * 5.2, z = -9 + Math.cos(a * D2R) * 5.2;
      this.prop('Bench', x, z, face(x, z, 0, -9), 0.6);
    }
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2 + Math.PI / 8;
      this.prop('LampPost', Math.sin(a) * 13, Math.cos(a) * 13, (-a / D2R) + 90, 0.25);
    }
    this.prop('Signpost', 3.2, 4.5, 20, 0.3);
    for (const x of [-4.5, 4.5]) this.prop('Banner', x, 10.5, 180, 0.2);

    // market: stalls in an arc to the north-east and north-west, goods around them
    const stalls: Array<[number, number]> = [[-14, -6], [-11, -14], [11, -14], [14, -6]];
    for (const [x, z] of stalls) {
      const rot = face(x, z);
      this.put('P_MarketStall', x, z, rot);
      this.box(x, z, 1.2, 0.6, rot);
      const side = new THREE.Vector3(1.6, 0, -0.3).applyAxisAngle(new THREE.Vector3(0, 1, 0), rot * D2R);
      this.prop(r() < 0.5 ? 'CrateStack' : 'Barrel', x + side.x, z + side.z, rot + r() * 40, 0.7);
      this.prop(r() < 0.5 ? 'SackPile' : 'Basket', x - side.x, z - side.z, rot - r() * 40, 0.5);
    }
    this.prop('BarrelWater', -9, -1, 30, 0.4);
    this.prop('Crate', 9.5, -1.5, 15, 0.45);
    this.prop('CrateSmall', 10.2, -0.6, 40, 0.35);

    // houses on a ring, facing the plaza
    const houses: Array<[number, number, 'Wood' | 'Stone', 'Thatch' | 'Tile' | 'Shingle', boolean]> = [
      [-24, -18, 'Wood', 'Thatch', true], [0, -30, 'Stone', 'Tile', true], [24, -18, 'Wood', 'Tile', false],
      [-30, 6, 'Wood', 'Tile', true], [30, 6, 'Stone', 'Thatch', false], [-20, 26, 'Wood', 'Tile', true], [20, 27, 'Wood', 'Thatch', true],
    ];
    houses.forEach(([x, z, wall, roof, chimney], i) => {
      this.house(x, z, face(x, z), { wall, roof, chimney, seed: i });
      const yard = new THREE.Vector3(-4.2, 0, 1.5).applyAxisAngle(new THREE.Vector3(0, 1, 0), face(x, z) * D2R);
      this.prop(i % 2 ? 'Woodpile' : 'Barrel', x + yard.x, z + yard.z, face(x, z) + 90, 0.6);
    });

    // camp (east): fire, logs to sit on, a tent and a bedroll
    this.prop('Campfire', 22, -2, 0, 0.6);
    this.prop('Log', 20, -2, 90, 0.5);
    this.prop('Log', 24.2, -1, 75, 0.5);
    this.prop('Stump', 22.5, 0.3, 0, 0.35);
    this.prop('Tent', 25, -6.5, -30, 0);
    this.box(25, -6.5, 1.2, 1.2, -30);
    this.prop('Bedroll', 19.8, -5.2, 20, 0);

    // training yard (west): dummies, targets, a rack, a fence line
    this.prop('TrainingDummy', -19, 9, 90, 0.35);
    this.prop('TrainingDummy', -19, 12.5, 90, 0.35);
    this.prop('ArcheryTarget', -25, 14, 90, 0.5);
    this.prop('ArcheryTarget', -25, 9.5, 90, 0.5);
    this.prop('WeaponRack', -16, 15.5, 180, 0.5);
    for (let i = 0; i < 5; i++) this.put('K_Fence_Wood', -21.5 + i * 3, 17.3, 0);
    this.box(-15.5, 17.3, 7.5, 0.15, 0);

    // farm patch (south-west): hay, scarecrow, pumpkins, a barrow
    this.prop('Haystack', -10, 22, 0, 1.0);
    this.prop('Scarecrow', -6, 24, 160, 0.25);
    for (let i = 0; i < 6; i++) this.prop('FoodPumpkin', -4 + (i % 3) * 1.1, 20.5 + Math.floor(i / 3) * 1.1, r() * 360, 0, 0, 1.4);
    this.prop('Wheelbarrow', -12.5, 19.5, 120, 0.6);
    this.prop('SackPile', -8.2, 19.8, 10, 0.5);

    // a little shrine and a statue at the south end of the plaza
    this.prop('Statue', 0, 16, 180, 0.7);
    this.prop('Candelabra', -1.4, 15, 0, 0, 0.0);
    this.prop('Candelabra', 1.4, 15, 0, 0, 0.0);

    // nature: trees and bushes outside the village, rocks here and there
    for (let i = 0; i < 56; i++) {
      const a = r() * Math.PI * 2;
      const d = 40 + r() * 42;
      const x = Math.cos(a) * d, z = Math.sin(a) * d;
      const kind = r() < 0.6 ? 'TreePine' : r() < 0.85 ? 'TreeOak' : 'TreeDead';
      const s = 0.8 + r() * 0.6;
      this.prop(kind, x, z, r() * 360, 0.45, 0, s);
    }
    for (let i = 0; i < 40; i++) {
      const a = r() * Math.PI * 2;
      const d = 18 + r() * 30;
      const x = Math.cos(a) * d, z = Math.sin(a) * d;
      if (Math.hypot(x, z - 26) < 8 || Math.abs(x) < 3 || Math.abs(z) < 3) continue;
      const kind = ['Bush', 'BushFlowers', 'Rock1', 'Rock2', 'GrassTuft', 'GrassTuft', 'Mushrooms'][Math.floor(r() * 7)];
      this.prop(kind, x, z, r() * 360, kind.startsWith('Rock') ? 0.6 : 0, 0, 0.8 + r() * 0.5);
    }
    for (let i = 0; i < 6; i++) {
      const a = r() * Math.PI * 2;
      const x = Math.cos(a) * (50 + r() * 20), z = Math.sin(a) * (50 + r() * 20);
      this.prop('Boulder', x, z, r() * 360, 1.6);
    }
  }

  // ---------------------------------------------------------------- creature camps

  /**
   * Dresses the creature camps the server sent (`fetch_mobs`: world units): a walled
   * graveyard, a ruined chapel, a barrow mound with standing stones. Once, after
   * build(); merged like the village, with colliders.
   */
  async addCamps(camps: Array<{ id: string; theme: string; x: number; z: number; radius: number }>): Promise<void> {
    await this.build(this.group.parent || this.scene);
    if (this.campsDone || !this.templates.size) return;
    this.campsDone = true;
    const U = UNITS_PER_METRE;
    for (const c of camps) {
      let seed = 7;
      for (const ch of c.id) seed = (seed * 31 + ch.charCodeAt(0)) >>> 0;
      const r = rng(seed);
      const cx = c.x / U, cz = c.z / U, R = c.radius / U;
      // the side facing the village, where the way in is
      const toTown = Math.atan2(-cx, -cz);
      if (c.theme === 'graveyard') this.graveyard(cx, cz, R, toTown, r);
      else if (c.theme === 'ruins') this.ruins(cx, cz, R, toTown, r);
      else if (c.theme === 'lair') this.lair(cx, cz, R, toTown, r);
      else this.barrow(cx, cz, R, toTown, r);
    }
    this.merge();
  }

  private patch(cx: number, cz: number, radius: number, color: string, seed: number) {
    const mat = groundMaterial(color, seed, radius / 2, { set: 'earth', scale: 3, antiTile: true }, { roughness: 1, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 });
    const m = new THREE.Mesh(new THREE.CircleGeometry(radius, 40), mat);
    m.rotation.x = -Math.PI / 2;
    m.position.set(cx, 0.012, cz);
    m.receiveShadow = true;
    this.group.add(m);
  }

  // A low stone wall in a ring, broken here and there, open toward `gap`.
  private ring(cx: number, cz: number, radius: number, gap: number, r: () => number, piece = 'K_Fence_Stone', keep = 0.8) {
    const n = Math.max(8, Math.round((2 * Math.PI * radius) / 3));
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      let d = a - gap;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      if (Math.abs(d) < 0.32 || r() > keep) continue;
      const x = cx + Math.sin(a) * radius, z = cz + Math.cos(a) * radius;
      // a piece's length runs along its local X, which a turn of `a` lays along the ring
      const rot = a / D2R;
      this.put(piece, x, z, rot + (r() - 0.5) * 6);
      this.box(x, z, 1.5, 0.25, rot);
    }
  }

  private graveyard(cx: number, cz: number, R: number, toTown: number, r: () => number) {
    this.patch(cx, cz, R + 3.5, '#5B5242', 31);
    this.ring(cx, cz, R + 2.5, toTown, r);
    // rows of headstones, turned to face the way in
    const face0 = toTown / D2R;
    for (let row = -1; row <= 1; row++) {
      for (let k = -2; k <= 2; k++) {
        if (r() < 0.2) continue;
        const lx = k * 2.6 + (r() - 0.5) * 0.6, lz = row * 3.2 + (r() - 0.5) * 0.6;
        const x = cx + lx * Math.cos(toTown) + lz * Math.sin(toTown);
        const z = cz - lx * Math.sin(toTown) + lz * Math.cos(toTown);
        this.prop('Tombstone', x, z, face0 + (r() - 0.5) * 24, 0.3, 0, 0.9 + r() * 0.3);
      }
    }
    for (let i = 0; i < 5; i++) {
      const a = r() * Math.PI * 2, d = r() * R;
      this.prop('Skull', cx + Math.sin(a) * d, cz + Math.cos(a) * d, r() * 360, 0);
    }
    for (let i = 0; i < 4; i++) {
      const a = r() * Math.PI * 2;
      this.prop('TreeDead', cx + Math.sin(a) * (R + 4.5 + r() * 3), cz + Math.cos(a) * (R + 4.5 + r() * 3), r() * 360, 0.45, 0, 0.9 + r() * 0.4);
    }
    const bx = cx + Math.sin(toTown) * (R + 3.4), bz = cz + Math.cos(toTown) * (R + 3.4);
    for (const s of [-1, 1]) this.prop('Brazier', bx + Math.cos(toTown) * 2 * s, bz - Math.sin(toTown) * 2 * s, 0, 0.35);
  }

  private ruins(cx: number, cz: number, R: number, toTown: number, r: () => number) {
    this.patch(cx, cz, R + 3, '#6E685C', 37);
    // a 12 x 9 m chapel outline: walls along the long sides, half walls, pillars at the corners
    const rot = toTown / D2R;
    const at = (lx: number, lz: number) => ({
      x: cx + lx * Math.cos(toTown) + lz * Math.sin(toTown),
      z: cz - lx * Math.sin(toTown) + lz * Math.cos(toTown),
    });
    for (let i = -1; i <= 2; i++) {
      for (const side of [-1, 1]) {
        if (r() < 0.3) continue;
        const p = at(side * 6, -4.5 + i * 3);
        const piece = r() < 0.5 ? 'K_Wall_Stone_Half' : 'K_Wall_Stone';
        this.put(piece, p.x, p.z, rot + 90);
        this.box(p.x, p.z, 0.3, 1.5, rot);
      }
    }
    for (let i = -1; i <= 1; i++) {
      if (r() < 0.35) continue;
      const p = at(i * 3, -6);
      this.put('K_Wall_Stone', p.x, p.z, rot);
      this.box(p.x, p.z, 1.5, 0.3, rot);
    }
    for (const [lx, lz] of [[-6, -6], [6, -6], [-6, 6], [6, 6]]) {
      if (r() < 0.25) continue;
      const p = at(lx, lz);
      this.prop('K_Pillar_Stone', p.x, p.z, rot, 0.35);
    }
    const door = at(0, 6.2);
    this.put('K_Arch_Stone', door.x, door.z, rot);
    for (let i = 0; i < 9; i++) {
      const a = r() * Math.PI * 2, d = R * (0.4 + r() * 0.8);
      this.prop(r() < 0.5 ? 'Rock1' : 'Rock2', cx + Math.sin(a) * d, cz + Math.cos(a) * d, r() * 360, 0.3, 0, 0.5 + r() * 0.5);
    }
    for (let i = 0; i < 4; i++) {
      const a = r() * Math.PI * 2, d = r() * R;
      this.prop('Skull', cx + Math.sin(a) * d, cz + Math.cos(a) * d, r() * 360, 0);
    }
    const st = at(0, -4.2);
    this.prop('Statue', st.x, st.z, rot, 0.6, 0, 0.9);
  }

  // Baconator's lair: scorched ground ringed by crags, open toward town, the hoard
  // heaped behind where the dragon sleeps (the middle stays clear for the fight).
  private lair(cx: number, cz: number, R: number, toTown: number, r: () => number) {
    this.patch(cx, cz, R + 7, '#3A2F27', 47);
    this.patch(cx, cz, R * 0.75, '#2A221D', 53);
    const at = (a: number, d: number) => ({ x: cx + Math.sin(a) * d, z: cz + Math.cos(a) * d });
    // the crags: tall boulders around the far three quarters
    const n = 16;
    for (let i = 0; i < n; i++) {
      const a = toTown + Math.PI * 0.32 + (i / (n - 1)) * Math.PI * 1.36 + (r() - 0.5) * 0.12;
      const d = R + 3.2 + r() * 2.4;
      const p = at(a, d);
      const s = 0.9 + r() * 0.8;
      this.put('Boulder', p.x, p.z, r() * 360, -0.2, s * 1.1, s * (1.4 + r() * 1.2), s);
      this.cols.push({ kind: 'circle', x: p.x, z: p.z, r: 1.7 * s });
    }
    // the hoard, behind the middle
    const away = toTown + Math.PI;
    const h = at(away, R * 0.72);
    this.prop('Chest', h.x, h.z, toTown / D2R, 0.6, 0, 2.2);
    for (let i = 0; i < 16; i++) {
      const p = at(away + (r() - 0.5) * 1.2, R * (0.5 + r() * 0.4));
      this.prop(r() < 0.7 ? 'CoinPile' : 'GemPile', p.x, p.z, r() * 360, 0, 0, 2.4 + r() * 2.6);
    }
    for (let i = 0; i < 4; i++) {
      const p = at(away + (r() - 0.5) * 1.3, R * (0.5 + r() * 0.4));
      this.prop(['Goblet', 'Amphora', 'Candelabra', 'Key'][i], p.x, p.z, r() * 360, 0, 0, 1.8);
    }
    // what is left of the ones who came before
    for (let i = 0; i < 10; i++) {
      const p = at(r() * Math.PI * 2, R * (0.3 + r() * 0.8));
      this.prop('Skull', p.x, p.z, r() * 360, 0, 0, 0.9 + r() * 0.4);
    }
    for (let i = 0; i < 5; i++) {
      const p = at(away + (r() - 0.5) * 2.6, R + 9 + r() * 4);
      this.prop('TreeDead', p.x, p.z, r() * 360, 0.45, 0, 1.0 + r() * 0.5);
    }
    for (let i = 0; i < 6; i++) {
      const p = at(r() * Math.PI * 2, R * (0.6 + r() * 0.5));
      this.prop(r() < 0.5 ? 'Rock2' : 'Rock3', p.x, p.z, r() * 360, 0.35, 0, 0.6 + r() * 0.6);
    }
    // the way in: two braziers and a warning stone
    const g = at(toTown, R + 3.4);
    for (const s of [-1, 1]) this.prop('Brazier', g.x + Math.cos(toTown) * 2.6 * s, g.z - Math.sin(toTown) * 2.6 * s, 0, 0.35, 0, 1.2);
    const w = at(toTown + 0.35, R + 5.5);
    this.prop('Waystone', w.x, w.z, toTown / D2R, 0.5);
  }

  private barrow(cx: number, cz: number, R: number, toTown: number, r: () => number) {
    this.patch(cx, cz, R + 4, '#4E5A3A', 41);
    // the mound, behind the camp (away from town), its door facing the camp
    const away = toTown + Math.PI;
    const mx = cx + Math.sin(away) * (R + 3), mz = cz + Math.cos(away) * (R + 3);
    const grass = groundMaterial('#4F6A35', 43, 6, { set: 'grass', scale: 2.5, strength: 0.75, antiTile: true }, { roughness: 1 });
    const mound = new THREE.Mesh(new THREE.SphereGeometry(6, 28, 12, 0, Math.PI * 2, 0, Math.PI / 2), grass);
    mound.scale.set(1, 0.42, 1);
    mound.position.set(mx, -0.05, mz);
    mound.castShadow = true;
    mound.receiveShadow = true;
    this.group.add(mound);
    this.cols.push({ kind: 'circle', x: mx, z: mz, r: 5.4 });
    const dx = mx + Math.sin(toTown) * 5.6, dz = mz + Math.cos(toTown) * 5.6;
    this.put('K_Wall_Stone_Gateway', dx, dz, toTown / D2R);
    this.prop('Brazier', dx + Math.cos(toTown) * 2.2, dz - Math.sin(toTown) * 2.2, 0, 0.35);
    this.prop('Brazier', dx - Math.cos(toTown) * 2.2, dz + Math.sin(toTown) * 2.2, 0, 0.35);
    // standing stones around the camp
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2 + r() * 0.2;
      let d = a - toTown;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      if (Math.abs(d) < 0.35) continue;
      const x = cx + Math.sin(a) * (R + 1.5), z = cz + Math.cos(a) * (R + 1.5);
      this.put('Boulder', x, z, r() * 360, 0, 0.45, 1.5 + r() * 0.7, 0.45);
      this.cols.push({ kind: 'circle', x, z, r: 0.55 });
    }
    for (let i = 0; i < 5; i++) {
      const a = r() * Math.PI * 2, d = r() * R;
      this.prop('Skull', cx + Math.sin(a) * d, cz + Math.cos(a) * d, r() * 360, 0);
    }
  }

  /** What the ground is at (x, z) in metres: the cobbled plaza, a dirt path, or grass (footsteps). */
  static surfaceAt(x: number, z: number): 'stone' | 'gravel' | 'grass' {
    const d = Math.hypot(x, z);
    if (d < 14.2) return 'stone';
    for (const a of [0, 90, 180, 270, 45, -45]) {
      const len = a % 90 === 0 ? 40 : 24;
      const s = Math.sin(a * D2R), c = Math.cos(a * D2R);
      const along = x * s + z * c;
      const across = Math.abs(x * c - z * s);
      if (across < 1.7 && along > 9.5 && along < 10 + len) return 'gravel';
    }
    return 'grass';
  }

  // ---------------------------------------------------------------- merging

  private merge() {
    type Bucket = { mat: THREE.Material; parts: Array<{ geo: THREE.BufferGeometry; m: THREE.Matrix4 }>; verts: number; idx: number };
    const buckets = new Map<string, Bucket>();
    const tmp = new THREE.Matrix4();
    for (const p of this.placements) {
      const tpl = this.templates.get(p.name)!;
      tpl.updateWorldMatrix(true, true);
      // Relative to the piece's parent, not the piece: a quantized GLB keeps each mesh's
      // dequantisation (scale and offset) in that node's own transform.
      const rootInv = new THREE.Matrix4();
      if (tpl.parent) rootInv.copy(tpl.parent.matrixWorld).invert();
      tpl.traverse((o: any) => {
        if (!o.isMesh) return;
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        const geo: THREE.BufferGeometry = o.geometry;
        const local = tmp.copy(rootInv).multiply(o.matrixWorld);
        const m = p.m.clone().multiply(local);
        const groups = Array.isArray(o.material) && geo.groups.length ? geo.groups : [{ start: 0, count: geo.index ? geo.index.count : geo.attributes.position.count, materialIndex: 0 }];
        for (const g of groups) {
          const mat = mats[g.materialIndex ?? 0];
          const key = `${mat.userData.b8family || ''}:${mat.name || mat.uuid}`;
          let b = buckets.get(key);
          if (!b) buckets.set(key, (b = { mat, parts: [], verts: 0, idx: 0 }));
          const sub = groups.length > 1 ? subGeometry(geo, g.start, g.count) : geo;
          b.parts.push({ geo: sub, m });
          b.verts += sub.attributes.position.count;
          b.idx += sub.index ? sub.index.count : sub.attributes.position.count;
        }
      });
    }
    const v = new THREE.Vector3();
    const nm = new THREE.Matrix3();
    for (const [name, b] of buckets) {
      const pos = new Float32Array(b.verts * 3);
      const nor = new Float32Array(b.verts * 3);
      const index = new Uint32Array(b.idx);
      let vo = 0, io = 0;
      for (const { geo, m } of b.parts) {
        const P = geo.attributes.position, N = geo.attributes.normal;
        nm.getNormalMatrix(m);
        for (let i = 0; i < P.count; i++) {
          v.fromBufferAttribute(P as any, i).applyMatrix4(m);
          pos.set([v.x, v.y, v.z], (vo + i) * 3);
          if (N) {
            v.fromBufferAttribute(N as any, i).applyMatrix3(nm).normalize();
            nor.set([v.x, v.y, v.z], (vo + i) * 3);
          }
        }
        if (geo.index) {
          const I = geo.index;
          for (let i = 0; i < I.count; i++) index[io + i] = I.getX(i) + vo;
          io += I.count;
        } else {
          for (let i = 0; i < P.count; i++) index[io + i] = vo + i;
          io += P.count;
        }
        vo += P.count;
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      g.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
      g.setIndex(new THREE.BufferAttribute(index, 1));
      g.computeBoundingSphere();
      const mat = (b.mat as THREE.MeshStandardMaterial).clone();
      const surface = surfaceFor(mat.userData.b8family || 'props', mat.name || '');
      if (surface) void applySurface(mat, surface);
      if ((mat as any).emissive && (mat.emissive.r + mat.emissive.g + mat.emissive.b) > 0.01) {
        mat.userData.base = mat.emissiveIntensity || 1;
        this.glow.push(mat);
      }
      const mesh = new THREE.Mesh(g, mat);
      mesh.name = `World_${name.replace(':', '_')}`;
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      this.group.add(mesh);
    }
    // Merged: a later merge (the camps) only takes what was placed after this.
    this.placements = [];
  }

  // ---------------------------------------------------------------- ground

  private ground(): THREE.Object3D {
    const g = new THREE.Group();
    g.name = 'Ground';
    const grass = new THREE.Mesh(new THREE.CircleGeometry(150, 96), groundMaterial('#5E7F3F', 7, 60, { set: 'grass', scale: 3, strength: 0.75, antiTile: true }, { roughness: 0.95 }));
    grass.rotation.x = -Math.PI / 2;
    grass.receiveShadow = true;
    g.add(grass);
    // dirt paths out of the plaza
    const dirt = groundMaterial('#8A7152', 11, [2, 12], { set: 'forest_ground', scale: 2.5, antiTile: true }, { roughness: 1, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 });
    for (const a of [0, 90, 180, 270, 45, -45]) {
      const len = a % 90 === 0 ? 40 : 24;
      const p = new THREE.Mesh(new THREE.PlaneGeometry(3.2, len), dirt);
      p.rotation.x = -Math.PI / 2;
      p.rotation.z = a * D2R;
      const d = 10 + len / 2;
      p.position.set(Math.sin(a * D2R) * d, 0.01, Math.cos(a * D2R) * d);
      p.receiveShadow = true;
      g.add(p);
    }
    // cobbled plaza
    const cobParams = { roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 };
    let cob: THREE.MeshStandardMaterial;
    if (surfacesEnabled()) {
      cob = new THREE.MeshStandardMaterial({ color: '#B4AEA5', ...cobParams });
      void applySurface(cob, { set: 'plaza', scale: 3 });
    } else {
      cob = new THREE.MeshStandardMaterial({ map: cobbleTexture(), ...cobParams });
      cob.map!.repeat.set(14, 14);
    }
    const plaza = new THREE.Mesh(new THREE.CircleGeometry(14, 64), cob);
    plaza.rotation.x = -Math.PI / 2;
    plaza.position.y = 0.02;
    plaza.receiveShadow = true;
    g.add(plaza);
    const rimMat = new THREE.MeshStandardMaterial({ color: '#6E6A62', roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 });
    void applySurface(rimMat, { set: 'stone_blocks', scale: 1.2 });
    const rim = new THREE.Mesh(new THREE.RingGeometry(13.6, 14.3, 64), rimMat);
    rim.rotation.x = -Math.PI / 2;
    rim.position.y = 0.03;
    g.add(rim);
    return g;
  }
}

function subGeometry(geo: THREE.BufferGeometry, start: number, count: number): THREE.BufferGeometry {
  const g = new THREE.BufferGeometry();
  for (const k of Object.keys(geo.attributes)) g.setAttribute(k, geo.attributes[k]);
  if (geo.index) {
    const src = geo.index.array as ArrayLike<number>;
    const arr = new Uint32Array(count);
    for (let i = 0; i < count; i++) arr[i] = src[start + i];
    g.setIndex(new THREE.BufferAttribute(arr, 1));
  }
  return g;
}

/** A ground material: colour `color` with a real texture set on it (detail mode), or the
 *  old canvas noise (repeated `repeat` times) when surface textures are off. */
function groundMaterial(color: string, seed: number, repeat: number | [number, number], surface: Surface, params: THREE.MeshStandardMaterialParameters): THREE.MeshStandardMaterial {
  if (surfacesEnabled()) {
    const mat = new THREE.MeshStandardMaterial({ color, ...params });
    void applySurface(mat, surface);
    return mat;
  }
  const mat = new THREE.MeshStandardMaterial({ map: noiseTexture(color, shadeHex(color, -0.18), shadeHex(color, 0.12), seed), ...params });
  const [u, v] = Array.isArray(repeat) ? repeat : [repeat, repeat];
  mat.map!.repeat.set(u, v);
  return mat;
}

function noiseTexture(base: string, dark: string, light: string, seed: number): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = base;
  ctx.fillRect(0, 0, 128, 128);
  const r = rng(seed);
  for (let i = 0; i < 900; i++) {
    ctx.fillStyle = r() < 0.5 ? dark : light;
    ctx.globalAlpha = 0.25 + r() * 0.35;
    const s = 1 + r() * 3;
    ctx.fillRect(r() * 128, r() * 128, s, s * (1 + r() * 2));
  }
  ctx.globalAlpha = 1;
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function cobbleTexture(): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = '#4F4C47';
  ctx.fillRect(0, 0, 256, 256);
  const r = rng(5);
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const x = col * 32 + (row % 2 ? 16 : 0) + (r() - 0.5) * 4;
      const y = row * 32 + (r() - 0.5) * 4;
      const v = 120 + Math.floor(r() * 50);
      ctx.fillStyle = `rgb(${v},${v - 6},${v - 14})`;
      ctx.beginPath();
      (ctx as any).roundRect ? (ctx as any).roundRect(x + 2, y + 2, 28, 28, 8) : ctx.rect(x + 2, y + 2, 28, 28);
      ctx.fill();
    }
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function shadeHex(hex: string, amount: number): string {
  const n = parseInt(hex.slice(1), 16);
  const f = (v: number) => Math.max(0, Math.min(255, Math.round(v + (amount > 0 ? (255 - v) * amount : v * amount))));
  const r = f((n >> 16) & 255), g = f((n >> 8) & 255), b = f(n & 255);
  return `#${((r << 16) | (g << 8) | b).toString(16).padStart(6, '0')}`;
}
