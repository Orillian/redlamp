"""Shared conventions for the lens blur benchmark (OTH-03): paths, EXR I/O, the thin-lens camera."""

import json
import math
import os
import pathlib

import numpy as np

os.environ.setdefault("OPENCV_IO_ENABLE_OPENEXR", "1")

ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA = ROOT / "build/proto-data/lens_blur"
OUT = ROOT / "build/proto-out/lens_blur"
PHOTOS = ROOT / "build/mask-eval"
PHOTO_MANIFEST = ROOT / "research/mask-eval/manifest.json"

SENSOR_WIDTH_MM = 36.0
FOCUS_NAMES = ("subject", "background")


def write_exr(path, image):
    """RGB (H, W, 3) or single channel (H, W), float32, linear; ZIP-compressed."""
    import cv2
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    image = np.asarray(image, dtype=np.float32)
    if image.ndim == 3:
        image = image[..., ::-1]
    params = [cv2.IMWRITE_EXR_COMPRESSION, cv2.IMWRITE_EXR_COMPRESSION_ZIP]
    if not cv2.imwrite(str(path), np.ascontiguousarray(image), params):
        raise RuntimeError(f"couldn't write {path}")


def read_exr(path):
    import cv2
    image = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise FileNotFoundError(path)
    image = image.astype(np.float32)
    if image.ndim == 3:
        image = image[..., 2::-1] if image.shape[2] >= 3 else image[..., 0]
    return np.ascontiguousarray(image)


def srgb_to_linear(x):
    return np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(x):
    x = np.clip(x, 0, 1)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def save_preview(path, linear):
    from PIL import Image
    Image.fromarray((linear_to_srgb(linear) * 255 + 0.5).astype(np.uint8)).save(path)


def camera(focal_mm, f_number, focus_m, width, height, blades=0, rotation=0.0, ratio=1.0,
           sensor_width_mm=SENSOR_WIDTH_MM):
    """The thin-lens camera of one variant, as written to its JSON.

    The sensor sits at the image distance v = f s / (s - f), so focusing breathes: the pinhole
    image is the scene projected through the lens centre onto a sensor v behind it.
    """
    f = focal_mm
    s = focus_m * 1000
    v = f * s / (s - f)
    pitch = sensor_width_mm / width
    aperture = f / f_number
    # c_px = scale * |1/s - 1/z| with s and z in metres.
    scale = aperture * v * 1e-3 / pitch
    return {
        "image": {"width": width, "height": height},
        "focal_length_mm": f,
        "sensor_width_mm": sensor_width_mm,
        "sensor_height_mm": sensor_width_mm * height / width,
        "pixel_pitch_mm": pitch,
        "focus_distance_m": focus_m,
        "f_number": f_number,
        "aperture_diameter_mm": aperture,
        "image_distance_mm": v,
        "aperture": {"blades": blades, "rotation_rad": rotation, "ratio": ratio},
        "coc": {
            "formula": "c = f^2 / (N (s - f)) * |z - s| / z  (sensor mm); c_px = c / sensor_width * image_width",
            "disparity_form": "c_px = coc_px_per_inverse_metre * |1/s - 1/z|, s and z in metres",
            "coc_px_per_inverse_metre": scale,
            "signed": "c_signed_px = coc_px_per_inverse_metre * (1/z - 1/s): positive in front of focus",
        },
        "blender": {"lens_mm": v, "fstop": f_number * v / f, "sensor_width_mm": sensor_width_mm,
                    "sensor_fit": "HORIZONTAL"},
    }


def coc_px(cam, z):
    """Signed circle-of-confusion diameter in pixels for depth z in metres (array or scalar)."""
    return cam["coc"]["coc_px_per_inverse_metre"] * (1 / np.asarray(z, dtype=np.float64) - 1 / cam["focus_distance_m"])


def aperture_lattice(blades, rotation, ratio, n_side, angle=0.37):
    """Equal-weight points filling the unit aperture: a rotated square lattice clipped to the shape.

    Polygons are inscribed in the unit circle with vertices at rotation + pi/n + 2 pi k/n, as in
    Cycles; the anamorphic ratio squeezes x by 1/ratio. Lens-plane axes: x right, y up.
    """
    t = (np.arange(n_side) + 0.5) / n_side * 2 - 1
    x, y = np.meshgrid(t * math.sqrt(2), t * math.sqrt(2))
    c, s = math.cos(angle), math.sin(angle)
    u, w = c * x - s * y, s * x + c * y
    if blades == 0:
        inside = u * u + w * w <= 1
    else:
        inside = np.ones_like(u, dtype=bool)
        apothem = math.cos(math.pi / blades)
        for k in range(blades):
            mid = rotation + 2 * math.pi * k / blades
            inside &= u * math.cos(mid) + w * math.sin(mid) <= apothem
    points = np.stack([u[inside] / ratio, w[inside]], axis=1)
    return points.astype(np.float32)


def write_json(path, data):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1))


def variants(apertures=(1.4, 2.8, 5.6)):
    """(name, f_number, blades, rotation, ratio) for each aperture variant of a focus distance."""
    wide, mid, narrow = apertures
    return [
        (f"f{wide}-circle", wide, 0, 0.0, 1.0),
        (f"f{mid}-circle", mid, 0, 0.0, 1.0),
        (f"f{narrow}-circle", narrow, 0, 0.0, 1.0),
        (f"f{mid}-blade5", mid, 5, 0.0, 1.0),
        (f"f{mid}-blade7", mid, 7, 0.0, 1.0),
        (f"f{wide}-oval", wide, 0, 0.0, 1.6),
    ]
