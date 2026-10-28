// Bows, arrows and rats (2026-10-28). Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BOWS, bowLimb, heldLeft, nockPoint } from '../items';
import { arrowAt } from '../arrows';
import { STANCES } from '../anim-driver';
import { ratGait } from '../rat-view';

test('a bow: limbs bend back toward the archer, the tips level, the grip at the origin', () => {
  for (const [name, b] of Object.entries(BOWS)) {
    const grip = bowLimb(b, 0);
    assert.equal(grip.y, 0);
    assert.ok(Math.abs(grip.z) < 1e-12);
    const top = bowLimb(b, 1), bot = bowLimb(b, -1);
    assert.ok(Math.abs(top.y - b.half) < 1e-12 && Math.abs(bot.y + b.half) < 1e-12, name);
    assert.ok(top.z < 0 && Math.abs(top.z - bot.z) < 1e-12, name);
  }
  assert.ok(heldLeft('Bow') && heldLeft('ShortBow') && heldLeft('Longbow') && !heldLeft('Sword') && !heldLeft(null));
});

test('the string: follows the drawing hand behind the bow, otherwise at rest', () => {
  const b = BOWS.Bow;
  const rest = nockPoint(b, null);
  assert.equal(rest.drawn, 0);
  assert.ok(Math.abs(rest.z - bowLimb(b, 1).z) < 1e-12);
  // the hand at the cheek, 0.7 m behind the grip: fully drawn
  const full = nockPoint(b, { x: 0.02, y: 0.05, z: -0.72 });
  assert.ok(full.drawn > 0.8 && full.z === -0.72);
  // the hand in front of the bow, or far off to the side: the string stays put
  assert.equal(nockPoint(b, { x: 0, y: 0, z: 0.3 }).drawn, 0);
  assert.equal(nockPoint(b, { x: 0.6, y: 0, z: -0.5 }).drawn, 0);
  assert.equal(nockPoint(b, { x: 0, y: 0, z: -1.5 }).drawn, 0);
});

test('the bow stance: drawn and loosed with the library clips; a heavy shot draws slower', () => {
  const s = STANCES.bow;
  assert.equal(s.idle, 'Bow_Idle_Loop');
  assert.equal(s.light[0].clip, 'Bow_Draw');
  assert.equal(s.light[0].rec, 'Bow_Release');
  assert.ok((s.heavy as any).rate < 1);
});

test('an arrow flies from one point to the other on a shallow arc', () => {
  const a = { x: 0, y: 1, z: 0 }, b = { x: 10, y: 1, z: 0 };
  assert.deepEqual(arrowAt(a, b, 0.5, 0), a);
  assert.deepEqual(arrowAt(a, b, 0.5, 1), b);
  const mid = arrowAt(a, b, 0.5, 0.5);
  assert.ok(Math.abs(mid.x - 5) < 1e-9 && Math.abs(mid.y - 1.5) < 1e-9);
  // clamped
  assert.deepEqual(arrowAt(a, b, 0.5, 2), b);
});

test('a rat walks, then runs, faster as it goes', () => {
  assert.equal(ratGait(0).clip, 'Idle');
  assert.equal(ratGait(0.8).clip, 'Walk');
  assert.equal(ratGait(4).clip, 'Run');
  assert.ok(ratGait(1.5).rate > ratGait(0.6).rate);
  assert.ok(ratGait(100).rate <= 1.8);
});
