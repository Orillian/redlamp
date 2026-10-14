"""Shared pieces of the lens blur renderers (OTH-03): variants, aperture shapes, pull-push fill, lights.

Offsets are in image pixels, x right and y down. A pixel p sees a plane at p + (a_x, -a_y) r, a being
the lens point in the unit aperture (y up) and r the signed CoC radius (positive in front of focus),
so a source at offset o = x_source - p reaches p when (o_x, -o_y) / r lies in the aperture.
"""

import json
import math
import time

import numpy as np
import torch
import torch.nn.functional as F

import common
from common import DATA, OUT, read_exr, write_exr

DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
LUMA = torch.tensor([0.2126, 0.7152, 0.0722])


def variant_paths(sets, scenes=None, focus=None, variants=None):
    paths = sorted(p for s in sets for p in (DATA / s).glob("*/*/f*.json"))
    return [p for p in paths
            if (not scenes or p.parts[-3] in scenes) and (not focus or p.parts[-2] == focus)
            and (not variants or p.stem in variants)]


def parse_args(argv, defaults=()):
    """--set, --scene, --focus, --variant (each repeatable) plus the flags named in defaults."""
    opts = {"sets": [], "scenes": [], "focus": None, "variants": [], "flags": set(), "values": {}}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--set":
            opts["sets"].append(argv[i + 1]); i += 2
        elif a == "--scene":
            opts["scenes"].append(argv[i + 1]); i += 2
        elif a == "--focus":
            opts["focus"] = argv[i + 1]; i += 2
        elif a == "--variant":
            opts["variants"].append(argv[i + 1]); i += 2
        elif a in defaults and defaults[a] is not None:
            opts["values"][a] = type(defaults[a])(argv[i + 1]); i += 2
        else:
            opts["flags"].add(a); i += 1
    opts["sets"] = opts["sets"] or ["layered", "blender"]
    for key, value in dict(defaults).items():
        if value is not None:
            opts["values"].setdefault(key, value)
    return opts


def output_path(renderer, json_path):
    return OUT / renderer / json_path.relative_to(DATA).with_suffix(".exr")


def run(renderer, paths, render_one, log_every=10):
    """Renders each variant with render_one(json_path, cam) -> (H, W, 3) array; returns seconds."""
    started = time.time()
    retries = 0
    for i, path in enumerate(paths):
        cam = json.loads(path.read_text())
        image = render_one(path, cam)
        # MPS has returned non-finite frames under heavy GPU contention; the same render then succeeds.
        while not np.isfinite(image).all() and retries < 20:
            retries += 1
            print(f"{renderer}: {path.relative_to(DATA)} had non-finite pixels, rendering again", flush=True)
            image = render_one(path, cam)
        write_exr(output_path(renderer, path), image)
        if i % log_every == 0:
            print(f"{renderer}: {i + 1}/{len(paths)} {path.relative_to(DATA)} {time.time() - started:.0f} s", flush=True)
    seconds = time.time() - started
    print(f"{renderer}: {len(paths)} variants in {seconds:.0f} s ({seconds / max(len(paths), 1):.2f} s each)", flush=True)
    return seconds


def to_t(x):
    return torch.from_numpy(np.ascontiguousarray(x, dtype=np.float32)).to(DEVICE)


def load(folder, clipped=False):
    image = read_exr(folder / ("input_clipped.exr" if clipped else "input.exr"))
    depth = read_exr(folder / "depth.exr")
    return image, depth


def matte(folder, kind="exact"):
    """The subject's alpha: exact (alpha.exr, an oracle) or coarse, as a segmentation mask without
    strand detail would be (alpha above 0.5, feathered by a 1.5 px Gaussian)."""
    from scipy import ndimage
    alpha = read_exr(folder / "alpha.exr").clip(0, 1)
    if kind == "coarse":
        alpha = ndimage.gaussian_filter((alpha > 0.5).astype(np.float32), 1.5)
    return alpha.astype(np.float32)


def subject_depth(depth, alpha):
    """The subject's own depth everywhere, from where it is solid (pull-push in disparity)."""
    z = to_t(depth)
    disparity = pull_push((1 / z)[None], to_t((alpha > 0.95).astype(np.float32)))[0]
    return (1 / disparity.clamp_min(1e-4)).cpu().numpy()


# MARK: - Aperture

def aperture_distance(ax, ay, cam):
    """Signed distance in aperture radii from the unit aperture's edge (negative inside), lens coords."""
    ap = cam["aperture"]
    blades, rotation, ratio = ap["blades"], ap["rotation_rad"], ap["ratio"]
    if blades == 0:
        return np.hypot(ax * ratio, ay) - 1
    apothem = math.cos(math.pi / blades)
    d = np.full(np.shape(ax), -np.inf)
    for k in range(blades):
        mid = rotation + 2 * math.pi * k / blades
        d = np.maximum(d, ax * math.cos(mid) + ay * math.sin(mid) - apothem)
    return d


def aperture_area(cam):
    ap = cam["aperture"]
    if ap["blades"] == 0:
        return math.pi / ap["ratio"]
    n = ap["blades"]
    return n / 2 * math.sin(2 * math.pi / n)


def kernel(radius, cam, front, supersample=4):
    """The aperture's image for a source with CoC radius |radius| px, as an odd square summing to 1.

    Indexed [dy, dx] by the output pixel's offset from the source, d = p - x_source.
    """
    r = abs(radius)
    half = int(math.ceil(r)) + 1
    t = (np.arange((2 * half + 1) * supersample) + 0.5) / supersample - half - 0.5
    dx, dy = np.meshgrid(t, t)
    if r < 0.5:
        k = np.zeros((2 * half + 1, 2 * half + 1), np.float32)
        k[half, half] = 1
        return k
    # o = -d; a = (o_x, -o_y) / r_signed.
    sign = 1 if front else -1
    ax, ay = sign * (-dx) / r, sign * dy / r
    inside = aperture_distance(ax, ay, cam) <= 0
    k = inside.reshape(2 * half + 1, supersample, 2 * half + 1, supersample).mean(axis=(1, 3))
    return (k / k.sum()).astype(np.float32)


# MARK: - Fill

def pull_push(values, weight, levels=None):
    """Fills values (C, H, W) where weight (H, W) in [0, 1] is low, from a box pyramid of the known ones."""
    c, h, w = values.shape
    levels = levels or int(math.ceil(math.log2(max(h, w)))) + 1
    pyramid = []
    v, wt = values * weight, weight[None]
    for _ in range(levels):
        pyramid.append((v, wt))
        lh, lw = v.shape[-2:]
        if lh <= 1 and lw <= 1:
            break
        # Odd sizes get a zero-weight row or column; avg_pool2d's ceil_mode has returned NaN on MPS.
        v = F.avg_pool2d(F.pad(v[None], (0, lw % 2, 0, lh % 2)), 2)[0]
        wt = F.avg_pool2d(F.pad(wt[None], (0, lw % 2, 0, lh % 2)), 2)[0]
    filled = pyramid[-1][0] / pyramid[-1][1].clamp_min(1e-8)
    for v, wt in reversed(pyramid[:-1]):
        lh, lw = v.shape[-2:]
        up = F.interpolate(filled[None], scale_factor=2, mode="bilinear", align_corners=False)[0][:, :lh, :lw]
        a = (wt * 2).clamp(0, 1)
        filled = a * v / wt.clamp_min(1e-8) + (1 - a) * up
    return filled


# MARK: - Lights

def detect_lights(image, depth, clipped_input, gain=16.0, knee=0.9, max_area=60, max_extent=8):
    """Small bright lights in linear light, as (base, energy, labels, light list).

    A light is a compact connected region whose luminance stands at least 0.25 above and 3 times
    over its surroundings (a 15 px median), at most max_area pixels and max_extent across, filling
    at least 45% of its bounding box, with depth within 10% across it and 2 px around it, before
    its 2 px dilation. energy holds
    each light's light above the surroundings (with the clip recovery when clipped_input), base the
    image with it taken out.
    """
    from scipy import ndimage
    y = image @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    around = ndimage.median_filter(y, size=15)
    seed = (y > around * 3) & (y - around > 0.25)
    labels, n = ndimage.label(seed, structure=np.ones((3, 3)))
    if n == 0:
        return image, np.zeros_like(image), labels, []
    areas = ndimage.sum_labels(np.ones_like(y), labels, index=np.arange(1, n + 1))
    keep = np.zeros(n + 1, bool)
    # Compact, and on even depth: a backlit strand of hair is small and bright too, but long and
    # thin, and sits on a depth edge.
    near = ndimage.minimum_filter(depth, size=5)
    far = ndimage.maximum_filter(depth, size=5)
    for i, sl in enumerate(ndimage.find_objects(labels)):
        bh, bw = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        m = labels[sl] == i + 1
        even = far[sl][m].max() < 1.1 * near[sl][m].min()
        keep[i + 1] = areas[i] <= max_area and max(bh, bw) <= max_extent and areas[i] >= 0.45 * bh * bw and even
    small = keep[labels]
    grown = ndimage.binary_dilation(small, iterations=2)
    # The surroundings, filled over the lights.
    known = torch.from_numpy((~grown).astype(np.float32))
    fill = pull_push(torch.from_numpy(np.ascontiguousarray(image.transpose(2, 0, 1))), known).permute(1, 2, 0).numpy()
    energy = np.where(grown[..., None], np.maximum(image - fill, 0), 0).astype(np.float32)
    if clipped_input:
        peak = image.max(axis=2)
        t = np.clip((peak - knee) / (1 - knee), 0, 1)
        g = 1 + (gain - 1) * t * t * (3 - 2 * t)
        energy = energy + np.where(grown[..., None], image * (g - 1)[..., None], 0)
    base = image - np.where(grown[..., None], np.maximum(image - fill, 0), 0)
    grown_labels, _ = ndimage.label(grown, structure=np.ones((3, 3)))
    lights = []
    for i, sl in enumerate(ndimage.find_objects(grown_labels)):
        if sl is None:
            continue
        m = grown_labels[sl] == i + 1
        core = m & small[sl]
        z = float(np.median(depth[sl][core])) if core.any() else float(np.median(depth[sl][m]))
        lights.append({"label": i + 1, "slice": sl, "depth": z,
                       "energy": float((energy[sl][m] @ np.array([0.2126, 0.7152, 0.0722])).sum())})
    return base.astype(np.float32), energy, grown_labels, lights
