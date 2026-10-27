import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergePage, debounce } from '../block_editor_library';

const img = (n: number) => ({ url: `/uploads/public/pages/x/${n}.png`, filename: `${n}.png` });

test('mergePage appends new pictures and skips ones already shown', () => {
  const merged = mergePage([img(1), img(2)], [img(2), img(3)]);
  assert.deepEqual(merged.map((i) => i.filename), ['1.png', '2.png', '3.png']);
});

test('mergePage leaves the shown list alone when the page is empty', () => {
  assert.deepEqual(mergePage([img(1)], []), [img(1)]);
});

test('debounce runs once, with the last arguments', async () => {
  const calls: number[] = [];
  const run = debounce((n: number) => calls.push(n), 20);
  run(1);
  run(2);
  run(3);
  await new Promise((resolve) => setTimeout(resolve, 60));
  assert.deepEqual(calls, [3]);
});
