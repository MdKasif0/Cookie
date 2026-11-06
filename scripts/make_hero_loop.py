#!/usr/bin/env python3
"""Renders the website's looping demo clip from Cookie's own sprite sheets.

Cookie walks onto the desk, waves, plays with a ball of yarn, yawns, naps, stretches and runs
off, and the clip loops from the empty desk. Everything comes from the shipped art, so it
stays in step with the app: re-run this after changing the animations.

Needs numpy-free Pillow and ffmpeg. Run from the repository root:

    python3 scripts/make_hero_loop.py

Writes website/assets/cookie-demo.mp4, .webm, a poster image and a short README GIF.
"""

import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SPRITES = [
    ROOT / "Cookie/Resources/Sprites/Cookie",
    ROOT / "Cookie.Windows/Resources/Sprites/Cookie",
]
BACKDROP = ROOT / "website/assets/hero-desk-bg.png"
OUT = ROOT / "website/assets"

FPS = 30
DURATION = 19.0
CAT = 238          # a 360px sheet cell, scaled for the 1024x582 backdrop
GROUND_Y = 536     # where her feet meet the desk
BALL = 124


# --- Art --------------------------------------------------------------------


class Sheet:
    def __init__(self, category, name):
        for root in SPRITES:
            manifest = root / category / f"{name}.json"
            if manifest.exists():
                break
        else:
            raise FileNotFoundError(f"no sheet {category}/{name}")

        meta = json.loads(manifest.read_text())
        columns, rows = meta["grid"]
        image = Image.open(root / category / f"{name}.png").convert("RGBA")
        cell = image.width // columns
        self.fps = meta["fps"]
        self.frames = []
        for index in meta.get("frames", range(columns * rows)):
            x, y = index % columns * cell, index // columns * cell
            frame = image.crop((x, y, x + cell, y + cell)).resize((CAT, CAT), Image.LANCZOS)
            self.frames.append(frame)

    def at(self, seconds, loop):
        index = int(seconds * self.fps)
        return self.frames[index % len(self.frames) if loop else min(index, len(self.frames) - 1)]


def shadow(width, height=18, opacity=70):
    layer = Image.new("L", (width * 2, height * 4), 0)
    ImageDraw.Draw(layer).ellipse([width // 2, height, width * 3 // 2, height * 3], fill=opacity)
    layer = layer.filter(ImageFilter.GaussianBlur(height * 0.55))
    out = Image.new("RGBA", layer.size, (84, 58, 44, 0))
    out.putalpha(layer)
    return out


# --- Timeline ----------------------------------------------------------------


def lerp(a, b, u):
    return a + (b - a) * u


def ease_out(u):
    return 1 - (1 - u) ** 2


def ease_in_out(u):
    return u * u * (3 - 2 * u)


# (start, end, sheet, loops?, x(u) -> centre in px, shadow width)
def build_segments():
    s = lambda category, name: Sheet(category, name)
    walk, run = s("Walk", "walk"), s("Run", "run")
    return [
        (0.0, 2.4, walk, True, lambda u: lerp(-190, 330, ease_out(u)), 150),
        (2.4, 3.9, s("Emotes", "wave"), False, lambda u: 330, 150),
        (3.9, 4.5, s("Idle", "idle"), True, lambda u: 330, 150),
        (4.5, 5.3, s("Interaction", "investigate"), True, lambda u: 330, 150),
        (5.3, 7.0, walk, True, lambda u: lerp(330, 560, ease_in_out(u)), 150),
        (7.0, 9.5, s("Emotions", "playful"), True, lambda u: 560, 160),
        (9.5, 10.2, s("Idle", "sit"), True, lambda u: 560, 150),
        (10.2, 11.4, s("Idle", "yawn"), False, lambda u: 560, 150),
        (11.4, 14.4, s("Sleep", "sleep"), True, lambda u: 560, 215),
        (14.4, 15.5, s("Sleep", "wake"), False, lambda u: 560, 190),
        (15.5, 16.7, s("Idle", "stretch"), False, lambda u: 560, 150),
        (16.7, DURATION, run, True, lambda u: lerp(560, 1260, ease_in(u)), 150),
    ]


def ease_in(u):
    return u * u


def ball_state(t):
    """(x centre, opacity, tilt in degrees) of the yarn ball, or None while it is away."""
    if t < 4.5 or t > 17.7:
        return None
    if t < 5.3:
        return lerp(1130, 760, ease_out((t - 4.5) / 0.8)), 1.0, 0.0
    tilt = 5 * math.sin((t - 7.0) * 9) if 7.0 <= t <= 9.5 else 0.0
    fade = 1.0 if t < 16.9 else max(0.0, 1 - (t - 16.9) / 0.8)
    return 760, fade, tilt


def make_frame(t, backdrop, segments, ball_art):
    frame = backdrop.copy()

    ball = ball_state(t)
    if ball:
        x, opacity, tilt = ball
        art = ball_art.rotate(tilt, resample=Image.BICUBIC, center=(BALL // 2, int(BALL * 0.9)))
        if opacity < 1:
            alpha = art.getchannel("A").point(lambda v: int(v * opacity))
            art.putalpha(alpha)
        frame.alpha_composite(art, (int(x - BALL / 2), int(GROUND_Y - BALL * 0.9)))

    for start, end, sheet, loop, x_of, shadow_width in segments:
        if start <= t < end:
            u = (t - start) / (end - start)
            x = x_of(u)
            cat = sheet.at(t - start, loop)
            under = shadow(shadow_width)
            frame.alpha_composite(under, (int(x - under.width / 2), int(GROUND_Y - under.height / 2 - 6)))
            frame.alpha_composite(cat, (int(x - CAT / 2), GROUND_Y - CAT + 2))
            break
    return frame


# --- Output -------------------------------------------------------------------


def encode(args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def main():
    backdrop = Image.open(BACKDROP).convert("RGBA")
    ball_art = Image.open(ROOT / "Cookie/Resources/Sprites/Cookie/Items/yarnBall.png").convert("RGBA")
    ball_art = ball_art.resize((BALL, BALL), Image.LANCZOS)
    segments = build_segments()

    work = Path(tempfile.mkdtemp(prefix="cookie-demo-"))
    try:
        total = int(DURATION * FPS)
        for index in range(total):
            make_frame(index / FPS, backdrop, segments, ball_art).convert("RGB").save(work / f"{index:05d}.png")

        source = ["-framerate", str(FPS), "-i", str(work / "%05d.png")]
        encode(source + ["-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p",
                         "-movflags", "+faststart", "-an", str(OUT / "cookie-demo.mp4")])
        encode(source + ["-c:v", "libvpx-vp9", "-crf", "38", "-b:v", "0", "-pix_fmt", "yuv420p",
                         "-an", str(OUT / "cookie-demo.webm")])

        # A shorter, smaller GIF for the README: the wave and the play.
        gif_filter = ("fps=12,scale=480:-1:flags=lanczos,split[a][b];"
                      "[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=5")
        encode(["-ss", "2.0", "-t", "8.0", "-framerate", str(FPS), "-i", str(work / "%05d.png"),
                "-vf", gif_filter, "-loop", "0", str(OUT / "cookie-demo.gif")])

        poster = Image.open(work / f"{int(3.0 * FPS):05d}.png")
        poster.save(OUT / "cookie-demo-poster.webp", quality=82, method=6)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    for name in ("cookie-demo.mp4", "cookie-demo.webm", "cookie-demo.gif", "cookie-demo-poster.webp"):
        print(f"{name:26} {(OUT / name).stat().st_size / 1024:7.0f} KB")


if __name__ == "__main__":
    main()
