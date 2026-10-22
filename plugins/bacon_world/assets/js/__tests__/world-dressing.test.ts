// Unit tests for the village colliders (world-dressing.ts). Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WorldDressing, Collider } from '../world-dressing';

const near = (a: number, b: number, eps = 1e-6) => Math.abs(a - b) < eps;

test('a point inside a circle is pushed to its edge', () => {
  const cols: Collider[] = [{ kind: 'circle', x: 0, z: 0, r: 1 }];
  const p = WorldDressing.pushOut(cols, 0.5, 0, 0.25);
  assert.ok(near(p.x, 1.25) && near(p.z, 0));
  const q = WorldDressing.pushOut(cols, 3, 3, 0.25);
  assert.deepEqual(q, { x: 3, z: 3 }, 'points outside stay put');
});

test('boxes push out along the shallow axis, also when rotated', () => {
  const box: Collider = { kind: 'box', x: 10, z: 0, hx: 2, hz: 1, rot: 0 };
  const p = WorldDressing.pushOut([box], 10.5, 0.8, 0);
  assert.ok(near(p.x, 10.5) && near(p.z, 1), `got ${p.x},${p.z}`);
  // the same box turned 90 degrees: its long side now runs along z
  const turned: Collider = { ...box, rot: Math.PI / 2 };
  const q = WorldDressing.pushOut([turned], 10.8, 0.5, 0);
  assert.ok(near(q.x, 11) && near(q.z, 0.5), `got ${q.x},${q.z}`);
  const r = WorldDressing.pushOut([turned], 10.2, 1.9, 0);
  assert.ok(near(r.x, 10.2) && near(r.z, 2), `got ${r.x},${r.z}`);
});
