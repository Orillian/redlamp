"""Lateral CA across the samples: the raw's red and blue scale against green, and the JPEG's.

Radii in the distortion's units: Olympus the crop's half-diagonal about its centre, Panasonic
word 12 about the active area's centre. Coefficients of 1 + a + b r² + e r⁴ − 1 (scale − 1).
"""

import json
import os
import sys
import traceback
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import rawpy

import ca
import measure

ROOT = "/Volumes/SSD/redlamp-tmp/pv16-raw-pixls"
survey_data = json.load(open("survey.json"))


def geometry(name, w, h):
    info = survey_data[name]
    if "d" in info:
        top, left = info.get("top", 0), info.get("left", 0)
        bottom, right = info.get("bottom", h), info.get("right", w)
        return np.array([(left + right) / 2, (top + bottom) / 2]), info["d"][12]
    left = (info.get("0612") or [0])[0]
    top = (info.get("0613") or [0])[0]
    cw = (info.get("0614") or [w])[0]
    ch = (info.get("0615") or [h])[0]
    return np.array([left + cw / 2, top + ch / 2]), np.hypot(cw, ch) / 2


def one(name):
    path = os.path.join(ROOT, name) if not name.startswith("/") else name
    base = os.path.basename(path)
    try:
        with rawpy.imread(path) as raw:
            rgb = raw.postprocess(use_camera_wb=True, output_bps=16, user_flip=0, half_size=True,
                                  output_color=rawpy.ColorSpace.raw)
        img = ca.to8(rgb)
        h, w = img.shape[:2]
        centre, R = geometry(base, 2 * w, 2 * h)
        out = {}
        g = img[..., 1]
        for i, label in ((0, "red"), (2, "blue")):
            got = ca.channel_pairs(g, img[..., i], long_edge=max(img.shape))
            if got is None:
                continue
            pg, pc = got
            coef, rms, n = ca.radial_scale(pg * 2, pc * 2, centre, R)
            out["raw_" + label] = [list(map(float, coef)), rms, n]
        jpeg = measure.largest_jpeg(path, color=True)[0]
        jr = ca.measure_image(jpeg)
        for label in ("red", "blue"):
            if label in jr:
                out["jpeg_" + label] = [list(map(float, jr[label][0])), jr[label][1], jr[label][2]]
        return base, out
    except Exception:
        return base, {"error": traceback.format_exc()[-300:]}


if __name__ == "__main__":
    names = sys.argv[1:]
    results = json.load(open("ca_survey.json")) if os.path.exists("ca_survey.json") else {}
    with ThreadPoolExecutor(3) as pool:
        for name, out in pool.map(one, [n for n in names if os.path.basename(n) not in results]):
            results[name] = out
            json.dump(results, open("ca_survey.json", "w"), indent=1)
            line = name
            for key in ("raw_red", "raw_blue", "jpeg_red", "jpeg_blue"):
                if key in out:
                    c = out[key][0]
                    line += "  %s %s" % (key, np.round(np.array(c) * 1e4, 2).tolist())
            print(line, flush=True)
