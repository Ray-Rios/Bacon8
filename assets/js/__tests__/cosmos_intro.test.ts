// The cosmic backgrounds' and the front door's small pure pieces (2026-10-28).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flatBackground, lean } from '../background_updater';
import { inView } from '../intro_reveal';

test('a flat background is a gradient or a colour, with defaults', () => {
  assert.equal(flatBackground('gradient', { gradient_start: '#111111', gradient_end: '#222222' }), 'linear-gradient(135deg, #111111, #222222)');
  assert.equal(flatBackground('gradient'), 'linear-gradient(135deg, #3B82F6, #9333EA)');
  assert.equal(flatBackground('solid', { solid_color: '#123456' }), '#123456');
  assert.equal(flatBackground('solid'), '#0F172A');
});

test('the pointer leans the stars from -1 to 1, clamped', () => {
  assert.deepEqual(lean(500, 400, 1000, 800), [0, 0]);
  assert.deepEqual(lean(0, 0, 1000, 800), [-1, -1]);
  assert.deepEqual(lean(1000, 800, 1000, 800), [1, 1]);
  assert.deepEqual(lean(5000, -50, 1000, 800), [1, -1]);
  assert.deepEqual(lean(10, 10, 0, 0), [1, 1]); // no division by zero
});

test('a section counts as in view once its top is above the last 8% of the window', () => {
  assert.equal(inView(100, 400, 800), true);
  assert.equal(inView(760, 1000, 800), false); // only in the bottom strip
  assert.equal(inView(-500, -10, 800), false); // scrolled past
  assert.equal(inView(-100, 50, 800), true);
});
