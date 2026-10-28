// The placements' instanced drawing (2026-10-28): one draw call per kind of piece however many
// there are, slots reused as pieces come and go, picking by instance, stretched sizes, and the
// binding stones' rings. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { BINDING_RADIUS_M, PlacedView, sizeOf, type Placement } from '../placed-view';

function source() {
  const box = (w: number, h: number, name: string) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, w), new THREE.MeshStandardMaterial({ name: 'Wood' }));
    m.position.y = h / 2;
    const g = new THREE.Group();
    g.name = name;
    g.add(m);
    return g;
  };
  const t: Record<string, THREE.Object3D> = { P_Barrel: box(0.8, 1, 'P_Barrel'), P_Crate: box(1, 1, 'P_Crate'), P_Waystone: box(0.6, 2, 'P_Waystone') };
  return { template: (n: string) => t[n] || null, ready: () => Promise.resolve() };
}

const at = (id: string, asset: string, x: number, z: number, extra: Partial<Placement> = {}): Placement => ({ id, asset, x, y: 0, z, rot: 0, scale: 1, data: {}, ...extra });

test('sizes: the uniform scale, or a stretch when the seed gave one', () => {
  assert.deepEqual(sizeOf({ scale: 2 }), [2, 2, 2]);
  assert.deepEqual(sizeOf({ scale: 1, data: { s: [1, 2, 3] } }), [1, 2, 3]);
  assert.deepEqual(sizeOf({ scale: 1.5, data: { s: [1, 'x', 3] } }), [1.5, 1.5, 1.5]);
  assert.equal(BINDING_RADIUS_M, 100);
});

test('a hundred barrels cost one draw call; removing one frees its slot', async () => {
  const v = new PlacedView(source());
  const list: Placement[] = [];
  for (let i = 0; i < 100; i++) list.push(at('b' + i, 'P_Barrel', i * 2, 0));
  list.push(at('c0', 'P_Crate', 0, 10));
  await v.setAll(list);
  assert.equal(v.all().length, 101);
  assert.equal(v.drawCalls(), 2);
  v.remove('b5');
  assert.equal(v.get('b5'), null);
  assert.equal(v.all().length, 100);
  v.put(at('b100', 'P_Barrel', 500, 0));
  assert.equal(v.drawCalls(), 2);
  // colliders follow: a barrel is round
  assert.ok(v.colliders().length >= 100);
});

test('picking finds the piece under the ray, by instance', async () => {
  const v = new PlacedView(source());
  await v.setAll([at('a', 'P_Crate', 0, 0), at('b', 'P_Crate', 10, 0), at('c', 'P_Crate', 20, 0)]);
  v.remove('a');
  v.group.updateMatrixWorld(true);
  const ray = new THREE.Raycaster(new THREE.Vector3(20, 10, 0), new THREE.Vector3(0, -1, 0));
  assert.equal(v.pick(ray), 'c');
  const miss = new THREE.Raycaster(new THREE.Vector3(0, 10, 0), new THREE.Vector3(0, -1, 0));
  assert.equal(v.pick(miss), null);
});

test('a hidden piece (being carried) is not picked and does not block', async () => {
  const v = new PlacedView(source());
  await v.setAll([at('a', 'P_Crate', 0, 0)]);
  const n = v.colliders().length;
  v.setHidden('a', true);
  v.group.updateMatrixWorld(true);
  assert.equal(v.pick(new THREE.Raycaster(new THREE.Vector3(0, 10, 0), new THREE.Vector3(0, -1, 0))), null);
  assert.ok(v.colliders().length < n);
  v.setHidden('a', false);
  assert.equal(v.colliders().length, n);
});

test('a binding stone shows its 100 m circle in build mode', async () => {
  const v = new PlacedView(source());
  await v.setAll([at('s', 'P_Waystone', 0, 0)]);
  let ring: THREE.Object3D | null = null;
  v.group.traverse((o) => { if (o.name === 'BindingRing') ring = o; });
  assert.ok(ring, 'a ring');
  v.setMarkers(true);
  assert.equal((ring as any).visible, true);
  v.setMarkers(false);
  assert.equal((ring as any).visible, false);
});
