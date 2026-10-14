#!/usr/bin/env python3
"""Per-pixel gather with scatter-as-gather weights, near and far fields composited (OTH-03).

    build/research-venv/bin/python research/prototypes/lens_blur/render_gather.py [--clipped] [--sprites]
        [--kappa 16] [--name NAME] [--set layered|blender] [--scene S] [--focus F] [--variant V]

After Jimenez 2014 (Call of Duty: Advanced Warfare), Abadie 2018 ('A Life of a Bokeh') and Gustafsson
2018 ('Bokeh depth of field in a single pass'). Each pixel reads samples on a dense lattice out to
kappa px and on rings beyond it, spaced rho / kappa, out to the largest CoC. A sample counts where
its own CoC, in the aperture's shape, reaches the pixel, weighted by its share of its own disc (so
each sample's light is spread over its disc, as a scatter would). Samples in front of the focus
plane form the near field, whose summed weights are its coverage; the rest form the far field,
where a sample behind the pixel reaches it no further than the pixel's own CoC, so an in-focus
subject keeps its edge, and which is normalised. The near field goes over the far one; where no far
sample reaches, a pull-push fill of the far field stands in for what the near field hides.

--matte exact|coarse gives every pixel the subject's matte covers (alpha above 0.1) the subject's
own depth, as a depth map refined against a matte would: exact is alpha.exr (an oracle), coarse a
mask without strand detail (render_common.matte).

--sprites takes small bright lights out first and splats each as an aperture-shaped sprite at its
own CoC, hidden by the blurred coverage of anything nearer than it. --clipped reads
input_clipped.exr; with --sprites it also gives clipped lights back energy (Glow's clip gain 16,
from 0.9 to the clip point).
"""

import math
import sys

import numpy as np
import torch
from scipy import signal

import common
import render_common as rc
from render_common import DEVICE

BATCH = 16
LUT_STEP = 8
EDGE = "replicate"


def gauge(ux, uy, cam, front):
    """How far the unit aperture reaches along offset direction (ux, uy): an offset rho away is on the
    edge of a source's disc of radius rho * gauge."""
    sign = 1 if front else -1
    ax, ay = sign * ux, sign * -uy
    ap = cam["aperture"]
    if ap["blades"] == 0:
        return np.hypot(ax * ap["ratio"], ay)
    apothem = math.cos(math.pi / ap["blades"])
    g = np.full(np.shape(ax), -np.inf)
    for k in range(ap["blades"]):
        mid = ap["rotation_rad"] + 2 * math.pi * k / ap["blades"]
        g = np.maximum(g, (ax * math.cos(mid) + ay * math.sin(mid)) / apothem)
    return g


def sample_set(radius, kappa):
    """Integer offsets, their distance, the spacing around them and the area each stands for."""
    pts = {}
    dense = min(kappa, radius)
    n = int(math.ceil(dense))
    for oy in range(-n, n + 1):
        for ox in range(-n, n + 1):
            if math.hypot(ox, oy) <= dense + 0.5:
                pts[(ox, oy)] = [1.0, 1.0]
    rho, ring = dense + 1.0, 0
    while rho <= radius + 1.5 and kappa < radius:
        s = max(rho / kappa, 1.0)
        count = max(int(round(2 * math.pi * rho / s)), 8)
        phase = (ring * 0.6180339887) % 1
        for k in range(count):
            t = 2 * math.pi * (k + phase) / count
            key = (int(round(rho * math.cos(t))), int(round(rho * math.sin(t))))
            area = 2 * math.pi * rho * s / count
            if key in pts:
                pts[key][0] += area
            else:
                pts[key] = [area, s]
        rho += s
        ring += 1
    keys = np.array(list(pts.keys()), np.float64)
    vals = np.array(list(pts.values()), np.float64)
    rho_k = np.hypot(keys[:, 0], keys[:, 1])
    return keys.astype(int), rho_k, vals[:, 1], vals[:, 0]


def normaliser(rho_k, spacing, area, g, top):
    radii = np.arange(int(top * LUT_STEP) + 2) / LUT_STEP
    cov = np.clip(0.5 + (radii[:, None] - rho_k[None] * g[None]) / spacing[None], 0, 1)
    return (cov * area[None]).sum(1)


def gather(image, depth, cam, kappa, light_classes=()):
    """The gather; also the blurred coverage of content nearer than each depth in light_classes."""
    h, w = depth.shape
    r = (common.coc_px(cam, depth) / 2).astype(np.float32)
    top = float(np.abs(r).max()) + 1
    offsets, rho_k, spacing, area = sample_set(top, kappa)
    ux, uy = np.divide(offsets[:, 0], rho_k, out=np.zeros(len(rho_k)), where=rho_k > 0), \
        np.divide(offsets[:, 1], rho_k, out=np.zeros(len(rho_k)), where=rho_k > 0)
    g_front, g_back = gauge(ux, uy, cam, True), gauge(ux, uy, cam, False)
    lut_front = torch.tensor(normaliser(rho_k, spacing, area, g_front, top), dtype=torch.float32, device=DEVICE)
    lut_back = torch.tensor(normaliser(rho_k, spacing, area, g_back, top), dtype=torch.float32, device=DEVICE)
    pad = int(math.ceil(top)) + 2
    # Outside the frame repeats its edge: counting those samples as missing leaves near content
    # that touches the frame half covered there.
    mode = "replicate" if EDGE == "replicate" else "constant"
    pd = lambda x: torch.nn.functional.pad(x[None], (pad, pad, pad, pad), mode=mode)[0]  # noqa: E731
    colour = pd(rc.to_t(image.transpose(2, 0, 1)))
    rad = pd(rc.to_t(r)[None])[0]
    logz = pd(rc.to_t(np.log(depth))[None])[0]
    valid = torch.nn.functional.pad(torch.ones(1, h, w, device=DEVICE), (pad, pad, pad, pad),
                                    value=1.0 if EDGE == "replicate" else 0.0)[0]
    rc_ = rc.to_t(r)
    zc = rc.to_t(np.log(depth))
    smooth = lambda x, a, b: ((x - a) / (b - a)).clamp(0, 1).pow(2) * (3 - 2 * ((x - a) / (b - a)).clamp(0, 1))  # noqa: E731
    near_c = smooth(rc_, 0.25, 1.0)
    cn, an = torch.zeros(3, h, w, device=DEVICE), torch.zeros(h, w, device=DEVICE)
    cf, wf = torch.zeros(3, h, w, device=DEVICE), torch.zeros(h, w, device=DEVICE)
    cover = [torch.zeros(h, w, device=DEVICE) for _ in light_classes]
    limits = [math.log(0.9 * z) for z in light_classes]
    t = lambda a: torch.tensor(a, dtype=torch.float32, device=DEVICE)[:, None, None]  # noqa: E731
    for start in range(0, len(offsets), BATCH):
        sel = slice(start, start + BATCH)
        sl = [(slice(pad + oy, pad + oy + h), slice(pad + ox, pad + ox + w)) for ox, oy in offsets[sel]]
        cj = torch.stack([colour[:, a, b] for a, b in sl])
        rj = torch.stack([rad[a, b] for a, b in sl])
        zj = torch.stack([logz[a, b] for a, b in sl])
        vj = torch.stack([valid[a, b] for a, b in sl])
        rk, sk, ak = t(rho_k[sel]), t(spacing[sel]), t(area[sel])
        gf, gb = t(g_front[sel]), t(g_back[sel])
        nf = smooth(rj, 0.25, 1.0)
        behind = ((zj - zc) / 0.05).clamp(0, 1) * (1 - near_c)
        ra = rj.abs()
        reff = ra * (1 - behind) + torch.minimum(ra, rc_.abs()) * behind
        idx = (reff * LUT_STEP).round().long().clamp(0, len(lut_back) - 1)
        w_far = ak * (0.5 + (reff - rk * gb) / sk).clamp(0, 1) / lut_back[idx] * (1 - nf) * vj
        cf += (w_far[:, None] * cj).sum(0)
        wf += w_far.sum(0)
        rn = rj.clamp_min(0)
        idx = (rn * LUT_STEP).round().long().clamp(0, len(lut_front) - 1)
        w_near = ak * (0.5 + (rn - rk * gf) / sk).clamp(0, 1) / lut_front[idx] * nf * vj
        cn += (w_near[:, None] * cj).sum(0)
        an += w_near.sum(0)
        if light_classes:
            front = rj > 0
            idx = (ra * LUT_STEP).round().long().clamp(0, len(lut_back) - 1)
            own = ak * (0.5 + (ra - rk * torch.where(front, gf, gb)) / sk).clamp(0, 1) \
                / torch.where(front, lut_front[idx], lut_back[idx]) * vj
            for c, limit in zip(cover, limits):
                c += (own * (zj < limit)).sum(0)
    alpha = an.clamp(0, 1)
    near = cn / an.clamp_min(1e-6)
    # On the CPU: after the loop above, MPS has returned an all-NaN fill for some frames.
    far_known = (1 - near_c).cpu()
    fill = rc.pull_push(torch.from_numpy(np.ascontiguousarray(image.transpose(2, 0, 1))), far_known).to(DEVICE)
    eps = 1e-3
    far = (cf + eps * fill) / (wf + eps)
    out = alpha * near + (1 - alpha) * far
    return out, [c.clamp(0, 1) for c in cover], len(offsets)


def classes_for(lights, tolerance=0.05):
    """Groups light depths whose logs lie within tolerance."""
    depths = sorted({round(l["depth"], 4) for l in lights})
    classes = []
    for z in depths:
        if not classes or math.log(z / classes[-1][0]) > tolerance:
            classes.append([z])
        else:
            classes[-1].append(z)
    return [min(c) for c in classes]


def render(image, depth, cam, kappa, sprites, clipped):
    if not sprites:
        out, _, n = gather(image, depth, cam, kappa)
        return out.permute(1, 2, 0).cpu().numpy(), n
    base, energy, labels, lights = rc.detect_lights(image, depth, clipped)
    classes = classes_for(lights)
    out, cover, n = gather(base, depth, cam, kappa, classes)
    out = out.permute(1, 2, 0).cpu().numpy()
    h, w = depth.shape
    splats = [np.zeros((h, w, 3), np.float32) for _ in classes]
    for light in lights:
        sl = light["slice"]
        patch = np.where((labels[sl] == light["label"])[..., None], energy[sl], 0)
        radius = float(common.coc_px(cam, light["depth"])) / 2
        k = rc.kernel(radius, cam, radius > 0)
        sprite = np.stack([signal.fftconvolve(patch[..., i], k) for i in range(3)], -1)
        half = k.shape[0] // 2
        y0, x0 = sl[0].start - half, sl[1].start - half
        ys, xs = slice(max(y0, 0), min(y0 + sprite.shape[0], h)), slice(max(x0, 0), min(x0 + sprite.shape[1], w))
        ci = max((i for i, z in enumerate(classes) if z <= round(light["depth"], 4)), default=0)
        splats[ci][ys, xs] += sprite[ys.start - y0:ys.stop - y0, xs.start - x0:xs.stop - x0]
    for s, c in zip(splats, cover):
        out += s * (1 - c.cpu().numpy())[..., None]
    return out, n


def main(argv):
    opts = rc.parse_args(argv, {"--kappa": 16.0, "--name": "", "--matte": "none"})
    clipped, sprites = "--clipped" in opts["flags"], "--sprites" in opts["flags"]
    kappa, matte = opts["values"]["--kappa"], opts["values"]["--matte"]
    name = opts["values"]["--name"] or ("gather" + ("-sprites" if sprites else "") + ("" if matte == "none" else f"-matte-{matte}")
                                        + ("-clipped" if clipped else ""))
    paths = rc.variant_paths(opts["sets"], opts["scenes"], opts["focus"], opts["variants"])
    if matte != "none":
        paths = [p for p in paths if (p.parent / "alpha.exr").exists()]
    counts = []

    def one(path, cam):
        image, depth = rc.load(path.parent, clipped)
        if matte != "none":
            alpha = rc.matte(path.parent, matte)
            depth = np.where(alpha > 0.1, rc.subject_depth(depth, alpha), depth).astype(np.float32)
        out, n = render(image, depth, cam, kappa, sprites, clipped)
        counts.append(n)
        return out

    rc.run(name, paths, one)
    if counts:
        print(f"samples per pixel: median {int(np.median(counts))}, max {max(counts)}")


if __name__ == "__main__":
    main(sys.argv[1:])
