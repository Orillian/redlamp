"""The radial residual of a Panasonic model on one file: measured corrected radius vs the model's."""

import sys

import numpy as np

import evaluate
import pana
import pana_search

S = 32768.0
name = sys.argv[1]
pairs = evaluate.load(name)
d, c0, active, k0 = pana.geometry(name, pairs)
print(name, "words", d[2:14])
F = pana_search.model(d, [8, 4, 11], "divide")
fit = evaluate.score(pairs, F, d[12], c0, k0)
print("model rms %.2f k %.5f shift %s" % (fit["rms"], fit["k_ratio"], np.round(fit["shift"], 2)))
k = fit["k"]
c = c0 + np.array(fit["shift"])
u, p = pairs["jpeg"], pairs["raw"]
jc = pairs["jpeg_size"] / 2.0
q = (u - jc) * k
rc = np.linalg.norm(q, axis=1) / d[12]
rs = np.linalg.norm(p - c, axis=1) / d[12]
s5 = 1 + d[5] / S
model_rc = rs * (1 + (d[8] * rs ** 2 + d[4] * rs ** 4 + d[11] * rs ** 6) / S) / s5
bins = np.linspace(0, rs.max(), 13)
print(" r_s      measured r_c/r_s   model r_c/r_s   diff (px at R)")
for lo, hi in zip(bins, bins[1:]):
    sel = (rs >= lo) & (rs < hi) & (rs > 0.02)
    if sel.sum() < 10:
        continue
    m = np.median(rc[sel] / rs[sel])
    mm = np.median(model_rc[sel] / rs[sel])
    print("%.3f   %.5f   %.5f   %+.2f" % (rs[sel].mean(), m, mm, (m - mm) * rs[sel].mean() * d[12]))
