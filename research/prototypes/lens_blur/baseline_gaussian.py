#!/usr/bin/env python3
"""The floor: a per-pixel Gaussian blur whose sigma follows the exact CoC, with no occlusion handling.

    build/research-venv/bin/python research/prototypes/lens_blur/baseline_gaussian.py [--clipped] [--set layered|blender]

For each truth variant it reads input.exr (or input_clipped.exr), depth.exr and the variant's JSON,
sets sigma = |c_px| / 4 at each pixel (the Gaussian with a uniform disc's second moment), and
gathers: the image is blurred at a ladder of sigmas and each pixel interpolates between the two
levels around its own sigma, capped at 64 px. The aperture's shape is ignored. Writes
build/proto-out/lens_blur/baseline-gaussian[-clipped]/<set>/<scene>/<focus>/<variant>.exr.
"""

import json
import sys
import time

import cv2
import numpy as np

import common
from common import DATA, OUT, read_exr, write_exr


MAX_SIGMA = 64.0


def blur_stack(image, sigmas):
    out = []
    for sigma in sigmas:
        if sigma == 0:
            out.append(image)
        else:
            k = int(np.ceil(sigma * 3)) * 2 + 1
            out.append(cv2.GaussianBlur(image, (k, k), sigma, borderType=cv2.BORDER_REFLECT))
    return out


def render(image, depth, cam):
    sigma = np.minimum(np.abs(common.coc_px(cam, depth)) / 4, MAX_SIGMA).astype(np.float32)
    top = float(sigma.max())
    sigmas = [0.0] + list(np.geomspace(0.25, max(top, 0.3), 24))
    stack = blur_stack(image, sigmas)
    levels = np.asarray(sigmas, np.float32)
    upper = np.clip(np.searchsorted(levels, sigma), 1, len(levels) - 1)
    lower = upper - 1
    t = np.clip((sigma - levels[lower]) / (levels[upper] - levels[lower]), 0, 1)[..., None]
    stack = np.stack(stack)
    rows, cols = np.indices(sigma.shape)
    return (1 - t) * stack[lower, rows, cols] + t * stack[upper, rows, cols]


def main(argv):
    clipped = "--clipped" in argv
    sets = [argv[argv.index("--set") + 1]] if "--set" in argv else ["layered", "blender"]
    name = "baseline-gaussian-clipped" if clipped else "baseline-gaussian"
    started = time.time()
    count = 0
    for path in sorted(p for s in sets for p in (DATA / s).glob("*/*/f*.json")):
        cam = json.loads(path.read_text())
        folder = path.parent
        image = read_exr(folder / ("input_clipped.exr" if clipped else "input.exr"))
        depth = read_exr(folder / "depth.exr")
        write_exr(OUT / name / path.relative_to(DATA).with_suffix(".exr"), render(image, depth, cam))
        count += 1
    print(f"{name}: {count} variants in {time.time() - started:.0f} s")


if __name__ == "__main__":
    main(sys.argv[1:])
