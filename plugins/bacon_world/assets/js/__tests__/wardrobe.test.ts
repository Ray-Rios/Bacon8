// Unit tests for wardrobe.ts: what a body shows for its gear, hidden regions, the bones the
// morphs move, the relaxed hand. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STARTER_GEAR, approach, boneOffsets, designFiles, gearKey, hiddenFor, relaxedCurl, relaxedSpread, wornGarments } from '../wardrobe';

const CATALOG: Record<string, any> = {
  linen_bikini_top: { slots: ['under_top'], wear: { female: { garment: 'Under_Top_Contour', design: 'classic' }, male: null }, colors: { main: '#EAE0C8' } },
  linen_bikini_bottom: { slots: ['under_bottom'], wear: { female: { garment: 'Under_Bottom', design: 'classic' }, male: { garment: 'Bottom_Shorts' } }, colors: { main: '#EAE0C8' } },
  cloth_trousers: { slots: ['legs'], wear: { female: { garment: 'Bottom_Pants', design: 'pants' }, male: { garment: 'Bottom_Pants' } }, colors: { main: '#4A4F57' } },
  cloth_shorts: { slots: ['legs'], wear: { female: { garment: 'Bottom_Shorts', design: 'shorts' }, male: { garment: 'Bottom_Shorts' } }, colors: { main: '#1E2E5C' } },
  cloth_tunic: { slots: ['chest'], wear: { female: { garment: 'Top_Tee' }, male: { garment: 'Top_Tee' } }, colors: { main: '#8A6A4A', trim: '#5C4630' } },
  rusty_dagger: { slots: ['main', 'off'] },
};
const item = (id: string) => CATALOG[id] || null;

test('the starter underwear: two design garments on her, his shorts on him', () => {
  const f = wornGarments('female', STARTER_GEAR, item);
  assert.deepEqual(f.map((g) => [g.slot, g.garment, g.design]), [['under_top', 'Under_Top_Contour', 'classic'], ['under_bottom', 'Under_Bottom', 'classic']]);
  const m = wornGarments('male', STARTER_GEAR, item);
  assert.deepEqual(m.map((g) => g.garment), ['Bottom_Shorts']);
});

test('inner layers first; hands and unknown items ignored', () => {
  const g = wornGarments('female', { ...STARTER_GEAR, main: 'rusty_dagger', chest: 'cloth_tunic', legs: 'cloth_trousers', feet: 'no_such_boots' }, item);
  assert.deepEqual(g.map((x) => x.garment), ['Under_Top_Contour', 'Under_Bottom', 'Top_Tee', 'Bottom_Pants']);
  assert.equal(g[2].colors.trim, '#5C4630');
});

test('the outer item wins a garment both would show (his underwear under his shorts)', () => {
  const g = wornGarments('male', { ...STARTER_GEAR, legs: 'cloth_shorts' }, item);
  assert.deepEqual(g.map((x) => [x.slot, x.garment]), [['legs', 'Bottom_Shorts']]);
});

test('hidden regions are the union of what the shown garments hide', () => {
  assert.deepEqual(hiddenFor(['Top_Tee', 'Bottom_Pants', 'Under_Bottom'], { Top_Tee: [3, 1], Bottom_Pants: [2, 3] }), [1, 2, 3]);
  assert.deepEqual(hiddenFor([], { Top_Tee: [1] }), []);
  assert.deepEqual(hiddenFor(['Top_Tee'], null), []);
});

test('design files and gear keys', () => {
  assert.deepEqual(designFiles('Wardrobe', 'Under_Bottom', 'lace'), { mask: 'Wardrobe/Under_Bottom__lace.webp', normal: 'Wardrobe/Under_Bottom__lace_n.webp' });
  assert.equal(gearKey({ main: 'a', chest: 'b' }), gearKey({ chest: 'b', main: 'a', off: null }));
  assert.notEqual(gearKey({ chest: 'b' }), gearKey({ legs: 'b' }));
});

test('bone offsets scale with the morph weights and add up', () => {
  const J = { Shoulders_Broad: { upperarm_l: [0.03, 0, 0], hand_l: [0.03, 0, 0] }, Other: { hand_l: [0, 0.01, 0] } };
  const d = boneOffsets(J, { Shoulders_Broad: 0.5, Other: 1 });
  assert.deepEqual(d.upperarm_l, [0.015, 0, 0]);
  assert.deepEqual(d.hand_l, [0.015, 0.01, 0]);
  assert.deepEqual(boneOffsets(J, {}), {});
  assert.deepEqual(boneOffsets(null, { Shoulders_Broad: 1 }), {});
});

test('a relaxed hand curls more toward the little finger; approach is rate-limited', () => {
  assert.equal(relaxedCurl('hand_l'), null);
  assert.equal(relaxedCurl('index_04_l'), null);
  assert.ok(relaxedCurl('pinky_01_r')! > relaxedCurl('index_01_r')!);
  assert.ok(relaxedCurl('middle_02_l')! > 0);
  // knuckles draw in toward the middle finger, mirrored left to right; other joints don't
  assert.equal(relaxedSpread('index_01_r'), -relaxedSpread('index_01_l'));
  assert.ok(relaxedSpread('index_01_r') > 0 && relaxedSpread('pinky_01_r') < 0);
  assert.equal(relaxedSpread('index_02_r'), 0);
  assert.equal(relaxedSpread('hand_r'), 0);
  assert.ok(Math.abs(approach(0, 1, 6, 0.1) - 0.6) < 1e-9);
  assert.equal(approach(0.9, 1, 6, 0.1), 1);
  assert.equal(approach(0.5, 0, 6, 1), 0);
});

test('a body may bring its own relaxed hand table', () => {
  const t = { index: [40, 30, 20, 5] };
  assert.equal(relaxedCurl('index_02_r', t), 30);
  assert.equal(relaxedSpread('index_01_l', t), -5);
  // fingers the table leaves out keep the default
  assert.equal(relaxedCurl('pinky_01_r', t), relaxedCurl('pinky_01_r'));
});
