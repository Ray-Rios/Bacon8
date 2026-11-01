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
  private count: number;
  private random: () => number;
  constructor(count: number, random: () => number = Math.random) {
    this.count = count;
    this.random = random;
  }

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
  water_wading: 220,
  water_splash: 250,
  fire_snap: 1800,
  thunder: 8000,
  owl: 7000,
  woodpecker: 6000,
  wind_gust: 3000,
};

export function gapFor(kind: string): number {
  if (kind.startsWith('step_')) return MIN_GAP_MS.step;
  if (kind.startsWith('sw_')) return MIN_GAP_MS.sw;
  if (kind.startsWith('water_wading') || kind === 'water_17_water_wading_slosh') return MIN_GAP_MS.water_wading;
  if (kind.startsWith('water_splash')) return MIN_GAP_MS.water_splash;
  if (kind.startsWith('fire_')) return MIN_GAP_MS.fire_snap;
  if (kind.startsWith('thunder_')) return MIN_GAP_MS.thunder;
  if (kind === 'owl' || kind.startsWith('bird_owl')) return MIN_GAP_MS.owl;
  if (kind === 'woodpecker') return MIN_GAP_MS.woodpecker;
  if (kind === 'wind_gust') return MIN_GAP_MS.wind_gust;
  return MIN_GAP_MS[kind] ?? 0;
}

/** The ambient details that fit where you are and the hour, with how much each is wanted. */
export function sweetenersFor(
  daylight: number,
  lair: number,
  high: number,
  lake = 0,
  ocean = 0,
  fire = 0,
  forest = 0,
  rain = 0,
  time = 0.5
): Array<[string, number]> {
  const out: Array<[string, number]> = [];
  const ground = (1 - lair) * (1 - high);

  // General ground sweeteners
  out.push(['sw_leaves', 0.8 * ground * (1 - rain * 0.7)]);
  out.push(['sw_gust', (0.5 + 0.8 * high) * (1 + rain * 0.5)]);
  if (high > 0.25) out.push(['wind_gust', 1.2 * high]);

  // Birds and wildlife by day/night
  if (daylight > 0.3) {
    out.push(['sw_bird', 1.0 * daylight * ground * (1 - rain * 0.8)]);
    out.push(['bird_song', 1.2 * daylight * ground * (1 - rain * 0.8)]);
    // Hot noon cicadas
    if (time >= 0.42 && time <= 0.65 && rain < 0.2) {
      out.push(['cicada', 1.4 * daylight * ground]);
    }
  } else {
    // Nocturnal insects & owls
    out.push(['night_cricket', 1.3 * (1 - daylight) * ground * (1 - rain * 0.6)]);
    out.push(['owl', 0.8 * (1 - daylight) * (forest * 0.8 + 0.2) * (1 - rain * 0.5)]);
  }

  // Deep forest
  if (forest > 0.2) {
    out.push(['tree_creak', 1.1 * forest * (1 - high)]);
    if (daylight > 0.35 && rain < 0.3) {
      out.push(['woodpecker', 1.0 * forest * daylight]);
    }
  }

  // Lair & subterranean
  if (lair > 0.2) {
    out.push(['sw_drip', 1.5 * lair]);
    out.push(['water_drip', 1.2 * lair]);
    out.push(['fire_flare', 0.8 * lair]);
  }

  // Campfire / fire sources
  if (fire > 0.15) {
    out.push(['fire_snap', 1.5 * fire]);
    out.push(['fire_burst', 0.9 * fire]);
    out.push(['fire_sizzle', 0.7 * fire]);
  }

  // Lakes & ocean
  if (lake > 0.15) {
    if (daylight < 0.45) out.push(['water_frog', 1.3 * lake * (1 - daylight)]);
    out.push(['water_drip', 0.6 * lake]);
  }
  if (ocean > 0.2) {
    out.push(['water_wave_wash', 1.5 * ocean]);
  }

  // Rain & storms
  if (rain > 0.2) {
    out.push(['rain_puddle_gust', 1.2 * rain]);
    if (rain > 0.55) {
      out.push(['thunder_distant', 1.5 * rain]);
    }
    if (rain > 0.8) {
      out.push(['thunder_strike', 1.2 * rain]);
    }
  }

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
