"""Lateral chromatic aberration in a raw render and in its camera JPEG.

For each of red and blue against green: SIFT pairs within the image, fitted as
p_c = c + (p_g − c)·(1 + a + b r² + e r⁴), r in units of the frame's half-diagonal.
Returns the scale (p_c/p_g − 1) at a few radii, in parts per 10⁴.
"""

import sys

import cv2
import numpy as np
import rawpy

import measure


def channel_pairs(a, b, long_edge=4000):
    f = long_edge / max(a.shape)
    A = measure.resized(a, long_edge)
    B = measure.resized(b, long_edge)
    sift = cv2.SIFT_create(nfeatures=30000, contrastThreshold=0.02)
    ka, da = sift.detectAndCompute(A, None)
    kb, db = sift.detectAndCompute(B, None)
    if da is None or db is None:
        return None
    bf = cv2.BFMatcher(cv2.NORM_L2, crossCheck=True)
    ms = bf.match(da, db)
    pa = (np.array([ka[m.queryIdx].pt for m in ms]) + 0.5) / f
    pb = (np.array([kb[m.trainIdx].pt for m in ms]) + 0.5) / f
    d = np.linalg.norm(pa - pb, axis=1)
    keep = d < 6
    return pa[keep], pb[keep]


def radial_scale(pg, pc, centre, R, terms=3, iterations=5):
    keep = np.ones(len(pg), bool)
    for _ in range(iterations):
        q = (pg[keep] - centre) / R
        r2 = (q ** 2).sum(1)
        cols = [q * (r2 ** i)[:, None] for i in range(terms)]
        A = np.concatenate([np.stack([c[:, 0] for c in cols] + [np.ones(keep.sum()), np.zeros(keep.sum())], 1),
                            np.stack([c[:, 1] for c in cols] + [np.zeros(keep.sum()), np.ones(keep.sum())], 1)])
        rhs = np.concatenate([(pc[keep, 0] - pg[keep, 0]) / R, (pc[keep, 1] - pg[keep, 1]) / R])
        sol, *_ = np.linalg.lstsq(A, rhs, rcond=None)
        Q = (pg - centre) / R
        R2 = (Q ** 2).sum(1)
        g = sum(sol[i] * R2 ** i for i in range(terms))
        pred = pg + R * (Q * g[:, None] + sol[terms:terms + 2])
        res = np.linalg.norm(pred - pc, axis=1)
        keep = res < max(0.5, 3 * np.median(res[keep]))
    return sol[:terms], float(np.sqrt(np.mean(res[keep] ** 2))), int(keep.sum())


def measure_image(rgb, centre=None):
    h, w = rgb.shape[:2]
    centre = np.array([w / 2, h / 2]) if centre is None else centre
    R = np.hypot(w, h) / 2
    g = rgb[..., 1]
    out = {}
    for i, label in ((0, "red"), (2, "blue")):
        got = channel_pairs(g, rgb[..., i])
        if got is None:
            continue
        pg, pc = got
        coef, rms, n = radial_scale(pg, pc, centre, R)
        out[label] = (coef, rms, n)
    return out


def to8(img):
    if img.dtype == np.uint16:
        img = img.astype(np.float32) / 65535.0
        img = np.clip(img, 0, 1) ** (1 / 2.2)
        return (img * 255).round().astype(np.uint8)
    return img


def describe(label, result):
    for ch in ("red", "blue"):
        if ch not in result:
            continue
        coef, rms, n = result[ch]
        at = [sum(c * r ** (2 * i) for i, c in enumerate(coef)) * 1e4 for r in (0.25, 0.5, 0.75, 1.0)]
        print("  %-5s %-4s scale×10⁴ at r .25/.5/.75/1: %s  (n %d, rms %.3f px)" % (label, ch, np.round(at, 2).tolist(), n, rms))


if __name__ == "__main__":
    for path in sys.argv[1:]:
        print(path.split("/")[-1])
        with rawpy.imread(path) as raw:
            rgb = raw.postprocess(use_camera_wb=True, output_bps=16, user_flip=0, demosaic_algorithm=rawpy.DemosaicAlgorithm.AHD)
        describe("raw", measure_image(to8(rgb)))
        jpeg = measure.largest_jpeg(path, color=True)[0]
        describe("jpeg", measure_image(jpeg))
