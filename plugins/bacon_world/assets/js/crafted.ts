// Things Bacon World makes in code rather than loading (2026-10-29): the Robin Hood hat (worn in the
// new head slot, and placeable in build mode as X_RobinHat), the grill fork (the starter piercing
// weapon), the arrow the bows shoot, and the bacon bobber. They match the site's front door and
// /games renders (library/pipeline/scripts/hero_hat.py, hero_forks.py), built light for the game:
// a few hundred triangles each, shared geometry and materials, MeshStandardMaterial only (no new
// shader kinds).
import * as THREE from '../../../../assets/js/vendor/three';

const std = (color: string, roughness: number, metalness = 0, extra: Partial<THREE.MeshStandardMaterialParameters> = {}) =>
  new THREE.MeshStandardMaterial({ color, roughness, metalness, ...extra });

const MATS = {
  felt: std('#1f4a14', 0.95),
  feltDark: std('#183b0f', 0.95, 0, { side: THREE.DoubleSide }),
  band: std('#4a2a16', 0.6),
  feather: std('#b8361c', 0.65, 0, { side: THREE.DoubleSide }),
  quill: std('#e9dcc4', 0.4),
  steel: std('#c6ccd3', 0.28, 0.85),
  walnut: std('#4e2e18', 0.5),
  brass: std('#c8a24a', 0.32, 0.85),
  ash: std('#cfa76f', 0.6),
  crest: std('#7a1d14', 0.6),
  nock: std('#1b1512', 0.45),
  vaneRed: std('#b52a1a', 0.75, 0, { side: THREE.DoubleSide }),
  vaneCream: std('#e8e2d2', 0.8, 0, { side: THREE.DoubleSide }),
  bacon: std('#ffffff', 0.55, 0, { vertexColors: true, side: THREE.DoubleSide }),
};

/** A grid of points (rows of `nu` around) as an indexed mesh, closed round each row. */
function gridGeometry(rows: number[][][], closed = true): THREE.BufferGeometry {
  const nv = rows.length;
  const nu = rows[0].length;
  const pos: number[] = [];
  for (const r of rows) for (const p of r) pos.push(p[0], p[1], p[2]);
  const idx: number[] = [];
  for (let j = 0; j < nv - 1; j++)
    for (let i = 0; i < (closed ? nu : nu - 1); i++) {
      const a = j * nu + i, b = j * nu + ((i + 1) % nu), c = (j + 1) * nu + ((i + 1) % nu), d = (j + 1) * nu + i;
      idx.push(a, b, c, a, c, d);
    }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

// ------------------------------------------------------------------ the Robin Hood hat

let hatGeo: { crown: THREE.BufferGeometry; brim: THREE.BufferGeometry; band: THREE.BufferGeometry; feather: THREE.BufferGeometry; quill: THREE.BufferGeometry } | null = null;

/**
 * The hat, in metres: the middle of the crown's base at the origin, +Y up, its point to the
 * front (+Z, the way a character faces), the brim turned up into a peak at the back and a red
 * feather on the left (+X). The shape is hero_hat.py's, scaled to a head (0.26 m long).
 */
export function makeRobinHat(): THREE.Group {
  if (!hatGeo) hatGeo = buildHat();
  const g = new THREE.Group();
  g.name = 'RobinHat';
  g.add(
    new THREE.Mesh(hatGeo.crown, MATS.felt),
    new THREE.Mesh(hatGeo.brim, MATS.feltDark),
    new THREE.Mesh(hatGeo.band, MATS.band),
    new THREE.Mesh(hatGeo.feather, MATS.feather),
    new THREE.Mesh(hatGeo.quill, MATS.quill),
  );
  g.traverse((o: any) => o.isMesh && ((o.castShadow = true), (o.receiveShadow = true)));
  return g;
}

function buildHat() {
  const S = 0.21;                       // hero_hat.py's units to metres
  const A = 0.62, B = 0.4, H = 0.62;
  const NU = 36, NV = 14;
  // hero_hat.py builds the point along -x with z up; here the point is +Z and up is +Y. A
  // rotation, not a mirror (so the faces still face out): (x, y, z)_hero -> (-y, z, -x)
  const P = (x: number, y: number, z: number) => [-y * S, z * S, -x * S];
  const crown: number[][][] = [];
  for (let j = 0; j < NV; j++) {
    const v = j / (NV - 1);
    const cx = -0.34 * v ** 1.3, cz = H * v - 0.07 * v ** 4;
    const rx = A * (1 - v) ** 0.85 + 0.012, ry = B * (1 - v) ** 0.6 * (1 - 0.45 * v) + 0.008;
    const row: number[][] = [];
    for (let i = 0; i < NU; i++) {
      const u = (i / NU) * Math.PI * 2;
      const lump = 0.012 * Math.sin(3 * u + 1.3) * Math.sin(Math.PI * v) + 0.008 * Math.sin(5 * u - 0.7) * v;
      row.push(P(cx + (rx + lump) * Math.cos(u), (ry + lump) * Math.sin(u), cz + 0.03 * Math.cos(u) * v));
    }
    crown.push(row);
  }
  const brim: number[][][] = [];
  for (let j = 0; j < 5; j++) {
    const w = j / 4;
    const row: number[][] = [];
    for (let i = 0; i < NU; i++) {
      const u = (i / NU) * Math.PI * 2;
      let nx = Math.cos(u) / A, ny = Math.sin(u) / B;
      const nn = Math.hypot(nx, ny);
      nx /= nn; ny /= nn;
      const back = (1 + Math.cos(u)) / 2, front = Math.max(0, -Math.cos(u));
      const width = 0.08 + 0.1 * back + 0.16 * Math.max(0, Math.cos(u)) ** 10 + 0.24 * front ** 9;
      const th = ((-10 + 90 * back ** 1.6 + 14 * w - 14 * front ** 4 * w) * Math.PI) / 180;
      const r = w * width;
      row.push(P(A * Math.cos(u) + r * Math.cos(th) * nx, B * Math.sin(u) + r * Math.cos(th) * ny, 0.012 + r * Math.sin(th)));
    }
    brim.push(row);
  }
  const band: number[][][] = [];
  for (const v of [0, 0.05, 0.1]) {
    const row: number[][] = [];
    for (let i = 0; i < NU; i++) {
      const u = (i / NU) * Math.PI * 2;
      row.push(P(-0.34 * v ** 1.3 + (A * (1 - v) ** 0.85 + 0.022) * Math.cos(u), (B * (1 - v) ** 0.6 * (1 - 0.45 * v) + 0.018) * Math.sin(u), H * v + 0.004));
    }
    band.push(row);
  }
  // the feather: a curved strip from the band at the back, our left, sweeping up and back
  const fpts: number[][] = [], fq: THREE.Vector3[] = [];
  const ua = -0.22;
  const ax = A * 0.93 * Math.cos(ua) + 0.02, ay = B * 1.05 * Math.sin(ua), az = 0.06;
  const N = 14;
  for (let k = 0; k <= N; k++) {
    const s = k / N;
    const c = [ax + 0.22 * s + 0.12 * s * s, ay - 0.04 * s, az + 0.8 * s - 0.14 * s ** 2.2];
    const w = 0.075 * Math.sin(Math.PI * Math.min(1, s * 0.95 + 0.04)) ** 0.55 * (1 - 0.35 * s);
    fpts.push(P(c[0] - w * 0.5, c[1], c[2] + w * 0.8), P(c[0] + w * 0.5, c[1], c[2] - w * 0.8));
    fq.push(new THREE.Vector3(...(P(c[0], c[1] - 0.004, c[2]) as [number, number, number])));
  }
  const feather = new THREE.BufferGeometry();
  feather.setAttribute('position', new THREE.Float32BufferAttribute(fpts.flat(), 3));
  const fi: number[] = [];
  for (let k = 0; k < N; k++) fi.push(2 * k, 2 * k + 1, 2 * k + 3, 2 * k, 2 * k + 3, 2 * k + 2);
  feather.setIndex(fi);
  feather.computeVertexNormals();
  const quill = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(fq), 16, 0.0012, 4, false);
  const crownGeo = gridGeometry(crown);
  // close the crown's tip
  return { crown: crownGeo, brim: gridGeometry(brim), band: gridGeometry(band), feather, quill };
}

// ------------------------------------------------------------------ the grill fork

let forkGeo: THREE.BufferGeometry[] | null = null;

/**
 * The grill fork as a weapon (build_weapons2.py's convention): the grip's middle at the origin,
 * +Y along the handle to the tines, the tines side by side along X, metres. 0.6 m long.
 */
export function makeGrillFork(): THREE.Group {
  if (!forkGeo) {
    const lathe = (pts: Array<[number, number]>, seg = 10) => new THREE.LatheGeometry(pts.map(([y, r]) => new THREE.Vector2(r, y)), seg);
    const handle = lathe([[-0.115, 0], [-0.115, 0.012], [-0.105, 0.016], [0.0, 0.017], [0.085, 0.015], [0.09, 0]], 12);
    const ferrule = lathe([[0.085, 0], [0.085, 0.0135], [0.112, 0.012], [0.112, 0]], 12);
    const cap = lathe([[-0.128, 0], [-0.128, 0.008], [-0.118, 0.014], [-0.112, 0.014], [-0.112, 0]], 10);
    const shank = new THREE.CylinderGeometry(0.0045, 0.0055, 0.24, 8).translate(0, 0.112 + 0.12, 0);
    shank.scale(1, 1, 0.75);
    const yoke = new THREE.TorusGeometry(0.03, 0.0045, 6, 14, Math.PI).rotateZ(Math.PI).translate(0, 0.38, 0);
    const tine = (x: number) => {
      const body = new THREE.CylinderGeometry(0.004, 0.0045, 0.13, 8).translate(x, 0.38 + 0.065, 0);
      const point = new THREE.ConeGeometry(0.004, 0.04, 8).translate(x, 0.38 + 0.13 + 0.02, 0);
      return [body, point];
    };
    forkGeo = [handle, ferrule, cap, shank, yoke, ...tine(-0.03), ...tine(0.03)];
  }
  const g = new THREE.Group();
  g.name = 'GrillFork';
  const mats = [MATS.walnut, MATS.brass, MATS.brass, MATS.steel, MATS.steel, MATS.steel, MATS.steel, MATS.steel, MATS.steel];
  forkGeo.forEach((geo, i) => g.add(new THREE.Mesh(geo, mats[i])));
  // two rivets through the handle
  for (const y of [-0.06, 0.04]) {
    const r = new THREE.Mesh(RIVET, MATS.brass);
    r.position.set(0, y, 0.0165);
    g.add(r);
  }
  return g;
}

const RIVET = new THREE.SphereGeometry(0.0035, 6, 4);

// ------------------------------------------------------------------ the arrow

let arrowGeo: Record<string, THREE.BufferGeometry> | null = null;

/**
 * The arrow the bows shoot (arrows.ts flies it, items.ts nocks it): along +Z from the nock (0) to
 * the point (0.79), metres. Ash shaft, red cresting, a steel broadhead, three vanes, the cock
 * feather red: the arrow of the site's hat shot.
 */
export function makeArrowModel(): THREE.Group {
  if (!arrowGeo) {
    const along = (g: THREE.BufferGeometry) => g.rotateX(Math.PI / 2);
    // a vane: a feather's outline in (out from the shaft, along it), stood up along +X and +Z
    const vane = new THREE.Shape();
    vane.moveTo(0, 0);
    vane.lineTo(0, 0.12);
    vane.quadraticCurveTo(0.014, 0.1, 0.024, 0.06);
    vane.quadraticCurveTo(0.027, 0.02, 0.02, 0.0);
    vane.lineTo(0, 0);
    const flat = new THREE.ShapeGeometry(vane, 5);
    const vp = flat.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < vp.count; i++) vp.setXYZ(i, vp.getX(i) + 0.0042, 0, vp.getY(i));
    flat.computeVertexNormals();
    arrowGeo = {
      shaft: along(new THREE.CylinderGeometry(0.0042, 0.0042, 0.7, 6)).translate(0, 0, 0.36),
      crest: along(new THREE.CylinderGeometry(0.0046, 0.0046, 0.012, 6)),
      nock: along(new THREE.CylinderGeometry(0.0048, 0.004, 0.014, 6)).translate(0, 0, 0.004),
      ferrule: along(new THREE.CylinderGeometry(0.004, 0.0055, 0.02, 6)).translate(0, 0, 0.72),
      head: along(new THREE.ConeGeometry(0.014, 0.065, 4)).scale(1, 0.45, 1).translate(0, 0, 0.762),
      vane: flat.translate(0, 0, 0.03),
    };
  }
  const a = new THREE.Group();
  a.name = 'Arrow';
  const G = arrowGeo;
  a.add(new THREE.Mesh(G.shaft, MATS.ash), new THREE.Mesh(G.nock, MATS.nock), new THREE.Mesh(G.ferrule, MATS.steel), new THREE.Mesh(G.head, MATS.steel));
  for (const z of [0.15, 0.17]) {
    const c = new THREE.Mesh(G.crest, MATS.crest);
    c.position.z = z;
    a.add(c);
  }
  for (let i = 0; i < 3; i++) {
    const v = new THREE.Mesh(G.vane, i === 0 ? MATS.vaneRed : MATS.vaneCream);
    v.rotation.z = (i * Math.PI * 2) / 3 + Math.PI / 2;
    a.add(v);
  }
  return a;
}

// ------------------------------------------------------------------ the bacon bobber

let baconGeo: THREE.BufferGeometry | null = null;

/** Two strips of bacon floating on the line (fishing), `size` metres long, centred, flat on +Y. */
export function makeBaconBobber(size = 0.16): THREE.Group {
  if (!baconGeo) baconGeo = baconStrips();
  const m = new THREE.Mesh(baconGeo, MATS.bacon);
  m.scale.setScalar(size);
  const g = new THREE.Group();
  g.name = 'BaconBobber';
  g.add(m);
  return g;
}

/** Bacon, crossways: meat with two lengthwise stripes of fat and crisp edges (pure geometry; tested). */
export function baconStrips(): THREE.BufferGeometry {
  const L = 40, W = 16;
  const pos: number[] = [], col: number[] = [], idx: number[] = [];
  const meat = new THREE.Color('#a8382a'), fat = new THREE.Color('#f2d8c4'), crisp = new THREE.Color('#5a1f14');
  const across = [crisp, meat, fat, meat, meat, fat, meat, crisp, crisp];
  let base = 0;
  // side by side: each strip moved off the middle square to its length (which runs at 45 degrees)
  for (const [dx, dz, ph] of [[0.092, -0.092, 0], [-0.092, 0.092, 1.7]]) {
    for (let j = 0; j <= W; j++) {
      for (let i = 0; i <= L; i++) {
        const s = i / L - 0.5, w = (j / W - 0.5) * 0.22;
        // 45 degrees, rippled along its length, its edges gently wavy
        const edge = j === 0 ? -1 : j === W ? 1 : 0;
        const x = s * 0.9, z = w + edge * 0.008 * Math.sin(s * 17 + ph * 3);
        const y = 0.03 * Math.sin(s * 11 + ph) + 0.01 * Math.sin(s * 23 + ph * 2);
        const c = Math.SQRT1_2;
        pos.push(dx + (x - z) * c, y, dz + (x + z) * c);
        const f = (j / W) * (across.length - 1), k0 = Math.floor(f), k1 = Math.min(across.length - 1, k0 + 1);
        const k = across[k0].clone().lerp(across[k1], f - k0);
        col.push(k.r, k.g, k.b);
      }
    }
    for (let j = 0; j < W; j++)
      for (let i = 0; i < L; i++) {
        const a = base + j * (L + 1) + i, b = a + 1, cc = a + L + 2, d = a + L + 1;
        idx.push(a, b, cc, a, cc, d);
      }
    base += (W + 1) * (L + 1);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

// ------------------------------------------------------------------ wearing the hat

/**
 * Where the hat sits on a head, as a matrix in the head bone's own space, worked out from the
 * skeleton's bind pose (so it doesn't matter which way the bone's axes point): upright in the
 * character's frame, its base `up` metres above the head bone, `fwd` metres forward, tipped back
 * `tilt` degrees, scaled by `scale` (pure apart from three's maths; tested).
 */
export function hatOnHead(boneBind: THREE.Matrix4, opts: { up: number; fwd: number; tilt: number; scale: number }): THREE.Matrix4 {
  const bonePos = new THREE.Vector3().setFromMatrixPosition(boneBind);
  const want = new THREE.Matrix4().compose(
    bonePos.clone().add(new THREE.Vector3(0, opts.up, opts.fwd)),
    new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), THREE.MathUtils.degToRad(-opts.tilt)),
    new THREE.Vector3(opts.scale, opts.scale, opts.scale),
  );
  return new THREE.Matrix4().copy(boneBind).invert().multiply(want);
}

/** How the hat sits on each body (metres; tuned in the harness, 2026-10-29). */
export const HAT_FIT: Record<string, { up: number; fwd: number; tilt: number; scale: number }> = {
  female: { up: 0.085, fwd: 0, tilt: 8, scale: 1.15 },
  male: { up: 0.1, fwd: -0.012, tilt: 8, scale: 1.25 },
};

/**
 * Puts the hat on (or takes it off) a character: `root` the character, `body` 'male' | 'female'.
 * The hat goes on the head bone so it follows every nod.
 */
export function wearHat(root: THREE.Object3D, body: string, on: boolean): void {
  const head = root.getObjectByName('head') as THREE.Bone | undefined;
  if (!head) return;
  const old = head.children.find((c) => c.userData.b8Hat);
  if (!on) {
    if (old) head.remove(old);
    return;
  }
  if (old) return;
  let bind: THREE.Matrix4 | null = null;
  root.traverse((o: any) => {
    if (bind || !o.isSkinnedMesh) return;
    const i = o.skeleton.bones.indexOf(head);
    if (i >= 0) bind = new THREE.Matrix4().copy(o.skeleton.boneInverses[i]).invert();
  });
  if (!bind) return;
  const hat = makeRobinHat();
  hat.userData.b8Hat = true;
  hat.matrixAutoUpdate = false;
  hat.matrix.copy(hatOnHead(bind, HAT_FIT[body] || HAT_FIT.female));
  head.add(hat);
}
