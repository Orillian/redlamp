#!/usr/bin/env python3
"""Tables for the depth bake-off (OTH-03): depth and edge metrics per label, and render scores.

    build/research-venv/bin/python research/prototypes/lens_blur/depth_report.py metrics [<label glob>...]
    build/research-venv/bin/python research/prototypes/lens_blur/depth_report.py renders [<label glob>...]

`metrics` reads build/proto-data/lens_blur/estimated/<label>/metrics.json; `renders` reads
build/proto-out/lens_blur/baseline-gaussian@<label>/score.json and puts each beside
baseline-gaussian@truth (the same renderer on the true depth, same variants), as the difference.
Prints Markdown tables, one per set.
"""

import fnmatch
import json
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import DATA, OUT  # noqa: E402

KEYS = [("coc_mae_px", "CoC err px", 2), ("coc_mae_focus_px", "in focus", 2), ("coc_mae_subject_px", "subject", 2),
        ("coc_mae_ring_px", "ring", 2), ("coc_log_ratio", "blur ratio", 3), ("absrel", "AbsRel", 3),
        ("delta1", "δ<1.25", 3), ("dbe_acc", "DBE acc", 2), ("dbe_comp", "DBE comp", 2), ("flying", "flying", 3)]


def labels(root, patterns, name):
    found = sorted(p.parent.name for p in root.glob(f"*/{name}"))
    if not patterns:
        return found
    return [f for f in found if any(fnmatch.fnmatch(f, p) for p in patterns)]


def metrics(patterns):
    root = DATA / "estimated"
    rows = {lab: json.loads((root / lab / "metrics.json").read_text())["summary"] for lab in labels(root, patterns, "metrics.json")}
    for set_name in ("layered", "blender"):
        print(f"\n{set_name}\n")
        print("| label | " + " | ".join(k[1] for k in KEYS) + " |")
        print("|---" * (len(KEYS) + 1) + "|")
        for lab, s in rows.items():
            if set_name in s:
                print(f"| {lab} | " + " | ".join(f"{s[set_name].get(k, float('nan')):.{d}f}" for k, _, d in KEYS) + " |")


def subset(rows, set_name, focus=None):
    return [r for r in rows if r["set"] == set_name and "@" not in r["scene"] and (focus is None or r["focus"] == focus)]


def mean(rows, key):
    values = [r[key] for r in rows if r.get(key) is not None]
    return float(np.mean(values)) if values else float("nan")


def renders(patterns):
    truth = json.loads((OUT / "baseline-gaussian@truth/score.json").read_text())["rows"]
    found = sorted(p.parent.name.split("@", 1)[1] for p in OUT.glob("baseline-gaussian@*/score.json"))
    found = [f for f in found if f != "truth" and (not patterns or any(fnmatch.fnmatch(f, p) for p in patterns))]
    for set_name in ("layered", "blender"):
        t = subset(truth, set_name)
        ts = subset(truth, set_name, "subject")
        print(f"\n{set_name}: truth depth PSNR {mean(t, 'psnr'):.2f}, band PSNR {mean(t, 'band_psnr'):.2f}, "
              f"band LPIPS {mean(t, 'band_lpips'):.3f}, bleed {mean(ts, 'bleed_de2000'):.2f}\n")
        print("| label | PSNR | Δ | band PSNR | Δ | band LPIPS | Δ | bleed dE | Δ |")
        print("|---" * 9 + "|")
        for lab in found:
            rows = subset(json.loads((OUT / f"baseline-gaussian@{lab}/score.json").read_text())["rows"], set_name)
            if not rows:
                continue
            subj = [r for r in rows if r["focus"] == "subject"]
            cells = []
            for key, chosen, ref, d in (("psnr", rows, t, 2), ("band_psnr", rows, t, 2), ("band_lpips", rows, t, 3),
                                        ("bleed_de2000", subj, ts, 2)):
                v = mean(chosen, key)
                cells += [f"{v:.{d}f}", f"{v - mean(ref, key):+.{d}f}"]
            print(f"| {lab} | " + " | ".join(cells) + " |")


def table(chosen):
    """Depth and edge metrics beside the render's cost against the truth's depth, for given labels."""
    truth = json.loads((OUT / "baseline-gaussian@truth/score.json").read_text())["rows"]
    keys = [("coc_mae_px", 2), ("coc_log_ratio", 3), ("coc_mae_ring_px", 2), ("dbe_acc", 2), ("dbe_comp", 2), ("flying", 3)]
    for set_name in ("layered", "blender"):
        t, ts = subset(truth, set_name), subset(truth, set_name, "subject")
        print(f"\n{set_name}\n")
        print("| | CoC error (px) | blur ratio | ring (px) | DBE acc | DBE comp | flying | ΔPSNR | Δband PSNR | Δbleed |")
        print("|---" * 10 + "|")
        for lab in chosen:
            m = json.loads((DATA / "estimated" / lab / "metrics.json").read_text())["summary"][set_name]
            cells = [f"{m.get(k, float('nan')):.{d}f}" for k, d in keys]
            score = OUT / f"baseline-gaussian@{lab}/score.json"
            if score.exists():
                rows = subset(json.loads(score.read_text())["rows"], set_name)
                subj = [r for r in rows if r["focus"] == "subject"]
                cells += [f"{mean(rows, 'psnr') - mean(t, 'psnr'):+.2f}", f"{mean(rows, 'band_psnr') - mean(t, 'band_psnr'):+.2f}",
                          f"{mean(subj, 'bleed_de2000') - mean(ts, 'bleed_de2000'):+.2f}"]
            else:
                cells += ["–"] * 3
            print(f"| `{lab}` | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    {"metrics": metrics, "renders": renders, "table": table}[sys.argv[1]](sys.argv[2:])
