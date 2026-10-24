// Unit tests for the animation driver (anim-driver.ts). Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { CharacterAnimator, channelOfBones, locomotionClip, locomotionRate, mirrorBoneName, mirrorValues, LOCO } from '../anim-driver';

test('locomotion picks strafe and backpedal clips from the direction relative to facing', () => {
  const m = (dirX: number, dirZ: number, speed = 5) => locomotionClip({ speed, dirX, dirZ, grounded: true });
  assert.equal(m(0, 1), LOCO.jog);
  assert.equal(m(0, 1, 1), LOCO.walk);
  assert.equal(m(0, 1, 7), LOCO.sprint);
  assert.equal(m(1, 0), LOCO.strafeRFast);
  assert.equal(m(-1, 0), LOCO.strafeLFast);
  assert.equal(m(-1, 0, 1), LOCO.strafeL);
  assert.equal(m(0, -1), LOCO.jogBack);
  assert.equal(m(0.2, -1, 1), LOCO.walkBack);
  assert.equal(m(0, 0, 0.1), LOCO.idle);
  assert.equal(locomotionClip({ speed: 2, dirX: 0, dirZ: 1, grounded: true, crouch: true }), LOCO.crouchWalk);
});

test('playback rate follows speed, within limits', () => {
  assert.ok(Math.abs(locomotionRate('Jog_Fwd_Loop', 3.9) - 1) < 1e-9);
  assert.equal(locomotionRate('Jog_Fwd_Loop', 100), 1.6);
  assert.equal(locomotionRate('Sword_Idle', 3), 1);
});

test('mirroring swaps sides and reflects rotations and positions', () => {
  assert.equal(mirrorBoneName('hand_l'), 'hand_r');
  assert.equal(mirrorBoneName('upperarm_twist_01_r'), 'upperarm_twist_01_l');
  assert.equal(mirrorBoneName('spine_01'), 'spine_01');
  const q = [0.1, 0.2, 0.3, 0.9];
  mirrorValues('quaternion', q);
  assert.deepEqual(q, [0.1, -0.2, -0.3, 0.9]);
  const p = [1, 2, 3];
  mirrorValues('position', p);
  assert.deepEqual(p, [-1, 2, 3]);
});

// A tiny skeleton with the B8 bone names that matter for the channels.
function rig() {
  const root = new THREE.Group();
  const mk = (name: string, parent: THREE.Object3D) => { const b = new THREE.Bone(); b.name = name; parent.add(b); return b; };
  const r = mk('root', root);
  const pelvis = mk('pelvis', r);
  mk('thigh_l', pelvis);
  const s1 = mk('spine_01', pelvis);
  const s2 = mk('spine_02', s1);
  const cl = mk('clavicle_l', s2);
  const hl = mk('hand_l', cl);
  const cr = mk('clavicle_r', s2);
  const hr = mk('hand_r', cr);
  return { root, pelvis, s1, hl, hr };
}

test('bones fall into lower, torso and arm channels', () => {
  const { root } = rig();
  const ch = channelOfBones(root);
  assert.equal(ch.get('thigh_l'), 'lower');
  assert.equal(ch.get('pelvis'), 'lower');
  assert.equal(ch.get('spine_01'), 'torso');
  assert.equal(ch.get('hand_l'), 'armL');
  assert.equal(ch.get('hand_r'), 'armR');
});

// Pack clips key every bone; so do these (the pelvis at height 1).
function clip(name: string, bone: string, x: number, duration = 1) {
  return new THREE.AnimationClip(name, duration, [
    new THREE.VectorKeyframeTrack(`${bone}.position`, [0, duration], [x, 0, 0, x, 0, 0]),
    new THREE.VectorKeyframeTrack('pelvis.position', [0, duration], [0, 1, 0, 0, 1, 0]),
  ]);
}

test('a right-hand swing mirrored onto the left hand moves the left hand, and weights stay whole', () => {
  const { root, hl, hr } = rig();
  const mixer = new THREE.AnimationMixer(root);
  const clips = [
    // Idle keeps both hands at 0; the cross moves the right hand to x = -0.5 (character's right).
    new THREE.AnimationClip('Idle_Loop', 2, [
      new THREE.VectorKeyframeTrack('hand_l.position', [0, 2], [0, 0, 0, 0, 0, 0]),
      new THREE.VectorKeyframeTrack('hand_r.position', [0, 2], [0, 0, 0, 0, 0, 0]),
      new THREE.VectorKeyframeTrack('pelvis.position', [0, 2], [0, 1, 0, 0, 1, 0]),
    ]),
    clip('Sword_Regular_A', 'hand_r', -0.5, 0.5),
    clip('Sword_Idle', 'hand_r', -0.1, 1),
  ];
  const anim = new CharacterAnimator(root, mixer, clips);
  anim.setGear(null, { set: 'torch', hands: 1 });
  anim.setMotion({ speed: 0, dirX: 0, dirZ: 1, grounded: true });
  for (let i = 0; i < 30; i++) { anim.update(1 / 30); mixer.update(1 / 30); }
  assert.ok(Math.abs(hl.position.x) < 1e-6 && Math.abs(hr.position.x) < 1e-6, 'idle hands at rest');
  assert.deepEqual(anim.armSets(), { l: 'torch', r: 'free' });
  // The torch swings with the left hand: the right-hand clip, mirrored.
  const info = anim.attack('left');
  assert.ok(info && info.clip === 'Sword_Regular_A');
  for (let i = 0; i < 6; i++) { anim.update(1 / 30); mixer.update(1 / 30); }
  assert.equal(anim.armSets().l, 'swing');
  assert.ok(hl.position.x > 0.4, `left hand mirrored out to +x, got ${hl.position.x}`);
  assert.ok(Math.abs(hr.position.x) < 1e-6, 'right hand untouched');
  // Pelvis is still fully driven (no blend toward the bind pose).
  assert.ok(Math.abs(root.getObjectByName('pelvis')!.position.y - 1) < 1e-6);
  for (let i = 0; i < 40; i++) { anim.update(1 / 30); mixer.update(1 / 30); }
  assert.ok(Math.abs(hl.position.x) < 1e-3, `back to rest after the swing, got ${hl.position.x}`);
});

test('death holds, revive returns to locomotion', () => {
  const { root, hr } = rig();
  const mixer = new THREE.AnimationMixer(root);
  const anim = new CharacterAnimator(root, mixer, [clip('Idle_Loop', 'hand_r', 0, 2), clip('Death01', 'hand_r', 2, 1)]);
  anim.setMotion({ speed: 0, dirX: 0, dirZ: 1, grounded: true });
  anim.update(0.1); mixer.update(0.1);
  anim.die();
  for (let i = 0; i < 90; i++) { anim.update(1 / 30); mixer.update(1 / 30); }
  assert.ok(Math.abs(hr.position.x - 2) < 1e-6, 'death pose held');
  assert.equal(anim.attack('right'), null, 'the dead do not swing');
  anim.revive();
  for (let i = 0; i < 30; i++) { anim.update(1 / 30); mixer.update(1 / 30); }
  assert.ok(Math.abs(hr.position.x) < 1e-3, `alive again, got ${hr.position.x}`);
});
