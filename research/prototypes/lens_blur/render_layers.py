#!/usr/bin/env python3
"""Depth slices blurred by FFT with the aperture's kernel and composited with over (OTH-03).

    build/research-venv/bin/python research/prototypes/lens_blur/render_layers.py --mode plain|fill|oracle
        [--step 1.0] [--clipped] [--sprites] [--name NAME] [--set S] [--scene S] [--focus F] [--variant V]

The signed CoC is linear in disparity, so the image is sliced into layers spaced --step px of CoC
apart, each pixel shared between the two layers around its own CoC (a tent). Each layer's
premultiplied RGBA is convolved with the aperture's image at the layer's CoC, and the layers are
composited front to back.

  plain   the layers as they are; the result is divided by its coverage, so what nearer layers hid
          isn't drawn black.
  fill    as Kraus and Strengert 2007 and MPIB: before blurring, each layer is filled where nearer
          layers hide it, by a pull-push of its own colour and coverage (coverage divided by what was
          visible of it), so a blurred edge shows plausible background rather than nothing.
  oracle  fill, with the subject split off as a layer of its own by the benchmark's exact alpha.exr
          and a blur-fusion estimate of its colour (Forte and Pitie 2021): an upper bound for what a
          matte would give. Not a renderer the app could run as it is. --matte coarse (layers-oracle-
          coarse) uses a mask without strand detail instead (render_common.matte), as a
          segmentation model would give.

--sprites takes small bright lights out before filling and adds their light back into their own
layer, so the fill doesn't spread them. --clipped reads input_clipped.exr; with --sprites it also
gives clipped lights back energy (Glow's clip gain 16).
"""

import math
import sys

import numpy as np
import torch
import torch.nn.functional as F

import common
import render_common as rc
from render_common import DEVICE

CONFIDENT = (0.2, 0.9)


def box(x, radius):
    k = 2 * radius + 1
    return F.avg_pool2d(x[None], k, stride=1, padding=radius, count_include_pad=False)[0]


def blur_fusion(image, alpha, passes=((45, None), (3, None))):
    """Foreground and background colours for a known alpha (Forte and Pitie 2021, two passes)."""
    fg, bg = image, image
    a = alpha[None]
    for radius, _ in passes:
        f_hat = box(fg * a, radius) / box(a, radius).clamp_min(1e-5)
        b_hat = box(bg * (1 - a), radius) / box(1 - a, radius).clamp_min(1e-5)
        fg = (f_hat + a * (image - a * f_hat - (1 - a) * b_hat)).clamp_min(0)
        bg = b_hat
    return fg, bg


def fill_depth(depth, weight):
    disparity = rc.pull_push((1 / depth)[None], weight)[0]
    return 1 / disparity.clamp_min(1e-4)


def sources_for(image, depth, folder, mode, matte="exact"):
    """(premultiplied RGB, alpha, depth) per source, torch on DEVICE."""
    img = rc.to_t(image.transpose(2, 0, 1))
    z = rc.to_t(depth)
    if mode != "oracle":
        return [(img, torch.ones_like(z), z)]
    alpha = rc.to_t(rc.matte(folder, matte))
    fg, _ = blur_fusion(img, alpha)
    subject = fg * alpha[None]
    z_subject = fill_depth(z, (alpha > 0.95).float())
    z_rest = fill_depth(z, (alpha < 0.05).float())
    return [(subject, alpha, z_subject), ((img - subject).clamp_min(0), 1 - alpha, z_rest)]


def fft_blur(x, k):
    """x (C, H, W) convolved with k (kh, kw, odd), same size, zero outside."""
    c, h, w = x.shape
    kh = k.shape[0]
    half = kh // 2
    size = (h + kh, w + kh)
    xf = torch.fft.rfft2(x, s=size)
    kf = torch.fft.rfft2(rc.to_t(k)[None], s=size)
    y = torch.fft.irfft2(xf * kf, s=size)
    return y[:, half:half + h, half:half + w]


def render(image, depth, cam, folder, mode, step, sprites, clipped, matte="exact"):
    h, w = depth.shape
    energy_t, lights = None, []
    if sprites:
        image, energy, labels, lights = rc.detect_lights(image, depth, clipped)
        energy_t = rc.to_t(energy.transpose(2, 0, 1))
        labels_t = torch.from_numpy(labels).to(DEVICE)
    sources = sources_for(image, depth, folder, mode, matte)
    cocs = [rc.to_t(common.coc_px(cam, z.cpu().numpy()).astype(np.float32)) for _, _, z in sources]
    c_lights = [float(common.coc_px(cam, l["depth"])) for l in lights]
    c_all = [float(c.min()) for c in cocs] + [float(c.max()) for c in cocs] + c_lights
    cmin, cmax = min(c_all), max(c_all)
    count = max(int(math.ceil((cmax - cmin) / step)) + 1, 1)
    u = [(c - cmin) / step for c in cocs]
    i0 = [x.floor() for x in u]
    frac = [x - f for x, f in zip(u, i0)]
    out = torch.zeros(3, h, w, device=DEVICE)
    transmit = torch.ones(h, w, device=DEVICE)
    covered = torch.zeros(h, w, device=DEVICE)
    last, i_last = torch.zeros(h, w, device=DEVICE), None
    used = 0
    for i in reversed(range(count)):
        p_i = torch.zeros(3, h, w, device=DEVICE)
        a_i = torch.zeros(h, w, device=DEVICE)
        for (premult, alpha, _), base, t in zip(sources, i0, frac):
            share = torch.where(base == i, 1 - t, torch.zeros_like(t)) + torch.where(base == i - 1, t, torch.zeros_like(t))
            p_i += premult * share[None]
            a_i += alpha * share
        light_here = []
        for light, c in zip(lights, c_lights):
            ui = (c - cmin) / step
            lo = math.floor(ui)
            share = (1 - (ui - lo)) if lo == i else (ui - lo) if lo == i - 1 else 0.0
            if share > 0:
                light_here.append((light, share))
        if float(a_i.max()) <= 1e-6 and not light_here:
            continue
        used += 1
        if mode in ("fill", "oracle"):
            visible = (1 - covered).clamp(0, 1)
            # Dividing by a small visible share amplifies whatever nearer content left in the pixel;
            # the layer just in front holds the other half of the same surface's tent, so it doesn't hide.
            adjacent = last if i_last == i + 1 else torch.zeros_like(last)
            apart = (1 - covered + adjacent).clamp(0, 1)
            known = ((apart - CONFIDENT[0]) / (CONFIDENT[1] - CONFIDENT[0])).clamp(0, 1) ** 2
            safe = visible.clamp_min(0.05)
            values = torch.cat([p_i / safe[None], (a_i / safe).clamp(0, 1)[None]])
            filled = rc.pull_push(values, known)
            p_fill, a_fill = filled[:3], filled[3].clamp(0, 1)
        else:
            p_fill, a_fill = p_i, a_i
        covered = covered + a_i
        last, i_last = a_i, i
        for light, share in light_here:
            p_fill = p_fill + energy_t * (labels_t == light["label"]).float()[None] * share
        radius = (cmin + i * step) / 2
        k = rc.kernel(radius, cam, radius > 0)
        blurred = fft_blur(torch.cat([p_fill, a_fill[None]]), k)
        out += transmit[None] * blurred[:3]
        transmit = transmit * (1 - blurred[3].clamp(0, 1))
    coverage = (1 - transmit).clamp_min(1e-4)
    return (out / coverage[None]).permute(1, 2, 0).cpu().numpy(), used


def main(argv):
    opts = rc.parse_args(argv, {"--mode": "fill", "--step": 1.0, "--name": "", "--matte": "exact"})
    mode, step, matte = opts["values"]["--mode"], opts["values"]["--step"], opts["values"]["--matte"]
    clipped, sprites = "--clipped" in opts["flags"], "--sprites" in opts["flags"]
    name = opts["values"]["--name"] or (f"layers-{mode}" + ("-coarse" if mode == "oracle" and matte == "coarse" else "")
                                        + ("-sprites" if sprites else "") + ("-clipped" if clipped else ""))
    paths = rc.variant_paths(opts["sets"], opts["scenes"], opts["focus"], opts["variants"])
    if mode == "oracle":
        paths = [p for p in paths if (p.parent / "alpha.exr").exists()]
    counts = []

    def one(path, cam):
        image, depth = rc.load(path.parent, clipped)
        out, used = render(image, depth, cam, path.parent, mode, step, sprites, clipped, matte)
        counts.append(used)
        return out

    rc.run(name, paths, one)
    if counts:
        print(f"layers blurred: median {int(np.median(counts))}, max {max(counts)}")


if __name__ == "__main__":
    main(sys.argv[1:])
