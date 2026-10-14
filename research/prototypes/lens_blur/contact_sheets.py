#!/usr/bin/env python3
"""Contact sheets of crops for the lens blur renderers (OTH-03): hair, foregrounds, lights, clipped lights.

    build/research-venv/bin/python research/prototypes/lens_blur/contact_sheets.py

Writes docs/research/images/lens-blur-renderers-<sheet>.jpg: one row per renderer (the truth first),
one column per crop, tone mapped as score.py does, 1:1 pixels. Crops are placed from the benchmark's
own data: the top of the subject's matte for hair, the soft edge of a nearer occluder over the
subject for foregrounds, and the largest clean light for lights. All content is CC0.
"""

import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

import common
from common import DATA, OUT, ROOT
from score import tone_map

CELL = 176
LABEL = 190
HEAD = 30
IMAGES = ROOT / "docs/research/images"

ROWS = [("truth", None), ("baseline Gaussian", "baseline-gaussian"), ("gather", "gather"),
        ("gather + sprites", "gather-sprites"), ("gather, coarse matte", "gather-matte-coarse"),
        ("layers plain", "layers-plain"), ("layers fill", "layers-fill"),
        ("layers, exact matte (oracle)", "layers-oracle"), ("Core Image depth blur", "apple-depth-blur")]
CLIPPED_ROWS = [("truth (unclipped)", None), ("baseline, clipped", "baseline-gaussian-clipped"),
                ("gather, clipped", "gather-clipped"), ("gather + sprites + recovery", "gather-sprites-clipped"),
                ("layers fill, clipped", "layers-fill-clipped"), ("layers + sprites + recovery", "layers-fill-sprites-clipped")]

SHEETS = {
    "hair": [("layered", "portrait-night", "subject", "f1.4-circle"), ("layered", "dandelion-sea", "subject", "f1.4-circle"),
             ("layered", "cat-overcast", "subject", "f1.4-circle"), ("layered", "portrait-leafy", "background", "f1.4-circle")],
    "foreground": [("layered", "portrait-fg-leaves", "subject", "f1.4-circle"), ("layered", "portrait-horizon", "subject", "f2.8-circle"),
                   ("layered", "cat-overcast", "subject", "f2.8-blade5"), ("blender", "foliage-layers", "subject", "f1.8-circle"),
                   ("blender", "tabletop", "background", "f1.8-circle")],
    "lights": [("layered", "portrait-night", "subject", "f1.4-circle"), ("layered", "portrait-city", "subject", "f2.8-blade5"),
               ("layered", "dandelion-night", "subject", "f1.4-oval"), ("blender", "night-street", "subject", "f1.8-blade5")],
}
SHEETS["clipped"] = SHEETS["lights"][:3] + [("layered", "portrait-stripes", "subject", "f2.8-blade7")]


def centre(kind, folder, cam, image_shape):
    h, w = image_shape
    if kind == "hair":
        alpha = common.read_exr(folder / "alpha.exr")
        ys, xs = np.nonzero(alpha > 0.5)
        top = ys.min()
        return int(top + CELL * 0.35), int(np.median(xs[ys < top + 20]))
    if kind == "foreground":
        alpha = common.read_exr(folder / "alpha.exr")
        if (folder / "occluder.exr").exists():
            occ = common.read_exr(folder / "occluder.exr")
            edge = (occ > 0.2) & (occ < 0.8) & ndimage.binary_dilation(alpha > 0.5, iterations=12)
        else:
            depth = common.read_exr(folder / "depth.exr")
            near = depth < 0.8 * cam["focus_distance_m"]
            edge = ndimage.binary_dilation(near, iterations=3) & ~near
            if (edge & (alpha > 0.5)).any():
                edge &= alpha > 0.5
        ys, xs = np.nonzero(edge)
        i = len(ys) // 2
        order = np.argsort(ys)
        return int(ys[order[i]]), int(xs[order[i]])
    lights = [l for l in cam["lights"] if CELL / 2 < l["x"] < w - CELL / 2 and CELL / 2 < l["y"] < h - CELL / 2
              and abs(l["coc_px"]) < CELL - 16]
    best = max(lights, key=lambda l: (abs(l["coc_px"]) * (1 if max(l["value"]) > 1 else 0.3), max(l["value"])))
    return int(best["y"]), int(best["x"])


def crop(image, cy, cx):
    h, w = image.shape[:2]
    y0 = min(max(cy - CELL // 2, 0), h - CELL)
    x0 = min(max(cx - CELL // 2, 0), w - CELL)
    return image[y0:y0 + CELL, x0:x0 + CELL]


def sheet(name, crops, rows):
    font = ImageFont.load_default(size=13)
    canvas = Image.new("RGB", (LABEL + CELL * len(crops), HEAD + CELL * len(rows)), (24, 24, 24))
    draw = ImageDraw.Draw(canvas)
    for j, (set_name, scene, focus, variant) in enumerate(crops):
        path = DATA / set_name / scene / focus / f"{variant}.json"
        cam = json.loads(path.read_text())
        truth = common.read_exr(path.with_suffix(".exr"))
        cy, cx = centre("lights" if name == "clipped" else name, path.parent, cam, truth.shape[:2])
        draw.text((LABEL + j * CELL + 4, 2), f"{scene}", fill=(230, 230, 230), font=font)
        draw.text((LABEL + j * CELL + 4, 15), f"{focus} {variant}", fill=(170, 170, 170), font=font)
        for i, (label, renderer) in enumerate(rows):
            if j == 0:
                draw.text((6, HEAD + i * CELL + CELL // 2 - 8), label, fill=(230, 230, 230), font=font)
            image = truth if renderer is None else None
            if renderer is not None:
                out = OUT / renderer / path.relative_to(DATA).with_suffix(".exr")
                if not out.exists():
                    continue
                image = common.read_exr(out)
            tile = (tone_map(crop(image, cy, cx)) * 255 + 0.5).astype(np.uint8)
            canvas.paste(Image.fromarray(tile), (LABEL + j * CELL, HEAD + i * CELL))
    IMAGES.mkdir(parents=True, exist_ok=True)
    target = IMAGES / f"lens-blur-renderers-{name}.jpg"
    for quality in (88, 82, 76, 70, 64):
        canvas.save(target, quality=quality, optimize=True)
        if target.stat().st_size < 400_000:
            break
    print(f"{target.relative_to(ROOT)}: {target.stat().st_size // 1024} KB")


def main():
    for name, crops in SHEETS.items():
        sheet(name, crops, CLIPPED_ROWS if name == "clipped" else ROWS)


if __name__ == "__main__":
    main()
