// Unit tests for keeping dragged windows on screen (window-drag.ts).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { clampPos } from '../window-drag';

test('a window stays on screen, with at least a strip of it showing', () => {
  assert.deepEqual(clampPos({ x: 100, y: 50 }, 200, 100, 1000, 800), { x: 100, y: 50 }, 'inside: unchanged');
  assert.deepEqual(clampPos({ x: 5000, y: 5000 }, 200, 100, 1000, 800), { x: 960, y: 760 }, 'off the bottom right: 40 px left showing');
  assert.deepEqual(clampPos({ x: -5000, y: -50 }, 200, 100, 1000, 800), { x: -160, y: 0 }, 'off the left: 40 px showing; never above the top');
});
