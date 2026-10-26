// lockLossWasEsc (controls-math.ts): a pointer lock the browser drops is the player's Esc only
// when the window kept its focus (2026-10-26: every screenshot opened the game menu).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lockLossWasEsc } from '../controls-math';

const base = { lostAtMs: 10_000, nowMs: 10_160, lastAwayMs: -1e9, lastPrintMs: -1e9, hidden: false, focused: true };

test('a lock lost with the window still focused is Esc', () => {
  assert.equal(lockLossWasEsc(base), true);
});

test('a screenshot tool or another window taking focus is not Esc', () => {
  assert.equal(lockLossWasEsc({ ...base, focused: false }), false);
  assert.equal(lockLossWasEsc({ ...base, lastAwayMs: 10_020 }), false, 'blur just after');
  assert.equal(lockLossWasEsc({ ...base, lastAwayMs: 9_900 }), false, 'blur just before');
  assert.equal(lockLossWasEsc({ ...base, hidden: true }), false, 'tab hidden');
});

test('PrintScreen in the last second and a half is not Esc', () => {
  assert.equal(lockLossWasEsc({ ...base, lastPrintMs: 9_000 }), false);
  assert.equal(lockLossWasEsc({ ...base, lastPrintMs: 5_000 }), true, 'long ago');
});

test('a focus lost long before (and come back) does not count', () => {
  assert.equal(lockLossWasEsc({ ...base, lastAwayMs: 2_000 }), true);
});
