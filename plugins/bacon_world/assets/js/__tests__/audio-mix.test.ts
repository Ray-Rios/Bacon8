// Unit tests for audio-mix.ts (the music shuffle, rests, placing sounds, ambient details).
// Run with __tests__/run.sh (esbuild + node --test).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MUSIC, Playlist, gapFor, placeSound, restAfter, sweetenersFor, weighted } from '../audio-mix';

function lcg(seed: number) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
}

test('a playlist plays every track before any repeats, and never one twice running', () => {
  for (let seed = 1; seed < 40; seed++) {
    const p = new Playlist(7, lcg(seed));
    const seq = Array.from({ length: 70 }, () => p.next());
    for (let i = 0; i < 70; i += 7) assert.deepEqual([...seq.slice(i, i + 7)].sort(), [1, 2, 3, 4, 5, 6, 7]);
    for (let i = 1; i < seq.length; i++) assert.notEqual(seq[i], seq[i - 1], `seed ${seed} at ${i}`);
  }
  const one = new Playlist(1);
  assert.deepEqual([one.next(), one.next()], [1, 1]);
});

test("rests between tracks fall inside each mood's range", () => {
  for (const mood of Object.keys(MUSIC) as Array<keyof typeof MUSIC>) {
    const [a, b] = MUSIC[mood].gap;
    for (const r of [0, 0.5, 0.999]) {
      const v = restAfter(mood, () => r);
      assert.ok(v >= a && v <= b, `${mood} ${v}`);
    }
  }
  assert.ok(MUSIC.day.gap[0] >= 30, 'the day music rests long enough to never wear thin');
});

test('placed sounds pan to their side, fade with distance and dull far away', () => {
  const ear = { x: 0, y: 0, z: 0 };
  const right = placeSound(ear, 1, 0, { x: 10, y: 0, z: 0 }, 40);
  const left = placeSound(ear, 1, 0, { x: -10, y: 0, z: 0 }, 40);
  assert.ok(right.pan > 0.5 && left.pan < -0.5);
  const near = placeSound(ear, 1, 0, { x: 0, y: 0, z: 2 }, 40);
  const far = placeSound(ear, 1, 0, { x: 0, y: 0, z: 30 }, 40);
  assert.ok(near.gain > far.gain && far.gain > 0);
  assert.ok(near.cutoff > far.cutoff);
  assert.equal(placeSound(ear, 1, 0, { x: 0, y: 0, z: 50 }, 40).gain, 0);
  // right at your feet: centred, not hard to one side
  assert.ok(Math.abs(placeSound(ear, 1, 0, { x: 0.5, y: 0, z: 0 }, 40).pan) < 0.5);
});

test('bursts of one kind are spaced, ambient details fit the place', () => {
  assert.ok(gapFor('step_grass') > 0 && gapFor('ui_hover') > 0 && gapFor('sw_bird') > 1000);
  assert.equal(gapFor('fireball_cast'), 0);
  const night = sweetenersFor(0, 0, 0).map(([k]) => k);
  assert.ok(!night.includes('sw_bird'), 'no birdsong at night');
  const lair = sweetenersFor(1, 1, 0).map(([k]) => k);
  assert.ok(lair.includes('sw_drip') && !lair.includes('sw_bird'));
  assert.equal(weighted([['a', 1], ['b', 3]], 0.1), 'a');
  assert.equal(weighted([['a', 1], ['b', 3]], 0.9), 'b');
  assert.equal(weighted([], 0.5), null);
});
