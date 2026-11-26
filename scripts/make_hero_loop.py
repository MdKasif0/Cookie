#!/usr/bin/env python3
"""Renders the website's looping demo clip from Cookie's own sprite sheets.

Cookie walks onto the desk, waves, plays with a ball of yarn, yawns, naps and stretches. Then she
helps: a reminder pops up above her, and she pins a sticky note that gets ticked off for a little
bond heart, before she runs off and the clip loops from the empty desk. Everything comes from the shipped art, so it
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

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SPRITES = [
    ROOT / "Cookie/Resources/Sprites/Cookie",
    ROOT / "Cookie.Windows/Resources/Sprites/Cookie",
]
BACKDROP = ROOT / "website/assets/hero-desk-bg.png"
OUT = ROOT / "website/assets"

FPS = 30
DURATION = 25.0
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


# --- Helping overlays -----------------------------------------------------------
# The reminder bubble and the sticky note, drawn in the app's warm palette.

FONT_PATHS = [
    "/System/Library/Fonts/SFCompactRounded.ttf",
    "/System/Library/Fonts/Avenir Next.ttc",
]
INK = (58, 46, 40, 255)
MUTED = (125, 108, 98, 255)
CARD = (255, 252, 246, 245)
NOTE_YELLOW = (255, 232, 140, 255)
HEART = (233, 104, 112, 255)


def font(size, bold=True):
    for path in FONT_PATHS:
        try:
            face = ImageFont.truetype(path, size)
            try:
                face.set_variation_by_name("Semibold" if bold else "Regular")
            except Exception:
                pass
            return face
        except OSError:
            continue
    return ImageFont.load_default(size)


def soft_shadow(card, radius, blur=10, opacity=60, offset=4):
    """The card with a soft warm shadow beneath, on a transparent canvas with room for the blur."""
    pad = blur * 2
    mask = Image.new("L", (card.width + pad * 2, card.height + pad * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle([pad, pad + offset, pad + card.width, pad + card.height + offset], radius, fill=opacity)
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", mask.size, (84, 58, 44, 0))
    out.putalpha(mask)
    out.alpha_composite(card, (pad, pad))
    return out


def bubble(title, line):
    """A speech bubble with a small tail, like the one Cookie shows above her head."""
    big, small = font(19), font(15, bold=False)
    width = int(max(big.getlength(title), small.getlength(line))) + 40
    height = 68
    card = Image.new("RGBA", (width, height + 12), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle([0, 0, width - 1, height - 1], 16, fill=CARD, outline=(232, 220, 206, 255))
    mid = width // 2
    draw.polygon([(mid - 10, height - 2), (mid + 10, height - 2), (mid, height + 11)], fill=CARD)
    draw.text((20, 12), title, font=big, fill=INK)
    draw.text((20, 38), line, font=small, fill=MUTED)
    return soft_shadow(card, 16)


def sticky_note(text, ticked):
    """A yellow sticky note, slightly tilted, with an optional tick and strike-through."""
    size = 150
    note = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(note)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], 8, fill=NOTE_YELLOW)
    draw.rectangle([0, 0, size - 1, 16], fill=(247, 214, 105, 255))
    face = font(19)
    y = 40
    for line in text.split("\n"):
        draw.text((18, y), line, font=face, fill=INK)
        if ticked:
            w = face.getlength(line)
            draw.line([(16, y + 12), (20 + w, y + 12)], fill=(120, 96, 70, 255), width=3)
        y += 28
    if ticked:
        draw.ellipse([size - 46, size - 46, size - 14, size - 14], fill=(96, 176, 120, 255))
        draw.line([(size - 38, size - 30), (size - 32, size - 23), (size - 21, size - 37)], fill=(255, 255, 255, 255), width=4)
    note = soft_shadow(note, 8, blur=8, opacity=55, offset=3)
    return note.rotate(-4, resample=Image.BICUBIC, expand=True)


def heart_badge(text):
    """A little heart with "+3", for the bond points a finished task earns."""
    face = font(20)
    width = int(face.getlength(text)) + 60
    badge = Image.new("RGBA", (width, 40), (0, 0, 0, 0))
    draw = ImageDraw.Draw(badge)
    draw.rounded_rectangle([0, 0, width - 1, 39], 20, fill=CARD)
    # A heart from two circles and a triangle.
    cx, cy = 22, 18
    draw.ellipse([cx - 11, cy - 8, cx + 1, cy + 4], fill=HEART)
    draw.ellipse([cx - 1, cy - 8, cx + 11, cy + 4], fill=HEART)
    draw.polygon([(cx - 11, cy - 1), (cx + 11, cy - 1), (cx, cy + 12)], fill=HEART)
    draw.text((40, 7), text, font=face, fill=INK)
    return soft_shadow(badge, 20, blur=6, opacity=45, offset=2)


def with_opacity(art, opacity):
    if opacity >= 1:
        return art
    art = art.copy()
    art.putalpha(art.getchannel("A").point(lambda v: int(v * opacity)))
    return art


def pop(t, start, end, fade=0.25):
    """Opacity and scale for something that pops in at `start` and fades out at `end`."""
    if t < start or t > end:
        return 0.0, 1.0
    rise = min(1.0, (t - start) / fade)
    fall = min(1.0, (end - t) / fade)
    opacity = min(rise, fall)
    scale = 0.86 + 0.14 * (1 - (1 - rise) ** 3)
    return opacity, scale


def place(frame, art, centre_x, bottom_y, opacity, scale):
    if opacity <= 0:
        return
    if scale != 1:
        art = art.resize((max(1, int(art.width * scale)), max(1, int(art.height * scale))), Image.LANCZOS)
    art = with_opacity(art, opacity)
    frame.alpha_composite(art, (int(centre_x - art.width / 2), int(bottom_y - art.height)))


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
        # Helping: a reminder comes due, then a sticky note is ticked off.
        (16.7, 17.3, s("Idle", "sit"), True, lambda u: 560, 150),
        (17.3, 19.4, s("Interaction", "meow"), True, lambda u: 560, 150),
        (19.4, 20.8, s("Idle", "sit"), True, lambda u: 560, 150),
        (20.8, 22.6, s("Emotes", "happy"), False, lambda u: 560, 150),
        (22.6, 23.2, s("Idle", "idle"), True, lambda u: 560, 150),
        (23.2, DURATION, run, True, lambda u: lerp(560, 1260, ease_in(u)), 150),
    ]


def ease_in(u):
    return u * u


def ball_state(t):
    """(x centre, opacity, tilt in degrees) of the yarn ball, or None while it is away."""
    if t < 4.5 or t > 24.2:
        return None
    if t < 5.3:
        return lerp(1130, 760, ease_out((t - 4.5) / 0.8)), 1.0, 0.0
    tilt = 5 * math.sin((t - 7.0) * 9) if 7.0 <= t <= 9.5 else 0.0
    fade = 1.0 if t < 23.4 else max(0.0, 1 - (t - 23.4) / 0.8)
    return 760, fade, tilt


def make_frame(t, backdrop, segments, ball_art, overlays):
    frame = backdrop.copy()

    # The sticky note goes up on the wall beside her, gets ticked off, and fades before the loop.
    note_opacity, note_scale = pop(t, 19.6, 24.6, fade=0.3)
    note = overlays["note_done"] if t >= 20.8 else overlays["note"]
    place(frame, note, 330, 330, note_opacity, note_scale)

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

    # The reminder bubble above her head.
    opacity, scale = pop(t, 17.4, 19.6)
    place(frame, overlays["reminder"], 560, GROUND_Y - CAT + 40, opacity, scale)

    # The bond heart floats up from the note.
    if 20.9 <= t <= 22.6:
        u = (t - 20.9) / 1.7
        opacity = min(1.0, u / 0.15, (1 - u) / 0.25)
        place(frame, overlays["heart"], 345, lerp(168, 122, ease_out(u)), opacity, 1.0)
    return frame


# --- Output -------------------------------------------------------------------


def encode(args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def main():
    backdrop = Image.open(BACKDROP).convert("RGBA")
    ball_art = Image.open(ROOT / "Cookie/Resources/Sprites/Cookie/Items/yarnBall.png").convert("RGBA")
    ball_art = ball_art.resize((BALL, BALL), Image.LANCZOS)
    segments = build_segments()
    overlays = {
        "reminder": bubble("Time to call Mom!", "You asked me to remind you at 3:00"),
        "note": sticky_note("Water the\nplants", ticked=False),
        "note_done": sticky_note("Water the\nplants", ticked=True),
        "heart": heart_badge("+3"),
    }

    work = Path(tempfile.mkdtemp(prefix="cookie-demo-"))
    try:
        total = int(DURATION * FPS)
        for index in range(total):
            make_frame(index / FPS, backdrop, segments, ball_art, overlays).convert("RGB").save(work / f"{index:05d}.png")

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
