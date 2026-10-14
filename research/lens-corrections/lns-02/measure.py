"""Measures how a camera's JPEG maps onto an uncorrected render of its raw (LNS-02 research).

Both images are put in coordinates normalised by their own half-diagonal about their centres.
SIFT matches give point pairs (q in the JPEG, p in the render); a radial model then says where
each JPEG point was recorded. Candidate conventions are scored by their RMS residual in render
pixels and by the framing scale they leave between the corrected render and the JPEG.
"""

import io
import json
import sys

import cv2
import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def largest_jpeg(path, color=False):
    data = open(path, "rb").read()
    found = []
    start = 0
    while True:
        i = data.find(b"\xff\xd8\xff", start)
        if i < 0:
            break
        start = i + 3
        try:
            im = Image.open(io.BytesIO(data[i:]))
            if im.format != "JPEG":
                continue
            found.append((im.size[0] * im.size[1], i))
        except Exception:
            continue
    for area, i in sorted(found, reverse=True):
        try:
            im = Image.open(io.BytesIO(data[i:]))
            im.load()
        except Exception:
            continue
        return np.asarray(im.convert("RGB" if color else "L")), im
    return None


def load_gray(path):
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if img is None:
        raise SystemExit("can't read " + path)
    if img.ndim == 3:
        img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.shape[2] == 3 else cv2.cvtColor(img, cv2.COLOR_BGRA2GRAY)
    if img.dtype == np.uint16:
        img = (img / 257.0).round().astype(np.uint8)
    return img


def resized(img, long_edge):
    h, w = img.shape[:2]
    scale = long_edge / max(h, w)
    if abs(scale - 1) < 1e-6:
        return img
    return cv2.resize(img, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)


def normalised(points, shape):
    h, w = shape[:2]
    centre = np.array([w / 2, h / 2])
    half = np.hypot(w, h) / 2
    return (points - centre) / half, half


def matches(jpeg, render, long_edge=3000):
    a = resized(jpeg, long_edge)
    b = resized(render, long_edge)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    a2, b2 = clahe.apply(a), clahe.apply(b)
    sift = cv2.SIFT_create(nfeatures=40000, contrastThreshold=0.01)
    ka, da = sift.detectAndCompute(a2, None)
    kb, db = sift.detectAndCompute(b2, None)
    if da is None or db is None:
        return None
    matcher = cv2.FlannBasedMatcher({"algorithm": 1, "trees": 5}, {"checks": 64})
    pairs = matcher.knnMatch(da, db, k=2)
    good = [m for m, n in (p for p in pairs if len(p) == 2) if m.distance < 0.8 * n.distance]
    pa = np.array([ka[m.queryIdx].pt for m in good])
    pb = np.array([kb[m.trainIdx].pt for m in good])
    qa, half_a = normalised(pa, a.shape)
    qb, half_b = normalised(pb, b.shape)
    return qa, qb, half_a, half_b, a.shape, b.shape


def fit_radial(qa, qb, half_b, terms=4, iterations=8, threshold=2.5):
    """qb ≈ centre + qa·s·g(|qa·s|), g a polynomial in ρ²; returns (coefficients, centre, inliers, rms px)."""
    keep = np.ones(len(qa), bool)
    # Start from a similarity on the central points, robust to distortion.
    rho = np.linalg.norm(qa, axis=1)
    central = rho < 0.45
    M, inl = cv2.estimateAffinePartial2D(qa[central], qb[central], ransacReprojThreshold=3 / half_b)
    if M is None:
        return None
    pred = qa @ M[:, :2].T + M[:, 2]
    keep = np.linalg.norm(pred - qb, axis=1) * half_b < 40
    coef = None
    for _ in range(iterations):
        x, y = qa[keep, 0], qa[keep, 1]
        r2 = x * x + y * y
        # Unknowns: c (powers of ρ² times qa), centre tx, ty, plus a small rotation term.
        cols = []
        for k in range(terms):
            cols.append(np.stack([x * r2 ** k, y * r2 ** k], 1))
        rot = np.stack([-y, x], 1)
        A = np.concatenate([np.stack([c[:, 0] for c in cols] + [rot[:, 0], np.ones_like(x), np.zeros_like(x)], 1),
                            np.stack([c[:, 1] for c in cols] + [rot[:, 1], np.zeros_like(x), np.ones_like(x)], 1)], 0)
        rhs = np.concatenate([qb[keep, 0], qb[keep, 1]])
        sol, *_ = np.linalg.lstsq(A, rhs, rcond=None)
        coef = sol
        X, Y = qa[:, 0], qa[:, 1]
        R2 = X * X + Y * Y
        g = sum(sol[k] * R2 ** k for k in range(terms))
        px = X * g - Y * sol[terms] + sol[terms + 1]
        py = Y * g + X * sol[terms] + sol[terms + 2]
        res = np.hypot(px - qb[:, 0], py - qb[:, 1]) * half_b
        new = res < max(threshold, np.median(res[keep]) * 3)
        if (new == keep).all():
            break
        keep = new
    rms = np.sqrt(np.mean(res[keep] ** 2))
    return coef, keep, rms, res


def profile(qa, qb, coef, terms, keep, bins=12):
    """Measured r/ρ against ρ (the JPEG's normalised radius), in bins, after removing the centre."""
    t = coef[terms + 1: terms + 3]
    rho = np.linalg.norm(qa[keep], axis=1)
    r = np.linalg.norm(qb[keep] - t, axis=1)
    edges = np.linspace(0.05, rho.max(), bins + 1)
    out = []
    for lo, hi in zip(edges, edges[1:]):
        sel = (rho >= lo) & (rho < hi)
        if sel.sum() >= 5:
            out.append((float(rho[sel].mean()), float(np.median(r[sel] / rho[sel])), int(sel.sum())))
    return out


if __name__ == "__main__":
    raw, render = sys.argv[1], sys.argv[2]
    jpeg, im = largest_jpeg(raw)
    rend = load_gray(render)
    print("jpeg", jpeg.shape, "render", rend.shape)
    got = matches(jpeg, rend)
    qa, qb, half_a, half_b, sa, sb = got
    print("matches", len(qa))
    fit = fit_radial(qa, qb, half_b)
    coef, keep, rms, res = fit
    print("inliers", keep.sum(), "rms px %.3f" % rms, "coef", np.round(coef, 6).tolist())
    for row in profile(qa, qb, coef, 4, keep):
        print("  rho %.3f  r/rho %.5f  n=%d" % row)
