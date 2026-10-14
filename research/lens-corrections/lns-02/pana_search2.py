"""Panasonic: (w8, w4, w11) as r², r⁴, r⁶; further terms, the scale's place, and the noise floor."""

import json
import sys

import numpy as np

import evaluate
import pana_search

chosen = pana_search.files(min_strength=float(sys.argv[1]) if len(sys.argv) > 1 else 0, same_only=True)
print(len(chosen), "files")
variants = [
    ([8, 4, 11], "divide"),
    ([8, 4, 11], "inside"),
    ([8, 4, 11], "none"),
    ([8, 4, 11, 2], "divide"),
    ([8, 4, 11, 9], "divide"),
    ([8, 4, 11, 3], "divide"),
    ([8, 4, 11, 6], "divide"),
]
table = {}
for slots, mode in variants:
    table[(tuple(slots), mode)] = []
free = []
for name, pairs, d, c0, k0, same in chosen:
    f = evaluate.score_free(pairs, d[12], c0, k0, terms=6)
    free.append(f["rms"])
    row = []
    for slots, mode in variants:
        r = evaluate.score(pairs, pana_search.model(d, slots, mode), d[12], c0, k0)
        table[(tuple(slots), mode)].append((r["rms"], r["k_ratio"]))
        row.append("%.2f/%.4f" % (r["rms"], r["k_ratio"]))
    print("%-24s free %.2f | %s" % (name[:24], f["rms"], " ".join(row)), flush=True)
print("\nfree: median %.3f mean %.3f" % (np.median(free), np.mean(free)))
for (slots, mode), values in table.items():
    rms = np.array([v[0] for v in values])
    k = np.array([v[1] for v in values])
    print("%-16s %-7s median %.3f mean %.3f  rms/free median %.3f  |k-1| median %.5f max %.5f" % (
        list(slots), mode, np.median(rms), rms.mean(), np.median(rms / np.array(free)), np.median(abs(k - 1)), abs(k - 1).max()))
