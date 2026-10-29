// The page builder's data operations (assets/js/page_builder/model.ts) and starters.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as M from '../page_builder/model';
import { STARTERS, startersFor } from '../page_builder/templates';

const ids = (doc: M.Doc) => doc.rows.map((r) => r.columns.map((c) => c.blocks.map((b) => b.content)));

test('old saves are read as they are: block JSON, HTML, nothing', () => {
  const saved = JSON.stringify({ rows: [{ id: 'r1', columns: [{ id: 'c1', width: 'full', blocks: [{ id: 'x', type: 'text', content: '<p>Hi</p>' }] }] }], version: 1 });
  const d = M.parseDoc(saved);
  assert.equal(d.rows[0].columns[0].blocks[0].content, '<p>Hi</p>');
  assert.equal(d.rows[0].id, 'r1');
  const html = M.parseDoc('<p>Old page</p>');
  assert.equal(html.rows[0].columns[0].blocks[0].type, 'text');
  assert.equal(html.rows[0].columns[0].blocks[0].content, '<p>Old page</p>');
  assert.deepEqual(M.parseDoc('').rows, []);
  // missing ids and widths are filled in, nothing else touched
  const bare = M.parseDoc(JSON.stringify({ rows: [{ columns: [{ blocks: [{ type: 'heading', content: 'T', settings: { level: 3 } }] }], settings: { gap: 'x' } }] }));
  assert.ok(bare.rows[0].id && bare.rows[0].columns[0].id && bare.rows[0].columns[0].blocks[0].id);
  assert.equal(bare.rows[0].columns[0].width, 'full');
  assert.equal(bare.rows[0].settings!.gap, 'x');
  assert.equal(bare.rows[0].columns[0].blocks[0].settings!.level, 3);
});

test('an empty page is one with nothing typed in it', () => {
  assert.equal(M.isEmpty(M.parseDoc('')), true);
  assert.equal(M.isEmpty({ rows: [M.row([M.textBlock('<p><br></p>')])], version: 1 }), true);
  assert.equal(M.isEmpty({ rows: [M.row([M.textBlock('<p>a</p>')])], version: 1 }), false);
  assert.equal(M.isEmpty({ rows: [M.row([M.block('divider')])], version: 1 }), false);
});

test('a layout change never loses a block', () => {
  let d: M.Doc = { rows: [M.row([], {}, [[M.textBlock('a')], [M.textBlock('b')], [M.textBlock('c')]])], version: 1 };
  const id = d.rows[0].id;
  d = M.setLayout(d, id, '1-2');
  assert.deepEqual(ids(d), [[['a'], ['b', 'c']]]);
  assert.deepEqual(d.rows[0].columns.map((c) => c.width), ['33.33%', '66.67%']);
  assert.equal(M.layoutOf(d.rows[0]), '1-2');
  d = M.setLayout(d, id, '1');
  assert.deepEqual(ids(d), [[['a', 'b', 'c']]]);
  assert.equal(d.rows[0].columns[0].width, 'full');
  d = M.setLayout(d, id, '1-1-1-1');
  assert.equal(d.rows[0].columns.length, 4);
  assert.equal(M.layoutOf(d.rows[0]), '1-1-1-1');
});

test('resizing two columns keeps their total and a sensible minimum', () => {
  let d: M.Doc = { rows: [M.row([], {}, [[], []])], version: 1 };
  d = M.resizeColumns(d, d.rows[0].id, 0, 70);
  assert.deepEqual(d.rows[0].columns.map((c) => c.width), ['70%', '30%']);
  d = M.resizeColumns(d, d.rows[0].id, 0, 99);
  assert.deepEqual(d.rows[0].columns.map((c) => c.width), ['88%', '12%']);
  assert.equal(M.layoutOf(d.rows[0]), null);
  assert.equal(M.widthNumber('1/2', 2), 50);
});

test('blocks are added, moved, copied and removed; the old doc is never changed', () => {
  const a = M.textBlock('a');
  const b = M.textBlock('b');
  const r1 = M.row([a, b]);
  const r2 = M.row([M.textBlock('c')]);
  const d0: M.Doc = { rows: [r1, r2], version: 1 };
  const before = JSON.stringify(d0);
  const d1 = M.moveBlock(d0, a.id, 1);
  assert.deepEqual(ids(d1), [[['b', 'a']], [['c']]]);
  const d2 = M.moveBlock(d1, a.id, 1); // off the bottom of its column: to the next row's top
  assert.deepEqual(ids(d2), [[['b']], [['a', 'c']]]);
  const d3 = M.duplicateBlock(d2, a.id);
  assert.deepEqual(ids(d3), [[['b']], [['a', 'a', 'c']]]);
  assert.notEqual(d3.rows[1].columns[0].blocks[1].id, a.id);
  const d4 = M.removeBlock(d3, b.id);
  assert.deepEqual(ids(M.dropEmptyRows(d4)), [[['a', 'a', 'c']]]);
  const d5 = M.moveBlockTo(d0, a.id, r2.columns[0].id, 1);
  assert.deepEqual(ids(d5), [[['b']], [['c', 'a']]]);
  const d6 = M.moveBlockTo(d0, a.id, r1.columns[0].id, 2); // to the end of its own column
  assert.deepEqual(ids(d6), [[['b', 'a']], [['c']]]);
  assert.equal(JSON.stringify(d0), before);
});

test('rows move, copy and take settings', () => {
  const r1 = M.row([M.textBlock('1')]);
  const r2 = M.row([M.textBlock('2')]);
  const r3 = M.row([M.textBlock('3')]);
  const d: M.Doc = { rows: [r1, r2, r3], version: 1 };
  assert.deepEqual(ids(M.moveRow(d, r3.id, -1)), [[['1']], [['3']], [['2']]]);
  assert.equal(M.moveRow(d, r1.id, -1), d);
  assert.deepEqual(ids(M.moveRowTo(d, r1.id, 3)), [[['2']], [['3']], [['1']]]);
  assert.deepEqual(ids(M.moveRowTo(d, r3.id, 0)), [[['3']], [['1']], [['2']]]);
  const dup = M.duplicateRow(d, r2.id);
  assert.equal(dup.rows.length, 4);
  assert.notEqual(dup.rows[2].id, r2.id);
  assert.notEqual(dup.rows[2].columns[0].blocks[0].id, r2.columns[0].blocks[0].id);
  const s = M.setRowSettings(d, r1.id, { width: 'wide', background: 'glass' });
  assert.deepEqual(s.rows[0].settings, { width: 'wide', background: 'glass' });
  assert.equal(M.row([]).settings!.width, 'normal');
  assert.deepEqual(ids(M.removeRow(d, r2.id)), [[['1']], [['3']]]);
});

test('undo and redo walk back and forth', () => {
  const h = new M.History();
  const d0: M.Doc = { rows: [], version: 1 };
  const d1 = M.insertRow(d0, 0, M.row([M.textBlock('x')]));
  h.record(d0);
  const d2 = M.insertRow(d1, 1, M.row([M.textBlock('y')]));
  h.record(d1);
  assert.equal(h.canUndo, true);
  const u1 = h.undo(d2)!;
  assert.equal(u1.rows.length, 1);
  const u2 = h.undo(u1)!;
  assert.equal(u2.rows.length, 0);
  assert.equal(h.undo(u2), null);
  const r1 = h.redo(u2)!;
  assert.equal(r1.rows.length, 1);
  h.record(r1); // a new change drops what could be redone
  assert.equal(h.canRedo, false);
});

test('typing shortcuts and safe links', () => {
  assert.deepEqual(M.shortcutFor('# '), { command: 'formatBlock', value: 'h2', strip: 2 });
  assert.deepEqual(M.shortcutFor('## '), { command: 'formatBlock', value: 'h3', strip: 3 });
  assert.equal(M.shortcutFor('- ')!.command, 'insertUnorderedList');
  assert.equal(M.shortcutFor('1. ')!.command, 'insertOrderedList');
  assert.equal(M.shortcutFor('> ')!.value, 'blockquote');
  assert.equal(M.shortcutFor('#x'), null);
  assert.equal(M.safeUrl('https://a.b/c'), 'https://a.b/c');
  assert.equal(M.safeUrl('/store'), '/store');
  assert.equal(M.safeUrl('#top'), '#top');
  assert.equal(M.safeUrl('mailto:x@y.z'), 'mailto:x@y.z');
  assert.equal(M.safeUrl('bacon8.net/games'), 'https://bacon8.net/games');
  assert.equal(M.safeUrl('javascript:alert(1)'), '');
  assert.equal(M.safeUrl('//evil.example'), '');
  assert.equal(M.safeUrl('data:text/html,x'), '');
  assert.equal(M.pasteToHtml('a <b>\n\nnext\nline'), '<p>a &lt;b&gt;</p><p>next<br>line</p>');
});

test('every starter is a valid, non-empty doc of known blocks', () => {
  const known = Object.keys(M.DEFAULTS);
  for (const s of STARTERS) {
    const d = M.normalise(s.make());
    assert.ok(d.rows.length > 0, s.id);
    for (const r of d.rows) for (const c of r.columns) for (const b of c.blocks) assert.ok(known.includes(b.type), `${s.id}: ${b.type}`);
    // a round trip through JSON keeps it
    assert.deepEqual(M.parseDoc(JSON.stringify(d)), d);
  }
  assert.ok(startersFor('page').some((s) => s.id === 'landing'));
  assert.ok(!startersFor('page').some((s) => s.id === 'patch'));
  assert.ok(startersFor('post').some((s) => s.id === 'patch'));
});
