// Unit tests for wardrobe.ts: what a body shows for its gear, hidden regions, the bones the
// morphs move, the relaxed hand. Run with __tests__/run.sh.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STARTER_GEAR, approach, boneOffsets, designFiles, gearKey, hiddenFor, relaxedCurl, relaxedSpread, wornGarments } from '../wardrobe';

const CATALOG: Record<string, any> = {
  homespun_top: { slots: ['under_top'], wear: { female: { part: 'Garments/Female/uw_homespun_top.glb' }, male: null }, colors: { main: '#E8DFCB' } },
  homespun_bottom: { slots: ['under_bottom'], wear: { female: { part: 'Garments/Female/uw_homespun_bottom.glb' }, male: { part: 'Garments/Male/uw_homespun_bottom.glb' } }, colors: { main: '#E8DFCB' } },
  old_bottom: { slots: ['under_bottom'], wear: { female: { garment: 'Under_Bottom', design: 'classic' }, male: { garment: 'Bottom_Shorts' } }, colors: { main: '#EAE0C8' } },
  robe: { slots: ['chest'], wear: { female: { part: 'Garments/Female/robe.glb', layer: 9 }, male: { part: 'Garments/Male/robe.glb', layer: 9 } } },
  boots: { slots: ['feet'], wear: { female: { part: 'Garments/Female/boots.glb' }, male: { part: 'Garments/Male/boots.glb' } } },
  cloth_trousers: { slots: ['legs'], wear: { female: { garment: 'Bottom_Pants', design: 'pants' }, male: { garment: 'Bottom_Pants' } }, colors: { main: '#4A4F57' } },
  cloth_shorts: { slots: ['legs'], wear: { female: { garment: 'Bottom_Shorts', design: 'shorts' }, male: { garment: 'Bottom_Shorts' } }, colors: { main: '#1E2E5C' } },
  cloth_tunic: { slots: ['chest'], wear: { female: { garment: 'Top_Tee' }, male: { garment: 'Top_Tee' } }, colors: { main: '#8A6A4A', trim: '#5C4630' } },
  linen_arm_wraps: { slots: ['wrist'], wear: { female: { garment: 'Wrist_Wraps', design: 'wrist_linen' }, male: { garment: 'Wrist_Wraps', design: 'wrist_linen' } }, colors: { main: '#D5C7A9' } },
  rusty_dagger: { slots: ['main', 'off'] },
};
const item = (id: string) => CATALOG[id] || null;

test('the starter underwear: garment parts, top and bottom on her, the bottom on him', () => {
  const f = wornGarments('female', STARTER_GEAR, item);
  assert.deepEqual(f.map((g) => [g.slot, g.part, g.layer]), [
    ['under_top', 'Garments/Female/uw_homespun_top.glb', 0],
    ['under_bottom', 'Garments/Female/uw_homespun_bottom.glb', 0],
  ]);
  assert.equal(f[0].garment, 'part:Garments/Female/uw_homespun_top.glb');
  const m = wornGarments('male', STARTER_GEAR, item);
  assert.deepEqual(m.map((g) => g.part), ['Garments/Male/uw_homespun_bottom.glb']);
});

test('inner layers first (legs under chest under feet); hands and unknown items ignored', () => {
  const g = wornGarments('female', { ...STARTER_GEAR, main: 'rusty_dagger', chest: 'cloth_tunic', legs: 'cloth_trousers', feet: 'no_such_boots' }, item);
  assert.deepEqual(g.map((x) => x.garment), ['part:Garments/Female/uw_homespun_top.glb', 'part:Garments/Female/uw_homespun_bottom.glb', 'Bottom_Pants', 'Top_Tee']);
  assert.equal(g[3].colors.trim, '#5C4630');
});

test('an item may set its own layer (a robe over the boots)', () => {
  const g = wornGarments('male', { chest: 'robe', feet: 'boots' }, item);
  assert.deepEqual(g.map((x) => [x.slot, x.layer]), [['feet', 4], ['chest', 9]]);
});

test('the outer item wins a garment both would show (old in-body underwear under shorts)', () => {
  const g = wornGarments('male', { under_bottom: 'old_bottom', legs: 'cloth_shorts' }, item);
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


test('wrist slot equips arm wraps for both genders', () => {
  const f = wornGarments('female', { ...STARTER_GEAR, wrist: 'linen_arm_wraps' }, item);
  assert.ok(f.some((g) => g.slot === 'wrist' && g.garment === 'Wrist_Wraps' && g.design === 'wrist_linen'));
  const m = wornGarments('male', { ...STARTER_GEAR, wrist: 'linen_arm_wraps' }, item);
  assert.ok(m.some((g) => g.slot === 'wrist' && g.garment === 'Wrist_Wraps' && g.design === 'wrist_linen'));
});
