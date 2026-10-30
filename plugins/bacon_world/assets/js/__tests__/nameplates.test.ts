// Unit tests for the names over heads' colours (nameplates.ts).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from '../../../../../assets/js/vendor/three';
import { UNITS_PER_METRE as U } from '../controls-math';
import { Nameplates, playerColor, PLAYER_COLOR, PVP_COLOR, conColor } from '../nameplates';

// Node has no canvas: just enough of one for the plates to measure and draw their names.
(globalThis as any).document ??= {
  createElement: () => ({
    width: 0,
    height: 0,
    getContext: () => ({ font: '', measureText: (t: string) => ({ width: t.length * 24 }), clearRect() {}, strokeText() {}, fillText() {} }),
  }),
};

test('players are Bacon8 blue, red with PvP on', () => {
  assert.equal(PLAYER_COLOR, '#247DF1');
  assert.equal(PVP_COLOR, '#E62929');
  assert.equal(playerColor(false), PLAYER_COLOR);
  assert.equal(playerColor(true), PVP_COLOR);
});

test('creatures keep their con colours', () => {
  assert.equal(conColor(0, 5), '#FFFFFF');
  assert.equal(conColor(3, 5), '#FF4A3D');
});

test('far names stay readable, and the nearer of two overlapping names wins (2026-10-30)', () => {
  const plates = new Nameplates();
  const cam = new THREE.PerspectiveCamera(60, 16 / 9, 0.1, 100000);
  cam.position.set(0, 2 * U, 0);
  cam.lookAt(0, 2 * U, -100 * U);
  cam.updateMatrixWorld();
  const host = (z: number, x = 0) => {
    const o = new THREE.Object3D();
    o.position.set(x, 0, z);
    return o;
  };
  plates.set('near', host(-60 * U), { name: 'a skeleton', color: '#fff' });
  plates.set('far', host(-62 * U, 0.2 * U), { name: 'a skeleton', color: '#fff' });
  plates.set('side', host(-60 * U, 20 * U), { name: 'a deer', color: '#fff' });
  plates.update(cam, 720);
  const sprite = (i: number) => plates.group.children[i] as THREE.Sprite;
  // 60 m off, a line is still at least 15 px tall: world size >= 15 px worth
  const perPx = (2 * 60 * U * Math.tan(Math.PI / 6)) / 720;
  assert.ok(sprite(0).scale.y >= 15 * perPx);
  assert.equal(sprite(0).visible, true);
  assert.equal(sprite(1).visible, false, 'the farther one under it is hidden');
  assert.equal(sprite(2).visible, true, 'one off to the side stays');
  // the target always shows, and wins
  plates.set('far', host(-62 * U, 0.2 * U), { name: 'a skeleton', color: '#fff' }, { target: true });
  plates.update(cam, 720);
  assert.equal(sprite(1).visible, true);
  assert.equal(sprite(0).visible, false);
});
