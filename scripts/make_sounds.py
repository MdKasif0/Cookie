#!/usr/bin/env python3
"""Designs Cookie's sound set as small mono WAV files.

Her voice is modeled the way a real one works: a pulsed vocal source shaped by moving
formant filters (the mouth opening and closing), with a little breath and a small warm
room. The purr is built from a slow pulse train that alternates between inhale and exhale,
and loops without a seam.

Requires numpy and scipy. Run from the repository root:

    python3 scripts/make_sounds.py

Recordings can replace any file: keep its name. Delete its entry from SOUNDS below so
this script won't overwrite it.
"""

import wave
from pathlib import Path

import numpy as np
from scipy import signal

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "Cookie/Resources/Sounds"
rng = np.random.default_rng(20261106)


def curve(points, n):
    """Smoothly interpolates (time 0..1, value) points over n samples."""
    times, values = zip(*points)
    x = np.linspace(0, 1, n)
    y = np.interp(x, times, values)
    kernel = max(3, n // 40) | 1
    pad = kernel // 2
    return np.convolve(np.pad(y, pad, mode="edge"), np.hanning(kernel) / np.hanning(kernel).sum(), mode="valid")


def glottal(f0):
    """A voiced source: harmonics rolling off like vocal folds, with natural unsteadiness."""
    n = f0.size
    wobble = 1 + 0.006 * signal.lfilter([1], [1, -0.998], rng.normal(0, 0.06, n))
    phase = 2 * np.pi * np.cumsum(f0 * wobble) / RATE
    out = np.zeros(n)
    for k in range(1, 26):
        limit = np.clip((RATE / 2.2 - k * f0) / 2000, 0, 1)
        out += limit * np.sin(k * phase) / k ** 1.45
    shimmer = 1 + 0.05 * signal.lfilter([1], [1, -0.995], rng.normal(0, 0.05, n))
    return out * shimmer


def formant(x, freq, bandwidth):
    """A time-varying two-pole resonator: one resonance of the mouth."""
    r = np.exp(-np.pi * bandwidth / RATE)
    a1 = -2 * r * np.cos(2 * np.pi * freq / RATE)
    a2 = r * r
    gain = 1 - r
    out = np.zeros(x.size)
    y1 = y2 = 0.0
    for i in range(x.size):
        y = gain * x[i] - a1[i] * y1 - a2 * y2
        out[i] = y
        y2, y1 = y1, y
    return out


def voice(duration, f0, f1, f2, f3, amp, breath=0.06, nasal=None):
    """Renders a vocalization from pitch, formant and loudness contours."""
    n = int(duration * RATE)
    pitch = curve(f0, n)
    source = glottal(pitch) + rng.normal(0, breath, n) * (0.4 + 0.6 * curve(amp, n))
    # Formants in parallel keep the mouth shapes distinct at a cat's high pitch.
    shaped = (
        formant(source, curve(f1, n), 110) * 1.0
        + formant(source, curve(f2, n), 170) * 0.75
        + formant(source, curve(f3, n), 260) * 0.35
    )
    if nasal:
        shaped = shaped * (1 - curve(nasal, n)) + signal.lfilter(*signal.butter(2, 900 / (RATE / 2)), source) * curve(nasal, n) * 0.5
    return shaped * curve(amp, n)


def warm_room(x, wet=0.07, tail=0.14):
    """Softens with gentle saturation and a tiny, soft room, as if she's nearby."""
    n = int(tail * RATE)
    impulse = rng.normal(0, 1, n) * np.exp(-np.linspace(0, 7, n))
    impulse = signal.lfilter(*signal.butter(1, 3200 / (RATE / 2)), impulse)
    impulse /= np.sqrt((impulse ** 2).sum())
    padded = np.concatenate([x, np.zeros(n)])
    out = padded + wet * signal.fftconvolve(padded, impulse)[: padded.size]
    return out


def finish(x, peak=0.72, fade=0.006):
    x = x - x.mean()
    x = np.tanh(x / (np.abs(x).max() + 1e-9) * 1.25)
    edge = int(fade * RATE)
    window = np.ones(x.size)
    window[:edge] = np.linspace(0, 1, edge)
    window[-edge * 4:] = np.linspace(1, 0, edge * 4)
    x = x * window
    return x / (np.abs(x).max() + 1e-9) * peak


def bandpass(x, low, high, order=2):
    return signal.sosfilt(signal.butter(order, [low / (RATE / 2), high / (RATE / 2)], "band", output="sos"), x)


def lowpass(x, cutoff, order=2):
    return signal.sosfilt(signal.butter(order, cutoff / (RATE / 2), output="sos"), x)


# --- Her voice -----------------------------------------------------------------


def meow(pitch=1.0, length=1.0):
    """Mi-a-ow: lips part, the mouth opens wide, then rounds and closes."""
    base = 640 * pitch
    return finish(warm_room(voice(
        0.78 * length,
        f0=[(0, base * 0.9), (0.18, base * 1.12), (0.42, base * 1.28), (0.7, base * 1.05), (1, base * 0.72)],
        f1=[(0, 500), (0.2, 780), (0.45, 1150), (0.72, 800), (1, 480)],
        f2=[(0, 2300), (0.25, 2000), (0.5, 1750), (0.75, 1250), (1, 950)],
        f3=[(0, 3500), (0.5, 3100), (1, 2600)],
        amp=[(0, 0), (0.07, 0.55), (0.3, 0.9), (0.48, 1), (0.74, 0.65), (1, 0)],
        nasal=[(0, 0.75), (0.12, 0.15), (1, 0.05)],
    )))


def mew(pitch=1.0):
    """A tiny, high, shy mew."""
    base = 980 * pitch
    return finish(warm_room(voice(
        0.36,
        f0=[(0, base * 0.95), (0.3, base * 1.14), (0.75, base * 1.02), (1, base * 0.78)],
        f1=[(0, 800), (0.4, 1200), (1, 700)],
        f2=[(0, 2500), (0.5, 2250), (1, 1500)],
        f3=[(0, 3800), (1, 3200)],
        amp=[(0, 0), (0.12, 0.8), (0.42, 1), (1, 0)],
        breath=0.09,
    )), peak=0.55)


def trill(pitch=1.0, length=0.5):
    """The rolling "mrrp!" cats greet with: a closed-mouth rumble rising into a chirp."""
    x = voice(
        length,
        f0=[(0, 340 * pitch), (0.55, 460 * pitch), (0.85, 760 * pitch), (1, 860 * pitch)],
        f1=[(0, 420), (0.6, 520), (1, 980)],
        f2=[(0, 1300), (0.6, 1500), (1, 2100)],
        f3=[(0, 2700), (1, 3200)],
        amp=[(0, 0), (0.1, 0.8), (0.65, 0.9), (0.86, 1), (1, 0)],
    )
    t = np.arange(x.size) / RATE
    flutter = 0.62 + 0.38 * np.sin(2 * np.pi * 31 * t)
    fade_flutter = curve([(0, 1), (0.65, 1), (0.88, 0), (1, 0)], x.size)
    return finish(warm_room(x * (flutter * fade_flutter + (1 - fade_flutter))), peak=0.68)


def chirp():
    """A quick "ek-ek" of noticing something."""
    pips = []
    for pitch, gap in ((1180, 0.055), (1320, 0.0)):
        pips.append(voice(
            0.075,
            f0=[(0, pitch * 0.85), (0.5, pitch), (1, pitch * 1.08)],
            f1=[(0, 800), (1, 1200)],
            f2=[(0, 2400), (1, 2700)],
            f3=[(0, 3600), (1, 3800)],
            amp=[(0, 0), (0.2, 1), (1, 0)],
        ))
        pips.append(np.zeros(int(gap * RATE)))
    return finish(warm_room(np.concatenate(pips)), peak=0.5)


def surprise():
    """A startled upward "mrow?"."""
    return finish(warm_room(voice(
        0.3,
        f0=[(0, 480), (0.5, 760), (0.85, 1160), (1, 1280)],
        f1=[(0, 500), (0.6, 1050), (1, 1250)],
        f2=[(0, 1500), (1, 2500)],
        f3=[(0, 2800), (1, 3500)],
        amp=[(0, 0), (0.18, 0.8), (0.78, 1), (1, 0)],
        breath=0.1,
    )), peak=0.6)


def welcome():
    """Hello: a soft trill that opens into a little meow."""
    first = trill(pitch=1.05, length=0.34)
    second = meow(pitch=1.14, length=0.6)
    gap = np.zeros(int(0.03 * RATE))
    return finish(np.concatenate([first * 0.9, gap, second]), peak=0.66)


# --- Purring -------------------------------------------------------------------

BREATH_SECONDS = 2.2
BREATHS_IN_LOOP = 4


def purr_loop():
    """About nine seconds of contented purring that repeats without a seam.

    Every component is periodic over the loop, and the loop point falls in the brief
    quiet as she turns from inhale to exhale, where a player's tiny restart gap is hidden.
    """
    seconds = BREATH_SECONDS * BREATHS_IN_LOOP
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    breath = (t / BREATH_SECONDS) % 1.0

    # Exhale (first 58%) is fuller and slightly slower than inhale, as in a real purr.
    exhale = breath < 0.58
    rate = np.where(exhale, 25.0, 27.5)
    rate = np.convolve(np.concatenate([rate[-400:], rate, rate[:400]]), np.hanning(801) / np.hanning(801).sum(), mode="valid")
    # Adjust so a whole number of pulses fits, keeping the pulse train periodic.
    cycles = np.cumsum(rate) / RATE
    cycles *= round(cycles[-1]) / cycles[-1]
    pulse_phase = cycles % 1.0

    # Each pulse is the larynx snapping open: a sharp attack with a fast decay.
    pulse = np.exp(-pulse_phase * 7.5) * (1 - np.exp(-pulse_phase * 90))

    swell = np.where(
        exhale,
        np.sin(np.pi * np.clip(breath / 0.58, 0, 1)) ** 0.55,
        0.62 * np.sin(np.pi * np.clip((breath - 0.58) / 0.42, 0, 1)) ** 0.7,
    )
    slow_drift = 1 + 0.07 * np.sin(2 * np.pi * t / seconds) + 0.05 * np.sin(4 * np.pi * t / seconds + 1.0)

    # Noise made periodic by crossfading its end into its start.
    overlap = int(0.25 * RATE)
    raw = rng.normal(0, 1, n + overlap)
    fade = np.sqrt(np.linspace(0, 1, overlap))
    raw[:overlap] = raw[:overlap] * fade + raw[n:] * fade[::-1]
    noise = raw[:n]

    def periodic_filter(x, sos):
        return signal.sosfilt(sos, np.concatenate([x, x]))[n:]

    chest = periodic_filter(pulse * noise, signal.butter(2, [45 / (RATE / 2), 240 / (RATE / 2)], "band", output="sos"))
    throat = periodic_filter(pulse * noise, signal.butter(2, [240 / (RATE / 2), 950 / (RATE / 2)], "band", output="sos"))
    air = periodic_filter(noise, signal.butter(2, [900 / (RATE / 2), 3800 / (RATE / 2)], "band", output="sos"))
    tone = np.sin(2 * np.pi * cycles) * pulse + 0.5 * np.sin(4 * np.pi * cycles) * pulse

    mix = (
        chest / np.abs(chest).max() * 1.0
        + throat / np.abs(throat).max() * 0.38
        + tone / np.abs(tone).max() * 0.55
    ) * swell + air / np.abs(air).max() * 0.018 * (0.3 + swell)
    mix = np.tanh(mix * slow_drift * 1.1)
    return mix / np.abs(mix).max() * 0.62


# --- Effects -------------------------------------------------------------------


def sleep():
    """A slow, sleepy sigh: one long breath out and a soft one in."""
    n = int(3.0 * RATE)
    noise = rng.normal(0, 1, n)
    body = bandpass(noise, 280, 1500) * curve([(0, 0), (0.12, 0.8), (0.42, 1), (0.6, 0.15), (0.72, 0.1), (0.86, 0.32), (1, 0)], n)
    hum = voice(
        3.0,
        f0=[(0, 220), (0.45, 170), (1, 150)],
        f1=[(0, 520), (1, 420)],
        f2=[(0, 1100), (1, 900)],
        f3=[(0, 2400), (1, 2300)],
        amp=[(0, 0), (0.15, 0.55), (0.42, 0.25), (0.55, 0), (1, 0)],
        breath=0.03,
    )
    mix = body / np.abs(body).max() + hum / np.abs(hum).max() * 0.4
    return finish(warm_room(mix, wet=0.1), peak=0.4)


def eat():
    """Dainty munching: small crunches with a little weight behind them."""
    total = int(0.72 * RATE)
    out = np.zeros(total)
    for start in (0.03, 0.17, 0.29, 0.44, 0.57):
        length = int(rng.uniform(0.055, 0.09) * RATE)
        grain = rng.normal(0, 1, length) * (rng.random(length) > 0.45)
        env = np.exp(-np.linspace(0, 6, length))
        crunch = bandpass(grain, rng.uniform(1300, 2200), rng.uniform(3600, 5600)) * env
        thump = np.sin(2 * np.pi * rng.uniform(120, 170) * np.arange(length) / RATE) * np.exp(-np.linspace(0, 9, length))
        at = int(start * RATE)
        out[at:at + length] += crunch / (np.abs(crunch).max() + 1e-9) * rng.uniform(0.7, 1) + thump * 0.55
    return finish(warm_room(out, wet=0.06), peak=0.5)


def toy():
    """A soft felt knock with a tiny jingle bell inside."""
    n = int(0.62 * RATE)
    t = np.arange(n) / RATE
    knock = np.sin(2 * np.pi * 210 * np.exp(-t * 6) * t) * np.exp(-t * 34)
    bell = np.zeros(n)
    for delay in (0.0, 0.07, 0.15):
        at = int(delay * RATE)
        tt = t[: n - at]
        tone = sum(amp * np.sin(2 * np.pi * freq * tt) * np.exp(-tt * decay)
                   for freq, amp, decay in ((2640, 1.0, 11), (4180, 0.55, 16), (6290, 0.3, 24)))
        bell[at:] += tone * (0.9 ** (delay * 20))
    return finish(warm_room(knock * 0.9 + bell * 0.22, wet=0.08), peak=0.46)


def drop():
    """A soft landing on a cushion, with a small puff of air."""
    n = int(0.42 * RATE)
    t = np.arange(n) / RATE
    thud = np.sin(2 * np.pi * (46 * t + 34 * (1 - np.exp(-t * 16)) / 16)) * np.exp(-t * 17)
    puff = bandpass(rng.normal(0, 1, n), 350, 2100) * np.exp(-t * 26)
    return finish(warm_room(thud + puff / np.abs(puff).max() * 0.26, wet=0.05), peak=0.62)


SOUNDS = {
    "cookie-meow": lambda: meow(),
    "cookie-meow-2": lambda: meow(pitch=1.09, length=0.82),
    "cookie-meow-3": lambda: meow(pitch=0.93, length=1.14),
    "cookie-mew": lambda: mew(),
    "cookie-mew-2": lambda: mew(pitch=1.1),
    "cookie-happy": lambda: trill(),
    "cookie-happy-2": lambda: trill(pitch=1.12, length=0.42),
    "cookie-chirp": chirp,
    "cookie-surprise": surprise,
    "cookie-welcome": welcome,
    "cookie-purr": purr_loop,
    "cookie-sleep": sleep,
    "cookie-eat": eat,
    "cookie-toy": toy,
    "cookie-drop": drop,
}


def write(name, samples):
    path = OUT / f"{name}.wav"
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    rms = float(np.sqrt((samples ** 2).mean()))
    print(f"{name:18} {samples.size / RATE:5.2f}s  peak {np.abs(samples).max():.2f}  rms {rms:.3f}  {path.stat().st_size // 1024:4} KB")


def main():
    for name, make in SOUNDS.items():
        write(name, make())


if __name__ == "__main__":
    main()
