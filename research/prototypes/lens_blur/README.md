# Lens blur benchmark (OTH-03, #138)

Exact truth for synthetic shallow depth of field rendered from one photo and its depth map. Two sets
of scenes, each giving a renderer what it gets in the app (an all-in-focus image and a depth map)
and the thin-lens image it should produce, plus a scorer and a naive baseline that sets the floor.
Nothing here ships; Blender is used only as a tool to render data.

## Setup

The research environment (`research/prototypes/README.md`) plus three packages:

```bash
uv venv --python python3.12 build/research-venv        # if it doesn't exist yet
VIRTUAL_ENV=build/research-venv uv pip install -r research/prototypes/requirements.txt
VIRTUAL_ENV=build/research-venv uv pip install lpips OpenEXR scikit-image scipy
```

Blender's Python module needs Python 3.11 and numpy below 2, so it has its own environment:

```bash
uv venv --python 3.11 build/lens-blur-bpy-venv
VIRTUAL_ENV=build/lens-blur-bpy-venv uv pip install --link-mode=copy bpy "numpy==1.26.4"
```

That installs bpy 5.0.1 (218 MB); Cycles renders on the Metal GPU. bpy prints
`numpy.core.multiarray failed to import` on import, from an optional module; rendering is unaffected.

## Run

```bash
P=research/prototypes/lens_blur
build/research-venv/bin/python $P/layered_truth.py            # 12 scenes, 144 variants
build/research-venv/bin/python $P/layered_truth.py --2x       # 3 scenes at 2048x1366, 6 variants
build/research-venv/bin/python $P/layered_truth.py --check    # the tracer against an analytic disc
build/research-venv/bin/python $P/fetch_polyhaven.py          # the CC0 assets for the Blender scenes
build/lens-blur-bpy-venv/bin/python $P/blender_scenes.py render   # raw multilayer EXRs
build/research-venv/bin/python $P/blender_scenes.py export        # into the shared layout
build/research-venv/bin/python $P/baseline_gaussian.py [--clipped]
build/research-venv/bin/python $P/score.py baseline-gaussian [--set layered|blender]
```

`blender_scenes.py render --quick <scene>` renders one low-sample variant into `blender-quick/` to
check a scene's build.

| Step | Time (M1 Ultra) | Size |
| --- | --- | --- |
| `layered_truth.py`, 12 scenes at 1024x683, PyTorch on MPS | 5 min 51 s | 2.4 GB with the 2x scenes |
| `layered_truth.py --2x`, 3 scenes at 2048x1366 | 2 min 45 s | (included above) |
| `fetch_polyhaven.py` | about 1 min | 172 MB |
| `blender_scenes.py render`, 8 scenes at 720x480, Cycles on Metal | 19 min for the first 7 scenes (1 min 52 s to 3 min 52 s each, 7 to 23 s a render); the meadow's alpha-textured grass takes about 115 s a render, about 25 min in all | 386 MB exported, 413 MB raw (7 scenes) |
| `baseline_gaussian.py`, all variants | 58 s for the layered set alone; 9 min 30 s for all 206 while Cycles rendered | 1.5 GB, and 1.2 GB for `--clipped` (layered only) |
| `score.py`, all variants with LPIPS on MPS | about 3 min | |

## Scripts

| Script | What it does |
| --- | --- |
| `common.py` | Paths, EXR reading and writing, the camera record (`camera()`), the signed CoC (`coc_px()`), the aperture lattice and the variant list |
| `layered_truth.py` | Set A: fronto-parallel RGBA layers at known depths, ray traced through a thin lens |
| `fetch_polyhaven.py` | Downloads the Poly Haven HDRIs, textures and models and records their authors in `polyhaven/assets.json` |
| `blender_scenes.py` | Set B: 3D scenes in bpy, rendered with Cycles' thin-lens camera; `render` then `export` |
| `baseline_gaussian.py` | The floor: a per-pixel Gaussian whose sigma is the exact CoC / 4, no occlusion handling |
| `score.py` | PSNR, SSIM, LPIPS, the same in the edge band, colour bleeding and light energy; `score.json` and `score.md` |

## Set A: layered scenes (`layered/`)

Each scene is a stack of planes, nearest first: sometimes a foreground (a leafy branch, grass blades or
a post) that partly covers the subject; the subject with soft alpha; sometimes a mid layer (a bush, a
fence, a bare tree, posts with string lights, a striped panel); and an opaque background, a CC0 photo
from the MSK-25 set (`build/mask-eval/`, `mise run maskeval`) or, in `portrait-stripes`, procedural
stripes, checks and gradients. Subjects are head and shoulders with about 1,400 hair strands and
flyaway wisps (0.15 to 2.2 px wide, three of them backlit or striped), a cat with fur along its edge and
whiskers, a dandelion seed head of 700 filaments with pappus tips (0.18 to 0.45 px), and plants with
fine stem hairs. Coverage is drawn at 4x supersampling and averaged, as `masking/edge_bench.py` draws
twigs; strands under a quarter of a supersample wide are drawn one supersample wide at proportional
opacity. Point lights are discs 0.5 to 2.5 px in radius: `bright` lights are 2 to 60 (log-uniform),
`glints` 3 to 60, `dim` lights 0.55 to 0.95 (below the clip, so the clipped input keeps their energy),
and the string lights 9 (warm). `plant-snow` has none.

| Scene | Focal length | Planes, near to far (m) |
| --- | --- | --- |
| `portrait-leafy` | 85 mm | portrait 2.5, photo 30 + 14 lights |
| `portrait-night` | 85 mm | backlit portrait 2.0, night photo 60 + 40 lights |
| `portrait-fg-leaves` | 85 mm | branch 1.1, portrait 2.5, bush 8, foggy forest 40 + 10 lights |
| `dandelion-sea` | 85 mm | grass 0.8, dandelion 1.5, sea 50 + 30 glints |
| `plant-sunset` | 50 mm | plant 1.2, bush 6, sunset 80 + 12 lights |
| `cat-overcast` | 85 mm | post 1.5, cat 3.0, fence 6, castle 30 + 12 dim lights |
| `portrait-city` | 50 mm | portrait 2.0, posts and 26 string lights 10, glass building 40 + 8 lights |
| `plant-snow` | 35 mm | plant 1.0, bare trees 15, mountains 200 |
| `dandelion-night` | 85 mm | backlit dandelion 1.8, station at blue hour 40 + 50 lights |
| `cat-leafy` | 135 mm | branch 3.0, cat 5.0, lime tree 25 + 16 dim lights |
| `portrait-horizon` | 35 mm | branch 0.7, portrait 1.5, bush 5, morning field 100 + 10 lights |
| `portrait-stripes` | 50 mm | portrait in a striped shirt 2.0, striped panel 5, procedural 20 + a grid of 24 lights |

Each scene is focused on the subject and on the background, and each focus has six variants:
f/1.4, f/2.8 and f/5.6 with a circular aperture, f/2.8 with 5 and with 7 blades, and f/1.4 with an
anamorphic oval (ratio 1.6). `portrait-leafy`, `portrait-fg-leaves` and `cat-overcast` also come at
2x (2048x1366, `<scene>@2x`) at f/2.8 with a circle, for scale checks: the same planes, photos and
noise at twice the resolution, except the cat's fur strands, which are placed afresh.

**The trace.** For a pixel p and a lens point a in the unit aperture, the ray meets the plane at depth
z where that plane's pinhole image is at p + a c(z)/2, c being the signed CoC in pixels (below). Every
ray samples every plane there, bilinearly on premultiplied RGBA, composites them front to back by
alpha and stops at the opaque background; the pixel is the mean over an equal-weight lattice of lens
points (a square lattice rotated by 0.37 rad, clipped to the aperture shape) whose spacing on the
most blurred plane is at most 1 px: 76 to 25,688 points per pixel. This is exact for planar layers,
including partial occlusion by a blurred foreground. `--check` traces a single bright texel 20 m away
with focus at 2 m: it keeps its energy to 1 part in 10^5, and its disc's second moment is within 0.9%
of a uniform disc of the formula's diameter (the texel's own bilinear footprint is the difference).

**What a renderer gets.** The pinhole image (a = 0) is `input.exr`; the per-pixel depth a renderer
sees is the alpha-weighted mean of the plane depths along the pinhole ray, w_i = alpha_i x prod over
nearer planes of (1 - alpha_j), so hair and soft edges get a depth between the subject's and the
background's (`depth.exr`). `depth_nearest.exr` is the depth of the plane with the largest weight,
and `layers.npz` holds every plane's premultiplied RGBA through the pinhole (float16, nearest first)
with their depths, for renderers that want the exact layers.

## Set B: Blender scenes (`blender/`)

Eight scenes with continuous depth, built in bpy from Poly Haven's CC0 assets and primitives:

| Scene | What's in it | Focus (m) |
| --- | --- | --- |
| `cobble-path` | low camera over a receding cobblestone ground, a dandelion, ferns, shrubs, 14 lights to 60 m, birch wood HDRI | 1.5, 25 |
| `brick-wall` | a brick wall slanted at 62 degrees from 2.4 to 12 m across the frame, a potted plant, 18 lights along the wall | 2.2, 12 |
| `trunk-forest` | 45 bark-textured trunks from 3.5 to 55 m, forest-floor leaves, a fern, a nettle near the lens, 10 lights | 1.8, 15 |
| `night-street` | cobblestones, 10 street lamps with lights to 39 m, 40 window lights to 120 m, a shrub, night HDRI | 3.0, 20 |
| `foliage-layers` | shrubs at 0.9 m either side, a nettle at 2 m, 30 plants from 4 to 12 m, 8 lights | 2.0, 8 |
| `tabletop` | a plank table receding from the lens, cups, an orange, a chrome ball, a brick wall at 5 m with 24 small lights | 0.7, 4.9 |
| `spheres-grid` | a checker ground, 30 noise-textured spheres to 30 m, a slanted panel, a sun, 20 lights, gradient sky | 2.0, 20 |
| `meadow` | 110 grass clumps from 0.8 to 25 m, dandelions, 10 lights, alpine HDRI | 1.2, 15 |

Each focus has four variants: f/1.8 and f/4.0, with a circular aperture and with 5 blades (rotation 0).
The camera is 50 mm on a 36 mm sensor. HDRIs light the scene through the world and are shown to the
camera on an emissive sphere 400 m away, so every pixel has a finite depth. Lights are emissive spheres
1.2 to 25 cm in radius with radiance 20 to 500.

**The thin lens in Cycles.** A lens of focal length f focused at s is a pinhole camera with its sensor
v = f s / (s - f) behind it and an aperture f/N. So each variant sets Blender's lens to v and its
f-stop to N v / f (Cycles' aperture radius is lens / (2 f-stop) = f / (2N)); the JSON records both
under `blender`. Cycles focuses on the plane at distance s along the view axis, so the CoC formula
below holds exactly, with the same breathing as set A. Checked on the renders: over the 22 isolated
lights of `night-street` (dark background) at f/1.8, the measured disc's second moment matches a
uniform disc of the formula's CoC convolved with the light's own image and the box pixel to a
median of 1.010 in sigma (interquartile 1.003 to 1.022), and the disc centres sit 0.04 px from the
lights' projected positions. On textured backgrounds the background subtraction is rougher (1.03 to
1.10).

**Renders.** Box pixel filter 1 px wide, no denoising, no clamping, 4 bounces (2 diffuse, 2 glossy),
adaptive sampling to a noise threshold of 0.01 with at most 256 samples per pixel, for the input and
the DOF renders alike. The truth therefore carries Monte Carlo noise, which caps the PSNR a perfect
renderer can reach on this set; set A has none. The subject alpha is a render with everything but
the subject held out and a transparent film, so it is the subject's visible coverage. Blender 5.0's
still renders don't save the Z pass to the EXR, so depth is its own render: every material's surface
becomes an emission of Camera Data's View Z Depth, mixed with transparency by the material's alpha,
at 32 samples with the same box filter. A pixel's depth is thus its coverage-weighted mean planar
depth, the same convention as set A's `depth.exr`.

The Blender set was planned at 960x640 and up to 2,048 samples; at that budget the meadow took 32 s at
64 samples, so it was cut to 720x480 and 256 samples to fit the session.

## Data layout

```
build/proto-data/lens_blur/
  layered/<scene>/scene.json                planes, depths, lights in reference coordinates, timings
  layered/<scene>/<focus>/                  focus = subject | background
      input.exr  input_clipped.exr          all-in-focus pinhole image, linear; the same clipped at 1.0
      depth.exr  depth_nearest.exr          metres
      alpha.exr  occluder.exr               subject alpha through the pinhole; coverage by nearer planes
      layers.npz                            per-plane premultiplied RGBA and depths
      <variant>.exr  <variant>.json  <variant>.png    truth, camera, sRGB preview
  blender/<scene>/scene.json
  blender/<scene>/<focus>/                  input, input_clipped, depth, alpha, <variant>.{exr,json,png}
  blender-raw/<scene>/                      Cycles' multilayer EXRs and render.json (timings, lights)
  polyhaven/                                the downloaded assets and assets.json
build/proto-out/lens_blur/<renderer>/<set>/<scene>/<focus>/<variant>.exr   a renderer's output
build/proto-out/lens_blur/<renderer>/score.json, score.md
```

Variants are named `f<N>-<shape>`: `circle`, `blade5`, `blade7`, `oval`.

## Conventions

- **Light.** Linear Rec.709 primaries, scene-referred, not clipped: lights go well above 1.0.
  `input_clipped.exr` is what a photo would hold; a renderer says which input it used.
- **Files.** EXR, float32, ZIP; RGB images have three channels, depth and alpha one. PNGs are
  previews only (sRGB, clipped).
- **Pixels.** Row 0 is the top. Pixel (i, j) has its centre at (i + 0.5, j + 0.5); set A samples at
  pixel centres, set B integrates over each pixel (box filter). Light positions in the JSON are
  continuous pixel coordinates on that grid.
- **Depth.** Planar distance from the lens plane along the optical axis, in metres, never radial.
  At soft edges it is the coverage-weighted mean of what the pixel sees.
- **Breathing.** The sensor sits at the image distance v, so the pinhole image depends on the focus
  distance: each focus has its own input, depth and alpha, shared by its variants.
- **Aperture.** Lens-plane axes x right, y up. Polygons are inscribed in the aperture circle of
  diameter f/N, with vertices at rotation + pi/n + 2 pi k / n (Cycles' convention; at rotation 0 they
  are symmetric about the x axis). The oval squeezes x by 1/ratio. Behind the focus plane a light's
  disc has the aperture's orientation; in front of it, the disc is rotated by 180 degrees.

## The camera JSON and the CoC

Each `<variant>.json` holds the image size, focal length f (mm), sensor width (mm) and pixel pitch,
focus distance s (m), f-number N, aperture diameter f/N, image distance v, aperture shape (blades,
rotation in radians, ratio), the Blender settings, the depth convention, the lights (centre, radius,
depth, CoC and radiance) and the sample count. The CoC diameter on the sensor is

    c = f^2 / (N (s - f)) * |z - s| / z          (f, s, z in the same units)
    c_px = c / sensor_width * image_width

for a point at depth z. It is linear in disparity:

    c = A f s / (s - f) * |1/s - 1/z|,   A = f / N

so a relative disparity map suffices up to scale, and the JSON gives the scale directly as
`coc.coc_px_per_inverse_metre`: c_px = K |1/s - 1/z| with s and z in metres. The signed form,
K (1/z - 1/s), is positive in front of the focus plane. `common.coc_px(cam, z)` computes it.

## Scoring

`score.py <renderer>` scores every variant it finds an output for, per variant, per scene, per focus
and overall for each set:

- **PSNR, SSIM, LPIPS** after a fixed tone map: extended Reinhard per channel with a white point of
  16, t(x) = x (1 + x/256) / (1 + x), then the sRGB transfer function. LPIPS is AlexNet
  (`lpips` 0.1.4; its weights come with the package and torchvision fetches AlexNet's).
- **Edge band**: the same three within 16 px of a depth discontinuity in the truth depth, where
  neighbours in a 3x3 window differ by more than 10% in depth.
- **Colour bleeding** (focus on the subject): mean CIE dE2000 between output and truth, tone mapped,
  2 to 8 px outside the subject's edge (alpha above 0.5 dilated by 8 px, less alpha above 0.02
  dilated by 2 px), where nothing nearer covers it.
- **Light energy**: for each clean point light, the Rec.709 luminance summed over its truth disc
  (CoC/2 + its radius + 1.5 px) in the output over the same in the truth; the median over lights, and
  separately over lights above 1.0 (clipped in `input_clipped.exr`) and at or below it. A light is
  clean when its disc is inside the frame, the pinhole sees it, no other light's disc overlaps it,
  and no nearer content (depth under 80% of the light's) lies within the disc's radius plus half
  that content's CoC. The disc includes the background around the light.

## Baseline scores (`baseline-gaussian`)

The first entry, to show the scorer works and give a floor. `baseline-gaussian` reads `input.exr`;
`baseline-gaussian-clipped` reads `input_clipped.exr` (scored on set A only). Set B covers the 7
scenes finished when this was written (56 variants); the meadow was still rendering.

| | Variants | PSNR | SSIM | LPIPS | Band PSNR | Band SSIM | Band LPIPS | Bleed dE2000 | Energy | Energy, lights > 1.0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Set A, overall | 150 | 32.15 | 0.935 | 0.140 | 27.36 | 0.785 | 0.343 | 4.81 | 1.000 | 0.999 |
| Set A, focus on subject | 75 | 32.71 | 0.935 | 0.158 | 28.18 | 0.798 | 0.339 | 4.81 | 0.987 | 0.984 |
| Set A, focus on background | 75 | 31.60 | 0.936 | 0.123 | 26.54 | 0.771 | 0.348 | – | 1.000 | 1.000 |
| Set A, clipped input | 150 | 31.71 | 0.935 | 0.146 | 27.24 | 0.785 | 0.348 | 4.96 | 0.410 | 0.356 |
| Set B, overall | 56 | 36.08 | 0.945 | 0.147 | 33.43 | 0.932 | 0.148 | 1.07 | 1.002 | 1.002 |
| Set B, focus on subject | 28 | 33.78 | 0.933 | 0.193 | 31.32 | 0.922 | 0.191 | 1.07 | 1.006 | 1.006 |
| Set B, focus on background | 28 | 38.39 | 0.957 | 0.100 | 35.55 | 0.941 | 0.105 | – | 1.000 | 1.000 |

What they show:

- **Edges are where it fails.** Near depth discontinuities set A loses 4.8 dB, SSIM falls from 0.935
  to 0.785 and LPIPS more than doubles; the worst scenes are the night ones, `portrait-night` (band
  PSNR 19.6, LPIPS 0.69) and `dandelion-night` (19.7, 0.70), where bright bokeh meets fine hair.
- **Colour bleeds.** With focus on the subject the blurred background takes the subject's colour,
  dE2000 4.8 on average over set A and 14.2 in `portrait-night`, against 1.1 in set B, whose
  subjects are smaller and darker.
- **Energy is kept when the input isn't clipped**: a Gaussian is a normalised linear blur, so the
  ratio is about 1 (the 1.5% shortfall with focus on the subject is the Gaussian's tail outside the
  disc). From the clipped input, lights above 1.0 keep 36% of their energy (29% when in focus, 56%
  when blurred), which is what a highlight-recovery step has to win back.
- Set B's higher scores come from its 50 mm lens and smaller CoCs (up to about 50 px against 181 in
  set A) and from its noise, which a blur averages away on both sides.

Per-scene rows are in `build/proto-out/lens_blur/baseline-gaussian/score.md`.

## Licences

All assets are CC0 1.0. CC0 covers copyright, not the people in the photos: two backgrounds show
small figures (a hiker, people at a station), and like the rest of MSK-25 these are for evaluation only.

Background photos (Wikimedia Commons, via the MSK-25 set, `research/mask-eval/manifest.json`):

| File | Commons page | Author | Licence |
| --- | --- | --- | --- |
| `sky-bright-horizon-02.jpg` | [Landscape-tree-morning-sun (23957218509).jpg](https://commons.wikimedia.org/wiki/File:Landscape-tree-morning-sun_(23957218509).jpg) | www.Pixel.la Free Stock Photos | CC0-1.0 |
| `sky-glass-01.jpg` | [Window reflection cn tower (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Window_reflection_cn_tower_(Unsplash).jpg) | Nadine Shaabana | CC0-1.0 |
| `sky-haze-fog-02.jpg` | [Forest in Rheinsberg with mist 2021-10-30 33.jpg](https://commons.wikimedia.org/wiki/File:Forest_in_Rheinsberg_with_mist_2021-10-30_33.jpg) | Leonhard Lenz | CC0-1.0 |
| `sky-leafy-trees-02.jpg` | [Joshua Tree National Park - 51758575850.jpg](https://commons.wikimedia.org/wiki/File:Joshua_Tree_National_Park_-_51758575850.jpg) | StephenGA | CC0-1.0 |
| `sky-leafy-trees-05.jpg` | [Tilia Levenstorf 2021-09-07 02.jpg](https://commons.wikimedia.org/wiki/File:Tilia_Levenstorf_2021-09-07_02.jpg) | Leonhard Lenz | CC0-1.0 |
| `sky-night-01.jpg` | [Altocumulus and Stratocumulus at dusk Lavender Blvd Ballina NSW L1020554.jpg](https://commons.wikimedia.org/wiki/File:Altocumulus_and_Stratocumulus_at_dusk_Lavender_Blvd_Ballina_NSW_L1020554.jpg) | John Robert McPherson | CC0-1.0 |
| `sky-night-02.jpg` | [Helsingin päärautatieasema at blue hour 2022-09-17 01.jpg](https://commons.wikimedia.org/wiki/File:Helsingin_p%C3%A4%C3%A4rautatieasema_at_blue_hour_2022-09-17_01.jpg) | Leonhard Lenz | CC0-1.0 |
| `sky-overcast-01.jpg` | [Burg Mauterndorf against a cloudy sky, Mauterndorf, 2023.jpg](https://commons.wikimedia.org/wiki/File:Burg_Mauterndorf_against_a_cloudy_sky,_Mauterndorf,_2023.jpg) | DimiTalen | CC0-1.0 |
| `sky-sea-01.jpg` | [Skyline by the sea on a cloudy day (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Skyline_by_the_sea_on_a_cloudy_day_(Unsplash).jpg) | Layton Diament | CC0-1.0 |
| `sky-snow-mountains-01.jpg` | [Snow covered mountains with hiker (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Snow_covered_mountains_with_hiker_(Unsplash).jpg) | Vashishtha Jogi | CC0-1.0 |
| `sky-sunset-02.jpg` | [Tree silhouette sunset. (Unsplash).jpg](https://commons.wikimedia.org/wiki/File:Tree_silhouette_sunset._(Unsplash).jpg) | Jagyasini Malakar | CC0-1.0 |

Poly Haven assets ([polyhaven.com](https://polyhaven.com/license), via its public API; HDRIs at 4k,
textures at 2k, models at 1k):

| Kind | Asset | Authors | Licence |
| --- | --- | --- | --- |
| HDRI | [Birchwood](https://polyhaven.com/a/birchwood) | Sergej Majboroda | CC0-1.0 |
| HDRI | [Cobblestone Street Night](https://polyhaven.com/a/cobblestone_street_night) | Greg Zaal, Jenelle van Heerden | CC0-1.0 |
| HDRI | [Alps Field](https://polyhaven.com/a/alps_field) | Andreas Mischok | CC0-1.0 |
| HDRI | [Autumn Forest 04](https://polyhaven.com/a/autumn_forest_04) | Alexander Scholten | CC0-1.0 |
| Texture | [Cobblestone Floor 01](https://polyhaven.com/a/cobblestone_floor_01) | Rob Tuytel | CC0-1.0 |
| Texture | [Forest Leaves 02](https://polyhaven.com/a/forest_leaves_02) | Rob Tuytel | CC0-1.0 |
| Texture | [Bark Brown 02](https://polyhaven.com/a/bark_brown_02) | Rob Tuytel | CC0-1.0 |
| Texture | [Brick Wall 001](https://polyhaven.com/a/brick_wall_001) | Rob Tuytel, Dimitrios Savva | CC0-1.0 |
| Texture | [Brown Planks 03](https://polyhaven.com/a/brown_planks_03) | Rob Tuytel | CC0-1.0 |
| Texture | [Leafy Grass](https://polyhaven.com/a/leafy_grass) | Charlotte Baglioni | CC0-1.0 |
| Model | [Dandelion 01](https://polyhaven.com/a/dandelion_01) | Rob Tuytel, Rico Cilliers | CC0-1.0 |
| Model | [Fern 02](https://polyhaven.com/a/fern_02) | Rob Tuytel, Rico Cilliers | CC0-1.0 |
| Model | [Potted Plant 04](https://polyhaven.com/a/potted_plant_04) | James Ray Cock | CC0-1.0 |
| Model | [Shrub 02](https://polyhaven.com/a/shrub_02) | Rico Cilliers | CC0-1.0 |
| Model | [Nettle Plant](https://polyhaven.com/a/nettle_plant) | Rob Tuytel, Rico Cilliers | CC0-1.0 |
| Model | [Grass Medium 01](https://polyhaven.com/a/grass_medium_01) | Rob Tuytel, Rico Cilliers | CC0-1.0 |
| Model | [Street Lamp 01](https://polyhaven.com/a/street_lamp_01) | Josh Dean | CC0-1.0 |

Tools: Blender 5.0.1 (`bpy` from PyPI, GPL-2.0-or-later) renders set B and nothing of it ships or is
linked; LPIPS (BSD-2-Clause) and its AlexNet weights score. The procedural content is this
repository's own.
