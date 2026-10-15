"""
The ambassadors reel (docs/plans/2026-10-15-ambassadors-promo.md): Redlamp's ambassador programme told as an
episode of the feature videos, under the header REDLAMP · AMBASSADORS, in eight bars at 100 BPM. The hook stands
over the lamp warming, as the opener's first bar does, re-timed to the reel's grid; on the first hit the lamp
rises into the header's mark as the dashboard comes in; an edit brightens a pixel-art street at dusk; the Basic
panel turns into a roadmap and one row lifts as the viewer's pick; on the drop the street comes up out of white
as a post with the viewer's handle under it; ten empty frames are laid out for the founding places and one is
ringed; then the ask over the lamp, fading to the wall the reel loops back to.

Its timings are src/ambassadors/cues.json, which scripts/ambassadors-score.py reads too, and its words are
src/ambassadors/copy.json. frame(c, beat, hook) draws any moment, and sounds() lists each sound on screen.
"""

import json
import math
from typing import NamedTuple

import numpy as np

from features import world as w

SHEET = json.loads((w.VIDEO / "src/ambassadors/cues.json").read_text())
COPY = json.loads((w.VIDEO / "src/ambassadors/copy.json").read_text())
CUE = SHEET["cues"]
BPM, FPS = SHEET["bpm"], SHEET["fps"]
PER_BEAT = 60 / BPM * FPS
FRAMES = round(SHEET["bars"] * SHEET["beatsPerBar"] * PER_BEAT)
FEATURE = COPY["header"]
HOOKS = COPY["hooks"]
LINES = COPY["lines"]
FILE = COPY["file"]

PHOTO_PANEL = w.Rect(4, 106, 208, 90)
HIST = w.Rect(4, 198, 208, 20)
BASIC = w.Rect(4, 220, 178, 66)
LEVEL = w.Rect(190, 224, 18, 58)
TRACK = (52, 140)
POST = w.Rect(40, 106, 136, 180)
PRINT = w.Rect(44, 110, 128, 160)
STRIP = w.Rect(44, 270, 128, 12)
PAPER = "#f3eee8"
LAMP_Y = 168

# The lamp takes the half beat after the first hit to rise into the header's mark, and the dashboard develops
# in over the same half beat.
MOVE = 0.5
# Panels and labels develop in over six frames, as the series' cards do.
APPEAR = 6 / PER_BEAT


# ---------------------------------------------------------------- the street

KERB = 0.7
# The sky by height, lighter towards the rooftops so they stand out against it.
SKY = [(0.0, "#120f30"), (0.12, "#2a1c5e"), (0.32, "#6f4ba3"), (KERB, "#7d5aad")]


def lin(h):
    return w._linear(w._hex(h))


def street(width, height):
    """A street at dusk, in linear light: a violet sky over dark buildings, a shopfront lit amber with a figure
    crossing in front of it, and all of it doubled in the wet pavement. It's laid out from the middle in heights,
    so it holds together as the wide photo panel and as the upright print, and nothing in it is red."""
    x = (np.arange(width) + 0.5) / width
    y = (np.arange(height) + 0.5) / height
    X, Y = np.meshgrid(x, y)
    U = (X - 0.5) * width / height
    wet = Y >= KERB
    V = np.where(wet, 2 * KERB - Y, Y)
    img = np.zeros((height, width, 3))
    stops = [s for s, _ in SKY]
    cols = np.array([lin(c) for _, c in SKY])
    for k in range(3):
        img[..., k] = np.interp(V, stops, cols[:, k])

    edges = [-9, -1.05, -0.66, -0.34, 0.34, 0.72, 1.12, 9]
    roofs = [0.24, 0.3, 0.2, 0.15, 0.27, 0.21, 0.29]
    for n, ((a, z), roof) in enumerate(zip(zip(edges, edges[1:]), roofs)):
        block = (U >= a) & (U < z) & (V > roof)
        img[block] = lin("#110e22")
        cu, cv = (U - a) / 0.06, (V - roof) / 0.06
        window = block & (cu % 1 > 0.3) & (cu % 1 < 0.75) & (cv % 1 > 0.35) & (cv % 1 < 0.8) & (V > roof + 0.03) & (V < 0.29)
        lit = (np.floor(cu) * 7 + np.floor(cv) * 13 + n * 5) % 6 == 0
        img[window & lit] = lin("#e0a04e") * 0.7
        img[window & ~lit] = lin("#221c3a")

    shop = (np.abs(U) < 0.3) & (V > 0.37) & (V < KERB)
    glow = np.clip((V - 0.37) / (KERB - 0.37), 0, 1)
    img[shop] = (lin("#ffd98c") * (1 - glow[shop, None]) + lin("#ff9f3a") * glow[shop, None])
    img[(np.abs(U) < 0.32) & (V > 0.3) & (V <= 0.37)] = lin("#1c1730")
    img[(np.abs(U) < 0.28) & (V > 0.33) & (V < 0.345)] = lin("#e8b060") * 0.7
    frames = shop & ((np.abs(np.abs(U) - 0.1) < 0.012) | (np.abs(V - 0.44) < 0.008) | (np.abs(np.abs(U) - 0.295) < 0.01))
    img[frames] = lin("#3a2a20")

    # A figure in silhouette crossing in front of the shopfront, mid-stride.
    fx, foot = 0.12, KERB
    figure = (np.hypot(U - fx, (V - (foot - 0.215)) * 1.0) < 0.03)
    figure |= (np.abs(U - fx - 0.004) < 0.034 - 0.012 * (V - (foot - 0.185)) / 0.1) & (V > foot - 0.185) & (V < foot - 0.085)
    for lean in (-0.3, 0.38):
        leg = (V >= foot - 0.09) & (V < foot) & (np.abs(U - fx - lean * (V - (foot - 0.09))) < 0.011)
        figure |= leg
    figure |= (V > foot - 0.17) & (V < foot - 0.1) & (np.abs(U - fx + 0.03 - 0.35 * (V - (foot - 0.17))) < 0.009)
    img[figure] = lin("#07060c")

    img[wet] *= 0.36
    img[wet & (np.arange(height)[:, None] % 3 == 0)] *= 0.55
    img[(Y >= KERB) & (Y < KERB + 1.5 / height)] = lin("#3c3656")
    rng = np.random.default_rng(11)
    for _ in range(width * height // 400):
        px, py = rng.integers(0, width), rng.integers(0, max(1, int(height * 0.12)))
        img[py, px] = lin("#e9ecf8")
    return img


class Slider(NamedTuple):
    label: str
    accent: str
    reach: float


SLIDERS = [Slider("EXPOSURE", "gold", 5), Slider("HIGHLIGHTS", "cyan", 100), Slider("SHADOWS", "violet", 100),
           Slider("VIBRANCE", "orange", 100)]
# Each drag in the cue sheet, [press, tick, tick, release], and the slider it moves to its value.
DRAGGED = [("EXPOSURE", 1.0), ("VIBRANCE", 40)]
DRAGS = list(zip(DRAGGED, SHEET["drags"]))
TARGET = dict(DRAGGED)


def value_at(label, b):
    for (name, target), (press, *ticks, release) in DRAGS:
        if name == label:
            return target * sum(b >= t for t in ticks) / len(ticks)
    return 0


def value_text(reach, v):
    if round(v, 2 if reach < 10 else 0) == 0:
        return "0.00" if reach < 10 else "0"
    return f"{v:+.2f}" if reach < 10 else f"{v:+.0f}"


def picture(values, size):
    return w.scene(street, values, size, TARGET)


# ---------------------------------------------------------------- the header, and the lamp rising into it

def header_at(c):
    """Where the header's safelight mark stands: its left edge, and the centre the lamp rises to."""
    tw = c.measure(f"REDLAMP · {FEATURE}", "large")
    x = (c.w - (9 + 4 + tw)) // 2
    return x, (x + 4.5, w.HEADER.y + 6)


def header(c, *, mark=True):
    """The series' header, REDLAMP · AMBASSADORS; without its mark while the lamp is still rising into it."""
    if mark:
        w.header(c, FEATURE)
        return
    x, _ = header_at(c)
    c.spans(x + 13, w.HEADER.y + 3, [("REDLAMP", "white"), (f" · {FEATURE}", "muted")], font="large")
    c.claim(w.Rect(0, w.HEADER.y, c.w, w.HEADER.h), "header")


def warmth(b):
    """How warm the lamp is at beat b: the opener's warming, on its own frames."""
    return w.ramp(b * w.OPENER_PER_BEAT, 6, 120)


def rising(c, b):
    """The lamp shrinking and rising into the header's mark over the half beat after the first hit, drawing its
    light in with it, so the mark that appears where it lands is the picture's one red light."""
    t = w.ease(w.between(b, CUE["dashboard"], CUE["dashboard"] + MOVE))
    _, (mx, my) = header_at(c)
    cx, cy = c.w / 2 + (mx - c.w / 2) * t, w.LAMP_Y + (my - w.LAMP_Y) * t
    r = w.LAMP_R + (4.5 - w.LAMP_R) * t
    warm = warmth(b)
    c.glow(cx, cy, (30 + 62 * warm) * (1 - 0.8 * t), "red", amount=0.5 * warm * (1 - t), levels=3)
    w.safelight(c, cx, cy, r, warm)


# ---------------------------------------------------------------- bar 1

def opening(c, b, hook):
    """Bar 1: the opener's first bar, its 100 frames at 72 BPM drawn into the reel's first 72, so the hook stands
    over the lamp warming in the dark, and its last frame is the cover every episode has."""
    w.opener(c, b * w.OPENER_PER_BEAT, {"title": FEATURE}, HOOKS[hook], FEATURE)


# ---------------------------------------------------------------- bars 2 and 3: the dashboard

def basic(c, b):
    """The Basic panel as meters, the one being dragged lit. Returns each knob's place."""
    active = next((name for (name, _), (press, *_, release) in DRAGS if press <= b < release), None)
    rows = []
    for s in SLIDERS:
        v = value_at(s.label, b)
        rows.append((s.label, s.accent, value_text(s.reach, v), 0.5 + v / (2 * s.reach), s.label == active))
    return w.meters(c, BASIC, rows, right="4 SLIDERS", track=TRACK)


# The roadmap's rows: a sprite each, in its own accent, for rows that could be on January's shortlist (Accepted, Not
# started, in Phase 2, S or M, and aimed at no release): zoom with the scroll wheel (UX-38), the Targeted Adjustment
# Tool (UX-35), choosing which Develop panels show (UX-41) and Open With from Finder (UX-37). The second is the one
# that lifts. Where copy.json names no rows, a dim bar stands where each name would be, so the picture promises no
# feature.
ROW_SPRITES = [
    ([".####...", "#....#..", "#....#..", "#....#..", "#....#..", ".####...", ".....##.", "......##"], "cyan"),
    (["...##...", ".######.", ".#....#.", "###..###", "###..###", ".#....#.", ".######.", "...##..."], "violet"),
    (["###.####", "#.#.....", "###.####", "........", "###.####", "#.#.....", "###.####", "........"], "sky"),
    (["###.....", "#..####.", "#......#", "#......#", "#......#", "#......#", "########", "........"], "green"),
]
ROW_BARS = [66, 92, 54, 78]
PICKED = 1


def roadmap_rows(c, p, b):
    """The roadmap's rows in the panel's content rect `p`: the picked row lit while it's pressed, then lifted two
    pixels out of the list with a shadow and a gold rim, and YOUR PICK beside it."""
    names = COPY.get("rows") or []
    for i, (art, accent) in enumerate(ROW_SPRITES):
        y = p.y + 2 + i * 12
        lifted = i == PICKED and b >= CUE["pick"]
        if i == PICKED and CUE["pickPress"] <= b < CUE["pick"]:
            c.rect(p.x - 2, y - 2, p.w + 4, 11, "raised")
        if lifted:
            y -= 2
            c.rect(p.x - 1, y - 1, p.w + 4, 12, "shadow")
            c.rect(p.x - 3, y - 3, p.w + 4, 12, "raised")
            c.box(p.x - 3, y - 3, p.w + 4, 12, "gold")
        c.sprite(p.x, y, art, {"#": f"{accent}.light" if lifted else accent})
        if i < len(names):
            c.text(p.x + 12, y + 2, names[i], "white" if lifted else "text")
        else:
            c.rect(p.x + 12, y + 3, ROW_BARS[i], 3, "muted" if lifted else "line")
        if lifted:
            w.appear(c, w.between(b, CUE["pick"], CUE["pick"] + 2 / PER_BEAT),
                     lambda c, y=y: c.text(176, y + 1, LINES["pick"], "gold", font="large", align="right"))
    return [w.Rect(p.x, p.y + 2 + i * 12 - (2 if i == PICKED and b >= CUE["pick"] else 0), p.w, 8)
            for i in range(len(ROW_SPRITES))]


def roadmap(c, b):
    """Bar 3's panel in the Basic panel's place. Returns each row's rect."""
    p = c.panel(*BASIC, "ROADMAP", color="sky")
    return roadmap_rows(c, p, b)


def glide(a, z, t):
    return round(a[0] + (z[0] - a[0]) * t), round(a[1] + (z[1] - a[1]) * t)


def pointer_at(knobs, rows, b):
    """The pointer: on Exposure's knob as the dashboard comes in, moving with each knob it drags, gliding from
    one to the next, then to the second row of the roadmap, which it presses and lets go on the pick."""
    (first, _), (press1, *_, release1) = DRAGS[0]
    (second, _), (press2, *_, release2) = DRAGS[1]
    if b < release1:
        return knobs[first], press1 <= b
    if b < press2:
        return glide(knobs[first], knobs[second], w.ease(w.between(b, release1, press2))), False
    if b < CUE["roadmap"] + 0.5 or rows is None:
        return knobs[second], press2 <= b < release2
    row = rows[PICKED]
    target = (row.x + 44, row.y + 3)
    if b < CUE["pickPress"]:
        return glide(knobs[second], target, w.ease(w.between(b, CUE["roadmap"] + 0.5, CUE["pickPress"]))), False
    return target, b < CUE["pick"]


def knob_x(label, v):
    """Where a meter's knob is at value v, as w.meters places it."""
    reach = next(s.reach for s in SLIDERS if s.label == label)
    t0, t1 = BASIC.x + TRACK[0], BASIC.x + TRACK[1]
    return round(t0 + (0.5 + v / (2 * reach)) * (t1 - t0))


def dashboard(c, b, *, rising_lamp=True):
    """Bars 2 and 3: the header, the street in the photo panel with its histogram and level, the Basic panel's
    meters and, from the roadmap's cue, the roadmap in their place, the pointer, and the bar's caption. Over the
    half beat after the first hit the whole dashboard develops in under the lamp rising into the header."""
    coming = b < CUE["dashboard"] + MOVE
    before = c.img.copy()
    header(c, mark=not coming)
    img = picture({name: value_at(name, b) for name, _ in DRAGGED}, (PHOTO_PANEL.w - 8, PHOTO_PANEL.h - 16))
    w.photo_panel(c, PHOTO_PANEL, img, b, FILE, horizon=KERB)
    w.histogram(c, img, HIST)
    c.seg_column(*LEVEL, min(1.0, float(np.asarray(img).mean()) / 255 * 2.2), "gold", seg=2, gap=1)
    if b < CUE["roadmap"]:
        knobs, rows = basic(c, b), None
    else:
        meters = w.canvas()
        meters.img.paste(c.img)
        knobs = basic(meters, CUE["roadmap"] - 0.01)
        rows = roadmap(c, b)
        w.develop(c, meters.img, w.between(b, CUE["roadmap"], CUE["roadmap"] + APPEAR))
    at, pressed = pointer_at(knobs, rows, b)
    w.pointer(c, *at, pressed=pressed)
    if coming:
        w.develop(c, before, w.between(b, CUE["dashboard"], CUE["dashboard"] + MOVE))
        if rising_lamp:
            rising(c, b)
    w.caption(c, LINES["dashboard"] if b < CUE["roadmap"] else LINES["roadmap"])
    return []


# ---------------------------------------------------------------- bar 4: the post

def strip(c, x, y):
    """The credit strip under the print: the Redlamp mark in white, so it isn't a second red light, and the
    viewer's handle."""
    c.rect(x, y, STRIP.w, STRIP.h, "shadow")
    c.sprite(x + 4, y + 2, w.LAMP_MARK[0], {"o": "white", "r": "shadow", "l": "white"})
    c.text(x + 17, y + 3, LINES["handle"], "white", font="large")


def post(c, b):
    """Bar 4, the drop: the stage turns into a post, whose print comes up out of white into the street as edited
    over the beat, and the credit strip slides up out of its bottom edge and lands on the credit's cue. Nothing on
    the post counts anything."""
    header(c)
    c.rect(*POST, "panel")
    c.box(*POST, "line")
    c.rect(*PRINT, PAPER)
    before = c.img.copy()
    c.img.paste(picture(TARGET, (PRINT.w, PRINT.h)), (PRINT.x, PRINT.y))
    w.develop(c, before, w.ease(w.between(b, CUE["drop"], CUE["developed"])))
    if b < CUE["drop"] + 0.5:
        c.sparkles(PRINT.x, PRINT.y, PRINT.w, PRINT.h, 26, ["white", "gold.light"], seed=int(b * PER_BEAT))
    slide = w.between(b, CUE["credit"] - 0.5, CUE["credit"])
    if slide > 0:
        window = c.sub(STRIP.w, POST.y2 - 1 - STRIP.y, bg="panel")
        strip(window, 0, round((1 - w.ease(slide)) * window.h))
        c.paste(window, STRIP.x, STRIP.y)
    w.caption(c, LINES["drop"])
    return []


# ---------------------------------------------------------------- bar 5: ten frames

FRAME = (34, 23)
STAGE = w.Rect(4, 104, 208, 183)
STRIP_YS = [160, 203]
# Each strip's frames, from the stage's left edge, running off both its edges: (x, the burst's index), or None for
# a frame at the edge, which is already on the roll. The burst takes the ten whole frames one a sixteenth.
STRIPS = [
    [(-16, None), (22, 0), (60, 1), (98, 2), (136, 3), (174, 4)],
    [(6, 5), (44, 6), (82, 7), (120, 8), (158, 9), (196, None)],
]
RINGED = 6
INK = "#17110f"


class Face(NamedTuple):
    """A photographer on the contact sheet, drawn for fun: a skin tone and its shade, the hair's colour and style,
    what's on their head, their eyes and mouth, the backdrop and the shirt."""
    skin: tuple
    hair: str
    style: str
    top: str | None
    eyes: str
    mouth: str
    backdrop: str
    shirt: str
    freckles: bool = False


# Nine photographers in the frames the burst fills, in its order, and None for the viewer's frame, which the marker
# rings. Nothing in them is red, so the lamp stays the picture's one red light.
FACES = [
    Face(("#7a4a2a", "#5f381f"), INK, "afro", None, "round", "grin", "violet.dark", "gold"),
    Face(("#e0ac7e", "#c08c5f"), "#6b4226", "short", "beanie:gold", "dots", "beard", "sky.dark", "green"),
    Face(("#f1c9a5", "#d4a682"), "#3b2416", "bun", None, "camera", "smile", "green.dark", "violet"),
    Face(("#c68a5d", "#a66d43"), "cyan", "mohawk", None, "wink", "tongue", "gold.dark", "line"),
    Face(("#a5683f", "#86512f"), INK, "short", "bucket:green", "shades", "smile", "cyan.dark", "orange"),
    Face(("#f3d6bd", "#d9b496"), "#e8c66a", "long", "headphones:violet", "dots", "smile", "blue.dark", "sky"),
    None,
    Face(("#d9a066", "#b9824c"), "#a3a8b0", "bald", None, "dots", "moustache", "orange.dark", "cyan"),
    Face(("#f1c9a5", "#d4a682"), "#c8642a", "short", "cap:sky", "dots", "grin", "violet.dark", "gold", freckles=True),
    Face(("#5a3620", "#432716"), "violet.light", "curly", None, "square", "smile", "gold.dark", "green"),
]
# The two photographers in the frames at the strips' edges, half in view.
EDGE_FACES = [
    Face(("#e0ac7e", "#c08c5f"), "#a3a8b0", "short", None, "round", "smile", "green.dark", "sky"),
    Face(("#8d5a37", "#704429"), INK, "bun", None, "shades", "grin", "sky.dark", "violet"),
]


def oval(c, cx, cy, rx, ry, colour, rows=(-99, 99)):
    """A filled ellipse in whole pixels, clipped to the canvas and to `rows`."""
    for y in range(max(0, math.floor(cy - ry), rows[0]), min(c.h - 1, math.ceil(cy + ry), rows[1]) + 1):
        for x in range(max(0, math.floor(cx - rx)), min(c.w - 1, math.ceil(cx + rx)) + 1):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1:
                c.px(x, y, colour)


def portrait(face):
    """A photographer, head and shoulders, on their own 34 × 23 canvas, lit from above left."""
    c = w.canvas(*FRAME)
    c.rect(0, 0, *FRAME, face.backdrop)
    tone, shade = face.skin
    top, colour = (face.top.split(":") + [None])[:2] if face.top else (None, None)
    if face.style == "afro":
        oval(c, 17, 8.5, 10.5, 9, face.hair)
    if face.style == "long":
        c.rect(9, 6, 3, 17, face.hair)
        c.rect(23, 6, 3, 17, face.hair)
    oval(c, 17, 26, 12, 7.5, face.shirt)
    c.rect(15, 16, 5, 4, shade)
    oval(c, 17, 10.5, 6.5, 7.5, shade)
    oval(c, 16.5, 10, 6, 7.2, tone)
    for y in (10, 11):
        c.px(10, y, shade)
        c.px(24, y, shade)
    if face.style in ("short", "bun", "curly", "afro", "long"):
        oval(c, 17, 6.5, 7, 4.5, face.hair, rows=(0, 6))
    if face.style == "curly":
        for x in range(11, 24, 2):
            c.px(x, 7, face.hair)
    if face.style == "bun":
        oval(c, 17, 1.5, 3, 2.5, face.hair)
    if face.style == "mohawk":
        c.rect(15, 0, 4, 7, face.hair)
        c.rect(16, 0, 2, 7, f"{face.hair}.light")
    if face.style == "bald":
        c.px(14, 4, "#f2c890")
        c.px(15, 4, "#f2c890")

    if top == "beanie":
        oval(c, 17, 6.5, 7.5, 6.5, colour, rows=(0, 6))
        c.rect(10, 5, 15, 2, f"{colour}.dark")
        oval(c, 17, 0.5, 2, 1.5, f"{colour}.light")
    elif top == "bucket":
        c.rect(11, 1, 13, 5, colour)
        c.rect(8, 5, 19, 2, f"{colour}.dark")
    elif top == "cap":
        oval(c, 17, 6.5, 7, 4.5, colour, rows=(0, 6))
        c.rect(23, 5, 5, 2, f"{colour}.dark")
        c.rect(10, 6, 2, 3, face.hair)
    elif top == "headphones":
        c.rect(11, 1, 13, 2, colour)
        c.rect(9, 3, 2, 5, colour)
        c.rect(24, 3, 2, 5, colour)
        c.rect(8, 8, 3, 5, f"{colour}.dark")
        c.rect(24, 8, 3, 5, f"{colour}.dark")

    eyes = face.eyes
    if eyes in ("dots", "round", "square", "camera"):
        c.rect(14, 10, 1, 2, INK)
        if eyes != "camera":
            c.rect(20, 10, 1, 2, INK)
    if eyes in ("round", "square"):
        rim = "white" if eyes == "round" else INK
        for x0 in (12, 18):
            c.box(x0, 8, 5, 5, rim)
            if eyes == "round":
                for dx, dy in ((0, 0), (4, 0), (0, 4), (4, 4)):
                    c.px(x0 + dx, 8 + dy, tone)
        c.px(17, 9, rim)
    elif eyes == "shades":
        c.rect(12, 9, 5, 3, INK)
        c.rect(18, 9, 5, 3, INK)
        c.px(17, 9, INK)
        c.px(13, 9, "dim")
        c.px(19, 9, "dim")
    elif eyes == "wink":
        c.rect(14, 10, 1, 2, INK)
        c.rect(19, 11, 3, 1, INK)
    elif eyes == "camera":
        c.rect(17, 6, 12, 8, "#2b2f3a")
        c.rect(18, 5, 4, 1, "#2b2f3a")
        c.rect(26, 5, 2, 1, "muted")
        oval(c, 22.5, 10, 3, 3, "#0d0f14")
        c.px(21, 9, "muted")
        c.rect(15, 12, 3, 3, tone)

    mouth = face.mouth
    if mouth in ("smile", "tongue"):
        for x, y in ((15, 14), (16, 15), (17, 15), (18, 15), (19, 14)):
            c.px(x, y, INK)
        if mouth == "tongue":
            c.rect(17, 16, 2, 1, "orange.light")
    elif mouth == "grin":
        c.rect(15, 14, 5, 2, "white")
        c.rect(15, 16, 5, 1, shade)
    elif mouth == "beard":
        oval(c, 17, 15.5, 6.5, 4, face.hair, rows=(13, 22))
        c.rect(15, 15, 5, 1, tone)
    elif mouth == "moustache":
        c.rect(14, 13, 7, 2, face.hair)
        c.px(13, 12, face.hair)
        c.px(21, 12, face.hair)
        c.rect(16, 16, 3, 2, INK)
    if face.freckles:
        for x, y in ((13, 12), (14, 13), (20, 12), (21, 13)):
            c.px(x, y, shade)
    return c


def silhouette():
    """The viewer's frame: the default profile picture, a head and shoulders in outline grey, waiting for a face."""
    c = w.canvas(*FRAME)
    c.rect(0, 0, *FRAME, "bg")
    oval(c, 17, 26, 11, 7.5, "line")
    oval(c, 17, 9.5, 5, 6, "line")
    return c


_portraits = {}


def frame_picture(face):
    """A frame's picture: a photographer, or the viewer's silhouette for None."""
    if face not in _portraits:
        _portraits[face] = portrait(face) if face else silhouette()
    return _portraits[face]


def burst():
    first, last, every = SHEET["burst"]
    return [first + i * every for i in range(round((last - first) / every))]


def ringed_centre():
    """The centre of the viewer's frame, which the marker rings."""
    row, x = next((row, x) for row, frames in enumerate(STRIPS) for x, k in frames if k == RINGED)
    return STAGE.x + x + FRAME[0] / 2, STRIP_YS[row] + FRAME[1] / 2


def contact(c, b):
    """Bar 5: a contact sheet, two strips of 3:2 film running off both edges of the stage on their film base, with
    their sprocket holes, so it reads as a roll of photographers rather than a count. The ten whole frames are taken
    one a sixteenth to a motor drive's burst, each flashing white: nine photographers, and the viewer's frame, empty
    but for the default profile picture; then a white marker rings that one, the way a frame is marked on a contact
    sheet."""
    header(c)
    shots = burst()
    edges = iter(EDGE_FACES)
    for sy, frames in zip(STRIP_YS, STRIPS):
        strip = c.sub(STAGE.w, FRAME[1] + 12, bg="shadow")
        strip.hline(0, 0, STAGE.w, "line")
        strip.hline(0, strip.h - 1, STAGE.w, "line")
        for hx in range(2, STAGE.w, 6):
            strip.rect(hx, 2, 3, 2, "dim")
            strip.rect(hx, strip.h - 4, 3, 2, "dim")
        for x, k in frames:
            if k is None:
                picture_ = frame_picture(next(edges))
            elif b < shots[k]:
                continue
            elif b < shots[k] + 2 / PER_BEAT:
                strip.rect(x, 6, *FRAME, "white")
                continue
            else:
                picture_ = frame_picture(FACES[k])
            strip.paste(picture_, x, 6)
            strip.box(x, 6, *FRAME, "dim")
        c.paste(strip, STAGE.x, sy - 6)
    p = w.between(b, CUE["ring"], CUE["ring"] + 0.25)
    if p > 0:
        ring(c, *ringed_centre(), p)
    w.caption(c, LINES["sheet"])
    return []


def ring(c, cx, cy, p):
    """A white marker's ring, two pixels thick and about 46 × 36, drawn round from the top right in whole pixels
    as far as `p` of the way, its ends crossing where it started."""
    turn = 2 * math.pi * (1 + 0.08)
    start = -math.pi / 4
    steps = 140
    for i in range(int(steps * min(1.0, p)) + 1):
        a = start - turn * i / steps
        wobble = 1 + 0.03 * math.sin(3 * a + 1.1)
        x = round(cx + 23 * wobble * math.cos(a))
        y = round(cy + 18 * wobble * math.sin(a))
        c.rect(x - 1, y - 1, 2, 2, "white")


# ---------------------------------------------------------------- bars 6 to 8: the end card

def end_card(c, b):
    """The end card, as the series': the lamp comes on, its light spreading in six steps over the beat, with the
    end line in the caption's place; then the address in its place from the call to action's cue; the light
    blooms out a step and settles back on the last hit; then everything dissolves into the wall, gone by the
    last frame, which is frame 0's wall."""
    light = math.ceil(6 * w.ease(w.between(b, CUE["endLine"], CUE["endLine"] + 1))) / 6
    bloom = math.ceil(3 * math.sin(math.pi * w.between(b, CUE["lastHit"], CUE["lastHit"] + 1))) / 3
    c.glow(c.w / 2, LAMP_Y, 120 * (0.4 + 0.6 * light) + 10 * bloom, "#2a0e12", amount=0.9 * light, levels=4)
    c.glow(c.w / 2, LAMP_Y, 52 + 6 * bloom, "red.dark", amount=0.35 * light, levels=3)
    w.lamp(c, c.w / 2, LAMP_Y)
    w.caption(c, LINES["endLine"] if b < CUE["cta"] else LINES["cta"])
    last = (FRAMES - 1) / PER_BEAT
    gone = w.between(b, CUE["fade"], last)
    if gone > 0:
        c.dissolve(min(1.0, gone), "bg")
    return []


def frame(c, b, hook="pick"):
    """The picture at beat b, drawn on c, with `hook`'s words in the first bar. All pixel art, so no overlays."""
    if b < CUE["dashboard"]:
        opening(c, b, hook)
        return []
    if b < CUE["drop"]:
        return dashboard(c, b)
    if b < CUE["sheet"]:
        return post(c, b)
    if b < CUE["endLine"]:
        return contact(c, b)
    return end_card(c, b)


# ---------------------------------------------------------------- its sounds

def pan(x):
    return round((x / w.W - 0.5) * 0.8, 2)


def sounds():
    """Each sound on screen, (beat, kind, pan): the lamp's light rushing into the mark, each drag's press, ticks
    and release with its knob, the roadmap opening, the row's press and its lift, the developer washing over the
    print, the strip landing, a shutter for each frame of the burst, the marker's squeak and the lamp's switch."""
    _, (mx, _) = header_at(w.canvas())
    out = [(CUE["dashboard"], "rise", pan(mx))]
    for (name, target), (press, *ticks, release) in DRAGS:
        out += [(press, "press", pan(knob_x(name, 0))), (release, "release", pan(knob_x(name, target)))]
        out += [(t, "tick", pan(knob_x(name, value_at(name, t)))) for t in ticks]
    out.append((CUE["roadmap"], "unroll", pan(BASIC.cx)))
    out += [(CUE["pickPress"], "press", pan(BASIC.x + 52)), (CUE["pick"], "release", pan(BASIC.x + 52)),
            (CUE["pick"], "lift", pan(150))]
    out.append((CUE["drop"], "wash", pan(PRINT.cx)))
    out.append((CUE["credit"], "lands", pan(STRIP.cx)))
    shot_x = {k: STAGE.x + x + FRAME[0] // 2 for frames in STRIPS for x, k in frames if k is not None}
    out += [(at, "shutter", pan(shot_x[k])) for k, at in enumerate(burst())]
    out.append((CUE["ring"], "marker", pan(ringed_centre()[0])))
    out.append((CUE["endLine"], "switch", 0.0))
    return sorted(out)


# ---------------------------------------------------------------- the storyboard

def at(b):
    return lambda c: frame(c, b)


def words(lines):
    return " / ".join([lines] if isinstance(lines, str) else lines)


PANELS = [
    w.Panel(1, 0.0, at(3.9), words(HOOKS["pick"]),
            "A deep hit and its sub on the first frame, a drone and a pad swelling with the lamp's warmth, a kick "
            "muffled as if through a wall, and the arpeggio growing out of nothing from the third beat."),
    w.Panel(2, 2.4, at(6.6), words(LINES["dashboard"]),
            "The first hit: the kick, the bass and the arpeggio, and air rushing up with the lamp into the mark; a "
            "press, two ticks and a release for each slider."),
    w.Panel(3, 4.8, at(10.6), words(LINES["roadmap"]) + ", then " + LINES["pick"],
            "The full beat with its gated snare and air as the roadmap opens; the press, then a two-note lift as the "
            "row rises; falling toms into the stop."),
    w.Panel(4, 7.2, at(14.6), words(LINES["drop"]) + ", then " + LINES["handle"],
            "The drop, the loudest bar: the boom, the low brass, the chord and the series' glass sting, a paper wash "
            "under the develop, and a soft landing as the strip arrives."),
    w.Panel(5, 9.6, at(19.6), words(LINES["sheet"]),
            "The groove holds; ten shutters a sixteenth apart as the frames are laid out, then a marker's squeak."),
    w.Panel(6, 12.0, at(21.5), words(LINES["endLine"]),
            "A switch as the lamp comes on, a low swell as its light spreads, and the closing phrase."),
    w.Panel(7, 14.4, at(25.5), words(LINES["cta"]), "A soft crash as the address comes in, over the dominant chord."),
    w.Panel(8, 16.8, at(30.6), words(LINES["cta"]) + ", fading",
            "The last hit on the tonic with a smaller boom, then the last chord dies away as the picture fades."),
]
