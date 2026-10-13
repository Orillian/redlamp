"""The assets of the Lightroom Lens Blur bench task: benchmark inputs as 16-bit sRGB TIFFs, CC0
portraits from the MSK-25 set and the iPhone and Pixel raw fixtures.

    build/research-venv/bin/python research/prototypes/lens_blur/bench_assets.py

Writes build/proto-out/lens_blur/bench-assets/. Copies of one photo that differ only by their
step's instructions carry a label in a corner, so they can be told apart in Lightroom.
"""

import shutil

import numpy as np
import tifffile
from PIL import Image, ImageDraw, ImageFont

from common import DATA, OUT, ROOT, linear_to_srgb, read_exr

ASSETS = OUT / "bench-assets"

LAYERED = ["portrait-leafy", "portrait-night", "portrait-fg-leaves", "portrait-city", "cat-leafy", "dandelion-night"]
BLENDER = ["tabletop", "night-street", "foliage-layers", "cobble-path"]
PORTRAITS = ["hair-busy-background-01", "hair-curly-02", "face-glasses-01", "pets-01"]
FIXTURES = ["IMG_1361.DNG", "PXL_20201121_100251397.dng"]
# Shapes Lightroom has beyond Circle, each on its own labelled copy of the night portrait.
SHAPES = ["5-blade", "bubble", "ring", "oval"]


def tiff(linear, path, label=None):
    """`linear` as 16-bit sRGB, clipped at white as a JPEG or HEIC would be."""
    encoded = np.clip(linear_to_srgb(np.clip(linear, 0, 1)), 0, 1)
    pixels = (encoded * 65535 + 0.5).astype(np.uint16)
    if label:
        mask = Image.new("L", (pixels.shape[1], pixels.shape[0]), 0)
        draw = ImageDraw.Draw(mask)
        font = ImageFont.load_default(size=max(14, pixels.shape[0] // 28))
        box = draw.textbbox((12, 10), label, font=font)
        pad = 6
        background = (box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)
        pixels[background[1]:background[3], background[0]:background[2]] = 0
        draw.text((12, 10), label, fill=255, font=font)
        text = np.asarray(mask) > 127
        pixels[text] = 65535
    tifffile.imwrite(path, pixels, photometric="rgb")


def main():
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    ASSETS.mkdir(parents=True)
    number = 1
    for scene in LAYERED:
        tiff(read_exr(DATA / "layered" / scene / "subject" / "input.exr"), ASSETS / f"lb-{number:02d}-{scene}.tif")
        number += 1
    for scene in BLENDER:
        tiff(read_exr(DATA / "blender" / scene / "subject" / "input.exr"), ASSETS / f"lb-{number:02d}-{scene}.tif")
        number += 1
    for name in PORTRAITS:
        shutil.copy(ROOT / "build/mask-eval" / f"{name}.jpg", ASSETS / f"lb-{number:02d}-{name}.jpg")
        number += 1
    for name in FIXTURES:
        stem, suffix = name.rsplit(".", 1)
        shutil.copy(ROOT / "tests/fixtures/raw" / name, ASSETS / f"lb-{number:02d}-{stem}.{suffix.lower()}")
        number += 1
    night = read_exr(DATA / "layered" / "portrait-night" / "subject" / "input.exr")
    for shape in SHAPES:
        tiff(night, ASSETS / f"lb-{number:02d}-portrait-night-{shape}.tif", label=shape.upper())
        number += 1
    print(f"{number - 1} assets in {ASSETS}")


if __name__ == "__main__":
    main()
