#!/usr/bin/env python3
"""Layered 2.5D scenes with exact thin-lens truth (OTH-03, #138).

Each scene is a stack of fronto-parallel RGBA planes at known distances: a far background (a CC0
photo from the MSK-25 set, or procedural), sometimes a mid layer, a subject with soft alpha (hair
strands, fur, filaments drawn at 4x supersampling for exact coverage) and sometimes a near
foreground that partly occludes it. Small bright point lights sit in the background.

The truth is ray traced through a thin lens. For a pixel p and a lens point a (unit aperture
shape), the ray meets the plane at depth z where the pinhole image of that plane is at
p + a * c(z) / 2, c being the signed circle of confusion in pixels. Each ray samples every plane
there (bilinear on premultiplied RGBA), composites front to back, and the pixel is the mean
over an equal-weight lattice of lens points spaced at most 1 px on the most blurred plane. The
pinhole image (a = 0) is the renderer's input. All values are linear Rec.709.

    build/research-venv/bin/python research/prototypes/lens_blur/layered_truth.py [scene...] [--2x]
"""

import math
import sys
import time

import numpy as np
import torch
from PIL import Image, ImageDraw
from scipy import ndimage

import common
from common import DATA, aperture_lattice, camera, coc_px, variants, write_exr, write_json

WIDTH, HEIGHT = 1024, 683
SUPER = 4
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
BATCH = 24
# Textures and photos cover the frame plus PAD px (1x) on each side, so every scale sees the same scene.
PAD = 320


# MARK: - Scenes

SCENES = {
    # name: focal mm, background (photo or procedural) and depth, mid, subject, foreground, lights.
    "portrait-leafy": dict(focal=85, bg=("sky-leafy-trees-02.jpg", 30), subject=("portrait", 2.5),
                           lights=("bright", 14)),
    "portrait-night": dict(focal=85, bg=("sky-night-01.jpg", 60), subject=("portrait-backlit", 2.0),
                           lights=("bright", 40)),
    "portrait-fg-leaves": dict(focal=85, bg=("sky-haze-fog-02.jpg", 40), mid=("bush", 8),
                               subject=("portrait", 2.5), fg=("branch", 1.1), lights=("bright", 10)),
    "dandelion-sea": dict(focal=85, bg=("sky-sea-01.jpg", 50), subject=("dandelion", 1.5),
                          fg=("grass", 0.8), lights=("glints", 30)),
    "plant-sunset": dict(focal=50, bg=("sky-sunset-02.jpg", 80), mid=("bush", 6), subject=("plant", 1.2),
                         lights=("bright", 12)),
    "cat-overcast": dict(focal=85, bg=("sky-overcast-01.jpg", 30), mid=("fence", 6), subject=("cat", 3.0),
                         fg=("post", 1.5), lights=("dim", 12)),
    "portrait-city": dict(focal=50, bg=("sky-glass-01.jpg", 40), mid=("string-lights", 10),
                          subject=("portrait", 2.0), lights=("bright", 8)),
    "plant-snow": dict(focal=35, bg=("sky-snow-mountains-01.jpg", 200), mid=("bare-tree", 15),
                       subject=("plant", 1.0)),
    "dandelion-night": dict(focal=85, bg=("sky-night-02.jpg", 40), subject=("dandelion-backlit", 1.8),
                            lights=("bright", 50)),
    "cat-leafy": dict(focal=135, bg=("sky-leafy-trees-05.jpg", 25), subject=("cat", 5.0),
                      fg=("branch", 3.0), lights=("dim", 16)),
    "portrait-horizon": dict(focal=35, bg=("sky-bright-horizon-02.jpg", 100), mid=("bush", 5),
                             subject=("portrait", 1.5), fg=("branch", 0.7), lights=("bright", 10)),
    "portrait-stripes": dict(focal=50, bg=("procedural", 20), mid=("panel", 5), subject=("portrait-stripes", 2.0),
                             lights=("grid", 24)),
}
DOUBLE = ["portrait-leafy", "portrait-fg-leaves", "cat-overcast"]


class Painter:
    """Coverage drawn at SUPER x over the reference canvas (frame plus margin), in frame pixels."""

    def __init__(self, width, height, margin, scale):
        self.margin, self.scale = margin, scale
        self.size = (width * SUPER, height * SUPER)
        self.image = Image.new("L", self.size, 0)
        self.draw = ImageDraw.Draw(self.image)

    def xy(self, p):
        return ((p[0] * self.scale + self.margin) * SUPER, (p[1] * self.scale + self.margin) * SUPER)

    def line(self, a, b, width, fill=255):
        w = width * self.scale * SUPER
        if w < 1:
            fill, w = int(round(fill * w)), 1
        w = int(round(w))
        pa, pb = self.xy(a), self.xy(b)
        self.draw.line([pa, pb], fill=fill, width=w)
        if w > 2:
            r = w / 2
            for p in (pa, pb):
                self.draw.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=fill)

    def strand(self, points, w0, w1, fill=255):
        n = len(points) - 1
        for i, (a, b) in enumerate(zip(points, points[1:])):
            self.line(a, b, w0 + (w1 - w0) * i / max(n, 1), fill)

    def ellipse(self, centre, rx, ry, fill=255):
        x, y = self.xy(centre)
        self.draw.ellipse((x - rx * self.scale * SUPER, y - ry * self.scale * SUPER,
                           x + rx * self.scale * SUPER, y + ry * self.scale * SUPER), fill=fill)

    def polygon(self, points, fill=255):
        self.draw.polygon([self.xy(p) for p in points], fill=fill)

    def coverage(self):
        a = np.asarray(self.image, dtype=np.float32) / 255
        h, w = a.shape[0] // SUPER, a.shape[1] // SUPER
        return a.reshape(h, SUPER, w, SUPER).mean(axis=(1, 3))


class Canvas:
    """Reference geometry: the frame plus a margin, in frame pixel coordinates at the 1x scale."""

    def __init__(self, scale, margin):
        self.scale = scale
        self.margin = margin
        self.width = WIDTH * scale + 2 * margin
        self.height = HEIGHT * scale + 2 * margin

    def painter(self):
        return Painter(self.width, self.height, self.margin, self.scale)

    def grid(self):
        """Frame coordinates (1x pixels) of each reference texel centre."""
        x = (np.arange(self.width) + 0.5 - self.margin) / self.scale
        y = (np.arange(self.height) + 0.5 - self.margin) / self.scale
        return np.meshgrid(x.astype(np.float32), y.astype(np.float32))

    def noise(self, rng, sigma, coarse=4):
        """Unit-variance smooth noise of scale `sigma` (1x px), the same field at every scale."""
        h, w = (HEIGHT + 2 * PAD) // coarse, (WIDTH + 2 * PAD) // coarse
        n = ndimage.gaussian_filter(rng.standard_normal((h, w)), sigma / coarse)
        n = (n - n.mean()) / (n.std() + 1e-9)
        x, y = self.grid()
        return ndimage.map_coordinates(n, [(y + PAD) / coarse - 0.5, (x + PAD) / coarse - 0.5], order=1,
                                       mode="nearest").astype(np.float32)


def photo(canvas, name, gain=0.8):
    image = Image.open(common.PHOTOS / name)
    target = ((WIDTH + 2 * PAD) * canvas.scale, (HEIGHT + 2 * PAD) * canvas.scale)
    image.draft("RGB", (target[0] * 2, target[1] * 2))
    image = image.convert("RGB")
    aspect = target[0] / target[1]
    w, h = image.size
    if w / h > aspect:
        cw = int(h * aspect)
        image = image.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h))
    else:
        ch = int(w / aspect)
        image = image.crop((0, (h - ch) // 2, w, (h - ch) // 2 + ch))
    image = image.resize(target, Image.LANCZOS)
    offset = PAD * canvas.scale - canvas.margin
    image = image.crop((offset, offset, offset + canvas.width, offset + canvas.height))
    return common.srgb_to_linear(np.asarray(image, dtype=np.float32) / 255) * gain


def procedural_background(canvas, rng):
    x, y = canvas.grid()
    stripes = 0.5 + 0.5 * np.sign(np.sin(x / 9.0 * math.pi))
    checker = ((np.floor(x / 48) + np.floor(y / 48)) % 2)
    gradient = y / HEIGHT
    n = canvas.noise(rng, 6)
    r = 0.08 + 0.35 * stripes * (y < HEIGHT * 0.4) + 0.25 * checker * (y >= HEIGHT * 0.4) * (1 - gradient)
    g = 0.10 + 0.25 * gradient + 0.05 * n
    b = 0.12 + 0.30 * (1 - gradient) * (0.5 + 0.5 * np.sin(x / 61.0))
    return np.clip(np.stack([r, g, b], -1), 0.005, 0.9).astype(np.float32)


# MARK: - Subjects (coverage plus straight colour, both on the reference canvas)

def head_and_shoulders(canvas, rng, cx, cy, size):
    body = canvas.painter()
    rx, ry = 0.62 * size, 0.8 * size
    body.ellipse((cx, cy), rx, ry)
    body.polygon([(cx - 0.3 * size, cy + 0.5 * ry), (cx + 0.3 * size, cy + 0.5 * ry),
                  (cx + 0.32 * size, cy + 1.25 * ry), (cx - 0.32 * size, cy + 1.25 * ry)])
    shoulders = canvas.painter()
    shoulders.polygon([(cx - 0.35 * size, cy + 1.15 * ry), (cx + 0.35 * size, cy + 1.15 * ry),
                       (cx + 1.6 * size, cy + 1.7 * ry), (cx + 1.9 * size, HEIGHT + 200),
                       (cx - 1.9 * size, HEIGHT + 200), (cx - 1.6 * size, cy + 1.7 * ry)])
    shoulders.ellipse((cx - 1.45 * size, cy + 2.0 * ry), 0.5 * size, 0.45 * ry)
    shoulders.ellipse((cx + 1.45 * size, cy + 2.0 * ry), 0.5 * size, 0.45 * ry)
    return body.coverage(), shoulders.coverage(), (rx, ry)


def hair(canvas, rng, cx, cy, rx, ry, count, length, backlit):
    cap = canvas.painter()
    cap.ellipse((cx, cy - 0.3 * ry), rx * 1.06, ry * 0.75)
    cap.polygon([(cx - rx * 1.06, cy - 0.3 * ry), (cx + rx * 1.06, cy - 0.3 * ry), (cx + rx * 1.1, cy + 1.2 * ry),
                 (cx + rx * 0.82, cy + 1.25 * ry), (cx + rx * 0.8, cy - 0.3 * ry), (cx - rx * 0.8, cy - 0.3 * ry),
                 (cx - rx * 0.82, cy + 1.25 * ry), (cx - rx * 1.1, cy + 1.2 * ry)])
    strands = canvas.painter()
    for i in range(count):
        t = rng.uniform(-0.95, 0.95) * math.pi
        root = (cx + rx * 1.02 * math.sin(t), cy - 0.12 * ry - ry * 0.95 * math.cos(t))
        if root[1] > cy + 1.1 * ry:
            continue
        angle = math.atan2(-math.cos(t) * 0.6 + 0.6 * (abs(t) > 1.2), math.sin(t)) + rng.normal(0, 0.35)
        wisp = rng.random() < 0.08
        steps = int(rng.uniform(0.3, 1.0) * length / 3) + 2
        if wisp:
            steps *= 2
        points, p, curl = [root], root, rng.normal(0, 0.05)
        for _ in range(steps):
            angle += curl + rng.normal(0, 0.08)
            # Hair falls under gravity: bend toward +y.
            angle += 0.02 * math.cos(angle)
            p = (p[0] + 3 * math.cos(angle), p[1] + 3 * math.sin(angle))
            points.append(p)
        w0 = rng.uniform(0.15, 0.5) if wisp else rng.uniform(0.3, 2.2)
        strands.strand(points, w0, w0 * 0.3)
    cov_cap, cov_strands = cap.coverage(), strands.coverage()
    alpha = 1 - (1 - cov_cap) * (1 - cov_strands)
    x, y = canvas.grid()
    distance = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    rim = np.clip(distance - 1.0, 0, 1)
    return alpha, rim * (3.0 if backlit else 0.4)


def portrait(canvas, rng, kind):
    cx, cy, size = WIDTH * rng.uniform(0.42, 0.58), HEIGHT * 0.36, HEIGHT * 0.17
    face, shoulders, (rx, ry) = head_and_shoulders(canvas, rng, cx, cy, size)
    backlit = kind == "portrait-backlit"
    hair_alpha, rim = hair(canvas, rng, cx, cy, rx, ry, 1400, size * 1.3, backlit)
    x, y = canvas.grid()
    n = canvas.noise(rng, 3)
    shade = np.clip(1.0 - 0.5 * (x - cx) / (2 * rx), 0.4, 1.4)
    skin = np.stack([0.42 + 0 * x, 0.26 + 0 * x, 0.18 + 0 * x], -1) * (shade * (1 + 0.05 * n))[..., None]
    if kind == "portrait-stripes":
        stripes = (np.sin((x + 0.4 * y) / 3.1) > 0).astype(np.float32)
        shirt = np.stack([0.02 + 0.6 * stripes, 0.03 + 0.05 * stripes, 0.05 + 0.1 * stripes], -1)
    else:
        tone = rng.uniform(0.05, 0.35, 3)
        shirt = tone[None, None, :] * (0.8 + 0.2 * canvas.noise(rng, 2)[..., None]) * shade[..., None]
    base = rng.choice([np.array([0.05, 0.03, 0.02]), np.array([0.35, 0.22, 0.10]), np.array([0.12, 0.06, 0.03])])
    hair_colour = base[None, None, :] * (1 + 0.35 * canvas.noise(rng, 1.5))[..., None] + rim[..., None] * np.array([1.0, 0.85, 0.6])
    a_body = 1 - (1 - face) * (1 - shoulders)
    body = (face[..., None] * skin + (1 - face[..., None]) * shoulders[..., None] * shirt)
    body = body / np.maximum(a_body, 1e-6)[..., None]
    return over(hair_alpha, hair_colour, a_body, body)


def over(a1, c1, a2, c2):
    """Straight-colour `1` over `2`."""
    alpha = a1 + (1 - a1) * a2
    colour = (a1[..., None] * c1 + ((1 - a1) * a2)[..., None] * c2) / np.maximum(alpha, 1e-6)[..., None]
    return alpha, colour


def fur(canvas, rng, alpha, density, length, width):
    """Short strands outward from the edge of a solid shape."""
    smooth = ndimage.gaussian_filter(alpha, 3 * canvas.scale)
    gy, gx = np.gradient(smooth)
    edge = (alpha > 0.4) & (alpha < 0.6)
    ys, xs = np.nonzero(edge)
    pick = rng.random(len(xs)) < density / canvas.scale
    strands = canvas.painter()
    for x0, y0 in zip(xs[pick], ys[pick]):
        nx, ny = -gx[y0, x0], -gy[y0, x0]
        norm = math.hypot(nx, ny) + 1e-9
        angle = math.atan2(ny / norm, nx / norm) + rng.normal(0, 0.4)
        p = ((x0 + 0.5 - canvas.margin) / canvas.scale, (y0 + 0.5 - canvas.margin) / canvas.scale)
        # Roots start inside the solid edge.
        p = (p[0] - 2 * math.cos(angle), p[1] - 2 * math.sin(angle))
        points = [p]
        for _ in range(int(rng.uniform(0.4, 1.0) * length / 2) + 1):
            angle += rng.normal(0, 0.12)
            p = (p[0] + 2 * math.cos(angle), p[1] + 2 * math.sin(angle))
            points.append(p)
        w = rng.uniform(*width)
        strands.strand(points, w, w * 0.3)
    return strands.coverage()


def cat(canvas, rng):
    cx, cy = WIDTH * 0.5, HEIGHT * 0.58
    body = canvas.painter()
    body.ellipse((cx, cy + 40), 170, 120)
    body.ellipse((cx - 150, cy - 90), 85, 75)
    body.polygon([(cx - 215, cy - 125), (cx - 200, cy - 215), (cx - 150, cy - 150)])
    body.polygon([(cx - 120, cy - 150), (cx - 85, cy - 220), (cx - 75, cy - 125)])
    for k in range(40):
        t = k / 39
        body.ellipse((cx + 150 + 110 * t, cy + 60 - 230 * t ** 1.5), 18 - 6 * t, 18 - 6 * t)
    solid = body.coverage()
    hairs = fur(canvas, np.random.default_rng(rng.integers(2**31)), solid, 0.5, 14, (0.3, 1.4))
    whiskers = canvas.painter()
    for k in range(6):
        angle = math.pi + rng.uniform(-0.4, 0.4)
        start = (cx - 190, cy - 70 + rng.uniform(-8, 8))
        whiskers.strand([start, (start[0] + 70 * math.cos(angle), start[1] + 70 * math.sin(angle) + 10)], 0.6, 0.2)
    alpha = 1 - (1 - solid) * (1 - hairs) * (1 - whiskers.coverage())
    n = canvas.noise(rng, 2)
    x, y = canvas.grid()
    tabby = 0.5 + 0.5 * np.sin((x * 0.3 + y) / 9 + 2 * n)
    colour = np.stack([0.30 * tabby + 0.05, 0.18 * tabby + 0.04, 0.08 * tabby + 0.03], -1)
    colour = colour * (1 + 0.15 * n)[..., None]
    colour = colour + whiskers.coverage()[..., None] * 0.6
    return alpha, colour.astype(np.float32)


def dandelion(canvas, rng, backlit):
    cx, cy, radius = WIDTH * 0.48, HEIGHT * 0.38, HEIGHT * 0.2
    solid = canvas.painter()
    solid.strand([(cx, cy), (cx + 10, cy + 0.6 * HEIGHT), (cx + 30, HEIGHT + 100)], 6, 8)
    solid.ellipse((cx, cy), 14, 14)
    filaments = canvas.painter()
    tips = canvas.painter()
    for _ in range(700):
        theta = rng.uniform(0, 2 * math.pi)
        r = radius * rng.uniform(0.75, 1.0) * (0.75 + 0.25 * abs(math.sin(theta)))
        end = (cx + r * math.cos(theta), cy + r * math.sin(theta))
        filaments.line((cx, cy), end, rng.uniform(0.2, 0.45))
        for _ in range(9):
            phi = theta + rng.normal(0, 0.5)
            tips.line(end, (end[0] + 14 * math.cos(phi), end[1] + 14 * math.sin(phi)), 0.18)
    a_solid, a_fil, a_tip = solid.coverage(), filaments.coverage(), tips.coverage()
    alpha = 1 - (1 - a_solid) * (1 - a_fil) * (1 - a_tip)
    glow = 2.2 if backlit else 0.85
    colour = np.empty(alpha.shape + (3,), np.float32)
    colour[:] = np.array([0.75, 0.75, 0.70]) * glow
    stem = (a_solid / np.maximum(alpha, 1e-6))[..., None]
    colour = stem * np.array([0.10, 0.16, 0.05]) + (1 - stem) * colour
    return alpha, colour


def plant(canvas, rng):
    p = canvas.painter()
    hairs = canvas.painter()
    cx = WIDTH * 0.5
    for stem in range(5):
        x0 = cx + rng.normal(0, 60)
        top = (x0 + rng.normal(0, 90), HEIGHT * rng.uniform(0.12, 0.4))
        points = [(x0 + (top[0] - x0) * t + 25 * math.sin(t * 3 + stem), HEIGHT + 40 + (top[1] - HEIGHT - 40) * t)
                  for t in np.linspace(0, 1, 40)]
        p.strand(points, 6, 2.5)
        for a, b in zip(points[::2], points[1::2]):
            for side in (-1, 1):
                if rng.random() < 0.7:
                    hairs.line(a, (a[0] + side * rng.uniform(4, 10), a[1] - rng.uniform(2, 8)), rng.uniform(0.2, 0.5))
        for t in rng.uniform(0.3, 0.95, 6):
            i = int(t * 39)
            base = points[i]
            angle = rng.uniform(-math.pi, 0)
            length, half = rng.uniform(50, 110), rng.uniform(10, 22)
            tip = (base[0] + length * math.cos(angle), base[1] + length * math.sin(angle))
            normal = (-math.sin(angle) * half, math.cos(angle) * half)
            mid = ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2)
            p.polygon([base, (mid[0] + normal[0], mid[1] + normal[1]), tip, (mid[0] - normal[0], mid[1] - normal[1])])
        for _ in range(30):
            angle = -math.pi / 2 + rng.normal(0, 0.6)
            hairs.strand([top, (top[0] + 40 * math.cos(angle), top[1] + 40 * math.sin(angle))], 0.4, 0.15)
    solid, fine = p.coverage(), hairs.coverage()
    alpha = 1 - (1 - solid) * (1 - fine)
    n = canvas.noise(rng, 2)
    colour = np.stack([0.06 + 0.02 * n, 0.20 + 0.05 * n, 0.04 + 0 * n], -1)
    fine_share = (fine * (1 - solid) / np.maximum(alpha, 1e-6))[..., None]
    colour = (1 - fine_share) * colour + fine_share * np.array([0.55, 0.50, 0.35])
    return alpha, np.clip(colour, 0.001, None).astype(np.float32)


def subject(canvas, rng, kind):
    if kind.startswith("portrait"):
        return portrait(canvas, rng, kind)
    if kind == "cat":
        return cat(canvas, rng)
    if kind.startswith("dandelion"):
        return dandelion(canvas, rng, kind.endswith("backlit"))
    return plant(canvas, rng)


# MARK: - Mid layers and foregrounds

def textured(canvas, rng, base, contrast=0.3):
    n = canvas.noise(rng, 1.5)
    return (np.asarray(base)[None, None, :] * np.exp(contrast * n)[..., None]).astype(np.float32)


def mid_layer(canvas, rng, kind, lights):
    p = canvas.painter()
    if kind == "bush":
        for _ in range(60):
            x = rng.uniform(-50, WIDTH + 50)
            p.ellipse((x, HEIGHT * rng.uniform(0.7, 1.05)), rng.uniform(30, 90), rng.uniform(25, 70))
        fine = canvas.painter()
        for _ in range(500):
            x, y = rng.uniform(-50, WIDTH + 50), HEIGHT * rng.uniform(0.62, 0.8)
            angle = -math.pi / 2 + rng.normal(0, 0.7)
            fine.line((x, y + 20), (x + 25 * math.cos(angle), y + 25 * math.sin(angle)), rng.uniform(0.4, 2))
        alpha = 1 - (1 - p.coverage()) * (1 - fine.coverage())
        return alpha, textured(canvas, rng, [0.04, 0.09, 0.03], 0.5)
    if kind == "fence":
        for y in (0.55, 0.75):
            p.polygon([(-50, HEIGHT * y), (WIDTH + 50, HEIGHT * y), (WIDTH + 50, HEIGHT * y + 12), (-50, HEIGHT * y + 12)])
        for x in np.arange(-40, WIDTH + 60, 55):
            p.polygon([(x, HEIGHT * 0.45), (x + 8, HEIGHT * 0.42), (x + 16, HEIGHT * 0.45), (x + 16, HEIGHT + 50),
                       (x, HEIGHT + 50)])
        return p.coverage(), textured(canvas, rng, [0.25, 0.22, 0.18], 0.2)
    if kind == "bare-tree":
        def branch(start, angle, length, width, depth):
            end = (start[0] + length * math.cos(angle), start[1] - length * math.sin(angle))
            p.line(start, end, width)
            if depth and width > 0.3:
                for _ in range(rng.integers(2, 4)):
                    branch(end, angle + rng.normal(0, 0.45), length * rng.uniform(0.6, 0.8), width * rng.uniform(0.55, 0.7),
                           depth - 1)
        for base in (WIDTH * 0.2, WIDTH * 0.85):
            p.line((base, HEIGHT + 50), (base, HEIGHT * 0.55), 18)
            for _ in range(3):
                branch((base, HEIGHT * 0.55), math.pi / 2 + rng.normal(0, 0.5), 110, 9, 8)
        return p.coverage(), textured(canvas, rng, [0.05, 0.04, 0.035])
    if kind == "string-lights":
        posts = [WIDTH * 0.12, WIDTH * 0.88]
        for x in posts:
            p.line((x, HEIGHT + 50), (x, HEIGHT * 0.15), 7)
        bulbs = canvas.painter()
        for k in range(26):
            t = k / 25
            x = posts[0] + (posts[1] - posts[0]) * t
            y = HEIGHT * 0.15 + 90 * (1 - (2 * t - 1) ** 2)
            bulbs.ellipse((x, y + 4), 2.2, 2.2)
            lights.append(dict(layer="mid", x=x, y=y + 4, radius=2.2, value=[9.0, 6.5, 3.0]))
        wire = canvas.painter()
        pts = [(posts[0] + (posts[1] - posts[0]) * t, HEIGHT * 0.15 + 90 * (1 - (2 * t - 1) ** 2))
               for t in np.linspace(0, 1, 120)]
        wire.strand(pts, 0.8, 0.8)
        a_post, a_bulb, a_wire = p.coverage(), bulbs.coverage(), wire.coverage()
        alpha = 1 - (1 - a_post) * (1 - a_bulb) * (1 - a_wire)
        colour = textured(canvas, rng, [0.03, 0.03, 0.03], 0.1)
        share = (a_bulb / np.maximum(alpha, 1e-6))[..., None]
        return alpha, (1 - share) * colour + share * np.array([9.0, 6.5, 3.0], np.float32)
    if kind == "panel":
        p.polygon([(WIDTH * 0.68, HEIGHT * 0.1), (WIDTH * 1.1, HEIGHT * 0.1), (WIDTH * 1.1, HEIGHT * 1.1), (WIDTH * 0.68, HEIGHT * 1.1)])
        x, y = canvas.grid()
        colour = np.stack([0.5 + 0.4 * np.sin(y / 15), 0.3 + 0 * x, 0.1 + 0.08 * np.cos(x / 7)], -1)
        return p.coverage(), np.clip(colour, 0.01, None).astype(np.float32)
    raise ValueError(kind)


def foreground(canvas, rng, kind):
    p = canvas.painter()
    if kind == "branch":
        start, end = (-80, HEIGHT * 0.25), (WIDTH * 0.32, HEIGHT * 0.62)
        p.line(start, end, 14)
        for t in np.linspace(0.15, 1.0, 12):
            base = (start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t)
            angle = rng.uniform(-1.2, 1.6)
            length, half = rng.uniform(70, 130), rng.uniform(18, 32)
            tip = (base[0] + length * math.cos(angle), base[1] + length * math.sin(angle))
            normal = (-math.sin(angle) * half, math.cos(angle) * half)
            mid = ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2)
            p.polygon([base, (mid[0] + normal[0], mid[1] + normal[1]), tip, (mid[0] - normal[0], mid[1] - normal[1])])
        return p.coverage(), textured(canvas, rng, [0.03, 0.10, 0.025], 0.4)
    if kind == "grass":
        for _ in range(14):
            x = rng.uniform(0, WIDTH * 0.45)
            lean = rng.normal(0, 60)
            h = HEIGHT * rng.uniform(0.35, 0.8)
            w = rng.uniform(6, 14)
            p.polygon([(x - w, HEIGHT + 20), (x + w, HEIGHT + 20), (x + lean, HEIGHT - h)])
        return p.coverage(), textured(canvas, rng, [0.05, 0.12, 0.03], 0.3)
    if kind == "post":
        p.polygon([(WIDTH * 0.66, -50), (WIDTH * 0.74, -50), (WIDTH * 0.75, HEIGHT + 50), (WIDTH * 0.67, HEIGHT + 50)])
        x, y = canvas.grid()
        grain = 0.5 + 0.5 * np.sin(x / 2.3 + 0.8 * np.sin(y / 40))
        colour = np.stack([0.20 + 0.10 * grain, 0.12 + 0.06 * grain, 0.06 + 0.03 * grain], -1)
        return p.coverage(), colour.astype(np.float32)
    raise ValueError(kind)


def background_lights(canvas, rng, kind, count, lights):
    if kind == "grid":
        spots = [(WIDTH * (0.08 + 0.12 * i), HEIGHT * (0.08 + 0.1 * (i % 3))) for i in range(8)]
        spots += [(WIDTH * (0.06 + 0.13 * i), HEIGHT * 0.92) for i in range(8)]
        spots += [(WIDTH * 0.04, HEIGHT * (0.3 + 0.08 * i)) for i in range(4)] + \
                 [(WIDTH * 0.96, HEIGHT * (0.3 + 0.08 * i)) for i in range(4)]
    else:
        spots = [(rng.uniform(0.03, 0.97) * WIDTH, rng.uniform(0.03, 0.97) * HEIGHT) for _ in range(count)]
    for x, y in spots:
        radius = rng.uniform(0.5, 2.5)
        if kind == "dim":
            level = rng.uniform(0.55, 0.95)
        elif kind == "glints":
            level = rng.uniform(3, 60)
        else:
            level = math.exp(rng.uniform(math.log(2), math.log(60)))
        tint = rng.choice([np.array([1.0, 0.85, 0.6]), np.array([1.0, 1.0, 1.0]), np.array([0.7, 0.85, 1.0]),
                           np.array([1.0, 0.5, 0.3])])
        lights.append(dict(layer="bg", x=float(x), y=float(y), radius=float(radius), value=(level * tint).tolist()))


def paint_lights(canvas, rgb, lights, layer):
    for light in [l for l in lights if l["layer"] == layer and layer == "bg"]:
        p = canvas.painter()
        p.ellipse((light["x"], light["y"]), light["radius"], light["radius"])
        cov = p.coverage()[..., None]
        rgb = (1 - cov) * rgb + cov * np.asarray(light["value"], np.float32)
    return rgb


def build_layers(name, spec, scale, margin):
    """Premultiplied RGBA layers, nearest first, with their depths and the lights."""
    def rng(part):
        return np.random.default_rng([sum(map(ord, name)), sum(map(ord, part))])

    canvas = Canvas(scale, margin)
    lights = []
    layers = []
    if "fg" in spec:
        a, c = foreground(canvas, rng("fg"), spec["fg"][0])
        layers.append(("foreground", spec["fg"][1], a, c))
    a, c = subject(canvas, rng("subject"), spec["subject"][0])
    layers.append(("subject", spec["subject"][1], a, c))
    if "mid" in spec:
        a, c = mid_layer(canvas, rng("mid"), spec["mid"][0], lights)
        layers.append(("mid", spec["mid"][1], a, c))
    bg_name, bg_z = spec["bg"]
    bg = procedural_background(canvas, rng("bg")) if bg_name == "procedural" else photo(canvas, bg_name)
    if "lights" in spec:
        background_lights(canvas, rng("lights"), spec["lights"][0], spec["lights"][1], lights)
    bg = paint_lights(canvas, bg, lights, "bg")
    layers.append(("background", bg_z, np.ones(bg.shape[:2], np.float32), bg))
    layer_depth = {n: z for n, z, _, _ in layers}
    for light in lights:
        light["z"] = layer_depth["background" if light["layer"] == "bg" else "mid"]
    rgba = np.stack([np.concatenate([c * a[..., None], a[..., None]], -1) for _, _, a, c in layers]).astype(np.float32)
    return [n for n, *_ in layers], [z for _, z, *_ in layers], rgba, lights


# MARK: - Tracing

def trace(layers_t, depths, cam, canvas, points, height, width):
    """Mean over lens points of the front-to-back composite along each ray; points (n, 2) unit lens coords."""
    f, v = cam["focal_length_mm"], cam["image_distance_mm"]
    breathe = f / v
    radii = [coc_px(cam, z) / 2 for z in depths]
    ys, xs = torch.meshgrid(torch.arange(height, device=DEVICE, dtype=torch.float32) + 0.5 - height / 2,
                            torch.arange(width, device=DEVICE, dtype=torch.float32) + 0.5 - width / 2, indexing="ij")
    base = torch.stack([xs, ys], -1)
    norm = torch.tensor([2 / canvas.width, 2 / canvas.height], device=DEVICE)
    centre = torch.tensor([canvas.width / 2, canvas.height / 2], device=DEVICE)
    # Lens y is up, image rows go down.
    pts = torch.from_numpy(points * np.array([1, -1], np.float32)).to(DEVICE)
    total = torch.zeros(3, height, width, device=DEVICE)
    for start in range(0, len(pts), BATCH):
        a = pts[start:start + BATCH]
        b = len(a)
        colour = torch.zeros(b, 3, height, width, device=DEVICE)
        transmit = torch.ones(b, 1, height, width, device=DEVICE)
        for layer, r in zip(layers_t, radii):
            q = (base[None] + a[:, None, None, :] * float(r)) * breathe
            grid = (q + centre) * norm - 1
            s = torch.nn.functional.grid_sample(layer.expand(b, -1, -1, -1), grid, mode="bilinear",
                                                padding_mode="zeros", align_corners=False)
            colour += transmit * s[:, :3]
            transmit = transmit * (1 - s[:, 3:])
        total += colour.sum(0)
    return (total / len(pts)).permute(1, 2, 0).cpu().numpy()


def pinhole_layers(layers_t, cam, canvas, height, width):
    """Each layer's premultiplied RGBA seen through the lens centre (no occlusion)."""
    breathe = cam["focal_length_mm"] / cam["image_distance_mm"]
    ys, xs = torch.meshgrid(torch.arange(height, device=DEVICE, dtype=torch.float32) + 0.5 - height / 2,
                            torch.arange(width, device=DEVICE, dtype=torch.float32) + 0.5 - width / 2, indexing="ij")
    q = torch.stack([xs, ys], -1) * breathe
    norm = torch.tensor([2 / canvas.width, 2 / canvas.height], device=DEVICE)
    centre = torch.tensor([canvas.width / 2, canvas.height / 2], device=DEVICE)
    grid = ((q + centre) * norm - 1)[None]
    return [torch.nn.functional.grid_sample(layer, grid, mode="bilinear", padding_mode="zeros",
                                            align_corners=False)[0].permute(1, 2, 0).cpu().numpy() for layer in layers_t]


def apertures_for(focal):
    return (1.4, 2.8, 5.6)


def render_scene(name, scale=1):
    spec = SCENES[name]
    width, height = WIDTH * scale, HEIGHT * scale
    scene_name = name if scale == 1 else f"{name}@{scale}x"
    out = DATA / "layered" / scene_name
    focal = spec["focal"]
    depth_all = [spec[k][1] for k in ("fg", "subject", "mid", "bg") if k in spec]
    focus = {"subject": spec["subject"][1], "background": spec["bg"][1]}
    wide = min(apertures_for(focal))
    max_radius = max(abs(coc_px(camera(focal, wide, s, width, height), z)) / 2 for s in focus.values() for z in depth_all)
    margin = int(math.ceil(max_radius)) + 8
    assert margin <= PAD * scale, (name, margin)
    started = time.time()
    names, depths, rgba, lights = build_layers(name, spec, scale, margin)
    canvas = Canvas(scale, margin)
    layers_t = [torch.from_numpy(np.ascontiguousarray(l.transpose(2, 0, 1)))[None].to(DEVICE) for l in rgba]
    built = time.time() - started
    scene_json = {"set": "layered", "scene": scene_name, "scale": scale, "layers": [
        {"name": n, "depth_m": z} for n, z in zip(names, depths)], "background_photo": spec["bg"][0],
        "lights_reference": lights, "margin_px": margin, "build_seconds": round(built, 1), "variants": []}
    variant_list = variants(apertures_for(focal)) if scale == 1 else [(f"f2.8-circle", 2.8, 0, 0.0, 1.0)]
    for focus_name, s in focus.items():
        folder = out / focus_name
        cam0 = camera(focal, 2.8, s, width, height)
        seen = pinhole_layers(layers_t, cam0, canvas, height, width)
        transmit = np.ones((height, width), np.float32)
        image = np.zeros((height, width, 3), np.float32)
        weights = []
        for layer in seen:
            weights.append(transmit * layer[..., 3])
            image += transmit[..., None] * layer[..., :3]
            transmit = transmit * (1 - layer[..., 3])
        weights = np.stack(weights)
        depth = (weights * np.asarray(depths, np.float32)[:, None, None]).sum(0) / weights.sum(0)
        nearest = np.asarray(depths, np.float32)[weights.argmax(0)]
        subject_index = names.index("subject")
        occluder = 1 - np.prod([1 - seen[i][..., 3] for i in range(subject_index)], axis=0) if subject_index else \
            np.zeros((height, width), np.float32)
        write_exr(folder / "input.exr", image)
        write_exr(folder / "input_clipped.exr", np.clip(image, 0, 1))
        write_exr(folder / "depth.exr", depth)
        write_exr(folder / "depth_nearest.exr", nearest)
        write_exr(folder / "alpha.exr", seen[subject_index][..., 3])
        write_exr(folder / "occluder.exr", occluder)
        np.savez_compressed(folder / "layers.npz", rgba=np.stack(seen).astype(np.float16), depth_m=np.asarray(depths),
                            names=np.asarray(names), premultiplied=True)
        common.save_preview(folder / "input.png", image)
        for variant, n_stop, blades, rotation, ratio in variant_list:
            cam = camera(focal, n_stop, s, width, height, blades, rotation, ratio)
            radius = max(abs(coc_px(cam, z)) / 2 for z in depths)
            n_side = max(16, int(math.ceil(2 * math.sqrt(2) * radius)))
            points = aperture_lattice(blades, rotation, ratio, n_side)
            t = time.time()
            truth = trace(layers_t, depths, cam, canvas, points, height, width)
            seconds = time.time() - t
            breathe = cam["image_distance_mm"] / cam["focal_length_mm"]
            cam_lights = []
            for light in lights:
                c = abs(float(coc_px(cam, light["z"])))
                cam_lights.append(dict(x=(light["x"] * scale - width / 2) * breathe + width / 2,
                                       y=(light["y"] * scale - height / 2) * breathe + height / 2,
                                       radius_px=light["radius"] * scale * breathe, depth_m=light["z"],
                                       coc_px=c, value=light["value"]))
            write_exr(folder / f"{variant}.exr", truth)
            common.save_preview(folder / f"{variant}.png", truth)
            write_json(folder / f"{variant}.json", dict(
                set="layered", scene=scene_name, focus=focus_name, variant=variant, **cam,
                depth_convention="planar distance from the lens plane along the optical axis, metres",
                lights=cam_lights, samples=len(points), lattice_spacing_px=2 * math.sqrt(2) * radius / n_side,
                trace_seconds=round(seconds, 2)))
            scene_json["variants"].append(f"{focus_name}/{variant}")
            print(f"{scene_name} {focus_name} {variant}: {len(points)} lens points, max CoC {2 * radius:.1f} px, "
                  f"{seconds:.1f} s", flush=True)
    scene_json["seconds"] = round(time.time() - started, 1)
    write_json(out / "scene.json", scene_json)


def check():
    """A single bright texel at 20 m with focus at 2 m: its disc must hold all its energy and have the
    second moment of a uniform disc of the formula's diameter, (c/2)^2 / 4 per axis."""
    cam = camera(85, 2.8, 2.0, WIDTH, HEIGHT)
    c = abs(float(coc_px(cam, 20.0)))
    margin = int(c) + 8
    canvas = Canvas(1, margin)
    layer = np.zeros((canvas.height, canvas.width, 4), np.float32)
    layer[..., 3] = 1
    # The texel whose centre maps to the frame centre once the breathing scale f/v is applied.
    layer[canvas.height // 2, canvas.width // 2, :3] = 1000.0
    layers_t = [torch.from_numpy(layer.transpose(2, 0, 1).copy())[None].to(DEVICE)]
    points = aperture_lattice(0, 0.0, 1.0, int(math.ceil(2 * math.sqrt(2) * c / 2)))
    truth = trace(layers_t, [20.0], cam, canvas, points, HEIGHT, WIDTH)[..., 0]
    seen = pinhole_layers(layers_t, cam, canvas, HEIGHT, WIDTH)[0][..., 0]
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH] + 0.5
    total = truth.sum()
    mx, my = (truth * x).sum() / total, (truth * y).sum() / total
    variance = ((truth * (x - mx) ** 2).sum() / total + (truth * (y - my) ** 2).sum() / total) / 2
    expected = (c / 2) ** 2 / 4
    print(f"CoC {c:.2f} px: energy {total / seen.sum():.5f} of the pinhole's, variance per axis {variance:.3f} "
          f"against {expected:.3f} ({variance / expected - 1:+.2%}), plus the pinhole texel's own spread")


def main(argv):
    if "--check" in argv:
        check()
        return
    double = "--2x" in argv
    names = [a for a in argv if not a.startswith("--")] or ([] if double else list(SCENES))
    started = time.time()
    if double and not names:
        names = DOUBLE
    for name in names:
        render_scene(name, scale=2 if double else 1)
    print(f"done in {time.time() - started:.0f} s on {DEVICE}")


if __name__ == "__main__":
    main(sys.argv[1:])
