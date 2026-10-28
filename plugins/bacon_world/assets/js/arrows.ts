// Arrows in flight (2026-10-28): the bows' (items.ts) and the goblin archers'. The server has
// already decided what each shot hits (BaconWorld.Melee, Brain); this only draws the arrow on its
// way, at about 45 m/s on a shallow arc, and lets it stick where it lands for a few seconds. One
// shared set of materials and geometries: no lights, nothing that recompiles a shader.
import * as THREE from '../../../../assets/js/vendor/three';
import { UNITS_PER_METRE } from './controls-math';
import { makeArrow } from './items';

const U = UNITS_PER_METRE;
const SPEED = 45 * U;
const STICK_S = 4;
const MAX = 40;
const ARROW_SCALE = 1.6;

interface Flight {
  obj: THREE.Object3D;
  from: THREE.Vector3;
  to: THREE.Vector3;
  t: number;
  dur: number;
  arc: number;
  stuck: number;
  done: (() => void) | null;
  /** Follows a moving target to the end (a creature, a player). */
  follow: (() => THREE.Vector3 | null) | null;
}

/** Where an arrow is at `x` (0..1) of its flight: a straight line lifted by a parabola (pure; tested). */
export function arrowAt(from: { x: number; y: number; z: number }, to: { x: number; y: number; z: number }, arc: number, x: number): { x: number; y: number; z: number } {
  const k = Math.max(0, Math.min(1, x));
  return { x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k + 4 * arc * k * (1 - k), z: from.z + (to.z - from.z) * k };
}

/** Seconds an arrow takes between two points (scene units). */
export function flightTime(from: THREE.Vector3, to: THREE.Vector3): number {
  return Math.max(0.06, from.distanceTo(to) / SPEED);
}

export class Arrows {
  readonly group = new THREE.Group();
  private flights: Flight[] = [];
  private template = makeArrow();
  private tmp = new THREE.Vector3();
  private look = new THREE.Vector3();

  constructor() {
    this.group.name = 'Arrows';
  }

  /**
   * Looses an arrow from `from` to `to` (scene units). `onArrive` runs as it gets there (the hit's
   * numbers show then); `follow` keeps its end on a moving target. Returns the flight's seconds.
   */
  shoot(from: THREE.Vector3, to: THREE.Vector3, onArrive: (() => void) | null = null, follow: (() => THREE.Vector3 | null) | null = null): number {
    while (this.flights.length >= MAX) this.drop(0);
    const obj = this.template.clone(true);
    // a little larger than life: a real arrow is a few pixels across at fighting range
    obj.scale.setScalar(U * ARROW_SCALE);
    this.group.add(obj);
    const dur = flightTime(from, to);
    const arc = Math.min(1.2 * U, from.distanceTo(to) * 0.025);
    this.flights.push({ obj, from: from.clone(), to: to.clone(), t: 0, dur, arc, stuck: -1, done: onArrive, follow });
    this.place(this.flights[this.flights.length - 1]);
    return dur;
  }

  update(dt: number) {
    for (let i = this.flights.length - 1; i >= 0; i--) {
      const f = this.flights[i];
      if (f.stuck >= 0) {
        f.stuck += dt;
        if (f.stuck > STICK_S) this.drop(i);
        continue;
      }
      f.t += dt;
      if (f.follow) {
        const p = f.follow();
        if (p) f.to.copy(p);
      }
      this.place(f);
      if (f.t >= f.dur) {
        f.stuck = 0;
        const cb = f.done;
        f.done = null;
        cb?.();
        // one that followed something is gone with it (it went in); the rest stick where they fell
        if (f.follow) this.drop(i);
      }
    }
  }

  clear() {
    while (this.flights.length) this.drop(0);
  }

  dispose() {
    this.clear();
    this.group.parent?.remove(this.group);
  }

  private place(f: Flight) {
    const x = f.t / f.dur;
    const p = arrowAt(f.from, f.to, f.arc, x);
    const q = arrowAt(f.from, f.to, f.arc, Math.min(1, x + 0.02));
    f.obj.position.set(p.x, p.y, p.z);
    // nose along the path (the arrow points +Z from its nock); the nock trails
    this.look.set(q.x - p.x, q.y - p.y, q.z - p.z);
    if (this.look.lengthSq() < 1e-10) this.look.set(f.to.x - f.from.x, f.to.y - f.from.y, f.to.z - f.from.z);
    this.look.normalize();
    f.obj.quaternion.setFromUnitVectors(this.tmp.set(0, 0, 1), this.look);
    // its nock is its origin: put the nose on the path
    f.obj.position.addScaledVector(this.look, -0.72 * U * ARROW_SCALE);
  }

  private drop(i: number) {
    const f = this.flights[i];
    this.group.remove(f.obj);
    this.flights.splice(i, 1);
  }
}
