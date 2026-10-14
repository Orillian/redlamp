"""Panasonic: fits the corrected radius as a polynomial of the recorded one, per file, beside the words."""

import json
import math
import os
import sys

import numpy as np
from scipy.optimize import least_squares

import evaluate

survey_data = json.load(open("survey.json"))


def geometry(name, pairs):
    info = survey_data[name]
    d = info["d"]
    top, left, bottom, right = info.get("top", 0), info.get("left", 0), info.get("bottom"), info.get("right")
    w, h = pairs["raw_size"]
    if bottom is None or right is None:
        top, left, bottom, right = 0, 0, h, w
    centre = np.array([(left + right) / 2, (top + bottom) / 2], float)
    active = np.array([right - left, bottom - top], float)
    js = pairs["jpeg_size"].astype(float)
    k0 = min(active[0] / js[0], active[1] / js[1])
    return d, centre, active, k0


def fit_inverse(pairs, R, c0, k0, terms=5, fix_k=True):
    """r_c = r_s·Σ b_i r_s^(2i): fitted with the JPEG's framing fixed at k0 (the active area)."""
    u, p = pairs["jpeg"], pairs["raw"]
    jc = pairs["jpeg_size"] / 2.0
    q = (u - jc) * k0

    def residual(x):
        b = x[:terms]
        t = x[terms:terms + 2]
        k = x[terms + 2] if not fix_k else 1.0
        d = p - (c0 + t)  # recorded offset from the centre
        rs = np.linalg.norm(d, axis=1) / R
        g = sum(b[i] * rs ** (2 * i) for i in range(terms))
        pred = d * g[:, None]  # corrected position
        return (pred - q * k).ravel()

    x0 = [1.0] + [0.0] * (terms - 1) + [0.0, 0.0] + ([] if fix_k else [1.0])
    sol = least_squares(residual, x0, loss="soft_l1", f_scale=2.0)
    res = np.linalg.norm(residual(sol.x).reshape(-1, 2), axis=1)
    return sol.x, float(np.sqrt(np.mean(res[res < max(4, 4 * np.median(res))] ** 2)))


if __name__ == "__main__":
    rows = []
    for fn in sorted(os.listdir("pairs")):
        name = fn[:-4]
        if not name.lower().endswith((".rw2", ".rwl")):
            continue
        info = survey_data.get(name, {})
        d = info.get("d")
        if not d or (d[7] & 0xF) != 1:
            continue
        pairs = evaluate.load(name)
        d, c0, active, k0 = geometry(name, pairs)
        js = pairs["jpeg_size"]
        same = abs(js[0] / js[1] - active[0] / active[1]) < 0.01
        if not same and "--all" not in sys.argv:
            continue
        x, rms = fit_inverse(pairs, d[12], c0, k0)
        b = x[:5]
        rows.append((name, b, rms, d))
        print("%-24s rms %.2f b0 %.5f b1 %+.5f b2 %+.5f b3 %+.5f b4 %+.5f | w2 %4d w3 %4d w4 %6d w5 %5d w6 %4d w8 %5d w9 %4d w11 %6d  s5 %.5f" % (
            name[:24], rms, b[0], b[1], b[2], b[3], b[4], d[2], d[3], d[4], d[5], d[6], d[8], d[9], d[11], 1 + d[5] / 32768))
    json.dump([(n, list(b), r, d) for n, b, r, d in rows], open("pana_fit.json", "w"))
