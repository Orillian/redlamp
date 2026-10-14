#!/usr/bin/env python3
"""Realistic subject mattes for the two-layer depth treatment (OTH-03): ViTMatte from a coarse trimap.

    build/lens-blur-depth-venv/bin/python research/prototypes/lens_blur/depth_mattes.py [--set layered|blender]

The trimap stands in for what a subject mask gives the app, made from the benchmark's visible subject
alpha (alpha.exr, times 1 - occluder.exr where there is one): blurred with a Gaussian of sigma 0.3% of
the width (3 px at 1024), thresholded at 0.5, then foreground is that eroded by a disc of 1% of the
width (10 px at 1024), unknown is it dilated by the same disc less the foreground, and the rest is
background. So strands and wisps beyond 10 px of the blurred silhouette are background, as a
segmentation mask would leave them. ViTMatte-base (hustvl/vitmatte-base-composition-1k, Apache-2.0,
DEC-35) mattes the sRGB input at full size on MPS; known regions keep 0 and 1. Writes
build/proto-out/lens_blur/depth-mattes/<set>/<scene>/<focus>/vitmatte.npy, trimap.png and matte.png,
and prints each matte's SAD and MSE against the alpha in the unknown band.
"""

import pathlib
import sys
import time

import cv2
import numpy as np
import torch
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import common  # noqa: E402
from common import DATA, OUT, read_exr  # noqa: E402
from depth_eval import disc  # noqa: E402

MATTES = OUT / "depth-mattes"


def visible_alpha(folder):
    alpha = read_exr(folder / "alpha.exr")
    if (folder / "occluder.exr").exists():
        alpha = alpha * (1 - read_exr(folder / "occluder.exr"))
    return np.clip(alpha, 0, 1)


def trimap(alpha):
    width = alpha.shape[1]
    blurred = cv2.GaussianBlur(alpha, (0, 0), 0.003 * width)
    inside = blurred > 0.5
    r = round(0.01 * width)
    fg = ndimage.binary_erosion(inside, structure=disc(r))
    unknown = ndimage.binary_dilation(inside, structure=disc(r)) & ~fg
    t = np.zeros(alpha.shape, np.float32)
    t[unknown] = 0.5
    t[fg] = 1
    return t


def main(argv):
    from transformers import VitMatteForImageMatting, VitMatteImageProcessor
    sets = [argv[argv.index("--set") + 1]] if "--set" in argv else ["layered", "blender"]
    name = "hustvl/vitmatte-base-composition-1k"
    processor = VitMatteImageProcessor.from_pretrained(name)
    model = VitMatteForImageMatting.from_pretrained(name).to("mps").eval()
    for set_name in sets:
        for folder in sorted((DATA / set_name).glob("*/*/alpha.exr")):
            folder = folder.parent
            scene, focus = folder.parts[-2], folder.parts[-1]
            if "@" in scene:
                continue
            alpha = visible_alpha(folder)
            t = trimap(alpha)
            rgb8 = np.round(common.linear_to_srgb(read_exr(folder / "input.exr")) * 255).astype(np.uint8)
            inputs = processor(images=Image.fromarray(rgb8), trimaps=Image.fromarray((t * 255).astype(np.uint8)),
                               return_tensors="pt").to("mps")
            started = time.perf_counter()
            with torch.no_grad():
                out = model(**inputs).alphas[0, 0].float().cpu().numpy()
            seconds = time.perf_counter() - started
            h, w = alpha.shape
            m = np.clip(out[:h, :w], 0, 1)
            m[t == 1] = 1
            m[t == 0] = 0
            target = MATTES / set_name / scene / focus
            target.mkdir(parents=True, exist_ok=True)
            np.save(target / "vitmatte.npy", m.astype(np.float32))
            Image.fromarray((t * 255).astype(np.uint8)).save(target / "trimap.png")
            Image.fromarray((m * 255 + 0.5).astype(np.uint8)).save(target / "matte.png")
            band = t == 0.5
            sad = float(np.abs(m - alpha)[band].sum() / 1000)
            mse = float(((m - alpha) ** 2)[band].mean())
            missed = float(alpha[t == 0].sum() / max(alpha.sum(), 1e-9))
            print(f"{set_name}/{scene}/{focus}: SAD {sad:.1f}k, MSE {mse:.4f}, alpha outside trimap {missed:.3%}, "
                  f"{seconds:.1f} s", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
