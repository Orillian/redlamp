#!/usr/bin/env python3
"""Runs the depth models of the OTH-03 bake-off on the benchmark's inputs and keeps their raw output.

    build/lens-blur-depth-venv/bin/python research/prototypes/lens_blur/depth_estimate.py <source>... \
        [--set layered|blender] [--photos <name>...]

A source is `<model>@<size>`: `da3-mono-l`, `da3-small`, `da3-base`, `v2-small`, `moge2-s`, `moge2-b`,
`moge2-l`, at `app` (the app's input: 504x336 for DA3, 518x392 for V2, squashed; MoGe has no app size
and takes DA3's), `2x` (twice that) or `<w>x<h>`; `<model>@tiled` runs the app size on overlapping
tiles of a 2x copy and merges them (`merge_tiles`). Each input.exr is converted to sRGB with the
transfer curve, clipped and rounded to 8 bits, resized to the model's input (area when shrinking,
bicubic when enlarging) and inferred on MPS. The raw output, at the model's resolution, goes to
build/proto-out/lens_blur/depth-raw/<source>/<set>/<scene>/<focus>/raw.npy with `kind`: `depth`
(larger is farther; DA3, MoGe) or `disparity` (larger is nearer; V2). `timing.json` beside the
source holds each photo's forward time (MPS synchronised, after a warm-up) and `uptime`.

`--photos` runs real photos instead (build/mask-eval/<name>.jpg, long side resized to 1536 first)
into depth-raw/<source>/photos/<name>/raw.npy.
"""

import json
import pathlib
import subprocess
import sys
import time

import numpy as np
import torch
import torch.nn.functional as F

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import common  # noqa: E402
from common import DATA, OUT, PHOTOS, read_exr  # noqa: E402

RAW = OUT / "depth-raw"
DEVICE = torch.device("mps")
MEAN = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1)
STD = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
APP_SIZE = {"da3": (504, 336), "v2": (518, 392), "moge2": (504, 336)}
HF = {
    "da3-mono-l": "depth-anything/DA3MONO-LARGE", "da3-small": "depth-anything/DA3-SMALL",
    "da3-base": "depth-anything/DA3-BASE", "v2-small": "depth-anything/Depth-Anything-V2-Small-hf",
    "moge2-s": "Ruicheng/moge-2-vits-normal", "moge2-b": "Ruicheng/moge-2-vitb-normal",
    "moge2-l": "Ruicheng/moge-2-vitl-normal",
}


def family(model):
    return model.split("-")[0]


class Model:
    def __init__(self, name):
        self.name = name
        self.family = family(name)
        if self.family == "da3":
            from depth_anything_3.api import DepthAnything3
            self.net = DepthAnything3.from_pretrained(HF[name]).to(DEVICE).eval()
            self.kind = "depth"
        elif self.family == "v2":
            from transformers import AutoModelForDepthEstimation
            self.net = AutoModelForDepthEstimation.from_pretrained(HF[name]).to(DEVICE).eval()
            self.kind = "disparity"
        else:
            from moge.model.v2 import MoGeModel
            self.net = MoGeModel.from_pretrained(HF[name]).to(DEVICE).eval()
            self.kind = "depth"

    @torch.inference_mode()
    def __call__(self, rgb):
        """rgb: float32 (H, W, 3) sRGB in [0, 1], already at the model's input size (multiples of 14)."""
        x = torch.from_numpy(rgb).permute(2, 0, 1)[None].contiguous()
        h, w = rgb.shape[:2]
        if self.family == "moge2":
            out = self.net.infer(x.to(DEVICE), num_tokens=(h // 14) * (w // 14), apply_mask=False,
                                 use_fp16=False)
            return out["depth"].float().reshape(h, w)
        x = ((x - MEAN) / STD).to(DEVICE)
        if self.family == "da3":
            return self.net.forward(x[:, None], export_feat_layers=[], ref_view_strategy="first")["depth"].float().reshape(h, w)
        return self.net(pixel_values=x).predicted_depth.float().reshape(h, w)


def srgb8(linear):
    return np.round(common.linear_to_srgb(linear) * 255).astype(np.uint8)


def resize(rgb8, size):
    import cv2
    w, h = size
    shrink = w < rgb8.shape[1]
    return cv2.resize(rgb8, (w, h), interpolation=cv2.INTER_AREA if shrink else cv2.INTER_CUBIC)


def parse_size(model, spec):
    base = APP_SIZE[family(model)]
    if spec == "app":
        return base
    if spec == "2x":
        return base[0] * 2, base[1] * 2
    if spec.endswith("x") and spec[:-1].replace(".", "").isdigit():
        k = float(spec[:-1])
        return int(round(base[0] * k / 14)) * 14, int(round(base[1] * k / 14)) * 14
    w, h = spec.split("x")
    return int(w), int(h)


def run_model(model, rgb8, size):
    rgb = resize(rgb8, size).astype(np.float32) / 255
    if DEVICE.type == "mps":
        torch.mps.synchronize()
    started = time.perf_counter()
    out = model(rgb)
    if DEVICE.type == "mps":
        torch.mps.synchronize()
    return out.cpu().numpy().astype(np.float32), time.perf_counter() - started


def merge_tiles(model, rgb8):
    """The app size on a 3x3 grid of half-overlapping tiles of a 2x copy, each fitted to the global
    estimate (affine in the model's own output) and blended with raised-cosine weights; then the
    global estimate's low frequencies with the tiles' high frequencies (Gaussian sigma 8 px)."""
    import cv2
    tw, th = APP_SIZE[model.family]
    W, H = tw * 2, th * 2
    glob, t0 = run_model(model, rgb8, (tw, th))
    big = resize(rgb8, (W, H)).astype(np.float32) / 255
    glob_big = cv2.resize(glob, (W, H), interpolation=cv2.INTER_LINEAR)
    acc = np.zeros((H, W), np.float64)
    wsum = np.zeros((H, W), np.float64)
    wy = np.sin(np.linspace(0, np.pi, th + 2)[1:-1])[:, None]
    wx = np.sin(np.linspace(0, np.pi, tw + 2)[1:-1])[None, :]
    weight = (wy * wx) ** 2
    seconds = t0
    for y0 in (0, th // 2, H - th):
        for x0 in (0, tw // 2, W - tw):
            tile = big[y0:y0 + th, x0:x0 + tw]
            if DEVICE.type == "mps":
                torch.mps.synchronize()
            started = time.perf_counter()
            out = model(tile)
            if DEVICE.type == "mps":
                torch.mps.synchronize()
            seconds += time.perf_counter() - started
            out = out.cpu().numpy().astype(np.float64)
            ref = glob_big[y0:y0 + th, x0:x0 + tw].astype(np.float64)
            A = np.stack([out.ravel(), np.ones(out.size)], 1)
            coef, *_ = np.linalg.lstsq(A, ref.ravel(), rcond=None)
            acc[y0:y0 + th, x0:x0 + tw] += weight * (coef[0] * out + coef[1])
            wsum[y0:y0 + th, x0:x0 + tw] += weight
    tiles = (acc / np.maximum(wsum, 1e-9)).astype(np.float32)
    low = cv2.GaussianBlur(glob_big, (0, 0), 8)
    merged = low + tiles - cv2.GaussianBlur(tiles, (0, 0), 8)
    return merged.astype(np.float32), seconds


def uptime():
    return subprocess.run(["uptime"], capture_output=True, text=True).stdout.strip()


def inputs(sets, photos):
    if photos:
        import cv2
        for name in photos:
            bgr = cv2.imread(str(PHOTOS / f"{name}.jpg"))
            h, w = bgr.shape[:2]
            k = 1536 / max(h, w)
            rgb8 = cv2.resize(bgr, (round(w * k), round(h * k)), interpolation=cv2.INTER_AREA)[..., ::-1].copy()
            yield pathlib.Path("photos") / name, rgb8
        return
    for set_name in sets:
        for folder in sorted((DATA / set_name).glob("*/*/input.exr")):
            scene = folder.parts[-3]
            if "@" in scene:
                continue
            yield pathlib.Path(set_name) / scene / folder.parts[-2], srgb8(read_exr(folder))


def main(argv):
    sets = [argv[argv.index("--set") + 1]] if "--set" in argv else ["layered", "blender"]
    photos = argv[argv.index("--photos") + 1:] if "--photos" in argv else []
    sources = [a for a in argv[:argv.index("--photos")] if "@" in a] if photos else [a for a in argv if "@" in a]
    for source in sources:
        name, spec = source.split("@")
        load_started = time.perf_counter()
        model = Model(name)
        load_seconds = time.perf_counter() - load_started
        timings = []
        items = list(inputs(sets, photos))
        before = uptime()
        for index, (relative, rgb8) in enumerate(items):
            if spec == "tiled":
                raw, seconds = merge_tiles(model, rgb8)
            else:
                size = parse_size(name, spec)
                if photos and rgb8.shape[0] > rgb8.shape[1]:
                    size = size[::-1]
                if index == 0:
                    run_model(model, rgb8, size)
                raw, seconds = run_model(model, rgb8, size)
            folder = RAW / source / relative
            folder.mkdir(parents=True, exist_ok=True)
            np.save(folder / "raw.npy", raw)
            (folder / "meta.json").write_text(json.dumps({"kind": model.kind, "shape": raw.shape, "seconds": seconds}))
            timings.append({"input": str(relative), "seconds": seconds})
            print(f"{source} {relative}: {raw.shape} {seconds * 1000:.0f} ms", flush=True)
        record = {"source": source, "model": HF[name], "kind": model.kind, "load_seconds": load_seconds,
                  "median_seconds": float(np.median([t["seconds"] for t in timings])), "uptime_before": before,
                  "uptime_after": uptime(), "photos": timings}
        target = RAW / source / ("timing-photos.json" if photos else f"timing-{'-'.join(sets)}.json")
        target.write_text(json.dumps(record, indent=1))
        print(f"{source}: median {record['median_seconds'] * 1000:.0f} ms; {record['uptime_after']}", flush=True)
        del model
        torch.mps.empty_cache()


if __name__ == "__main__":
    main(sys.argv[1:])
