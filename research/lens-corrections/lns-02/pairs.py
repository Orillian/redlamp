"""Saves SIFT point pairs between each sample's camera JPEG and its uncorrected LibRaw render.

pairs/<name>.npz holds `jpeg` (JPEG pixel coordinates, continuous, pixel centres at +0.5),
`raw` (the same points in LibRaw's full image, continuous coordinates at full resolution),
and the sizes. Pairs are the inliers of a generous radial fit, so a model can be judged on them.
"""

import json
import os
import sys
import traceback
from concurrent.futures import ThreadPoolExecutor

import cv2
import numpy as np
import rawpy

import measure

ROOT = "/Volumes/SSD/redlamp-tmp/pv16-raw-pixls"
OUT = "pairs"


def sift_pairs(jpeg, render, long_edge=3000):
    """Point pairs in each image's own pixel coordinates (continuous)."""
    fa = long_edge / max(jpeg.shape)
    fb = long_edge / max(render.shape)
    a = measure.resized(jpeg, long_edge)
    b = measure.resized(render, long_edge)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    sift = cv2.SIFT_create(nfeatures=40000, contrastThreshold=0.01)
    ka, da = sift.detectAndCompute(clahe.apply(a), None)
    kb, db = sift.detectAndCompute(clahe.apply(b), None)
    if da is None or db is None or len(ka) < 50 or len(kb) < 50:
        return None
    matcher = cv2.FlannBasedMatcher({"algorithm": 1, "trees": 5}, {"checks": 64})
    good = [m for m, n in (p for p in matcher.knnMatch(da, db, k=2) if len(p) == 2) if m.distance < 0.8 * n.distance]
    pa = (np.array([ka[m.queryIdx].pt for m in good]) + 0.5) / fa
    pb = (np.array([kb[m.trainIdx].pt for m in good]) + 0.5) / fb
    return pa, pb


def inliers(pa, ja_shape, pb, rb_shape):
    qa, _ = measure.normalised(pa, ja_shape)
    qb, half_b = measure.normalised(pb, rb_shape)
    fit = measure.fit_radial(qa, qb, half_b, terms=4, threshold=3)
    if fit is None:
        return None
    coef, keep, rms, res = fit
    return keep, rms


def one(path):
    name = os.path.basename(path)
    target = os.path.join(OUT, name + ".npz")
    if os.path.exists(target) and "--redo" not in sys.argv:
        return name, "cached"
    try:
        with rawpy.imread(path) as raw:
            rgb = raw.postprocess(use_camera_wb=True, output_bps=8, half_size=True, user_flip=0)
            sizes = raw.sizes
        render = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        got = measure.largest_jpeg(path)
        if got is None:
            return name, "no jpeg"
        jpeg = got[0]
        best = None
        rotations = [0] if (jpeg.shape[0] > jpeg.shape[1]) == (render.shape[0] > render.shape[1]) else [1, 3]
        if jpeg.shape[0] == jpeg.shape[1]:
            rotations = [0, 1, 3]
        for rot in rotations:
            j = np.ascontiguousarray(np.rot90(jpeg, rot)) if rot else jpeg
            got = sift_pairs(j, render)
            if got is None:
                continue
            pa, pb = got
            if len(pa) < 100:
                continue
            fit = inliers(pa, j.shape, pb, render.shape)
            if fit is None:
                continue
            keep, rms = fit
            if best is None or keep.sum() > best[0].sum():
                best = (keep, rms, rot, pa, pb, j.shape)
        if best is None:
            return name, "no fit"
        keep, rms, rot, pa, pb, jshape = best
        np.savez_compressed(
            target, jpeg=pa[keep], raw=pb[keep] * 2.0, jpeg_size=np.array([jshape[1], jshape[0]]),
            raw_size=np.array([sizes.width, sizes.height]), rotation=rot, rms=rms,
            crop=np.array([sizes.crop_left_margin, sizes.crop_top_margin, sizes.crop_width, sizes.crop_height]),
        )
        return name, "%d pairs, rms %.2f (half-size px), rot %d" % (keep.sum(), rms, rot)
    except Exception:
        return name, traceback.format_exc()[-300:]


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    pattern = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else ""
    names = sorted(n for n in os.listdir(ROOT) if n.lower().endswith((".rw2", ".rwl", ".orf", ".ori")) and pattern in n)
    with ThreadPoolExecutor(4) as pool:
        for name, result in pool.map(one, [os.path.join(ROOT, n) for n in names]):
            print(name, result, flush=True)
