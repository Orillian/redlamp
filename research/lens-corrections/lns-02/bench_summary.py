"""Framing scale and edge correlation from camera-bench reports, per file, before and after."""

import hashlib
import json
import os
import sys

import numpy as np

survey_data = json.load(open("survey.json"))
files = [l.strip() for l in open("bench/files.txt")] + [
    os.path.expanduser("~/src/darkroom-lns02/tests/fixtures/cameras/OM-System_OM-1-Mark-II.orf"),
    os.path.expanduser("~/src/darkroom-lns02/tests/fixtures/cameras/Panasonic_DC-S5M2.RW2"),
]


def hashes():
    cache = "bench/hashes.json"
    if os.path.exists(cache):
        return json.load(open(cache))
    out = {}
    for path in files:
        h = hashlib.sha256(open(path, "rb").read()).hexdigest()
        out[h] = os.path.basename(path)
    json.dump(out, open(cache, "w"), indent=1)
    return out


def corrected(name):
    info = survey_data.get(name) or survey_data.get(name.replace("_", "-"))
    if name.startswith("Panasonic_DC-S5M2"):
        info = {"d": [0] * 7 + [1]}
    if name.startswith("OM-System_OM-1-Mark-II"):
        info = {"kind": "OM", "150A": [-0.02, 0.01, 0, 1]}
    if not info:
        return False
    if "d" in info:
        return bool(info["d"]) and (info["d"][7] & 0xF) == 1
    k = info.get("150A")
    return bool(k) and (any(abs(x) > 0 for x in k[:3]) or abs(k[3] - 1) > 1e-6)


def table(path):
    report = json.load(open(path))
    names = hashes()
    out = {}
    for photo in report["photos"]:
        name = names.get(photo["fileHash"])
        checks = {c["id"]: c for c in photo["checks"]}
        framing = checks.get("preview.framing", {}).get("measurements") or {}
        structure = checks.get("preview.structure", {}).get("measurements") or {}
        if "scale" in framing and "correlation" in structure:
            out[name] = (framing["scale"], structure["correlation"], framing.get("offsetX", 0), framing.get("offsetY", 0))
    return out


def summary(label, rows):
    if not rows:
        return
    s = np.array([r[0] for r in rows])
    c = np.array([r[1] for r in rows])
    print("  %-34s n %3d  scale median %.4f (|s−1| median %.4f, max %.4f)  correlation median %.3f" % (
        label, len(rows), np.median(s), np.median(abs(s - 1)), abs(s - 1).max(), np.median(c)))


if __name__ == "__main__":
    before = table(sys.argv[1])
    after = table(sys.argv[2]) if len(sys.argv) > 2 else None
    for fmt, exts in (("Panasonic", (".rw2", ".rwl")), ("Olympus/OM", (".orf", ".ori"))):
        print(fmt)
        for has in (True, False):
            names = [n for n in before if n and n.lower().endswith(exts) and corrected(n) == has]
            summary(("with" if has else "without") + " a correction, before", [before[n] for n in names])
            if after:
                both = [n for n in names if n in after]
                summary(("with" if has else "without") + " a correction, after", [after[n] for n in both])
                if has and both:
                    better_s = sum(abs(after[n][0] - 1) < abs(before[n][0] - 1) - 1e-4 for n in both)
                    better_c = sum(after[n][1] > before[n][1] + 1e-3 for n in both)
                    worse_c = sum(after[n][1] < before[n][1] - 1e-3 for n in both)
                    print("    framing closer to 1 on %d of %d; correlation up on %d, down on %d" % (better_s, len(both), better_c, worse_c))
    if "--list" in sys.argv:
        for n in sorted(k for k in before if k):
            a = after.get(n) if after else None
            print("%-34s %s before scale %.4f corr %.3f%s" % (n, "C" if corrected(n) else " ", before[n][0], before[n][1],
                  "  after scale %.4f corr %.3f" % (a[0], a[1]) if a else ""))
