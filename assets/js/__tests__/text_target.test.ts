// The camera controller must not swallow presses on text (that kills text selection).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { isTextTarget } from '../threejs/controls/text-target';

const text = (t: string) => ({ nodeType: 3, textContent: t });
const el = (tagName: string, childNodes: any[] = [], closest?: string) => ({
  tagName,
  childNodes,
  closest: (sel: string) => (closest && sel.includes(closest) ? {} : null)
});

test('a paragraph and the words in a div are text', () => {
  assert.equal(isTextTarget(el('P')), true);
  assert.equal(isTextTarget(el('DIV', [text('b8fb_token')])), true);
});

test('anything inside a content panel is left alone', () => {
  assert.equal(isTextTarget(el('DIV', [], '.auth-glass-panel')), true);
  assert.equal(isTextTarget(el('DIV', [], '.desktop-window')), true);
});

test('the bare background still turns the camera', () => {
  assert.equal(isTextTarget(el('MAIN')), false);
  assert.equal(isTextTarget(el('DIV', [text('   \n ')])), false);
  assert.equal(isTextTarget(el('CANVAS')), false);
  assert.equal(isTextTarget(null), false);
});
