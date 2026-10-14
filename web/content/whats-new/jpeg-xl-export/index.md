---
version: 0.3.1-alpha
date: 2026-10-13
symbol: square.and.arrow.up
title: Export JPEG XL
summary: The Export dialog writes JPEG XL, lossy or lossless, in 8 or 16 bits.
image: export.jpg
imageAlt: The Export dialog saving DJI_FC4382-redlamp.jxl, with JPEG XL chosen as its format, a quality of 90, 16-bit and Display P3, above its note that macOS, Safari and Chrome read the files
---

JPEG XL is in the Export dialog's Format menu twice: under Lossy, and under Lossless, which keeps every pixel. Either writes 8 or 16 bits, in sRGB or Display P3, with the same metadata and embedded edit as the other formats.

On the command line, `redlamp render` writes JPEG XL when the output's name ends in `.jxl`. macOS reads the files, and so do Safari and Chrome 155.
