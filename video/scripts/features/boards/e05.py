"""
E05, Presets and LUTs, in the series' look (boards/e01.py): Lightroom develop presets dropped on Redlamp's
Recipes panel, the report of what came across, a .cube look table dropped the same way, then a click on one of
the presets. The editor is drawn as E08's dashboard is: a raw in the photo panel as pixel art, its histogram and
level under it, and below them the Recipes panel, Essentials open as the app opens it, with a Finder window beside
it, holding three presets and then a look table. The pointer drags the presets onto the panel, which lists them under
Lightroom and opens that list, as the app does, and the report comes up over the photo in the app's words: the
headline, the preset's tally, then
each of its settings under Approximated, Ignored and Mapped, its profile among the ignored. The look table joins
the list under Imported, and its table comes up as a card; the pointer lands on WARM SUMMER, the photo previews it
under the app's pill, and a click applies it, its sliders on the BASIC card. The result is the photo before and
after the preset, in pixel art.

The presets and the look table are the episode's own, in src/features/e05/: three Lightroom develop presets
written from the published Camera Raw schema (never Adobe's files), one with a profile, and a small, gentle .cube.
The report is Redlamp's, read from the CLI's import (`redlamp recipe import`, which words each preset's report as
the Recipes panel's import sheet does, LightroomReportSummary), and so are the lists they join and the values the
preset sets. The photo is a beach cove from the air, Hasselblad_L2D-20c.DNG, the raw from the Hasselblad camera on
DJI's Mavic 3 in the camera coverage set (tests/fixtures/cameras, CC0 from raw.pixls.us), shown as BEACH.DNG. Every
picture of it is Redlamp's render with the redlamp CLI, kept in public/features/e05/results/: as opened, and with
each imported recipe as the editor applies it (`redlamp recipe render`, which starts from the photo as opened),
reduced to pixel art with a palette of the photo's own colours, as E08's is.
"""

import hashlib
import json
import math
import re
import subprocess
from functools import cache
from pathlib import Path
from typing import NamedTuple

import numpy as np
from PIL import Image

from features import results
from features import world as w
from pixelkit.art import oklab

EPISODE = w.episode("e05")
FEATURE = "PRESETS AND LUTS"
# The panel shows the raw as BEACH.DNG: its own name carries its camera's maker.
FILE = "BEACH.DNG"
PHOTO = ("HASSELBLAD_L2D-20C.DNG (THE HASSELBLAD L2D-20C ON DJI'S MAVIC 3, CC0 FROM RAW.PIXLS.US), A BEACH COVE FROM "
         "THE AIR, SHOWN AS BEACH.DNG; EVERY PICTURE OF IT REDLAMP'S OWN RENDER WITH THE CLI: AS OPENED, AND WITH EACH "
         "IMPORTED PRESET AND THE LOOK TABLE AS THE EDITOR APPLIES IT; AS PIXEL ART WITH ITS OWN PALETTE. THE PRESETS "
         "AND THE .CUBE ARE THE EPISODE'S OWN (SRC/FEATURES/E05), WRITTEN FROM THE PUBLISHED SCHEMA; THE REPORT, THE "
         "LISTS AND THE VALUES ARE THE APP'S, FROM THE CLI'S IMPORT")
CUE = w.CUE
FOLDER = w.VIDEO / "public/features/e05/results"
SOURCES = w.VIDEO / "src/features/e05"
# The presets as Finder lists them, by name, and the look table.
PRESETS = ["Clear Sea.xmp", "Soft Fade.xmp", "Warm Summer.xmp"]
TABLE = "Soft Teal.cube"
# The preset the report is opened on, and the one the click applies: it carries a profile.
SHOWN = "WARM SUMMER"
# The bundled list the Recipes panel opens with (SidebarListView's expandedGroups); the imports' own lists come above
# the bundled ones.
OPEN = "ESSENTIALS"

PHOTO_PANEL = w.Rect(4, 106, 208, 84)
RESULT_PANEL = w.Rect(4, 106, 208, 178)
HIST = w.Rect(4, 192, 208, 12)
RECIPES = w.Rect(4, 206, 92, 81)
FINDER = w.Rect(100, 206, 86, 81)
LEVEL = w.Rect(190, 210, 18, 73)
# The report comes up over the photo and its histogram, where the app's sheet comes down over the window.
REPORT = w.Rect(4, 104, 208, 100)
EDITOR = (PHOTO_PANEL.w - 8, PHOTO_PANEL.h - 16)
RESULT = (RESULT_PANEL.w - 8, RESULT_PANEL.h - 16)
SWATCH = (9, 6)
# The Recipes panel's rows: the recipe's Amount, then the lists and the recipes in the open ones, a row each, the
# names under the lists' and the swatches under their folders.
AMOUNT_Y, LIST_Y, ROW, ROWS = RECIPES.y + 12, RECIPES.y + 20, 8, 7
LABEL_X, ICON_X, NAME_X = RECIPES.x + 4, RECIPES.x + 10, RECIPES.x + 22
TRACK = (RECIPES.x + 30, RECIPES.x + 70)
# The Amount's reach (the app's slider runs from 0, the photo as it was, to 200, twice as far).
REACH = 200
# Finder's rows, a file a row.
FILE_X, FILE_Y, FILE_ROW = FINDER.x + 4, FINDER.y + 14, 10
# Words keep left of the apps' side buttons, which cover the stage's right edge.
READ_RIGHT = 202
TITLE = w.wrapped(EPISODE["title"].upper())
CAPTION_RESULT = "BEFORE AND AFTER"


class Drag(NamedTuple):
    """The pointer presses on files on `press`, carries them, and lets go over the Recipes panel on `drop`."""
    files: tuple
    press: float
    drop: float


class Click(NamedTuple):
    """The pointer presses a recipe on `press` and lets go on `release`."""
    recipe: str
    press: float
    release: float


s1, s2, s3, s4 = (CUE[f"step{i}"] for i in range(1, 5))
# The pointer comes in with the first step's words, lands on the presets three sixteenths later and presses on
# the next beat; it lets go over the panel on the bar's third beat. The report's lines come up a sixteenth apart
# from half a beat into the second step. The look table is pressed on the third step's second beat and dropped on
# its third; the pointer lands on WARM SUMMER with the fourth step's words, previewing it, and clicks it a beat
# later. Each move takes the three sixteenths before the beat it lands on.
ENTER, MOVE = s1, 0.75
PRESETS_DRAG = Drag(tuple(PRESETS), s1 + 1, s1 + 2)
TABLE_DRAG = Drag((TABLE,), s3 + 1, s3 + 2)
HOVER = s4
CLICK = Click(SHOWN, s4 + 1, s4 + 1.5)
LINES_FROM, LINE_STEP = s2 + 0.5, 0.25
CAPTIONS = [(s1, ["DROP IN YOUR", ".XMP PRESETS"]), (s2, ["A REPORT OF WHAT", "CAME ACROSS"]),
            (s3, [".CUBE AND .3DL", "LUTS TOO"]), (s4, "CLICK TO APPLY"), (CUE["result"], CAPTION_RESULT)]
APPEAR = 6 / w.PER_BEAT


# ---------------------------------------------------------------- the presets, the table and the photo, from Redlamp

def fixture(name):
    """A raw in the repository's camera coverage set, which a worktree has only in the main checkout."""
    path = w.REPO / "tests/fixtures/cameras" / name
    if not path.exists():
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=w.REPO,
                                capture_output=True, text=True, check=True).stdout.strip()
        path = Path(common).parent / "tests/fixtures/cameras" / name
    return path


RAW = fixture("Hasselblad_L2D-20c.DNG")


def digest(key):
    return hashlib.sha256(json.dumps(key).encode()).hexdigest()[:12]


def kept(name, key, suffix, make):
    """The file or folder FOLDER keeps for `name`, made by `make(path)` when `key` is new; older ones go."""
    path = FOLDER / f"{name}-{digest(key)}{suffix}"
    if not path.exists():
        FOLDER.mkdir(parents=True, exist_ok=True)
        make(path)
        for old in FOLDER.glob(f"{name}-*{suffix}"):
            if old != path:
                if old.is_dir():
                    for f in old.iterdir():
                        f.unlink()
                    old.rmdir()
                else:
                    old.unlink()
    return path


def redlamp(*args):
    done = subprocess.run([str(results.CLI), *args], capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(f"redlamp {' '.join(args)} failed: {done.stderr.strip() or done.stdout.strip()}")
    return done.stdout


def source_key(name):
    path = SOURCES / name
    return [name, hashlib.sha256(path.read_bytes()).hexdigest(), results.CLI.stat().st_mtime_ns]


class Report(NamedTuple):
    """A preset as the import read it: its file, the list it joins and its name, in capitals, its tally, and each
    outcome's settings, in the order the import sheet lists them."""
    file: str
    list: str
    name: str
    tally: str
    sections: tuple


def import_presets(folder):
    folder.mkdir(parents=True)
    out = redlamp("recipe", "import", *(str(SOURCES / name) for name in PRESETS), "-o", str(folder))
    (folder / "report.txt").write_text(out)


@cache
def presets():
    """The presets as `redlamp recipe import` reads them, dropped together as on the Recipes panel: each one's
    report, as the import sheet words it, and the recipe it becomes, by its name in capitals."""
    folder = kept("presets", [source_key(name) for name in PRESETS], "", import_presets)
    reports, current, section = [], None, None
    for line in (folder / "report.txt").read_text().splitlines():
        if " → " in line and not line.startswith(" "):
            file, made = line.split(" → ")
            listed, name = made.split(" / ", 1)
            current = {"file": file, "list": listed.upper(), "name": name.upper(), "tally": None, "sections": []}
            reports.append(current)
        elif current and line.startswith("    "):
            section[1].append(line.strip().split(": ", 1)[0])
        elif current and line.startswith("  ") and line.strip().endswith(":"):
            section = (line.strip()[:-1].upper(), [])
            current["sections"].append(section)
        elif current and current["tally"] is None and re.match(r"  (\d+ \w+|No settings)", line):
            current["tally"] = re.sub(r" \(Lightroom process version [^)]*\)$", "", line.strip()).upper()
    recipes = {json.loads(p.read_text())["name"].upper(): p for p in folder.glob("*.redrecipe")}
    return {r["name"]: (Report(r["file"], r["list"], r["name"], r["tally"],
                               tuple((title, tuple(names)) for title, names in r["sections"])), recipes[r["name"]])
            for r in reports}


def import_table(path):
    redlamp("recipe", "import", str(SOURCES / TABLE), "-o", str(path))


@cache
def table():
    """The look table as `redlamp recipe import` reads it: the list it joins, its name in capitals and its recipe."""
    path = kept("table", source_key(TABLE), ".redrecipe", import_table)
    recipe = json.loads(path.read_text())
    return recipe["group"].upper(), recipe["name"].upper(), path


def asked(name, *args):
    """What the CLI prints as JSON for `args`, kept until the CLI changes."""
    path = kept(name, [list(args), results.CLI.stat().st_mtime_ns], ".json",
                lambda path: path.write_text(redlamp(*args)))
    return json.loads(path.read_text())


@cache
def bundled():
    """The bundled lists, in the order the Recipes panel lists them, each with its recipes as (name in capitals, id);
    the library's own recipes on this Mac are left out."""
    lists = {}
    for r in asked("list", "recipe", "list", "--json"):
        if r["id"].startswith("redlamp/"):
            lists.setdefault(r["group"].upper(), []).append((r["name"].upper(), r["id"]))
    return lists


def recipe_path(name):
    return table()[2] if name == table()[1] else presets()[name][1]


def recipe_values(name):
    return json.loads(recipe_path(name).read_text())["settings"]["values"]


def report():
    return presets()[SHOWN][0]


@cache
def render(name=None):
    """Redlamp's render of the raw, 2048 pixels on its long edge: as opened, or with the recipe `name`, an imported
    preset, the look table or a bundled recipe, as the editor applies it, from the photo as opened."""
    if name is None:
        return results.render(RAW, FOLDER, "opened")
    if name in presets() or name == table()[1]:
        source = TABLE if name == table()[1] else presets()[name][0].file
        recipe, made = str(recipe_path(name)), source_key(source)
    else:
        recipe = next(rid for recipes in bundled().values() for n, rid in recipes if n == name)
        made = [recipe, results.CLI.stat().st_mtime_ns]
    key = [RAW.name, RAW.stat().st_size, RAW.stat().st_mtime_ns, made, 2048]
    args = ["recipe", "render", str(RAW), "--recipe", recipe, "--size", "2048"]
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    path = kept(slug, key, ".png", lambda path: redlamp(*args, "-o", str(path)))
    return Image.open(path).convert("RGB")


def shown(img, size):
    """The part of a render a picture of `size` shows: a band across its whole width through the middle, the sand
    and the water, for the editor, its whole height about the cove for the result, all of it at the photo's own
    shape."""
    iw, ih = img.size
    if size[0] * ih > size[1] * iw * 1.01:
        h = round(iw * size[1] / size[0])
        top = (ih - h) // 2
        box = (0, top, iw, top + h)
    elif size[0] * ih < size[1] * iw * 0.99:
        wd = round(ih * size[0] / size[1])
        left = (iw - wd) // 2
        box = (left, 0, left + wd, ih)
    else:
        box = (0, 0, iw, ih)
    return img.crop(box).resize(size, Image.BOX)


@cache
def palette(colors=40):
    """The photo's own colours, as opened and with the preset the click applies, at the editor's size and the
    result's: the centres of its pixels' clusters in Oklab, so the water's turquoise, the sand and the trees' greens
    keep a colour as opened and as the preset takes them."""
    shots = [shown(render(look), size) for look in (None, SHOWN) for size in (EDITOR, RESULT)]
    rgb = np.concatenate([np.asarray(img).reshape(-1, 3) for img in shots]).astype(np.float64)
    lab = oklab(rgb)

    def nearest(centres):
        return ((lab**2).sum(1)[:, None] - 2 * lab @ centres.T + (centres**2).sum(1)[None]).argmin(1)

    rng = np.random.default_rng(5)
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
def picture(look, size):
    """The photo as opened (None) or with the recipe `look`, at `size`, as pixel art."""
    return w.lock(shown(render(look), size), palette(), dither=0.15).convert("RGB")


@cache
def keys():
    """Where the photo as opened is the water's turquoise, white (the sand's, and the houses' above it) and the trees'
    green, at 512 pixels."""
    a = np.asarray(render().resize((512, 384), Image.BOX), dtype=np.float64)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return [(g > r + 60) & (b > r + 40) & (g > b), (r > 180) & (g > 170) & (b > 140),
            (g > b + 25) & (g >= r) & (g < r + 50)]


@cache
def swatch(name):
    """A recipe's look on the photo, as the list's swatch: three stripes, its take on the water's turquoise, the sand
    and the trees' green."""
    a = np.asarray(render(name).resize((512, 384), Image.BOX), dtype=np.float64)
    out = np.zeros((SWATCH[1], SWATCH[0], 3), np.uint8)
    for i, mask in enumerate(keys()):
        out[:, i * SWATCH[0] // 3:(i + 1) * SWATCH[0] // 3] = np.rint(a[mask].mean(0))
    return Image.fromarray(out)


@cache
def grid():
    """The look table's size and its output at each of its grid points, as 8-bit colours indexed [blue][green][red],
    as a .cube lists them, red fastest: from the .cube itself."""
    rows = [line.split() for line in (SOURCES / TABLE).read_text().splitlines()]
    size = next(int(r[1]) for r in rows if r and r[0] == "LUT_3D_SIZE")
    data = np.array([[float(v) for v in r] for r in rows if len(r) == 3 and re.match(r"[-\d.]", r[0])])
    return size, np.rint(np.clip(data.reshape(size, size, size, 3), 0, 1) * 255).astype(int)


# ---------------------------------------------------------------- the lists, the files and the pointer

def imported_by(b):
    """The lists the imports have added by beat b: Lightroom's presets once they're dropped, then the look table."""
    lists = []
    if b >= TABLE_DRAG.drop:
        lists.append((table()[0], [table()[1]]))
    if b >= PRESETS_DRAG.drop:
        lists.append((report().list, list(presets())))
    return lists


def rows_at(b):
    """The Recipes panel's rows under the Amount at beat b, as (kind, name): each list an import added, open, with
    its recipes, then the bundled lists, Essentials open as the app opens it and the others closed."""
    out = []
    for name, recipes in imported_by(b):
        out += [("list", name)] + [("recipe", r) for r in recipes]
    for name, recipes in bundled().items():
        out += [("list", name)] + [("recipe", r) for r, _ in recipes] if name == OPEN else [("bundled", name)]
    return out[:ROWS]


def row_y(name, b):
    return LIST_Y + [n for _, n in rows_at(b)].index(name) * ROW


def target(name, b):
    """Where the pointer's tip rests on a recipe: just past its name, so the name stays clear."""
    return NAME_X + w.FONTS["small"].measure(name) + 1, row_y(name, b) + 2


def finder_at(b):
    """Finder's window at beat b: its folder and its files."""
    return ("LUTS", [TABLE]) if b >= s3 else ("PRESETS", PRESETS)


def file_y(i):
    return FILE_Y + i * FILE_ROW


def grab(drag):
    """Where the pointer takes hold of a drag's files: just past the first one's name."""
    _, files = finder_at(drag.press)
    first = files.index(drag.files[0])
    return FILE_X + 10 + w.FONTS["small"].measure(drag.files[0].upper()) + 2, file_y(first) + 2


# A drop lands on the whole list, wherever it's let go: here, on the second row, which is a list's both before and
# after each import, so the pointer resting there previews nothing.
DROP_AT = (RECIPES.x + 64, LIST_Y + 2)


def path():
    """The pointer's moves, as (the beat it leaves, the beat it lands, where it lands)."""
    return [(ENTER, PRESETS_DRAG.press - 0.25, grab(PRESETS_DRAG)), (PRESETS_DRAG.press, PRESETS_DRAG.drop, DROP_AT),
            (TABLE_DRAG.press - MOVE, TABLE_DRAG.press, grab(TABLE_DRAG)), (TABLE_DRAG.press, TABLE_DRAG.drop, DROP_AT),
            (HOVER - MOVE, HOVER, target(SHOWN, HOVER))]


def pointer_at(b):
    """Where the pointer's tip is at beat b and whether it's pressed, or None while it's off screen: it comes in
    from the right, takes hold of the presets and carries them onto the Recipes panel, does the same with the look
    table, then lands on WARM SUMMER and clicks it."""
    if b < ENTER:
        return None

    def glide(a, z, t):
        return round(a[0] + (z[0] - a[0]) * t), round(a[1] + (z[1] - a[1]) * t)

    at = (w.W + 6, grab(PRESETS_DRAG)[1] + 20)
    for leave, land, to in path():
        if b < leave:
            break
        at = glide(at, to, w.ease(w.between(b, leave, land))) if b < land else to
    pressed = any(d.press <= b < d.drop for d in (PRESETS_DRAG, TABLE_DRAG)) or CLICK.press <= b < CLICK.release
    return at, pressed


def dragging(b):
    """The drag under way at beat b, if any."""
    return next((d for d in (PRESETS_DRAG, TABLE_DRAG) if d.press <= b < d.drop), None)


def over_panel(b):
    """Whether a drag at beat b is over the Recipes panel, which takes it."""
    at = pointer_at(b)
    if dragging(b) is None or at is None:
        return False
    (x, y), _ = at
    return RECIPES.x <= x < RECIPES.x2 and RECIPES.y <= y < RECIPES.y2


def previewing(b):
    """The recipe the photo previews at beat b: the one the pointer lands on, until the click applies it."""
    return SHOWN if HOVER <= b < CLICK.press else None


def applied(b):
    return b >= CLICK.press


def look_at(b):
    return SHOWN if previewing(b) or applied(b) else None


# ---------------------------------------------------------------- the panels

ARROW = ["#..", "##.", "###", "##.", "#.."]


def amount_row(c, b):
    """The recipe's Amount: dim until a recipe is applied, then its knob at 100 and its value."""
    made = applied(b)
    y, (t0, t1) = AMOUNT_Y, TRACK
    c.text(LABEL_X, y, "AMOUNT", "gold" if made else "dim")
    c.rect(t0, y + 1, t1 - t0, 3, "shadow")
    kx = round(t0 + 100 / REACH * (t1 - t0))
    if made:
        c.rect(t0, y + 1, kx - t0 + 1, 3, "gold")
    c.vline(kx, y, 5, "dim")
    if made:
        c.rect(kx - 1, y - 1, 3, 7, "white")
        c.text(RECIPES.x2 - 4, y, "100", "white", align="right")


def recipes_panel(c, b):
    """The Recipes panel: the Amount, each list an import added, open, its recipes with their swatches, then the
    bundled lists, closed; the one previewed raised with the system accent at its edge, the one clicked sunk while
    pressed, the one applied lit; outlined in the accent while a drag over it offers files."""
    c.panel(*RECIPES, "RECIPES", color="sky")
    amount_row(c, b)
    for kind, name in rows_at(b):
        y = row_y(name, b)
        if kind == "recipe":
            band = w.Rect(RECIPES.x + 2, y - 2, RECIPES.w - 4, ROW)
            ink = "text"
            if name == CLICK.recipe and CLICK.press <= b < CLICK.release:
                c.rect(*band, "green.dark")
                ink = "green.light"
            elif name == CLICK.recipe and applied(b):
                c.rect(*band, "green")
                c.hline(band.x, band.y, band.w, "green.light")
                ink = "shadow"
            elif name == previewing(b):
                c.rect(*band, "raised")
                c.vline(band.x, band.y, band.h, "sky")
                ink = "white"
            c.rect(ICON_X - 1, y - 2, SWATCH[0] + 2, SWATCH[1] + 2, "shadow")
            c.img.paste(swatch(name), (ICON_X, y - 1))
            c.text(NAME_X, y, name, ink)
        else:
            if kind == "list":
                c.text(LABEL_X, y, "▼", "dim")
            else:
                c.sprite(LABEL_X + 1, y, ARROW, {"#": "dim"})
            c.icon(ICON_X, y - 1, "folder", "muted")
            c.text(NAME_X, y, name, "text")
    if over_panel(b):
        c.box(RECIPES.x - 1, RECIPES.y - 1, RECIPES.w + 2, RECIPES.h + 2, "sky")
        c.box(RECIPES.x, RECIPES.y, RECIPES.w, RECIPES.h, "sky.light")


def finder(c, b):
    """Finder's window beside the panel: the folder and its files, the ones the pointer takes selected until they're
    dropped, then left as Finder leaves them."""
    folder, files = finder_at(b)
    accent = "violet" if folder == "PRESETS" else "cyan"
    c.panel(*FINDER, folder, color=accent, right=f"{len(files)} ITEM{'S' if len(files) > 1 else ''}", right_color="dim")
    drag = PRESETS_DRAG if folder == "PRESETS" else TABLE_DRAG
    for i, name in enumerate(files):
        y = file_y(i)
        c.rect(FINDER.x + 2, y - 2, FINDER.w - 4, FILE_ROW - 1, "sky.dark" if b < drag.drop else "raised")
        c.icon(FILE_X, y - 2, "file", f"{accent}.light")
        c.text(FILE_X + 10, y, name.upper(), "white")


def ghost(c, b):
    """The files a drag carries, a little below and right of the pointer, with the copy badge once they're over the
    panel."""
    drag = dragging(b)
    if not drag:
        return
    (x, y), _ = pointer_at(b)
    accent = "violet" if drag is PRESETS_DRAG else "cyan"
    for i in reversed(range(len(drag.files))):
        fx, fy = x + 7 + 2 * i, y + 8 + 2 * i
        c.rect(fx - 1, fy - 1, 9, 11, "shadow")
        c.icon(fx, fy, "file", f"{accent}.light")
    if over_panel(b):
        bx, by = x + 1, y + 12
        c.circle(bx + 2.5, by + 2.5, 3.2, "green")
        c.hline(bx + 1, by + 2, 3, "white")
        c.vline(bx + 2, by + 1, 3, "white")


def arrived(c, b):
    """Sparkles over a list as an import adds it."""
    for drag in (PRESETS_DRAG, TABLE_DRAG):
        if drag.drop <= b < drag.drop + 0.5:
            name = report().list if drag is PRESETS_DRAG else table()[0]
            y = row_y(name, b)
            count = len(presets()) if drag is PRESETS_DRAG else 1
            c.sparkles(RECIPES.x + 2, y - 3, RECIPES.w - 4, (count + 1) * ROW + 2, 8, ["sky.light", "white"],
                       seed=int(b * w.PER_BEAT))


# ---------------------------------------------------------------- the cards

def shown_lines():
    """The report's lines, as they come up: each of the approximated and ignored settings with its section's title
    above it, side by side, then the mapped ones two to a line under theirs."""
    sections = dict(report().sections)
    head = [(title, list(sections.get(title, ()))) for title in ("APPROXIMATED", "IGNORED")]
    mapped = list(sections.get("MAPPED", ()))
    half = math.ceil(len(mapped) / 2)
    deep = max(len(names) for _, names in head)
    return head, deep, [mapped[:half], mapped[half:]], half


def lines_up(b):
    """How many of the report's lines have come up by beat b."""
    return sum(1 for k in range(report_lines()) if b >= LINES_FROM + k * LINE_STEP)


def report_lines():
    _, deep, _, half = shown_lines()
    return deep + half


# The tally's outcomes, in its order, as the card colours them: each section's title, and its count and LEDs.
OUTCOMES = {"MAPPED": "green", "APPROXIMATED": "gold", "IGNORED": "text"}
COUNTED = {"MAPPED": "green.light", "APPROXIMATED": "gold.light", "IGNORED": "text"}


def tally_spans():
    """The tally in the app's words, each outcome's count in its section's colour."""
    parts = []
    for i, part in enumerate(report().tally.split(", ")):
        parts += [(", ", "text")] if i else []
        parts.append((part, COUNTED[part.split(" ", 1)[1]]))
    return parts


def leds(c, x, y, b):
    """The tally drawn as LEDs, one a setting in the tally's order, each lit as its line comes up."""
    counts = {part.split(" ", 1)[1]: int(part.split(" ")[0]) for part in report().tally.split(", ")}
    head, deep, columns, _ = shown_lines()
    up = lines_up(b)
    lit = {"APPROXIMATED": sum(1 for k in range(len(dict(head)["APPROXIMATED"])) if k < up),
           "IGNORED": sum(1 for k in range(len(dict(head)["IGNORED"])) if k < up),
           "MAPPED": sum(len(col[: max(0, up - deep)]) for col in columns)}
    k = 0
    for outcome in ("MAPPED", "APPROXIMATED", "IGNORED"):
        for i in range(counts.get(outcome, 0)):
            c.rect(x + 4 * k, y, 3, 5, COUNTED[outcome] if i < lit[outcome] else "raised")
            k += 1


def report_card(c, r, b):
    """The import's report, as the Recipes panel's import sheet words it, opened on the preset with a profile: its
    name and tally, the tally drawn as LEDs, then the approximated and ignored settings side by side under their
    titles and the mapped ones under theirs, each line coming up in turn."""
    c.text(r.x, r.y + 1, "▼", "dim")
    c.text(r.x + 8, r.y, report().name, "white", font="large")
    leds(c, READ_RIGHT - 4 * sum(int(p.split(" ")[0]) for p in report().tally.split(", ")) + 1, r.y + 1, b)
    c.spans(r.x + 8, r.y + 10, tally_spans())
    head, deep, columns, half = shown_lines()
    up = lines_up(b)
    for (title, names), x in zip(head, (r.x + 8, r.x + 106)):
        c.text(x, r.y + 19, title, OUTCOMES[title])
        for k, name in enumerate(names):
            if k < up:
                c.text(x + 4, r.y + 26 + 7 * k, name, "white" if title == "IGNORED" else "text")
    top = r.y + 26 + 7 * deep + 2
    c.text(r.x + 8, top, "MAPPED", OUTCOMES["MAPPED"])
    for column, x in zip(columns, (r.x + 12, r.x + 72)):
        for k, name in enumerate(column):
            if deep + k < up:
                c.text(x, top + 7 + 7 * k, name, "text")


CUBE = [(0, 4, 8, 0), (8, 0, 16, 4), (16, 4, 8, 8), (8, 8, 0, 4), (0, 4, 0, 13), (8, 8, 8, 17), (16, 4, 16, 13),
        (0, 13, 8, 17), (8, 17, 16, 13)]


def table_card(c, r, b):
    """The look table that came in: a cube for its three dimensions and its size, then what it does along its grey
    axis, its grid's greys in over what they become, from the .cube itself."""
    size, colours = grid()
    x0 = r.x + 4
    for x_a, y_a, x_b, y_b in CUBE:
        c.line(x0 + x_a, r.y + 1 + y_a, x0 + x_b, r.y + 1 + y_b, "cyan")
    c.text(x0 + 24, r.y + 3, table()[1], "white")
    c.text(x0 + 24, r.y + 12, f"{size} × {size} × {size}", "text")
    cell = (r.w - 8) // size
    left = r.x + (r.w - cell * size) // 2
    for k in range(size):
        grey = round(255 * k / (size - 1))
        c.rect(left + k * cell, r.y + 27, cell, 6, "#%02x%02x%02x" % (grey, grey, grey))
        c.rect(left + k * cell, r.y + 34, cell, 6, "#%02x%02x%02x" % tuple(int(v) for v in colours[k, k, k]))
    c.text(left, r.y + 43, "IN", "dim")
    c.text(left + cell * size, r.y + 43, "OUT", "dim", align="right")


def temp_position(kelvin):
    """Where the Temp slider's knob sits for `kelvin`: its track is linear in mireds from 2,000 to 50,000 K, as the
    app's (ParameterSpec)."""
    lo, hi = 1e6 / 50000, 1e6 / 2000
    return 1 - (1e6 / kelvin - lo) / (hi - lo)


def gradient(c, x, y, wd, stops):
    """A slider's track coloured along its length, from the first colour to the last."""
    cols = np.array([[int(h[i:i + 2], 16) for i in (1, 3, 5)] for h in stops], dtype=np.float64)
    for k in range(wd):
        t = k / max(1, wd - 1) * (len(cols) - 1)
        i = min(int(t), len(cols) - 2)
        rgb = cols[i] + (cols[i + 1] - cols[i]) * (t - i)
        c.vline(x + k, y, 3, "#%02x%02x%02x" % tuple(int(round(v)) for v in rgb))


def signed(v, digits=0):
    return "0" if v == 0 else f"{v:+.{digits}f}"


# The Basic panel's sliders the preset sets, as the app names them, with their values' formats.
BASIC = [("TEMP", "wb.temperature"), ("TINT", "wb.tint"), ("EXPOSURE", "basic.exposure"),
         ("CONTRAST", "basic.contrast"), ("HIGHLIGHTS", "basic.highlights"), ("SHADOWS", "basic.shadows"),
         ("VIBRANCE", "basic.vibrance")]


def basic_card(c, r, b):
    """The sliders the click moved, at the preset's values: Temp and Tint on their coloured tracks, the rest as
    meters either side of zero."""
    values = recipe_values(SHOWN)
    t0, t1 = r.x + 42, r.x + 56
    for i, (label, key) in enumerate(BASIC):
        y = r.y + i * 8
        v = values.get(key, 0)
        c.text(r.x, y, label, "text")
        if key == "wb.temperature":
            gradient(c, t0, y + 1, t1 - t0, ["#3a6fd8", "#e8e8e8", "#e8c040"])
            kx = round(t0 + temp_position(v) * (t1 - t0 - 1))
            c.rect(kx, y, 1, 5, "white")
            text = f"{v:.0f}"
        elif key == "wb.tint":
            gradient(c, t0, y + 1, t1 - t0, ["#3fbf5a", "#e8e8e8", "#d04fc8"])
            kx = round(t0 + (v + 150) / 300 * (t1 - t0 - 1))
            c.rect(kx, y, 1, 5, "white")
            text = signed(v)
        else:
            reach, digits = (5, 2) if key == "basic.exposure" else (100, 0)
            c.rect(t0, y + 1, t1 - t0, 3, "shadow")
            mid = (t0 + t1) // 2
            kx = round(mid + v / reach * (t1 - t0) / 2)
            lo, hi = sorted((mid, kx))
            c.rect(lo, y + 1, hi - lo + 1, 3, "sky")
            c.vline(mid, y, 5, "dim")
            text = signed(v, digits)
        c.text(r.x2, y, text, "white", align="right")


# Each card over the dashboard: where it comes up, from the beat it comes up on to the beat it goes, its title and
# accent, and what it draws.
CARDS = [(REPORT, s2, s3, f"IMPORTED {len(PRESETS)} LIGHTROOM PRESETS", "lime", report_card),
         (FINDER, TABLE_DRAG.drop, s4, "LOOK TABLE", "cyan", table_card),
         (FINDER, CLICK.press, CUE["result"], "BASIC", "sky", basic_card)]


# ---------------------------------------------------------------- the dashboard

def level(img):
    """How bright the photo is, as the LED level: it sits higher than the dusk's, so it reads at 1.4 times its
    mean where E01's reads at 2.2."""
    return min(1.0, float(np.asarray(img).mean()) / 255 * 1.4)


def card_at(b):
    return next(((r, start, title, colour, body) for r, start, end, title, colour, body in CARDS if start <= b < end), None)


def editor(c, b):
    """The photo with the preview's pill, its histogram and level, and the Recipes panel; Finder's window unless a
    card has taken its place."""
    img = picture(look_at(b), EDITOR)
    card = card_at(b)
    if not card or card[0] is not REPORT:
        r = w.photo_panel(c, PHOTO_PANEL, img, b, FILE, horizon=None)
        if previewing(b):
            w.tag(c, r, f"PREVIEW: {previewing(b)}")
        w.histogram(c, img, HIST)
    c.seg_column(*LEVEL, level(img), "gold", seg=2, gap=1)
    recipes_panel(c, b)
    if not card or card[0] is not FINDER:
        finder(c, b)


def develop_in(c, before, rect, p):
    """Keeps the share p of what's been drawn inside `rect` since `before`, in the 8 × 8 ordered dither world.develop
    uses, so a card comes up in its place while the rest of the picture changes on its own beats."""
    if p >= 1:
        return
    order = w.bayer(8)[np.arange(c.h)[:, None] % 8, np.arange(c.w)[None, :] % 8] < max(p, 0.0)
    inside = np.zeros((c.h, c.w), bool)
    inside[rect.y:rect.y2, rect.x:rect.x2] = True
    out = np.where((order | ~inside)[..., None], np.asarray(c.img), np.asarray(before))
    c.img.paste(Image.fromarray(out.astype(np.uint8)))


def dashboard(c, b):
    """Bars 1 to 5: the editor, the bar's card coming up over its place, and the pointer with what it carries."""
    w.header(c, FEATURE)
    card = card_at(b)
    if card:
        rect, start, title, colour, body = card
        before = w.canvas()
        editor(before, start - 0.01)
        editor(c, b)
        w.card(c, rect.x, rect.y, title, colour, lambda c, content: body(c, content, b), w=rect.w - 2, h=rect.h - 2)
        develop_in(c, before.img, rect, w.between(b, start, start + APPEAR))
        if b < start + 0.5:
            c.sparkles(rect.x - 2, rect.y - 2, rect.w + 4, rect.h + 4, 8, [f"{colour}.light", "white"],
                       seed=int(b * w.PER_BEAT))
    else:
        editor(c, b)
    arrived(c, b)
    ghost(c, b)
    at = pointer_at(b)
    if at:
        w.pointer(c, *at[0], pressed=at[1])
    w.caption(c, caption_at(b))
    return []


def result(c, b):
    """Bar 6: the photo fills the stage, as opened, then developing into the preset on the flip."""
    w.header(c, FEATURE)
    before = picture(None, RESULT)
    if b < CUE["flip"]:
        w.photo_panel(c, RESULT_PANEL, before, b, FILE, right="BEFORE", right_color="text", horizon=None)
    else:
        flat = w.canvas()
        w.header(flat, FEATURE)
        w.photo_panel(flat, RESULT_PANEL, before, b, FILE, right="BEFORE", right_color="text", horizon=None)
        r = w.photo_panel(c, RESULT_PANEL, picture(SHOWN, RESULT), b, FILE, right="AFTER", right_color="gold",
                          horizon=None)
        w.develop(c, flat.img, w.between(b, CUE["flip"], CUE["flip"] + 8 / w.PER_BEAT))
        if b < CUE["flip"] + 1:
            c.sparkles(r.x, r.y, r.w, r.h, 26, ["gold.light", "white", "orange.light"], seed=int(b * w.PER_BEAT))
    w.caption(c, CAPTION_RESULT)
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
    """Each sound on screen, (beat, kind, pan): a press as the pointer takes hold of the presets and a soft drop as
    they land on the panel, panned with the pointer; a soft tick as each line of the report comes up, panned along
    the card; the same press and drop for the look table; a soft tick as the preview changes and a click on WARM
    SUMMER; and a tick on the flip to after."""
    out = []
    for drag in (PRESETS_DRAG, TABLE_DRAG):
        out += [(drag.press, "press", pan(grab(drag)[0])), (drag.drop, "lands", pan(DROP_AT[0]))]
    for k in range(report_lines()):
        out.append((LINES_FROM + k * LINE_STEP, "step", pan(REPORT.x + 20 + 150 * k / max(1, report_lines() - 1))))
    x = target(SHOWN, HOVER)[0]
    out += [(HOVER, "tick", pan(x)), (CLICK.press, "press", pan(x)), (CLICK.release, "release", pan(x)),
            (CUE["flip"], "flip", 0.0)]
    return sorted(out)


# ---------------------------------------------------------------- the storyboard

def at(b):
    return lambda c: frame(c, b)


PANELS = [
    w.Panel(1, 0.0, at(1.5), " / ".join(TITLE),
            "A deep hit and a boom, and the lead-in's E and F sharp turn to C sharp minor: a recorded drone on C sharp and "
            "wide pads in front, the arpeggio's bell in sixteenths over a kick muffled as if through a wall. The photo as "
            "opened, the Recipes panel's lists, and three presets selected in Finder."),
    w.Panel(2, 2.4, at(PRESETS_DRAG.press + 0.8), " / ".join(CAPTIONS[0][1]),
            "The riff starts on a supersaw lead and the bass rolls in sixteenths; a press as the pointer takes the "
            "presets, and a soft drop on the bar's third beat as they land: the panel lists them under LIGHTROOM."),
    w.Panel(3, 4.8, at(s2 + 3.2), " / ".join(CAPTIONS[1][1]),
            "Synth hats on the offbeats; a soft tick as each line of the report comes up, a sixteenth apart: the "
            "approximated and ignored settings, CAMERAPROFILE among them, then the mapped ones."),
    w.Panel(4, 7.2, at(TABLE_DRAG.drop + 1.2), " / ".join(CAPTIONS[2][1]),
            "The recorded kit comes in with a crash; a press as the pointer takes the .cube, and a soft drop as it lands "
            "under IMPORTED and its table comes up."),
    w.Panel(5, 9.6, at(CLICK.release + 1.0), CAPTIONS[3][1],
            "A soft tick as the pointer lands on WARM SUMMER and the photo previews it, then a click a beat later: the "
            "BASIC card shows its sliders; toms fall into the stop, and the riff's D sharp holds through it."),
    w.Panel(6, 12.0, at(CUE["flip"] + 0.6), CAPTION_RESULT + "; before, then after at 13.2 s",
            "The drop on C sharp minor: the boom, an impact, the choir and a crash, and the sting; a tick and a burst "
            "of sparkles as the photo develops on the flip."),
    w.Panel(7, 14.4, at(CUE["cta"] + 0.5), " / ".join(EPISODE["endLine"]) + ", then " + " / ".join(w.END_CARD),
            "The closing phrase over A major and G#7(b9), turning over B sharp to C sharp on the last hit."),
    w.Panel(8, 16.8, at(CUE["fade"] + 1), " / ".join(w.END_CARD), "The last chord dies away as the picture fades."),
]
