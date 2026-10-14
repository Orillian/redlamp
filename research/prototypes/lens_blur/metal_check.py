#!/usr/bin/env python3
"""Inputs for the Metal harness, and its output against the Python gather (OTH-03).

    build/research-venv/bin/python research/prototypes/lens_blur/metal_check.py prep [--scene S --focus F --variant V]
    build/proto-out/lens_blur/metal/gather check build/proto-out/lens_blur/metal/check
    build/research-venv/bin/python research/prototypes/lens_blur/metal_check.py compare

prep writes one variant's input with its signed CoC radius (RGBA float32), its log depth and
params.json, and renders the same variant with render_gather.gather. compare reports the PSNR between
the two after score.py's tone map, and against the truth.
"""

import json
import math
import sys

import numpy as np

import common
import render_common as rc
import render_gather
from common import DATA, OUT
from score import tone_map

CHECK = OUT / "metal" / "check"


def psnr(a, b):
    return 10 * math.log10(1 / max(float(((tone_map(a) - tone_map(b)) ** 2).mean()), 1e-12))


def main(argv):
    opts = rc.parse_args(argv[1:], {"--kappa": 16.0})
    scene = (opts["scenes"] or ["portrait-leafy"])[0]
    focus = opts["focus"] or "subject"
    variant = (opts["variants"] or ["f1.4-circle"])[0]
    path = DATA / "layered" / scene / focus / f"{variant}.json"
    if argv[0] == "prep":
        cam = json.loads(path.read_text())
        image, depth = rc.load(path.parent)
        r = (common.coc_px(cam, depth) / 2).astype(np.float32)
        CHECK.mkdir(parents=True, exist_ok=True)
        np.concatenate([image, r[..., None]], -1).astype("<f4").tofile(CHECK / "colour.f32")
        np.log(depth).astype("<f4").tofile(CHECK / "logz.f32")
        ap = cam["aperture"]
        common.write_json(CHECK / "params.json", {
            "width": cam["image"]["width"], "height": cam["image"]["height"], "kappa": opts["values"]["--kappa"],
            "aperture": {"blades": ap["blades"], "rotation": ap["rotation_rad"], "ratio": ap["ratio"]},
            "variant": str(path.relative_to(DATA))})
        out, _, n = render_gather.gather(image, depth, cam, opts["values"]["--kappa"])
        out.permute(1, 2, 0).cpu().numpy().astype("<f4").tofile(CHECK / "python.f32")
        print(f"prepared {path.relative_to(DATA)}, {n} samples")
    else:
        params = json.loads((CHECK / "params.json").read_text())
        h, w = params["height"], params["width"]
        python = np.fromfile(CHECK / "python.f32", "<f4").reshape(h, w, 3)
        metal = np.fromfile(CHECK / "metal.f32", "<f4").reshape(h, w, 4)[..., :3]
        truth = common.read_exr(DATA / params["variant"].replace(".json", ".exr"))
        print(f"{params['variant']}: Metal against Python {psnr(metal, python):.2f} dB "
              f"(largest difference {np.abs(metal - python).max():.4f}); "
              f"against the truth, Python {psnr(python, truth):.2f} dB, Metal {psnr(metal, truth):.2f} dB")


if __name__ == "__main__":
    main(sys.argv[1:])
