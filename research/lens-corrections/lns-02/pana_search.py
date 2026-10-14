"""Panasonic: which words are which terms. Scores word-to-power assignments by residual RMS."""

import itertools
import json
import os
import sys

import numpy as np

import evaluate
import pana

S = 32768.0


def model(d, slots, scale_mode):
    """G: recorded radius → corrected radius (units of word 12); F = G⁻¹."""
    coef = [d[w] / S if isinstance(w, int) else 0.0 for w in slots]
    s5 = 1 + d[5] / S

    def G(r):
        r2 = r * r
        poly = 1 + sum(c * r2 ** (i + 1) for i, c in enumerate(coef))
        if scale_mode == "divide":
            return r * poly / s5
        if scale_mode == "inside":  # polynomial of the scaled radius
            x = r / s5
            return x * (1 + sum(c * (x * x) ** (i + 1) for i, c in enumerate(coef)))
        return r * poly

    return evaluate.invert(G)


def subsample(pairs, n=2500, seed=1):
    m = len(pairs["jpeg"])
    if m <= n:
        return pairs
    idx = np.random.default_rng(seed).choice(m, n, replace=False)
    out = dict(pairs)
    out["jpeg"], out["raw"] = pairs["jpeg"][idx], pairs["raw"][idx]
    return out


def files(min_strength=0.0, same_only=True):
    out = []
    for fn in sorted(os.listdir("pairs")):
        name = fn[:-4]
        if not name.lower().endswith((".rw2", ".rwl")):
            continue
        d = pana.survey_data.get(name, {}).get("d")
        if not d or (d[7] & 0xF) != 1:
            continue
        pairs = evaluate.load(name)
        d, c0, active, k0 = pana.geometry(name, pairs)
        js = pairs["jpeg_size"]
        same = abs(js[0] / js[1] - active[0] / active[1]) < 0.01
        if same_only and not same:
            continue
        strength = abs(d[8]) + abs(d[4]) + abs(d[11])
        if strength < min_strength:
            continue
        out.append((name, subsample(pairs), d, c0, k0, same))
    return out


if __name__ == "__main__":
    chosen = files(min_strength=float(sys.argv[1]) if len(sys.argv) > 1 else 3000)
    print(len(chosen), "files:", [n for n, *_ in chosen])
    words = [2, 3, 4, 6, 9, 11, None]
    results = []
    for a2, a3 in itertools.product(words, words):
        if a2 is not None and a2 == a3:
            continue
        for scale_mode in ["divide"]:
            slots = [8, a2, a3]
            total, ks = [], []
            for name, pairs, d, c0, k0, same in chosen:
                r = evaluate.score(pairs, model(d, slots, scale_mode), d[12], c0, k0)
                total.append(r["rms"])
                ks.append(r["k_ratio"])
            results.append((float(np.median(total)), float(np.mean(total)), slots, scale_mode, total, ks))
            print("slots r2..r6 = %s %-7s median %.3f mean %.3f" % (slots, scale_mode, results[-1][0], results[-1][1]), flush=True)
    results.sort(key=lambda x: x[0])
    print("\nbest:")
    for med, mean, slots, mode, total, ks in results[:8]:
        print(slots, mode, "median %.3f mean %.3f" % (med, mean), "k ratios", np.round(ks, 4).tolist())
    json.dump([(m, n, s, mo, t, k) for m, n, s, mo, t, k in results], open("pana_search.json", "w"))
