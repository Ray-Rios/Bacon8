// Build mode (2026-10-28): snapping, finding the ground under the cursor, which pieces block
// walking, and the window's search. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rayGround, snapPiece } from '../build-world';
import { colliderShape, isModel } from '../placed-view';
import { filterCatalogue, type CatalogueEntry } from '../build-ui';

test('building pieces snap to the 1.5 m grid and right angles', () => {
  const s = snapPiece(2.2, -0.8, 1.4);
  assert.equal(s.x, 1.5);
  assert.equal(s.z, -1.5);
  assert.ok(Math.abs(s.rot - Math.PI / 2) < 1e-9);
  // a negative turn comes back in 0..2pi
  const t = snapPiece(0, 0, -0.1);
  assert.ok(Math.abs(t.rot) < 1e-9 || Math.abs(t.rot - 2 * Math.PI) < 1e-9);
  assert.ok(Math.abs(snapPiece(0, 0, -1.6).rot - 1.5 * Math.PI) < 1e-9);
});

test('the ray meets flat ground, a hill, and misses the sky', () => {
  const flat = () => 0;
  const hit = rayGround({ x: 0, y: 10, z: 0 }, { x: 0, y: -1, z: 0 }, flat, 100, 0.5)!;
  assert.ok(Math.abs(hit.y) < 0.02 && Math.abs(hit.x) < 1e-9);
  // looking down at 45 degrees from 10 up: lands 10 out
  const d = Math.SQRT1_2;
  const h2 = rayGround({ x: 0, y: 10, z: 0 }, { x: d, y: -d, z: 0 }, flat, 100, 0.5)!;
  assert.ok(Math.abs(h2.x - 10) < 0.05);
  // a wall of a hill at x > 5 rising to 8: the ray stops on its face
  const hill = (x: number) => (x > 5 ? 8 : 0);
  const h3 = rayGround({ x: 0, y: 10, z: 0 }, { x: d, y: -d, z: 0 }, hill, 100, 0.5)!;
  assert.ok(h3.x > 5 && h3.x < 5.6 && h3.y === 8);
  assert.equal(rayGround({ x: 0, y: 10, z: 0 }, { x: 0, y: 1, z: 0 }, flat, 100, 0.5), null);
  // starting under the ground: nothing
  assert.equal(rayGround({ x: 0, y: -1, z: 0 }, { x: 0, y: -1, z: 0 }, flat, 100, 0.5), null);
});

const box = (sx: number, sy: number, sz: number) => ({ min: { x: -sx / 2, y: 0, z: -sz / 2 }, max: { x: sx / 2, y: sy, z: sz / 2 } });

test('what blocks walking', () => {
  assert.equal(colliderShape('K_Floor_Wood', box(3, 0.2, 3)).kind, 'none');
  assert.equal(colliderShape('K_Roof_Tile', box(3, 1.5, 3)).kind, 'none');
  assert.equal(colliderShape('K_Stairs_Stone', box(3, 3, 3)).kind, 'none');
  assert.equal(colliderShape('P_Mug', box(0.1, 0.12, 0.1)).kind, 'none');
  assert.equal(colliderShape('K_Wall_Stone', box(3, 3, 0.24)).kind, 'box');
  const gate = colliderShape('K_Wall_Stone_Door', box(3, 3, 0.24));
  assert.equal(gate.kind, 'gate');
  if (gate.kind === 'gate') assert.ok(gate.gap > 1 && gate.gap < 1.4);
  const tree = colliderShape('P_TreeOak', box(4, 6, 4));
  assert.ok(tree.kind === 'circle' && tree.r < 0.5);
  assert.equal(colliderShape('P_Barrel', box(0.7, 1, 0.7)).kind, 'circle');
  assert.equal(colliderShape('P_Crate', box(0.9, 0.9, 0.9)).kind, 'box');
  assert.ok(isModel('P_Barrel') && isModel('K_Wall_Wood') && !isModel('mob:goblin') && !isModel('npc:villager'));
});

const E = (id: string, name: string, category: string, allowed = true): CatalogueEntry => ({ id, name, category, kind: 'model', min_role: allowed ? 'member' : 'gm', allowed });

test('the search: every word, the category, the locked ones last or hidden', () => {
  const list = [E('P_Barrel', 'Barrel', 'Props'), E('P_BarrelWater', 'Barrel water', 'Props'), E('K_Wall_Stone', 'Wall stone', 'Building'),
    E('mob:goblin', 'Goblin', 'Creatures', false), E('P_TreeOak', 'Tree oak', 'Trees & plants')];
  assert.deepEqual(filterCatalogue(list, 'barrel', 'All', false).map((e) => e.id), ['P_Barrel', 'P_BarrelWater']);
  assert.deepEqual(filterCatalogue(list, 'barrel water', 'All', false).map((e) => e.id), ['P_BarrelWater']);
  assert.deepEqual(filterCatalogue(list, '', 'Building', false).map((e) => e.id), ['K_Wall_Stone']);
  assert.equal(filterCatalogue(list, 'goblin', 'All', false).length, 0);
  const all = filterCatalogue(list, '', 'All', true);
  assert.equal(all[all.length - 1].id, 'mob:goblin');
  // the id matches too
  assert.deepEqual(filterCatalogue(list, 'k_wall', 'All', false).map((e) => e.id), ['K_Wall_Stone']);
});
