// Bacon World sound. Effects are real recordings (CC0; /audio/world/CREDITS.md), with
// spell, wing and breath sounds designed from them (library/pipeline/scripts/build_audio_v2.py):
// a voice for efforts and pain (a man's or a woman's, by body), footsteps by surface, weapon
// swings, hits, spells, the dragon, coins, chimes and a quiet UI. Each kind has several takes,
// picked so the same one never plays twice running, with a little pitch and level variety.
//
// Under it all: nature beds (birds and wind by day, crickets by night, a campfire near the
// camp, the lair's drips and draughts, wind high up) with rare details placed around you,
// and music by mood (day, night, the lair, the boss, the select screen): several tracks a
// mood, shuffled, with long rests between them so the music never wears thin.
//
// Everything plays through one Web Audio graph: effects and nature pan to where they come
// from and get duller with distance, and a gentle compressor on the master keeps a busy
// fight from getting loud. Browsers only allow sound after the player has clicked or pressed
// a key, so nothing plays before that.
//
// Three volumes (effects, nature, music; sliders in the game menu) and one switch for all
// sound (the player window's Sound button), remembered in this browser.

import { MUSIC, Playlist, gapFor, placeSound, restAfter, sweetenersFor, weighted, type Mood, type Vec3 } from './audio-mix';
import { UNITS_PER_METRE } from './controls-math';

const BASE = '/audio/world';

// Kinds with several takes: name -> number of files (<name>_1.mp3 ...).
const GROUPS: Record<string, number> = {
  voice_m_jump: 3,
  voice_m_attack: 3,
  voice_m_hurt: 5,
  voice_m_death: 3,
  voice_f_jump: 3,
  voice_f_attack: 3,
  voice_f_hurt: 3,
  voice_f_death: 2,
  land: 2,
  land_hard: 5,
  step_grass: 6,
  step_stone: 6,
  step_gravel: 5,
  step_wood: 9,
  step_dirt: 8,
  swing: 3,
  swing_more: 6,
  swing_heavy: 4,
  hit_bone: 3,
  hit_flesh: 2,
  hit_metal: 6,
  // spells (the skill tree's first ring)
  fireball_cast: 4,
  fireball_hit: 4,
  heal: 4,
  root_cast: 3,
  root_hit: 3,
  recall: 3,
  spin: 3,
  fizzle: 2,
  // the dragon (Baconator and the mounts)
  dragon_roar: 3,
  dragon_growl: 5,
  dragon_hurt: 3,
  dragon_breath: 3,
  dragon_step: 5,
  wing_flap: 5,
  // the UI
  ui_hover: 4,
  ui_select: 4,
  ui_open: 3,
  ui_close: 3,
  ui_error: 2,
  ui_learn: 2,
  ui_drag: 3,
  ui_drop: 3,
  // details placed around you
  sw_bird: 5,
  sw_leaves: 8,
  sw_gust: 5,
  sw_drip: 3,
};
const SINGLES = ['draw', 'bone_break', 'bone_collapse', 'coins', 'loot', 'equip', 'bag_open', 'level_up', 'respawn', 'click'];
// Loops that follow something (a cast, a fireball, the wind while flying).
const LOOPS = ['cast_loop_fire', 'cast_loop_holy', 'cast_loop_nature', 'cast_loop_arcane', 'fireball_fly', 'flight_wind'];
// A kind that draws its takes from several groups.
const POOLS: Record<string, string[]> = {
  swing: ['swing', 'swing_more'],
};
// Names the older code used, mapped to the new sounds.
const ALIASES: Record<string, string> = {
  throw: 'swing',
  hit: 'hit_flesh',
  levelup: 'level_up',
  jump: 'land',
};
// How far a kind carries (metres). Most things: about 33 m.
const RANGE_M: Record<string, number> = {
  dragon_roar: 120,
  dragon_breath: 70,
  dragon_growl: 50,
  dragon_step: 60,
  wing_flap: 60,
  fireball_hit: 55,
  bone_collapse: 40,
};
const DEFAULT_RANGE_M = 33;
const BEDS = ['amb_day', 'amb_birds', 'amb_wind', 'amb_night', 'amb_campfire', 'amb_lair', 'amb_high'];

const PREF_KEY = 'bacon_world:sound';
// Before the volume sliders (2026-10-22), music had an on/off switch of its own.
const MUSIC_KEY = 'bacon_world:music';
export type VolumeKind = 'effects' | 'ambience' | 'music';
const VOLUME_KEYS: Record<VolumeKind, string> = {
  effects: 'bacon_world:volume_effects',
  ambience: 'bacon_world:volume_ambience',
  music: 'bacon_world:volume_music',
};
const DEFAULT_VOLUME: Record<VolumeKind, number> = { effects: 0.8, ambience: 0.8, music: 0.5 };
// Each slider's full-up level. A slider sets level * v², which sounds even across its travel.
// The music is mastered at -21 LUFS, so it sits under the effects at these levels.
const FULL_LEVEL: Record<VolumeKind, number> = { effects: 1.1, ambience: 0.6, music: 0.7 };
// The key before the plugin was renamed from Web Lobby (2026-10-21).
const OLD_PREF_KEY = 'web_lobby:sound';
const MAX_VOICES = 28;

export type Voice = 'm' | 'f' | null;
export type Surface = 'grass' | 'stone' | 'gravel' | 'wood' | 'dirt';

function readPref(key: string, fallbackKey?: string): boolean {
  try {
    let value = window.localStorage.getItem(key);
    if (value === null && fallbackKey) {
      value = window.localStorage.getItem(fallbackKey);
      if (value !== null) {
        window.localStorage.setItem(key, value);
        window.localStorage.removeItem(fallbackKey);
      }
    }
    return value !== 'off';
  } catch {
    return true;
  }
}

function writePref(key: string, on: boolean): void {
  try {
    window.localStorage.setItem(key, on ? 'on' : 'off');
  } catch {
    // private mode or blocked storage: the toggle still works for this visit
  }
}

function readVolume(kind: VolumeKind): number {
  try {
    const raw = window.localStorage.getItem(VOLUME_KEYS[kind]);
    if (raw !== null && raw !== '' && Number.isFinite(Number(raw))) return Math.max(0, Math.min(1, Number(raw) / 100));
    if (kind === 'music' && window.localStorage.getItem(MUSIC_KEY) === 'off') return 0;
  } catch {
    // blocked storage: the default
  }
  return DEFAULT_VOLUME[kind];
}

function writeVolume(kind: VolumeKind, v: number): void {
  try {
    window.localStorage.setItem(VOLUME_KEYS[kind], String(Math.round(v * 100)));
  } catch {
    // the slider still works for this visit
  }
}

const level = (kind: VolumeKind, v: number) => FULL_LEVEL[kind] * v * v;

/** A sound that keeps playing until stopped (a cast, a fireball in flight, the wind). */
export interface LoopHandle {
  /** Change its level (0..1 of its own) and, for a placed loop, where it is. */
  set(gain: number, at?: Vec3): void;
  stop(fadeSeconds?: number): void;
}

interface MusicTrack {
  el: HTMLAudioElement;
  node: MediaElementAudioSourceNode | null;
  gain: GainNode;
}

export class LobbyAudio {
  enabled: boolean;
  /** Whose voice grunts and cries: the local character's body ('m' or 'f'). */
  voice: Voice = 'm';
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private fx: GainNode | null = null;
  private amb: GainNode | null = null;
  private mus: GainNode | null = null;
  private buffers = new Map<string, AudioBuffer>();
  private loading = new Map<string, Promise<AudioBuffer | null>>();
  private beds = new Map<string, { src: AudioBufferSourceNode; gain: GainNode }>();
  private wantMusic = false;
  private wantAmbience = false;
  private unlocked = false;
  private last = new Map<string, number>();
  private lastAt = new Map<string, number>();
  private voices: Array<{ src: AudioBufferSourceNode; gain: number }> = [];
  private daylight = 1;
  private campfire = 0;
  private lair = 0;
  private high = 0;
  private volumes: Record<VolumeKind, number> = {
    effects: readVolume('effects'),
    ambience: readVolume('ambience'),
    music: readVolume('music'),
  };
  private lastMusic = DEFAULT_VOLUME.music; // where Music goes back to when switched on again
  private lastPreview = 0;
  // the listener: the camera (or the player), for placing sounds
  private ear: Vec3 = { x: 0, y: 0, z: 0 };
  private right = { x: 1, z: 0 };
  // music
  private mood: Mood = 'day';
  private playlists = new Map<Mood, Playlist>();
  private track: MusicTrack | null = null;
  private fading: MusicTrack[] = [];
  private musicTimer: number | null = null;
  // details placed around you
  private sweetTimer: number | null = null;
  // UI hooks
  private uiRoots: Array<{ el: HTMLElement; off: () => void }> = [];

  constructor() {
    this.enabled = readPref(PREF_KEY, OLD_PREF_KEY);
    if (this.volumes.music > 0) this.lastMusic = this.volumes.music;
    this.unlock = this.unlock.bind(this);
    window.addEventListener('pointerdown', this.unlock);
    window.addEventListener('keydown', this.unlock);
  }

  private unlock(): void {
    if (this.unlocked) return;
    this.unlocked = true;
    window.removeEventListener('pointerdown', this.unlock);
    window.removeEventListener('keydown', this.unlock);
    this.context();
    if (this.enabled && this.wantMusic && this.musicOn) this.startMusic();
    if (this.enabled && this.wantAmbience) this.startBeds();
  }

  /** Music plays (its slider is above zero). */
  get musicOn(): boolean {
    return this.volumes.music > 0;
  }

  /** A slider's position, 0..1. */
  getVolume(kind: VolumeKind): number {
    return this.volumes[kind];
  }

  /** Move a slider (0..1): takes effect at once and is remembered in this browser. */
  setVolume(kind: VolumeKind, v: number): void {
    const value = Math.max(0, Math.min(1, v));
    this.volumes[kind] = value;
    writeVolume(kind, value);
    const node = kind === 'effects' ? this.fx : kind === 'ambience' ? this.amb : this.mus;
    if (node && this.ctx) node.gain.setTargetAtTime(level(kind, value), this.ctx.currentTime, 0.03);
    if (kind === 'music') {
      if (value > 0) this.lastMusic = value;
      if (value > 0 && this.wantMusic && this.enabled && this.unlocked && !this.track) this.startMusic();
      else if (value <= 0) this.stopMusic();
      return;
    }
    // A sample at the new level while the effects slider moves (a few a second at most).
    if (kind === 'effects') {
      const now = performance.now();
      if (now - this.lastPreview > 180) {
        this.lastPreview = now;
        this.play('coins', 0.6);
      }
    }
  }

  private context(): AudioContext | null {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
      return this.ctx;
    }
    const Ctor = (window as any).AudioContext || (window as any).webkitAudioContext;
    if (!Ctor) return null;
    this.ctx = new Ctor() as AudioContext;
    // master: a gentle compressor so a busy moment never gets loud, then a safety ceiling
    this.master = this.ctx.createGain();
    const comp = this.ctx.createDynamicsCompressor();
    comp.threshold.value = -20;
    comp.knee.value = 12;
    comp.ratio.value = 3;
    comp.attack.value = 0.008;
    comp.release.value = 0.25;
    this.master.connect(comp).connect(this.ctx.destination);
    this.fx = this.ctx.createGain();
    this.fx.gain.value = level('effects', this.volumes.effects);
    this.fx.connect(this.master);
    this.amb = this.ctx.createGain();
    this.amb.gain.value = level('ambience', this.volumes.ambience);
    this.amb.connect(this.master);
    this.mus = this.ctx.createGain();
    this.mus.gain.value = level('music', this.volumes.music);
    this.mus.connect(this.master);
    return this.ctx;
  }

  private file(name: string): string | null {
    if (SINGLES.includes(name) || BEDS.includes(name) || LOOPS.includes(name) || /_\d+$/.test(name)) return `${BASE}/${name}.mp3`;
    return null;
  }

  private load(name: string): Promise<AudioBuffer | null> {
    const cached = this.buffers.get(name);
    if (cached) return Promise.resolve(cached);
    const pending = this.loading.get(name);
    if (pending) return pending;
    const ctx = this.context();
    const url = this.file(name);
    if (!ctx || !url) return Promise.resolve(null);
    const p = fetch(url)
      .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(`${r.status} ${url}`))))
      .then((data) => ctx.decodeAudioData(data))
      .then((buf) => {
        this.buffers.set(name, buf);
        return buf;
      })
      .catch((err) => {
        console.warn('[audio] could not load', url, err);
        return null;
      })
      .finally(() => this.loading.delete(name));
    this.loading.set(name, p);
    return p;
  }

  /** Fetch and decode the common effects ahead of time (after the first click). */
  preload(): void {
    if (!this.unlocked) return;
    const common = ['voice_m', 'voice_f', 'land', 'step_', 'swing', 'hit_', 'ui_hover', 'ui_select', 'ui_open', 'ui_close'];
    for (const [g, n] of Object.entries(GROUPS)) {
      if (!common.some((c) => g.startsWith(c))) continue;
      for (let i = 1; i <= n; i++) void this.load(`${g}_${i}`);
    }
    SINGLES.forEach((s) => void this.load(s));
  }

  // A take of a kind, not the same one twice in a row.
  private pick(kind: string): string | null {
    const name = ALIASES[kind] ?? kind;
    const pool = POOLS[name];
    if (pool) {
      const total = pool.reduce((s, g) => s + (GROUPS[g] || 0), 0);
      const prev = this.last.get(name) ?? -1;
      let k = Math.floor(Math.random() * total);
      if (total > 1 && k === prev) k = (k + 1) % total;
      this.last.set(name, k);
      for (const g of pool) {
        const n = GROUPS[g] || 0;
        if (k < n) return `${g}_${k + 1}`;
        k -= n;
      }
    }
    const n = GROUPS[name];
    if (!n) return SINGLES.includes(name) || LOOPS.includes(name) ? name : null;
    if (n === 1) return `${name}_1`;
    const prev = this.last.get(name) ?? 0;
    let i = 1 + Math.floor(Math.random() * n);
    if (i === prev) i = (i % n) + 1;
    this.last.set(name, i);
    return `${name}_${i}`;
  }

  private tooSoon(kind: string): boolean {
    const gap = gapFor(kind);
    if (!gap) return false;
    const now = performance.now();
    if (now - (this.lastAt.get(kind) ?? -1e9) < gap) return true;
    this.lastAt.set(kind, now);
    return false;
  }

  /** Where sounds are heard from: the camera (position, and the direction to its right). */
  setListener(at: Vec3, rightX: number, rightZ: number): void {
    this.ear.x = at.x;
    this.ear.y = at.y;
    this.ear.z = at.z;
    const l = Math.hypot(rightX, rightZ) || 1;
    this.right.x = rightX / l;
    this.right.z = rightZ / l;
  }

  private range(kind: string): number {
    return (RANGE_M[kind] ?? DEFAULT_RANGE_M) * UNITS_PER_METRE;
  }

  /** Play an effect; `distance` (world units) makes far-away sounds quieter and duller. */
  play(kind: string, gain = 1, distance = 0, rate = 1): void {
    const range = this.range(ALIASES[kind] ?? kind);
    const near = Math.max(0, 1 - distance / range);
    this.voice_(kind, gain * near * near, 0, distance > 0 ? 18000 * Math.pow(0.18, Math.min(1, distance / range)) : 0, rate);
  }

  /** Play an effect from a place in the world: it pans to that side and dulls with distance. */
  playAt(kind: string, at: Vec3, gain = 1, rate = 1): void {
    const p = placeSound(this.ear, this.right.x, this.right.z, at, this.range(ALIASES[kind] ?? kind));
    this.voice_(kind, gain * p.gain, p.pan, p.cutoff, rate);
  }

  private voice_(kind: string, gain: number, pan: number, cutoff: number, rate: number): void {
    if (!this.enabled || !this.unlocked || gain <= 0.004) return;
    if (this.tooSoon(kind)) return;
    const name = this.pick(kind);
    const ctx = this.context();
    if (!name || !ctx || !this.fx) return;
    void this.load(name).then((buf) => {
      if (!buf || !this.ctx || !this.fx) return;
      // Too many at once: the quietest gives way (a big fight stays readable).
      if (this.voices.length >= MAX_VOICES) {
        this.voices.sort((a, b) => a.gain - b.gain);
        if (this.voices[0].gain > gain) return;
        try {
          this.voices.shift()!.src.stop();
        } catch {
          // already over
        }
      }
      const src = this.ctx.createBufferSource();
      src.buffer = buf;
      // A little pitch and level variety keeps repeats from sounding canned.
      src.playbackRate.value = rate * (0.95 + Math.random() * 0.1);
      const g = this.ctx.createGain();
      g.gain.value = gain * (0.88 + Math.random() * 0.12);
      let node: AudioNode = src;
      if (cutoff > 0 && cutoff < 17000) {
        const f = this.ctx.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = cutoff;
        node = node.connect(f);
      }
      if (pan && this.ctx.createStereoPanner) {
        const p = this.ctx.createStereoPanner();
        p.pan.value = pan;
        node = node.connect(p);
      }
      node.connect(g).connect(this.fx);
      const v = { src, gain };
      this.voices.push(v);
      src.onended = () => {
        const i = this.voices.indexOf(v);
        if (i >= 0) this.voices.splice(i, 1);
      };
      src.start();
    });
  }

  /** A grunt or cry in a voice (the local character's by default): 'jump', 'attack', 'hurt', 'death'. */
  say(kind: 'jump' | 'attack' | 'hurt' | 'death', gain = 0.8, distance = 0, voice: Voice = this.voice): void {
    if (!voice) return;
    this.play(`voice_${voice}_${kind}`, gain, distance);
  }

  footstep(running: boolean, surface: Surface = 'grass'): void {
    this.play(`step_${surface}`, running ? 0.55 : 0.4);
  }

  /**
   * A sound that keeps going (a cast, a fireball in flight, the wind while flying) until
   * stopped; null when sound is off. `at` places it in the world (it then follows `set`).
   */
  loop(kind: string, gain = 1, at?: Vec3, bus: 'fx' | 'amb' = 'fx'): LoopHandle | null {
    if (!this.enabled || !this.unlocked) return null;
    const ctx = this.context();
    const out = bus === 'fx' ? this.fx : this.amb;
    if (!ctx || !out) return null;
    const g = ctx.createGain();
    g.gain.value = 0;
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = 18000;
    const p = ctx.createStereoPanner ? ctx.createStereoPanner() : null;
    if (p) f.connect(p).connect(g).connect(out);
    else f.connect(g).connect(out);
    let src: AudioBufferSourceNode | null = null;
    let stopped = false;
    let want = gain;
    let where = at;
    const apply = (t = 0.08) => {
      if (!this.ctx) return;
      let k = want;
      if (where) {
        const pl = placeSound(this.ear, this.right.x, this.right.z, where, this.range(kind));
        k *= pl.gain;
        f.frequency.setTargetAtTime(pl.cutoff, this.ctx.currentTime, t);
        p?.pan.setTargetAtTime(pl.pan, this.ctx.currentTime, t);
      }
      g.gain.setTargetAtTime(k, this.ctx.currentTime, t);
    };
    void this.load(kind).then((buf) => {
      if (!buf || !this.ctx || stopped) return;
      src = this.ctx.createBufferSource();
      src.buffer = buf;
      src.loop = true;
      src.connect(f);
      src.start(0, Math.random() * buf.duration);
      apply(0.12);
    });
    return {
      set: (gainNow: number, atNow?: Vec3) => {
        want = gainNow;
        if (atNow) where = atNow;
        apply();
      },
      stop: (fade = 0.25) => {
        if (stopped) return;
        stopped = true;
        if (!this.ctx) return;
        g.gain.setTargetAtTime(0, this.ctx.currentTime, Math.max(0.02, fade / 3));
        const s = src;
        setTimeout(() => {
          try {
            s?.stop();
          } catch {
            // already stopped
          }
          g.disconnect();
        }, fade * 1000 + 200);
      },
    };
  }

  // ---------------------------------------------------------------- the UI

  /**
   * Quiet UI sounds for a window system: a soft tick when the pointer comes onto a button,
   * slot or row, a click when it's pressed, and a page sound when a window opens or closes.
   * Elements can opt out with data-sound="off", or pick their own with data-sound="<kind>".
   */
  attachUi(root: HTMLElement): void {
    const hoverSel = 'button, .btn, .slot, .row, .tab, [data-sound], .ab, .node';
    let lastHover: Element | null = null;
    const over = (e: Event) => {
      const t = (e.target as Element)?.closest?.(hoverSel);
      if (!t || t === lastHover) return;
      lastHover = t;
      if ((t as HTMLElement).dataset?.sound === 'off' || (t as HTMLButtonElement).disabled) return;
      this.play('ui_hover', 0.55);
    };
    const out = (e: Event) => {
      if (!(e as PointerEvent).relatedTarget || !root.contains((e as PointerEvent).relatedTarget as Node)) lastHover = null;
    };
    const down = (e: Event) => {
      const t = (e.target as Element)?.closest?.(hoverSel) as HTMLElement | null;
      if (!t || t.dataset?.sound === 'off' || (t as HTMLButtonElement).disabled) return;
      const own = t.dataset?.sound;
      this.play(own && own !== 'on' ? own : 'ui_select', 0.7);
    };
    root.addEventListener('pointerover', over);
    root.addEventListener('pointerout', out);
    root.addEventListener('pointerdown', down);
    // windows: a page turning as one opens, a book closing as it shuts
    const shown = new WeakMap<Element, boolean>();
    const visible = (el: HTMLElement) => el.style.display !== 'none' && getComputedStyle(el).display !== 'none';
    const mo = new MutationObserver((list) => {
      for (const m of list) {
        const el = m.target as HTMLElement;
        if (!el.classList?.contains('w')) continue;
        const now = visible(el);
        const was = shown.get(el) ?? !now;
        if (now !== was) this.play(now ? 'ui_open' : 'ui_close', 0.6);
        shown.set(el, now);
      }
    });
    mo.observe(root, { subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
    for (const el of Array.from(root.querySelectorAll<HTMLElement>('.w'))) shown.set(el, visible(el));
    this.uiRoots.push({
      el: root,
      off: () => {
        root.removeEventListener('pointerover', over);
        root.removeEventListener('pointerout', out);
        root.removeEventListener('pointerdown', down);
        mo.disconnect();
      },
    });
  }

  // ---------------------------------------------------------------- music

  /** Turn the music on or off for this scene (it also needs sound and the music setting on). */
  setMusic(on: boolean): void {
    this.wantMusic = on;
    if (on && this.enabled && this.unlocked && this.musicOn) this.startMusic();
    else this.stopMusic();
  }

  /**
   * The music's mood: 'menu' (the select screen), 'day', 'night', 'lair' (Baconator's
   * crags) or 'boss' (fighting him). A change crossfades; the same mood carries on.
   */
  setMood(mood: Mood): void {
    if (mood === this.mood) return;
    const from = this.mood;
    this.mood = mood;
    if (!this.wantMusic || !this.enabled || !this.unlocked || !this.musicOn) return;
    // Day and night share a rest: the next track simply comes from the new mood. Anything
    // else changes now.
    const quietSwap = (from === 'day' && mood === 'night') || (from === 'night' && mood === 'day');
    if (quietSwap && this.track) return;
    this.fadeOutTrack(mood === 'boss' ? 1.2 : 3.5);
    this.schedule(mood === 'boss' ? 0.3 : from === 'boss' ? 8 : 2.5);
  }

  private playlist(mood: Mood): Playlist {
    let p = this.playlists.get(mood);
    if (!p) this.playlists.set(mood, (p = new Playlist(MUSIC[mood].tracks)));
    return p;
  }

  private schedule(seconds: number): void {
    if (this.musicTimer) window.clearTimeout(this.musicTimer);
    this.musicTimer = window.setTimeout(() => {
      this.musicTimer = null;
      this.nextTrack();
    }, seconds * 1000);
  }

  private nextTrack(): void {
    if (!this.wantMusic || !this.enabled || !this.unlocked || !this.musicOn) return;
    const ctx = this.context();
    if (!ctx || !this.mus) return;
    const mood = this.mood;
    const n = this.playlist(mood).next();
    const el = new Audio(`${BASE}/music/${mood}_${n}.mp3`);
    el.preload = 'auto';
    el.loop = !!MUSIC[mood].loop;
    const gain = ctx.createGain();
    gain.gain.value = 0;
    let node: MediaElementAudioSourceNode | null = null;
    try {
      node = ctx.createMediaElementSource(el);
      node.connect(gain).connect(this.mus);
    } catch {
      el.volume = Math.min(1, level('music', this.volumes.music));
    }
    const track: MusicTrack = { el, node, gain };
    this.track = track;
    el.onended = () => {
      if (this.track !== track) return;
      this.drop(track);
      this.track = null;
      this.schedule(restAfter(mood));
    };
    void el
      .play()
      .then(() => gain.gain.setTargetAtTime(1, ctx.currentTime, mood === 'boss' ? 0.4 : 1.2))
      .catch(() => {});
  }

  private fadeOutTrack(seconds: number): void {
    const t = this.track;
    this.track = null;
    if (!t || !this.ctx) return;
    t.gain.gain.setTargetAtTime(0, this.ctx.currentTime, seconds / 3);
    this.fading.push(t);
    setTimeout(() => this.drop(t), seconds * 1000 + 300);
  }

  private drop(t: MusicTrack): void {
    t.el.pause();
    t.el.src = '';
    t.node?.disconnect();
    t.gain.disconnect();
    const i = this.fading.indexOf(t);
    if (i >= 0) this.fading.splice(i, 1);
  }

  private startMusic(): void {
    if (this.track || this.musicTimer) return;
    // the first track comes in after a breath, not on the click that unlocked sound
    this.schedule(this.mood === 'menu' ? 0.5 : 3);
  }

  private stopMusic(): void {
    if (this.musicTimer) window.clearTimeout(this.musicTimer);
    this.musicTimer = null;
    this.fadeOutTrack(1.0);
  }

  // ---------------------------------------------------------------- nature

  /** Nature sounds for the world (off on the select screen). */
  setAmbience(on: boolean): void {
    this.wantAmbience = on;
    if (on && this.enabled && this.unlocked) this.startBeds();
    else this.stopBeds();
  }

  /** 1 = full day (birds, wind), 0 = night (crickets). */
  setDaylight(d: number): void {
    this.daylight = Math.max(0, Math.min(1, d));
    this.mixBeds();
  }

  /** How close the campfire is: 1 next to it, 0 out of earshot. */
  setCampfire(nearness: number): void {
    this.campfire = Math.max(0, Math.min(1, nearness));
    this.mixBeds();
  }

  /** How deep into the lair (1 inside its crags) and how high up (1 well above the treetops). */
  setPlace(lair: number, high: number): void {
    this.lair = Math.max(0, Math.min(1, lair));
    this.high = Math.max(0, Math.min(1, high));
    this.mixBeds();
  }

  private mixBeds(): void {
    const d = this.daylight;
    const out = (1 - this.lair) * (1 - this.high * 0.8);
    const levels: Record<string, number> = {
      amb_day: 0.5 * d * out,
      amb_birds: 0.35 * d * d * out,
      amb_wind: (0.3 + 0.15 * (1 - d)) * (1 - this.lair * 0.6),
      amb_night: 0.55 * (1 - d) * (1 - d) * out,
      amb_campfire: 0.8 * this.campfire,
      amb_lair: 0.9 * this.lair,
      amb_high: 0.8 * this.high,
    };
    if (!this.ctx) return;
    for (const [name, b] of this.beds) b.gain.gain.setTargetAtTime(levels[name] ?? 0, this.ctx.currentTime, 0.8);
  }

  private startBeds(): void {
    const ctx = this.context();
    if (!ctx || !this.amb) return;
    for (const name of BEDS) {
      if (this.beds.has(name)) continue;
      void this.load(name).then((buf) => {
        if (!buf || !this.ctx || !this.amb || this.beds.has(name) || !this.wantAmbience || !this.enabled) return;
        const src = this.ctx.createBufferSource();
        src.buffer = buf;
        src.loop = true;
        const gain = this.ctx.createGain();
        gain.gain.value = 0;
        src.connect(gain).connect(this.amb);
        // Start each bed at a random point so the loops don't line up.
        src.start(0, Math.random() * buf.duration);
        this.beds.set(name, { src, gain });
        this.mixBeds();
      });
    }
    this.scheduleSweetener();
  }

  // A detail now and then (a bird call, leaves, a gust, a drip in the lair), somewhere
  // around you, quiet: what keeps the beds from sounding like loops.
  private scheduleSweetener(): void {
    if (this.sweetTimer) return;
    const wait = 5000 + Math.random() * 9000;
    this.sweetTimer = window.setTimeout(() => {
      this.sweetTimer = null;
      if (!this.wantAmbience || !this.enabled || !this.unlocked) return;
      const kind = weighted(sweetenersFor(this.daylight, this.lair, this.high), Math.random());
      if (kind && this.amb && this.ctx) {
        const name = this.pick(kind);
        if (name) {
          void this.load(name).then((buf) => {
            if (!buf || !this.ctx || !this.amb) return;
            const src = this.ctx.createBufferSource();
            src.buffer = buf;
            src.playbackRate.value = 0.94 + Math.random() * 0.12;
            const g = this.ctx.createGain();
            g.gain.value = 0.55 + Math.random() * 0.35;
            const p = this.ctx.createStereoPanner ? this.ctx.createStereoPanner() : null;
            if (p) {
              p.pan.value = (Math.random() * 2 - 1) * 0.8;
              src.connect(p).connect(g).connect(this.amb);
            } else src.connect(g).connect(this.amb);
            src.start();
          });
        }
      }
      this.scheduleSweetener();
    }, wait);
  }

  private stopBeds(): void {
    for (const b of this.beds.values()) {
      try {
        b.src.stop();
      } catch {
        // already stopped
      }
      b.src.disconnect();
    }
    this.beds.clear();
    if (this.sweetTimer) window.clearTimeout(this.sweetTimer);
    this.sweetTimer = null;
  }

  /** Sound on/off for this browser; returns the new state. */
  toggle(): boolean {
    this.enabled = !this.enabled;
    writePref(PREF_KEY, this.enabled);
    if (!this.enabled) {
      this.stopMusic();
      this.stopBeds();
    } else if (this.unlocked) {
      if (this.wantMusic && this.musicOn) this.startMusic();
      if (this.wantAmbience) this.startBeds();
    }
    return this.enabled;
  }

  /** Music off, or back to where its slider was; returns whether it plays. */
  toggleMusic(): boolean {
    this.setVolume('music', this.musicOn ? 0 : this.lastMusic || DEFAULT_VOLUME.music);
    return this.musicOn;
  }

  dispose(): void {
    window.removeEventListener('pointerdown', this.unlock);
    window.removeEventListener('keydown', this.unlock);
    for (const r of this.uiRoots) r.off();
    this.uiRoots = [];
    this.stopMusic();
    this.stopBeds();
    for (const t of [...this.fading]) this.drop(t);
    this.buffers.clear();
    if (this.ctx) void this.ctx.close().catch(() => {});
    this.ctx = null;
    this.master = null;
  }
}

export default LobbyAudio;
