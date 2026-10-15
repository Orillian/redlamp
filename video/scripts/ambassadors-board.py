#!/usr/bin/env python3
"""
The ambassadors reel's storyboard sheet: its eight panels, one a bar, from its board (scripts/ambassadors/reel.py),
laid out as the feature videos' sheets are (scripts/features-boards.py), with the claim, its sources and the photo
in the footer; and, at their own size, each hook's cover (the hook over the lamp at its warmest, the first bar's
last frame) and the post on the drop, for the rooms.

    python3 scripts/ambassadors-board.py    # out/ambassadors/board.png, board-hook-<hook>.png, board-post.png

Needs Pillow and numpy, and pixelkit at $PIXELKIT or ~/src/pixelartvisuals. Every warning the kit or the safe zones
raise is printed; fix them all.
"""

import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from features import world as w  # noqa: E402


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reel = load(HERE / "ambassadors/reel.py", "ambassadors_reel")
boards = load(HERE / "features-boards.py", "features_boards")
OUT = w.VIDEO / "out/ambassadors"
COVER = round(reel.CUE["roadmap"] * reel.PER_BEAT) - 1

CLAIM = ("Each quarter, ambassadors pick one feature from a shortlist of the roadmap, and it's built next; their edits "
         "are shown with their name; ten founding places; unpaid; apply at redlamp.app/join with a photo edited in Redlamp.")
SOURCE = ("The programme, plans/2026-10-15-ambassadors.md in the private redlamp-social repository (the offer, the cohort, "
          "the ambassadors' pick); DEC-86 in the tracker; the page, web/content/ambassadors.ts; /join redirects to its form "
          "(web/next.config.ts).")
PHOTO = ("No photo: a pixel-art street at dusk stands in, developed by Exposure +1.00 and Vibrance +40. The roadmap's rows "
         "are drawn for UX-38, UX-35, UX-41 and UX-37, each Accepted and Not started in Phase 2. The maker at the laptop "
         "and the photographers on the roll are drawn characters, not real people or ambassadors.")


def main():
    board = SimpleNamespace(EPISODE={"id": "ambassadors", "title": "reel", "feature": CLAIM, "source": SOURCE},
                            PANELS=reel.PANELS, PHOTO=PHOTO)
    drawn = [boards.draw(p) for p in reel.PANELS]
    for panel, (_, _, notes) in zip(reel.PANELS, drawn):
        for note in notes:
            print(f"bar {panel.bar}: warning: {note}")
    c, overlays = boards.sheet("ambassadors", board, drawn)
    for note in w.check(c, video=False):
        print(f"sheet: warning: {note}")
    paths = [w.save(w.render(c, boards.SHEET, overlays), OUT / "board.png")]
    for hook in reel.HOOKS:
        cover = w.canvas()
        reel.frame(cover, COVER / reel.PER_BEAT, hook)
        paths.append(w.save(cover.img, OUT / f"board-hook-{hook}.png"))
    post = w.canvas()
    reel.frame(post, reel.CUE["credit"] + 0.6)
    paths.append(w.save(post.img, OUT / "board-post.png"))
    for path in paths:
        print(f"wrote {path.relative_to(w.VIDEO)}")


if __name__ == "__main__":
    main()
