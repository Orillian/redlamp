"""Olympus / OM System: scores 0x150a conventions on every ORF/ORI with pairs.

Centre and normalisation: the camera's crop (ImageProcessing 0x0612–0x0615) or LibRaw's frame.
Scale (0x150a[3]): inside the polynomial (x = s·r), outside (s·r·P(r)), or ignored.
"""

import json
import os
import sys

import numpy as np

import evaluate

survey_data = json.load(open("survey.json"))


def crop_geometry(name, pairs):
    info = survey_data[name]
    w, h = pairs["raw_size"]
    left = (info.get("0612") or [0])[0]
    top = (info.get("0613") or [0])[0]
    cw = (info.get("0614") or [w])[0]
    ch = (info.get("0615") or [h])[0]
    return np.array([left + cw / 2, top + ch / 2], float), np.hypot(cw, ch) / 2, np.array([cw, ch], float)


def model(k, mode):
    k1, k2, k3, s = k

    def P(x):
        x2 = x * x
        return 1 + k1 * x2 + k2 * x2 * x2 + k3 * x2 * x2 * x2

    if mode == "inside":
        return lambda r: (s * r) * P(s * r)
    if mode == "outside":
        return lambda r: s * r * P(r)
    return lambda r: r * P(r)


if __name__ == "__main__":
    rows = []
    for fn in sorted(os.listdir("pairs")):
        name = fn[:-4]
        info = survey_data.get(name)
        if not info or "kind" not in info:
            continue
        k = info.get("150A")
        if not k or len(k) != 4:
            continue
        same = info.get("1510") == k
        pairs = evaluate.load(name)
        c_crop, R_crop, crop = crop_geometry(name, pairs)
        w, h = pairs["raw_size"]
        c_full, R_full = np.array([w / 2, h / 2], float), np.hypot(w, h) / 2
        js = pairs["jpeg_size"].astype(float)
        k0 = min(crop[0] / js[0], crop[1] / js[1])
        out = {"name": name, "k": k, "1510same": same}
        line = "%-28s k %-36s 1510=%s" % (name[:28], np.round(k, 4).tolist(), "same" if same else info.get("1510"))
        for geo, c0, R in (("crop", c_crop, R_crop), ("full", c_full, R_full)):
            for mode in ("inside", "outside", "none"):
                r = evaluate.score(pairs, model(k, mode), R, c0, k0)
                out[geo + "/" + mode] = (r["rms"], r["k_ratio"])
                line += "  %s/%s %.2f/%.4f" % (geo[0], mode[:2], r["rms"], r["k_ratio"])
        f = evaluate.score_free(pairs, R_crop, c_crop, k0)
        out["free"] = f["rms"]
        line += "  free %.2f" % f["rms"]
        rows.append(out)
        print(line, flush=True)
    json.dump(rows, open("oly_eval.json", "w"), indent=1)
    active = [r for r in rows if any(abs(x) > 1e-6 for x in r["k"][:3]) or abs(r["k"][3] - 1) > 1e-6]
    print("\n%d files with a correction" % len(active))
    for key in ("crop/inside", "crop/outside", "crop/none", "full/inside", "full/outside", "full/none"):
        rms = np.array([r[key][0] for r in active])
        kr = np.array([r[key][1] for r in active])
        free = np.array([r["free"] for r in active])
        print("%-13s rms median %.3f mean %.3f  rms/free median %.3f  |k-1| median %.5f max %.5f" % (
            key, np.median(rms), rms.mean(), np.median(rms / free), np.median(abs(kr - 1)), abs(kr - 1).max()))
