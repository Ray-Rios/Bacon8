// Bacon World sound. Effects are real recordings (CC0; /audio/world/CREDITS.md):
// a voice for efforts and pain (a man's or a woman's, by body), footsteps by surface, weapon swings, hits on bone
// and on flesh, coins, chimes. Each kind has a few takes picked at random so
// nothing repeats exactly. Under it all: nature (birds and wind by day, crickets
// by night, a campfire near the camp) and a quiet ambient music bed.
//
// Effects and nature play through Web Audio (low latency, gapless loops); the music
// is a looping <audio> element. Browsers only allow sound after the player has
// clicked or pressed a key, so nothing plays before that.

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
  step_grass: 5,
  step_stone: 6,
  step_gravel: 5,
  swing: 3,
  hit_bone: 3,
  hit_flesh: 2,
};
const SINGLES = ['draw', 'bone_break', 'bone_collapse', 'coins', 'loot', 'equip', 'bag_open', 'level_up', 'respawn', 'click'];
// Names the older code used, mapped to the new sounds.
const ALIASES: Record<string, string> = {
  throw: 'swing',
  hit: 'hit_flesh',
  levelup: 'level_up',
  jump: 'land',
};
const BEDS = ['amb_day', 'amb_birds', 'amb_wind', 'amb_night', 'amb_campfire'];
const MUSIC_URL = `${BASE}/music_ambient.mp3`;

const PREF_KEY = 'bacon_world:sound';
const MUSIC_KEY = 'bacon_world:music';
// The key before the plugin was renamed from Web Lobby (2026-10-21).
const OLD_PREF_KEY = 'web_lobby:sound';
const HEARING_RANGE = 40; // world units

export type Voice = 'm' | 'f' | null;
export type Surface = 'grass' | 'stone' | 'gravel';

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

export class LobbyAudio {
  enabled: boolean;
  musicOn: boolean;
  /** Whose voice grunts and cries: the local character's body ('m' or 'f'). */
  voice: Voice = 'm';
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private fx: GainNode | null = null;
  private amb: GainNode | null = null;
  private buffers = new Map<string, AudioBuffer>();
  private loading = new Map<string, Promise<AudioBuffer | null>>();
  private beds = new Map<string, { src: AudioBufferSourceNode; gain: GainNode }>();
  private music: HTMLAudioElement | null = null;
  private wantMusic = false;
  private wantAmbience = false;
  private unlocked = false;
  private last = new Map<string, number>();
  private daylight = 1;
  private campfire = 0;

  constructor(private volume = 0.7, private musicVolume = 0.16) {
    this.enabled = readPref(PREF_KEY, OLD_PREF_KEY);
    this.musicOn = readPref(MUSIC_KEY);
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

  private context(): AudioContext | null {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
      return this.ctx;
    }
    const Ctor = (window as any).AudioContext || (window as any).webkitAudioContext;
    if (!Ctor) return null;
    this.ctx = new Ctor() as AudioContext;
    this.master = this.ctx.createGain();
    this.master.gain.value = this.volume;
    this.master.connect(this.ctx.destination);
    this.fx = this.ctx.createGain();
    this.fx.connect(this.master);
    this.amb = this.ctx.createGain();
    this.amb.gain.value = 0.55;
    this.amb.connect(this.master);
    return this.ctx;
  }

  private file(name: string): string | null {
    if (SINGLES.includes(name) || BEDS.includes(name) || /_\d+$/.test(name)) return `${BASE}/${name}.mp3`;
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
    for (const [g, n] of Object.entries(GROUPS)) for (let i = 1; i <= n; i++) void this.load(`${g}_${i}`);
    SINGLES.forEach((s) => void this.load(s));
  }

  // A take of a kind, not the same one twice in a row.
  private pick(kind: string): string | null {
    const name = ALIASES[kind] ?? kind;
    const n = GROUPS[name];
    if (!n) return SINGLES.includes(name) ? name : null;
    const prev = this.last.get(name) ?? 0;
    let i = 1 + Math.floor(Math.random() * n);
    if (n > 1 && i === prev) i = (i % n) + 1;
    this.last.set(name, i);
    return `${name}_${i}`;
  }

  /** Play an effect; `distance` (world units) makes far-away sounds quieter. */
  play(kind: string, gain = 1, distance = 0, rate = 1): void {
    if (!this.enabled || !this.unlocked) return;
    const falloff = Math.max(0, 1 - distance / HEARING_RANGE);
    if (falloff <= 0.02) return;
    const name = this.pick(kind);
    const ctx = this.context();
    if (!name || !ctx || !this.fx) return;
    void this.load(name).then((buf) => {
      if (!buf || !this.ctx || !this.fx) return;
      const src = this.ctx.createBufferSource();
      src.buffer = buf;
      // A little pitch variety keeps repeats from sounding canned.
      src.playbackRate.value = rate * (0.94 + Math.random() * 0.12);
      const g = this.ctx.createGain();
      g.gain.value = gain * falloff * falloff;
      src.connect(g).connect(this.fx);
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

  // ---------------------------------------------------------------- music and nature

  /** Turn the music on or off for this scene (it also needs sound and the music setting on). */
  setMusic(on: boolean): void {
    this.wantMusic = on;
    if (on && this.enabled && this.unlocked && this.musicOn) this.startMusic();
    else this.stopMusic();
  }

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

  private mixBeds(): void {
    const d = this.daylight;
    const levels: Record<string, number> = {
      amb_day: 0.5 * d,
      amb_birds: 0.35 * d * d,
      amb_wind: 0.3 + 0.15 * (1 - d),
      amb_night: 0.55 * (1 - d) * (1 - d),
      amb_campfire: 0.8 * this.campfire,
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
  }

  private startMusic(): void {
    if (!this.music) {
      this.music = new Audio(MUSIC_URL);
      this.music.loop = true;
      this.music.preload = 'auto';
    }
    this.music.volume = this.musicVolume;
    void this.music.play().catch(() => {});
  }

  private stopMusic(): void {
    this.music?.pause();
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

  /** Music on/off for this browser (nature sounds stay); returns the new state. */
  toggleMusic(): boolean {
    this.musicOn = !this.musicOn;
    writePref(MUSIC_KEY, this.musicOn);
    if (this.musicOn && this.wantMusic && this.enabled && this.unlocked) this.startMusic();
    else this.stopMusic();
    return this.musicOn;
  }

  dispose(): void {
    window.removeEventListener('pointerdown', this.unlock);
    window.removeEventListener('keydown', this.unlock);
    this.stopMusic();
    this.stopBeds();
    if (this.music) this.music.src = '';
    this.music = null;
    this.buffers.clear();
    if (this.ctx) void this.ctx.close().catch(() => {});
    this.ctx = null;
    this.master = null;
  }
}

export default LobbyAudio;
