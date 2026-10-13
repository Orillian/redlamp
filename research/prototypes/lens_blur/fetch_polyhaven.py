#!/usr/bin/env python3
"""Downloads the Poly Haven assets (all CC0) the Blender scenes use, and records their authors.

    build/research-venv/bin/python research/prototypes/lens_blur/fetch_polyhaven.py

Writes build/proto-data/lens_blur/polyhaven/{hdris,textures,models}/ and assets.json.
"""

import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
DEST = ROOT / "build/proto-data/lens_blur/polyhaven"
API = "https://api.polyhaven.com"

HDRIS = ["birchwood", "cobblestone_street_night", "alps_field", "autumn_forest_04"]
TEXTURES = ["cobblestone_floor_01", "forest_leaves_02", "bark_brown_02", "brick_wall_001", "brown_planks_03",
            "leafy_grass"]
MODELS = ["dandelion_01", "fern_02", "potted_plant_04", "shrub_02", "nettle_plant", "grass_medium_01",
          "street_lamp_01"]


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "redlamp-research/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def save(url, path):
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(get(url))
    print(f"  {path.relative_to(DEST)} ({path.stat().st_size / 1e6:.1f} MB)")


def main():
    assets = []
    for kind, ids in (("hdris", HDRIS), ("textures", TEXTURES), ("models", MODELS)):
        for asset in ids:
            info = json.loads(get(f"{API}/info/{asset}"))
            files = json.loads(get(f"{API}/files/{asset}"))
            folder = DEST / kind / asset
            if kind == "hdris":
                entry = files["hdri"]["4k"]["hdr"]
                save(entry["url"], folder / f"{asset}_4k.hdr")
            elif kind == "textures":
                for key in ("Diffuse", "nor_gl", "Rough"):
                    if key in files:
                        entry = files[key]["2k"]["jpg"] if "jpg" in files[key]["2k"] else files[key]["2k"]["exr"]
                        save(entry["url"], folder / entry["url"].rsplit("/", 1)[1])
            else:
                entry = files["blend"]["1k"]["blend"]
                save(entry["url"], folder / entry["url"].rsplit("/", 1)[1])
                for relative, include in entry.get("include", {}).items():
                    save(include["url"], folder / relative)
            assets.append({"id": asset, "type": kind, "name": info.get("name"), "authors": list(info.get("authors", {})),
                           "page": f"https://polyhaven.com/a/{asset}", "license": "CC0-1.0"})
            print(f"{kind}/{asset}")
    (DEST / "assets.json").write_text(json.dumps(assets, indent=1))


if __name__ == "__main__":
    main()
