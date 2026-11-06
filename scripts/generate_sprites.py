#!/usr/bin/env python3
"""Generates Cookie's animation sprite sheets from the shipped artwork.

Each frame bends the original painting with soft, localized warps (like a
puppet rig), so limbs, tail, ears and head really move while the character keeps
its exact look. Closed eyes and open mouths are painted over the base art.

Requires numpy, scipy and Pillow. Run from the repository root:

    python3 scripts/generate_sprites.py            # write all sheets
    python3 scripts/generate_sprites.py walk run   # write only these sheets
    python3 scripts/generate_sprites.py --preview DIR   # also write review images

Hand-made art can replace any sheet: delete its entry from SHEETS below so this
script no longer overwrites it, then drop in a new PNG and JSON.
"""

import argparse
import json
import math
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ni

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Cookie/Assets/Assets.xcassets"
SHARED_OUT = ROOT / "Cookie/Resources/Sprites/Cookie"
WINDOWS_OUT = ROOT / "Cookie.Windows/Resources/Sprites/Cookie"

WORK = 720  # working canvas in pixels
FRAME = 360  # shipped frame size: the app's 180pt canvas at 2x
BODY_SIZE = 698.4  # the cat's longest side on the working canvas (matches the Mac fit)
GROUND = 714.2  # y of the feet on the working canvas

YY, XX = np.mgrid[0:WORK, 0:WORK].astype(np.float32)


# --- Artwork ----------------------------------------------------------------


def art_path(name):
    if name == "base":
        return ASSETS / "CookieArt.imageset/cookie.png"
    return ASSETS / f"cookie-{name}.imageset/cookie-{name}.png"


def premultiply(rgba):
    out = rgba.astype(np.float32) / 255.0
    out[..., :3] *= out[..., 3:]
    return out


@dataclass
class Art:
    """Artwork normalized onto the working canvas: same body size, feet on the ground."""

    cat: np.ndarray
    deco: np.ndarray
    scale: float
    offset: tuple
    source_size: tuple
    tail: tuple = field(default=(0.88, 0.76))

    def g(self, x, y):
        """Maps a point read off a 720px fit of the source art to canvas units (0..1)."""
        w, h = self.source_size
        fit = 720 / max(w, h)
        sx = (x * 720 - (720 - w * fit) / 2) / fit
        sy = (y * 720 - (720 - h * fit)) / fit
        return (
            (sx * self.scale + self.offset[0]) / WORK,
            (sy * self.scale + self.offset[1]) / WORK,
        )

    def n(self, x, y):
        """Maps a point in fractions of the source image to canvas units."""
        w, h = self.source_size
        return (
            (x * w * self.scale + self.offset[0]) / WORK,
            (y * h * self.scale + self.offset[1]) / WORK,
        )


_arts = {}


def _fit_decorations(deco):
    """Pulls detached decorations in toward the cat when they would overflow the canvas.

    Stickers are wider than the canvas once the cat is sized to match the base pose.
    """
    visible = deco[..., 3] > 0.04
    if not visible.any():
        return deco
    ys, xs = np.where(visible)
    margin = 26
    center = WORK / 2
    reach_x = max(center - xs.min(), xs.max() - center)
    fit_x = min(1.0, (center - margin) / reach_x)
    fit_top = min(1.0, (GROUND - margin) / (GROUND - ys.min()))
    fit = min(fit_x, fit_top)
    if fit >= 1.0:
        return deco
    x = (XX - center) / fit + center
    y = (YY - GROUND) / fit + GROUND
    return np.stack(
        [ni.map_coordinates(deco[..., c], [y, x], order=1, mode="constant") for c in range(4)],
        axis=-1,
    )


def load_art(name):
    if name in _arts:
        return _arts[name]

    source = Image.open(art_path(name)).convert("RGBA")
    alpha = np.array(source)[..., 3] > 100
    labels, count = ni.label(alpha)
    sizes = ni.sum(alpha, labels, range(1, count + 1))
    biggest = int(np.argmax(sizes)) + 1
    ys, xs = np.where(labels == biggest)
    left, right, top, bottom = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1

    scale = BODY_SIZE / max(right - left, bottom - top)
    offset = (WORK / 2 - (left + right) / 2 * scale, GROUND - bottom * scale)

    affine = Image.AFFINE
    placed = source.transform(
        (WORK, WORK),
        affine,
        (1 / scale, 0, -offset[0] / scale, 0, 1 / scale, -offset[1] / scale),
        resample=Image.BICUBIC,
    )
    full = premultiply(np.array(placed))

    # Split the cat from detached decorations (stars, hearts, Zs) so they can move on their own.
    mask = ni.binary_dilation(labels == biggest, iterations=6).astype(np.float32)
    mask_image = Image.fromarray((mask * 255).astype(np.uint8)).transform(
        (WORK, WORK),
        affine,
        (1 / scale, 0, -offset[0] / scale, 0, 1 / scale, -offset[1] / scale),
        resample=Image.BILINEAR,
    )
    cat_mask = (np.array(mask_image).astype(np.float32) / 255.0)[..., None]
    deco = _fit_decorations(full * (1 - cat_mask))
    art = Art(full * cat_mask, deco, scale, offset, source.size)

    # The tail tip is the rightmost part of the lower body in these poses.
    cat_alpha = art.cat[..., 3] > 0.5
    rows = np.where(cat_alpha[int(WORK * 0.62):int(WORK * 0.92)].any(axis=1))[0] + int(WORK * 0.62)
    tip_x = max(np.where(cat_alpha[r])[0].max() for r in rows)
    tip_row = max(rows, key=lambda r: np.where(cat_alpha[r])[0].max())
    art.tail = (tip_x / WORK, tip_row / WORK)

    _arts[name] = art
    return art


# --- Warping ----------------------------------------------------------------


def move(center, radius, dx=0.0, dy=0.0):
    """Pushes a soft region of the image by (dx, dy), in canvas units."""
    return ("move", center, radius, dx, dy)


def turn(pivot, center, radius, degrees):
    """Rotates a soft region around a pivot, like bending a limb at a joint."""
    return ("turn", pivot, center, radius, degrees)


def _displacement(ops, x, y):
    dx = np.zeros_like(x)
    dy = np.zeros_like(y)
    for op in ops:
        if op[0] == "move":
            _, (cx, cy), r, mx, my = op
            weight = np.exp(-((x - cx * WORK) ** 2 + (y - cy * WORK) ** 2) / (2 * (r * WORK) ** 2))
            dx += weight * mx * WORK
            dy += weight * my * WORK
        else:
            _, (px, py), (cx, cy), r, degrees = op
            weight = np.exp(-((x - cx * WORK) ** 2 + (y - cy * WORK) ** 2) / (2 * (r * WORK) ** 2))
            a = math.radians(degrees)
            rx = x - px * WORK
            ry = y - py * WORK
            dx += weight * (rx * math.cos(a) - ry * math.sin(a) - rx)
            dy += weight * (rx * math.sin(a) + ry * math.cos(a) - ry)
    return dx, dy


def warp(layer, ops=(), squash=(1.0, 1.0), shift=(0.0, 0.0), lean=0.0, anchor=(0.5, GROUND / WORK)):
    """Applies soft warps, then a whole-body squash, lean and shift around the feet."""
    ax, ay = anchor[0] * WORK, anchor[1] * WORK
    a = math.radians(-lean)
    x = XX - ax - shift[0] * WORK
    y = YY - ay - shift[1] * WORK
    rx = x * math.cos(a) - y * math.sin(a)
    ry = x * math.sin(a) + y * math.cos(a)
    x = rx / squash[0] + ax
    y = ry / squash[1] + ay

    if ops:
        dx, dy = _displacement(ops, x, y)
        dx, dy = _displacement(ops, x - dx, y - dy)
        x = x - dx
        y = y - dy

    return np.stack(
        [ni.map_coordinates(layer[..., c], [y, x], order=1, mode="constant") for c in range(4)],
        axis=-1,
    )


def over(top, bottom):
    return top + bottom * (1 - top[..., 3:])


def scaled(layer, factor):
    return layer * factor


# --- Painted face variants --------------------------------------------------

EYE_LEFT = (0.283, 0.395, 0.052, 0.049)
EYE_RIGHT = (0.646, 0.438, 0.053, 0.049)
MOUTH = (0.450, 0.464, 0.059, 0.023)
INK = (43, 26, 22)


def _ellipse_mask(center, rx, ry, softness=2.5):
    mask = (((XX - center[0]) / rx) ** 2 + ((YY - center[1]) / ry) ** 2 <= 1).astype(np.float32)
    return ni.gaussian_filter(mask, softness)


def _heal(layer, mask):
    """Fills a masked region with the surrounding fur's soft shading."""
    known = (1 - np.clip(mask * 1.6, 0, 1)) * layer[..., 3]
    blurred = np.stack([ni.gaussian_filter(layer[..., c] * known, 22) for c in range(4)], axis=-1)
    weight = ni.gaussian_filter(known, 22)[..., None] + 1e-4
    fill = blurred / weight
    fill[..., 3] = layer[..., 3]
    return layer * (1 - mask[..., None]) + fill * mask[..., None]


def _paint(layer, draw_fn):
    """Draws antialiased shapes (via a 3x buffer) over a premultiplied layer."""
    image = Image.new("RGBA", (WORK * 3, WORK * 3), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(image), 3)
    image = image.resize((WORK, WORK), Image.LANCZOS)
    return over(premultiply(np.array(image)), layer)


def _feature_px(art, feature):
    cx, cy = art.n(feature[0], feature[1])
    w, h = art.source_size
    return (
        (cx * WORK, cy * WORK),
        feature[2] * w * art.scale,
        feature[3] * h * art.scale,
    )


def face(eyes="open", mouth="closed", mouth_size=1.0):
    """The base painting with its eyes and mouth repainted."""
    art = load_art("base")
    layer = art.cat.copy()

    if eyes != "open":
        for feature in (EYE_LEFT, EYE_RIGHT):
            center, rx, ry = _feature_px(art, feature)
            region = _ellipse_mask(center, rx * 1.22, ry * 1.22)
            if eyes == "half":
                # Keep the eye's lower half showing beneath a heavy lid.
                lid = np.clip((center[1] + ry * 0.05 - YY) / 3.0, 0, 1).astype(np.float32)
                region = region * lid
            layer = _heal(layer, region)

    def draw_eyes(draw, k):
        for feature in (EYE_LEFT, EYE_RIGHT):
            center, rx, ry = _feature_px(art, feature)
            box = [
                (center[0] - rx * 1.15) * k,
                (center[1] - ry * 0.75) * k,
                (center[0] + rx * 1.15) * k,
                (center[1] + ry * 0.95) * k,
            ]
            if eyes == "closed":
                # A gentle downward curve, like her sleeping expression.
                draw.arc(box, 20, 160, fill=INK + (255,), width=int(rx * 0.34 * k))
            elif eyes == "happy":
                box = [box[0], (center[1] - ry * 0.55) * k, box[2], (center[1] + ry * 1.0) * k]
                draw.arc(box, 200, 340, fill=INK + (255,), width=int(rx * 0.34 * k))
            elif eyes == "half":
                draw.line(
                    [(center[0] - rx * 1.05) * k, (center[1] + ry * 0.02) * k,
                     (center[0] + rx * 1.05) * k, (center[1] + ry * 0.02) * k],
                    fill=INK + (255,),
                    width=int(rx * 0.22 * k),
                )

    if eyes != "open":
        layer = _paint(layer, draw_eyes)

    if mouth == "open":
        center, rx, ry = _feature_px(art, MOUTH)
        layer = _heal(layer, _ellipse_mask(center, rx * 1.3, ry * 1.8))
        open_rx = rx * 0.72 * mouth_size
        open_ry = ry * 1.75 * mouth_size

        def draw_mouth(draw, k):
            box = [(center[0] - open_rx) * k, (center[1] - open_ry * 0.75) * k,
                   (center[0] + open_rx) * k, (center[1] + open_ry * 1.25) * k]
            draw.ellipse(box, fill=(84, 30, 36, 255), outline=INK + (255,), width=int(rx * 0.12 * k))
            tongue = [(center[0] - open_rx * 0.62) * k, (center[1] + open_ry * 0.25) * k,
                      (center[0] + open_rx * 0.62) * k, (center[1] + open_ry * 1.2) * k]
            draw.ellipse(tongue, fill=(226, 120, 128, 255))

        layer = _paint(layer, draw_mouth)

    return layer


# --- Rig points --------------------------------------------------------------


def wave_sin(t, cycles=1.0, phase=0.0):
    return math.sin(2 * math.pi * (t * cycles + phase))


def tail_swing(art, degrees):
    tx, ty = art.tail
    return turn((tx - 0.13, ty + 0.13), (tx - 0.03, ty + 0.02), 0.10, degrees)


class BaseRig:
    art = staticmethod(lambda: load_art("base"))

    @staticmethod
    def points():
        a = load_art("base")
        return dict(
            neck=a.g(0.47, 0.68),
            head=a.g(0.47, 0.35),
            ear_l=a.g(0.21, 0.09),
            ear_r=a.g(0.84, 0.16),
            ear_l_base=a.g(0.25, 0.19),
            ear_r_base=a.g(0.78, 0.25),
            paw_l=a.g(0.36, 0.93),
            paw_r=a.g(0.55, 0.93),
            haunch_l=a.g(0.21, 0.88),
            haunch_r=a.g(0.72, 0.87),
            arm_l=a.g(0.34, 0.78),
            arm_r=a.g(0.60, 0.78),
        )


# --- Animation recipes -------------------------------------------------------


def lay(cat, ops=(), squash=(1, 1), shift=(0, 0), lean=0.0, deco=None, deco_shift=(0, 0), deco_alpha=1.0, anchor=(0.5, GROUND / WORK)):
    frame = warp(cat, ops, squash, shift, lean, anchor)
    if deco is not None:
        moved = warp(deco, (), (1, 1), (shift[0] + deco_shift[0], shift[1] + deco_shift[1]))
        frame = over(scaled(moved, deco_alpha), frame)
    return frame


def breathing(t, amount, cycles=1.0):
    s = wave_sin(t, cycles)
    return (1 - amount * 0.55 * s, 1 + amount * s)


def idle_frames(n=12):
    a, p, frames = load_art("base"), BaseRig.points(), []
    for i in range(n):
        t = i / n
        ops = [
            tail_swing(a, 9 * wave_sin(t)),
            turn(p["neck"], p["head"], 0.30, 0.8 * wave_sin(t, 1, 0.2)),
        ]
        # A quick ear flick late in the cycle.
        if i in (8, 9):
            ops.append(turn(p["ear_r_base"], p["ear_r"], 0.08, 7 if i == 8 else 3))
        frames.append(lay(a.cat, ops, breathing(t, 0.009)))
    return frames


def sit_frames(n=8):
    a, p, frames = load_art("base"), BaseRig.points(), []
    for i in range(n):
        t = i / n
        ops = [
            tail_swing(a, 4 * wave_sin(t)),
            turn(p["neck"], p["head"], 0.30, -1.2),
        ]
        sx, sy = breathing(t, 0.006)
        frames.append(lay(a.cat, ops, (sx, sy * 0.985)))
    return frames


def blink_frames():
    return [face(), face("half"), face("closed"), face("half")]


def walk_cycle(n, stride, lift, bob, lean, tail, arm):
    a, frames = load_art("walk"), []
    leg_a = a.g(0.42, 0.91)    # supporting leg
    hip_a = a.g(0.42, 0.74)
    leg_b = a.g(0.62, 0.90)    # stepping leg
    hip_b = a.g(0.60, 0.74)
    arm_a = a.g(0.40, 0.68)
    shoulder_a = a.g(0.43, 0.62)
    arm_b = a.g(0.75, 0.66)
    shoulder_b = a.g(0.68, 0.59)
    tail_tip = a.g(0.19, 0.70)
    tail_base = a.g(0.31, 0.76)
    neck = a.g(0.47, 0.60)
    head = a.g(0.50, 0.32)
    ear_l = a.g(0.18, 0.16)
    ear_l_base = a.g(0.22, 0.25)
    ear_r = a.g(0.72, 0.09)
    ear_r_base = a.g(0.68, 0.18)

    for i in range(n):
        t = i / n
        s = wave_sin(t)
        c = wave_sin(t, 1, 0.25)
        lift_a = max(0.0, -c)
        lift_b = max(0.0, c)
        ops = [
            # The painted pose has the near leg back and the far leg forward, so
            # the cycle swings each leg either side of where it was painted.
            move(leg_a, 0.075, stride * s, -lift * lift_a),
            turn(hip_a, leg_a, 0.085, -7 * s),
            move(leg_b, 0.085, -stride * s - stride * 0.25, -lift * lift_b),
            turn(hip_b, leg_b, 0.09, 7 * s),
            # Arms counter-swing the legs.
            turn(shoulder_a, arm_a, 0.075, arm * s),
            turn(shoulder_b, arm_b, 0.07, -arm * s),
            turn(tail_base, tail_tip, 0.09, tail * wave_sin(t, 1, 0.1)),
            turn(neck, head, 0.33, 1.4 * s),
            turn(ear_l_base, ear_l, 0.07, 3.0 * c),
            turn(ear_r_base, ear_r, 0.07, -3.0 * c),
        ]
        # Two bobs per cycle: highest as each leg passes under the body.
        rise = abs(c)
        frames.append(lay(a.cat, ops, (1 + 0.006 * rise, 1 - 0.008 * rise), (0, -bob * (1 - rise)), lean + 1.2 * s))
    return frames


def walk_frames():
    return walk_cycle(10, stride=0.045, lift=0.030, bob=0.006, lean=1.5, tail=14, arm=12)


def run_frames():
    return walk_cycle(8, stride=0.075, lift=0.050, bob=0.014, lean=5.0, tail=22, arm=24)


def sleep_cycle(n=10, decorated=True):
    a, frames = load_art("sleep"), []
    head = a.g(0.40, 0.65)
    back = a.g(0.82, 0.76)
    for i in range(n):
        t = i / n
        s = wave_sin(t)
        ops = [
            move(back, 0.14, 0, -0.006 * s),
            move(head, 0.22, 0, 0.003 * s),
            move(a.g(0.27, 0.78), 0.03, 0.0035 * s, 0.002 * s),  # the little bubble
        ]
        drift = -0.012 * (t if t < 1 else 1)
        frames.append(lay(
            a.cat, ops, (1 - 0.005 * s, 1 + 0.012 * s),
            deco=a.deco if decorated else None,
            deco_shift=(0.008 * s, drift),
        ))
    return frames


def wake_frames():
    a, p = load_art("sleep"), BaseRig.points()
    b = load_art("base")
    return [
        lay(a.cat, (), (1, 1.0)),
        lay(a.cat, (), (0.99, 1.03)),
        lay(a.cat, (), (0.98, 1.07)),
        lay(face("closed"), [], (1.02, 0.90)),
        lay(face("half"), [], (1.0, 0.96)),
        lay(face("half"), [tail_swing(b, 8)], (0.99, 1.02)),
        lay(face(), [tail_swing(b, 4)], (1, 1.005)),
        lay(face(), [], (1, 1)),
    ]


def stretch_frames():
    b, p = load_art("base"), BaseRig.points()
    closed = face("closed")
    keys = [
        (face(), 0.00, 0.0, 0.0),
        (closed, 0.35, 0.3, 0.2),
        (closed, 0.80, 0.8, 0.6),
        (closed, 1.00, 1.0, 1.0),
        (closed, 1.00, 1.0, 1.0),
        (closed, 0.70, 0.6, 0.6),
        (face("half"), 0.30, 0.2, 0.2),
        (face(), 0.05, 0.0, 0.0),
    ]
    frames = []
    for layer, amount, paws, tail in keys:
        ops = [
            # Front paws slide out and the head dips as her back arches up.
            move(p["paw_l"], 0.07, -0.030 * paws, 0.0),
            move(p["paw_r"], 0.07, 0.030 * paws, 0.0),
            move(p["head"], 0.30, 0, 0.012 * amount),
            turn(p["neck"], p["head"], 0.3, -2.0 * amount),
            tail_swing(b, -24 * tail),
        ]
        frames.append(lay(layer, ops, (1 + 0.045 * amount, 1 - 0.06 * amount)))
    return frames


def yawn_frames():
    b, p = load_art("base"), BaseRig.points()
    keys = [
        (face("half"), 0.1),
        (face("half", "open", 0.8), 0.4),
        (face("closed", "open", 1.2), 0.8),
        (face("closed", "open", 1.6), 1.0),
        (face("closed", "open", 1.6), 1.0),
        (face("closed", "open", 1.1), 0.6),
        (face("half", "open", 0.7), 0.3),
        (face(), 0.0),
    ]
    return [
        lay(layer, [turn(p["neck"], p["head"], 0.3, 2.5 * amount), tail_swing(b, 7 * amount)],
            (1 - 0.006 * amount, 1 + 0.004 * amount))
        for layer, amount in keys
    ]


def paws_at_mouth_frames(name, n, keep_deco, tilt=2.0, rub=0.010):
    """Licking or rubbing: both paws work up and down in front of the mouth."""
    a, frames = load_art(name), []
    paw_a = a.g(0.40, 0.56)
    paw_b = a.g(0.60, 0.56)
    head = a.g(0.50, 0.32)
    neck = a.g(0.50, 0.62)
    for i in range(n):
        t = i / n
        s = wave_sin(t, 2)
        ops = [
            move(paw_a, 0.07, 0.002 * s, -rub * s),
            move(paw_b, 0.07, -0.002 * s, rub * s),
            turn(neck, head, 0.30, tilt * wave_sin(t)),
            tail_swing(a, 6 * wave_sin(t)),
        ]
        frames.append(lay(a.cat, ops, breathing(t, 0.006), deco=a.deco if keep_deco else None))
    return frames


def groom_frames():
    return paws_at_mouth_frames("shy", 10, keep_deco=False, tilt=2.5, rub=0.012)


def nibble_frames(n, dip, cycles, tail):
    a, frames = load_art("hungry"), []
    head = a.g(0.50, 0.35)
    neck = a.g(0.50, 0.62)
    paws = a.g(0.50, 0.68)
    for i in range(n):
        t = i / n
        s = wave_sin(t, cycles)
        ops = [
            move(head, 0.28, 0, dip * (s + 1) / 2),
            turn(neck, head, 0.3, 1.2 * wave_sin(t)),
            move(paws, 0.09, 0, -0.008 * s),
            tail_swing(a, tail * wave_sin(t)),
        ]
        frames.append(lay(a.cat, ops, breathing(t, 0.005), deco=a.deco, deco_shift=(0, -0.006 * (s + 1))))
    return frames


def eat_frames():
    return nibble_frames(8, 0.014, 2, 8)


def drink_frames():
    return nibble_frames(6, 0.009, 2, 4)


def hop_frames(name, keep_deco=True, depth=0.11):
    """A springy bounce. The art already fills the canvas height, so the energy
    comes from crouching low and rebounding, not from leaving the top of the frame."""
    a = load_art(name)
    keys = [
        ((1.0, 1.0), 0.0),
        ((1 + depth * 0.5, 1 - depth), 0.0),
        ((1 + depth * 0.2, 1 - depth * 0.4), 0.0),
        ((0.985, 1.0), -0.004),
        ((1 + depth * 0.2, 1 - depth * 0.4), 0.0),
        ((1 + depth * 0.5, 1 - depth), 0.0),
        ((1 + depth * 0.1, 1 - depth * 0.25), 0.0),
        ((1.0, 1.0), 0.0),
    ]
    frames = []
    for i, (squash, lift) in enumerate(keys):
        ops = [tail_swing(a, 9 * wave_sin(i / len(keys), 2))]
        frames.append(lay(a.cat, ops, squash, (0, lift), deco=a.deco if keep_deco else None))
    return frames


def rock_frames(name, n, lean, tail, cycles=1.0, breath=0.008, keep_deco=True):
    a, frames = load_art(name), []
    for i in range(n):
        t = i / n
        ops = [tail_swing(a, tail * wave_sin(t, cycles * 2))]
        s = wave_sin(t, cycles)
        frames.append(lay(a.cat, ops, breathing(t, breath, cycles), lean=lean * s,
                          deco=a.deco if keep_deco else None, deco_shift=(0, -0.004 * abs(s))))
    return frames


def shiver_frames():
    a, frames = load_art("scared"), []
    for i in range(6):
        direction = 1 if i % 2 == 0 else -1
        frames.append(lay(a.cat, [tail_swing(a, 3 * direction)], (0.99, 0.985), (0.005 * direction, 0),
                          deco=a.deco))
    return frames


def surprised_frames():
    a = load_art("scared")
    keys = [((1.05, 0.90), 0), ((1.02, 0.96), 0), ((0.985, 1.0), -0.002), ((1.03, 0.95), 0), ((1, 1), 0)]
    return [lay(a.cat, [], s, (0, y), deco=a.deco) for s, y in keys]


def curious_frames(n=10):
    b, p, frames = load_art("base"), BaseRig.points(), []
    for i in range(n):
        t = i / n
        s = wave_sin(t)
        ops = [
            turn(p["neck"], p["head"], 0.32, 4.5 * s),
            turn(p["ear_r_base"], p["ear_r"], 0.08, -5 * max(0, s)),
            turn(p["ear_l_base"], p["ear_l"], 0.08, -5 * max(0, -s)),
            tail_swing(b, 6 * wave_sin(t, 2)),
        ]
        frames.append(lay(b.cat, ops, breathing(t, 0.005)))
    return frames


def investigate_frames(n=8):
    b, p, frames = load_art("base"), BaseRig.points(), []
    for i in range(n):
        t = i / n
        s = wave_sin(t)
        ops = [
            move(p["head"], 0.30, 0.018, 0.012 + 0.004 * s),
            turn(p["neck"], p["head"], 0.3, 3.0 + 2.0 * s),
            move(p["paw_r"], 0.06, 0.012 * max(0, s), -0.012 * max(0, s)),
            tail_swing(b, 11 * wave_sin(t, 2)),
        ]
        frames.append(lay(b.cat, ops, (1.01, 0.975)))
    return frames


def meow_frames():
    b, p = load_art("base"), BaseRig.points()
    keys = [
        (face(), 0.0),
        (face("open", "open", 0.8), 0.5),
        (face("happy", "open", 1.3), 1.0),
        (face("happy", "open", 1.3), 1.0),
        (face("open", "open", 0.8), 0.5),
        (face(), 0.0),
    ]
    return [lay(layer, [turn(p["neck"], p["head"], 0.3, -3 * amount), tail_swing(b, 10 * amount)],
                (1 - 0.01 * amount, 1 + 0.02 * amount)) for layer, amount in keys]


def tired_frames(n=8):
    b, p, frames = load_art("base"), BaseRig.points(), []
    half = face("half")
    closed = face("closed")
    for i in range(n):
        t = i / n
        layer = closed if i in (4, 5) else half
        ops = [
            move(p["head"], 0.30, 0, 0.012 + 0.006 * wave_sin(t)),
            turn(p["neck"], p["head"], 0.3, 2.0),
            tail_swing(b, 2.5 * wave_sin(t)),
        ]
        frames.append(lay(layer, ops, (1.008, 0.975 + 0.006 * wave_sin(t))))
    return frames


def in_box_frames(n=8):
    closed = face("closed")
    half = face("half")
    return [lay(closed if i >= 3 else half, (), (0.78, 0.78 * (1 + 0.012 * wave_sin(i / n))), (0, -0.16)) for i in range(n)]


def box_peek_frames(n=6):
    happy = face("happy")
    opened = face()
    return [lay(happy if i % 3 == 2 else opened, (), (0.78, 0.78), (0, -0.16 - 0.015 * abs(wave_sin(i / n)))) for i in range(n)]


def jump_frames():
    b, p = load_art("base"), BaseRig.points()
    keys = [
        (1.0, 1.0, 0.0, 0),
        (1.06, 0.90, 0.0, -10),
        (1.08, 0.86, 0.0, -16),
        (0.96, 1.01, 0.0, 12),
        (0.97, 1.01, 0.0, 18),
        (0.99, 1.0, 0.0, 10),
    ]
    frames = []
    for sx, sy, y, tail in keys:
        stretch = max(0.0, 1.0 - sx) / 0.04
        ops = [
            tail_swing(b, tail),
            move(p["haunch_l"], 0.10, -0.01 * stretch, 0.012 * stretch),
            move(p["haunch_r"], 0.10, 0.01 * stretch, 0.012 * stretch),
        ]
        frames.append(lay(b.cat, ops, (sx, sy), (0, y)))
    return frames


def fall_frames(n=6):
    a, frames = load_art("walk"), []
    leg_a = a.g(0.42, 0.91)
    leg_b = a.g(0.62, 0.90)
    arm_a = a.g(0.40, 0.68)
    arm_b = a.g(0.75, 0.66)
    tail_tip = a.g(0.19, 0.70)
    tail_base = a.g(0.31, 0.76)
    for i in range(n):
        s = wave_sin(i / n)
        ops = [
            move(leg_a, 0.08, -0.012 + 0.006 * s, -0.012),
            move(leg_b, 0.08, 0.012 - 0.006 * s, -0.016),
            move(arm_a, 0.07, -0.006, -0.018 - 0.006 * s),
            move(arm_b, 0.07, 0.008, -0.022 + 0.006 * s),
            turn(tail_base, tail_tip, 0.09, 16 + 10 * s),
        ]
        frames.append(lay(a.cat, ops, (0.985, 1.0), lean=2.5 * s, anchor=(0.5, 0.5)))
    return frames


def picked_up_frames(n=8):
    b, p, frames = load_art("base"), BaseRig.points(), []
    head = p["head"]
    for i in range(n):
        s = wave_sin(i / n)
        ops = [
            # Hanging from the scruff: paws and haunches dangle and sway.
            move(p["paw_l"], 0.07, 0.008 * s, 0.015),
            move(p["paw_r"], 0.07, 0.008 * s, 0.018),
            move(p["haunch_l"], 0.08, 0.012 * s, 0.022),
            move(p["haunch_r"], 0.08, 0.012 * s, 0.022),
            tail_swing(b, 10 * s),
        ]
        frames.append(lay(b.cat, ops, (0.985, 1.0), lean=2.2 * s, anchor=head))
    return frames


def dropped_frames():
    a = load_art("dizzy")
    keys = [((1.08, 0.84), 0), ((1.05, 0.90), 0), ((0.98, 1.0), -0.003), ((1.03, 0.95), 0),
            ((0.99, 1.0), 0), ((1, 1), 0), ((1, 1), 0), ((1, 1), 0)]
    return [lay(a.cat, [tail_swing(a, 7 * wave_sin(i / 4))], s, (0, y), lean=2 * wave_sin(i / 4),
                deco=a.deco, deco_shift=(0.008 * wave_sin(i / 4), 0)) for i, (s, y) in enumerate(keys)]


def wave_emote_frames(n=10):
    a, frames = load_art("wave"), []
    paw = a.g(0.14, 0.60)
    shoulder = a.g(0.27, 0.70)
    for i in range(n):
        t = i / n
        s = wave_sin(t, 2)
        ops = [
            turn(shoulder, paw, 0.11, 13 * s),
            tail_swing(a, 11 * s),
            turn(a.g(0.50, 0.66), a.g(0.50, 0.35), 0.30, 1.8 * wave_sin(t)),
        ]
        frames.append(lay(a.cat, ops, breathing(t, 0.005), deco=a.deco, deco_shift=(0.004 * s, 0), deco_alpha=0.6 + 0.4 * abs(s)))
    return frames


def love_frames(n=10):
    a, frames = load_art("shy"), []
    for i in range(n):
        t = i / n
        ops = [
            move(a.g(0.5, 0.56), 0.09, 0, -0.006 * wave_sin(t, 2)),
            turn(a.g(0.5, 0.62), a.g(0.5, 0.34), 0.3, 2.2 * wave_sin(t)),
            tail_swing(a, 9 * wave_sin(t)),
        ]
        frames.append(lay(a.cat, ops, breathing(t, 0.008), deco=a.deco, deco_shift=(0, -0.018 * t), deco_alpha=1 - 0.5 * t))
    return frames


def climb_frames(n=8):
    return [lay(frame, lean=-2.5, anchor=(0.5, 0.9)) for frame in walk_cycle(n, 0.04, 0.03, 0.005, 0.0, 10, 18)]


@dataclass
class Sheet:
    category: str
    fps: float
    loop: bool
    frames: callable
    order: list = None
    windows_only: bool = False


def repeat(count, n):
    return list(range(n)) * count


SHEETS = {
    "idle": Sheet("Idle", 8, True, idle_frames),
    "idleBlink": Sheet("Idle", 14, False, blink_frames),
    "sit": Sheet("Idle", 6, True, sit_frames),
    "stretch": Sheet("Idle", 7, False, stretch_frames),
    "yawn": Sheet("Idle", 7, False, yawn_frames),
    "groom": Sheet("Idle", 8, False, groom_frames),
    "tired": Sheet("Idle", 5, True, tired_frames),
    "walk": Sheet("Walk", 12, True, walk_frames),
    "run": Sheet("Run", 16, True, run_frames),
    "sleep": Sheet("Sleep", 5, True, sleep_cycle),
    "wake": Sheet("Sleep", 7, False, wake_frames),
    "eat": Sheet("Interaction", 8, True, eat_frames),
    "drink": Sheet("Interaction", 7, True, drink_frames),
    "pet": Sheet("Interaction", 10, False, lambda: hop_frames("eyes-close", depth=0.07)),
    "meow": Sheet("Interaction", 8, False, meow_frames),
    "investigate": Sheet("Interaction", 7, True, investigate_frames),
    "happy": Sheet("Emotions", 10, False, lambda: hop_frames("eyes-close")),
    "surprised": Sheet("Emotions", 10, False, surprised_frames),
    "scared": Sheet("Emotions", 14, False, shiver_frames),
    "annoyed": Sheet("Emotions", 7, True, lambda: rock_frames("angry", 8, 1.2, 15)),
    "curious": Sheet("Emotions", 7, True, curious_frames),
    "playful": Sheet("Emotions", 9, True, lambda: rock_frames("mischievous", 8, 2.5, 20)),
    "jump": Sheet("Special", 12, False, jump_frames),
    "fall": Sheet("Special", 9, False, fall_frames),
    "pickedUp": Sheet("Special", 7, True, picked_up_frames),
    "dropped": Sheet("Special", 10, False, dropped_frames),
    # Live emotes on Mac play whole-pose stickers with SpriteKit actions, so these sheets are used by
    # Windows and by Photo Mode on both platforms. The frame orders repeat to fill each emote's time.
    "wave": Sheet("Emotes", 9, False, wave_emote_frames, repeat(3, 10)),
    "emote-happy": Sheet("Emotes", 10, False, lambda: hop_frames("eyes-close"), repeat(3, 8)),
    "love": Sheet("Emotes", 7, False, love_frames, repeat(2, 10)),
    "sleepy": Sheet("Emotes", 5, False, lambda: sleep_cycle(10), repeat(2, 10)),
    "emote-playful": Sheet("Emotes", 9, False, lambda: rock_frames("mischievous", 8, 2.5, 20), repeat(3, 8)),
    # The Mac draws its own box around the cat, and it has no climb animation.
    "inBox": Sheet("Special", 4, True, in_box_frames, windows_only=True),
    "boxPeek": Sheet("Special", 6, False, box_peek_frames, windows_only=True),
    "climb": Sheet("Special", 10, True, climb_frames, windows_only=True),
}

# Files keep the app's sheet names; "emote-" only separates dictionary keys.
FILE_NAMES = {"emote-happy": "happy", "emote-playful": "playful"}


# --- Output -----------------------------------------------------------------


def to_image(frame):
    """Downsamples a working frame to the shipped size as straight-alpha RGBA."""
    pre = np.clip(frame, 0, 1)
    channels = []
    for c in range(4):
        channel = Image.fromarray((pre[..., c] * 255).astype(np.uint8))
        channels.append(np.array(channel.resize((FRAME, FRAME), Image.LANCZOS)).astype(np.float32))
    r, g, b, a = channels
    a = np.where(a < 3, 0, a)
    safe = np.maximum(a, 1) / 255.0
    rgba = np.stack(
        [np.clip(r / safe, 0, 255), np.clip(g / safe, 0, 255), np.clip(b / safe, 0, 255), a],
        axis=-1,
    )
    rgba[a == 0] = 0
    return Image.fromarray(rgba.astype(np.uint8))


def _touches_top_or_sides(frame):
    alpha = np.array(frame)[..., 3]
    return (alpha[0, :] > 40).any() or (alpha[:, 0] > 40).any() or (alpha[:, -1] > 40).any()


def write_sheet(key, sheet, preview_dir):
    name = FILE_NAMES.get(key, key)
    frames = [to_image(f) for f in sheet.frames()]
    clipped = [i for i, f in enumerate(frames) if _touches_top_or_sides(f)]
    if clipped:
        print(f"warning: {key} frames {clipped} are cut off by the canvas edge")
    columns = min(len(frames), 6)
    rows = math.ceil(len(frames) / columns)

    canvas = Image.new("RGBA", (columns * FRAME, rows * FRAME), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        canvas.paste(frame, (index % columns * FRAME, index // columns * FRAME))

    out_dir = (WINDOWS_OUT if sheet.windows_only else SHARED_OUT) / sheet.category
    out_dir.mkdir(parents=True, exist_ok=True)
    canvas.save(out_dir / f"{name}.png", optimize=True)

    # Always listed: the last grid row may have empty cells that must never play.
    manifest = {
        "grid": [columns, rows],
        "fps": sheet.fps,
        "loop": sheet.loop,
        "frames": sheet.order or list(range(len(frames))),
    }
    (out_dir / f"{name}.json").write_text(json.dumps(manifest) + "\n")

    size = (out_dir / f"{name}.png").stat().st_size
    print(f"{sheet.category + '/' + name:26} {len(frames):3} frames  {size / 1024:7.0f} KB")

    if preview_dir:
        preview_dir.mkdir(parents=True, exist_ok=True)
        strip = Image.new("RGB", (len(frames) * 180, 180), (70, 80, 100))
        for index, frame in enumerate(frames):
            small = frame.resize((180, 180), Image.LANCZOS)
            strip.paste(small, (index * 180, 0), small)
        strip.save(preview_dir / f"{key}.png")
        gif = [Image.alpha_composite(Image.new("RGBA", frame.size, (70, 80, 100, 255)), frame).convert("P", palette=Image.ADAPTIVE) for frame in frames]
        gif[0].save(preview_dir / f"{key}.gif", save_all=True, append_images=gif[1:], loop=0, duration=int(1000 / sheet.fps))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("sheets", nargs="*", help="sheet names to generate (default: all)")
    parser.add_argument("--preview", type=Path, help="directory for review strips and GIFs")
    args = parser.parse_args()

    for key in args.sheets or SHEETS:
        write_sheet(key, SHEETS[key], args.preview)


if __name__ == "__main__":
    main()
