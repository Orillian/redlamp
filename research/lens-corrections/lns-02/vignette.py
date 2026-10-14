"""Olympus vignetting: the radial gain a camera's JPEG applied, against the 0x0801 table.

At the saved JPEG/raw pairs: the raw's linear green (LibRaw, camera space, no brightening)
and the JPEG's linear luminance, both blurred a little. A monotonic tone curve from raw to JPEG
is fitted at the centre (r < 0.35); the gain at each point is T⁻¹(JPEG)/raw, in radius bins.
"""

import json
import sys

import cv2
import numpy as np
import rawpy

import evaluate
import oly_eval

ROOT = "/Volumes/SSD/redlamp-tmp/pv16-raw-pixls"
survey_data = json.load(open("survey.json"))


def sample(img, pts):
    return cv2.remap(img, pts[:, 0:1].astype(np.float32) - 0.5, pts[:, 1:2].astype(np.float32) - 0.5,
                     cv2.INTER_LINEAR)[:, 0]


def measure(name):
    pairs = evaluate.load(name)
    with rawpy.imread(ROOT + "/" + name) as raw:
        lin = raw.postprocess(use_camera_wb=True, output_bps=16, user_flip=0, gamma=(1, 1), no_auto_bright=True,
                              output_color=rawpy.ColorSpace.raw, half_size=True).astype(np.float32) / 65535
    import measure as m
    jpeg = m.largest_jpeg(ROOT + "/" + name, color=True)[0].astype(np.float32) / 255
    jl = np.where(jpeg <= 0.04045, jpeg / 12.92, ((jpeg + 0.055) / 1.055) ** 2.4)
    jy = 0.2126 * jl[..., 0] + 0.7152 * jl[..., 1] + 0.0722 * jl[..., 2]
    rg = lin[..., 1]
    jy = cv2.GaussianBlur(jy, (0, 0), 2.0)
    rg = cv2.GaussianBlur(rg, (0, 0), 1.5)
    pj = pairs["jpeg"]
    pr = pairs["raw"] / 2.0  # half-size render
    a = sample(rg, pr)
    b = sample(jy, pj)
    c, R, crop = oly_eval.crop_geometry(name, pairs)
    r = np.linalg.norm(pairs["raw"] - c, axis=1) / R
    ok = (a > 0.01) & (a < 0.6) & (b > 0.02) & (b < 0.85)
    a, b, r = a[ok], b[ok], r[ok]
    # Tone curve at the centre: log b as a smooth function of log a.
    centre = r < 0.35
    la, lb = np.log(a), np.log(b)
    coef = np.polyfit(la[centre], lb[centre], 3)
    grid = np.linspace(la.min(), la.max(), 400)
    curve = np.polyval(coef, grid)
    if not (np.diff(curve) > 0).all():
        return None
    # The raw value the centre's curve would need to give each JPEG value; its ratio is the gain.
    needed = np.interp(lb, curve, grid)
    gain = np.exp(needed - la)
    bins = np.linspace(0, r.max(), 14)
    out = []
    for lo, hi in zip(bins, bins[1:]):
        sel = (r >= lo) & (r < hi)
        if sel.sum() > 30:
            out.append((float(r[sel].mean()), float(np.median(gain[sel])), int(sel.sum())))
    return out


def table_gain(v, r, convention):
    g = np.array(v, float) / 8192
    n = len(g)
    knots = {"i/15": np.arange(n) / (n - 1), "i/16": np.arange(n) / n, "(i+.5)/16": (np.arange(n) + 0.5) / n,
             "(i+1)/16": (np.arange(n) + 1) / n}[convention]
    return np.interp(r, knots, g)


if __name__ == "__main__":
    for name in sys.argv[1:]:
        info = survey_data[name]
        v = info.get("0801")
        prof = measure(name)
        print(name, "shading comp", info.get("1012"), "table", (np.array(v) / 8192).round(3).tolist() if v else None)
        if not prof:
            print("  no profile")
            continue
        for r, g, n in prof:
            line = "  r %.3f measured gain %.3f (n %d)" % (r, g, n)
            if v and any(v):
                line += "   table: " + "  ".join("%s %.3f" % (k, table_gain(v, r, k)) for k in ("i/15", "i/16", "(i+.5)/16", "(i+1)/16"))
            print(line)
