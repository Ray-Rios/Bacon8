// Unit tests for the Kraken's procedural rig (kraken-view.ts), on a stand-in skeleton shaped like
// build_kraken.py's (no model file, no WebGL). Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { KrakenRig } from '../kraken-view';

// A head, a maw in front of it (+z), and one arm splayed forward and up from the crown, ten bones.
function template(): { scene: THREE.Object3D } {
  const scene = new THREE.Group();
  const head = new THREE.Bone();
  head.name = 'head';
  scene.add(head);
  const maw = new THREE.Bone();
  maw.name = 'maw';
  maw.position.set(0, 0, 1.6);
  head.add(maw);
  for (const [name, dir] of [
    ['arm_1', new THREE.Vector3(0, 0.6, 0.8)],
    ['arm_5', new THREE.Vector3(0, -0.6, 0.8)],
  ] as Array<[string, THREE.Vector3]>) {
    let parent: THREE.Object3D = head;
    let at = new THREE.Vector3(0, dir.y > 0 ? 0.8 : -0.8, 1.0);
    for (let k = 1; k <= 10; k++) {
      const b = new THREE.Bone();
      b.name = `${name}_${String(k).padStart(2, '0')}`;
      // bones point along their +y: turn +y onto the arm's direction
      const world = parent.getWorldPosition(new THREE.Vector3());
      b.position.copy(at.clone().sub(world));
      b.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir.clone().normalize());
      // positions are in the parent's frame: undo the parent's rotation
      b.position.applyQuaternion(parent.getWorldQuaternion(new THREE.Quaternion()).invert());
      b.quaternion.premultiply(parent.getWorldQuaternion(new THREE.Quaternion()).invert());
      parent.add(b);
      scene.updateMatrixWorld(true);
      parent = b;
      at = at.clone().add(dir.clone().multiplyScalar(1.1));
    }
  }
  const saddle = new THREE.Object3D();
  saddle.name = 'saddle';
  head.add(saddle);
  return { scene };
}

function tipOf(rig: KrakenRig, name: string): THREE.Vector3 {
  rig.root.updateMatrixWorld(true);
  return rig.model.getObjectByName(`${name}_10`)!.getWorldPosition(new THREE.Vector3());
}

test('it builds a rig from the bones and animates every frame without moving its root', () => {
  const rig = new KrakenRig(template(), 1);
  const before = tipOf(rig, 'arm_1');
  for (let i = 0; i < 30; i++) rig.update(1 / 30);
  const after = tipOf(rig, 'arm_1');
  assert.ok(before.distanceTo(after) > 0.01, 'the arm writhes');
  assert.equal(rig.root.position.length(), 0);
  assert.ok(rig.saddle);
});

test('swimming gathers the arms toward the axis through the maw', () => {
  const still = new KrakenRig(template(), 1);
  const swim = new KrakenRig(template(), 1);
  for (let i = 0; i < 60; i++) {
    still.update(1 / 30);
    swim.root.position.z += 9 * 2.2 / 1.8 / 30; // ~9 m/s forward
    swim.update(1 / 30);
  }
  // distance of the tips from the axis (x = 0, y = 0 line along z), in the model's own frame
  const off = (rig: KrakenRig) => {
    const t = rig.model.worldToLocal(tipOf(rig, 'arm_1'));
    return Math.hypot(t.x, t.y);
  };
  assert.ok(off(swim) < off(still) - 0.2, `swimming tips ${off(swim)} vs still ${off(still)}`);
});

test('one-shots: each move has a length, a lash lands mid-swing, death sinks and holds', () => {
  const rig = new KrakenRig(template(), 1);
  for (const m of ['lash', 'slam', 'grab', 'squeeze', 'ink', 'maelstrom', 'roar', 'Hit']) assert.ok(rig.duration(m) > 0, m);
  assert.ok(rig.has('Roar') && rig.has('Death'));
  assert.ok(rig.play('lash') > 0.5);
  rig.die();
  for (let i = 0; i < 200; i++) rig.update(1 / 30);
  assert.ok(rig.model.position.y < -1, 'it sank');
  assert.equal(rig.play('lash'), 0, 'the dead do nothing');
  rig.revive();
  rig.update(1 / 30);
  assert.ok(Math.abs(rig.model.position.y) < 0.5);
});

test('the lash moves an upper arm (2026-10-27: it picked arms that did not exist)', () => {
  const still = new KrakenRig(template(), 1);
  const lash = new KrakenRig(template(), 1);
  lash.play('lash');
  for (let i = 0; i < 18; i++) {
    still.update(1 / 30);
    lash.update(1 / 30);
  }
  assert.ok(tipOf(lash, 'arm_1').distanceTo(tipOf(still, 'arm_1')) > 0.5);
});
