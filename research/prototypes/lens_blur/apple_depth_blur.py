#!/usr/bin/env python3
"""Inputs for apple_depth_blur.swift, and its outputs back into the benchmark's layout (OTH-03).

    build/research-venv/bin/python research/prototypes/lens_blur/apple_depth_blur.py prep [--set layered]
    swift research/prototypes/lens_blur/apple_depth_blur.swift build/proto-out/lens_blur/apple-depth-blur/raw/jobs.json
    build/research-venv/bin/python research/prototypes/lens_blur/apple_depth_blur.py collect

prep writes raw little-endian float32 files (row 0 at the top) for each focus: the linear input as
RGBA, the disparity 1 / z in 1/m, the subject matte from alpha.exr, and each variant's truth, with
a focus rectangle: a box an eighth of the frame across centred on the subject's solid part (alpha
above 0.95), or for focus on the background the box a fifth of the frame across that holds the
most pixels within 3% of the focus distance. collect converts the
best render of each variant into an EXR for score.py.
"""

import json
import sys

import numpy as np

import common
import render_common as rc
from common import DATA, OUT

ROOT = OUT / "apple-depth-blur"
RAW = ROOT / "raw"


def focus_rect(depth, alpha, cam):
    h, w = depth.shape
    if cam["focus"] == "subject":
        # The subject's bounding box is mostly background for a seed head or a plant, and the
        # filter then focuses on the background; a box an eighth of the frame on its solid core.
        ys, xs = np.nonzero(alpha > 0.95)
        cx, cy = int(np.median(xs)), int(np.median(ys))
        bw, bh = w // 8, h // 8
        x0, y0 = min(max(cx - bw // 2, 0), w - bw), min(max(cy - bh // 2, 0), h - bh)
        return [x0, y0, bw, bh]
    s = cam["focus_distance_m"]
    near = (np.abs(depth / s - 1) < 0.03).astype(np.float64)
    bw, bh = w // 5, h // 5
    integral = np.pad(near.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    best, rect = -1, None
    for y in range(0, h - bh, 8):
        for x in range(0, w - bw, 8):
            v = integral[y + bh, x + bw] - integral[y, x + bw] - integral[y + bh, x] + integral[y, x]
            if v > best:
                best, rect = v, [x, y, bw, bh]
    return rect


def prep(sets):
    jobs = []
    for path in rc.variant_paths(sets):
        cam = json.loads(path.read_text())
        folder = path.parent
        rel = folder.relative_to(DATA)
        raw = RAW / rel
        raw.mkdir(parents=True, exist_ok=True)
        if not (raw / "input.f32").exists():
            image = common.read_exr(folder / "input.exr")
            rgba = np.concatenate([image, np.ones_like(image[..., :1])], -1)
            rgba.astype("<f4").tofile(raw / "input.f32")
            depth = common.read_exr(folder / "depth.exr")
            (1 / depth).astype("<f4").tofile(raw / "disparity.f32")
            common.read_exr(folder / "alpha.exr").clip(0, 1).astype("<f4").tofile(raw / "matte.f32")
        common.read_exr(path.with_suffix(".exr")).astype("<f4").tofile(raw / f"{path.stem}.truth.f32")
        depth = common.read_exr(folder / "depth.exr")
        alpha = common.read_exr(folder / "alpha.exr")
        jobs.append({"name": f"{rel}/{path.stem}", "width": cam["image"]["width"], "height": cam["image"]["height"],
                     "input": str(raw / "input.f32"), "disparity": str(raw / "disparity.f32"),
                     "matte": str(raw / "matte.f32"), "truth": str(raw / f"{path.stem}.truth.f32"),
                     "output": str(raw / f"{path.stem}.out.f32"), "focusRect": focus_rect(depth, alpha, cam)})
    (RAW / "jobs.json").write_text(json.dumps(jobs, indent=1))
    print(f"{len(jobs)} jobs in {RAW / 'jobs.json'}")


def collect():
    jobs = json.loads((RAW / "jobs.json").read_text())
    results = {r["name"]: r for r in json.loads((RAW / "results.json").read_text())}
    count = 0
    for job in jobs:
        out = np.fromfile(job["output"], "<f4") if job["name"] in results else None
        if out is None or out.size != job["width"] * job["height"] * 4:
            continue
        image = out.reshape(job["height"], job["width"], 4)[..., :3]
        common.write_exr(ROOT / f"{job['name']}.exr", image)
        count += 1
    apertures = [r["aperture"] for r in results.values()]
    print(f"collected {count}; best inputAperture median {np.median(apertures):.2f}, "
          f"range {min(apertures):.2f} to {max(apertures):.2f}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "prep":
        prep([args[args.index("--set") + 1]] if "--set" in args else ["layered"])
    else:
        collect()
