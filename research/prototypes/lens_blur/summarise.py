#!/usr/bin/env python3
"""Score tables for several renderers over the variants they all have (OTH-03).

    build/research-venv/bin/python research/prototypes/lens_blur/summarise.py <renderer>... [--set S] [--by focus|type|scene]

Reads each renderer's score.json and prints Markdown tables: for each set, the mean of each metric
(the median for energy, as score.py does) over the variants every listed renderer was scored on,
overall and, with --by, per focus, per scene type or per scene.
"""

import json
import sys

import numpy as np

from common import OUT

METRICS = [("psnr", "PSNR", 2), ("band_psnr", "band PSNR", 2), ("ssim", "SSIM", 3), ("band_ssim", "band SSIM", 3),
           ("lpips", "LPIPS", 3), ("band_lpips", "band LPIPS", 3), ("bleed_de2000", "bleed ΔE", 2),
           ("energy_ratio", "energy", 3), ("energy_ratio_clipped", "energy >1", 3)]

TYPES = {"portrait": "portraits", "cat": "cats", "dandelion": "seed heads", "plant": "plants"}


def scene_type(row):
    if row["set"] == "blender":
        return row["scene"]
    name = row["scene"].split("@")[0]
    kind = TYPES[name.split("-")[0]]
    return f"{kind} (2x)" if "@" in row["scene"] else kind


def aggregate(rows, key):
    values = [r[key] for r in rows if r.get(key) is not None]
    if not values:
        return None
    return float(np.median(values)) if key.startswith("energy") else float(np.mean(values))


def main(argv):
    names = [a for a in argv if not a.startswith("--") and (argv.index(a) == 0 or argv[argv.index(a) - 1] not in ("--set", "--by"))]
    sets = [argv[argv.index("--set") + 1]] if "--set" in argv else ["layered", "blender"]
    by = argv[argv.index("--by") + 1] if "--by" in argv else None
    rows = {n: json.loads((OUT / n / "score.json").read_text())["rows"] for n in names}
    for set_name in sets:
        keyed = {n: {(r["scene"], r["focus"], r["variant"]): r for r in rs if r["set"] == set_name} for n, rs in rows.items()}
        common_keys = set.intersection(*(set(k) for k in keyed.values())) if keyed else set()
        if not common_keys:
            continue
        groups = {"all": common_keys}
        if by == "focus":
            groups = {f: {k for k in common_keys if k[1] == f} for f in ("subject", "background")}
        elif by in ("type", "scene"):
            sample = next(iter(keyed.values()))
            label = (lambda k: scene_type(sample[k])) if by == "type" else (lambda k: k[0])
            groups = {}
            for k in sorted(common_keys):
                groups.setdefault(label(k), set()).add(k)
        print(f"\n**Set {'A' if set_name == 'layered' else 'B'} ({set_name}), {len(common_keys)} variants**\n")
        for group, keys in groups.items():
            if by:
                print(f"\n*{group}* ({len(keys)} variants)\n")
            print("| renderer | " + " | ".join(m[1] for m in METRICS) + " |")
            print("|---" * (len(METRICS) + 1) + "|")
            for n in names:
                rs = [keyed[n][k] for k in keys]
                cells = []
                for key, _, digits in METRICS:
                    v = aggregate(rs, key)
                    cells.append("–" if v is None else f"{v:.{digits}f}")
                print(f"| {n} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main(sys.argv[1:])
