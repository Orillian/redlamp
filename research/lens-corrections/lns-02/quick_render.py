"""An uncorrected render through LibRaw (rawpy), for quick geometry work: sRGB, 8-bit, EXIF-oriented."""

import sys

import cv2
import numpy as np
import rawpy


def render(path, out=None, half=False):
    with rawpy.imread(path) as raw:
        rgb = raw.postprocess(use_camera_wb=True, no_auto_bright=False, output_bps=8, half_size=half, user_flip=None)
        sizes = raw.sizes
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    if out:
        cv2.imwrite(out, bgr)
    return bgr, sizes


if __name__ == "__main__":
    img, sizes = render(sys.argv[1], sys.argv[2])
    print(img.shape, sizes)
