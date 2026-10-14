#!/usr/bin/env python3
"""Contact sheets for the depth bake-off (OTH-03): photos, depth maps as colour, and crops at hair.

    build/lens-blur-depth-venv/bin/python research/prototypes/lens_blur/depth_sheets.py photos
    build/lens-blur-depth-venv/bin/python research/prototypes/lens_blur/depth_sheets.py benchmark

`photos` reads the raw estimates of the CC0 MSK-25 photos (depth_estimate.py --photos) for each
combination in COMBOS, refines them at the photo's 1536 px as depth_eval.py does (in disparity,
normalised between the 1st and 99th percentiles), and lays out, per photo, the photo and each map
(turbo, near is red), then the same crop of each at the hair, marked on the photo. `benchmark` does the
same for benchmark scenes, with the truth's disparity first, from build/proto-data/lens_blur/estimated/.
Sheets go to docs/research/images/lens-blur-depth-<name>.jpg, each kept under 400 KB.
"""

import json
import pathlib
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import common  # noqa: E402
from common import DATA, PHOTOS, ROOT, read_exr  # noqa: E402
from depth_eval import ESTIMATED, RAW, app_chain, guided, luma, weighted_median  # noqa: E402

IMAGES = ROOT / "docs/research/images"
TILE_H = 300
GROUPS = {
    "hair": ["hair-busy-background-01", "hair-busy-background-03", "hair-backlit-02"],
    "curly": ["hair-curly-01", "hair-curly-03", "beard-02"],
    "people": ["glasses-hats-02", "crowd-01", "groups-02"],
    "pets-branches": ["pets-01", "pets-04", "sky-bare-trees-03"],
}
# Crop centres as fractions of the photo (x, y), at the hair, fur or branches; side as a fraction of
# the short side.
CROPS = {}
COMBOS = [("da3-mono-l@app", "app", "Mono-L 504, app chain (ships)"),
          ("da3-mono-l@2x", "wmf", "Mono-L 1008, weighted median"),
          ("moge2-b@2x", "wmf", "MoGe-2 B 1008, weighted median"),
          ("moge2-l@2x", "wmf", "MoGe-2 L 1008, weighted median")]
BENCH_SCENES = [("layered", "portrait-leafy", "subject", None, 0.3),
                ("layered", "cat-overcast", "subject", None, 0.3),
                ("layered", "portrait-night", "subject", None, 0.3),
                ("blender", "foliage-layers", "subject", None, 0.3),
                ("blender", "brick-wall", "subject", (0.5, 0.5), 0.6)]
BENCH_LABELS = ["da3-mono-l@app+app", "da3-mono-l@2x+wmf", "moge2-b@2x+wmf", "moge2-b@2x+layers-vitmatte",
                "moge2-b@2x+layers-oracle"]


def font(size):
    for path in ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/SFNS.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def colour(q, lo=None, hi=None):
    import matplotlib
    lo = np.percentile(q, 1) if lo is None else lo
    hi = np.percentile(q, 99) if hi is None else hi
    t = np.clip((q - lo) / max(hi - lo, 1e-9), 0, 1)
    return (matplotlib.colormaps["turbo"](t)[..., :3] * 255).astype(np.uint8)


def refined(source, refinement, relative, rgb):
    raw_dir = RAW / source / relative
    raw = np.load(raw_dir / "raw.npy").astype(np.float32)
    kind = json.loads((raw_dir / "meta.json").read_text())["kind"]
    H, W = rgb.shape[:2]
    if refinement == "app":
        m, depth = app_chain(raw, kind, rgb, (H, W))
        return m if depth is None else 1 / np.maximum(depth, 1e-6)
    q = raw if kind == "disparity" else 1 / np.maximum(raw, 1e-6)
    lo, hi = np.percentile(q, [1, 99])
    q = cv2.resize((q - lo) / (hi - lo), (W, H), interpolation=cv2.INTER_LINEAR)
    if refinement == "guided":
        return guided(q, luma(rgb))
    if refinement == "wmf":
        return weighted_median(q, rgb)
    return q


def auto_crop(q, rgb):
    """The window with the most depth edge over fine image detail, in the upper two thirds."""
    gy, gx = np.gradient(cv2.GaussianBlur(q, (0, 0), 2))
    edge = np.hypot(gx, gy)
    g = luma(rgb)
    detail = np.abs(g - cv2.GaussianBlur(g, (0, 0), 2))
    score = cv2.boxFilter(edge * detail, -1, (61, 61))
    H = q.shape[0]
    score[int(H * 0.7):] = 0
    y, x = np.unravel_index(np.argmax(score), score.shape)
    return x / q.shape[1], y / q.shape[0]


def crop_box(centre, side_frac, shape):
    H, W = shape
    side = int(min(H, W) * side_frac)
    x = int(np.clip(centre[0] * W - side / 2, 0, W - side))
    y = int(np.clip(centre[1] * H - side / 2, 0, H - side))
    return x, y, side


def tile(img, height):
    h, w = img.shape[:2]
    return np.asarray(Image.fromarray(img).resize((round(w * height / h), height), Image.LANCZOS))


def sheet_rows(name, rgb8, maps, labels, centre, crop_frac=0.22):
    H, W = rgb8.shape[:2]
    x, y, side = crop_box(centre, crop_frac, (H, W))
    marked = Image.fromarray(rgb8.copy())
    ImageDraw.Draw(marked).rectangle([x, y, x + side, y + side], outline=(255, 255, 255), width=max(2, W // 300))
    top = [tile(np.asarray(marked), TILE_H)] + [tile(m, TILE_H) for m in maps]
    crops = [rgb8[y:y + side, x:x + side]] + [m[y:y + side, x:x + side] for m in maps]
    bottom = [np.asarray(Image.fromarray(c).resize((TILE_H, TILE_H), Image.NEAREST if side < TILE_H else Image.LANCZOS)) for c in crops]
    gap = 6
    width = max(sum(t.shape[1] for t in top) + gap * len(top), sum(b.shape[1] for b in bottom) + gap * len(bottom))
    canvas = Image.new("RGB", (width, 28 + TILE_H * 2 + gap * 2), (24, 24, 24))
    draw = ImageDraw.Draw(canvas)
    draw.text((4, 4), name, fill=(230, 230, 230), font=font(18))
    xo = 0
    for t, label in zip(top, ["photo"] + labels):
        canvas.paste(Image.fromarray(t), (xo, 28))
        draw.text((xo + 4, 28 + 4), label, fill=(255, 255, 255), font=font(15), stroke_width=2, stroke_fill=(0, 0, 0))
        xo += t.shape[1] + gap
    xo = 0
    for b in bottom:
        canvas.paste(Image.fromarray(b), (xo, 28 + TILE_H + gap))
        xo += b.shape[1] + gap
    return canvas


def save(rows, name):
    width = max(r.width for r in rows)
    canvas = Image.new("RGB", (width, sum(r.height + 8 for r in rows)), (24, 24, 24))
    yo = 0
    for r in rows:
        canvas.paste(r, (0, yo))
        yo += r.height + 8
    if canvas.width > 1900:
        canvas = canvas.resize((1900, round(canvas.height * 1900 / canvas.width)), Image.LANCZOS)
    target = IMAGES / f"lens-blur-depth-{name}.jpg"
    for quality in (88, 82, 76, 70, 62, 55):
        canvas.save(target, quality=quality, optimize=True, progressive=True)
        if target.stat().st_size < 400_000:
            break
    print(f"{target.relative_to(ROOT)}: {target.stat().st_size // 1024} KB")


def photos():
    for group, names in GROUPS.items():
        rows = []
        for name in names:
            bgr = cv2.imread(str(PHOTOS / f"{name}.jpg"))
            h, w = bgr.shape[:2]
            k = 1536 / max(h, w)
            rgb8 = cv2.resize(bgr, (round(w * k), round(h * k)), interpolation=cv2.INTER_AREA)[..., ::-1].copy()
            rgb = rgb8.astype(np.float32) / 255
            qs = [refined(s, r, pathlib.Path("photos") / name, rgb) for s, r, _ in COMBOS]
            centre = CROPS.get(name) or auto_crop(qs[-1], rgb)
            rows.append(sheet_rows(name, rgb8, [colour(q) for q in qs], [lab for _, _, lab in COMBOS], centre))
        save(rows, group)


def benchmark(scenes, labels, name):
    rows = []
    for set_name, scene, focus, centre, frac in scenes:
        folder = DATA / set_name / scene / focus
        rgb8 = np.round(common.linear_to_srgb(read_exr(folder / "input.exr")) * 255).astype(np.uint8)
        truth = 1 / read_exr(folder / "depth.exr")
        lo, hi = np.percentile(truth, [1, 99])
        maps = [colour(truth, lo, hi)]
        for label in labels:
            z = read_exr(ESTIMATED / label / set_name / scene / focus / "depth.exr")
            maps.append(colour(1 / z, lo, hi))
        centre = centre or auto_crop(cv2.GaussianBlur(truth.astype(np.float32), (0, 0), 1), rgb8.astype(np.float32) / 255)
        rows.append(sheet_rows(f"{set_name}/{scene}, focus on {focus}", rgb8, maps,
                               ["truth"] + [lab.split("+", 1)[0] + " " + lab.split("+", 1)[1] for lab in labels], centre, frac))
    save(rows, name)


if __name__ == "__main__":
    {"photos": photos, "benchmark": lambda: benchmark(BENCH_SCENES, BENCH_LABELS, "benchmark")}[sys.argv[1]]()
