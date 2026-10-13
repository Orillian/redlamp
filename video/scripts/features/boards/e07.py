"""
E07, Speed, in the series' look (boards/e01.py): a slider change rendering in 1.8 ms and a 24 MP raw
opening in 0.16 s, measured on an M1 Ultra. The editor is drawn as E01's dashboard is: a raw in the photo
panel as pixel art, its histogram and level under it, a row of two readouts, and a bottom panel that holds
the Basic panel's meters, then the filmstrip, then the Mac the figures were measured on.

The pointer drags Exposure up to +1.00 a step a beat, the photo following each step, and back down to
-0.50, while the RENDER readout stays at 1.8 ms and the EXPOSURE readout beside it follows the knob. Then
it clicks another raw in the filmstrip, which comes up over the frames its open takes, and the OPEN readout
comes up at 0.16 s in the EXPOSURE readout's place; the bottom panel turns to the M1 Ultra's chip and the
Release build. The result is the raw that opened filling the stage as Exposure moves under it, a render a
beat.

The photos are the Nikon Z 6 tripod shoot in the repository's fixtures (tests/fixtures/shoots/nikon-z6),
eight frames of a paper star, a toy monkey and a globe on a table. The raw that opens, and that the result
shows, is DSC_0750.NEF, 6064 x 4040 (24.5 MP); the one open before it is the next frame, DSC_0751.NEF, the
same size, so the open shows as another raw coming up as opened. Every picture of them is Redlamp's render
with the redlamp CLI, kept in public/features/e07/results/: as opened, and at each Exposure the knob passes
through, reduced to pixel art with a palette of the photos' own colours, as E08's is. The figures are the
README's performance card (drawn from docs/performance/history.jsonl), read from the README; the words say
them too, so a new figure stops the board until the words are reviewed.
"""

import math
import re
import subprocess
import sys
from functools import cache
from pathlib import Path
from typing import NamedTuple

import numpy as np
from PIL import Image

from features import results
from features import world as w
from pixelkit.art import oklab

EPISODE = w.episode("e07")
FEATURE = "SPEED"
CUE = w.CUE
FOLDER = w.VIDEO / "public/features/e07/results"

# The README's performance card: a slider change's render at Fit and a 24 MP raw's open, and the Mac and the
# build they were measured with.
README = (w.REPO / "README.md").read_text()
RENDER_MS, OPEN_MS = map(float, re.search(r"([\d.]+) ms to render a slider change; ([\d.]+) ms to open a 24 MP raw",
                                          README).groups())
MAC, BUILD = re.search(r"on an Apple (M1 Ultra) with a (Release build)", README).groups()
if (RENDER_MS, OPEN_MS) != (1.8, 160.0):
    sys.exit(f"The README's performance card now gives {RENDER_MS:g} ms to render a slider change and {OPEN_MS:g} ms to "
             "open a 24 MP raw, where E07's words say 1.8 ms and 0.16 s: have the words reviewed before drawing it.")
RENDER, OPEN = f"{RENDER_MS:g} MS", f"{OPEN_MS / 1000:g} S"


def fixture(path):
    """A file in the repository's test fixtures, which a worktree has only in the main checkout."""
    found = w.REPO / "tests/fixtures" / path
    if not found.exists():
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=w.REPO,
                                capture_output=True, text=True, check=True).stdout.strip()
        found = Path(common).parent / "tests/fixtures" / path
    return found


SHOOT = fixture("shoots/nikon-z6")
FRAMES = sorted(SHOOT.glob("DSC_*.NEF"))
# The raw open from the first frame, and the raw the click opens, which the result shows.
FIRST, RAW = SHOOT / "DSC_0751.NEF", SHOOT / "DSC_0750.NEF"
PHOTO = ("THE NIKON Z 6 TRIPOD SHOOT IN THE REPOSITORY'S FIXTURES (TESTS/FIXTURES/SHOOTS/NIKON-Z6): DSC_0751.NEF OPEN IN "
         "BARS 1 TO 3, DSC_0750.NEF (6064 X 4040, 24.5 MP) OPENED FROM THE FILMSTRIP IN BAR 4 AND SHOWN IN THE RESULT, THE "
         "SHOOT'S EIGHT FRAMES IN THE FILMSTRIP. EVERY PICTURE IS REDLAMP'S OWN RENDER WITH THE CLI: AS OPENED, AND AT EACH "
         "EXPOSURE THE KNOB PASSES THROUGH; AS PIXEL ART WITH THE PHOTOS' OWN PALETTE. THE READOUTS ARE THE README'S "
         "PERFORMANCE CARD")

PHOTO_PANEL = w.Rect(4, 106, 208, 96)
RESULT_PANEL = w.Rect(4, 106, 208, 152)
HIST = w.Rect(4, 204, 208, 12)
# The readouts: RENDER, and beside it EXPOSURE's value, which OPEN takes the place of once the raw opens.
READOUT = w.Rect(4, 218, 89, 30)
BESIDE = w.Rect(95, 218, 91, 30)
BOTTOM = w.Rect(4, 250, 182, 37)
LEVEL = w.Rect(190, 222, 18, 61)
# Bar 6's Exposure meter under the photo, and its level beside it.
METER = w.Rect(4, 260, 182, 27)
METER_LEVEL = w.Rect(190, 263, 18, 23)
EDITOR = (PHOTO_PANEL.w - 8, PHOTO_PANEL.h - 16)
RESULT = (RESULT_PANEL.w - 8, RESULT_PANEL.h - 16)
TRACK = (44, 152)
# The filmstrip's thumbnails, the shoot's eight frames in a row.
THUMB, GAP = (19, 13), 3
THUMB_Y = BOTTOM.y + 16
# Exposure's reach either side of zero (ParameterSpec).
REACH = 5
TITLE = w.wrapped(EPISODE["title"].upper())


class Drag(NamedTuple):
    """The pointer presses a knob on `press`, moves it to each of `values` on its beat in `ticks`, and lets go
    on `release`."""
    press: float
    ticks: tuple
    values: tuple
    release: float


class Click(NamedTuple):
    press: float
    release: float


s1, s2, s3, s4 = (CUE[f"step{i}"] for i in range(1, 5))
# Exposure goes up to +1.00 a step a beat through the first step's bar, holds as the second step's words come
# up, and comes back down to -0.50 a step a beat; the photo is rendered at each value.
DRAG = Drag(s1, (s1 + 1, s1 + 2, s1 + 3, s2 + 1, s2 + 2, s2 + 3), (0.33, 0.67, 1.0, 0.5, 0.0, -0.5), s2 + 3.5)
# The pointer comes in from the right two beats before it presses Exposure's knob.
ENTER = s1 - 2
# A knob's step eases in over the frames before its beat and lands on it.
EASE = 3 / w.PER_BEAT
# The pointer moves to the raw over the three sixteenths before the beat it clicks it on.
MOVE = 0.75
CLICK = Click(s3 + 1, s3 + 1.5)
# The raw comes up over the frames the README's open takes, from the click.
OPENING = OPEN_MS / 1000 * w.FPS / w.PER_BEAT
# Bar 6: Exposure from the photo as opened up a step a beat, the second step on the flip.
RESULT_DRAG = Drag(CUE["result"], (CUE["result"] + 1, CUE["flip"], CUE["flip"] + 1), (0.5, 1.0, 1.5), CUE["flip"] + 1.5)
# A readout's clock lights for the frames after each change that it renders.
LIT = 4 / w.PER_BEAT
CAPTIONS = [(s1, "DRAG A SLIDER"), (s2, "1.8 MS PER CHANGE"), (s3, ["A 24 MP RAW OPENS", "IN 0.16 S"]),
            (s4, ["MEASURED ON", "AN M1 ULTRA"]), (CUE["result"], ["THE PHOTO FOLLOWS", "THE SLIDER"])]
APPEAR = 6 / w.PER_BEAT


# ---------------------------------------------------------------- the photos, from Redlamp

@cache
def render(raw, ev=0.0):
    """Redlamp's render of `raw` with Exposure at `ev`, 1024 pixels on its long edge: as opened at 0."""
    ev = round(ev, 2)
    if ev == 0:
        return results.render(raw, FOLDER, f"{raw.stem}-opened", size=1024)
    return results.render(raw, FOLDER, f"{raw.stem}-ev{ev:+.2f}", sets=(("basic.exposure", ev),), size=1024)


@cache
def thumbnail(raw):
    return results.render(raw, FOLDER, f"thumb-{raw.stem}", size=256)


# Where the editor's band across the photo starts, as a share of its height.
BAND = 0.23


def shown(img, size):
    """The part of a render a picture of `size` shows: a band across its whole width for the editor, from just
    over the monkey's head to the wagon's wheels, and its whole height for the result and the thumbnails."""
    iw, ih = img.size
    if size[0] * ih > size[1] * iw:
        h = round(iw * size[1] / size[0])
        top = min(ih - h, round(BAND * ih))
        box = (0, top, iw, top + h)
    else:
        wd = round(ih * size[0] / size[1])
        left = (iw - wd) // 2
        box = (left, 0, left + wd, ih)
    return img.crop(box).resize(size, Image.BOX)


@cache
def palette(colors=40):
    """The photos' own colours at every Exposure the video shows them at: the centres of their pixels' clusters in
    Oklab, so the star's orange and blue, the monkey's brown and the globe's blues keep a colour at each step."""
    shots = [shown(render(FIRST, v), EDITOR) for v in (0.0, *DRAG.values)] + [shown(render(RAW), EDITOR)]
    shots += [shown(render(RAW, v), RESULT) for v in (0.0, *RESULT_DRAG.values)]
    rgb = np.concatenate([np.asarray(img).reshape(-1, 3) for img in shots]).astype(np.float64)
    lab = oklab(rgb)

    def nearest(centres):
        return ((lab**2).sum(1)[:, None] - 2 * lab @ centres.T + (centres**2).sum(1)[None]).argmin(1)

    rng = np.random.default_rng(3)
    centres = lab[[rng.integers(len(lab))]]
    far = ((lab - centres[0]) ** 2).sum(1)
    while len(centres) < colors:
        centres = np.vstack([centres, lab[rng.choice(len(lab), p=far / far.sum())]])
        far = np.minimum(far, ((lab - centres[-1]) ** 2).sum(1))
    for _ in range(20):
        near = nearest(centres)
        centres = np.array([lab[near == k].mean(0) if (near == k).any() else centres[k] for k in range(colors)])
    near = nearest(centres)
    return list(dict.fromkeys(tuple(int(v) for v in np.rint(rgb[near == k].mean(0))) for k in range(colors)
                              if (near == k).any()))


@cache
def picture(raw, ev, size):
    """`raw` with Exposure at `ev`, at `size`, as pixel art."""
    return w.lock(shown(render(raw, ev), size), palette(), dither=0.15).convert("RGB")


@cache
def small(raw):
    return w.lock(shown(thumbnail(raw), THUMB), palette()).convert("RGB")


def level(img):
    """How bright the photo is, as the LED level, at 1.6 times its mean, so it climbs with each step of Exposure
    from -0.50 to +1.50 without reaching the top."""
    return min(1.0, float(np.asarray(img).mean()) / 255 * 1.6)


# ---------------------------------------------------------------- the drags and the click

def value_at(drag, b):
    """A drag's value at beat b, as its knob shows it, easing into each step over the frames before its beat."""
    v = 0.0
    for t, value in zip(drag.ticks, drag.values):
        if b >= t:
            v = value
        elif b > t - EASE:
            return v + (value - v) * w.ease((b - t + EASE) / EASE)
        else:
            break
    return v


def step_at(drag, b):
    """The value the photo shows at beat b: the drag's last step, which it follows on the step's beat."""
    landed = [value for t, value in zip(drag.ticks, drag.values) if t <= b]
    return landed[-1] if landed else 0.0


def changed(drag, b):
    """Whether one of the drag's steps has just landed, so its render has just been made."""
    return any(t <= b < t + LIT for t in drag.ticks)


def value_text(v):
    return "0.00" if round(v, 2) == 0 else f"{v:+.2f}"


def knob(rect, v):
    """Where a meter's knob is at value v, in a meters panel at `rect`."""
    t0, t1 = rect.x + TRACK[0], rect.x + TRACK[1]
    return round(t0 + (0.5 + v / (2 * REACH)) * (t1 - t0)), rect.y + 12 + 2 + 2


def thumb_xs():
    x = BOTTOM.x + 4 + (BOTTOM.w - 8 - (len(FRAMES) * (THUMB[0] + GAP) - GAP)) // 2
    return [x + i * (THUMB[0] + GAP) for i in range(len(FRAMES))]


def thumb_tip(raw):
    """Where the pointer's tip rests on a raw's thumbnail."""
    return thumb_xs()[FRAMES.index(raw)] + THUMB[0] // 2, THUMB_Y + THUMB[1] // 2


def opened(b):
    return b >= CLICK.press


def pointer_at(b):
    """Where the pointer's tip is at beat b and whether it's pressed, or None while it's off screen: it comes in
    from the right to Exposure's knob, drags it up and back down, rests, then moves to DSC_0750's thumbnail and
    clicks it; it goes with the bottom panel at the fourth step."""
    if b < ENTER or b >= s4:
        return None

    def glide(a, z, t):
        return round(a[0] + (z[0] - a[0]) * t), round(a[1] + (z[1] - a[1]) * t)

    if b < DRAG.press:
        start = (w.W + 6, knob(BOTTOM, 0)[1] + 6)
        return glide(start, knob(BOTTOM, 0), w.ease(w.between(b, ENTER, DRAG.press))), False
    rest = knob(BOTTOM, DRAG.values[-1])
    if b < CLICK.press - MOVE:
        return knob(BOTTOM, value_at(DRAG, b)) if b < DRAG.release else rest, b < DRAG.release
    tip = thumb_tip(RAW)
    if b < CLICK.press:
        return glide(rest, tip, w.ease(w.between(b, CLICK.press - MOVE, CLICK.press))), False
    return tip, b < CLICK.release


# ---------------------------------------------------------------- the readouts

def readout(c, r, title, colour, figure, *, right=None, lit=False):
    """A readout: its title in its accent and a note at its right, and the README's figure in the large font at
    twice its size beside a clock, which lights while a change renders."""
    p = c.panel(*r, title, color=colour, right=right, right_color="dim")
    width = 7 + 4 + c.measure(figure, "large", 2)
    x = p.x + (p.w - width) // 2
    c.icon(x, p.y + 4, "clock", f"{colour}.light" if lit else colour)
    c.text(x + 11, p.y, figure, "white", font="large", scale=2)


def exposure(c, r, b):
    """EXPOSURE's value as the knob shows it, in the large font at twice its size, lit while it's dragged."""
    p = c.panel(*r, "EXPOSURE", color="gold")
    lit = DRAG.press <= b < DRAG.release
    c.text(p.cx, p.y, value_text(value_at(DRAG, b)), "gold.light" if lit else "white", font="large", scale=2,
           align="center")


def readouts(c, b):
    readout(c, READOUT, "RENDER", "lime", RENDER, right="PER CHANGE", lit=changed(DRAG, b))
    if not opened(b):
        exposure(c, BESIDE, b)
        return
    w.appear(c, w.between(b, CLICK.press, CLICK.press + APPEAR),
             lambda c: readout(c, BESIDE, "OPEN", "orange", OPEN, right="24 MP RAW"))
    if b < CLICK.press + 0.5:
        c.sparkles(BESIDE.x - 2, BESIDE.y - 2, BESIDE.w + 4, BESIDE.h + 4, 8, ["orange.light", "white"],
                   seed=int(b * w.PER_BEAT))


# ---------------------------------------------------------------- the bottom panel

def basic(c, b):
    """Bars 1 to 3: the Basic panel's first sliders as meters, Exposure lit while it's dragged."""
    v, lit = value_at(DRAG, b), DRAG.press <= b < DRAG.release
    rows = [("EXPOSURE", "gold", value_text(v), 0.5 + v / (2 * REACH), lit), ("CONTRAST", "cyan", "0", 0.5, False)]
    w.meters(c, BOTTOM, rows, track=TRACK)


def filmstrip(c, b):
    """Bar 4: the shoot's eight frames, the one open ringed in the system accent; DSC_0750 lit while it's pressed."""
    c.panel(*BOTTOM, "FILMSTRIP", color="sky", right=f"{len(FRAMES)} PHOTOS", right_color="dim")
    chosen = RAW if opened(b) else FIRST
    for raw, x in zip(FRAMES, thumb_xs()):
        if raw == chosen:
            c.box(x - 1, THUMB_Y - 1, THUMB[0] + 2, THUMB[1] + 2, "sky.light" if b < CLICK.release and opened(b) else "sky")
        c.img.paste(small(raw), (x, THUMB_Y))


def measured(c, b):
    """Bar 5: the Mac the figures were measured on, its M1 Ultra's chip with its twenty cores, and the build."""
    p = c.panel(*BOTTOM, "MAC", color="violet")
    label = BUILD.upper()
    chip_w = c.measure(MAC.upper(), "large") + 14
    width = chip_w + 10 + c.measure(label, "large")
    x = p.x + (p.w - width) // 2
    c.chip(x, p.y + 2, chip_w, 17, MAC.upper(), "violet", cores=20)
    c.text(x + chip_w + 10, p.y + 7, label, "white", font="large")


def bottom(c, b):
    if b < s3:
        basic(c, b)
    elif b < s4:
        w.appear(c, w.between(b, s3, s3 + APPEAR), lambda c: filmstrip(c, b))
    else:
        w.appear(c, w.between(b, s4, s4 + APPEAR), lambda c: measured(c, b))
        if b < s4 + 0.5:
            c.sparkles(BOTTOM.x - 2, BOTTOM.y - 2, BOTTOM.w + 4, BOTTOM.h + 4, 10, ["violet.light", "white"],
                       seed=int(b * w.PER_BEAT))


# ---------------------------------------------------------------- the dashboard

def dashboard(c, b):
    """Bars 1 to 5: the photo, its histogram and level, the readouts, the bottom panel and the pointer; the raw the
    click opens comes up over the frames the open takes."""
    w.header(c, FEATURE)
    raw, ev = (RAW, 0.0) if opened(b) else (FIRST, step_at(DRAG, b))
    img = picture(raw, ev, EDITOR)
    r = w.photo_panel(c, PHOTO_PANEL, img, b, raw.name, horizon=None)
    if CLICK.press <= b < CLICK.press + OPENING:
        before = c.img.copy()
        before.paste(Image.new("RGB", (r.w, r.h), w.THEME.rgb("shadow")), (r.x, r.y))
        w.develop(c, before, w.between(b, CLICK.press, CLICK.press + OPENING))
    w.histogram(c, img, HIST)
    c.seg_column(*LEVEL, level(img), "gold", seg=2, gap=1)
    readouts(c, b)
    bottom(c, b)
    at = pointer_at(b)
    if at:
        w.pointer(c, *at[0], pressed=at[1])
    w.caption(c, caption_at(b))
    return []


def result(c, b):
    """Bar 6: the raw that opened fills the stage as opened, and follows Exposure up a step a beat, the second on
    the flip."""
    w.header(c, FEATURE)
    img = picture(RAW, step_at(RESULT_DRAG, b), RESULT)
    r = w.photo_panel(c, RESULT_PANEL, img, b, RAW.name, right=f"RENDER {RENDER}", right_color="lime", horizon=None)
    if CUE["flip"] <= b < CUE["flip"] + 1:
        c.sparkles(r.x, r.y, r.w, r.h, 26, ["gold.light", "white", "orange.light"], seed=int(b * w.PER_BEAT))
    v, held = value_at(RESULT_DRAG, b), b < RESULT_DRAG.release
    w.meters(c, METER, [("EXPOSURE", "gold", value_text(v), 0.5 + v / (2 * REACH), held)], track=TRACK)
    c.seg_column(*METER_LEVEL, level(img), "gold", seg=2, gap=1)
    w.pointer(c, *knob(METER, v), pressed=held)
    w.caption(c, caption_at(b))
    return []


def end_card(c, b):
    """Bars 7 and 8: the lamp comes on with the end line, the call to action from its cue, then the fade."""
    light = math.ceil(6 * w.ease(w.between(b, CUE["endLine"], CUE["endLine"] + 1))) / 6
    w.cta_card(c, EPISODE["endLine"], cta=b >= CUE["cta"], light=light)
    w.fade(c, w.between(b, CUE["fade"], CUE["end"]))
    return []


def caption_at(b):
    """The caption at beat b: the title held from the opener, then each step's words."""
    lines = TITLE
    for start, words in CAPTIONS:
        if b >= start:
            lines = words
    return lines


def frame(c, b, hook="a"):
    """The picture at beat b, drawn on c; the hook is the opener's. All pixel art, so no overlays."""
    if b < CUE["result"]:
        return dashboard(c, b)
    if b < CUE["endLine"]:
        return result(c, b)
    return end_card(c, b)


# ---------------------------------------------------------------- its sounds

def pan(x):
    return round((x / w.W - 0.5) * 0.8, 2)


def sounds():
    """Each sound on screen, (beat, kind, pan): a press, a tick for each step and a release for Exposure's drag,
    panned with its knob; a click on DSC_0750's thumbnail; and the result's drag, its second step the flip."""
    out = [(DRAG.press, "press", pan(knob(BOTTOM, 0)[0]))]
    out += [(t, "tick", pan(knob(BOTTOM, v)[0])) for t, v in zip(DRAG.ticks, DRAG.values)]
    out.append((DRAG.release, "release", pan(knob(BOTTOM, DRAG.values[-1])[0])))
    x = thumb_tip(RAW)[0]
    out += [(CLICK.press, "press", pan(x)), (CLICK.release, "release", pan(x))]
    out.append((RESULT_DRAG.press, "press", pan(knob(METER, 0)[0])))
    for t, v in zip(RESULT_DRAG.ticks, RESULT_DRAG.values):
        out.append((t, "flip" if t == CUE["flip"] else "tick", pan(knob(METER, v)[0])))
    out.append((RESULT_DRAG.release, "release", pan(knob(METER, RESULT_DRAG.values[-1])[0])))
    return sorted(out)


# ---------------------------------------------------------------- the storyboard

def at(b):
    return lambda c: frame(c, b)


PANELS = [
    w.Panel(1, 0.0, at(1.0), " / ".join(TITLE),
            "The boom lands under the kick on the first frame; the bass runs in sixteenths, muffled, under a kick "
            "muffled as if through a wall, over a drone on G sharp and the glass hum. DSC_0751 as opened, RENDER 1.8 MS "
            "and EXPOSURE 0.00."),
    w.Panel(2, 2.4, at(s1 + 3.2), CAPTIONS[0][1],
            "The riff starts on the sync lead; a press on Exposure's knob, then a tick a beat as it climbs to +1.00 and "
            "the photo follows each step."),
    w.Panel(3, 4.8, at(s2 + 3.1), CAPTIONS[1][1],
            "A tick a beat as Exposure comes back down to -0.50; RENDER stays at 1.8 MS, its clock lit at each change."),
    w.Panel(4, 7.2, at(CLICK.release + 0.5), " / ".join(CAPTIONS[2][1]),
            "The gated drums come in with a cymbal; a click on DSC_0750 in the filmstrip a beat later, and it comes up "
            "as opened as OPEN 0.16 S takes EXPOSURE's place."),
    w.Panel(5, 9.6, at(s4 + 2.5), " / ".join(CAPTIONS[3][1]),
            "The riff's answer over the sequencer in thirty-seconds and a riser, as the M1 Ultra's chip and the Release "
            "build come up; fuzz toms fall into the stop, the riff's A sharp held through it."),
    w.Panel(6, 12.0, at(CUE["flip"] + 0.6), " / ".join(CAPTIONS[4][1]),
            "The drop on G#m9: the boom, the low brass, the chord struck and the sting; then a tick a beat as Exposure "
            "climbs from 0.00 to +1.50 under the photo, with sparkles on the flip."),
    w.Panel(7, 14.4, at(CUE["cta"] + 0.5), " / ".join(EPISODE["endLine"]) + ", then " + " / ".join(w.END_CARD),
            "The closing phrase over Emaj9 and D#7(b9), turning through G to G sharp on the last hit."),
    w.Panel(8, 16.8, at(CUE["fade"] + 1), " / ".join(w.END_CARD),
            "The last chord, G#m9, dies away as the picture fades."),
]
