// Unit tests for garment-parts.ts: cover sets, masks and triangle filtering, material metadata.
// Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { coverMask, covered, decodeCover, dilateCover, keepTriangles, parseMeta, roleColor } from '../garment-parts';

// encode like b8_garments.cover_set: alternating runs (empty first) as base-128 varints, base64
function encode(bits: number[]): string {
  const runs: number[] = [];
  let cur = 0, n = 0;
  for (const b of bits) {
    if (b === cur) n++;
    else {
      runs.push(n);
      cur = b;
      n = 1;
    }
  }
  runs.push(n);
  const bytes: number[] = [];
  for (let r of runs) {
    for (;;) {
      const b = r & 0x7f;
      r = Math.floor(r / 128);
      if (r) bytes.push(b | 0x80);
      else {
        bytes.push(b);
        break;
      }
    }
  }
  return Buffer.from(bytes).toString('base64');
}

test('a cover set decodes and answers point queries', () => {
  // 2 x 2 x 2 cells of 0.5 m from the origin; cells (1,0,1) and (1,1,1) occupied
  const bits = [0, 0, 0, 0, 0, 1, 0, 1];
  const c = decodeCover({ o: [0, 0, 0], c: 0.5, d: [2, 2, 2], rle: encode(bits) })!;
  assert.ok(c);
  assert.equal(covered(c, 0.75, 0.25, 0.75), true);
  assert.equal(covered(c, 0.75, 0.75, 0.75), true);
  assert.equal(covered(c, 0.25, 0.25, 0.25), false);
  assert.equal(covered(c, -1, 0, 0), false, 'outside the grid is never covered');
  assert.equal(decodeCover(null), null);
  assert.equal(decodeCover({ o: [0, 0, 0], c: 1, d: [1, 1], rle: 'AA==' } as any), null);
});

test('long runs use multi-byte varints', () => {
  const bits = new Array(300).fill(0).concat(new Array(200).fill(1));
  const c = decodeCover({ o: [0, 0, 0], c: 1, d: [500, 1, 1], rle: encode(bits) })!;
  assert.equal(covered(c, 299.5, 0.5, 0.5), false);
  assert.equal(covered(c, 300.5, 0.5, 0.5), true);
  assert.equal(covered(c, 499.5, 0.5, 0.5), true);
});

test('masks and triangle filtering: all three corners covered, or all in hidden regions', () => {
  const c = decodeCover({ o: [0, 0, 0], c: 1, d: [2, 1, 1], rle: encode([0, 1]) })!;
  const pts = [0.5, 0.5, 0.5, 1.5, 0.5, 0.5, 1.6, 0.5, 0.5, 1.7, 0.5, 0.5];
  const mask = coverMask(pts, 4, [c]);
  assert.deepEqual([...mask], [0, 1, 1, 1]);
  const index = [0, 1, 2, 1, 2, 3];
  const r = keepTriangles(index, [{ start: 0, count: 6 }], null, new Set(), mask)!;
  assert.deepEqual(r.index, [0, 1, 2]);
  assert.equal(keepTriangles(index, [{ start: 0, count: 6 }], null, new Set(), new Uint8Array(4)), null);
  const reg = (v: number) => (v === 0 ? 5 : 6);
  const r2 = keepTriangles(index, [{ start: 0, count: 6 }], reg, new Set([6]), null)!;
  assert.deepEqual(r2.index, [0, 1, 2]);
});

test('material metadata: roles take the item colour, natural fabrics and metal stay white', () => {
  assert.deepEqual(parseMeta('{"role":"trim","fabric":"satin"}'), { role: 'trim', fabric: 'satin' });
  assert.equal(parseMeta('not json'), null);
  const colors = { main: '#112233', trim: '#445566' };
  assert.equal(roleColor({ role: 'trim' }, colors), '#445566');
  assert.equal(roleColor({ role: 'accent' }, colors), '#112233');
  assert.equal(roleColor({ role: 'metal' }, colors), '#FFFFFF');
  assert.equal(roleColor({ role: 'metal' }, { ...colors, metal: '#C9CED6' }), '#C9CED6');
  assert.equal(roleColor({ role: 'main', natural: true }, {}), '#FFFFFF');
});

test('a grown cover reaches the cells around the occupied ones', () => {
  const bits = new Array(27).fill(0);
  bits[13] = 1; // the centre of a 3x3x3 grid
  const c = decodeCover({ o: [0, 0, 0], c: 1, d: [3, 3, 3], rle: encode(bits) })!;
  const g = dilateCover(c, 1);
  assert.equal([...g.bits].reduce((a, b) => a + b, 0), 27);
  assert.equal([...c.bits].reduce((a, b) => a + b, 0), 1, 'the original is untouched');
});
