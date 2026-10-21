"""A small synthesizer for Bacon8's sound effects and music.

Everything here is numpy/scipy: oscillators, envelopes, filters, a few effects,
and helpers to place notes on a timeline. No samples are used anywhere, so every
sound built with it is original.
"""
import numpy as np
from scipy import signal

SR = 48000


# ---------------------------------------------------------------- basics

def n_of(seconds):
    return int(round(seconds * SR))


def t_axis(seconds):
    return np.arange(n_of(seconds)) / SR


def silence(seconds, ch=1):
    return np.zeros((n_of(seconds), 2)) if ch == 2 else np.zeros(n_of(seconds))


def midi(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def db(x):
    return 10 ** (x / 20)


def _freq_array(freq, seconds):
    if np.isscalar(freq):
        return np.full(n_of(seconds), float(freq))
    return np.asarray(freq, dtype=float)


def glide(f0, f1, seconds, curve="exp"):
    """A frequency ramp, per sample."""
    n = n_of(seconds)
    if curve == "exp":
        return f0 * (f1 / f0) ** np.linspace(0, 1, n)
    return np.linspace(f0, f1, n)


# ---------------------------------------------------------------- oscillators

def _phase(freq, seconds=None, phase0=0.0):
    f = _freq_array(freq, seconds)
    return (phase0 + np.cumsum(f) / SR) % 1.0, f / SR


def sine(freq, seconds=None, phase0=0.0):
    f = _freq_array(freq, seconds)
    return np.sin(2 * np.pi * (phase0 + np.cumsum(f) / SR))


def _blep(p, dt):
    y = np.zeros_like(p)
    m = p < dt
    x = p[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = p > 1.0 - dt
    x = (p[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def saw(freq, seconds=None, phase0=0.0):
    """Band-limited sawtooth (polyBLEP)."""
    p, dt = _phase(freq, seconds, phase0)
    return (2.0 * p - 1.0) - _blep(p, dt)


def square(freq, seconds=None, pw=0.5, phase0=0.0):
    """Band-limited pulse wave (polyBLEP)."""
    p, dt = _phase(freq, seconds, phase0)
    y = np.where(p < pw, 1.0, -1.0)
    y += _blep(p, dt)
    y -= _blep((p + 1.0 - pw) % 1.0, dt)
    return y


def triangle(freq, seconds=None, phase0=0.0):
    p, _ = _phase(freq, seconds, phase0)
    return 4.0 * np.abs(p - 0.5) - 1.0


def noise(seconds, color="white", seed=0):
    rng = np.random.default_rng(seed)
    w = rng.standard_normal(n_of(seconds))
    if color == "white":
        return w / 3.0
    if color == "pink":
        # Paul Kellet's economy filter
        b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
        y = signal.lfilter(b, a, w)
        return y / (np.max(np.abs(y)) + 1e-9)
    if color == "brown":
        y = np.cumsum(w)
        y = signal.sosfilt(signal.butter(1, 20, "hp", fs=SR, output="sos"), y)
        return y / (np.max(np.abs(y)) + 1e-9)
    raise ValueError(color)


def fm(carrier, ratio, index, seconds, index_env=None, phase0=0.0):
    """Two-operator FM: a sine modulator at carrier*ratio drives a sine carrier."""
    f = _freq_array(carrier, seconds)
    mod = sine(f * ratio)
    idx = index if index_env is None else index * index_env
    return np.sin(2 * np.pi * (phase0 + np.cumsum(f) / SR) + idx * mod)


def supersaw(freq, seconds, voices=5, detune_cents=12, seed=1):
    rng = np.random.default_rng(seed)
    f = _freq_array(freq, seconds)
    out = np.zeros(len(f))
    for i in range(voices):
        c = (i - (voices - 1) / 2) / max(1, (voices - 1) / 2) * detune_cents
        out += saw(f * 2 ** (c / 1200), phase0=rng.random())
    return out / voices


# ---------------------------------------------------------------- envelopes

def adsr(seconds, a=0.005, d=0.1, s=0.7, r=0.2, hold=None):
    """Attack/decay/sustain/release over `seconds` total; release starts at `hold` (default: end - r)."""
    a, d, r = max(a, 1e-4), max(d, 1e-4), max(r, 1e-4)
    t = np.arange(n_of(seconds)) / SR
    hold = max(0.0, seconds - r) if hold is None else hold

    def level(tt):
        tt = np.asarray(tt, dtype=float)
        return np.where(tt < a, tt / a, np.where(tt < a + d, 1 - (1 - s) * (tt - a) / d, s))

    env = level(t)
    rel = t >= hold
    env[rel] = float(level(hold)) * np.clip(1 - (t[rel] - hold) / r, 0, 1)
    return env


def decay(seconds, tau, attack=0.002):
    t = t_axis(seconds)
    return np.minimum(1.0, t / max(attack, 1e-5)) * np.exp(-t / tau)


def points(seconds, pts, curve=1.0):
    """Piecewise envelope through (time, level) points."""
    t = t_axis(seconds)
    xs, ys = zip(*pts)
    e = np.interp(t, xs, ys)
    return np.sign(e) * np.abs(e) ** curve


# ---------------------------------------------------------------- filters

def lp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, min(fc, SR * 0.45), "lp", fs=SR, output="sos"), x, axis=0)


def hp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "hp", fs=SR, output="sos"), x, axis=0)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR * 0.45)], "bp", fs=SR, output="sos"), x, axis=0)


def _rbj(kind, f, q):
    w = 2 * np.pi * f / SR
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / (2 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    elif kind == "bp":
        b = [alpha, 0, -alpha]
    else:
        raise ValueError(kind)
    a = [1 + alpha, -2 * cw, 1 - alpha]
    return np.array(b) / a[0], np.array(a) / a[0]


def sweep(x, freqs, q=0.9, kind="lp", block=64):
    """Time-varying resonant biquad; `freqs` is a per-sample cutoff."""
    freqs = np.clip(_freq_array(freqs, len(x) / SR), 20, SR * 0.45)
    y = np.empty_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        b, a = _rbj(kind, freqs[i], q)
        y[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return y


# ---------------------------------------------------------------- stereo, effects

def stereo(mono, pan=0.0):
    """Constant-power pan, -1 left .. 1 right."""
    a = (pan + 1) * np.pi / 4
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def as_stereo(x):
    return x if x.ndim == 2 else stereo(x)


def delay(x, seconds, feedback=0.35, mix=0.3, tone=5000, repeats=8, pingpong=False):
    """Echoes every `seconds`, each `feedback` quieter and a little darker."""
    x = as_stereo(x)
    d = n_of(seconds)
    wet = np.zeros_like(x)
    tap = x.copy()
    gain = 1.0
    for k in range(1, repeats + 1):
        if k * d >= len(x):
            break
        tap = lp(tap, tone, 1)
        if pingpong:
            tap = tap[:, ::-1]
        wet[k * d:] += tap[:len(x) - k * d] * gain
        gain *= feedback
    return x + wet * mix


def reverb(x, seconds=2.5, wet=0.3, predelay=0.02, damp=6000, seed=7, width=1.0):
    """Convolution with a synthetic, decorrelated stereo tail."""
    x = as_stereo(x)
    n = n_of(seconds)
    t = np.arange(n) / SR
    env = np.exp(-6.9 * t / seconds)            # -60 dB at `seconds`
    rng = np.random.default_rng(seed)
    irs = []
    for ch in range(2):
        ir = rng.standard_normal(n) * env
        # darker as it decays
        ir = lp(ir, damp, 1) * 0.6 + lp(ir, damp / 3, 1) * 0.4
        ir = np.concatenate([np.zeros(n_of(predelay)), ir])
        irs.append(ir / np.sqrt(np.sum(ir ** 2)))
    l = signal.fftconvolve(x[:, 0], irs[0])[:len(x)]
    r = signal.fftconvolve(x[:, 1], irs[1])[:len(x)]
    mid, side = (l + r) / 2, (l - r) / 2
    wetsig = np.stack([mid + side * width, mid - side * width], axis=1)
    return x * (1 - wet) + wetsig * wet * 1.4


def chorus(x, rate=0.6, depth_ms=6, base_ms=14, mix=0.4):
    x = as_stereo(x)
    n = len(x)
    t = np.arange(n) / SR
    out = x.copy()
    for ch, ph in ((0, 0.0), (1, np.pi / 2)):
        dl = (base_ms + depth_ms * np.sin(2 * np.pi * rate * t + ph)) / 1000 * SR
        idx = np.arange(n) - dl
        out[:, ch] = x[:, ch] * (1 - mix) + np.interp(idx, np.arange(n), x[:, ch], left=0) * mix
    return out


def duck(x, hits, depth=0.5, release=0.25):
    """Sidechain-style pumping: dip the level at each hit time (seconds)."""
    env = np.ones(len(x))
    rn = n_of(release)
    curve = 1 - depth * np.exp(-np.arange(rn) / (rn / 4))
    for h in hits:
        i = n_of(h)
        if i >= len(x):
            continue
        k = min(rn, len(x) - i)
        env[i:i + k] = np.minimum(env[i:i + k], curve[:k])
    return x * (env[:, None] if x.ndim == 2 else env)


def fade(x, fade_in=0.003, fade_out=0.01):
    x = x.copy()
    a, b = n_of(fade_in), n_of(fade_out)
    if a:
        ramp = np.linspace(0, 1, a)
        x[:a] *= ramp[:, None] if x.ndim == 2 else ramp
    if b:
        ramp = np.linspace(1, 0, b)
        x[-b:] *= ramp[:, None] if x.ndim == 2 else ramp
    return x


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def normalize(x, peak_db=-1.0):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * db(peak_db)


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(np.square(x))) + 1e-12)


def master(x, peak_db=-1.0, drive=1.15, hp_hz=25):
    x = hp(as_stereo(x), hp_hz, 2)
    x = soft_clip(normalize(x, 0) * 0.95, drive)
    return normalize(x, peak_db)


def mix_into(buf, sound, at_seconds, gain=1.0):
    """Add `sound` into `buf` starting at `at_seconds` (both stereo or both mono)."""
    i = n_of(at_seconds)
    if i >= len(buf):
        return buf
    k = min(len(sound), len(buf) - i)
    buf[i:i + k] += sound[:k] * gain
    return buf


def concat(*parts):
    return np.concatenate(parts, axis=0)
