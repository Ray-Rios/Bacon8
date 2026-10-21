// Unit tests for controls-math.ts. Run with __tests__/run.sh (esbuild + node --test),
// in a throwaway container: the hub has no JS test runner.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CAMERA,
  MOVE,
  UNITS_PER_METRE,
  cameraBasis,
  cameraPosition,
  clampLookPitch,
  facingYaw,
  moveDirection,
  shortestAngleDiff,
  stepVelocity,
  turnToward,
  zoomDistance,
  type MoveInput,
} from '../controls-math';

const EPS = 1e-9;
const near = (a: number, b: number, eps = EPS) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);
const nearVec = (v: { x: number; z: number }, x: number, z: number, eps = EPS) => {
  near(v.x, x, eps);
  near(v.z, z, eps);
};

const none: MoveInput = { forward: false, back: false, left: false, right: false };
const keys = (k: Partial<MoveInput>): MoveInput => ({ ...none, ...k });

test('camera basis: psi = 0 looks along +Z, right is -X', () => {
  const { forward, right } = cameraBasis(0);
  nearVec(forward, 0, 1);
  nearVec(right, -1, 0);
});

for (const [label, yaw, f, r] of [
  ['0', 0, { x: 0, z: 1 }, { x: -1, z: 0 }],
  ['pi/2', Math.PI / 2, { x: 1, z: 0 }, { x: 0, z: 1 }],
  ['pi', Math.PI, { x: 0, z: -1 }, { x: 1, z: 0 }],
] as const) {
  test(`W/A/S/D are camera-relative at psi = ${label}`, () => {
    nearVec(moveDirection(keys({ forward: true }), yaw), f.x, f.z);
    nearVec(moveDirection(keys({ back: true }), yaw), -f.x, -f.z);
    nearVec(moveDirection(keys({ right: true }), yaw), r.x, r.z);
    nearVec(moveDirection(keys({ left: true }), yaw), -r.x, -r.z);
  });
}

test('W moves away from the camera, S toward it', () => {
  for (const yaw of [0, 0.7, Math.PI / 2, Math.PI, -2.1]) {
    const pivot = { x: 3, y: 1, z: -4 };
    const cam = cameraPosition(pivot, yaw, -0.3, 10);
    const w = moveDirection(keys({ forward: true }), yaw);
    const before = Math.hypot(pivot.x - cam.x, pivot.z - cam.z);
    const after = Math.hypot(pivot.x + w.x - cam.x, pivot.z + w.z - cam.z);
    assert.ok(after > before, `W at yaw ${yaw} should move away from the camera`);
    const s = moveDirection(keys({ back: true }), yaw);
    assert.ok(Math.hypot(pivot.x + s.x - cam.x, pivot.z + s.z - cam.z) < before);
  }
});

test('diagonals are normalised; opposing keys cancel', () => {
  const d = moveDirection(keys({ forward: true, right: true }), 0);
  near(Math.hypot(d.x, d.z), 1);
  nearVec(d, -Math.SQRT1_2, Math.SQRT1_2);
  nearVec(moveDirection(keys({ forward: true, back: true }), 1.2), 0, 0);
  nearVec(moveDirection(none, 1.2), 0, 0);
});

test('a character facing its move direction looks where W goes (B8 humans face +Z)', () => {
  near(facingYaw({ x: 0, z: 1 }), 0);
  near(facingYaw({ x: 1, z: 0 }), Math.PI / 2);
  near(Math.abs(facingYaw({ x: 0, z: -1 })), Math.PI);
  for (const yaw of [0, 1, -2.5, 3]) {
    near(shortestAngleDiff(facingYaw(moveDirection(keys({ forward: true }), yaw)), yaw), 0, 1e-9);
  }
});

test('shortest-arc angle difference wraps to (-pi, pi]', () => {
  near(shortestAngleDiff(0, 0.5), 0.5);
  near(shortestAngleDiff(0.5, 0), -0.5);
  near(shortestAngleDiff(3, -3), 2 * Math.PI - 6); // across +/-pi, the short way
  near(shortestAngleDiff(-3, 3), 6 - 2 * Math.PI);
  near(shortestAngleDiff(0, 4 * Math.PI + 0.2), 0.2);
  near(shortestAngleDiff(0, Math.PI), Math.PI);
});

test('turnToward takes the shortest arc and never overshoots', () => {
  near(turnToward(0, 1, 0.25), 0.25);
  near(turnToward(0, -1, 0.25), -0.25);
  near(turnToward(0, 0.1, 0.25), 0.1); // reaches it, doesn't pass it
  // From 170 degrees to -170 degrees is 20 degrees forward, not 340 back.
  const from = (170 * Math.PI) / 180;
  const to = (-170 * Math.PI) / 180;
  const after = turnToward(from, to, 0.01);
  assert.ok(after > from, 'turns up through 180 degrees, the short way');
  // At 500 deg/s a half turn takes 0.36 s.
  let yaw = 0;
  let t = 0;
  while (Math.abs(shortestAngleDiff(yaw, Math.PI)) > 1e-9 && t < 1) {
    yaw = turnToward(yaw, Math.PI, MOVE.turnRate / 60);
    t += 1 / 60;
  }
  near(t, 0.36, 1 / 60 + 1e-9);
});

test('acceleration is capped at accel * dt toward the target velocity', () => {
  const v = stepVelocity({ x: 0, z: 0 }, { x: 0, z: 5 }, true, MOVE.acceleration, MOVE.brakingGround, 0.1);
  nearVec(v, 0, 2.048);
  // Close enough: snaps to the target.
  nearVec(stepVelocity({ x: 0, z: 4.9 }, { x: 0, z: 5 }, true, 20.48, 20, 0.1), 0, 5);
  // Reversing direction moves straight toward the new target.
  const r = stepVelocity({ x: 0, z: 5 }, { x: 0, z: -5 }, true, 20, 20, 0.1);
  nearVec(r, 0, 3);
  // Jog to full speed takes ~0.24 s on the ground.
  let w = { x: 0, z: 0 };
  let t = 0;
  while (w.z < MOVE.jogSpeed && t < 1) {
    w = stepVelocity(w, { x: 0, z: MOVE.jogSpeed }, true, MOVE.acceleration, MOVE.brakingGround, 1 / 120);
    t += 1 / 120;
  }
  near(t, MOVE.jogSpeed / MOVE.acceleration, 1 / 120 + 1e-9);
});

test('air control scales acceleration', () => {
  const air = stepVelocity({ x: 0, z: 0 }, { x: 5, z: 0 }, true, MOVE.acceleration * MOVE.airControl, MOVE.brakingAir, 0.1);
  nearVec(air, 0.7168, 0);
});

test('braking without input slows along the current direction and stops at zero', () => {
  const v = stepVelocity({ x: 3, z: 4 }, { x: 0, z: 0 }, false, 20.48, 20, 0.1);
  nearVec(v, 1.8, 2.4); // speed 5 -> 3, same direction
  nearVec(stepVelocity({ x: 0.3, z: 0.4 }, { x: 0, z: 0 }, false, 20.48, 20, 0.1), 0, 0); // never reverses
  nearVec(stepVelocity({ x: 0, z: 0 }, { x: 0, z: 0 }, false, 20.48, 20, 0.1), 0, 0);
});

test('camera sits behind the pivot, above it when looking down', () => {
  const pivot = { x: 0, y: 1, z: 0 };
  const cam = cameraPosition(pivot, 0, -Math.PI / 6, 4);
  assert.ok(cam.z < 0, 'behind: -Z when looking along +Z');
  near(cam.x, 0);
  near(cam.y, 1 + 4 * Math.sin(Math.PI / 6));
  near(Math.hypot(cam.x - pivot.x, cam.y - pivot.y, cam.z - pivot.z), 4);
});

test('look pitch is clamped to -70..+55 degrees; zoom to 1.5..9 m', () => {
  near(clampLookPitch(-2), CAMERA.minLookPitch);
  near(clampLookPitch(2), CAMERA.maxLookPitch);
  near(clampLookPitch(0.1), 0.1);
  near(CAMERA.minLookPitch, (-70 * Math.PI) / 180);
  near(zoomDistance(4, 100000), CAMERA.maxDistance);
  near(zoomDistance(4, -100000), CAMERA.minDistance);
  assert.ok(zoomDistance(4, 100) > 4);
  assert.ok(zoomDistance(4, -100) < 4);
});

test('speeds fit the server limit (30 units/s, play_live.ex)', () => {
  near(UNITS_PER_METRE, 2.2 / 1.8);
  const sprint = MOVE.sprintSpeed * UNITS_PER_METRE;
  const jumpUp = MOVE.jumpSpeed * UNITS_PER_METRE;
  assert.ok(Math.hypot(sprint, jumpUp) < 30, `sprinting jump ${Math.hypot(sprint, jumpUp)} u/s`);
});
