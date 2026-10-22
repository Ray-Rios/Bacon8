#!/usr/bin/env python3
"""Build Bacon8's original sound effects and music.

Every sound is synthesized from scratch by scripts/audio/synth.py; no samples,
loops or presets from anywhere else are used.

Writes (from the repository root):
    priv/static/audio/ui/*.mp3       desktop and site sounds (served at /audio/ui/...)
    priv/static/audio/music/*.mp3    the Bacon8 sting
and, when the game repository is checked out beside this one (./RaysSpaceSim):
    RaysSpaceSim/SourceAssets/Audio/{SFX,UI,Music}/*.wav   48 kHz 16-bit, for import into Unreal

Run in a throwaway container from the repository root (nothing is built on the PC):

    docker run --rm -v "$(pwd -W):/work" -w /work python:3.12-slim \\
      sh -c "pip install -q numpy scipy lameenc && python scripts/audio/make_sounds.py"

`--only NAME` builds just the sounds whose names contain NAME (quick iteration).
"""
import argparse
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from synth import *  # noqa: E402,F401,F403
from synth import SR  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
HUB = ROOT / "priv" / "static" / "audio"
GAME = ROOT / "RaysSpaceSim" / "SourceAssets" / "Audio"


# ================================================================ instruments

def bell(f, seconds=1.0, tau=0.4, ratio=3.5, index=1.6, idx_tau=0.12, bright=0.25):
    t = t_axis(seconds)
    tone = fm(f, ratio, index, seconds, index_env=np.exp(-t / idx_tau))
    tone += bright * sine(f * 2.76, seconds) * np.exp(-t / (tau * 0.35))
    return tone * decay(seconds, tau, 0.0015)


def marimba(f, seconds=0.6, tau=0.18):
    t = t_axis(seconds)
    tone = fm(f, 1.0, 1.4, seconds, index_env=np.exp(-t / 0.03)) + 0.3 * sine(f * 4.0, seconds) * np.exp(-t / 0.02)
    return tone * decay(seconds, tau, 0.001)


def blip(f0, f1, seconds, tau, shape="sine"):
    f = glide(f0, f1, seconds)
    osc = {"sine": sine, "triangle": triangle}[shape](f)
    return osc * decay(seconds, tau, 0.002)


def whoosh(seconds, f0, f1, q=1.2, seed=0, swell=0.4, color="white"):
    nz = noise(seconds, color, seed)
    f = glide(f0, f1, seconds)
    body = sweep(nz, f, q=q, kind="bp")
    env = points(seconds, [(0, 0), (seconds * swell, 1), (seconds, 0)], curve=1.6)
    return body * env


def kick(seconds=0.45):
    t = t_axis(seconds)
    f = 44 + 120 * np.exp(-t / 0.032)
    body = sine(f) * np.exp(-t / 0.17)
    click = hp(noise(seconds, seed=3), 2500) * np.exp(-t / 0.004) * 0.35
    return soft_clip((body + click) * 1.3, 1.6)


def snare(seconds=0.35, seed=5):
    t = t_axis(seconds)
    tone = (sine(188, seconds) * 0.6 + sine(331, seconds) * 0.25) * np.exp(-t / 0.055)
    nz = bp(noise(seconds, seed=seed), 1400, 9000) * np.exp(-t / 0.10)
    return tone * 0.6 + nz


def clap(seconds=0.3, seed=9):
    t = t_axis(seconds)
    nz = bp(noise(seconds, seed=seed), 900, 6000)
    env = np.zeros_like(t)
    for k, off in enumerate((0.0, 0.011, 0.022)):
        env += (t >= off) * np.exp(-np.clip(t - off, 0, None) / (0.006 if k < 2 else 0.07))
    return nz * env * 0.8


def hat(open_=False, seed=11):
    seconds = 0.32 if open_ else 0.07
    t = t_axis(seconds)
    nz = hp(noise(seconds, seed=seed), 7500, 4)
    metal = sum(square(f, seconds) for f in (3150, 4610, 5550, 6870)) / 4
    x = nz * 0.8 + hp(metal, 6000, 2) * 0.25
    return x * np.exp(-t / (0.085 if open_ else 0.013))


def bass_note(f, seconds):
    x = saw(f, seconds) * 0.65 + square(f / 2, seconds) * 0.35
    env = adsr(seconds, 0.003, 0.09, 0.55, min(0.05, seconds * 0.3))
    cutoff = 260 + 1500 * decay(seconds, 0.08, 0.001)
    return sweep(x * env, cutoff, q=1.1)


def pad_chord(notes, seconds, attack=0.35, release=0.6, cutoff=2300, detune=14, voices=5):
    x = sum(supersaw(midi(n), seconds, voices=voices, detune_cents=detune, seed=i) for i, n in enumerate(notes)) / len(notes)
    env = adsr(seconds, attack, 0.5, 0.8, release)
    return lp(x * env, cutoff, 2)


def pluck(f, seconds=0.2, pw=0.35, tau=0.07):
    x = square(f, seconds, pw=pw) * 0.55 + saw(f * 2, seconds) * 0.12
    env = decay(seconds, tau, 0.002)
    cutoff = 900 + 5200 * decay(seconds, 0.045, 0.001)
    return sweep(x * env, cutoff, q=1.0)


def lead_note(f, seconds):
    t = t_axis(seconds)
    vib = 1 + 0.0055 * np.sin(2 * np.pi * 5.4 * t) * np.clip((t - 0.18) / 0.25, 0, 1)
    x = square(f * vib, pw=0.42) * 0.5 + saw(f * vib * 1.004) * 0.45
    env = adsr(seconds, 0.012, 0.18, 0.72, min(0.12, seconds * 0.35))
    return lp(x * env, 3300, 2)


# ================================================================ UI (hub)

def ui_notification():
    a = bell(midi(81), 1.1, tau=0.38, ratio=3.5, index=1.2)          # A5
    b = bell(midi(88), 1.1, tau=0.45, ratio=3.5, index=1.2)          # E6
    buf = np.zeros((n_of(1.3), 2))
    mix_into(buf, stereo(a, -0.15), 0.0, 0.75)
    mix_into(buf, stereo(b, 0.15), 0.09, 0.9)
    return master(reverb(buf, 1.2, wet=0.18), peak_db=-4)


def ui_message():
    x = blip(760, 1500, 0.22, 0.06) * 0.9 + blip(1520, 3000, 0.22, 0.03) * 0.12
    return master(reverb(stereo(fade(x)), 0.6, wet=0.12), peak_db=-7)


def ui_send():
    w = whoosh(0.2, 700, 4200, q=1.6, seed=21, swell=0.75)
    tip = np.zeros(n_of(0.26))
    mix_into(tip, blip(1700, 2100, 0.06, 0.02), 0.16)
    x = concat(w, np.zeros(n_of(0.06))) * 0.6 + tip * 0.5
    return master(stereo(fade(x)), peak_db=-9)


def ui_click():
    t = t_axis(0.05)
    x = hp(noise(0.05, seed=31), 2000) * np.exp(-t / 0.0025) * 0.6 + sine(2300, 0.05) * np.exp(-t / 0.008) * 0.5
    return master(stereo(fade(x, 0.0005, 0.005)), peak_db=-12)


def ui_open():
    s = 0.3
    body = triangle(glide(330, 620, s)) * points(s, [(0, 0), (0.05, 1), (s, 0)], 1.5)
    air = whoosh(s, 400, 2600, q=1.0, seed=41, swell=0.6) * 0.35
    tail = np.zeros(n_of(s))
    mix_into(tail, bell(1760, 0.2, tau=0.06, index=0.6) * 0.18, 0.12)
    return master(reverb(stereo(fade(body * 0.5 + air + tail)), 0.7, wet=0.15), peak_db=-10)


def ui_close():
    s = 0.24
    body = triangle(glide(600, 300, s)) * points(s, [(0, 0), (0.02, 1), (s, 0)], 1.6)
    air = whoosh(s, 2200, 500, q=1.0, seed=43, swell=0.3) * 0.3
    return master(reverb(stereo(fade(body * 0.5 + air)), 0.6, wet=0.12), peak_db=-11)


def ui_error():
    buf = np.zeros(n_of(0.42))
    for at, f in ((0.0, 233.1), (0.13, 207.7)):
        s = 0.16
        x = lp(square(f, s, pw=0.4), 1300, 2) * decay(s, 0.07, 0.003)
        mix_into(buf, x, at)
    return master(reverb(stereo(fade(buf)), 0.5, wet=0.1), peak_db=-8)


def ui_success():
    buf = np.zeros((n_of(1.2), 2))
    for i, n in enumerate((72, 76, 79, 84)):                         # C5 E5 G5 C6
        mix_into(buf, stereo(marimba(midi(n), 0.7, tau=0.22), -0.2 + i * 0.13), i * 0.065, 0.85)
    return master(reverb(buf, 1.4, wet=0.22), peak_db=-6)


def ui_gems():
    rng = np.random.default_rng(88)
    scale = [84, 86, 88, 91, 93, 96, 98, 100]                         # C major pentatonic, high
    buf = np.zeros((n_of(1.5), 2))
    for i in range(11):
        n = scale[min(len(scale) - 1, i * len(scale) // 11 + int(rng.integers(0, 2)))]
        mix_into(buf, stereo(bell(midi(n), 0.6, tau=0.16, ratio=2.0, index=0.9, bright=0.1), rng.uniform(-0.7, 0.7)),
                 i * 0.045 + rng.uniform(0, 0.01), 0.45)
    body = marimba(midi(60), 0.5, tau=0.12)
    mix_into(buf, stereo(body), 0.0, 0.6)
    return master(reverb(buf, 1.8, wet=0.28), peak_db=-7)


# ================================================================ Bacon World

def lobby_footstep(variant):
    rng = np.random.default_rng(100 + variant)
    s = 0.16
    t = t_axis(s)
    cutoff = 500 + 250 * variant
    scuff = lp(noise(s, "pink", 200 + variant), cutoff, 2) * np.exp(-t / (0.035 + 0.008 * variant))
    thump = sine(80 + 12 * variant, s) * np.exp(-t / 0.045)
    tick = hp(noise(s, seed=300 + variant), 3000) * np.exp(-t / 0.002) * 0.25
    x = scuff * 0.8 + thump * 0.7 + tick
    return master(stereo(fade(x, 0.0005, 0.02), rng.uniform(-0.1, 0.1)), peak_db=-14)


def lobby_jump():
    s = 0.32
    hup = triangle(glide(210, 470, s)) * points(s, [(0, 0), (0.03, 1), (0.16, 0.4), (s, 0)], 1.3)
    cloth = whoosh(s, 900, 3200, q=0.9, seed=51, swell=0.35) * 0.4
    return master(stereo(fade(hup * 0.6 + cloth)), peak_db=-9)


def lobby_land():
    s = 0.3
    t = t_axis(s)
    x = sine(glide(95, 55, s)) * np.exp(-t / 0.09) + lp(noise(s, "pink", 61), 420, 2) * np.exp(-t / 0.07) * 0.8
    x += hp(noise(s, seed=62), 2500) * np.exp(-t / 0.003) * 0.2
    return master(stereo(fade(x)), peak_db=-9)


def lobby_throw():
    s = 0.36
    nz = noise(s, seed=71)
    f = points(s, [(0, 500), (0.12, 2600), (s, 1100)])
    body = sweep(nz, f, q=1.5, kind="bp") * points(s, [(0, 0), (0.11, 1), (s, 0)], 1.4)
    pan_path = np.linspace(-0.5, 0.5, n_of(s))
    a = (pan_path + 1) * np.pi / 4
    st = np.stack([body * np.cos(a), body * np.sin(a)], axis=1)
    return master(fade(st), peak_db=-8)


def lobby_hit():
    s = 0.32
    t = t_axis(s)
    crack = bp(noise(s, seed=81), 1200, 4200) * np.exp(-t / 0.008)
    knock = sine(glide(330, 250, s)) * np.exp(-t / 0.06)
    thump = sine(110, s) * np.exp(-t / 0.08)
    x = crack * 0.9 + knock * 0.8 + thump * 0.5
    return master(reverb(stereo(fade(x)), 0.5, wet=0.12), peak_db=-6)


def lobby_hurt():
    s = 0.3
    x = lp(square(glide(560, 180, s), pw=0.4), 1500, 2) * points(s, [(0, 0), (0.01, 1), (s, 0)], 1.6)
    x = soft_clip(x * 1.2, 1.2) + sine(glide(280, 90, s)) * points(s, [(0, 0), (0.01, 1), (s, 0)], 1.6) * 0.4
    return master(stereo(fade(x)), peak_db=-8)


def lobby_death():
    buf = np.zeros(n_of(1.8))
    for i, (n, d) in enumerate(((69, 0.22), (65, 0.22), (62, 0.7))):   # A4 F4 D4
        s = d + 0.25
        x = lp(square(midi(n) * glide(1.0, 0.985 if i == 2 else 1.0, s, "lin"), pw=0.45), 1800, 2)
        x *= adsr(s, 0.01, 0.1, 0.6, 0.25)
        mix_into(buf, x * 0.6, i * 0.24)
    fall = whoosh(1.2, 1800, 120, q=0.8, seed=91, swell=0.15) * 0.25
    mix_into(buf, fall, 0.05)
    return master(reverb(stereo(fade(buf)), 1.6, wet=0.22), peak_db=-6)


def lobby_respawn():
    buf = np.zeros((n_of(1.6), 2))
    notes = (69, 72, 74, 76, 79, 81, 84, 86, 88, 93)                   # A minor pentatonic, rising
    for i, n in enumerate(notes):
        mix_into(buf, stereo(bell(midi(n), 0.5, tau=0.14, ratio=2.0, index=0.8, bright=0.1), -0.6 + i * 0.13), i * 0.06, 0.5)
    rise = whoosh(0.8, 300, 5000, q=0.7, seed=95, swell=0.9) * 0.2
    mix_into(buf, stereo(rise), 0.0)
    return master(reverb(buf, 2.0, wet=0.3), peak_db=-6)


def lobby_levelup():
    buf = np.zeros((n_of(1.9), 2))
    for i, n in enumerate((72, 76, 79)):
        x = lp(square(midi(n), 0.16, pw=0.4) * 0.5 + saw(midi(n), 0.16) * 0.3, 3500, 2) * adsr(0.16, 0.005, 0.05, 0.7, 0.05)
        mix_into(buf, stereo(x, -0.2 + i * 0.2), i * 0.1, 0.8)
    chord = sum(lp(square(midi(n), 1.2, pw=0.4) * 0.4 + saw(midi(n) * 1.003, 1.2) * 0.4, 3000, 2) for n in (72, 76, 79, 84)) / 4
    chord *= adsr(1.2, 0.01, 0.3, 0.6, 0.6)
    mix_into(buf, stereo(chord), 0.3, 1.0)
    return master(reverb(buf, 1.8, wet=0.25), peak_db=-6)


# ================================================================ RaysSpaceSim (game)

def _seamless(x, overlap):
    """Crossfade the last `overlap` seconds into the start so the clip loops."""
    k = n_of(overlap)
    head, body, tail = x[:k], x[k:-k], x[-k:]
    ramp = np.linspace(0, 1, k)
    if x.ndim == 2:
        ramp = ramp[:, None]
    return concat(tail * (1 - ramp) + head * ramp, body)


def game_thruster_loop():
    s = 5.0
    t = t_axis(s)
    rumble = lp(noise(s, "brown", 401), 260, 2)
    hiss = bp(noise(s, seed=402), 1800, 6000) * 0.08
    hum = (sine(55, s) * 0.5 + sine(110.4, s) * 0.25) * (1 + 0.15 * np.sin(2 * np.pi * 7 * t))
    l = rumble + hiss + hum * 0.4
    r = lp(noise(s, "brown", 403), 260, 2) + bp(noise(s, seed=404), 1800, 6000) * 0.08 + hum * 0.4
    x = _seamless(hp(np.stack([l, r], axis=1), 25), 1.0)
    return normalize(x, -3)


def game_boost():
    s = 1.7
    growl = lp(saw(glide(70, 190, s)) * 0.5 + saw(glide(70.5, 191, s)) * 0.5, 900, 2)
    w = whoosh(s, 200, 3200, q=0.8, seed=411, swell=0.7)
    env = points(s, [(0, 0), (0.15, 0.7), (1.1, 1), (s, 0)])
    return master(reverb(stereo(fade((growl * 0.6 + w * 0.6) * env)), 1.2, wet=0.15), peak_db=-3)


def game_warp_jump():
    total = 4.2
    buf = np.zeros((n_of(total), 2))
    s = 1.9
    t = t_axis(s)
    charge = sine(glide(90, 1400, s)) * (0.6 + 0.4 * np.sin(2 * np.pi * glide(4, 28, s, "lin").cumsum() / SR))
    charge *= points(s, [(0, 0), (1.6, 1), (s, 1)], 1.8)
    mix_into(buf, stereo(charge * 0.5), 0.0)
    mix_into(buf, stereo(whoosh(s, 300, 6000, q=0.9, seed=421, swell=0.98) * 0.35), 0.0)
    b = 2.3
    tb = t_axis(b)
    boom = sine(glide(120, 28, b)) * np.exp(-tb / 0.5) + lp(noise(b, "pink", 422), 900, 2) * np.exp(-tb / 0.35) * 0.7
    mix_into(buf, stereo(boom), s, 1.0)
    return master(reverb(buf, 3.0, wet=0.3, width=1.3), peak_db=-1.5)


def game_laser():
    s = 0.4
    t = t_axis(s)
    f = glide(1900, 260, 0.18)
    f = np.concatenate([f, np.full(n_of(s) - len(f), 260.0)])
    x = square(f, pw=0.3) * 0.5 + fm(f, 1.5, 2.0, s, index_env=np.exp(-t / 0.05)) * 0.5
    x = lp(x, 5000, 2) * decay(s, 0.08, 0.001)
    return master(delay(stereo(fade(x)), 0.09, feedback=0.3, mix=0.25, tone=3000, pingpong=True), peak_db=-5)


def game_explosion():
    s = 2.2
    t = t_axis(s)
    nz = noise(s, "white", 431)
    body = sweep(nz, 200 + 3800 * np.exp(-t / 0.18), q=0.7) * np.exp(-t / 0.45)
    sub = sine(glide(70, 26, s)) * np.exp(-t / 0.5)
    rng = np.random.default_rng(432)
    crackle = np.zeros(len(t))
    for c in rng.uniform(0.02, 1.2, 60):
        i = n_of(c)
        crackle[i:i + 80] += rng.uniform(-1, 1) * np.exp(-np.arange(min(80, len(t) - i)) / 12)
    x = body * 0.9 + sub * 0.9 + hp(crackle, 1500) * 0.25 * np.exp(-t / 0.6)
    return master(reverb(stereo(fade(x)), 2.5, wet=0.25, width=1.3), peak_db=-1.5)


def game_alarm_loop():
    s = 1.0
    buf = np.zeros(n_of(s))
    for at, f in ((0.0, 880.0), (0.5, 660.0)):
        x = lp(square(f, 0.45, pw=0.5), 2200, 2) * adsr(0.45, 0.01, 0.05, 0.8, 0.04)
        mix_into(buf, x, at)
    return normalize(stereo(buf), -7)


def game_docking_clamp():
    s = 1.1
    t = t_axis(s)
    clunk = fm(178, 1.41, 3.5, s, index_env=np.exp(-t / 0.04)) * np.exp(-t / 0.14)
    clunk += lp(noise(s, "pink", 441), 1200, 2) * np.exp(-t / 0.03) * 0.6
    hiss = np.zeros(len(t))
    hs = 0.6
    mix_into(hiss, bp(noise(hs, seed=442), 1800, 6500) * points(hs, [(0, 0), (0.05, 1), (hs, 0)], 1.8) * 0.18, 0.3)
    return master(reverb(stereo(fade(clunk + hiss)), 0.9, wet=0.18), peak_db=-3)


def game_space_ambience_loop():
    s = 46.0
    t = t_axis(s)
    drone = sum(sine(f, s) * a for f, a in ((36.71, 0.5), (55.0, 0.35), (73.4, 0.2)))
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * t / 23.0)
    wind = sweep(noise(s, "pink", 451), 500 + 400 * np.sin(2 * np.pi * t / 15.3), q=1.4, kind="bp", block=512) * 0.35
    l = drone + wind
    r = drone + sweep(noise(s, "pink", 452), 520 + 420 * np.sin(2 * np.pi * t / 17.1 + 1), q=1.4, kind="bp", block=512) * 0.35
    x = np.stack([l, r], axis=1)
    rng = np.random.default_rng(453)
    for at in rng.uniform(2, s - 4, 7):
        f = rng.choice([1318.5, 1760.0, 1975.5, 2637.0])
        mix_into(x, stereo(bell(f, 1.2, tau=0.25, ratio=2.0, index=0.5, bright=0.05) * 0.08, rng.uniform(-0.8, 0.8)), at)
    x = hp(reverb(x, 4.0, wet=0.35, width=1.4), 25)
    return normalize(_seamless(x, 4.0), -6)


def game_ui_hover():
    t = t_axis(0.05)
    return master(stereo(fade(sine(3000, 0.05) * np.exp(-t / 0.006), 0.0005, 0.005)), peak_db=-16)


def game_ui_select():
    return master(stereo(fade(blip(1100, 1250, 0.12, 0.035))), peak_db=-10)


def game_ui_confirm():
    buf = np.zeros(n_of(0.35))
    mix_into(buf, marimba(880, 0.3, 0.08), 0.0, 0.7)
    mix_into(buf, marimba(1318.5, 0.3, 0.1), 0.07, 0.8)
    return master(reverb(stereo(fade(buf)), 0.6, wet=0.12), peak_db=-8)


def game_ui_back():
    buf = np.zeros(n_of(0.35))
    mix_into(buf, marimba(880, 0.3, 0.08), 0.0, 0.7)
    mix_into(buf, marimba(659.3, 0.3, 0.1), 0.07, 0.8)
    return master(reverb(stereo(fade(buf)), 0.6, wet=0.12), peak_db=-9)


# ================================================================ music

class Song:
    """Places notes on a beat grid; renders the pattern twice and keeps the second
    pass, so reverb and delay tails from the end carry into the start and the
    clip loops without a seam."""

    def __init__(self, bpm, bars, tail=6.0):
        self.bpm, self.bars = bpm, bars
        self.beat = 60.0 / bpm
        self.loop = bars * 4 * self.beat
        self.total = self.loop * 2 + tail
        self.tracks = {}

    def at(self, bar, beat=0.0, rep=0):
        return rep * self.loop + (bar * 4 + beat) * self.beat

    def track(self, name):
        if name not in self.tracks:
            self.tracks[name] = np.zeros((n_of(self.total), 2))
        return self.tracks[name]

    def add(self, name, sound, bar, beat=0.0, gain=1.0, pan=0.0):
        s = stereo(sound, pan) if sound.ndim == 1 else sound
        for rep in (0, 1):
            mix_into(self.track(name), s, self.at(bar, beat, rep), gain)

    def hits(self, bar_beats):
        return [self.at(b, x, rep) for rep in (0, 1) for b, x in bar_beats]

    def finish(self, bus):
        start = n_of(self.loop)
        return bus[start:start + n_of(self.loop)]


def music_arcade_lobby():
    """Bacon World theme: 80s arcade synthwave, A minor, 108 BPM, 32 bars."""
    song = Song(108, 32)
    B = song.beat
    chords = {
        "Am": (33, (57, 60, 64, 69)), "F": (29, (53, 57, 60, 65)), "C": (36, (55, 60, 64, 67)),
        "G": (31, (55, 59, 62, 67)), "Em": (28, (52, 55, 59, 64)),
    }
    p1, p2 = ["Am", "F", "C", "G"], ["F", "G", "Em", "Am"]
    prog = p1 * 4 + p2 * 2 + p1 * 2                                    # 32 bars
    kick_times = []
    for bar, name in enumerate(prog):
        root, tones = chords[name]
        breakdown = 16 <= bar < 20
        intro = bar < 4
        # pads, every bar
        song.add("pad", pad_chord(tones, 4 * B + 0.6, attack=0.3, release=0.6), bar, 0, 0.55)
        # bass: pulsing eighths with octave jumps (out for the first two breakdown bars)
        if not (16 <= bar < 18):
            for i in range(8):
                n = root + (12 if i % 2 else 0)
                song.add("bass", bass_note(midi(n), B * 0.5 * 0.92), bar, i * 0.5, 0.75)
        # arp: sixteenths over the chord, an octave up
        arp_notes = [tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[3] + 12, tones[2] + 12, tones[1] + 12, tones[3] + 12, tones[2] + 24]
        if not intro:
            for i in range(16):
                vel = 0.55 if i % 4 == 0 else 0.38
                song.add("arp", pluck(midi(arp_notes[i % 8]), 0.2), bar, i * 0.25, vel, pan=(-0.35 if i % 2 else 0.35))
        # drums
        for b in range(4):
            if breakdown and b != 0:
                continue
            song.add("kick", kick(), bar, b, 0.95)
            kick_times.append((bar, b))
        if not intro and not breakdown:
            for b in (1, 3):
                song.add("snare", snare(), bar, b, 0.55)
                song.add("snare", clap(), bar, b, 0.45)
        for i in range(8):
            if breakdown and i % 2 == 0:
                continue
            openh = (i % 2 == 1) and bar >= 24
            song.add("hats", hat(open_=openh, seed=11 + i), bar, i * 0.5, 0.32 if i % 2 else 0.22, pan=0.25)
    # lead melody over bars 8-15 and 24-31 (bar offset, beat, length in beats, midi)
    melody = [
        (0, 0, 1.5, 76), (0, 1.5, 0.5, 74), (0, 2, 1, 72), (0, 3, 1, 69),
        (1, 0, 1.5, 72), (1, 1.5, 0.5, 74), (1, 2, 2, 76),
        (2, 0, 1, 79), (2, 1, 1, 76), (2, 2, 1, 74), (2, 3, 1, 72),
        (3, 0, 2, 74), (3, 2, 1, 71), (3, 3, 1, 67),
        (4, 0, 1.5, 76), (4, 1.5, 0.5, 74), (4, 2, 1, 72), (4, 3, 1, 74),
        (5, 0, 1, 76), (5, 1, 1, 77), (5, 2, 1, 76), (5, 3, 1, 72),
        (6, 0, 1.5, 79), (6, 1.5, 0.5, 81), (6, 2, 1, 79), (6, 3, 1, 76),
        (7, 0, 3, 74), (7, 3, 1, 71),
    ]
    # bars 8-15 as written; bars 24-27 the first half again, 28-31 the second half an octave up
    for start, which, shift in ((8, range(0, 8), 0), (24, range(0, 4), 0), (24, range(4, 8), 12)):
        for (b, beat, length, n) in melody:
            if b in which:
                song.add("lead", lead_note(midi(n + shift), length * B * 0.95), start + b, beat, 0.42)
    # buses
    hits = song.hits(kick_times)
    pad = reverb(chorus(duck(song.track("pad"), hits, 0.45, 0.32), mix=0.35), 2.8, wet=0.35)
    bass = duck(song.track("bass"), hits, 0.35, 0.18)
    arp = reverb(delay(song.track("arp"), B * 0.75, feedback=0.35, mix=0.28, tone=3500, pingpong=True), 1.8, wet=0.25)
    lead = reverb(delay(song.track("lead"), B * 0.75, feedback=0.3, mix=0.25, tone=4000), 2.2, wet=0.28)
    snare_bus = reverb(song.track("snare"), 1.4, wet=0.32)
    drums = song.track("kick") + snare_bus + song.track("hats")
    bus = pad * 0.55 + bass * 0.75 + arp * 0.42 + lead * 0.6 + drums * 0.8
    return song.finish(master(bus, peak_db=-1.0, drive=1.25))


def music_orbit():
    """RaysSpaceSim menu: slow, spacious, D Lydian, 72 BPM, 24 bars."""
    song = Song(72, 24, tail=9.0)
    B = song.beat
    chords = [
        (38, (50, 54, 57, 61, 64)),   # Dmaj9
        (35, (47, 50, 54, 57, 61)),   # Bm9
        (31, (43, 50, 54, 59, 61)),   # Gmaj7#11
        (33, (45, 52, 57, 59, 64)),   # Asus2
    ]
    rng = np.random.default_rng(72)
    for cyc in range(3):
        for k, (root, tones) in enumerate(chords):
            bar = cyc * 8 + k * 2
            length = 8 * B + 2.0
            song.add("pad", pad_chord(tones, length, attack=1.6, release=2.0, cutoff=1500, detune=8, voices=3), bar, 0, 0.6)
            sub = sine(midi(root), length) * adsr(length, 1.5, 0.5, 0.8, 2.0)
            song.add("sub", sub, bar, 0, 0.35)
            # shimmer notes, sparse
            for _ in range(5):
                beat = float(rng.integers(0, 16)) * 0.5
                n = int(rng.choice(tones)) + 24
                song.add("shimmer", bell(midi(n), 1.6, tau=0.5, ratio=2.0, index=0.7, bright=0.05), bar, beat, 0.22,
                         pan=float(rng.uniform(-0.7, 0.7)))
    t = t_axis(song.total)
    wind = sweep(noise(song.total, "pink", 731), 600 + 400 * np.sin(2 * np.pi * t / 19.0), q=1.6, kind="bp", block=512)
    pad_bus = song.track("pad")
    cut = 900 + 700 * (0.5 + 0.5 * np.sin(2 * np.pi * t / song.loop))  # one filter cycle per loop: seamless
    pad_bus = np.stack([sweep(pad_bus[:, 0], cut, q=0.8, block=512), sweep(pad_bus[:, 1], cut, q=0.8, block=512)], axis=1)
    pad = reverb(chorus(pad_bus, rate=0.25, mix=0.4), 6.0, wet=0.45, width=1.3)
    shimmer = reverb(delay(song.track("shimmer"), B * 0.75, feedback=0.45, mix=0.4, tone=3000, pingpong=True), 6.0, wet=0.6, width=1.4)
    bus = pad * 0.8 + song.track("sub") * 0.7 + shimmer * 0.55 + stereo(wind * 0.05)
    return song.finish(master(bus, peak_db=-2.0, drive=1.05))


def music_bacon8_sting():
    total = 3.4
    buf = np.zeros((n_of(total), 2))
    for i, n in enumerate((69, 73, 76, 81)):                           # A4 C#5 E5 A5
        mix_into(buf, stereo(bell(midi(n), 1.2, tau=0.35, ratio=1.0, index=1.1, bright=0.08), -0.3 + i * 0.2), i * 0.075, 0.6)
    chord = pad_chord((57, 61, 64, 69, 73), 2.6, attack=0.08, release=1.4, cutoff=3200, detune=10)
    mix_into(buf, stereo(chord), 0.3, 0.7)
    tb = t_axis(1.2)
    boom = sine(glide(90, 45, 1.2)) * np.exp(-tb / 0.35)
    mix_into(buf, stereo(boom), 0.3, 0.6)
    for i, n in enumerate((93, 97, 100, 105)):
        mix_into(buf, stereo(bell(midi(n), 0.8, tau=0.2, ratio=2.0, index=0.5, bright=0.05), 0.6 - i * 0.4), 0.45 + i * 0.09, 0.18)
    return master(reverb(buf, 2.8, wet=0.32, width=1.3), peak_db=-1.0)


# ================================================================ catalogue and output

HUB_SOUNDS = {
    "ui/notification": ui_notification, "ui/message": ui_message, "ui/send": ui_send, "ui/click": ui_click,
    "ui/open": ui_open, "ui/close": ui_close, "ui/error": ui_error, "ui/success": ui_success, "ui/gems": ui_gems,
    # Bacon World's synthesised lobby sounds and its arcade music are retired
    # (2026-10-22): it plays recorded CC0 sounds from priv/static/audio/world/.
    # The lobby_* and music_arcade_lobby functions above are kept, unused.
    "music/bacon8-sting": music_bacon8_sting,
}

GAME_SOUNDS = {
    "SFX/thruster_loop": game_thruster_loop, "SFX/boost": game_boost, "SFX/warp_jump": game_warp_jump,
    "SFX/laser": game_laser, "SFX/explosion_small": game_explosion, "SFX/alarm_loop": game_alarm_loop,
    "SFX/docking_clamp": game_docking_clamp, "SFX/space_ambience_loop": game_space_ambience_loop,
    "UI/hover": game_ui_hover, "UI/select": game_ui_select, "UI/confirm": game_ui_confirm, "UI/back": game_ui_back,
    "UI/notification": ui_notification, "UI/error": ui_error,
    "Music/orbit": music_orbit, "Music/bacon8_sting": music_bacon8_sting,
}


def to_int16(x):
    x = as_stereo(np.asarray(x, dtype=float))
    return (np.clip(x, -1, 1) * 32767).astype("<i2")


def write_wav(path, x):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = to_int16(x)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", path.relative_to(ROOT) if path.is_relative_to(ROOT) else path, f"{len(pcm) / SR:.2f}s")


def write_mp3(path, x, kbps):
    import lameenc
    path.parent.mkdir(parents=True, exist_ok=True)
    enc = lameenc.Encoder()
    enc.set_bit_rate(kbps)
    enc.set_in_sample_rate(SR)
    enc.set_channels(2)
    enc.set_quality(2)
    data = enc.encode(to_int16(x).tobytes()) + enc.flush()
    path.write_bytes(data)
    print("wrote", path.relative_to(ROOT), f"{len(data) // 1024} KB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--wav-preview", default="", help="also write WAVs of the hub sounds into this folder")
    args = ap.parse_args()
    for name, make in HUB_SOUNDS.items():
        if args.only in name:
            x = make()
            write_mp3(HUB / f"{name}.mp3", x, 160 if name.startswith("music/") else 128)
            if args.wav_preview:
                write_wav(Path(args.wav_preview).resolve() / f"{name.replace('/', '_')}.wav", x)
    if (ROOT / "RaysSpaceSim").is_dir():
        for name, make in GAME_SOUNDS.items():
            if args.only in name:
                write_wav(GAME / f"{name}.wav", make())
    else:
        print("no ./RaysSpaceSim - skipping the game's sounds")


if __name__ == "__main__":
    main()
