#!/usr/bin/env python3
"""Refines, aligns and measures the depth estimates of the OTH-03 bake-off (OTH-03, #138).

    build/lens-blur-depth-venv/bin/python research/prototypes/lens_blur/depth_eval.py <source> \
        [--refine none,guided,app,wmf,layers-oracle,layers-vitmatte] [--base none|guided|wmf] \
        [--align disparity,depth,map,pinned] [--set layered|blender] [--store <bits>:<long side>[,…]]
    build/lens-blur-depth-venv/bin/python research/prototypes/lens_blur/depth_eval.py --remeasure <label glob>...

For each raw estimate in build/proto-out/lens_blur/depth-raw/<source>/ (depth_estimate.py):

1. The model's output is turned into disparity (1/depth for a depth model), normalised so its 1st and
   99th percentiles are 0 and 1 (not clipped) and resized bilinearly to the benchmark's size.
2. A refinement, at the benchmark's size, in disparity:
   `none`; `guided`, the app's filter (grey guided filter on the sRGB image's Rec.709 luma, radius 6,
   epsilon 2e-3); `app`, the app's whole chain in the model's own space (normalised between its
   percentiles, clipped to [0, 1], guided, clipped; for DA3 and MoGe that is linear in depth);
   `wmf`, a joint weighted median (radius 7, weights exp(-|dRGB|^2 / (2 0.1^2)) on sRGB, 256 bins,
   interpolated); `layers-<matte>`, two layers at the subject's edge (on `--base`, default none):
   see `two_layers`.
3. Alignment, an oracle for Blur Amount and focus: a scale and an offset fitted by least squares
   against the truth, over every pixel. `disparity` fits 1/z; `depth` fits metres to 1/disparity;
   `map` fits disparity to the app's map itself (`app` only), as if a depth model's map were
   disparity, which is what a renderer reading the app's stored DA3 map as disparity gets; `pinned`
   fixes the in-focus pixels' median (focus clicked there) and fits only the scale about it.
   Depth is then 1/disparity, clamped to 0.05-1000 m.
4. Written to build/proto-data/lens_blur/estimated/<label>/<set>/<scene>/<focus>/depth.exr, label
   `<source>+<refinement>[~<align>]` (disparity has no suffix), in metres, the truth's convention.
5. Metrics against the truth depth.exr, in disparity D = 1/z: AbsRel and delta < 1.25; the CoC error
   |K (D_est - D)| in px at the widest aperture of that focus, over the frame, over the in-focus
   pixels (|truth CoC| < 1 px), over the subject (visible alpha above 0.02, dilated by 16 px) and
   over its ring (that, less alpha above 0.98 eroded by 4 px); `--remeasure` adds those two and the
   blur ratio, the mean |log((|c_est| + 2) / (|c_true| + 2))|, to labels already measured;
   depth-boundary errors as in iBims-1 (edges by Canny on log D with
   sigma 1 and thresholds 0.1 / 0.2, accuracy the mean distance from each estimated edge pixel within
   10 px of a true edge to the nearest true edge, completeness the mean distance from each true edge
   pixel to the nearest estimated edge, truncated at 10 px); flying pixels, the share of pixels within
   8 px of a true discontinuity (score.py's: a 3x3 depth jump over 10%), whose truth lies within 10%
   of the gap of either side (the two sides being the truth's largest and smallest D within 8 px) and
   whose estimate lies in the middle 80% of the gap.

`--store 8:1024` quantises the refined map's disparity (normalised min to max) to 8 bits and stores it
with its long side at 1024 / 6000 of the benchmark's (a 24-megapixel photo's 1024 px), then
upsamples it bilinearly before the alignment; `full` keeps the benchmark's size, and `8:1024:wmf`
runs the weighted median on the upsampled map, as a renderer could on loading it. Several settings
are separated by commas. The label gets `#<bits>b<size>[:wmf]`.
Writes metrics.json beside the label's depths, and prints the summary.
"""

import json
import math
import pathlib
import sys
import time

import cv2
import numpy as np
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import common  # noqa: E402
from common import DATA, OUT, read_exr, write_exr  # noqa: E402

RAW = OUT / "depth-raw"
ESTIMATED = DATA / "estimated"
MATTES = OUT / "depth-mattes"
PHOTO_LONG_SIDE = 6000


def disc(radius):
    r = int(math.ceil(radius))
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    return x * x + y * y <= radius * radius


def srgb(folder):
    return common.linear_to_srgb(read_exr(folder / "input.exr")).astype(np.float32)


def luma(rgb):
    return (rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)).astype(np.float32)


def guided(p, guide, radius=6, eps=2e-3):
    k = (2 * radius + 1, 2 * radius + 1)
    box = lambda x: cv2.boxFilter(x, -1, k, borderType=cv2.BORDER_REFLECT)  # noqa: E731
    mI, mP = box(guide), box(p)
    var = box(guide * guide) - mI * mI
    cov = box(guide * p) - mI * mP
    a = cov / (var + eps)
    b = mP - a * mI
    return (box(a) * guide + box(b)).astype(np.float32)


def weighted_median(values, rgb, radius=7, sigma=0.1, bins=256):
    import torch
    v = torch.from_numpy(values.astype(np.float32))
    lo, hi = float(v.min()), float(v.max())
    width = max(hi - lo, 1e-9) / bins
    q = ((v - lo) / width).clamp(0, bins - 1e-4)
    index = q.floor().long()
    img = torch.from_numpy(rgb)
    H, W = values.shape
    pad = lambda t: torch.nn.functional.pad(t[None, None] if t.ndim == 2 else t.permute(2, 0, 1)[None],  # noqa: E731
                                            (radius,) * 4, mode="replicate")[0]
    ip, imgp = pad(index.float())[0].long(), pad(img)
    out = torch.empty(H * W)
    rows = 48
    offsets = [(dy, dx) for dy in range(-radius, radius + 1) for dx in range(-radius, radius + 1)]
    for r0 in range(0, H, rows):
        r1 = min(r0 + rows, H)
        n = (r1 - r0) * W
        hist = torch.zeros(bins, n)
        centre = img[r0:r1].reshape(n, 3)
        for dy, dx in offsets:
            ys = slice(r0 + radius + dy, r1 + radius + dy)
            xs = slice(radius + dx, radius + dx + W)
            nb = imgp[:, ys, xs].permute(1, 2, 0).reshape(n, 3)
            w = torch.exp(-((nb - centre) ** 2).sum(1) / (2 * sigma * sigma))
            hist.scatter_add_(0, ip[ys, xs].reshape(1, n), w[None])
        cum = hist.cumsum(0)
        half = cum[-1] / 2
        b = (cum < half[None]).sum(0).clamp(max=bins - 1)
        prev = torch.where(b > 0, cum.gather(0, (b - 1).clamp(min=0)[None])[0], torch.zeros(n))
        mass = hist.gather(0, b[None])[0].clamp(min=1e-12)
        frac = ((half - prev) / mass).clamp(0, 1)
        out[r0 * W:r1 * W] = lo + (b.float() + frac) * width
    return out.reshape(H, W).numpy()


def nearest_fill(values, valid):
    if valid.all() or not valid.any():
        return values
    _, (iy, ix) = ndimage.distance_transform_edt(~valid, return_indices=True)
    return values[iy, ix]


def matte(set_name, scene, focus, folder, kind):
    if kind == "oracle":
        alpha = read_exr(folder / "alpha.exr")
        if (folder / "occluder.exr").exists():
            alpha = alpha * (1 - read_exr(folder / "occluder.exr"))
        return np.clip(alpha, 0, 1)
    return np.load(MATTES / set_name / scene / focus / "vitmatte.npy")


def two_layers(z, alpha, width):
    """The subject's depth held out to the matte's edge and the background's behind it.

    The subject layer takes the estimate where the matte is above 0.98, eroded by 0.8% of the
    width (8 px at 1024), and the background layer where it is below 0.02, dilated by the same; each
    is filled outward from its nearest reliable pixel, and they are composited by the matte in
    metres, the truth's convention for soft edges."""
    r = max(2, round(0.008 * width))
    core = ndimage.binary_erosion(alpha > 0.98, structure=disc(r))
    clear = ~ndimage.binary_dilation(alpha > 0.02, structure=disc(r))
    if not core.any():
        return z
    zs = nearest_fill(z, core)
    zb = nearest_fill(z, clear)
    return (alpha * zs + (1 - alpha) * zb).astype(np.float32)


def fit(x, y):
    A = np.stack([x.ravel().astype(np.float64), np.ones(x.size)], 1)
    coef, *_ = np.linalg.lstsq(A, y.ravel().astype(np.float64), rcond=None)
    return coef


def align(q, lo, hi, truth_z, mode, app_map=None, in_focus=None):
    """q: the refined disparity, normalised; returns depth in metres."""
    truth_d = 1 / truth_z
    if mode == "pinned":
        # Focus clicked on the in-focus region, then Blur Amount: one scale about that point.
        q_f, d_f = float(np.median(q[in_focus])), float(np.median(truth_d[in_focus]))
        x, y = (q - q_f).ravel().astype(np.float64), (truth_d - d_f).ravel().astype(np.float64)
        a = float(x @ y / max(x @ x, 1e-12))
        return (1 / np.clip(a * (q - q_f) + d_f, 1e-3, 20)).astype(np.float32)
    if mode == "depth":
        depth = 1 / np.maximum(lo + q * (hi - lo), 1e-6 * hi)
        a, b = fit(depth, truth_z)
        return np.clip(a * depth + b, 0.05, 1000).astype(np.float32)
    x = app_map if mode == "map" else q
    a, b = fit(x, truth_d)
    return (1 / np.clip(a * x + b, 1e-3, 20)).astype(np.float32)


def canny_edges(d):
    from skimage.feature import canny
    return canny(np.log(np.maximum(d, 1e-4)), sigma=1.0, low_threshold=0.1, high_threshold=0.2)


def boundary_errors(est_d, true_edges, theta=10.0):
    est_edges = canny_edges(est_d)
    if not true_edges.any():
        return None, None
    to_true = ndimage.distance_transform_edt(~true_edges)
    near = est_edges & (to_true < theta)
    acc = float(to_true[near].mean()) if near.any() else theta
    to_est = ndimage.distance_transform_edt(~est_edges) if est_edges.any() else np.full(est_d.shape, theta)
    comp = float(np.minimum(to_est[true_edges], theta).mean())
    return acc, comp


class Truth:
    """What the metrics need from the truth depth, computed once per image."""

    def __init__(self, truth_z, cam, alpha=None):
        self.z, self.d, self.cam = truth_z, 1 / truth_z, cam
        self.subject = self.ring = None
        if alpha is not None and (alpha > 0.5).any():
            self.subject = ndimage.binary_dilation(alpha > 0.02, structure=disc(16))
            self.ring = self.subject & ~ndimage.binary_erosion(alpha > 0.98, structure=disc(4))
        self.edges = canny_edges(self.d)
        self.to_edges = ndimage.distance_transform_edt(~self.edges)
        log = np.log(truth_z)
        jump = ndimage.maximum_filter(log, 3) - ndimage.minimum_filter(log, 3) > math.log(1.1)
        band = ndimage.binary_dilation(jump, structure=disc(8))
        near = ndimage.maximum_filter(self.d, footprint=disc(8))
        far = ndimage.minimum_filter(self.d, footprint=disc(8))
        gap = near - far
        self.clean = band & (gap > 0.1 * far) & ((self.d > near - 0.1 * gap) | (self.d < far + 0.1 * gap))
        self.low, self.high = far + 0.1 * gap, near - 0.1 * gap
        self.in_focus = np.abs(common.coc_px(cam, truth_z)) < 1


def boundary_errors(est_d, truth, theta=10.0):
    est_edges = canny_edges(est_d)
    if not truth.edges.any():
        return None, None
    near = est_edges & (truth.to_edges < theta)
    acc = float(truth.to_edges[near].mean()) if near.any() else theta
    to_est = ndimage.distance_transform_edt(~est_edges) if est_edges.any() else np.full(est_d.shape, theta)
    comp = float(np.minimum(to_est[truth.edges], theta).mean())
    return acc, comp


def flying_share(est_d, truth):
    flying = truth.clean & (est_d > truth.low) & (est_d < truth.high)
    return float(flying.sum() / max(truth.clean.sum(), 1)), int(truth.clean.sum())


def widest_camera(folder):
    cams = [json.loads(p.read_text()) for p in folder.glob("f*-circle.json")]
    return min(cams, key=lambda c: c["f_number"])


def metrics(z, truth):
    d, td, cam = 1 / z, truth.d, truth.cam
    ratio = np.maximum(d / td, td / d)
    K = cam["coc"]["coc_px_per_inverse_metre"]
    coc_err = K * np.abs(d - td)
    in_focus = truth.in_focus
    acc, comp = boundary_errors(d, truth)
    fly, fly_n = flying_share(d, truth)
    return {"absrel": float((np.abs(d - td) / td).mean()), "delta1": float((ratio < 1.25).mean()),
            "coc_mae_px": float(coc_err.mean()),
            "coc_mae_focus_px": float(coc_err[in_focus].mean()) if in_focus.any() else None,
            "coc_mae_subject_px": float(coc_err[truth.subject].mean()) if truth.subject is not None else None,
            "coc_mae_ring_px": float(coc_err[truth.ring].mean()) if truth.ring is not None else None,
            "dbe_acc": acc, "dbe_comp": comp, "flying": fly, "flying_band_px": fly_n}


def store(native, bits, size, shape):
    lo, hi = float(native.min()), float(native.max())
    q = (native - lo) / max(hi - lo, 1e-9)
    if bits:
        levels = 2 ** bits - 1
        q = np.round(q * levels) / levels
    if size != "full":
        h, w = shape
        k = int(size) / PHOTO_LONG_SIDE
        small = (max(1, round(w * k)), max(1, round(h * k)))
        q = cv2.resize(cv2.resize(q.astype(np.float32), small, interpolation=cv2.INTER_AREA), (w, h),
                       interpolation=cv2.INTER_LINEAR)
    return (lo + q * (hi - lo)).astype(np.float32)


def app_chain(raw, kind, rgb, shape):
    """The app's map: the model's own output normalised between its percentiles, clipped, guided,
    clipped, near white. Returns it and, for depth models, the depth it stands for."""
    lo, hi = np.percentile(raw, [1, 99])
    H, W = shape
    n = cv2.resize((raw - lo) / max(hi - lo, 1e-9), (W, H), interpolation=cv2.INTER_LINEAR)
    n = np.clip(guided(np.clip(n, 0, 1), luma(rgb)), 0, 1)
    if kind == "disparity":
        return n, None
    return 1 - n, lo + n * (hi - lo)


def refine(name, q, rgb, cache):
    if name == "none":
        return q
    if name == "guided":
        return guided(q, luma(rgb))
    if name == "wmf":
        if "wmf" not in cache:
            cache["wmf"] = weighted_median(q, rgb)
        return cache["wmf"]
    raise ValueError(name)


def summarise(rows):
    keys = ["absrel", "delta1", "coc_mae_px", "coc_mae_focus_px", "coc_mae_subject_px", "coc_mae_ring_px",
            "coc_log_ratio", "dbe_acc", "dbe_comp", "flying"]
    out = {}
    for set_name in sorted({r["set"] for r in rows}):
        chosen = [r for r in rows if r["set"] == set_name]
        out[set_name] = {k: float(np.mean([r[k] for r in chosen if r.get(k) is not None] or [np.nan])) for k in keys}
        out[set_name]["images"] = len(chosen)
    return out


def remeasure(patterns):
    """Recomputes metrics.json for labels already written, from their depth.exr files."""
    import fnmatch
    truths = {}
    for label_dir in sorted(p for p in ESTIMATED.iterdir() if p.is_dir()):
        if not any(fnmatch.fnmatch(label_dir.name, p) for p in patterns):
            continue
        rows = json.loads((label_dir / "metrics.json").read_text())["rows"]
        for row in rows:
            set_name, scene, focus = row["set"], row["scene"], row["focus"]
            folder = DATA / set_name / scene / focus
            key = (set_name, scene, focus)
            if key not in truths:
                truth_z = read_exr(folder / "depth.exr")
                alpha = matte(set_name, scene, focus, folder, "oracle")
                subject = ndimage.binary_dilation(alpha > 0.02, structure=disc(16))
                ring = subject & ~ndimage.binary_erosion(alpha > 0.98, structure=disc(4))
                cam = widest_camera(folder)
                truths[key] = (1 / truth_z, cam["coc"]["coc_px_per_inverse_metre"], subject, ring, 1 / cam["focus_distance_m"])
            td, K, subject, ring, ds = truths[key]
            d = 1 / read_exr(label_dir / set_name / scene / focus / "depth.exr")
            err = K * np.abs(d - td)
            row["coc_log_ratio"] = float(np.abs(np.log((K * np.abs(d - ds) + 2) / (K * np.abs(td - ds) + 2))).mean())
            row["coc_mae_subject_px"] = float(err[subject].mean()) if subject.any() else None
            row["coc_mae_ring_px"] = float(err[ring].mean()) if ring.any() else None
        (label_dir / "metrics.json").write_text(json.dumps({"label": label_dir.name, "summary": summarise(rows),
                                                            "rows": rows}, indent=1))
        print(f"remeasured {label_dir.name}", flush=True)


def main(argv):
    if argv[0] == "--remeasure":
        return remeasure(argv[1:])
    source = argv[0]
    opt = lambda key, default: argv[argv.index(key) + 1] if key in argv else default  # noqa: E731
    refinements = opt("--refine", "none,guided,app,wmf").split(",")
    aligns = opt("--align", "disparity").split(",")
    sets = [opt("--set", None)] if "--set" in argv else ["layered", "blender"]
    base = opt("--base", "none")
    stored = opt("--store", None)
    started = time.time()
    results = {}
    for set_name in sets:
        for raw_path in sorted((RAW / source / set_name).glob("*/*/raw.npy")):
            scene, focus = raw_path.parts[-3], raw_path.parts[-2]
            folder = DATA / set_name / scene / focus
            kind = json.loads((raw_path.parent / "meta.json").read_text())["kind"]
            raw = np.load(raw_path).astype(np.float32)
            q_raw = raw if kind == "disparity" else 1 / np.maximum(raw, 1e-6)
            lo, hi = np.percentile(q_raw, [1, 99])
            truth_z = read_exr(folder / "depth.exr")
            H, W = truth_z.shape
            q = cv2.resize((q_raw - lo) / max(hi - lo, 1e-9), (W, H), interpolation=cv2.INTER_LINEAR)
            rgb = srgb(folder)
            truth = Truth(truth_z, widest_camera(folder), matte(set_name, scene, focus, folder, "oracle"))
            cache = {}
            for refinement in refinements:
                layered = refinement.startswith("layers-")
                app_map = None
                if refinement == "app":
                    app_map, app_depth = app_chain(raw, kind, rgb, (H, W))
                    native = app_map if kind == "disparity" else (1 / np.maximum(app_depth, 1e-6) - lo) / (hi - lo)
                else:
                    native = refine(base if layered else refinement, q, rgb, cache)
                for storage in stored.split(",") if stored else [None]:
                    kept = native
                    if storage:
                        bits, size, *upsample = storage.split(":")
                        kept = store(native, int(bits), size, (H, W))
                        if upsample == ["wmf"]:
                            kept = weighted_median(kept, rgb)
                    for mode in aligns:
                        if mode in ("depth", "map") and kind == "disparity":
                            continue
                        if mode == "map" and app_map is None:
                            continue
                        z = align(kept, lo, hi, truth_z, mode, app_map, truth.in_focus)
                        if layered:
                            z = two_layers(z, matte(set_name, scene, focus, folder, refinement[7:]), W)
                        label = f"{source}+{refinement}" + (f"/{base}" if layered and base != "none" else "")
                        label += "" if mode == "disparity" else f"~{mode}"
                        label += f"#{storage.replace(':', 'b')}" if storage else ""
                        write_exr(ESTIMATED / label / set_name / scene / focus / "depth.exr", z)
                        row = {"set": set_name, "scene": scene, "focus": focus, **metrics(z, truth)}
                        results.setdefault(label, []).append(row)
            print(f"{source} {set_name}/{scene}/{focus}: {time.time() - started:.0f} s", flush=True)
    for label, rows in results.items():
        summary = summarise(rows)
        target = ESTIMATED / label / "metrics.json"
        target.write_text(json.dumps({"label": label, "summary": summary, "rows": rows}, indent=1))
        print(label, json.dumps({s: {k: round(v, 4) for k, v in d.items()} for s, d in summary.items()}))


if __name__ == "__main__":
    main(sys.argv[1:])
