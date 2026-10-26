// water.ts's rules (2026-10-26): the same answers as the server's BaconWorld.Water (whose tests are
// plugins/bacon_world/test/bacon_world/fishing_test.exs), so the client only casts where the server
// allows. The layout is the server's, in scene units.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { UNITS_PER_METRE as U } from '../controls-math';
import { castSpot, clampToIsland, lakeDistance, nearWater, waterKindAt, type WaterLayout } from '../water';

const lake = { id: 'millpond', name: 'the Millpond', x: -31 * U, z: -40 * U, rx: 12 * U, rz: 8 * U };
const w: WaterLayout = { shore: 150 * U, walk_radius: 151.5 * U, bank: 3 * U, cast_reach: 10 * U, lakes: [lake] };

test('the sea all round, the Millpond, land between', () => {
  assert.equal(waterKindAt(w, lake.x, lake.z), 'lake');
  assert.equal(waterKindAt(w, 0, 0), null);
  assert.equal(waterKindAt(w, 155 * U, 0), 'ocean');
  assert.equal(waterKindAt(w, lake.x + lake.rx + 0.5 * U, lake.z), null);
});

test('near: the bank of the lake, the beach, not the village', () => {
  assert.equal(nearWater(w, lake.x + lake.rx + 2 * U, lake.z, w.bank), 'lake');
  assert.equal(nearWater(w, lake.x, lake.z + lake.rz + 2.5 * U, w.bank), 'lake');
  assert.equal(nearWater(w, lake.x + lake.rx + 5 * U, lake.z, w.bank), null);
  assert.equal(nearWater(w, 149 * U, 0, w.bank), 'ocean');
  assert.equal(nearWater(w, 0, 0, w.bank), null);
  assert.ok(Math.abs(lakeDistance(lake, lake.x + lake.rx + 2 * U, lake.z) - 2 * U) < 1e-9);
});

test('casting: facing the water from the bank lands on it, within reach', () => {
  const px = lake.x + lake.rx + 1.5 * U, pz = lake.z;
  const spot = castSpot(w, px, pz, -1, 0); // facing west, over the lake
  assert.ok(spot);
  assert.equal(spot!.kind, 'lake');
  assert.equal(waterKindAt(w, spot!.x, spot!.z), 'lake');
  assert.ok(Math.hypot(spot!.x - px, spot!.z - pz) <= w.cast_reach);
  assert.equal(castSpot(w, px, pz, 1, 0), null, 'facing away, over land');
  assert.equal(castSpot(w, 0, 0, 0, -1), null, 'from the village');
  const sea = castSpot(w, 149 * U, 0, 1, 0);
  assert.equal(sea?.kind, 'ocean');
});

test('nobody walks out to sea', () => {
  assert.deepEqual(clampToIsland(w, 10 * U, 0), { x: 10 * U, z: 0 });
  const p = clampToIsland(w, 300 * U, 0);
  assert.ok(Math.abs(Math.hypot(p.x, p.z) - w.walk_radius) < 1e-9);
});
