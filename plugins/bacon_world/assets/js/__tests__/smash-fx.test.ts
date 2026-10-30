// Smashing (2026-10-30): the bits a piece breaks into are its own triangles, every one kept once,
// with their textures' coordinates; how many hits a piece takes grows with its size; and the bits
// fall, land on the ground and go. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { SmashFx, cutIntoBits, hitsFor } from '../smash-fx';

test('a box cut 2x2x2 keeps every triangle, uv and all, and the bits sit where they were', () => {
  const geo = new THREE.BoxGeometry(2, 2, 2); // indexed, 12 triangles
  const local = new THREE.Matrix4().makeTranslation(0, 1, 0);
  const bits = cutIntoBits(geo, local, 2);
  assert.ok(bits.length > 1 && bits.length <= 8);
  const tris = bits.reduce((n, b) => n + b.geo.getAttribute('position').count / 3, 0);
  assert.equal(tris, 12);
  for (const b of bits) {
    assert.ok(b.geo.getAttribute('uv'), 'keeps the uvs');
    assert.ok(b.geo.getAttribute('normal'), 'keeps the normals');
    // centred on itself; its centre is in the model's frame (the box stands on y = 0..2)
    b.geo.computeBoundingBox();
    const c = b.geo.boundingBox!.getCenter(new THREE.Vector3());
    assert.ok(c.length() < 1e-5);
    assert.ok(b.center.y >= 0 && b.center.y <= 2);
  }
});

test('multi-material groups survive the cut', () => {
  const geo = new THREE.BoxGeometry(1, 1, 1); // six groups, one per side
  const bits = cutIntoBits(geo, new THREE.Matrix4(), 3);
  for (const b of bits) {
    const covered = b.geo.groups.reduce((n, g) => n + g.count, 0);
    assert.equal(covered, b.geo.getAttribute('position').count);
  }
});

test('bigger things take more hits, from 1 up to 6', () => {
  const box = (s: number) => new THREE.Box3(new THREE.Vector3(0, 0, 0), new THREE.Vector3(s, s, s));
  assert.equal(hitsFor(box(0.2)), 1);
  assert.ok(hitsFor(box(1)) >= 2);
  assert.ok(hitsFor(box(3)) > hitsFor(box(1)));
  assert.equal(hitsFor(box(40)), 6);
});

test('the bits fly, land on the ground and are gone a few seconds later', () => {
  const fx = new SmashFx(() => 0);
  const geo = new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0);
  const mat = new THREE.MeshStandardMaterial();
  const parts = [{ geo, mat, local: new THREE.Matrix4() }];
  const box = new THREE.Box3(new THREE.Vector3(-0.5, 0, -0.5), new THREE.Vector3(0.5, 1, 0.5));
  fx.shatter('P_Crate', parts, new THREE.Matrix4(), box);
  const bits = () => fx.group.children.filter((o: any) => o.isInstancedMesh);
  assert.ok(bits().length > 1);
  for (let i = 0; i < 60; i++) fx.update(1 / 30); // two seconds
  for (const b of bits()) assert.ok(b.position.y >= -1e-6, 'nothing falls through the ground');
  for (let i = 0; i < 180; i++) fx.update(1 / 30); // six more
  assert.equal(fx.group.children.length, 0);
  // the second smash of the same kind reuses the cut
  fx.shatter('P_Crate', parts, new THREE.Matrix4(), box);
  assert.ok(bits().length > 1);
  fx.clear();
  assert.equal(fx.group.children.length, 0);
});
