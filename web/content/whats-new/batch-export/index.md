---
version: 0.3.2-alpha
date: 2026-10-15
symbol: square.and.arrow.up.on.square
title: Export several photos at once
summary: Export… works on every photo selected, in the background, naming files from templates.
image: export.jpg
imageAlt: The Export dialog titled Export 5 Photos, naming the files with the Custom Name - Sequence template, {text}-{sequence}, with Samples as its custom text, so it saves Samples-1.jpg and 4 more beside the originals and asks if a file exists
---

Select several photos in the filmstrip or the grid and choose Export… or Export with Previous: the dialog says how many. Files are named by the templates Rename Photos and Import use, numbered in the filmstrip's order. A photo already in the folder is never replaced; for earlier exports, Ask asks once for the whole batch, and Skip leaves them as they are.

The photos render one at a time in the background, with progress and Cancel in the filmstrip. On the command line, `redlamp export` exports several photos the same way.
