// Unit tests for the names over heads' colours (nameplates.ts).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { playerColor, PLAYER_COLOR, PVP_COLOR, conColor } from '../nameplates';

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
