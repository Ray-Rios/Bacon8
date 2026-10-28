// <b8-spin>'s sheets and frames (2026-10-28). Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { framePos, sheetFor } from '../store_spin';

test('the smallest sheet that is sharp enough', () => {
  assert.equal(sheetFor(90), 128);
  assert.equal(sheetFor(128), 128);
  assert.equal(sheetFor(200), 224);
  assert.equal(sheetFor(640), 320);
});

test('frames walk the 8 x 6 sheet and wrap', () => {
  assert.equal(framePos(0), '0% 0%');
  assert.equal(framePos(7), '100% 0%');
  assert.equal(framePos(8), '0% 20%');
  assert.equal(framePos(47), '100% 100%');
  assert.equal(framePos(48), '0% 0%');
  assert.equal(framePos(-1), '100% 100%');
});
