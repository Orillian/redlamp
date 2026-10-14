"""Panasonic: a free 3- and 4-term inverse polynomial per file, beside (w8, w4, w11)/32768."""

import sys

import numpy as np
from scipy.optimize import least_squares

import evaluate
import pana
import pana_search

S = 32768.0


def fit(pairs, d, c0, k0, terms):
    u, p = pairs["jpeg"], pairs["raw"]
    jc = pairs["jpeg_size"] / 2.0
    R = d[12]
    s5 = 1 + d[5] / S

    def residual(x):
        k, tx, ty, cx, cy = x[:5]
        coef = x[5:]
        G = lambda r: r * (1 + sum(c * r ** (2 * (i + 1)) for i, c in enumerate(coef))) / s5
        F = evaluate.invert(G)
        pred = evaluate.predict([k, tx, ty, cx, cy], u, jc, F, R, c0, False)
        return (pred - p).ravel()

    x0 = [k0, 0, 0, 0, 0] + [d[8] / S, d[4] / S, d[11] / S, 0, 0][:terms]
    sol = least_squares(residual, x0, loss="soft_l1", f_scale=2.0, diff_step=1e-6)
    res = np.linalg.norm(residual(sol.x).reshape(-1, 2), axis=1)
    keep = res < max(4, 4 * np.median(res))
    return sol.x, float(np.sqrt(np.mean(res[keep] ** 2)))


names = sys.argv[1:]
for name in names:
    pairs = pana_search.subsample(evaluate.load(name), 3000)
    d, c0, active, k0 = pana.geometry(name, pairs)
    print(name, "w8 w4 w11 /S:", round(d[8] / S, 5), round(d[4] / S, 5), round(d[11] / S, 5), " w2 w3 w6 w9 w10:", d[2], d[3], d[6], d[9], d[10])
    for terms in (3, 4, 5):
        x, rms = fit(pairs, d, c0, k0, terms)
        print("  %d terms rms %.2f k/k0 %.5f coef %s" % (terms, rms, x[0] / k0, np.round(x[5:], 5).tolist()))
