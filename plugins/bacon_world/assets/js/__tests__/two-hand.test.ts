// Unit tests for the weapon-driven two-handed poses (two-hand.ts). Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TWO_HAND_SETS, swingPose, twoHandDuration, twoHandPose } from '../two-hand';

const len = (v: number[]) => Math.hypot(v[0], v[1], v[2]);

test('every set has a guard, light swings and a heavy one, each starting and ending at the guard', () => {
  for (const [name, set] of Object.entries(TWO_HAND_SETS)) {
    assert.ok(set.light.length > 0, name);
    for (const s of [...set.light, set.heavy]) {
      const sw = set.swings[s];
      assert.ok(sw, `${name}.${s}`);
      assert.ok(sw.hit > 0 && sw.hit < 1, `${name}.${s} hit`);
      for (const x of [0, 1]) swingPose(sw, x).grip.forEach((g, i) => assert.ok(Math.abs(g - set.guard.grip[i]) < 1e-9));
      for (let i = 1; i < sw.keys.length; i++) assert.ok(sw.keys[i].at > sw.keys[i - 1].at, `${name}.${s} keys in order`);
    }
  }
});

test('poses in between stay sane: unit directions, the edge across the haft, grips within reach', () => {
  for (const set of Object.values(TWO_HAND_SETS)) {
    for (const sw of Object.values(set.swings)) {
      for (let x = 0; x <= 1.0001; x += 0.05) {
        const p = swingPose(sw, x);
        assert.ok(Math.abs(len(p.dir) - 1) < 1e-6);
        assert.ok(Math.abs(len(p.edge) - 1) < 1e-6);
        // never along the haft (the hand's frame would be undefined)
        assert.ok(Math.abs(p.dir[0] * p.edge[0] + p.dir[1] * p.edge[1] + p.dir[2] * p.edge[2]) < 0.9);
        // within about an arm's reach of the chest (units of the pelvis-to-neck height)
        assert.ok(Math.hypot(p.grip[0], p.grip[1] - 1, p.grip[2]) < 2.2);
      }
    }
  }
});

test('the guard when not swinging; swing timing follows the weapon', () => {
  twoHandPose('two_hand', null)!.grip.forEach((g, i) => assert.ok(Math.abs(g - TWO_HAND_SETS.two_hand.guard.grip[i]) < 1e-9));
  assert.equal(twoHandPose('unarmed', null), null);
  assert.ok(twoHandDuration(1.6, true) > twoHandDuration(1.6, false));
  assert.ok(twoHandDuration(9, false) <= 0.95 && twoHandDuration(0.1, false) >= 0.55);
});
