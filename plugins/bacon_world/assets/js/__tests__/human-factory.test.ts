// Unit tests for the parts of human-factory.ts that need no GPU or files. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { HumanFactory } from '../human-factory';

const list = [
  { id: 'Ponytail', label: 'Ponytail', file: 'Hair_Female_Ponytail.glb' },
  { id: 'Lob', label: 'Inverted bob', file: 'Hair_Female_Lob.glb' },
];

test('a style is found by its id, or by a retired id that maps to it', () => {
  const f = new HumanFactory({});
  assert.equal(f.findStyle(list, 'Lob')?.file, 'Hair_Female_Lob.glb');
  assert.equal(f.findStyle(list, 'HighPonytail', { HighPonytail: 'Ponytail' })?.id, 'Ponytail');
  assert.equal(f.findStyle(list, 'Gone', { Gone: 'Missing' }), null);
  assert.equal(f.findStyle(list, 'HighPonytail'), null);
  assert.equal(f.findStyle(list, 'none', { none: 'Lob' }), null);
});

test('the manifest aliases reach styles()', () => {
  const f = new HumanFactory({ hair: { Female: { hair: list, aliases: { TopBun: 'Ponytail' } } } });
  const st = f.styles('female');
  assert.equal(st.hair.length, 2);
  assert.deepEqual(st.facial, []);
  assert.equal(st.aliases.TopBun, 'Ponytail');
  assert.deepEqual(f.styles('male').aliases, {});
});

function quadStrip(regions: number[]): THREE.BufferGeometry {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(new Array(regions.length * 3).fill(0), 3));
  g.setAttribute('_region', new THREE.Float32BufferAttribute(regions, 1));
  return g;
}

test('hiding regions drops only triangles whose three corners are all hidden', () => {
  const g = quadStrip([0, 4, 4, 4, 7]);
  g.setIndex([1, 2, 3, 0, 1, 2, 2, 3, 4]);
  const f = new HumanFactory({});
  const a = f.filteredGeometry(g, [4]);
  assert.deepEqual(Array.from(a.getIndex()!.array), [0, 1, 2, 2, 3, 4]);
  assert.equal(a.getAttribute('position'), g.getAttribute('position'), 'attributes are shared, not copied');
  assert.equal(f.filteredGeometry(g, [4, 4]), a, 'cached per hidden set');
  assert.equal(f.filteredGeometry(g, []), g, 'nothing hidden: the template itself');
  assert.equal(f.filteredGeometry(g, [9]), g, 'nothing matched: the template itself');
  assert.deepEqual(Array.from(f.filteredGeometry(g, [7, 4]).getIndex()!.array), [0, 1, 2]);
});

test('material groups keep their own triangles after hiding', () => {
  const g = quadStrip([4, 4, 4, 0, 0, 0]);
  g.setIndex([0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5]);
  g.addGroup(0, 6, 0);
  g.addGroup(6, 6, 1);
  const a = new HumanFactory({}).filteredGeometry(g, [4]);
  assert.deepEqual(Array.from(a.getIndex()!.array), [3, 4, 5, 3, 4, 5]);
  assert.deepEqual(a.groups.map((x) => [x.start, x.count, x.materialIndex]), [[0, 3, 0], [3, 3, 1]]);
});
