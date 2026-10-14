#!/usr/bin/env python3
"""Makes the table of exposure anchors Redlamp ships (CAM-29) from a camera bench report.

The camera bench compares Redlamp's default rendering of each raw with the JPEG the camera
embedded in it: preview.exposure is the median of log2(ours / theirs) over flat midtones. Each
camera's entry is how many stops its photos need beyond the typical camera's to open at the
brightness of its own JPEGs: the bench's median offset among the camera's photos, measured from
the median of every photo, with the sign turned. A camera with few photos is pulled towards its
maker and format's median by n / (n + 1) for n photos, and the table also carries each maker and
format's median and each maker's, for cameras it lacks. Previews made by Adobe's software
(DNG Converter, Lightroom, Camera Raw) aren't the camera's own and are left out, as are photos
whose decode, orientation, framing or structure checks failed, whose comparison means nothing.
The bench's midtones move further than the exposure through the tone curve's contrast (1.37
times as far, measured on the run at process 16 with uncorrected values), so each correction is
the offset divided by that response, and so is `lookStops`, the median's.

    scripts/exposure-anchors.py [report.json ...] [-o packages/RedlampEngineAPI/Resources/ExposureAnchors.json]
        [--check]

Without an output it prints the table's held-out estimate, each photo corrected by what the
other photos say, by maker; --check fails when the shipped table isn't what the reports make.
"""

import argparse
import collections
import json
import pathlib
import statistics
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORTS = [ROOT / "research/camera-bench/raw-pixls-process-15.json"]
OUTPUT = ROOT / "packages/RedlampEngineAPI/Resources/ExposureAnchors.json"
FAMILIES = {"CRW": "CR2", "NRW": "NEF", "SRF": "ARW", "SR2": "ARW", "RWL": "RW2"}
SHRINK = 1.0
RESPONSE = 1.37


def camera_name(make, model):
    """ImageInfo.cameraName: the model, after the make unless the model already names it."""
    if model is None:
        return make
    if make is None or make.lower() in model.lower():
        return model
    return f"{make} {model}"


def family(format_):
    format_ = (format_ or "").upper()
    return FAMILIES.get(format_, format_)


def usable(photo):
    checks = {check["id"]: check for check in photo["checks"]}
    exposure = checks.get("preview.exposure")
    if not exposure or exposure["verdict"] not in ("pass", "warn"):
        return False
    if "adobe" in (photo["identity"].get("software") or "").lower():
        return False
    for check in photo["checks"]:
        if check["verdict"] == "fail" and (check["id"].startswith("decode.") or check["id"] in (
                "preview.orientation", "preview.framing", "preview.structure")):
            return False
    return True


def samples(reports):
    rows = []
    for path in reports:
        for photo in json.loads(pathlib.Path(path).read_text())["photos"]:
            if not usable(photo):
                continue
            identity = photo["identity"]
            stops = next(c for c in photo["checks"] if c["id"] == "preview.exposure")["measurements"]["stops"]
            rows.append({
                "camera": camera_name(identity.get("make"), identity.get("model")),
                "make": identity.get("make"),
                "maker": identity.get("normalizedMake") or identity.get("make"),
                "family": family(identity.get("format")),
                "stops": stops,
            })
    return rows


def table(rows):
    """Each camera's, maker and format's and maker's stops beyond the typical camera's."""
    median = statistics.median(r["stops"] for r in rows)
    by_maker = collections.defaultdict(list)
    by_family = collections.defaultdict(list)
    by_camera = collections.defaultdict(list)
    for r in rows:
        by_maker[r["maker"]].append(r["stops"])
        by_family[(r["maker"], r["family"])].append(r["stops"])
        by_camera[r["camera"]].append(r)
    makers = {m: statistics.median(v) for m, v in by_maker.items() if len(v) >= 3}
    families = {k: statistics.median(v) for k, v in by_family.items() if len(v) >= 3}

    def group(maker, family_):
        return families.get((maker, family_), makers.get(maker, median))

    cameras = {}
    for camera, photos in by_camera.items():
        own = statistics.median(p["stops"] for p in photos)
        prior = group(photos[0]["maker"], photos[0]["family"])
        weight = len(photos) / (len(photos) + SHRINK)
        cameras[camera] = prior + weight * (own - prior)
    makes = {}
    for r in rows:
        if r["maker"] in makers and r["make"]:
            makes[r["make"]] = makers[r["maker"]]
    family_keys = {}
    for r in rows:
        if (r["maker"], r["family"]) in families and r["make"]:
            family_keys[f'{r["make"]}|{r["family"]}'] = families[(r["maker"], r["family"])]

    def correction(offset):
        return round((median - offset) / RESPONSE, 2)

    return median, {
        "format": 1,
        "photos": len(rows),
        "medianStops": round(median, 2),
        "response": RESPONSE,
        "lookStops": round(-median / RESPONSE, 2),
        "cameras": {k: correction(v) for k, v in sorted(cameras.items())},
        "families": {k: correction(v) for k, v in sorted(family_keys.items())},
        "makes": {k: correction(v) for k, v in sorted(makes.items())},
    }


def held_out(rows):
    """Each photo's offset after its correction from a table made without it, and before."""
    out = []
    for index, row in enumerate(rows):
        others = rows[:index] + rows[index + 1:]
        median, made = table(others)
        correction = made["cameras"].get(row["camera"])
        if correction is None:
            correction = made["families"].get(f'{row["make"]}|{row["family"]}', made["makes"].get(row["make"], 0))
        out.append((row["maker"], row["stops"], row["stops"] + RESPONSE * (correction + made["lookStops"])))
    return out


def summary(values):
    n = len(values)
    return (f"n {n:4d}  median {statistics.median(values):+.2f}  more than a stop off "
            f"{sum(abs(v) > 1 for v in values) / n:5.1%}  more than a third {sum(abs(v) > 1 / 3 for v in values) / n:5.1%}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("reports", nargs="*", default=[str(p) for p in REPORTS])
    parser.add_argument("-o", "--output", help="write the table here")
    parser.add_argument("--check", action="store_true", help="fail when the shipped table differs")
    options = parser.parse_args()
    rows = samples(options.reports)
    _, made = table(rows)
    text = json.dumps(made, indent=1, ensure_ascii=False) + "\n"
    if options.check:
        if OUTPUT.read_text() != text:
            sys.exit(f"{OUTPUT.relative_to(ROOT)} isn't what {', '.join(options.reports)} make: run scripts/exposure-anchors.py -o it")
        return
    if options.output:
        pathlib.Path(options.output).write_text(text)
        print(f"wrote {options.output}: {len(made['cameras'])} cameras from {made['photos']} photos")
        return
    results = held_out(rows)
    by_maker = collections.defaultdict(list)
    for maker, before, after in results:
        by_maker[maker].append((before, after))
    print("Held out, each photo corrected by a table made without it: before, then after")
    for maker, pairs in sorted(by_maker.items(), key=lambda kv: -len(kv[1])):
        if len(pairs) >= 24:
            print(f"{maker:12s} before {summary([b for b, _ in pairs])}")
            print(f"{'':12s} after  {summary([a for _, a in pairs])}")
    print(f"{'Every photo':12s} before {summary([b for _, b, _ in results])}")
    print(f"{'':12s} after  {summary([a for _, _, a in results])}")


if __name__ == "__main__":
    main()
