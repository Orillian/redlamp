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
| `blender_scenes.py render`, 8 scenes at 720x480, Cycles on Metal | 64 min: 19 min for 7 scenes (1 min 52 s to 3 min 52 s each, 7 to 23 s a render) and 45 min for the meadow, whose alpha-textured grass takes about 115 s a render and 12 min for a depth pass | 459 MB exported, 442 MB raw |
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
| `depth_estimate.py` | The depth bake-off's models on the benchmark's inputs (or on MSK-25 photos), raw output and timings |
| `depth_mattes.py` | Realistic subject mattes: ViTMatte-base from a trimap made from the true alpha |
| `depth_eval.py` | Refines, aligns and measures each raw estimate; writes `estimated/<label>/…/depth.exr` and `metrics.json` |
| `render_depth.py` | Renders the baseline on an estimated depth and scores it with `score.py` |
| `depth_report.py` | The bake-off's tables, from `metrics.json` and the renders' `score.json` |
| `depth_sheets.py` | Contact sheets of the depth maps, on the benchmark and on MSK-25 photos |
| `render_common.py` | The renderers' shared pieces: variant lists, aperture shapes and kernels, pull-push fill, the subject matte, light detection and clip recovery |
| `render_gather.py` | Per-pixel gather with scatter-as-gather weights, near and far fields; `--sprites`, `--matte`, `--clipped`, `--depth` |
| `render_layers.py` | Depth slices 1 px of CoC apart, blurred by FFT and composited: `--mode plain`, `fill` or `oracle` (`--matte coarse`); `--sprites`, `--clipped` |
| `apple_depth_blur.py`, `apple_depth_blur.swift` | Core Image's `CIDepthBlurEffect` as a reference, its aperture searched per variant against the truth |
| `metal/main.swift`, `metal/Gather.metal` | Standalone Metal harness for the gather: checks against the Python render, times it at editor and export sizes |
| `metal/fft_layer.swift` | Times one FFT layer of `render_layers.py` with MPSGraph |
| `metal_check.py` | The harness's check scene, and its output against the Python gather |
| `summarise.py` | Score tables for several renderers over the variants they share |
| `contact_sheets.py` | Crops of hair, foregrounds and lights for the truth and each renderer, into `docs/research/images/` |
| `run_renderers.sh` | Renders and scores every renderer configuration, in chains that run side by side |
| `bench_assets.py` | The Lightroom bench task's 20 assets in `build/proto-out/lens_blur/bench-assets/`: ten benchmark inputs as 16-bit sRGB TIFFs (clipped at white), four CC0 MSK-25 portraits, the iPhone ProRAW and Pixel raw fixtures, and four labelled copies of the night portrait for the bokeh shapes. The task is `oth-03-lens-blur-lightroom` (`redlamp task new --draft …/draft.json`) |

## Depth bake-off

Which depth model, input size, refinement and stored format a lens blur needs, measured on the two
sets' exact depth. Findings: section 11 of the
[OTH-03 note](../../../docs/research/notes/OTH-03-lens-blur.md#11-depth-for-lens-blur). The models run
in a venv of their own, since Depth Anything 3 and MoGe pin different packages:

```bash
uv venv --python 3.12 build/lens-blur-depth-venv
mkdir -p build/depth-src && cd build/depth-src
git clone --depth 1 https://github.com/ByteDance-Seed/Depth-Anything-3 da3
git clone --depth 1 https://github.com/microsoft/MoGe moge
cd ../..
VIRTUAL_ENV=build/lens-blur-depth-venv uv pip install torch==2.7.0 torchvision==0.22.0 "numpy<2.3" \
    opencv-python-headless OpenEXR scipy scikit-image pillow huggingface_hub safetensors einops omegaconf \
    addict imageio trimesh tqdm requests matplotlib "transformers==4.49.0" timm==0.9.1 click e3nn plyfile \
    pillow_heif moviepy==1.0.3 evo pycolmap typer gdown \
    "utils3d_moge @ git+https://github.com/EasternJournalist/utils3d-moge.git@62f09d58509485564e24d5d9f6aac9ee9ebc0c37"
VIRTUAL_ENV=build/lens-blur-depth-venv uv pip install --no-deps build/depth-src/da3 build/depth-src/moge
```

(MoGe's own dependencies include FlexGEMM, a CUDA library that its v3 needs and v2 doesn't, so MoGe is
installed without them.) Then, with `V=build/lens-blur-depth-venv/bin/python`,
`P=research/prototypes/lens_blur` and `PYTORCH_ENABLE_MPS_FALLBACK=1`:

```bash
$V $P/depth_estimate.py da3-mono-l@app da3-mono-l@2x moge2-b@2x …   # every <model>@<size>
$V $P/depth_mattes.py
$V $P/depth_eval.py moge2-b@2x --refine none,guided,app,wmf --align disparity,depth,map
$V $P/depth_eval.py moge2-b@2x --refine layers-oracle,layers-vitmatte [--base wmf]
$V $P/depth_eval.py moge2-b@2x --refine none --align pinned
$V $P/depth_eval.py moge2-b@2x --refine wmf --store 8:1536,16:1536,16:1536:wmf,…
build/research-venv/bin/python $P/render_depth.py truth moge2-b@2x+wmf …
build/research-venv/bin/python $P/depth_report.py metrics|renders [<label glob>…]
$V $P/depth_estimate.py da3-mono-l@app moge2-b@2x --photos hair-curly-01 …
$V $P/depth_sheets.py benchmark|photos
```

Estimated depths go to `build/proto-data/lens_blur/estimated/<label>/<set>/<scene>/<focus>/depth.exr`,
in metres after alignment, the truth's convention, so any renderer can read them in place of
`depth.exr`. A label is `<model>@<size>+<refinement>[/<base>][~<alignment>][#<bits>b<size>]`.

| Step | Time, with the load average beside it |
| --- | --- |
| `depth_estimate.py`, 14 sources on 40 inputs | 4 min (load 45 to 62); per photo, see the note's §11.6 |
| `depth_mattes.py`, 40 mattes at full size | 1 min (0.1 to 0.3 s a matte) |
| `depth_eval.py`, one source, 4 refinements, 3 alignments | 2.5 min (load 30 to 60); the weighted median takes 3 to 6 s an image |
| `render_depth.py`, one label (104 circular variants) and its score | 5 to 10 min (load 35 to 190) |
| `depth_sheets.py photos`, 12 photos, 4 combinations | 5 min (load 170) |

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
`baseline-gaussian-clipped` reads `input_clipped.exr` (scored on set A only).

| | Variants | PSNR | SSIM | LPIPS | Band PSNR | Band SSIM | Band LPIPS | Bleed dE2000 | Energy | Energy, lights > 1.0 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Set A, overall | 150 | 32.15 | 0.935 | 0.140 | 27.36 | 0.785 | 0.343 | 4.81 | 1.000 | 0.999 |
| Set A, focus on subject | 75 | 32.71 | 0.935 | 0.158 | 28.18 | 0.798 | 0.339 | 4.81 | 0.987 | 0.984 |
| Set A, focus on background | 75 | 31.60 | 0.936 | 0.123 | 26.54 | 0.771 | 0.348 | – | 1.000 | 1.000 |
| Set A, clipped input | 150 | 31.71 | 0.935 | 0.146 | 27.24 | 0.785 | 0.348 | 4.96 | 0.410 | 0.356 |
| Set B, overall | 64 | 35.83 | 0.944 | 0.152 | 33.13 | 0.927 | 0.159 | 1.10 | 1.002 | 1.002 |
| Set B, focus on subject | 32 | 33.62 | 0.934 | 0.192 | 31.06 | 0.919 | 0.195 | 1.10 | 1.006 | 1.006 |
| Set B, focus on background | 32 | 38.04 | 0.954 | 0.113 | 35.20 | 0.935 | 0.123 | – | 1.000 | 1.000 |

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

Per-scene rows are in `build/proto-out/lens_blur/baseline-gaussian/score.md`. Since the meadow was
exported, `baseline-gaussian-all` (links to the same outputs) scores set B's 64 variants: 35.83 dB,
band 33.13, bleeding 1.10.

## Renderers

Prototypes in PyTorch on MPS, written from the papers each names; the findings, scores and timings
are in section 10 of the [OTH-03 note](../../../docs/research/notes/OTH-03-lens-blur.md#10-renderers),
the contact sheets in `docs/research/images/lens-blur-renderers-*.jpg`.

```bash
P=research/prototypes/lens_blur
PY=build/research-venv/bin/python
$PY $P/render_gather.py [--sprites] [--matte exact|coarse] [--clipped] [--depth LABEL] [--circles] [--kappa 16] [--set S --scene S --focus F --variant V]
$PY $P/render_layers.py --mode plain|fill|oracle [--matte coarse] [--sprites] [--clipped] [--step 1.0]
$PY $P/score.py <renderer> [--set layered]
$PY $P/summarise.py baseline-gaussian-all gather layers-fill [--set layered] [--by focus|type|scene]
$PY $P/contact_sheets.py
```

Each writes `build/proto-out/lens_blur/<renderer>/`, the renderer's name built from its options
(`gather-sprites-clipped`, `layers-oracle-coarse`). `run_renderers.sh <chain>` runs a chain of them
and their scores; don't edit it while a chain runs, since `sh` reads the script as it goes. Start the
chains from a shell that stays open until they finish (`wait` on them): started with `nohup … &` from
an agent's shell that then exited, they were killed with it.

`--depth <label>` renders on one of the depth bake-off's estimates in place of the truth's depth,
into `gather…@<label>/`. The chains `depth_moge2_l`, `depth_moge2_b` and `depth_mono_l` render the
leading estimates this way, on the circular variants (`--circles`), about 25 minutes each side by side.

Core Image's depth blur, as a reference (set A only):

```bash
$PY $P/apple_depth_blur.py prep
swiftc -O $P/apple_depth_blur.swift -o build/proto-out/lens_blur/apple-depth-blur/apple_depth_blur
build/proto-out/lens_blur/apple-depth-blur/apple_depth_blur build/proto-out/lens_blur/apple-depth-blur/raw/jobs.json --grid
$PY $P/apple_depth_blur.py collect
$PY $P/score.py apple-depth-blur --set layered
```

Run it compiled: under `swift` its PSNR loop takes about 20 s a variant. The focus rectangle has to
be normalised to the image; in pixels the filter returns its input unchanged.

The Metal harness (nothing in it is linked into the app):

```bash
swiftc -O "$PWD/$P/metal/main.swift" -o build/proto-out/lens_blur/metal/gather   # absolute path: it finds Gather.metal beside it
swiftc -O "$PWD/$P/metal/fft_layer.swift" -o build/proto-out/lens_blur/metal/fft_layer
$PY $P/metal_check.py prep                    # portrait-leafy, subject, f/1.4
build/proto-out/lens_blur/metal/gather check build/proto-out/lens_blur/metal/check
$PY $P/metal_check.py compare
build/proto-out/lens_blur/metal/gather time build/proto-out/lens_blur/metal/check --kappa 16,0 --dense-max 30000
build/proto-out/lens_blur/metal/fft_layer
```

`gather check` renders one variant and writes it beside the Python render for `metal_check.py
compare`: on portrait-leafy, subject, f/1.4, Metal matches Python to 91.6 dB (largest difference
0.0022), and both score 30.73 dB against the truth.

### Timings

On this Mac (M1 Ultra, 48-core GPU, 128 GB), shared with other sessions. The Python prototypes,
for a whole run (set A at 1024×683 and set B at 720×480, file reading and writing included):

| Renderer | Variants | Wall time | Per variant | Load average (1 min) at start |
| --- | --- | --- | --- | --- |
| `gather` | 214 | 413 s | 1.9 s | 32.2 |
| `gather-matte-coarse` | 214 | 404 s | 1.9 s | 32.5 |
| `gather-sprites` | 214 | 875 s | 4.1 s | 28.2 |
| `layers-plain` | 214 | 487 s | 2.3 s | 31.3 |
| `layers-fill` | 214 | 366 s | 1.7 s | 41.1 |
| `layers-oracle` | 214 | 512 s | 2.4 s | 145.9 |
| `apple-depth-blur` (one `CIDepthBlurEffect` render) | 150 | 12.8 ms median | 19 renders a variant for the search | 33.4 |

Two or three of these ran at once on the GPU, so their times compare only roughly.

The Metal gather (`gather time`, at 0:51 with load average 11.1 at the start and 10.2 at the end,
nothing else of this session's on the GPU): the GPU time of one frame (`GPUStartTime` to
`GPUEndTime`, summed over its bands, the median of five runs after a warm-up, three at the two
largest sizes). The CoC is the largest circle of confusion's diameter, as a fraction of the long
edge; κ = 16 is the dense lattice out to 16 px and rings beyond, κ = 0 the dense lattice throughout
(timed up to 30,000 million pixel-samples). Memory is the frame's textures and buffers.

| Size | MP | CoC | Largest CoC | Samples (κ 16) | Gather, κ 16 | Samples (dense) | Gather, dense | Memory |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1280×800 | 1.0 | 2% | 26 px | 641 | 8.5 ms | 641 | 8.5 ms | 68 MB |
| 1280×800 | 1.0 | 4% | 51 px | 1,758 | 28.3 ms | 2,313 | 45.5 ms | 68 MB |
| 1500×1000 | 1.5 | 2% | 30 px | 861 | 17.4 ms | 861 | 17.5 ms | 102 MB |
| 1500×1000 | 1.5 | 4% | 60 px | 1,960 | 51.2 ms | 3,125 | 81.9 ms | 102 MB |
| 2560×1600 | 4.1 | 2% | 51 px | 1,758 | 100.7 ms | 2,313 | 131.4 ms | 269 MB |
| 2560×1600 | 4.1 | 4% | 102 px | 2,768 | 170.7 ms | – | – | 269 MB |
| 3000×2000 | 6.0 | 2% | 60 px | 1,960 | 164.0 ms | 3,125 | 250.3 ms | 399 MB |
| 3000×2000 | 6.0 | 4% | 120 px | 3,071 | 267.1 ms | – | – | 399 MB |
| 6000×4000 | 24.0 | 2% | 120 px | 3,071 | 904 ms | – | – | 1.6 GB |
| 6000×4000 | 24.0 | 4% | 240 px | 4,182 | 1,262 ms | – | – | 1.6 GB |
| 8064×6048 | 48.8 | 2% | 161 px | 3,576 | 2,091 ms | – | – | 3.2 GB |
| 8064×6048 | 48.8 | 4% | 323 px | 4,687 | 2,828 ms | – | – | 3.2 GB |
| 11648×8736 | 101.8 | 2% | 233 px | 4,182 | 5,001 ms | – | – | 6.7 GB |
| 11648×8736 | 101.8 | 4% | 466 px | 5,293 | 6,512 ms | – | – | 6.7 GB |

The gather runs at about 12 to 14 ps per pixel-sample at every size. The dense lattice's samples
grow with CoC²; from 2% to 4% at 1280×800 (CoC² ×4) they grow ×3.6 and its time ×5.4, since wider
samples miss the cache more often. With rings beyond 16 px the samples grow with the radius's
logarithm: ×2.7 and ×3.3 over the same step, and ×1.3 to ×1.4 from 2% to 4% at the largest sizes.

One layer of `render_layers.py` by FFT (`fft_layer`, at 0:54 with load average 8.3 at the start and
8.1 at the end): four channels forward and back, padded by the largest CoC to a size with no prime
factor over 5 (a factor of 43 made one size three times slower), wall time from encoding to
completion, the median of five runs after a warm-up; two runs agreed within 0.5 ms.

| Size | Padded (2%) | Layer, 2% | Layer, 4% | Memory |
| --- | --- | --- | --- | --- |
| 2560×1600 | 2880×1728 | 5.1 ms | 5.0 ms | 323 MB |
| 3000×2000 | 3072×2304 | 7.6 ms | 8.2 ms | 459 MB |
| 6000×4000 | 6144×4608 | 43.7 ms | 45.4 ms | 1.8 GB |
| 8064×6048 | 8640×6400 | 53.7 ms | 53.9 ms | 3.6 GB |
| 11648×8736 | 12288×9216 | 155.8 ms | 153.0 ms | 7.3 GB |

A frame takes one layer per pixel of CoC its depth spans, plus a one-channel transform of each
layer's kernel. A frame blurred only behind focus up to the largest CoC takes that many layers: 120
at 3000×2000 and 4% (about 1 s), 240 at 6000×4000 and 4% (about 11 s); one blurred as much in front
of focus takes twice as many.

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
