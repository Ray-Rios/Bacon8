// The parts of Bacon World's sound that are plain logic, kept here so they can be tested
// without a browser (__tests__/audio-mix.test.ts): which music track plays next and
// when, when an ambient detail plays, how a sound placed in the world pans and dulls with
// distance, and how often one kind of sound may repeat.

export type Mood = 'menu' | 'day' | 'night' | 'lair' | 'boss';

/** How many tracks each mood has (music/<mood>_<n>.mp3), and how long it rests between them. */
export const MUSIC: Record<Mood, { tracks: number; gap: [number, number]; loop?: boolean }> = {
  menu: { tracks: 1, gap: [0, 0], loop: true },
  day: { tracks: 7, gap: [50, 130] },
  night: { tracks: 3, gap: [60, 150] },
  lair: { tracks: 3, gap: [15, 45] },
  boss: { tracks: 1, gap: [0, 0], loop: true },
};

/**
 * A shuffled deck of a mood's tracks: every track once before any repeats, and never the
 * same track twice in a row across reshuffles.
 */
export class Playlist {
  private deck: number[] = [];
  private last = 0;
  constructor(private count: number, private random: () => number = Math.random) {}

  next(): number {
    if (this.count <= 1) return (this.last = 1);
    if (!this.deck.length) {
      const d = Array.from({ length: this.count }, (_, i) => i + 1);
      for (let i = d.length - 1; i > 0; i--) {
        const j = Math.floor(this.random() * (i + 1));
        [d[i], d[j]] = [d[j], d[i]];
      }
      if (d[0] === this.last) [d[0], d[d.length - 1]] = [d[d.length - 1], d[0]];
      this.deck = d;
    }
    this.last = this.deck.shift()!;
    return this.last;
  }
}

/** Seconds of quiet after a track before the next one (the ambience carries the gap). */
export function restAfter(mood: Mood, random: () => number = Math.random): number {
  const [a, b] = MUSIC[mood].gap;
  return a + (b - a) * random();
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

/**
 * Where a sound sits for the listener: `gain` from distance (full up close, gone at
 * `range`), `pan` from the side it's on (-1 left .. 1 right), and `cutoff` (Hz) so far
 * sounds are duller, the way air and obstacles make them.
 */
export function placeSound(listener: Vec3, rightX: number, rightZ: number, at: Vec3, range: number) {
  const dx = at.x - listener.x;
  const dy = at.y - listener.y;
  const dz = at.z - listener.z;
  const d = Math.hypot(dx, dy, dz);
  const near = Math.max(0, 1 - d / range);
  const gain = near * near;
  const flat = Math.hypot(dx, dz);
  // Close sounds are nearly centred: panning a sound at your feet hard left sounds wrong.
  const side = flat > 1e-6 ? (dx * rightX + dz * rightZ) / flat : 0;
  const pan = Math.max(-1, Math.min(1, side * Math.min(1, d / (range * 0.08)) * 0.85));
  const cutoff = 18000 * Math.pow(0.18, Math.min(1, d / range));
  return { gain, pan, cutoff, distance: d };
}

/** The shortest gap between two plays of a kind (ms): stops a burst from stacking into noise. */
export const MIN_GAP_MS: Record<string, number> = {
  ui_hover: 70,
  ui_select: 40,
  step: 90,
  swing: 50,
  hit_bone: 35,
  hit_flesh: 35,
  hit_metal: 60,
  coins: 80,
  wing_flap: 180,
  dragon_step: 150,
  dragon_growl: 2500,
  dragon_roar: 1800,
  sw: 1500,
};

export function gapFor(kind: string): number {
  if (kind.startsWith('step_')) return MIN_GAP_MS.step;
  if (kind.startsWith('sw_')) return MIN_GAP_MS.sw;
  return MIN_GAP_MS[kind] ?? 0;
}

/** The ambient details that fit where you are and the hour, with how much each is wanted. */
export function sweetenersFor(daylight: number, lair: number, high: number): Array<[string, number]> {
  const out: Array<[string, number]> = [];
  const ground = (1 - lair) * (1 - high);
  if (daylight > 0.3) out.push(['sw_bird', 1.2 * daylight * ground]);
  out.push(['sw_leaves', 0.8 * ground]);
  out.push(['sw_gust', 0.5 + 0.8 * high]);
  if (lair > 0.2) out.push(['sw_drip', 1.5 * lair]);
  return out.filter(([, w]) => w > 0.05);
}

/** Pick by weight (`roll` in 0..1). */
export function weighted<T>(items: Array<[T, number]>, roll: number): T | null {
  const total = items.reduce((s, [, w]) => s + w, 0);
  if (total <= 0) return null;
  let r = roll * total;
  for (const [v, w] of items) {
    if ((r -= w) <= 0) return v;
  }
  return items[items.length - 1][0];
}
