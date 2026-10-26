import test from 'node:test';
import assert from 'node:assert/strict';
import { isEmptyBlock, shrinkColumns, Col, ColBlock } from '../block_editor_columns';

let n = 0;
const id = () => `n${++n}`;
const text = (content: string): ColBlock => ({ id: id(), type: 'text', content });
const col = (...blocks: ColBlock[]): Col => ({ id: id(), width: '10%', blocks });
const contents = (c: Col) => c.blocks.map((b) => b.content);

test('empty text blocks are empty; anything with content is not', () => {
  for (const empty of ['', '<p></p>', '<p><br></p>', '<p>&nbsp;</p>', '  ', '<div> </div>']) {
    assert.equal(isEmptyBlock(text(empty)), true, JSON.stringify(empty));
  }
  assert.equal(isEmptyBlock(text('<p>words</p>')), false);
  assert.equal(isEmptyBlock(text('<img src="a.png">')), false);
  assert.equal(isEmptyBlock(text('<hr>')), false);
  assert.equal(isEmptyBlock({ id: 'x', type: 'divider', content: '' }), false);
  assert.equal(isEmptyBlock({ id: 'x', type: 'image', content: '' }), false);
  assert.equal(isEmptyBlock({ id: 'x', type: 'text', content: '', media: [{}] }), false);
});

test('8 columns to 4 with nothing typed leaves four clean columns (the reported bug)', () => {
  const cols = Array.from({ length: 8 }, () => col(text('')));
  const out = shrinkColumns(cols, 4, id);
  assert.equal(out.length, 4);
  for (const c of out) assert.deepEqual(contents(c), ['']);
});

test('blocks with content from dropped columns move to the first column, in order', () => {
  const cols = [col(text('<p>a</p>')), col(text('<p>b</p>')), col(text('<p>c</p>'), text('<p>d</p>')), col(text(''))];
  const out = shrinkColumns(cols, 2, id);
  assert.deepEqual(contents(out[0]), ['<p>a</p>', '<p>c</p>', '<p>d</p>']);
  assert.deepEqual(contents(out[1]), ['<p>b</p>']);
});

test('placeholders in dropped columns are discarded even beside real content', () => {
  const cols = [col(text('<p>a</p>')), col(text('')), col(text(''), text('<p>keep</p>'), text('')), col(text(''))];
  const out = shrinkColumns(cols, 2, id);
  assert.deepEqual(contents(out[0]), ['<p>a</p>', '<p>keep</p>']);
  assert.deepEqual(contents(out[1]), ['']);
});

test("an empty first column gives up its placeholder to the moved blocks", () => {
  const out = shrinkColumns([col(text('')), col(text('<p>x</p>'))], 1, id);
  assert.deepEqual(contents(out[0]), ['<p>x</p>']);
});

test('non-text blocks always move', () => {
  const divider: ColBlock = { id: id(), type: 'divider', content: '' };
  const out = shrinkColumns([col(text('<p>a</p>')), col(divider)], 1, id);
  assert.equal(out[0].blocks.length, 2);
  assert.equal(out[0].blocks[1].type, 'divider');
});

test('a kept column that is somehow empty gets a placeholder to type in', () => {
  const out = shrinkColumns([col(), col(text(''))], 2, id);
  assert.deepEqual(contents(out[0]), ['']);
});

test('the input columns beyond the new count are not returned', () => {
  const cols = [col(text('1')), col(text('2')), col(text('3'))];
  const out = shrinkColumns(cols, 2, id);
  assert.equal(out.length, 2);
  assert.equal(out[0].id, cols[0].id);
});
