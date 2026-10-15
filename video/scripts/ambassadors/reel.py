"""
The ambassadors reel (docs/plans/2026-10-15-ambassadors-promo.md): Redlamp's ambassador programme told in four
acts, in the look of the feature videos, under the header REDLAMP · AMBASSADORS, in eight bars at 100 BPM.

1. What this is: the hook names the programme over the lamp warming, as the opener's first bar does, re-timed to
   the reel's grid.
2. Why it matters: on the first hit the lamp rises into the header's mark as a roadmap fills the stage and the
   viewer's pick lifts out of it; then a print comes up out of white as a post with the viewer's handle under it.
3. Why Redlamp needs you: a roll of film, dark but for the frame of the one person who makes Redlamp, fills with
   photographers on the drop, one frame left empty and ringed for the viewer.
4. How to apply: an edit made on the street at dusk, then the address over the lamp, fading to the wall the reel
   loops back to.

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

STAGE = w.Rect(4, 104, 208, 183)
ROADMAP = w.Rect(4, 106, 208, 180)
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
INK = "#17110f"

# The lamp takes the half beat after the first hit to rise into the header's mark, and the roadmap develops in
# over the same half beat.
MOVE = 0.5
# Labels develop in over two frames.
POP = 2 / PER_BEAT


def between(b, start, end):
    return w.between(b, start, end)


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
    t = w.ease(between(b, CUE["roadmap"], CUE["roadmap"] + MOVE))
    _, (mx, my) = header_at(c)
    cx, cy = c.w / 2 + (mx - c.w / 2) * t, w.LAMP_Y + (my - w.LAMP_Y) * t
    r = w.LAMP_R + (4.5 - w.LAMP_R) * t
    warm = warmth(b)
    c.glow(cx, cy, (30 + 62 * warm) * (1 - 0.8 * t), "red", amount=0.5 * warm * (1 - t), levels=3)
    w.safelight(c, cx, cy, r, warm)


# ---------------------------------------------------------------- act 1

def opening(c, b, hook):
    """Bar 1: the opener's first bar, its 100 frames at 72 BPM drawn into the reel's first 72, so the hook stands
    over the lamp warming in the dark, and its last frame is the cover every episode has."""
    w.opener(c, b * w.OPENER_PER_BEAT, {"title": FEATURE}, HOOKS[hook], FEATURE)


# ---------------------------------------------------------------- act 2: the roadmap

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
# The bars where the names would be; the picked row's is short, so YOUR PICK has room beside it.
ROW_BARS = [118, 28, 92, 136]
ROW_STEP = 36
PICKED = 1


def roadmap_rows(c, p, b):
    """The roadmap's rows at twice the size of the series' panels, in the panel's content rect `p`: the picked row lit
    while it's pressed, then lifted out of the list with a shadow and a gold rim, and YOUR PICK beside it."""
    names = COPY.get("rows") or []
    rows = []
    for i, (art, accent) in enumerate(ROW_SPRITES):
        y = p.y + 8 + i * ROW_STEP
        lifted = i == PICKED and b >= CUE["pick"]
        if i == PICKED and CUE["pickPress"] <= b < CUE["pick"]:
            c.rect(p.x - 2, y - 4, p.w + 4, 24, "raised")
        if lifted:
            y -= 3
            c.rect(p.x, y - 2, p.w + 2, 24, "shadow")
            c.rect(p.x - 3, y - 5, p.w + 4, 24, "raised")
            c.box(p.x - 3, y - 5, p.w + 4, 24, "gold")
        c.sprite(p.x + 2, y, art, {"#": f"{accent}.light" if lifted else accent}, scale=2)
        if i < len(names):
            c.text(p.x + 26, y + 4, names[i], "white" if lifted else "text", font="large")
        else:
            c.rect(p.x + 26, y + 6, ROW_BARS[i], 5, "muted" if lifted else "line")
        if lifted:
            w.appear(c, between(b, CUE["pick"], CUE["pick"] + POP),
                     lambda c, y=y: c.text(176, y + 1, LINES["pick"], "gold", font="large", scale=2, align="right"))
        rows.append(w.Rect(p.x, y, p.w, 16))
    return rows


def glide(a, z, t):
    return round(a[0] + (z[0] - a[0]) * t), round(a[1] + (z[1] - a[1]) * t)


def roadmap(c, b):
    """Bar 2: the header, and a roadmap filling the stage, which develops in under the lamp as it rises into the
    header's mark. The pointer comes in from the right to the second row, presses it and lets it go on the pick."""
    coming = b < CUE["roadmap"] + MOVE
    before = c.img.copy()
    header(c, mark=not coming)
    p = c.panel(*ROADMAP, "ROADMAP", color="sky")
    rows = roadmap_rows(c, p, b)
    if coming:
        w.develop(c, before, between(b, CUE["roadmap"], CUE["roadmap"] + MOVE))
        rising(c, b)
    if b >= CUE["roadmap"] + 0.5:
        row = rows[PICKED]
        target = (row.x + 60, row.y + 8)
        at = glide((w.W + 6, row.y + 30), target, w.ease(between(b, CUE["roadmap"] + 0.5, CUE["pickPress"])))
        w.pointer(c, *at, pressed=CUE["pickPress"] <= b < CUE["pick"])
    w.caption(c, LINES["roadmap"])
    return []


# ---------------------------------------------------------------- act 2: the post

def strip(c, x, y):
    """The credit strip under the print: the Redlamp mark in white, so it isn't a second red light, and the
    viewer's handle."""
    c.rect(x, y, STRIP.w, STRIP.h, "shadow")
    c.sprite(x + 4, y + 2, w.LAMP_MARK[0], {"o": "white", "r": "shadow", "l": "white"})
    c.text(x + 17, y + 3, LINES["handle"], "white", font="large")


def post(c, b):
    """Bar 3: the stage turns into a post, whose print comes up out of white into the street as edited over the
    beat, and the credit strip slides up out of its bottom edge and lands on the credit's cue. Nothing on the post
    counts anything."""
    header(c)
    c.rect(*POST, "panel")
    c.box(*POST, "line")
    c.rect(*PRINT, PAPER)
    before = c.img.copy()
    c.img.paste(picture(TARGET, (PRINT.w, PRINT.h)), (PRINT.x, PRINT.y))
    w.develop(c, before, w.ease(between(b, CUE["print"], CUE["developed"])))
    if b < CUE["print"] + 0.5:
        c.sparkles(PRINT.x, PRINT.y, PRINT.w, PRINT.h, 26, ["white", "gold.light"], seed=int(b * PER_BEAT))
    slide = between(b, CUE["credit"] - 0.5, CUE["credit"])
    if slide > 0:
        window = c.sub(STRIP.w, POST.y2 - 1 - STRIP.y, bg="panel")
        strip(window, 0, round((1 - w.ease(slide)) * window.h))
        c.paste(window, STRIP.x, STRIP.y)
    w.caption(c, LINES["print"])
    return []


# ---------------------------------------------------------------- act 3: the roll

FRAME = (34, 23)
STRIP_YS = [160, 203]
# Each strip's frames, from the stage's left edge, running off both its edges: (x, what it holds). The maker's frame
# is lit from the bar's first beat, the frames at the edges come up on the drop, and the burst takes the others one
# a sixteenth, by its index.
STRIPS = [
    [(-16, "edge"), (22, 0), (60, 1), (98, "maker"), (136, 2), (174, 3)],
    [(6, 4), (44, 5), (82, 6), (120, 7), (158, 8), (196, "edge")],
]
# The burst's frame left for the viewer, which the marker rings.
YOU = 5


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


# The photographers in the burst's order, and None for the viewer's frame. Nothing in them is red, so the lamp stays
# the picture's one red light.
FACES = [
    Face(("#7a4a2a", "#5f381f"), INK, "afro", None, "round", "grin", "violet.dark", "gold"),
    Face(("#e0ac7e", "#c08c5f"), "#6b4226", "short", "beanie:gold", "dots", "beard", "sky.dark", "green"),
    Face(("#c68a5d", "#a66d43"), "cyan", "mohawk", None, "wink", "tongue", "gold.dark", "line"),
    Face(("#a5683f", "#86512f"), INK, "short", "bucket:green", "shades", "smile", "cyan.dark", "orange"),
    Face(("#f3d6bd", "#d9b496"), "#e8c66a", "long", "headphones:violet", "dots", "smile", "blue.dark", "sky"),
    None,
    Face(("#d9a066", "#b9824c"), "#a3a8b0", "bald", None, "dots", "moustache", "orange.dark", "cyan"),
    Face(("#f1c9a5", "#d4a682"), "#c8642a", "short", "cap:sky", "dots", "grin", "violet.dark", "gold", freckles=True),
    Face(("#5a3620", "#432716"), "violet.light", "curly", None, "square", "smile", "gold.dark", "green"),
]
# The photographers half in view at the strips' edges: a camera held up to the eye, and a bun and shades.
EDGE_FACES = [
    Face(("#f1c9a5", "#d4a682"), "#3b2416", "bun", None, "camera", "smile", "green.dark", "violet"),
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


def maker():
    """The one person who makes Redlamp, head and shoulders behind an open laptop in a dark room, lit by its
    screen. No logo on the lid, and nothing red."""
    c = w.canvas(*FRAME)
    c.rect(0, 0, *FRAME, "#0b0f1a")
    oval(c, 17, 13, 16, 11, "#141c30")
    tone, shade = "#e6bc96", "#bf9370"
    oval(c, 17, 26, 12, 7.5, "#34405a")
    c.rect(15, 15, 5, 3, shade)
    oval(c, 17, 9.5, 6.5, 7.5, shade)
    oval(c, 16.5, 9, 6, 7.2, tone)
    for y in (9, 10):
        c.px(10, y, shade)
        c.px(24, y, shade)
    oval(c, 17, 5.5, 7, 4.5, "#2a1d16", rows=(0, 5))
    c.rect(14, 10, 1, 1, INK)
    c.rect(20, 10, 1, 1, INK)
    c.rect(13, 9, 3, 1, "#2a1d16")
    c.rect(19, 9, 3, 1, "#2a1d16")
    c.rect(5, 14, 24, 9, "#6b778f")
    c.rect(5, 14, 24, 1, "#a7b1c6")
    c.rect(5, 22, 24, 1, "#4a5468")
    return c


def silhouette():
    """The viewer's frame: the default profile picture, a head and shoulders in outline grey, waiting for a face."""
    c = w.canvas(*FRAME)
    c.rect(0, 0, *FRAME, "bg")
    oval(c, 17, 26, 11, 7.5, "line")
    oval(c, 17, 9.5, 5, 6, "line")
    return c


_pictures = {}


def frame_picture(what):
    """A frame's picture: a photographer, the maker, or the viewer's silhouette for None."""
    if what not in _pictures:
        _pictures[what] = maker() if what == "maker" else portrait(what) if what else silhouette()
    return _pictures[what]


def burst():
    first, last, every = SHEET["burst"]
    return [first + i * every for i in range(round((last - first) / every))]


def holds(role, edges):
    """When a frame comes up, and its picture: the maker's at the start of the act, the edges' on the drop, and
    each of the others on its shot of the burst."""
    if role == "maker":
        return CUE["onePerson"], frame_picture("maker")
    if role == "edge":
        return CUE["drop"], frame_picture(next(edges))
    return burst()[role], frame_picture(FACES[role])


def you_centre():
    """The centre of the viewer's frame, which the marker rings."""
    row, x = next((row, x) for row, frames in enumerate(STRIPS) for x, role in frames if role == YOU)
    return STAGE.x + x + FRAME[0] / 2, STRIP_YS[row] + FRAME[1] / 2


def roll(c, b):
    """Bars 4 and 5: two strips of film running off both edges of the stage, so it reads as a roll rather than a
    count. Every frame is dark but the maker's, which comes up as the act begins; on the drop the others come up to
    a motor drive's burst, each flashing white, until every frame holds a photographer but the viewer's, empty but
    for the default profile picture, which a white marker then rings."""
    header(c)
    edges = iter(EDGE_FACES)
    for sy, frames in zip(STRIP_YS, STRIPS):
        film = c.sub(STAGE.w, FRAME[1] + 12, bg="shadow")
        film.hline(0, 0, STAGE.w, "line")
        film.hline(0, film.h - 1, STAGE.w, "line")
        for hx in range(2, STAGE.w, 6):
            film.rect(hx, 2, 3, 2, "dim")
            film.rect(hx, film.h - 4, 3, 2, "dim")
        for x, role in frames:
            at, picture_ = holds(role, edges)
            if b < at:
                film.rect(x, 6, *FRAME, "bg")
                film.box(x, 6, *FRAME, "line")
            elif b < at + POP:
                film.rect(x, 6, *FRAME, "white")
            else:
                film.paste(picture_, x, 6)
                film.box(x, 6, *FRAME, "text" if role == "maker" and b < CUE["drop"] else "dim")
        c.paste(film, STAGE.x, sy - 6)
    p = between(b, CUE["ring"], CUE["ring"] + 0.25)
    if p > 0:
        ring(c, *you_centre(), p)
    w.caption(c, LINES["onePerson"] if b < CUE["drop"] else LINES["needs"])
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


# ---------------------------------------------------------------- act 4: the editor

def basic(c, b):
    """The Basic panel as meters, the one being dragged lit. Returns each knob's place."""
    active = next((name for (name, _), (press, *_, release) in DRAGS if press <= b < release), None)
    rows = []
    for s in SLIDERS:
        v = value_at(s.label, b)
        rows.append((s.label, s.accent, value_text(s.reach, v), 0.5 + v / (2 * s.reach), s.label == active))
    return w.meters(c, BASIC, rows, right="4 SLIDERS", track=TRACK)


def knob_x(label, v):
    """Where a meter's knob is at value v, as w.meters places it."""
    reach = next(s.reach for s in SLIDERS if s.label == label)
    t0, t1 = BASIC.x + TRACK[0], BASIC.x + TRACK[1]
    return round(t0 + (0.5 + v / (2 * reach)) * (t1 - t0))


def editor(c, b):
    """Bar 6: the editor, with the street the viewer saw as a print, as opened, its histogram, its level and the
    Basic panel's meters; the pointer drags Exposure, then Vibrance, and the street brightens and takes its colour."""
    header(c)
    img = picture({name: value_at(name, b) for name, _ in DRAGGED}, (PHOTO_PANEL.w - 8, PHOTO_PANEL.h - 16))
    w.photo_panel(c, PHOTO_PANEL, img, b, FILE, horizon=KERB)
    w.histogram(c, img, HIST)
    c.seg_column(*LEVEL, min(1.0, float(np.asarray(img).mean()) / 255 * 2.2), "gold", seg=2, gap=1)
    knobs = basic(c, b)
    (first, _), (press1, *_, release1) = DRAGS[0]
    (second, _), (press2, *_, release2) = DRAGS[1]
    if b < release1:
        at, pressed = knobs[first], press1 <= b
    elif b < press2:
        at, pressed = glide(knobs[first], knobs[second], w.ease(between(b, release1, press2))), False
    else:
        at, pressed = knobs[second], press2 <= b < release2
    w.pointer(c, *at, pressed=pressed)
    w.caption(c, LINES["editor"])
    return []


# ---------------------------------------------------------------- act 4: the end card

def end_card(c, b):
    """Bars 7 and 8: the lamp comes on, its light spreading in six steps over the beat, with the address in the
    caption's place above it; the light blooms out a step and settles back on the last hit; then everything
    dissolves into the wall, gone by the last frame, which is frame 0's wall."""
    light = math.ceil(6 * w.ease(between(b, CUE["cta"], CUE["cta"] + 1))) / 6
    bloom = math.ceil(3 * math.sin(math.pi * between(b, CUE["lastHit"], CUE["lastHit"] + 1))) / 3
    c.glow(c.w / 2, LAMP_Y, 120 * (0.4 + 0.6 * light) + 10 * bloom, "#2a0e12", amount=0.9 * light, levels=4)
    c.glow(c.w / 2, LAMP_Y, 52 + 6 * bloom, "red.dark", amount=0.35 * light, levels=3)
    w.lamp(c, c.w / 2, LAMP_Y)
    w.caption(c, LINES["cta"])
    last = (FRAMES - 1) / PER_BEAT
    gone = between(b, CUE["fade"], last)
    if gone > 0:
        c.dissolve(min(1.0, gone), "bg")
    return []


def frame(c, b, hook=None):
    """The picture at beat b, drawn on c, with `hook`'s words in the first bar. All pixel art, so no overlays."""
    if b < CUE["roadmap"]:
        opening(c, b, hook or next(iter(HOOKS)))
        return []
    if b < CUE["print"]:
        return roadmap(c, b)
    if b < CUE["onePerson"]:
        return post(c, b)
    if b < CUE["editor"]:
        return roll(c, b)
    if b < CUE["cta"]:
        return editor(c, b)
    return end_card(c, b)


# ---------------------------------------------------------------- its sounds

def pan(x):
    return round((x / w.W - 0.5) * 0.8, 2)


def sounds():
    """Each sound on screen, (beat, kind, pan): the lamp's light rushing into the mark, the row's press and its
    lift, the developer washing over the print, the strip landing, a shutter as the maker's frame comes up and one
    for each frame of the burst, the marker's squeak, each drag's press, ticks and release with its knob, and the
    lamp's switch."""
    _, (mx, _) = header_at(w.canvas())
    row_x = ROADMAP.x + 4 + 60
    out = [(CUE["roadmap"], "rise", pan(mx)), (CUE["pickPress"], "press", pan(row_x)),
           (CUE["pick"], "release", pan(row_x)), (CUE["pick"], "lift", pan(150)),
           (CUE["print"], "wash", pan(PRINT.cx)), (CUE["credit"], "lands", pan(STRIP.cx))]
    shot_x = {role: STAGE.x + x + FRAME[0] // 2 for frames in STRIPS for x, role in frames}
    out.append((CUE["onePerson"], "shutter", pan(shot_x["maker"])))
    out += [(at, "shutter", pan(shot_x[k])) for k, at in enumerate(burst())]
    out.append((CUE["ring"], "marker", pan(you_centre()[0])))
    for (name, target), (press, *ticks, release) in DRAGS:
        out += [(press, "press", pan(knob_x(name, 0))), (release, "release", pan(knob_x(name, target)))]
        out += [(t, "tick", pan(knob_x(name, value_at(name, t)))) for t in ticks]
    out.append((CUE["cta"], "switch", 0.0))
    return sorted(out)


# ---------------------------------------------------------------- the storyboard

def at(b):
    return lambda c: frame(c, b)


def words(lines):
    return " / ".join([lines] if isinstance(lines, str) else lines)


LEAD = next(iter(HOOKS))
PANELS = [
    w.Panel(1, 0.0, at(3.9), words(HOOKS[LEAD]),
            "Act 1. A deep hit and its sub on the first frame, a drone and a pad swelling with the lamp's warmth, a kick "
            "muffled as if through a wall, and the arpeggio growing out of nothing from the third beat."),
    w.Panel(2, 2.4, at(6.6), words(LINES["roadmap"]) + ", then " + LINES["pick"],
            "Act 2. The first hit: the kick, the bass and the arpeggio, and air rushing up with the lamp into the mark; "
            "the row's press, then a two-note lift as it rises."),
    w.Panel(3, 4.8, at(10.6), words(LINES["print"]) + ", then " + LINES["handle"],
            "The full beat and the riff come in, with the series' glass sting and the developer's wash as the print "
            "comes up, and a soft landing as the strip arrives."),
    w.Panel(4, 7.2, at(14.6), words(LINES["onePerson"]),
            "Act 3. The music thins to the drone, a muffled kick and the riff's first notes; a shutter as the maker's "
            "frame comes up; a riser and a snare roll into the stop."),
    w.Panel(5, 9.6, at(19.6), words(LINES["needs"]),
            "The drop, the loudest bar: the boom, the low brass, the chord and a crash, nine shutters a sixteenth apart "
            "as the roll fills, then the marker's squeak."),
    w.Panel(6, 12.0, at(22.6), words(LINES["editor"]),
            "Act 4. The groove holds and the closing phrase begins; a press, two ticks and a release for each slider."),
    w.Panel(7, 14.4, at(25.5), words(LINES["cta"]),
            "A switch as the lamp comes on, a low swell as its light spreads, and a soft crash over the dominant chord."),
    w.Panel(8, 16.8, at(30.6), words(LINES["cta"]) + ", fading",
            "The last hit on the tonic with a smaller boom, then the last chord dies away as the picture fades."),
]
