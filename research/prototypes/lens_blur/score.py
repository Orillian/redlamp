#!/usr/bin/env python3
"""Scores a lens blur renderer against the exact truth (OTH-03, #138).

    build/research-venv/bin/python research/prototypes/lens_blur/score.py <renderer> [--set layered|blender]

reads build/proto-out/lens_blur/<renderer>/<set>/<scene>/<focus>/<variant>.exr (linear float RGB, the
truth's size) for every truth variant, and writes score.json and score.md beside them. Per variant:

  * PSNR, SSIM and LPIPS (AlexNet) after a fixed tone map: extended Reinhard per channel with a white
    point of 16, t(x) = x (1 + x / 256) / (1 + x), then the sRGB transfer function;
  * the same in the edge band: pixels within 16 px of a depth discontinuity in the truth depth
    (neighbours in a 3x3 window differing by more than 10% in depth);
  * colour bleeding (focus on the subject only): mean CIE dE2000 between output and truth, tone
    mapped, in the band 2 to 8 px outside the in-focus subject's edge, where no nearer layer covers it;
  * light energy: for each point light that is clean (inside the frame, visible through the pinhole,
    its disc clear of other lights' discs and of nearer content that could blur into it), the
    luminance summed over its truth disc (CoC/2 + its own radius + 1.5 px) in the output over the
    same sum in the truth. Lights brighter than 1.0 are clipped in input_clipped.exr.
"""

import json
import math
import sys
import time

import numpy as np
from scipy import ndimage
from skimage.color import deltaE_ciede2000, rgb2lab
from skimage.metrics import structural_similarity

import common
from common import DATA, OUT, read_exr

BAND_PX = 16
LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


def tone_map(x):
    x = np.maximum(x, 0)
    return common.linear_to_srgb(np.minimum(x * (1 + x / 256) / (1 + x), 1)).astype(np.float32)


def disc(radius):
    r = int(math.ceil(radius))
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= radius * radius


def edge_band(depth):
    log = np.log(np.maximum(depth, 1e-4))
    jump = ndimage.maximum_filter(log, 3) - ndimage.minimum_filter(log, 3) > math.log(1.1)
    return ndimage.binary_dilation(jump, structure=disc(BAND_PX))


def bleed_band(alpha, occluder):
    inside = alpha > 0.5
    band = ndimage.binary_dilation(inside, structure=disc(8)) & ~ndimage.binary_dilation(alpha > 0.02, structure=disc(2))
    if occluder is not None:
        band &= occluder < 0.01
    return band


class Lpips:
    def __init__(self):
        self.model = None
        try:
            import lpips
            import torch
            self.torch = torch
            self.device = "mps" if torch.backends.mps.is_available() else "cpu"
            self.model = lpips.LPIPS(net="alex", spatial=True, verbose=False).to(self.device).eval()
        except Exception as error:  # noqa: BLE001
            print(f"LPIPS unavailable, skipped: {error}")

    def __call__(self, a, b):
        if self.model is None:
            return None
        t = [self.torch.from_numpy(x.transpose(2, 0, 1)[None] * 2 - 1).to(self.device) for x in (a, b)]
        with self.torch.no_grad():
            return self.model(*t)[0, 0].cpu().numpy()


def light_energy(cam, lights, output, truth, depth):
    height, width = depth.shape
    yy, xx = np.mgrid[0:height, 0:width]
    rows = []
    radii = [l["coc_px"] / 2 + l["radius_px"] + 1.5 for l in lights]
    for i, (light, r) in enumerate(zip(lights, radii)):
        x, y, z = light["x"], light["y"], light["depth_m"]
        if not (r + 1 < x < width - r - 1 and r + 1 < y < height - r - 1):
            continue
        cx, cy = int(x), int(y)
        if abs(depth[cy, cx] - z) > 0.1 * z:
            continue
        if any(j != i and math.hypot(x - o["x"], y - o["y"]) < r + radii[j] for j, o in enumerate(lights)):
            continue
        near = depth < 0.8 * z
        if near.any():
            window = (slice(max(cy - int(r) - 200, 0), cy + int(r) + 200), slice(max(cx - int(r) - 200, 0), cx + int(r) + 200))
            z_near = depth[window].min()
            reach = abs(float(common.coc_px(cam, z_near))) / 2
            distance = np.sqrt((xx[near] + 0.5 - x) ** 2 + (yy[near] + 0.5 - y) ** 2).min()
            if distance < r + reach:
                continue
        mask = (xx + 0.5 - x) ** 2 + (yy + 0.5 - y) ** 2 <= r * r
        t = float((truth[mask] @ LUMA).sum())
        o = float((output[mask] @ LUMA).sum())
        rows.append({"ratio": o / t if t > 0 else None, "clipped": max(light["value"]) > 1.0})
    return rows


def score_variant(path, output_path, lpips_model):
    cam = json.loads(path.read_text())
    folder = path.parent
    truth = read_exr(path.with_suffix(".exr"))
    output = read_exr(output_path)
    if output.shape != truth.shape:
        raise ValueError(f"{output_path}: {output.shape} against the truth's {truth.shape}")
    depth = read_exr(folder / "depth.exr")
    a, b = tone_map(output), tone_map(truth)
    band = edge_band(depth)
    squared = ((a - b) ** 2).mean(axis=2)
    ssim_value, ssim_map = structural_similarity(a, b, channel_axis=2, data_range=1.0, full=True)
    ssim_map = ssim_map.mean(axis=2)
    lp = lpips_model(a, b)
    row = {
        "psnr": float(10 * math.log10(1 / max(squared.mean(), 1e-12))),
        "ssim": float(ssim_value),
        "lpips": float(lp.mean()) if lp is not None else None,
        "band_psnr": float(10 * math.log10(1 / max(squared[band].mean(), 1e-12))) if band.any() else None,
        "band_ssim": float(ssim_map[band].mean()) if band.any() else None,
        "band_lpips": float(lp[band].mean()) if lp is not None and band.any() else None,
        "band_share": float(band.mean()),
    }
    row["bleed_de2000"] = None
    if cam["focus"] == "subject" and (folder / "alpha.exr").exists():
        occluder = read_exr(folder / "occluder.exr") if (folder / "occluder.exr").exists() else None
        mask = bleed_band(read_exr(folder / "alpha.exr"), occluder)
        if mask.any():
            row["bleed_de2000"] = float(deltaE_ciede2000(rgb2lab(a[mask][None]), rgb2lab(b[mask][None])).mean())
    energy = light_energy(cam, cam.get("lights", []), output, truth, depth)
    for key, chosen in (("energy_ratio", energy), ("energy_ratio_clipped", [e for e in energy if e["clipped"]]),
                        ("energy_ratio_unclipped", [e for e in energy if not e["clipped"]])):
        values = [e["ratio"] for e in chosen if e["ratio"] is not None]
        row[key] = float(np.median(values)) if values else None
    row["lights_scored"] = len(energy)
    return row


METRICS = ["psnr", "ssim", "lpips", "band_psnr", "band_ssim", "band_lpips", "bleed_de2000", "energy_ratio",
           "energy_ratio_clipped", "energy_ratio_unclipped"]


def mean_of(rows, key):
    values = [r[key] for r in rows if r.get(key) is not None]
    if not values:
        return None
    return float(np.median(values)) if key.startswith("energy") else float(np.mean(values))


def summarise(rows):
    return {key: mean_of(rows, key) for key in METRICS} | {"variants": len(rows)}


def fmt(value, key):
    if value is None:
        return "–"
    if key.endswith("psnr"):
        return f"{value:.2f}"
    if key.startswith("energy") or key.endswith("ssim") or key.endswith("lpips"):
        return f"{value:.3f}"
    return f"{value:.2f}"


def markdown(renderer, results, seconds):
    lines = [f"# Lens blur scores: {renderer}", "",
             "Tone map: extended Reinhard (white 16) per channel, then sRGB. Band: within 16 px of a depth "
             "discontinuity. Bleed: mean dE2000 2–8 px outside the in-focus subject. Energy: median over "
             "clean point lights of output/truth luminance in the light's truth disc (1.0 is right).", ""]
    header = "| | variants | PSNR | SSIM | LPIPS | band PSNR | band SSIM | band LPIPS | bleed dE | energy | energy >1.0 | energy ≤1.0 |"
    rule = "|---" * 13 + "|"
    for set_name, block in results["sets"].items():
        lines += [f"## {set_name}", "", header, rule]
        def row(label, s):
            return f"| {label} | {s['variants']} | " + " | ".join(fmt(s[k], k) for k in METRICS) + " |"
        lines.append(row("**overall**", block["overall"]))
        for focus, s in block["by_focus"].items():
            lines.append(row(f"focus on {focus}", s))
        for scene, s in block["scenes"].items():
            lines.append(row(scene, s))
        lines.append("")
    lines.append(f"Scored in {seconds:.0f} s.")
    return "\n".join(lines) + "\n"


def main(argv):
    renderer = argv[0]
    sets = [argv[argv.index("--set") + 1]] if "--set" in argv else ["layered", "blender"]
    root = OUT / renderer
    lpips_model = Lpips()
    started = time.time()
    results = {"renderer": renderer, "tone_map": "extended Reinhard, white 16, per channel; sRGB", "sets": {}, "rows": []}
    for set_name in sets:
        rows = []
        for path in sorted((DATA / set_name).glob("*/*/f*.json")):
            relative = path.relative_to(DATA).with_suffix(".exr")
            output_path = root / relative
            if not output_path.exists():
                continue
            row = {"set": set_name, "scene": path.parts[-3], "focus": path.parts[-2], "variant": path.stem,
                   **score_variant(path, output_path, lpips_model)}
            rows.append(row)
            print(f"{relative}: PSNR {row['psnr']:.2f}, band {fmt(row['band_psnr'], 'band_psnr')}, "
                  f"bleed {fmt(row['bleed_de2000'], 'bleed')}, energy {fmt(row['energy_ratio'], 'energy')}", flush=True)
        if not rows:
            continue
        results["rows"] += rows
        results["sets"][set_name] = {
            "overall": summarise(rows),
            "by_focus": {f: summarise([r for r in rows if r["focus"] == f]) for f in common.FOCUS_NAMES},
            "scenes": {s: summarise([r for r in rows if r["scene"] == s]) for s in sorted({r["scene"] for r in rows})},
        }
    seconds = time.time() - started
    (root / "score.json").write_text(json.dumps(results, indent=1))
    (root / "score.md").write_text(markdown(renderer, results, seconds))
    print(f"wrote {root / 'score.md'}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
