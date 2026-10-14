#!/usr/bin/env python3
"""Renders the baseline on an estimated depth map and scores it (OTH-03 depth bake-off).

    build/research-venv/bin/python research/prototypes/lens_blur/render_depth.py <label>... [--all-variants] [--keep]

For each label in build/proto-data/lens_blur/estimated/, runs baseline_gaussian.render on input.exr with
estimated/<label>/<set>/<scene>/<focus>/depth.exr in place of the truth's depth.exr, into
build/proto-out/lens_blur/baseline-gaussian@<label>/, and scores it with score.py. The baseline ignores
the aperture's shape, so by default only the circular variants are rendered (f/1.4, f/2.8, f/5.6 in
set A; f/1.8 and f/4.0 in set B): the 5- and 7-blade and oval variants would be the same images.
`truth` renders the truth's own depth over the same variants. The renders are deleted after scoring
unless --keep is given; score.json and score.md stay.
"""

import json
import pathlib
import shutil
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import baseline_gaussian  # noqa: E402
import score  # noqa: E402
from common import DATA, OUT, read_exr, write_exr  # noqa: E402

ESTIMATED = DATA / "estimated"


def main(argv):
    all_variants = "--all-variants" in argv
    keep = "--keep" in argv
    for label in [a for a in argv if not a.startswith("--")]:
        renderer = f"baseline-gaussian@{label}"
        started = time.time()
        count = 0
        for path in sorted(DATA.glob("*/*/*/f*.json")):
            if not all_variants and not path.stem.endswith("-circle"):
                continue
            set_name, scene, focus = path.parts[-4], path.parts[-3], path.parts[-2]
            if "@" in scene:
                continue
            depth_path = path.parent / "depth.exr" if label == "truth" else ESTIMATED / label / set_name / scene / focus / "depth.exr"
            if not depth_path.exists():
                continue
            cam = json.loads(path.read_text())
            out = baseline_gaussian.render(read_exr(path.parent / "input.exr"), read_exr(depth_path), cam)
            write_exr(OUT / renderer / path.relative_to(DATA).with_suffix(".exr"), out)
            count += 1
        print(f"{renderer}: rendered {count} variants in {time.time() - started:.0f} s", flush=True)
        score.main([renderer])
        if not keep:
            for set_name in ("layered", "blender"):
                shutil.rmtree(OUT / renderer / set_name, ignore_errors=True)


if __name__ == "__main__":
    main(sys.argv[1:])
