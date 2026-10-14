"""Scores candidate lens-correction conventions against the saved JPEG/raw point pairs.

A model is F: corrected radius → recorded radius, both in units of a normalisation radius R
(pixels of LibRaw's full image) about an optical centre c. For a pair (u in the JPEG, p in
the raw), q = (u − jpeg centre)·k + t is the corrected position, and the model predicts
p = c + q·F(|q|/R)/(|q|/R). k (the JPEG's framing), t and a centre shift are fitted; the
residual RMS (in raw pixels) says how well the convention describes the camera's correction.
"""

import json
import math
import os

import numpy as np
from scipy.optimize import least_squares

import survey

ROOT = "/Volumes/SSD/redlamp-tmp/pv16-raw-pixls"


def load(name):
    z = np.load(os.path.join("pairs", name + ".npz"))
    out = {k: z[k] for k in z.files}
    # LibRaw halves its reported sizes for half-size renders; the pairs are at full resolution.
    out["raw_size"] = out["raw_size"] * 2
    return out


def predict(params, u, jc, F, R, c0, fix_centre):
    k, tx, ty = params[:3]
    cx, cy = (c0 if fix_centre else c0 + params[3:5])
    q = (u - jc) * k + np.array([tx, ty])
    rc = np.linalg.norm(q, axis=1) / R
    rs = F(rc)
    ratio = np.where(rc > 1e-9, rs / np.maximum(rc, 1e-9), F(np.array([1e-6]))[0] / 1e-6)
    return np.array([cx, cy]) + q * ratio[:, None]


def score(pairs, F, R, c0, k0, fix_centre=False, robust=True):
    u, p = pairs["jpeg"], pairs["raw"]
    jc = pairs["jpeg_size"] / 2.0
    x0 = [k0, 0.0, 0.0] + ([] if fix_centre else [0.0, 0.0])

    def residual(x):
        return (predict(x, u, jc, F, R, c0, fix_centre) - p).ravel()

    sol = least_squares(residual, x0, loss="soft_l1" if robust else "linear", f_scale=2.0)
    res = np.linalg.norm(residual(sol.x).reshape(-1, 2), axis=1)
    keep = res < max(4.0, 4 * np.median(res))
    return {"rms": float(np.sqrt(np.mean(res[keep] ** 2))), "median": float(np.median(res)),
            "k": float(sol.x[0]), "k_ratio": float(sol.x[0] / k0), "shift": sol.x[3:5].tolist() if not fix_centre else [0, 0],
            "n": int(keep.sum())}


def free_model(terms=6):
    """The best a radial polynomial can do: fitted per file (the noise floor)."""
    def make(coef):
        return lambda r: r * sum(c * r ** (2 * i) for i, c in enumerate(coef))
    return make


def score_free(pairs, R, c0, k0, terms=6):
    u, p = pairs["jpeg"], pairs["raw"]
    jc = pairs["jpeg_size"] / 2.0

    def residual(x):
        coef = [1.0] + list(x[5:])
        F = lambda r: r * sum(c * r ** (2 * i) for i, c in enumerate(coef))
        return (predict(x[:5], u, jc, F, R, c0, False) - p).ravel()

    x0 = [k0, 0, 0, 0, 0] + [0.0] * (terms - 1)
    sol = least_squares(residual, x0, loss="soft_l1", f_scale=2.0)
    res = np.linalg.norm(residual(sol.x).reshape(-1, 2), axis=1)
    keep = res < max(4.0, 4 * np.median(res))
    return {"rms": float(np.sqrt(np.mean(res[keep] ** 2))), "k": float(sol.x[0]), "coef": sol.x[5:].tolist(),
            "shift": sol.x[3:5].tolist()}


def invert(G, rmax=1.6, n=4000):
    """F = G⁻¹ by tabulation: G maps recorded radius to corrected radius."""
    rs = np.linspace(0, rmax, n)
    rc = G(rs)
    order = np.argsort(rc)
    return lambda r: np.interp(r, rc[order], rs[order])
