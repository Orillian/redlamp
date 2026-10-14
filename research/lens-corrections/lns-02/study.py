"""Measures each Panasonic and Olympus sample's JPEG-to-raw radial mapping beside its tags.

For every file: an uncorrected LibRaw render in sensor orientation, its camera crop (LibRaw's
inset crop), and the largest embedded JPEG. The mapping is fitted as
    p_raw = c + q · g(|q|) (+ a small rotation),  q = (p_jpeg − centre_jpeg) / halfdiag_jpeg,
with p_raw in units of the crop's half-diagonal about the crop's centre, g a polynomial in ρ².
"""

import json
import multiprocessing
import os
import sys
import traceback

import cv2
import numpy as np
import rawpy

import measure
import survey

ROOT = "/Volumes/SSD/redlamp-tmp/pv16-raw-pixls"
TERMS = 4


def crop_of(raw_sizes, shape, half):
    s = raw_sizes
    if s.crop_width and s.crop_height:
        left, top, w, h = s.crop_left_margin, s.crop_top_margin, s.crop_width, s.crop_height
    else:
        left, top, w, h = 0, 0, s.width, s.height
    k = 0.5 if half else 1.0
    return left * k, top * k, w * k, h * k


def study(path):
    name = os.path.basename(path)
    try:
        with rawpy.imread(path) as raw:
            rgb = raw.postprocess(use_camera_wb=True, output_bps=8, half_size=True, user_flip=0)
            sizes = raw.sizes
        render = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
        got = measure.largest_jpeg(path)
        if got is None:
            return name, {"error": "no jpeg"}
        jpeg = got[0]
        left, top, cw, ch = crop_of(sizes, render.shape, True)
        best = None
        rotations = [0]
        if (jpeg.shape[0] > jpeg.shape[1]) != (ch > cw):
            rotations = [1, 3]
        for rot in rotations:
            j = np.ascontiguousarray(np.rot90(jpeg, rot)) if rot else jpeg
            # Matches on the crop only, so the render's coordinates are about the crop's centre.
            crop = render[int(round(top)):int(round(top + ch)), int(round(left)):int(round(left + cw))]
            m = measure.matches(j, crop, long_edge=3000)
            if m is None:
                continue
            qa, qb, half_a, half_b, sa, sb = m
            if len(qa) < 200:
                continue
            fit = measure.fit_radial(qa, qb, half_b, terms=TERMS)
            if fit is None:
                continue
            coef, keep, rms, res = fit
            if best is None or keep.sum() > best[2].sum():
                best = (rot, coef, keep, rms, qa, qb, half_b)
        if best is None:
            return name, {"error": "no fit"}
        rot, coef, keep, rms, qa, qb, half_b = best
        # Crop offset of the cropped render: the crop's integer bounds vs its exact centre.
        exact = np.array([left + cw / 2, top + ch / 2])
        rounded = np.array([round(left) + round(left + cw) - round(left), round(top) + round(top + ch) - round(top)]) / 2
        prof = measure.profile(qa, qb, coef, TERMS, keep)
        return name, {
            "rotation": rot, "jpeg": list(jpeg.shape), "render": list(render.shape),
            "crop": [left * 2, top * 2, cw * 2, ch * 2], "full": [sizes.width, sizes.height],
            "inliers": int(keep.sum()), "rms": float(rms), "coef": [float(c) for c in coef],
            "rho_max": float(np.linalg.norm(qa[keep], axis=1).max()), "profile": prof,
        }
    except Exception as error:
        return name, {"error": traceback.format_exc()[-400:]}


if __name__ == "__main__":
    pattern = sys.argv[1] if len(sys.argv) > 1 else ""
    names = sorted(n for n in os.listdir(ROOT) if n.lower().endswith((".rw2", ".rwl", ".orf", ".ori")) and pattern in n)
    paths = [os.path.join(ROOT, n) for n in names]
    out = {}
    if os.path.exists("study.json"):
        out = json.load(open("study.json"))
    todo = [p for p in paths if os.path.basename(p) not in out or "--redo" in sys.argv]
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(4) as pool:
        for name, result in pool.map(study, todo):
            out[name] = result
            print(name, result.get("error") or "inliers %d rms %.2f g %s" % (
                result["inliers"], result["rms"], np.round(result["coef"][:TERMS], 5).tolist()), flush=True)
            json.dump(out, open("study.json", "w"), indent=1)
