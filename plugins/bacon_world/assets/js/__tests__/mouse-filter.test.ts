// Unit tests for mouse-filter.ts. Run with __tests__/run.sh (esbuild + node --test),
// in a throwaway container: the hub has no JS test runner.
//
// The tests drive the filter with what Chrome reports for a locked pointer when the
// mouse comes from a remote-desktop client: the client sends its cursor's absolute
// position; Chrome measures each move from the previous position and, when the cursor
// is within 15% of an edge, moves it back to the middle (ignoring that move); the
// client puts its own cursor in the middle when it hears about it, `latencyMs` later.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MouseFilter, jumpLimit, type Move } from '../mouse-filter';

type Sim = {
  width: number;
  height: number;
  /** The hand's speed at a time (px/s on the remote screen). */
  velocity: (tMs: number) => Move;
  seconds: number;
  /** The client sends a position this often. */
  eventMs: number;
  /** When Chrome's moves to the middle reach the client; null: never. */
  latencyMs: number | null;
  /** The client's cursor stops here (the edge of its own screen), if it never follows Chrome. */
  clientMaxX?: number;
  /** The page's devicePixelRatio, as the filter is told it. */
  dpr?: number;
  /**
   * Chrome's movement units per CSS pixel: 1, or the dpr if it reports device pixels.
   * `width` and `height` are in Chrome's units; the filter is told the CSS size.
   */
  units?: number;
};

type Report = { t: number; x: number; y: number };

function chromeOverRemote(s: Sim): { reports: Report[]; truth: Move } {
  const mid = { x: s.width / 2, y: s.height / 2 };
  const nearEdge = (p: Move) =>
    p.x < s.width * 0.15 || p.x > s.width * 0.85 || p.y < s.height * 0.15 || p.y > s.height * 0.85;
  let client = { ...mid };
  let last = { ...mid };
  const landings: number[] = [];
  const reports: Report[] = [];
  const truth = { x: 0, y: 0 };
  for (let t = s.eventMs; t <= s.seconds * 1000; t += s.eventMs) {
    while (landings.length && landings[0] <= t) {
      landings.shift();
      client = { ...mid };
    }
    const v = s.velocity(t);
    const before = { ...client };
    client = { x: client.x + (v.x * s.eventMs) / 1000, y: client.y + (v.y * s.eventMs) / 1000 };
    if (s.clientMaxX !== undefined) client.x = Math.min(client.x, s.clientMaxX);
    truth.x += client.x - before.x;
    truth.y += client.y - before.y;
    reports.push({ t, x: client.x - last.x, y: client.y - last.y });
    last = { ...client };
    if (nearEdge(client)) {
      last = { ...mid };
      if (s.latencyMs !== null) landings.push(t + s.latencyMs);
    }
  }
  return { reports, truth };
}

function run(s: Sim, merge = 1) {
  const sim = chromeOverRemote(s);
  const truth = sim.truth;
  // `merge` > 1: the browser hands the page several reports summed into one event.
  const reports: Report[] = [];
  for (let i = 0; i < sim.reports.length; i += merge) {
    const group = sim.reports.slice(i, i + merge);
    reports.push(group.reduce((a, r) => ({ t: r.t, x: a.x + r.x, y: a.y + r.y }), { t: 0, x: 0, y: 0 }));
  }
  const units = s.units ?? 1;
  const filter = new MouseFilter(() => ({ width: s.width / units, height: s.height / units, dpr: s.dpr ?? 1 }));
  const out = { x: 0, y: 0 };
  const raw = { x: 0, y: 0 };
  let worst = 0; // the furthest the filtered total got from the hand's at any moment (px)
  const hand = { x: 0, y: 0 };
  let i = 0;
  // Replay the hand alongside, to compare at every report.
  const { reports: again } = chromeOverRemote({ ...s, latencyMs: 0, clientMaxX: undefined });
  for (const r of reports) {
    const m = filter.filter(r.x, r.y);
    out.x += m.x;
    out.y += m.y;
    raw.x += r.x;
    raw.y += r.y;
    if (s.clientMaxX === undefined) {
      for (let k = 0; k < merge && i < again.length; k++, i++) {
        hand.x += again[i].x;
        hand.y += again[i].y;
      }
      worst = Math.max(worst, Math.hypot(out.x - hand.x, out.y - hand.y));
    }
  }
  return { out, raw, truth, worst, filter };
}

const within = (got: number, want: number, frac: number, what: string) =>
  assert.ok(Math.abs(got - want) <= Math.abs(want) * frac + 1, `${what}: got ${got.toFixed(1)}, want ${want.toFixed(1)}`);

test('a local mouse passes straight through', () => {
  const r = run({ width: 1600, height: 900, velocity: () => ({ x: 1500, y: -200 }), seconds: 3, eventMs: 8, latencyMs: 0 });
  assert.equal(r.filter.repaired, 0);
  assert.equal(r.filter.remoteDesktop, false);
  within(r.out.x, r.truth.x, 0, 'x');
  within(r.out.y, r.truth.y, 0, 'y');
});

test('remote desktop: a steady turn neither spins nor falls behind', () => {
  const r = run({ width: 1600, height: 900, velocity: () => ({ x: 1500, y: 0 }), seconds: 3, eventMs: 16, latencyMs: 80 });
  // What Chrome reports adds up to several times the real turn: that was the spinning.
  assert.ok(r.raw.x > 3 * r.truth.x, `raw ${r.raw.x} vs ${r.truth.x}`);
  assert.ok(r.filter.remoteDesktop);
  within(r.out.x, r.truth.x, 0.02, 'x');
  assert.ok(r.worst < 80, `worst lag ${r.worst.toFixed(1)} px`);
});

test('remote desktop: slow link, diagonal, at 30 events a second', () => {
  const r = run({ width: 1280, height: 720, velocity: () => ({ x: -1200, y: 350 }), seconds: 4, eventMs: 33, latencyMs: 150 });
  within(r.out.x, r.truth.x, 0.04, 'x');
  within(r.out.y, r.truth.y, 0.04, 'y');
});

test('remote desktop: turning back and forth stays with the hand', () => {
  const r = run({
    width: 1920,
    height: 1000,
    velocity: (t) => ({ x: Math.floor(t / 700) % 2 === 0 ? 1800 : -1500, y: Math.floor(t / 1100) % 2 === 0 ? 120 : -120 }),
    seconds: 6,
    eventMs: 16,
    latencyMs: 60,
  });
  assert.ok(r.worst < 120, `worst lag ${r.worst.toFixed(1)} px`);
  within(r.out.x, r.truth.x, 0.05, 'x');
});

test('remote desktop: slow, careful aiming', () => {
  const r = run({ width: 1600, height: 900, velocity: () => ({ x: 220, y: -60 }), seconds: 8, eventMs: 16, latencyMs: 90 });
  within(r.out.x, r.truth.x, 0.03, 'x');
  within(r.out.y, r.truth.y, 0.05, 'y');
});

test('remote desktop: input arriving in bursts', () => {
  // Every third report carries the movement of three (the link batches input).
  const r = run({
    width: 1600,
    height: 900,
    velocity: (t) => (Math.round(t / 16) % 3 === 0 ? { x: 3600, y: 300 } : { x: 0, y: 0 }),
    seconds: 4,
    eventMs: 16,
    latencyMs: 70,
  });
  within(r.out.x, r.truth.x, 0.06, 'x');
  assert.ok(r.worst < 150, `worst lag ${r.worst.toFixed(1)} px`);
});

test('remote desktop: a very slow link (300 ms), looking up and down', () => {
  // A hand swinging smoothly up and down while turning slowly.
  const r = run({
    width: 1600,
    height: 900,
    velocity: (t) => ({ x: 300, y: 1100 * Math.sin((2 * Math.PI * t) / 1800) }),
    seconds: 5,
    eventMs: 20,
    latencyMs: 300,
  });
  within(r.out.x, r.truth.x, 0.05, 'x');
  assert.ok(Math.abs(r.out.y - r.truth.y) < 60, `y: got ${r.out.y.toFixed(1)}, want ${r.truth.y.toFixed(1)}`);
  assert.ok(r.worst < 160, `worst lag ${r.worst.toFixed(1)} px`);
});

test('remote desktop: a very slow link, snapping up and down mid catch-up, costs a few steps at most', () => {
  const r = run({
    width: 1600,
    height: 900,
    velocity: (t) => ({ x: 300, y: Math.floor(t / 900) % 2 === 0 ? 900 : -900 }),
    seconds: 5,
    eventMs: 20,
    latencyMs: 300,
  });
  // A step here is 18 px.
  assert.ok(Math.abs(r.out.y - r.truth.y) <= 5 * 18, `y: got ${r.out.y.toFixed(1)}, want ${r.truth.y.toFixed(1)}`);
  assert.ok(r.worst < 160, `worst lag ${r.worst.toFixed(1)} px`);
});

test('remote desktop, with the browser merging pairs of reports: still no spin', () => {
  const r = run({ width: 1600, height: 900, velocity: () => ({ x: 1500, y: 0 }), seconds: 3, eventMs: 8, latencyMs: 80 }, 2);
  assert.ok(r.raw.x > 3 * r.truth.x);
  within(r.out.x, r.truth.x, 0.15, 'x');
});

test('high-DPI screens: movement in device pixels or in CSS pixels, the filter copes with either', () => {
  for (const units of [1, 1.5]) {
    const local = run({ width: 1600 * units, height: 900 * units, velocity: () => ({ x: 1400, y: 120 }), seconds: 3, eventMs: 8, latencyMs: 0, dpr: 1.5, units });
    within(local.out.x, local.truth.x, 0, `local x (units ${units})`);
    const remote = run({ width: 1600 * units, height: 900 * units, velocity: () => ({ x: 1400, y: 120 }), seconds: 3, eventMs: 16, latencyMs: 80, dpr: 1.5, units });
    within(remote.out.x, remote.truth.x, 0.04, `remote x (units ${units})`);
    assert.ok(remote.worst < 120, `worst lag ${remote.worst.toFixed(1)} px (units ${units})`);
  }
});

test('a client that never follows Chrome stops turning at its own edge instead of spinning', () => {
  const r = run({
    width: 1600,
    height: 900,
    velocity: () => ({ x: 1500, y: 0 }),
    seconds: 3,
    eventMs: 16,
    latencyMs: null,
    clientMaxX: 1450,
  });
  // The client's cursor could only go from the middle (800) to 1450.
  within(r.truth.x, 650, 0.01, 'truth');
  assert.ok(r.out.x <= r.truth.x * 1.05 + 30, `out ${r.out.x}`);
  assert.ok(r.out.x >= r.truth.x * 0.9, `out ${r.out.x}`);
});

test('one stray jump (focus change, lock start) costs at most a normal step', () => {
  const f = new MouseFilter(() => ({ width: 1600, height: 900, dpr: 1 }));
  const moves = [10, 12, 11, 900, 10, 9, 11];
  let total = 0;
  for (const m of moves) total += f.filter(m, 0).x;
  assert.ok(Math.abs(total - (10 + 12 + 11 + 11 + 10 + 9 + 11)) < 15, `total ${total}`);
});

test('the believable step scales with the page', () => {
  assert.deepEqual(jumpLimit(1000, 500), { x: 220, y: 110 });
  assert.deepEqual(jumpLimit(300, 200), { x: 120, y: 90 });
});
