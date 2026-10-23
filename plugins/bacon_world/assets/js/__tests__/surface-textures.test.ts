// Unit tests for the material-name -> texture-set tables (surface-textures.ts).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { KIT, MOBS, PROPS, SETS, WEAPONS, surfaceFor } from '../surface-textures';

test('every table entry names a packed set, with a sane scale and strength', () => {
  for (const [table, entries] of Object.entries({ KIT, PROPS, WEAPONS, MOBS })) {
    for (const [name, s] of Object.entries(entries)) {
      assert.ok(SETS[s.set], `${table}.${name} uses unknown set ${s.set}`);
      assert.ok(s.scale > 0.05 && s.scale < 10, `${table}.${name} scale ${s.scale}`);
      const st = s.strength ?? 1;
      assert.ok(st > 0 && st <= 1, `${table}.${name} strength ${st}`);
      if (s.own) assert.ok(s.tint === undefined || /^#[0-9A-F]{6}$/i.test(s.tint), `${table}.${name} tint`);
    }
  }
});

test('set means are linear colours with room to divide by', () => {
  for (const [k, v] of Object.entries(SETS)) {
    assert.equal(v.mean.length, 3);
    for (const c of v.mean) assert.ok(c > 0.005 && c < 1, `${k} mean ${c}`);
    assert.ok(v.rough > 0 && v.rough <= 1 && v.ao > 0 && v.ao <= 1, k);
  }
});

test('surfaceFor picks the family table and ignores Blender suffixes', () => {
  assert.equal(surfaceFor('kit', 'M_Stone')?.set, 'stone_blocks');
  assert.equal(surfaceFor('props', 'M_Stone')?.set, 'rock');
  assert.equal(surfaceFor('weapons', 'W_Leather.001')?.set, 'leather');
  assert.equal(surfaceFor('props', 'M_Glass'), null, 'glass stays plain');
  assert.equal(surfaceFor('weapons', 'W_Fire'), null, 'emissive stays plain');
  assert.equal(surfaceFor('mobs', 'Skel_Glow'), null);
});
