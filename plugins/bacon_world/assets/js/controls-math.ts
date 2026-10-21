// Pure maths for Bacon World's third-person controls (character-controller.ts).
// No three.js and no DOM, so it runs under `node --test` (__tests__/).
//
// The numbers are RaysSpaceSim's on-foot character (ARSSCharacter, Unreal's
// third-person template), in metres; convert with UNITS_PER_METRE where they
// meet the scene.

// Characters are scaled so a 1.8 m human is 2.2 scene units tall
// (model-manager.ts, targetHeight = 2.2).
export const CHARACTER_HEIGHT_UNITS = 2.2;
export const UNITS_PER_METRE = CHARACTER_HEIGHT_UNITS / 1.8;

const DEG = Math.PI / 180;

export const MOVE = {
  jogSpeed: 5.0, // MaxWalkSpeed, m/s (the default pace)
  sprintSpeed: 8.0, // Shift: 1.6 x jog
  crouchSpeed: 2.5, // C
  acceleration: 20.48, // MaxAcceleration, m/s^2
  brakingGround: 20.0, // BrakingDecelerationWalking, m/s^2
  brakingAir: 15.0, // BrakingDecelerationFalling, m/s^2
  airControl: 0.35,
  jumpSpeed: 5.0, // JumpZVelocity, m/s
  gravity: 9.8, // m/s^2
  turnRate: 500 * DEG, // RotationRate.Yaw, rad/s (bOrientRotationToMovement)
} as const;

// Animation and footstep thresholds, m/s.
export const PACE = {
  idleBelow: 0.3, // slower than this is standing still
  jogUpTo: 5.5, // faster than this (or Shift) is a sprint
} as const;

export const CAMERA = {
  distance: 4.0, // boom length, m
  minDistance: 1.5,
  maxDistance: 9.0,
  pivotHeight: 0.62, // fraction of character height above the feet
  // Look pitch in Unreal's sense: negative looks down, positive looks up.
  minLookPitch: -70 * DEG,
  maxLookPitch: 55 * DEG,
  minHeightAboveGround: 0.25, // m
  mouseSensitivity: 0.0022, // rad per pixel
} as const;

export type Vec2 = { x: number; z: number };

/**
 * The ground-plane basis for a camera yaw. psi = 0 looks along +Z.
 * forward = (sin psi, cos psi); right is 90 degrees clockwise seen from above.
 */
export function cameraBasis(yaw: number): { forward: Vec2; right: Vec2 } {
  return {
    forward: { x: Math.sin(yaw), z: Math.cos(yaw) },
    right: { x: -Math.cos(yaw), z: Math.sin(yaw) },
  };
}

export type MoveInput = { forward: boolean; back: boolean; left: boolean; right: boolean };

/**
 * Camera-relative movement direction, unit length (diagonals normalised), or
 * (0, 0) with no input or opposing keys.
 */
export function moveDirection(input: MoveInput, yaw: number): Vec2 {
  const f = (input.forward ? 1 : 0) - (input.back ? 1 : 0);
  const r = (input.right ? 1 : 0) - (input.left ? 1 : 0);
  if (f === 0 && r === 0) return { x: 0, z: 0 };

  const { forward, right } = cameraBasis(yaw);
  const x = forward.x * f + right.x * r;
  const z = forward.z * f + right.z * r;
  const len = Math.hypot(x, z);
  return { x: x / len, z: z / len };
}

/** The yaw a character faces when it moves along `dir` (B8 humans face +Z at yaw 0). */
export function facingYaw(dir: Vec2): number {
  return Math.atan2(dir.x, dir.z);
}

/** Signed difference to - from, wrapped to (-pi, pi]: the shortest way round. */
export function shortestAngleDiff(from: number, to: number): number {
  let d = (to - from) % (2 * Math.PI);
  if (d <= -Math.PI) d += 2 * Math.PI;
  if (d > Math.PI) d -= 2 * Math.PI;
  return d;
}

/** Turn `current` toward `target` by at most `maxStep` radians, along the shortest arc. */
export function turnToward(current: number, target: number, maxStep: number): number {
  const d = shortestAngleDiff(current, target);
  if (Math.abs(d) <= maxStep) return current + d;
  return current + Math.sign(d) * maxStep;
}

/**
 * One step of horizontal velocity (m/s) toward `target` (m/s). With input the
 * change is capped at `acceleration * dt`; without it the speed falls by at
 * most `braking * dt` and never reverses.
 */
export function stepVelocity(
  v: Vec2,
  target: Vec2,
  hasInput: boolean,
  acceleration: number,
  braking: number,
  dt: number
): Vec2 {
  if (hasInput) {
    const dx = target.x - v.x;
    const dz = target.z - v.z;
    const dist = Math.hypot(dx, dz);
    const max = acceleration * dt;
    if (dist <= max) return { x: target.x, z: target.z };
    return { x: v.x + (dx / dist) * max, z: v.z + (dz / dist) * max };
  }

  const speed = Math.hypot(v.x, v.z);
  if (speed === 0) return { x: 0, z: 0 };
  const next = Math.max(0, speed - braking * dt);
  return { x: (v.x / speed) * next, z: (v.z / speed) * next };
}

/** Clamp a look pitch (negative looks down) to the camera's range. */
export function clampLookPitch(pitch: number): number {
  return Math.min(CAMERA.maxLookPitch, Math.max(CAMERA.minLookPitch, pitch));
}

/**
 * Camera position on its boom: behind the pivot along the view direction.
 * `lookPitch` < 0 looks down, so the camera sits above the pivot.
 */
export function cameraPosition(
  pivot: { x: number; y: number; z: number },
  yaw: number,
  lookPitch: number,
  distance: number
): { x: number; y: number; z: number } {
  const { forward } = cameraBasis(yaw);
  const elevation = -lookPitch;
  const horizontal = distance * Math.cos(elevation);
  return {
    x: pivot.x - forward.x * horizontal,
    y: pivot.y + distance * Math.sin(elevation),
    z: pivot.z - forward.z * horizontal,
  };
}

/** Zoom the boom by a wheel delta (pixels), multiplicatively, within its range (m). */
export function zoomDistance(distance: number, wheelDeltaY: number): number {
  const next = distance * Math.exp(wheelDeltaY * 0.001);
  return Math.min(CAMERA.maxDistance, Math.max(CAMERA.minDistance, next));
}
