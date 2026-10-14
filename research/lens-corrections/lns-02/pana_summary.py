"""Panasonic: the conventions' scores over every file whose JPEG shows the whole active area."""

import json

import numpy as np

import evaluate
import pana
import pana_inv
import pana_search

S = 32768.0


def G_words(slots, scale):
    def G_of(d):
        s5 = 1 + d[5] / S
        coef = [d[w] / S if w is not None else 0.0 for w in slots]

        def G(r, _):
            if scale == "inside":
                x = r / s5
                return x * (1 + sum(c * x ** (2 * (i + 1)) for i, c in enumerate(coef)))
            poly = 1 + sum(c * r ** (2 * (i + 1)) for i, c in enumerate(coef))
            return r * poly / (s5 if scale == "divide" else 1.0)
        return G
    return G_of


variants = {
    "w8,w4,w11 /s5 R=w12": (G_words([8, 4, 11], "divide"), "w12"),
    "w8,w4,w11 /s5 R=active": (G_words([8, 4, 11], "divide"), "active"),
    "w8,w4,w11 no scale": (G_words([8, 4, 11], "none"), "w12"),
    "w8,w4,w11 scale inside": (G_words([8, 4, 11], "inside"), "w12"),
    "w8,w4 /s5": (G_words([8, 4, None], "divide"), "w12"),
    "w8,w11,w4 /s5": (G_words([8, 11, 4], "divide"), "w12"),
    "w4,w8,w11 /s5": (G_words([4, 8, 11], "divide"), "w12"),
}

rows = []
for name, pairs, d, c0, k0, same in pana_search.files(min_strength=0, same_only=True):
    pairs = pana_search.subsample(pairs, 3000)
    _, c0, active, k0 = pana.geometry(name, pairs)
    free_x, free_rms, _ = pana_inv.solve(pairs, d, c0, k0, pana_inv.poly_G(1 + d[5] / S), 6, [d[8] / S, d[4] / S, d[11] / S, 0, 0, 0])
    if free_rms > 5:
        print("skip", name, "free rms", free_rms)
        continue
    row = {"name": name, "free": free_rms}
    line = "%-24s free %.2f" % (name[:24], free_rms)
    for label, (G_of, norm) in variants.items():
        R = d[12] if norm == "w12" else float(np.hypot(*active) / 2)
        dd = list(d)
        dd[12] = R
        x, rms, _ = pana_inv.solve(pairs, dd, c0, k0, G_of(d), 3, None, fix_coef=True)
        row[label] = (rms, x[0] / k0)
        line += " | %.2f/%.4f" % (rms, x[0] / k0)
    rows.append(row)
    print(line, flush=True)

print("\n%d files" % len(rows))
free = np.array([r["free"] for r in rows])
print("free 6-term: median %.3f" % np.median(free))
for label in variants:
    rms = np.array([r[label][0] for r in rows])
    k = np.array([r[label][1] for r in rows])
    print("%-26s median %.3f mean %.3f  /free median %.3f p90 %.3f  |k-1| median %.5f p90 %.5f" % (
        label, np.median(rms), rms.mean(), np.median(rms / free), np.percentile(rms / free, 90),
        np.median(abs(k - 1)), np.percentile(abs(k - 1), 90)))
json.dump(rows, open("pana_summary.json", "w"), indent=1)
