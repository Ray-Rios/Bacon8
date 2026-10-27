// terrain.ts (2026-10-26): the packed heights unpack exactly (terrain_build.py's encoding), the
// ground is the drawn triangles, water and walking follow the sea's level; water.ts's rules with a
// terrain. The server's side is plugins/bacon_world/test/bacon_world/terrain_test.exs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeHeights, Heightfield, type TerrainInfo } from '../terrain';
import { keepOnLand, nearWater, waterKindAt, waterNameAt, waterYAt, type WaterLayout } from '../water';
import { UNITS_PER_METRE as U } from '../controls-math';

/** terrain_build.py's packing, for a k grid. */
function encode(k: number[][]): Uint8Array {
  const n = k.length;
  const d = k.map((row) => row.map((v, j) => (j === 0 ? v : v - row[j - 1])));
  const e = d.map((row, i) => row.map((v, j) => (i > 0 && j > 0 ? v - d[i - 1][j] : v)));
  const out = new Uint8Array(n * n * 2);
  e.flat().forEach((v, at) => {
    const u = v & 0xffff;
    out[at] = u >> 8;
    out[n * n + at] = u & 0xff;
  });
  return out;
}

test('decodeHeights undoes the packing exactly, rough ground included', () => {
  const n = 9;
  let seed = 7;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  const k = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => Math.floor(rnd() * 60000 * (i + j > 6 ? 1 : 0.01))));
  const out = decodeHeights(encode(k), n);
  assert.deepEqual(Array.from(out), k.flat());
  assert.throws(() => decodeHeights(new Uint8Array(10), n));
});

// A 5 x 5 world, 4 m between samples (16 m across), corner at (-8, -8) m; heights in metres.
// The west column is the sea (deep), one cell is a lake.
function world(): Heightfield {
  const n = 5, step = 0.05;
  const metres = [
    [-6, -1, 1, 2, 3],
    [-6, -1, 1, 2, 3],
    [-6, -1, 1, -4, 3],
    [-6, -1, 1, 2, 3],
    [-6, -1, 1, 2, 3],
  ];
  const lo = -10;
  const k = new Uint16Array(metres.flat().map((m) => Math.round((m - lo) / step)));
  const labels = new Uint8Array(n * n);
  metres.forEach((row, j) => row.forEach((m, i) => (labels[j * n + i] = m < 0 ? (i === 3 ? 2 : 1) : 0)));
  const info: TerrainInfo = {
    zone: 't', name: 'T', heights: '', water: '', samples: n, water_samples: n,
    size: 16 * U, x0: -8 * U, z0: -8 * U, lo: lo * U, step: step * U, sea: 0, margin: 2 * U, wade: 1.2 * U,
    lakes: [{ label: 2, id: 'tarn', name: 'the Tarn' }],
  };
  return new Heightfield(info, k, labels);
}

test('height: the samples, and on the triangles between them', () => {
  const hf = world();
  const near = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-6, `${a} vs ${b}`);
  near(hf.height(-8 * U, -8 * U), -6 * U); // north-west corner
  near(hf.height(0, 0), 1 * U); // the middle sample
  near(hf.height(-6 * U, -8 * U), -3.5 * U); // half way along the north edge
  // the cell's split runs north-west to south-east: on the diagonal it's the average of those two
  near(hf.height(-6 * U, -6 * U), (-6 + -1) / 2 * U);
  near(hf.height(-100 * U, 0), -6 * U); // off the map: the edge
  assert.ok(hf.normal(0, 0).y > 0.5);
});

test('water: the sea, a named lake, land; walking stops at wading depth and the margin', () => {
  const hf = world();
  assert.equal(hf.water(-8 * U, 0)?.kind, 'ocean');
  assert.equal(hf.water(4 * U, 0)?.name, 'the Tarn');
  assert.equal(hf.water(0, 0), null);
  assert.ok(hf.walkable(0, 0));
  assert.ok(hf.walkable(-4 * U, 0), 'ankle deep at -1 m');
  assert.ok(!hf.walkable(-7.5 * U, 0), 'deep sea');
  assert.ok(!hf.walkable(0, 7.5 * U), 'past the margin');
  assert.equal(hf.surface(-8 * U, 0), 0, 'over water: the surface');
});

test('water.ts with a terrain: kinds, names, the bank, keeping people out of deep water', () => {
  const hf = world();
  const w: WaterLayout = { shore: 150 * U, walk_radius: 151.5 * U, bank: 3 * U, cast_reach: 10 * U, lakes: [], sea: 0, terrain: hf };
  assert.equal(waterKindAt(w, -8 * U, 0), 'ocean');
  assert.equal(waterKindAt(w, 4 * U, 0), 'lake');
  assert.equal(waterKindAt(w, 0, 0), null);
  assert.equal(waterNameAt(w, 4 * U, 0), 'the Tarn');
  assert.equal(nearWater(w, 0, 0, 3 * U), 'lake', 'the tarn is 3 m east');
  assert.equal(waterYAt(w, -8 * U, 0), 0);
  // into the deep sea from land: refused (slides along where it can)
  assert.deepEqual(keepOnLand(w, -7.5 * U, 0, -3 * U, 0), { x: -3 * U, z: 0 });
  assert.deepEqual(keepOnLand(w, -2 * U, 1 * U, -3 * U, 0), { x: -2 * U, z: 1 * U });
  // already in deep water (a mount landed there): free to get out
  assert.deepEqual(keepOnLand(w, -7 * U, 0, -7.5 * U, 0), { x: -7 * U, z: 0 });
  // the Millpond still wins where it is
  const m: WaterLayout = { ...w, lakes: [{ id: 'millpond', name: 'the Millpond', x: 0, z: 0, rx: 1 * U, rz: 1 * U }] };
  assert.equal(waterNameAt(m, 0, 0), 'the Millpond');
  assert.ok(Math.abs(waterYAt(m, 0, 0) - 0.03 * U) < 1e-9);
});
