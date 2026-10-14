"""Panasonic, fitted in the direction the words describe: recorded radius → corrected radius.

For a pair (u in the JPEG, p in the raw): d = p − c, r = |d|/R, the corrected point is
d·G(r)/r, compared with (u − jpeg centre)·k + t. Residuals are in sensor pixels.
"""

import sys

import numpy as np
from scipy.optimize import least_squares

import evaluate
import pana
import pana_search

S = 32768.0


def solve(pairs, d, c0, k0, G_of, n_coef, x_coef0, fix_coef=False):
    u, p = pairs["jpeg"], pairs["raw"]
    jc = pairs["jpeg_size"] / 2.0
    R = d[12]

    def residual(x):
        k, tx, ty, cx, cy = x[:5]
        coef = x_coef0 if fix_coef else x[5:]
        dd = p - (c0 + np.array([cx, cy]))
        r = np.linalg.norm(dd, axis=1) / R
        g = G_of(r, coef) / np.maximum(r, 1e-9)
        pred = dd * g[:, None]
        return (pred - ((u - jc) * k + np.array([tx, ty]))).ravel()

    x0 = [k0, 0, 0, 0, 0] + ([] if fix_coef else list(x_coef0))
    sol = least_squares(residual, x0, loss="soft_l1", f_scale=2.0, x_scale="jac")
    res = np.linalg.norm(residual(sol.x).reshape(-1, 2), axis=1)
    keep = res < max(4, 4 * np.median(res))
    return sol.x, float(np.sqrt(np.mean(res[keep] ** 2))), res


def poly_G(s5):
    def G(r, coef):
        return r * (1 + sum(c * r ** (2 * (i + 1)) for i, c in enumerate(coef))) / s5
    return G


if __name__ == "__main__":
    for name in sys.argv[1:]:
        pairs = pana_search.subsample(evaluate.load(name), 4000)
        d, c0, active, k0 = pana.geometry(name, pairs)
        s5 = 1 + d[5] / S
        words = [d[8] / S, d[4] / S, d[11] / S]
        print(name, "words (w8, w4, w11)/S", np.round(words, 5).tolist(), " w2 %d w3 %d w6 %d w9 %d w10 %d" % (d[2], d[3], d[6], d[9], d[10]))
        x, rms, _ = solve(pairs, d, c0, k0, poly_G(s5), 3, words, fix_coef=True)
        print("  words      rms %.2f k/k0 %.5f" % (rms, x[0] / k0))
        for terms in (3, 4, 5, 6):
            x, rms, _ = solve(pairs, d, c0, k0, poly_G(s5), terms, (words + [0, 0, 0])[:terms])
            print("  free %d     rms %.2f k/k0 %.5f coef %s" % (terms, rms, x[0] / k0, np.round(x[5:], 5).tolist()))
