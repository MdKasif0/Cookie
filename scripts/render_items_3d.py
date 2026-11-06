#!/usr/bin/env python3
"""Renders Cookie's toys, treats and accessories as soft 3D art.

A small numpy raymarcher lights signed-distance models with the same warm key
light and glowing rim as Cookie's painted artwork, so everything looks like it
belongs in her world. Output is shared by the macOS and Windows apps.

Requires numpy and Pillow. Run from the repository root:

    python3 scripts/render_items_3d.py
    python3 scripts/render_items_3d.py ball crown --preview DIR
"""

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Cookie/Resources/Sprites/Cookie"

# --- Vectors and shapes ------------------------------------------------------
# A point set is a tuple of arrays (x, y, z): x right, y up, z toward the viewer.


def length(*parts):
    return np.sqrt(sum(p * p for p in parts))


def sphere(p, c, r):
    return length(p[0] - c[0], p[1] - c[1], p[2] - c[2]) - r


def ellipsoid(p, c, r):
    x, y, z = (p[0] - c[0]) / r[0], (p[1] - c[1]) / r[1], (p[2] - c[2]) / r[2]
    k0 = length(x, y, z)
    k1 = length(x / r[0], y / r[1], z / r[2])
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-5)


def capsule(p, a, b, r):
    ax, ay, az = p[0] - a[0], p[1] - a[1], p[2] - a[2]
    bx, by, bz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    h = np.clip((ax * bx + ay * by + az * bz) / (bx * bx + by * by + bz * bz), 0, 1)
    return length(ax - bx * h, ay - by * h, az - bz * h) - r


def chain(p, points, r):
    """A soft tube through points; r may taper from start to end."""
    radii = r if isinstance(r, (list, tuple)) else (r, r)
    d = None
    count = len(points) - 1
    for i in range(count):
        radius = radii[0] + (radii[1] - radii[0]) * (i + 0.5) / count
        part = capsule(p, points[i], points[i + 1], radius)
        d = part if d is None else np.minimum(d, part)
    return d


def round_box(p, c, half, r):
    qx = np.abs(p[0] - c[0]) - half[0] + r
    qy = np.abs(p[1] - c[1]) - half[1] + r
    qz = np.abs(p[2] - c[2]) - half[2] + r
    outside = length(np.maximum(qx, 0), np.maximum(qy, 0), np.maximum(qz, 0))
    return outside + np.minimum(np.maximum(qx, np.maximum(qy, qz)), 0) - r


def cylinder_y(p, c, radius, half, r=0.0):
    dx = length(p[0] - c[0], p[2] - c[2]) - radius + r
    dy = np.abs(p[1] - c[1]) - half + r
    return np.minimum(np.maximum(dx, dy), 0) + length(np.maximum(dx, 0), np.maximum(dy, 0)) - r


def torus_y(p, c, major, minor):
    q = length(p[0] - c[0], p[2] - c[2]) - major
    return length(q, p[1] - c[1]) - minor


def torus_z(p, c, major, minor, stretch_y=1.0):
    q = length(p[0] - c[0], (p[1] - c[1]) / stretch_y) - major
    return length(q, p[2] - c[2]) - minor


def smooth_min(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def rotate(p, center, axis, degrees):
    """Coordinates of p in a frame rotated about center; rotating the model by +degrees."""
    a = math.radians(-degrees)
    c, s = math.cos(a), math.sin(a)
    x, y, z = p[0] - center[0], p[1] - center[1], p[2] - center[2]
    if axis == "z":
        x, y = x * c - y * s, x * s + y * c
    elif axis == "x":
        y, z = y * c - z * s, y * s + z * c
    else:
        x, z = x * c + z * s, -x * s + z * c
    return (x + center[0], y + center[1], z + center[2])


def bumps(p, scale):
    return np.sin(p[0] * scale) * np.sin(p[1] * scale * 1.13 + 1.3) * np.sin(p[2] * scale * 0.91 + 2.1)


def srgb(hex_color):
    v = hex_color.lstrip("#")
    rgb = np.array([int(v[i:i + 2], 16) / 255 for i in (0, 2, 4)])
    return rgb ** 2.2


def solid(hex_color):
    color = srgb(hex_color)

    def fill(p):
        return np.broadcast_to(color, p[0].shape + (3,))

    return fill


def mix_by(mask, a, b):
    return a * (1 - mask[..., None]) + b * mask[..., None]


# --- Renderer ---------------------------------------------------------------


@dataclass
class Part:
    sdf: callable
    color: callable
    gloss: float = 0.0
    glow: float = 1.0


KEY_DIR = np.array([-0.42, 0.74, 0.52])
KEY_DIR = KEY_DIR / np.linalg.norm(KEY_DIR)
FILL_DIR = np.array([0.72, 0.12, 0.68])
FILL_DIR = FILL_DIR / np.linalg.norm(FILL_DIR)


def scene_distance(parts, p):
    d = None
    for part in parts:
        value = part.sdf(p)
        d = value if d is None else np.minimum(d, value)
    return d


def render(parts, size, pitch=14.0, view=1.0, center=(0.0, 0.0)):
    """Marches an orthographic view; returns a linear premultiplied RGBA float image."""
    scale = 2 * view / size
    px, py = np.meshgrid(
        (np.arange(size) + 0.5) * scale - view + center[0],
        view - (np.arange(size) + 0.5) * scale + center[1],
    )
    px, py = px.ravel(), py.ravel()
    count = px.size

    a = math.radians(pitch)
    ray = np.array([0.0, -math.sin(a), -math.cos(a)])
    up = np.array([0.0, math.cos(a), -math.sin(a)])
    right = np.array([1.0, 0.0, 0.0])
    start = 3.2
    ox = px * right[0] + py * up[0] - ray[0] * start
    oy = px * right[1] + py * up[1] - ray[1] * start
    oz = px * right[2] + py * up[2] - ray[2] * start

    t = np.zeros(count)
    hit = np.zeros(count, dtype=bool)
    active = np.arange(count)
    for _ in range(90):
        if active.size == 0:
            break
        p = (ox[active] + ray[0] * t[active], oy[active] + ray[1] * t[active], oz[active] + ray[2] * t[active])
        d = scene_distance(parts, p)
        reached = d < 0.0012
        hit[active[reached]] = True
        t[active] += d * 0.9
        keep = (~reached) & (t[active] < 6.5)
        active = active[keep]

    image = np.zeros((count, 4))
    index = np.where(hit)[0]
    if index.size:
        q = (ox[index] + ray[0] * t[index], oy[index] + ray[1] * t[index], oz[index] + ray[2] * t[index])
        image[index] = shade(parts, q, ray)
    return image.reshape(size, size, 4)


def shade(parts, q, ray):
    e = 0.002
    samples = [(1, -1, -1), (-1, -1, 1), (-1, 1, -1), (1, 1, 1)]
    nx = ny = nz = 0
    for sx, sy, sz in samples:
        v = scene_distance(parts, (q[0] + sx * e, q[1] + sy * e, q[2] + sz * e))
        nx, ny, nz = nx + sx * v, ny + sy * v, nz + sz * v
    norm = np.maximum(length(nx, ny, nz), 1e-6)
    nx, ny, nz = nx / norm, ny / norm, nz / norm

    values = np.stack([part.sdf(q) for part in parts])
    material = np.argmin(values, axis=0)

    albedo = np.zeros(q[0].shape + (3,))
    gloss = np.zeros(q[0].shape)
    glow = np.ones(q[0].shape)
    for i, part in enumerate(parts):
        mask = material == i
        if mask.any():
            albedo[mask] = part.color((q[0][mask], q[1][mask], q[2][mask]))
            gloss[mask] = part.gloss
            glow[mask] = part.glow

    # Ambient occlusion from the distance field.
    occlusion = np.zeros(q[0].shape)
    for step in range(1, 5):
        h = 0.035 * step
        d = scene_distance(parts, (q[0] + nx * h, q[1] + ny * h, q[2] + nz * h))
        occlusion += np.maximum(h - d, 0) / (2 ** step)
    ao = np.clip(1 - 7.0 * occlusion, 0.2, 1)

    # Soft shadow toward the key light.
    shadow = np.ones(q[0].shape)
    travel = np.full(q[0].shape, 0.03)
    for _ in range(14):
        d = scene_distance(parts, (
            q[0] + nx * 0.006 + KEY_DIR[0] * travel,
            q[1] + ny * 0.006 + KEY_DIR[1] * travel,
            q[2] + nz * 0.006 + KEY_DIR[2] * travel,
        ))
        shadow = np.minimum(shadow, np.clip(9 * d / travel, 0, 1))
        travel += np.clip(d, 0.012, 0.15)
    shadow = 0.5 + 0.5 * shadow

    key = np.clip((nx * KEY_DIR[0] + ny * KEY_DIR[1] + nz * KEY_DIR[2] + 0.42) / 1.42, 0, 1) ** 1.2
    fill = np.clip((nx * FILL_DIR[0] + ny * FILL_DIR[1] + nz * FILL_DIR[2] + 0.5) / 1.5, 0, 1)
    sky = 0.5 + 0.5 * ny
    facing = np.clip(-(nx * ray[0] + ny * ray[1] + nz * ray[2]), 0, 1)
    rim = (1 - facing) ** 2.6

    warm = np.array([1.0, 0.93, 0.82])
    cool = np.array([0.92, 0.84, 0.88])
    bounce = np.array([1.0, 0.82, 0.66])
    light = (
        warm * (key * shadow * 1.12)[..., None]
        + cool * (fill * 0.20)[..., None]
        + bounce * ((1 - sky) * 0.26)[..., None]
        + np.array([1.0, 0.97, 0.93]) * 0.20
    )
    color = albedo * light * ao[..., None]

    # The soft golden edge glow Cookie has, as if light passes through her.
    color += albedo ** 0.6 * np.array([1.0, 0.72, 0.42]) * (rim * glow * 0.38)[..., None]

    # Highlight.
    hx, hy, hz = KEY_DIR[0] - ray[0], KEY_DIR[1] - ray[1], KEY_DIR[2] - ray[2]
    hn = math.sqrt(hx * hx + hy * hy + hz * hz)
    spec = np.clip((nx * hx + ny * hy + nz * hz) / hn, 0, 1)
    color += (spec ** (20 + 90 * gloss) * gloss * 0.9 * shadow)[..., None] * np.array([1.0, 0.98, 0.95])

    return np.concatenate([color, np.ones(q[0].shape + (1,))], axis=-1)


def to_srgb_image(linear, out_size):
    """Filmic-free soft clip and sRGB encoding, downsampled with premultiplied alpha."""
    alpha = linear[..., 3]
    color = np.clip(linear[..., :3], 0, None)
    color = color / (1 + np.maximum(color - 0.75, 0) * 0.55)
    color = np.clip(color, 0, 1) ** (1 / 2.2)
    rgba = np.concatenate([color * alpha[..., None], alpha[..., None]], axis=-1)
    channels = [
        Image.fromarray((rgba[..., c] * 255 + 0.5).astype(np.uint8)).resize((out_size, out_size), Image.LANCZOS)
        for c in range(4)
    ]
    r, g, b, a = [np.array(c).astype(np.float32) for c in channels]
    safe = np.maximum(a, 1) / 255
    result = np.stack([np.clip(r / safe, 0, 255), np.clip(g / safe, 0, 255), np.clip(b / safe, 0, 255), a], axis=-1)
    result[a < 2] = 0
    return Image.fromarray(result.astype(np.uint8))


def contact_shadow(size, width, ground=0.9, height=0.075, opacity=0.26):
    """A soft shadow pooled under an item."""
    scale = 2
    image = Image.new("L", (size * scale, size * scale), 0)
    draw = ImageDraw.Draw(image)
    cx = size * scale / 2
    cy = ground * size * scale
    rx = width * size * scale / 2
    ry = height * size * scale / 2
    draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=int(255 * opacity))
    image = image.filter(ImageFilter.GaussianBlur(size * scale * 0.022)).resize((size, size), Image.LANCZOS)
    shadow = Image.new("RGBA", (size, size), (84, 58, 44, 0))
    shadow.putalpha(image)
    return shadow


# --- World items --------------------------------------------------------------
# Ground plane is y = GROUND, which lands on the item image's ground line.

GROUND = -0.80


def yarn_ball():
    c = (0.0, GROUND + 0.50, 0.0)

    def ball(p):
        d = sphere(p, c, 0.50)
        q = rotate(p, c, "z", 28)
        r = rotate(p, c, "x", 55)
        wrap_a = np.sin(q[1] * 46) * (q[0] - c[0] > -0.08)
        wrap_b = np.sin(r[0] * 46 + r[2] * 16) * (q[0] - c[0] <= -0.08)
        return d - 0.014 * (wrap_a + wrap_b)

    def color(p):
        q = rotate(p, c, "z", 28)
        groove = np.sin(q[1] * 46) * 0.5 + 0.5
        return mix_by(groove * 0.5, solid("#CE5F60")(p), solid("#F19B92")(p))

    points = [(0.34, GROUND + 0.12, 0.28), (0.50, GROUND + 0.05, 0.34), (0.66, GROUND + 0.035, 0.24),
              (0.80, GROUND + 0.04, 0.32), (0.92, GROUND + 0.035, 0.42)]
    return [Part(ball, color), Part(lambda p: chain(p, points, 0.032), solid("#EE938B"))], 1.02


def feather():
    tilt = -38

    def vane(p):
        q = rotate(p, (0, GROUND + 0.56, 0), "z", tilt)
        bend = q[0] + 0.22 * ((q[1] - (GROUND + 0.56)) ** 2) - 0.1
        along = (q[1] - (GROUND + 0.56))
        d = ellipsoid((bend, q[1], q[2] + 0.1 * bend), (0, GROUND + 0.62, 0), (0.205, 0.66, 0.045))
        return d - 0.008 * np.sin(along * 44 + np.abs(bend) * 18)

    def color(p):
        q = rotate(p, (0, GROUND + 0.56, 0), "z", tilt)
        along = np.clip((q[1] - (GROUND - 0.1)) / 1.3, 0, 1)
        ramp = mix_by(along, solid("#A6C796")(p), solid("#E8C98F")(p))
        return mix_by(np.exp(-((q[0] + 0.22 * ((q[1] - (GROUND + 0.56)) ** 2) - 0.1) ** 2) / 0.0006) * 0.7, ramp, solid("#F7EFD8")(p))

    def quill(p):
        q = rotate(p, (0, GROUND + 0.56, 0), "z", tilt)
        points = [(0.1 - 0.22 * ((y - 0.56) ** 2), GROUND + y, 0.03) for y in (-0.13, 0.06, 0.3, 0.6, 0.95, 1.2)]
        return chain(q, points, (0.022, 0.009))

    return [Part(vane, color), Part(quill, solid("#F8F1DF"))], 1.0


def toy_mouse():
    body_c = (0.05, GROUND + 0.27, 0)

    def body(p):
        d = ellipsoid(p, body_c, (0.46, 0.27, 0.30))
        snout = ellipsoid(p, (0.42, GROUND + 0.21, 0.02), (0.20, 0.15, 0.16))
        return smooth_min(d, snout, 0.10) - 0.0025 * bumps(p, 70)

    ear_far = lambda p: ellipsoid(p, (0.27, GROUND + 0.48, -0.13), (0.125, 0.13, 0.035))
    ear_near = lambda p: ellipsoid(p, (0.23, GROUND + 0.47, 0.17), (0.13, 0.135, 0.035))
    inner = lambda p: ellipsoid(p, (0.23, GROUND + 0.47, 0.195), (0.085, 0.09, 0.022))
    nose = lambda p: sphere(p, (0.61, GROUND + 0.21, 0.04), 0.038)
    eye = lambda p: sphere(p, (0.45, GROUND + 0.31, 0.135), 0.035)
    tail = [(-0.38, GROUND + 0.20, 0), (-0.58, GROUND + 0.14, 0.05), (-0.74, GROUND + 0.26, 0.10),
            (-0.84, GROUND + 0.42, 0.08), (-0.93, GROUND + 0.40, 0.04)]
    return [
        Part(body, solid("#B6A8A2")),
        Part(ear_far, solid("#B6A8A2")),
        Part(ear_near, solid("#B6A8A2")),
        Part(inner, solid("#F2A6A5")),
        Part(nose, solid("#EC8C94"), gloss=0.5),
        Part(eye, solid("#1B1311"), gloss=1.0, glow=0.1),
        Part(lambda p: chain(p, tail, (0.032, 0.018)), solid("#E9A7A3")),
    ], 1.02


def fish_toy():
    c = (0.08, GROUND + 0.42, 0)

    def body(p):
        return ellipsoid(p, c, (0.52, 0.30, 0.19)) - 0.003 * bumps(p, 90)

    def tail(p):
        a = ellipsoid(rotate(p, (-0.46, GROUND + 0.42, 0), "z", 34), (-0.68, GROUND + 0.42, 0), (0.25, 0.10, 0.05))
        b = ellipsoid(rotate(p, (-0.46, GROUND + 0.42, 0), "z", -34), (-0.68, GROUND + 0.42, 0), (0.25, 0.10, 0.05))
        return smooth_min(a, b, 0.05)

    fin = lambda p: ellipsoid(rotate(p, (0.02, GROUND + 0.70, 0), "z", 16), (0.0, GROUND + 0.72, 0), (0.22, 0.10, 0.045))
    side_fin = lambda p: ellipsoid(rotate(p, (0.12, GROUND + 0.30, 0.17), "z", -22), (0.10, GROUND + 0.28, 0.18), (0.12, 0.06, 0.03))
    eye_white = lambda p: sphere(p, (0.38, GROUND + 0.50, 0.125), 0.072)
    eye = lambda p: sphere(p, (0.40, GROUND + 0.505, 0.178), 0.036)

    def color(p):
        stripe = (np.sin((p[0] - 0.1) * 16) > 0.45).astype(float) * ((p[0]) < 0.25)
        belly = np.clip((c[1] - 0.04 - p[1]) * 6, 0, 1)
        base = mix_by(belly, solid("#5AA7C4")(p), solid("#CFE7E7")(p))
        return mix_by(stripe * 0.6, base, solid("#F4C486")(p))

    return [
        Part(body, color),
        Part(tail, solid("#F0B26F")),
        Part(fin, solid("#F0B26F")),
        Part(side_fin, solid("#F0B26F")),
        Part(eye_white, solid("#FBF7EE")),
        Part(eye, solid("#1B1311"), gloss=1.0, glow=0.1),
    ], 1.02


def rubber_ball():
    c = (0.0, GROUND + 0.46, 0.0)

    def seam(p):
        q = rotate(p, c, "z", -22)
        q = rotate(q, c, "x", 18)
        x, y, z = q[0] - c[0], q[1] - c[1], q[2] - c[2]
        return np.abs(y - 0.14 * np.sin(np.arctan2(z, x) * 2))

    def color(p):
        line = np.exp(-(seam(p) ** 2) / 0.0012)
        return mix_by(line, solid("#F1A23F")(p), solid("#FFF2DC")(p))

    return [Part(lambda p: sphere(p, c, 0.46), color, gloss=0.55)], 1.0


BOX_W, BOX_D, BOX_H = 0.86, 0.46, 0.60


def box_color_outer(p):
    grain = np.sin(p[1] * 240 + np.sin(p[0] * 9) * 3) * 0.018
    base = solid("#CFA177")(p) * (1 + grain[..., None])
    return base


def box_front_color(p):
    base = box_color_outer(p)
    tape = np.clip((0.115 - np.abs(p[0])) * 80, 0, 1)
    base = mix_by(tape * 0.8, base, solid("#E9D7B0")(p))
    # Paw print on the right of the tape.
    cx, cy = 0.50, GROUND + 0.30
    pad = (((p[0] - cx) / 0.085) ** 2 + ((p[1] - cy) / 0.07) ** 2) < 1
    toes = np.zeros_like(pad)
    for ox, oy in ((-0.075, 0.09), (-0.025, 0.125), (0.03, 0.125), (0.08, 0.09)):
        toes = toes | (((p[0] - cx - ox) ** 2 + (p[1] - cy - oy) ** 2) < 0.024 ** 2)
    return mix_by((pad | toes).astype(float) * 0.75, base, solid("#7E5A3E")(p))


def box_scene(part):
    top = GROUND + BOX_H
    z_front = BOX_D
    wall = 0.03

    def front(p):
        return round_box(p, (0, GROUND + BOX_H / 2, z_front), (BOX_W, BOX_H / 2, wall), 0.022)

    def back_wall(p):
        return round_box(p, (0, GROUND + BOX_H / 2, -BOX_D), (BOX_W, BOX_H / 2, wall), 0.022)

    def sides(p):
        left = round_box(p, (-BOX_W, GROUND + BOX_H / 2, 0), (wall, BOX_H / 2, BOX_D), 0.022)
        right = round_box(p, (BOX_W, GROUND + BOX_H / 2, 0), (wall, BOX_H / 2, BOX_D), 0.022)
        floor = round_box(p, (0, GROUND + 0.03, 0), (BOX_W, wall, BOX_D), 0.02)
        return np.minimum(np.minimum(left, right), floor)

    def front_flap(p):
        q = rotate(p, (0, top, z_front + 0.02), "x", 62)
        return round_box(q, (0, top, z_front + 0.10), (BOX_W - 0.02, 0.016, 0.085), 0.014)

    def back_flap(p):
        q = rotate(p, (0, top, -BOX_D), "x", 62)
        return round_box(q, (0, top, -BOX_D - 0.23), (BOX_W - 0.02, 0.016, 0.21), 0.014)

    def side_flaps(p):
        l = rotate(p, (-BOX_W, top, 0), "z", 40)
        r = rotate(p, (BOX_W, top, 0), "z", -40)
        a = round_box(l, (-BOX_W - 0.13, top, 0), (0.13, 0.016, BOX_D - 0.03), 0.014)
        b = round_box(r, (BOX_W + 0.13, top, 0), (0.13, 0.016, BOX_D - 0.03), 0.014)
        return np.minimum(a, b)

    inner_shade = lambda p: solid("#9C7350")(p)
    if part == "front":
        return [Part(front, box_front_color), Part(front_flap, solid("#C29469"))]
    return [
        Part(back_wall, inner_shade),
        Part(sides, solid("#BE9166")),
        Part(back_flap, solid("#B58A61")),
        Part(side_flaps, solid("#C89C72")),
    ]


def plate_parts():
    y = GROUND + 0.08
    return [
        Part(lambda p: cylinder_y(p, (0, y - 0.03, 0), 0.68, 0.05, 0.04), solid("#F4EEE2"), gloss=0.45),
        Part(lambda p: torus_y(p, (0, y + 0.02, 0), 0.68, 0.034), solid("#FBF7EE"), gloss=0.55),
    ], y + 0.03


def food_fish():
    plate, y = plate_parts()

    def body(p):
        return ellipsoid(rotate(p, (0, y + 0.1, 0), "y", -8), (0.10, y + 0.11, 0), (0.40, 0.125, 0.22)) - 0.004 * bumps(p, 70)

    tail = lambda p: ellipsoid(rotate(p, (-0.3, y + 0.1, 0), "z", 10), (-0.42, y + 0.11, 0), (0.17, 0.07, 0.17))
    eye = lambda p: sphere(p, (0.38, y + 0.17, 0.10), 0.028)

    def color(p):
        scale = (np.sin(p[0] * 44 + np.sin(p[2] * 34) * 1.2) * 0.5 + 0.5)
        return mix_by(scale * 0.35, solid("#EBA08E")(p), solid("#F7C5AE")(p))

    return plate + [Part(body, color, gloss=0.4), Part(tail, solid("#E4917E"), gloss=0.2),
                    Part(eye, solid("#1B1311"), gloss=1.0, glow=0.1)], 1.0


def food_milk():
    y = GROUND + 0.05

    def bowl(p):
        outer = ellipsoid(p, (0, y + 0.21, 0), (0.68, 0.26, 0.68))
        cut = p[1] - (y + 0.30)
        hollow = ellipsoid(p, (0, y + 0.30, 0), (0.60, 0.20, 0.60))
        return np.maximum(np.maximum(outer, cut), -hollow)

    milk = lambda p: cylinder_y(p, (0, y + 0.255, 0), 0.60, 0.015, 0.012)
    return [Part(bowl, solid("#E6A67E"), gloss=0.5),
            Part(lambda p: torus_y(p, (0, y + 0.30, 0), 0.645, 0.03), solid("#F3C19B"), gloss=0.6),
            Part(milk, solid("#FFFBF2"), gloss=0.65, glow=0.3)], 1.0


def food_chicken():
    plate, y = plate_parts()

    def meat(p):
        a = ellipsoid(rotate(p, (0, y + 0.15, 0), "z", 14), (-0.12, y + 0.17, 0), (0.33, 0.16, 0.18))
        return a - 0.004 * bumps(p, 34)

    bone = [(0.12, y + 0.19, 0.0), (0.44, y + 0.26, 0.0)]
    knob_a = lambda p: sphere(p, (0.47, y + 0.30, 0.0), 0.052)
    knob_b = lambda p: sphere(p, (0.49, y + 0.235, 0.0), 0.052)

    def color(p):
        crisp = bumps(p, 80) * 0.5 + 0.5
        return mix_by(crisp * 0.4, solid("#DE8E3F")(p), solid("#F0B566")(p))

    return plate + [Part(meat, color, gloss=0.5),
                    Part(lambda p: chain(p, bone, 0.038), solid("#FBF3E2")),
                    Part(knob_a, solid("#FBF3E2")), Part(knob_b, solid("#FBF3E2"))], 1.0


def food_cookie():
    plate, y = plate_parts()
    c = (0, y + 0.075, 0)
    chips = [(-0.16, 0.10), (0.14, 0.17), (0.02, -0.04), (0.22, -0.12), (-0.20, -0.14), (-0.03, 0.26), (0.30, 0.05)]

    def cookie(p):
        return cylinder_y(p, c, 0.38, 0.07, 0.055) - 0.009 * bumps(p, 45)

    def chip_field(p):
        d = None
        for x, z in chips:
            part = sphere(p, (x, y + 0.14, z), 0.042)
            d = part if d is None else np.minimum(d, part)
        return d

    return plate + [Part(cookie, solid("#D8A264")), Part(chip_field, solid("#4A2A1A"), gloss=0.5, glow=0.3)], 1.0


def food_empty():
    plate, _ = plate_parts()
    return plate, 1.0


ITEMS = {
    "yarnBall": (yarn_ball, 0.62),
    "feather": (feather, 0.72),
    "toyMouse": (toy_mouse, 0.78),
    "fishToy": (fish_toy, 0.80),
    "ball": (rubber_ball, 0.56),
    "food-fish": (food_fish, 0.90),
    "food-milk": (food_milk, 0.90),
    "food-chicken": (food_chicken, 0.90),
    "food-cookie": (food_cookie, 0.90),
    "food-empty": (food_empty, 0.90),
}

ITEM_SIZE = 320
BOX_SIZE = 680
SUPERSAMPLE = 2


def render_item(name, make, shadow_width, out):
    parts, view = make()
    linear = render(parts, ITEM_SIZE * SUPERSAMPLE, view=view)
    art = to_srgb_image(linear, ITEM_SIZE)
    canvas = contact_shadow(ITEM_SIZE, shadow_width)
    canvas.alpha_composite(art)
    canvas.save(out / f"{name}.png", optimize=True)
    return canvas


def render_box(out):
    size = BOX_SIZE
    view = 1.15
    # Ground at the same 0.9 line as other items.
    center = (0.0, GROUND + 0.8 * view)
    back = to_srgb_image(render(box_scene("back"), size, view=view, center=center), size)
    front = to_srgb_image(render(box_scene("front"), size, view=view, center=center), size)
    shadow = contact_shadow(size, 0.84)

    back_layer = shadow.copy()
    back_layer.alpha_composite(back)
    back_layer.save(out / "box-back.png", optimize=True)
    front.save(out / "box-front.png", optimize=True)

    whole = back_layer.copy()
    whole.alpha_composite(front)
    whole.save(out / "box.png", optimize=True)
    return whole


# --- Accessories --------------------------------------------------------------
# World coordinates are the 180pt canvas: a canvas fraction (u, v) from the top-left
# maps to x = 2u - 1, y = 1 - 2v. Rendered with no pitch so they stay registered with the art.


def C(u, v, z=0.0):
    return (2 * u - 1, 1 - 2 * v, z)


# Measured on the base frame: the head tilts about 7.5 degrees clockwise.
HEAD_TOP = C(0.505, 0.085)
EYE_L = C(0.3055, 0.4065)
EYE_R = C(0.6265, 0.4485)
CHIN = C(0.47, 0.675)
HEAD_TILT = -7.5


def party_hat():
    base = C(0.545, 0.170)
    height = 0.285
    radius_at_base = 0.185

    def cone(p):
        q = rotate(p, base, "z", -9)
        y = q[1] - base[1]
        radius = radius_at_base * (1 - np.clip(y / height, 0, 1))
        side = length(q[0] - base[0], (q[2] - base[2]) * 1.2) - radius
        return np.maximum(np.maximum(side, -y), y - height) * 0.7 - 0.008

    def color(p):
        q = rotate(p, base, "z", -9)
        band = np.sin((q[1] - base[1]) * 38 + (q[0] - base[0]) * 14) > 0.1
        return mix_by(band.astype(float), solid("#F2925A")(p), solid("#FCE6C2")(p))

    tip = rotate((np.array([base[0]]), np.array([base[1] + height + 0.012]), np.array([0.0])), base, "z", 9)
    pom = lambda p: sphere(p, (float(tip[0][0]), float(tip[1][0]), 0), 0.046) - 0.004 * bumps(p, 110)
    trim = lambda p: capsule(rotate(p, base, "z", -9), (base[0] - radius_at_base, base[1], 0.03), (base[0] + radius_at_base, base[1], 0.03), 0.024)
    return [Part(cone, color), Part(pom, solid("#FFF6E6")), Part(trim, solid("#FCE6C2"))]


def crown():
    base = C(0.53, 0.150)
    half_width = 0.205

    def body(p):
        q = rotate(p, base, "z", -8)
        x = (q[0] - base[0]) / half_width
        y = q[1] - base[1]
        # Three points along the top edge.
        top = 0.085 + 0.095 * np.abs(np.cos(x * 1.5 * math.pi)) ** 1.6
        flat = np.maximum(np.maximum(np.abs(x) - 1, 0) * half_width, np.maximum(y - top, -y))
        curved_z = q[2] - (0.09 * (1 - x * x))
        return length(flat, np.maximum(np.abs(curved_z) - 0.014, 0)) * 0.72 - 0.008

    def tip(u):
        h = 0.085 + 0.095 * abs(math.cos(u / half_width * 1.5 * math.pi)) ** 1.6
        return lambda p: sphere(rotate(p, base, "z", -8), (base[0] + u, base[1] + h + 0.006, 0.09 * (1 - (u / half_width) ** 2)), 0.021)

    def jewel(u, color):
        return Part(lambda p: sphere(rotate(p, base, "z", -8), (base[0] + u, base[1] + 0.045, 0.095 * (1 - (u / half_width) ** 2) + 0.014), 0.027),
                    solid(color), gloss=1.0, glow=0.5)

    band = lambda p: capsule(rotate(p, base, "z", -8), (base[0] - half_width, base[1], 0.02), (base[0] + half_width, base[1], 0.02), 0.022)
    return [
        Part(body, solid("#F2BE45"), gloss=0.9),
        Part(band, solid("#F8D674"), gloss=0.9),
        Part(tip(0.0), solid("#F8D674"), gloss=0.9),
        Part(tip(-half_width * 0.667), solid("#F8D674"), gloss=0.9),
        Part(tip(half_width * 0.667), solid("#F8D674"), gloss=0.9),
        jewel(0.0, "#D9423C"),
        jewel(-0.115, "#4F9FC4"),
        jewel(0.115, "#4F9FC4"),
    ]


def santa_hat():
    base = C(0.53, 0.185)
    points = [
        (base[0] - 0.015, base[1] + 0.05, 0),
        (base[0] + 0.03, base[1] + 0.16, 0),
        (base[0] + 0.14, base[1] + 0.225, 0),
        (base[0] + 0.25, base[1] + 0.18, 0.02),
        (base[0] + 0.315, base[1] + 0.085, 0.03),
    ]
    radii = (0.175, 0.125, 0.085, 0.052, 0.032)

    def cone(p):
        q = rotate(p, base, "z", -8)
        d = None
        for i in range(4):
            part = capsule(q, points[i], points[i + 1], (radii[i] + radii[i + 1]) / 2)
            d = part if d is None else smooth_min(d, part, 0.06)
        return d - 0.002 * bumps(p, 80)

    def brim(p):
        q = rotate(p, base, "z", -8)
        return capsule(q, (base[0] - 0.19, base[1], 0.05), (base[0] + 0.19, base[1], 0.05), 0.058) - 0.006 * bumps(p, 100)

    tip = rotate((np.array([points[-1][0]]), np.array([points[-1][1]]), np.array([0.03])), base, "z", 8)
    pom = lambda p: sphere(p, (float(tip[0][0]), float(tip[1][0]), 0.04), 0.062) - 0.006 * bumps(p, 100)
    return [Part(cone, solid("#D2453D")), Part(brim, solid("#FFF8EE")), Part(pom, solid("#FFF8EE"))]


def pumpkin():
    c = C(0.535, 0.125)

    def body(p):
        q = rotate(p, c, "z", -8)
        angle = np.arctan2(q[2] - c[2], q[0] - c[0])
        rib = np.abs(np.sin(angle * 4)) * 0.03
        return ellipsoid(q, c, (0.255, 0.165, 0.20)) - rib + 0.016

    stem_points = [(c[0] + 0.01, c[1] + 0.12, 0), (c[0] + 0.035, c[1] + 0.18, 0), (c[0] + 0.08, c[1] + 0.215, 0)]
    return [Part(body, solid("#EE8B39"), gloss=0.35),
            Part(lambda p: chain(rotate(p, c, "z", -8), stem_points, (0.032, 0.022)), solid("#7D9A5A"))]


def bow():
    c = C(0.255, 0.215)

    def loop(side):
        def sdf(p):
            q = rotate(p, c, "z", 24)
            outer = ellipsoid(q, (c[0] + side * 0.10, c[1], c[2]), (0.115, 0.078, 0.04))
            return outer - 0.003 * np.sin(np.abs(q[1] - c[1]) * 90)
        return sdf

    knot = lambda p: sphere(p, c, 0.04)
    return [Part(loop(-1), solid("#EF8AA0"), gloss=0.5), Part(loop(1), solid("#EF8AA0"), gloss=0.5),
            Part(knot, solid("#E0647F"), gloss=0.6)]


def glasses():
    tilt = HEAD_TILT
    center = ((EYE_L[0] + EYE_R[0]) / 2, (EYE_L[1] + EYE_R[1]) / 2, 0)
    half = math.hypot(EYE_R[0] - EYE_L[0], EYE_R[1] - EYE_L[1]) / 2

    def rim(side):
        def sdf(p):
            q = rotate(p, center, "z", -tilt)
            return torus_z(q, (center[0] + side * half, center[1], 0), 0.145, 0.018)
        return sdf

    def bridge(p):
        q = rotate(p, center, "z", -tilt)
        return chain(q, [(center[0] - half + 0.14, center[1] + 0.012, 0), (center[0], center[1] + 0.03, 0),
                         (center[0] + half - 0.14, center[1] + 0.012, 0)], 0.016)

    return [Part(rim(-1), solid("#3A2A24"), gloss=0.9, glow=0.25), Part(rim(1), solid("#3A2A24"), gloss=0.9, glow=0.25),
            Part(bridge, solid("#3A2A24"), gloss=0.9, glow=0.25)]


def collar():
    points = [C(u, v) for u, v in ((0.225, 0.645), (0.32, 0.705), (0.42, 0.735), (0.50, 0.742), (0.59, 0.726), (0.68, 0.684), (0.735, 0.635))]
    bell_c = C(0.475, 0.792, 0.03)
    slit = lambda p: capsule(p, (bell_c[0] - 0.026, bell_c[1] - 0.016, 0.092), (bell_c[0] + 0.026, bell_c[1] - 0.016, 0.092), 0.007)
    return [Part(lambda p: chain(p, points, 0.048), solid("#E8764E"), gloss=0.4),
            Part(lambda p: sphere(p, bell_c, 0.064), solid("#F2C14D"), gloss=1.0),
            Part(slit, solid("#6E4A1E"), glow=0.2)]


def scarf():
    points = [C(u, v) for u, v in ((0.20, 0.655), (0.30, 0.73), (0.40, 0.765), (0.50, 0.772), (0.60, 0.752), (0.70, 0.705), (0.76, 0.64))]
    drape_a = C(0.60, 0.775, 0.09)
    drape_b = C(0.635, 0.925, 0.10)

    def wrap(p):
        return chain(p, points, 0.098) - 0.006 * np.sin(p[0] * 60)

    def drape(p):
        d = capsule(p, drape_a, drape_b, 0.082)
        return np.maximum(d, np.abs(p[2] - drape_a[2]) - 0.04) - 0.006 * np.sin(p[1] * 60)

    def color(p):
        return mix_by((np.sin(p[0] * 26 + p[1] * 6) > 0.15).astype(float) * 0.85, solid("#9DBB8F")(p), solid("#F4EBD7")(p))

    def drape_color(p):
        return mix_by((np.sin(p[1] * 30) > 0.1).astype(float) * 0.85, solid("#9DBB8F")(p), solid("#F4EBD7")(p))

    return [Part(wrap, color), Part(drape, drape_color)]


def bandana():
    top = [C(u, v) for u, v in ((0.225, 0.645), (0.34, 0.715), (0.47, 0.742), (0.60, 0.72), (0.73, 0.64))]
    left = C(0.235, 0.665)
    right = C(0.725, 0.665)
    tip = C(0.46, 0.93)

    def cloth(p):
        # A rounded triangle hanging from the neck, gently bulging over the chest.
        def edge(a, b):
            nx, ny = b[1] - a[1], a[0] - b[0]
            n = math.hypot(nx, ny)
            return ((p[0] - a[0]) * nx + (p[1] - a[1]) * ny) / n

        inside = np.maximum(np.maximum(edge(left, tip), edge(tip, right)), edge(right, left))
        bulge = 0.05 * np.clip(-inside * 5, 0, 1)
        slab = np.abs(p[2] - bulge) - 0.018
        d = length(np.maximum(inside, 0), np.maximum(slab, 0)) + np.minimum(np.maximum(inside, slab), 0) - 0.014
        return d * 0.8

    def color(p):
        dots = ((np.sin(p[0] * 38) * np.sin(p[1] * 38)) > 0.7).astype(float)
        return mix_by(dots, solid("#E96D5B")(p), solid("#FBEBD8")(p))

    return [Part(cloth, color), Part(lambda p: chain(p, top, 0.03), solid("#D95D4B"))]


ACCESSORIES = {
    "collar": (collar, True),
    "bandana": (bandana, True),
    "scarf": (scarf, True),
    "bow": (bow, False),
    "hat": (party_hat, False),
    "crown": (crown, False),
    "pumpkin": (pumpkin, False),
    "santaHat": (santa_hat, False),
    "glasses": (glasses, False),
}

ACCESSORY_SIZE = 360


def head_mask(size):
    """Coverage of the cat's head on the canvas, so neck pieces tuck under the chin."""
    scale = 2
    side = size * scale
    # A painted-head ellipse measured on the base frame.
    cx, cy = 0.472 * side, 0.350 * side
    rx, ry = 0.430 * side, 0.3195 * side
    y, x = np.mgrid[0:side, 0:side].astype(np.float32)
    a = math.radians(5)
    dx, dy = x - cx, y - cy
    u = dx * math.cos(a) + dy * math.sin(a)
    v = -dx * math.sin(a) + dy * math.cos(a)
    inside = (u / rx) ** 2 + (v / ry) ** 2
    mask = np.clip((1.02 - inside) * 22, 0, 1)
    return Image.fromarray((mask * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)


def add_lenses(image):
    """Glass over the eyes: a faint tint and a diagonal glare, drawn after the frames."""
    size = image.width * 2
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    r = 0.0725 * size
    for u, v in ((0.3055, 0.4065), (0.6265, 0.4485)):
        draw.ellipse([u * size - r, v * size - r, u * size + r, v * size + r], fill=(235, 240, 245, 42))
        glare = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        glare_draw = ImageDraw.Draw(glare)
        glare_draw.line([(u - 0.042) * size, (v - 0.012) * size, (u - 0.008) * size, (v - 0.05) * size],
                        fill=(255, 255, 255, 120), width=int(0.012 * size))
        overlay.alpha_composite(glare)
    overlay = overlay.resize((image.width, image.height), Image.LANCZOS)
    result = overlay.copy()
    result.alpha_composite(image)
    return result


def render_accessory(name, make, tuck_under_head, out):
    linear = render(make(), ACCESSORY_SIZE * SUPERSAMPLE, pitch=0.0)
    image = to_srgb_image(linear, ACCESSORY_SIZE)
    if name == "glasses":
        image = add_lenses(image)
    if tuck_under_head:
        array = np.array(image)
        cover = np.array(head_mask(ACCESSORY_SIZE)).astype(np.float32) / 255
        array[..., 3] = (array[..., 3] * (1 - cover)).astype(np.uint8)
        image = Image.fromarray(array)
    image.save(out / f"{name}.png", optimize=True)
    return image


# --- Icons ---------------------------------------------------------------------

ICON_SIZE = 64


def icon_paw():
    pads = [(-0.46, 0.20), (-0.17, 0.48), (0.17, 0.48), (0.46, 0.20)]
    parts = [Part(lambda p: ellipsoid(p, (0, -0.28, 0), (0.46, 0.40, 0.22)), solid("#F7C3C0"), gloss=0.2)]
    for x, y in pads:
        parts.append(Part(lambda p, x=x, y=y: ellipsoid(p, (x, y, 0), (0.185, 0.235, 0.14)), solid("#F7C3C0"), gloss=0.2))
    return parts


def icon_heart():
    def heart(p):
        mirrored = (np.abs(p[0]), p[1], p[2] * 1.5)
        lobe = sphere(mirrored, (0.38, 0.30, 0), 0.40)
        taper = chain(mirrored, [(0.36, 0.26, 0), (0.17, -0.20, 0), (0.0, -0.66, 0)], (0.36, 0.07))
        return smooth_min(lobe, taper, 0.08) * 0.8

    return [Part(heart, solid("#EE7186"), gloss=0.7)]


def icon_palette():
    def board(p):
        plate = ellipsoid(p, (0, 0, 0), (0.86, 0.72, 0.13))
        return np.maximum(plate, -sphere(p, (0.38, -0.30, 0), 0.15))

    dabs = [(-0.46, 0.14, "#E96D5B"), (-0.16, 0.40, "#F2C14D"), (0.22, 0.38, "#7FB08A"), (0.48, 0.08, "#5AA7C4")]
    parts = [Part(board, solid("#E2B27E"))]
    for x, y, color in dabs:
        parts.append(Part(lambda p, x=x, y=y: ellipsoid(p, (x, y, 0.10), (0.15, 0.15, 0.07)), solid(color), gloss=0.5))
    return parts


def icon_moon():
    return [Part(lambda p: np.maximum(sphere(p, (0, 0, 0), 0.78), -sphere(p, (0.42, 0.24, 0.1), 0.66)), solid("#F2D27A"), gloss=0.3)]


def icon_speaker():
    cone = lambda p: round_box(p, (-0.36, 0, 0), (0.22, 0.26, 0.2), 0.08)
    horn = lambda p: ellipsoid(p, (-0.06, 0, 0), (0.28, 0.56, 0.26))
    wave = lambda p: np.maximum(torus_z(p, (0.12, 0, 0), 0.54, 0.065), -p[0] + 0.36)
    return [Part(cone, solid("#E2A36D")), Part(horn, solid("#E2A36D")), Part(wave, solid("#F1BE8D"))]


GLYPHS = {
    "paw": icon_paw,
    "heart": icon_heart,
    "palette": icon_palette,
    "moon": icon_moon,
    "speaker": icon_speaker,
}


def trimmed_icon(image, inset=2):
    """Crops an image to its opaque content and fits it on an icon canvas."""
    alpha = np.array(image)[..., 3]
    ys, xs = np.where(alpha > 90)
    if xs.size == 0:
        return Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    cropped = image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    cropped.thumbnail((ICON_SIZE - inset * 2, ICON_SIZE - inset * 2), Image.LANCZOS)
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(cropped, ((ICON_SIZE - cropped.width) // 2, (ICON_SIZE - cropped.height) // 2))
    return canvas


def head_crop(path, box):
    """Crops the face from a pose, as fractions of the source image."""
    image = Image.open(path).convert("RGBA")
    w, h = image.size
    return image.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))


def base_head_mask(side):
    """The head and ears of the base art, as a mask, with the body removed."""
    art = Image.open(ROOT / "Cookie/Assets/Assets.xcassets/CookieArt.imageset/cookie.png").convert("RGBA")
    w, h = art.size
    head = art.crop((0, 0, w, int(h * 0.68)))
    head = head.resize((side, int(side * head.height / head.width)), Image.LANCZOS)
    canvas = Image.new("L", (side, side), 0)
    canvas.paste(head.split()[3], (0, (side - head.height) // 2))
    return canvas


def make_menu_bar_icon(side):
    """A template glyph: Cookie's head with eyes and mouth punched out."""
    scale = 8
    big = side * scale
    mask = base_head_mask(big).point(lambda v: 255 if v > 128 else 0)

    # The art is 0.907 of its height wide, cropped at 0.68, so features map by width.
    top = (big - big * (0.68 * 1158 / 1050)) / 2
    def point(u, v):
        return (u * big, top + v * big * 1158 / 1050)

    draw = ImageDraw.Draw(mask)
    for u, v in ((0.283, 0.395), (0.646, 0.438)):
        cx, cy = point(u, v)
        r = 0.066 * big
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=0)
    cx, cy = point(0.45, 0.495)
    w, h = 0.058 * big, 0.04 * big
    width = int(0.036 * big)
    draw.arc([cx - w * 2, cy - h, cx, cy + h], 10, 170, fill=0, width=width)
    draw.arc([cx, cy - h, cx + w * 2, cy + h], 10, 170, fill=0, width=width)

    mask = mask.filter(ImageFilter.GaussianBlur(scale * 0.25)).resize((side, side), Image.LANCZOS)
    glyph = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    glyph.putalpha(mask)
    return glyph


def make_icons():
    icons = OUT / "Icons"
    icons.mkdir(parents=True, exist_ok=True)
    items = OUT / "Items"
    for name in list(ITEMS) + ["box"]:
        if name == "food-empty":
            continue
        image = Image.open(items / f"{name}.png").convert("RGBA")
        trimmed_icon(image).save(icons / f"item-{name}.png", optimize=True)

    assets = ROOT / "Cookie/Assets/Assets.xcassets"
    faces = {
        "wave": ("cookie-wave", (0.08, 0.0, 0.92, 0.68)),
        "happy": ("cookie-eyes-close", (0.0, 0.0, 1.0, 0.66)),
        "love": ("cookie-shy", (0.08, 0.0, 0.98, 0.62)),
        "sleepy": ("cookie-sleep", (0.0, 0.32, 0.82, 1.0)),
        "playful": ("cookie-mischievous", (0.08, 0.0, 0.98, 0.62)),
    }
    for name, (asset, box) in faces.items():
        trimmed_icon(head_crop(assets / f"{asset}.imageset/{asset}.png", box)).save(icons / f"emote-{name}.png", optimize=True)

    for name, make in GLYPHS.items():
        linear = render(make(), ICON_SIZE * 4, pitch=0.0, view=1.02)
        trimmed_icon(to_srgb_image(linear, ICON_SIZE * 2)).save(icons / f"glyph-{name}.png", optimize=True)

    # Menu bar template icon, in the Mac asset catalog.
    menu_bar = assets / "CookieMenuBar.imageset"
    menu_bar.mkdir(exist_ok=True)
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        make_menu_bar_icon(18 * scale).save(menu_bar / f"menubar{suffix}.png", optimize=True)
    (menu_bar / "Contents.json").write_text("""{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "menubar@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
""")

    # Windows tray icon: her face, in color, at every size the shell asks for.
    head = head_crop(assets / "CookieArt.imageset/cookie.png", (0, 0, 1, 0.67))
    square = Image.new("RGBA", (head.width, head.width), (0, 0, 0, 0))
    square.alpha_composite(head, (0, (head.width - head.height) // 2))
    square.save(
        ROOT / "Cookie.Windows/Resources/CookieTray.ico",
        sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64)],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="items to render (default: all)")
    parser.add_argument("--preview", type=Path, help="directory for review images")
    args = parser.parse_args()

    items_dir = OUT / "Items"
    accessories_dir = OUT / "Accessories"
    items_dir.mkdir(parents=True, exist_ok=True)
    accessories_dir.mkdir(parents=True, exist_ok=True)
    if args.preview:
        args.preview.mkdir(parents=True, exist_ok=True)

    wanted = set(args.names)
    results = {}
    for name, (make, width) in ITEMS.items():
        if not wanted or name in wanted:
            results[name] = render_item(name, make, width, items_dir)
            print("item", name)
    if not wanted or "box" in wanted:
        results["box"] = render_box(items_dir)
        print("item box")
    for name, (make, tuck) in ACCESSORIES.items():
        if not wanted or name in wanted:
            results[name] = render_accessory(name, make, tuck, accessories_dir)
            print("accessory", name)

    if not wanted:
        make_icons()
        print("icons")

    if args.preview:
        base = Image.open(OUT / "Idle/idle.png").crop((0, 0, 360, 360)).convert("RGBA")
        for name, image in results.items():
            backdrop = Image.new("RGBA", (360, 360), (70, 80, 100, 255))
            if name in ACCESSORIES:
                backdrop.alpha_composite(base)
                backdrop.alpha_composite(image)
            else:
                backdrop.alpha_composite(image.resize((360, 360), Image.LANCZOS))
            backdrop.convert("RGB").save(args.preview / f"{name}.png")


if __name__ == "__main__":
    main()
