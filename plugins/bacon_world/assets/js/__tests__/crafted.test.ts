// crafted.ts (2026-10-29): the Robin Hood hat, the grill fork, the arrow and the bacon bobber, all
// drawn in code. Their sizes and the way they face are what the game relies on: the fork's tines
// up +Y from the grip, the arrow along +Z with its point at the front, the hat's point forward.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { baconStrips, hatOnHead, makeArrowModel, makeBaconBobber, makeGrillFork, makeRobinHat } from '../crafted';

const box = (o: THREE.Object3D) => {
  o.updateMatrixWorld(true);
  return new THREE.Box3().setFromObject(o);
};

test('the grill fork is about 0.6 m long, its tines up +Y', () => {
  const b = box(makeGrillFork());
  const s = b.getSize(new THREE.Vector3());
  assert.ok(s.y > 0.5 && s.y < 0.75, `length ${s.y}`);
  assert.ok(s.x < 0.12 && s.z < 0.12, 'slender');
});

test('the arrow lies along +Z, nock at 0, point at about 0.79 m', () => {
  const b = box(makeArrowModel());
  assert.ok(Math.abs(b.min.z) < 0.02, `nock ${b.min.z}`);
  assert.ok(b.max.z > 0.75 && b.max.z < 0.84, `point ${b.max.z}`);
  assert.ok(b.getSize(new THREE.Vector3()).x < 0.08, 'vanes stay close to the shaft');
});

test('the hat is head-sized, its point forward (+Z) and its crown up', () => {
  const hat = makeRobinHat();
  const b = box(hat);
  const s = b.getSize(new THREE.Vector3());
  assert.ok(s.z > 0.25 && s.z < 0.6, `length ${s.z}`);
  assert.ok(s.x > 0.15 && s.x < 0.45, `width ${s.x}`);
  assert.ok(b.max.y > 0.08, 'a crown');
  assert.ok(b.max.z > -b.min.z, 'the point reaches further forward than the back');
});

test('the hat faces outwards (no mirrored, inside-out faces)', () => {
  let out = 0, inn = 0;
  const c = box(makeRobinHat()).getCenter(new THREE.Vector3());
  // the crown is the hat's first part
  [makeRobinHat().children[0]].forEach((m: any) => {
    const g = m.geometry.index ? m.geometry.toNonIndexed() : m.geometry;
    const p = g.attributes.position, a = new THREE.Vector3(), b = new THREE.Vector3(), d = new THREE.Vector3();
    for (let i = 0; i < p.count; i += 3) {
      a.fromBufferAttribute(p, i); b.fromBufferAttribute(p, i + 1); d.fromBufferAttribute(p, i + 2);
      const n = new THREE.Vector3().crossVectors(b.clone().sub(a), d.clone().sub(a));
      const mid = a.clone().add(b).add(d).divideScalar(3).sub(c);
      if (n.dot(mid) > 0) out++; else inn++;
    }
  });
  assert.ok(out > 2 * inn, `outward ${out}, inward ${inn}`);
});

test('the bacon bobber: two coloured strips, bobber-sized', () => {
  const g = baconStrips();
  assert.ok(g.attributes.color.count === g.attributes.position.count);
  const s = box(makeBaconBobber(0.17)).getSize(new THREE.Vector3());
  assert.ok(s.x < 0.25 && s.z < 0.25 && s.x > 0.05, `size ${s.x} x ${s.z}`);
});

test('hatOnHead undoes the bone bind, so the hat sits upright above the head', () => {
  const bind = new THREE.Matrix4().compose(new THREE.Vector3(0, 1.6, 0), new THREE.Quaternion().setFromEuler(new THREE.Euler(0.3, 1, -0.5)), new THREE.Vector3(1, 1, 1));
  const local = hatOnHead(bind, { up: 0.1, fwd: 0, tilt: 0, scale: 1 });
  const world = bind.clone().multiply(local);
  const p = new THREE.Vector3().setFromMatrixPosition(world);
  assert.ok(Math.abs(p.y - 1.7) < 1e-6 && Math.abs(p.x) < 1e-6);
  const up = new THREE.Vector3(0, 1, 0).transformDirection(world);
  assert.ok(up.y > 0.999);
});
