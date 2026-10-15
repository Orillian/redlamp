#!/usr/bin/env python3
"""
The ambassadors reel's pictures (src/ambassadors/AmbassadorsReel.tsx): every frame drawn by pixelkit from the
reel's cue sheet, src/ambassadors/cues.json, by its board, scripts/ambassadors/reel.py, and framed in the reel's
margin as the feature videos' frames are (scripts/features-frames.py), into public/ambassadors/frames/, with
frames.json listing each hook's frames. The hooks differ only in the first bar, so the others share the first
hook's frames from the first hit on, and a picture that comes out the same as another is written once.

    python3 scripts/ambassadors-frames.py                   # public/ambassadors/frames/, every hook
    python3 scripts/ambassadors-frames.py --hook pick       # one hook
    python3 scripts/ambassadors-frames.py --only 0,71,200   # these frames at 1080 × 1920, in /tmp/ambassadors-frames/

Needs Pillow and numpy, and pixelkit at $PIXELKIT or ~/src/pixelartvisuals. Warnings from the kit's checks and
the safe zones are printed once each; fix them all.
"""

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from features import world as w  # noqa: E402


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reel = load(HERE / "ambassadors/reel.py", "ambassadors_reel")
framed = load(HERE / "features-frames.py", "features_frames").framed


def draw(f, hook):
    """Frame f with `hook`: the canvas framed in the reel's margin, and the kit's warnings."""
    c = w.canvas()
    spread = []
    for name in ("glow", "dissolve"):
        def recorded(*args, _call=getattr(c, name), _name=name, **kwargs):
            if kwargs.get("region") is None:
                spread.append((_name, args, kwargs))
            return _call(*args, **kwargs)
        setattr(c, name, recorded)
    reel.frame(c, f / reel.PER_BEAT, hook)
    return framed(c.img, spread), w.check(c)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hook", help=f"one hook (default: every hook in copy.json: {', '.join(reel.HOOKS)})")
    parser.add_argument("--only", help="comma-separated frames, written at 1080 × 1920 to /tmp/ambassadors-frames/")
    args = parser.parse_args()
    if args.hook and args.hook not in reel.HOOKS:
        sys.exit(f"no hook called {args.hook}: choose from {', '.join(reel.HOOKS)}")
    hooks = [args.hook] if args.hook else list(reel.HOOKS)
    warnings = {}

    if args.only:
        out = Path("/tmp/ambassadors-frames")
        out.mkdir(parents=True, exist_ok=True)
        for f in (int(x) for x in args.only.split(",")):
            image, notes = draw(f, hooks[0])
            image = image.resize((image.width * w.SHOWN, image.height * w.SHOWN), 0)
            print(f"wrote {w.save(image, out / f'{f:04d}.png')}")
            warnings.update(dict.fromkeys(notes))
    else:
        folder = w.VIDEO / "public/ambassadors"
        frames_dir = folder / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)
        manifest_path = folder / "frames.json"
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() and args.hook else {"frames": {}}
        shared = round(reel.CUE["roadmap"] * reel.PER_BEAT)
        written = set()
        for i, hook in enumerate(hooks):
            names = []
            for f in range(reel.FRAMES):
                if i > 0 and f >= shared:
                    names.append(manifest["frames"][hooks[0]][f])
                    continue
                image, notes = draw(f, hook)
                warnings.update(dict.fromkeys(notes))
                a = np.asarray(image)
                name = f"px-{hashlib.sha1(a.tobytes() + str(a.shape).encode()).hexdigest()[:12]}.png"
                if name not in written:
                    w.save(image, frames_dir / name)
                    written.add(name)
                names.append(name)
            manifest["frames"][hook] = names
        manifest.update({"fps": reel.FPS, "frames": manifest["frames"]})
        manifest_path.write_text(json.dumps(manifest))
        used = {n for names in manifest["frames"].values() for n in names}
        for stale in frames_dir.glob("*.png"):
            if stale.name not in used:
                stale.unlink()
        print(f"==> public/ambassadors/frames/: {len(used)} pictures for {reel.FRAMES} frames, hooks {', '.join(manifest['frames'])}")
    for note in warnings:
        print(f"warning: {note}")


if __name__ == "__main__":
    main()
