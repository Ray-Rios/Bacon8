// Unit tests for flight (controls-math.ts FLIGHT, isDoubleTap, flightTarget,
// approachVelocity): a flying mount takes off on a double-tapped Space, like RaysSpaceSim.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FLIGHT, approachVelocity, flightTarget, isDoubleTap, type FlightInput } from '../controls-math';

const near = (a: number, b: number, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);
const idle: FlightInput = { forward: false, back: false, left: false, right: false, up: false, down: false, boost: false };
const keys = (k: Partial<FlightInput>): FlightInput => ({ ...idle, ...k });

test('a double tap is two presses within the window', () => {
  assert.equal(isDoubleTap(1000, 1000 + FLIGHT.doubleTapMs - 1), true);
  assert.equal(isDoubleTap(1000, 1000 + FLIGHT.doubleTapMs + 1), false);
  assert.equal(isDoubleTap(1000, 1000), false); // the same press, not two
  assert.equal(isDoubleTap(-Infinity, 50), false); // the first press ever
});

test('no keys: hover in place', () => {
  const v = flightTarget(idle, 0.3, -0.2, 18);
  near(v.x, 0);
  near(v.y, 0);
  near(v.z, 0);
});

test('W flies where the camera looks, pitch included (no roll: level strafe)', () => {
  const level = flightTarget(keys({ forward: true }), 0, 0, 18);
  near(level.x, 0);
  near(level.y, 0);
  near(level.z, 18);
  const dive = flightTarget(keys({ forward: true }), 0, -Math.PI / 4, 18);
  near(dive.y, -18 * Math.SQRT1_2);
  near(dive.z, 18 * Math.SQRT1_2);
  near(Math.hypot(dive.x, dive.y, dive.z), 18);
  const strafe = flightTarget(keys({ right: true }), 0, -0.6, 18);
  near(strafe.y, 0); // A/D never tilt the flight path
  near(Math.hypot(strafe.x, strafe.z), 18);
});

test('Space climbs, C dives, Shift boosts', () => {
  near(flightTarget(keys({ up: true }), 0, 0, 10).y, 10 * FLIGHT.climbShare);
  near(flightTarget(keys({ down: true }), 0, 0, 10).y, -10 * FLIGHT.climbShare);
  near(flightTarget(keys({ forward: true, boost: true }), 0, 0, 10).z, 10 * FLIGHT.boost);
});

test('velocity eases toward the target and never overshoots', () => {
  let v = { x: 0, y: 0, z: 0 };
  const target = { x: 0, y: 2, z: 18 };
  let last = 0;
  for (let i = 0; i < 120; i++) {
    v = approachVelocity(v, target, FLIGHT.response, 1 / 60);
    assert.ok(v.z >= last && v.z <= 18);
    last = v.z;
  }
  assert.ok(v.z > 18 * 0.99 - 1); // most of the way after 2 s
  near(approachVelocity(v, target, FLIGHT.response, 0).z, v.z);
});
