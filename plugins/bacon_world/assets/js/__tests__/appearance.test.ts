// Unit tests for appearance.ts (the client side of BaconWorld.Appearance). Run with
// __tests__/run.sh (esbuild + node --test), in a throwaway container.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SHAPES,
  appearanceKey,
  bodyFromModelPath,
  browColor,
  defaultAppearance,
  isHumanModel,
  morphWeights,
  normalizeAppearance,
  randomAppearance,
  shade,
} from '../appearance';

test('defaults are already normal', () => {
  for (const b of ['male', 'female'] as const) {
    const d = defaultAppearance(b);
    assert.deepEqual(normalizeAppearance(d), d);
  }
});

test('normalise clamps, drops junk and falls back per field', () => {
  const a = normalizeAppearance({
    body: 'female',
    height: 3,
    shape: { weight: -7, muscle: '0.5', evil: 1, chest: 0.123456 },
    skin: 'red',
    eyes: '#00ff00',
    hair: { style: '../../etc', color: '#abcdef' },
    facial: { style: 'FullBeard' },
    outfit: { top: { id: 'Top_Armor', main: '#123456' } },
    extra: true,
  });
  assert.equal(a.height, 1.08);
  assert.equal(a.shape.weight, -1);
  assert.equal(a.shape.muscle, 0.5);
  assert.equal(a.shape.chest, 0.123);
  assert.equal((a.shape as any).evil, undefined);
  assert.equal((a as any).extra, undefined);
  assert.equal(a.skin, '#C68E6E');
  assert.equal(a.eyes, '#00FF00');
  assert.deepEqual(a.hair, { style: 'Lob', color: '#ABCDEF' });
  assert.equal(a.facial.style, 'none');
  assert.equal((a as any).outfit, undefined, 'clothes are items now: an old outfit is dropped');
});

test('body fallbacks and model paths', () => {
  assert.equal(normalizeAppearance(null, 'female').body, 'female');
  assert.equal(normalizeAppearance({ body: 'robot' }).body, 'male');
  // the male has the chest size (his pectorals), waist, glute lift and limbs; the chest's
  // shaping sliders are hers only and stay 0 on him
  assert.equal(normalizeAppearance({ body: 'male', shape: { chest: 1 } }).shape.chest, 1);
  assert.equal(normalizeAppearance({ body: 'male', shape: { arms: 1, chest_shape: -1 } }).shape.arms, 1);
  assert.equal(normalizeAppearance({ body: 'male', shape: { arms: 1, chest_shape: -1 } }).shape.chest_shape, 0);
  assert.equal(morphWeights(normalizeAppearance({ body: 'male', shape: { waist: -0.5 } })).Waist_Narrow, 0.5);
  assert.equal(normalizeAppearance({ body: 'female', shape: { arms: 0.4, chest_shape: -3 } }).shape.chest_shape, -1);
  assert.equal(morphWeights(normalizeAppearance({ body: 'female', shape: { chest_shape: -0.5 } })).Chest_Round, 0.5);
  assert.equal(bodyFromModelPath('/models/Humans/Female.glb'), 'female');
  assert.equal(bodyFromModelPath('/models/Humans/Male.glb'), 'male');
  assert.ok(isHumanModel('/models/Humans/Male.glb'));
  assert.ok(!isHumanModel('/models/heroes/runner.glb'));
});

test('morph weights split bipolar sliders', () => {
  const a = defaultAppearance('female');
  a.shape.weight = -0.4;
  a.shape.chest = 0.7;
  a.shape.muscle = 0.2;
  const w = morphWeights(a);
  assert.equal(w.Weight_Thin, 0.4);
  assert.equal(w.Weight_Heavy, 0);
  assert.equal(w.Breasts_Large, 0.7);
  assert.equal(w.Breasts_Small, 0);
  assert.equal(w.Muscle, 0.2);
  const m = morphWeights(defaultAppearance('male'));
  assert.equal(m.Breasts_Large, 0, 'his chest slider drives the pectorals');
  assert.equal(m.Chest_Perky, undefined, 'the chest shaping sliders are hers only');
});

test('random looks are valid and reproducible', () => {
  const a = randomAppearance('male', ['Buzz', 'Afro'], ['Goatee'], 42);
  const b = randomAppearance('male', ['Buzz', 'Afro'], ['Goatee'], 42);
  assert.equal(appearanceKey(a), appearanceKey(b));
  assert.deepEqual(normalizeAppearance(a), a);
  assert.ok(['Buzz', 'Afro'].includes(a.hair.style));
  for (const s of SHAPES) assert.ok(a.shape[s.key] >= s.min && a.shape[s.key] <= s.max);
  const f = randomAppearance('female', [], ['Goatee'], 7);
  assert.equal(f.facial.style, 'none');
});

test('shades and brow colour', () => {
  assert.equal(shade('#808080', 0.5), '#404040');
  assert.equal(shade('#FFFFFF', 2), '#FFFFFF');
  const a = defaultAppearance('male');
  assert.equal(browColor(a), shade(a.hair.color, 0.85));
  a.brows = '#112233';
  assert.equal(browColor(a), '#112233');
});

test('shoulders: the male goes narrower than his look (Shoulders_Narrow); the female stays 0..1', () => {
  const m = normalizeAppearance({ body: 'male', shape: { shoulders: -1 } });
  assert.equal(m.shape.shoulders, -1);
  assert.equal(morphWeights(m).Shoulders_Narrow, 1);
  assert.equal(morphWeights(m).Shoulders_Broad, 0);
  const f = normalizeAppearance({ body: 'female', shape: { shoulders: -1 } });
  assert.equal(f.shape.shoulders, 0);
});
