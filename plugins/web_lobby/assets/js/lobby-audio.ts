// Web Lobby sound: effects through Web Audio (low latency, overlapping), music as
// a looping <audio> element. The files are the hub's original sounds under
// /audio/ (scripts/audio/make_sounds.py). Browsers only allow sound after the
// player has clicked or pressed a key, so nothing plays before that.

const EFFECTS: Record<string, string> = {
  throw: '/audio/lobby/throw.mp3',
  hit: '/audio/lobby/hit.mp3',
  hurt: '/audio/lobby/hurt.mp3',
  death: '/audio/lobby/death.mp3',
  respawn: '/audio/lobby/respawn.mp3',
  jump: '/audio/lobby/jump.mp3',
  land: '/audio/lobby/land.mp3',
  levelup: '/audio/lobby/levelup.mp3',
  step1: '/audio/lobby/footstep-1.mp3',
  step2: '/audio/lobby/footstep-2.mp3',
  step3: '/audio/lobby/footstep-3.mp3',
  step4: '/audio/lobby/footstep-4.mp3',
};
const MUSIC_URL = '/audio/music/arcade-lobby.mp3';
const PREF_KEY = 'web_lobby:sound';
const HEARING_RANGE = 40; // world units; matches roughly what the camera shows

function readPref(): boolean {
  try {
    return window.localStorage.getItem(PREF_KEY) !== 'off';
  } catch {
    return true;
  }
}

function writePref(on: boolean): void {
  try {
    window.localStorage.setItem(PREF_KEY, on ? 'on' : 'off');
  } catch {
    // private mode or blocked storage: the toggle still works for this visit
  }
}

export class LobbyAudio {
  enabled: boolean;
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private buffers = new Map<string, AudioBuffer>();
  private loading = new Map<string, Promise<AudioBuffer | null>>();
  private music: HTMLAudioElement | null = null;
  private wantMusic = false;
  private unlocked = false;
  private step = 0;

  constructor(private volume = 0.6, private musicVolume = 0.28) {
    this.enabled = readPref();
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
    if (this.enabled && this.wantMusic) this.startMusic();
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
    return this.ctx;
  }

  private load(name: string): Promise<AudioBuffer | null> {
    const cached = this.buffers.get(name);
    if (cached) return Promise.resolve(cached);
    const pending = this.loading.get(name);
    if (pending) return pending;
    const ctx = this.context();
    const url = EFFECTS[name];
    if (!ctx || !url) return Promise.resolve(null);
    const p = fetch(url)
      .then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(`${r.status} ${url}`))))
      .then((data) => ctx.decodeAudioData(data))
      .then((buf) => {
        this.buffers.set(name, buf);
        return buf;
      })
      .catch((err) => {
        console.warn('[LobbyAudio] could not load', url, err);
        return null;
      })
      .finally(() => this.loading.delete(name));
    this.loading.set(name, p);
    return p;
  }

  /** Fetch and decode every effect ahead of time (after the first click). */
  preload(): void {
    if (!this.unlocked) return;
    Object.keys(EFFECTS).forEach((name) => void this.load(name));
  }

  /** Play an effect; `distance` (world units) makes far-away sounds quieter. */
  play(name: string, gain = 1, distance = 0): void {
    if (!this.enabled || !this.unlocked) return;
    const falloff = Math.max(0, 1 - distance / HEARING_RANGE);
    if (falloff <= 0.02) return;
    const ctx = this.context();
    if (!ctx || !this.master) return;
    void this.load(name).then((buf) => {
      if (!buf || !this.ctx || !this.master) return;
      const src = this.ctx.createBufferSource();
      src.buffer = buf;
      src.playbackRate.value = name.startsWith('step') ? 0.95 + Math.random() * 0.1 : 1;
      const g = this.ctx.createGain();
      g.gain.value = gain * falloff * falloff;
      src.connect(g).connect(this.master);
      src.start();
    });
  }

  footstep(running: boolean): void {
    this.step = (this.step + 1) % 4;
    this.play(`step${this.step + 1}`, running ? 0.9 : 0.65);
  }

  /** Turn the lobby music on or off (it also needs sound to be enabled). */
  setMusic(on: boolean): void {
    this.wantMusic = on;
    if (on && this.enabled && this.unlocked) this.startMusic();
    else this.stopMusic();
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
    writePref(this.enabled);
    if (!this.enabled) this.stopMusic();
    else if (this.wantMusic && this.unlocked) this.startMusic();
    return this.enabled;
  }

  dispose(): void {
    window.removeEventListener('pointerdown', this.unlock);
    window.removeEventListener('keydown', this.unlock);
    this.stopMusic();
    if (this.music) this.music.src = '';
    this.music = null;
    this.buffers.clear();
    if (this.ctx) void this.ctx.close().catch(() => {});
    this.ctx = null;
    this.master = null;
  }
}

export default LobbyAudio;
