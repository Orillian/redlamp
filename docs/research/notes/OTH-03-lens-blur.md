# OTH-03: Lens blur

What it would take for Redlamp to have a lens blur (synthetic shallow depth of field from one photo and its depth) that does what Lightroom's Lens Blur does and more, especially on phone photos. Tracker row OTH-03, issue [#138](https://github.com/pdcgomes/redlamp/issues/138). Started 13 October 2026.

This note holds the desk study (sections 0 to 7). The measurements follow it as they're made: the exact-truth benchmark, the renderers, the depth bake-off, the iPhone's files and the comparison with Lightroom. The fetched pages and scripts the desk study drew on were working material and are not kept.

Builds on [C-masking §4](C-masking.md#4-depth-depth-range-mask-and-lens-blur) and [F-other §1](F-other.md#1-lens-blur-synthetic-depth-of-field-with-bokeh-shapes) (September 2026), which it does not repeat. Licences were read on 2026-10-13 from the primary sources named inline (`gh api repos/<owner>/<repo>/license`, the repository README, the Hugging Face API's `cardData.license`). Verdicts follow [`_conventions.md`](_conventions.md); a second column applies the owner's rule DEC-24 (follow the weights' licence; never ship a model trained directly on Places2). Anything not confirmed from a source in this session is marked **UNVERIFIED**.

## 0. Desk study: findings that bear on decisions

1. **Lightroom's XMP stores settings, not the depth.** `crs:LensBlur` holds 17 fields plus `ImageOrientation`; `crs:DepthMapInfo` holds only digests and version numbers of three cached products (raw depth, *layered* depth and a *highlight guide*); refinement brush strokes have their own list, `crs:DepthBasedCorrections`. A Lightroom edit can be imported as settings, but its depth must be regenerated, as Lightroom itself does when it asks to "update AI settings".
2. **Adobe's renderer matches three Adobe patent filings,** one of them now granted: US12586163B2 (granted 24 March 2026, adjusted expiry 16 April 2044) claims refining a *layered* depth map against a focal matte, by focus range and correction mode. That is close to Lightroom's Focus and Blur brushes that "adapt to later Focus Range changes". Redlamp's refinement design should go to counsel (DEC-05) before it is built.
3. **The depth model to evaluate first is MoGe-2 ViT-S or ViT-B (MIT weights, no Places in its paper), then Depth Anything 3 Small and Base (Apache-2.0).** Depth Anything 3 Mono-L, which Redlamp already ships, trains its student on unlabeled images "following the DA2 framework", without naming them. Depth Anything V2's unlabeled set includes Places365, so Mono-L is probably trained directly on Places365 (**UNVERIFIED**). It ships under the DEC-02 exception, so nothing changes now, but the exception covers more than its record says. Pixel-Perfect Depth (Apache-2.0) is the edge-quality reference, at diffusion cost.
4. **No bokeh dataset with real photographs is cleanly usable for evaluation.** EBB! states no licence; RealBokeh is CC BY-NC-SA 4.0 ("only permitted for non-commercial purposes"); BokehMe's BLB states no data terms. The clean option is a set the owner shoots himself, the same scenes at f/1.4 and at f/11 to f/16 on a tripod, plus Blender scenes we render ourselves.
5. **The only ProRAW sample checked has no depth.** The repository's iPhone 12 Pro ProRAW (`tests/fixtures/raw/IMG_1361.DNG`) holds a raw IFD and one DNG 1.6 semantic mask, the sky matte (`urn:com:apple:photo:2020:aux:semanticskymatte`, 2016 × 1512, 8-bit). It has no DNG depth tags and no depth IFD. Newer iPhones are **UNVERIFIED**.
6. **The iPhone records Portrait's aperture and focus in an Apple "portrait metadata" set.** Apple's capture framework exports `kFigApplePortraitMetadata` with `ApertureFocalRatio`, `Minimum`/`MaximumApertureFocalRatio`, `FocusRectangle`, `LuminanceNoiseAmplitude`, `PortraitLightingEffectStrength`, `SDOFRenderingVersion` and face landmarks. Photos reads them back with `PIValuesAtCapture valuesAtCaptureFromImageProperties:`, that is, from the image file's own properties. Which container in the file holds them (a MakerApple tag or the depth image's metadata) is **UNVERIFIED** and needs sample files. Core Image's public `CIDepthBlurEffect` takes the same quantities as inputs (aperture 0–22, focus rectangle, luma noise scale 0–0.1, face landmarks, hair, glasses and portrait mattes).

## 1. Lightroom's Lens Blur

### 1.1 Controls and behaviour

Sources: Adobe's Camera Raw help page (Wayback copy of 15 February 2026; page last updated 12 December 2024) [ACR]; the Lightroom Classic page (copy of 13 June 2026; page updated 10 October 2025) [LrC]; the Lightroom (desktop) page (copy of 12 November 2025) [LR]; Josh Bury's post [Bury]. `helpx.adobe.com` refuses the sandbox, but the Wayback Machine's copies load.

- [ACR] <https://web.archive.org/web/20260215094055/https://helpx.adobe.com/camera-raw/using/lens-blur.html>
- [LrC] <https://web.archive.org/web/20260613022825/https://helpx.adobe.com/lightroom-classic/help/lens-blur.html>
- [LR] <https://web.archive.org/web/20251112063341/https://helpx.adobe.com/lightroom-cc/using/lens-blur.html>
- [Bury] <https://blog.adobe.com/en/publish/2024/06/26/inside-lens-blur>

| Control | What the sources say |
|---|---|
| Apply | Desktop: "add Lens Blur to a photo by checking Apply. On mobile, drag the blur slider to activate. There will be a short delay as we estimate the scene depth" [Bury]. |
| Initial focus | "takes advantage of Select Subject to set the initial focus range setting for the subject" [Bury]. |
| Blur Amount | "The slider is set at 50 by default" [ACR]. |
| Bokeh shape | Circle ("Modern circular lens"), Bubble ("over-corrected spherical aberration"), 5-blade, Ring ("reflex or mirror lenses … Doughnut"), Anamorphic / Oval / Anamorphic ("an oval appearance") [ACR], [LR]. At launch the fifth button was Cat Eye [Bury]. |
| Cat Eye | A slider "to achieve a swirling, crescent-shaped blur effect toward the edges and corners" [ACR]. Since December 2024 a slider on desktop, applicable to any shape; still a button on mobile ([Lightroom Queen, December 2024](https://www.lightroomqueen.com/whats-new-in-lightroom-2024-12/)). |
| Boost (Bokeh Boost) | "adjust the brightness of out-of-focus light sources" [ACR]; driven by "a dedicated step for detecting out-of-focus light sources" [Bury]. |
| Focus Range | A range of depth values in focus; "expand or contract the slider box by holding and dragging it from either side" [LrC]. It shows a histogram: a December 2023 bug reads "Lens Blur's Focal Range histogram doesn't update when Use Device Map is toggled" ([LRQ 2023-12](https://www.lightroomqueen.com/whats-new-in-lightroom-2023-12/)). |
| Subject Focus | "Automatically sets the focal range using AI-powered subject detection" [ACR]. |
| Point / Area Focus | "Manually set the focal range by clicking or dragging on the photo" [ACR]. |
| Visualize Depth | Overlay colours: "Warm or Yellow … near", "Cool or Blue … far", "White … currently in focus", the white "only visible while adjusting the focal range slider" [ACR]. |
| Refinement | Focus and Blur brushes with Amount, Brush Size, Feather, Flow and Auto Mask; a Reset icon [ACR]. Blur "can also be used to increase the strength of blur locally in areas just outside of the focal range" [ACR]. Refinements "are also adaptive to changes in the Focus Range" [Bury]. Desktop apps only: "we offer refinement brushes in Lightroom on desktop, Lightroom Classic, and ACR" [Bury]. |
| Device depth | "Lens Blur supports Device Depth for images like .HEIC that already has a depth map" [ACR]; "If a photo has an existing depth map, Lens Blur will use it, unless you specify otherwise" [LR]. The toggle is "Use Device Depth" [Bury] (a bug calls it "Use Device Map"). |
| Copy / Paste / Sync | Since 13.3 (May 2024). When copying, "select Focus on Subject if you want Lightroom to automatically detect the subject in each photo … Focus settings from the source image will apply If Focus on Subject isn't selected" [LrC]. |
| Presets | Adaptive: Blur Background: "Subtle, Strong, Circle, Circle Swirl, Bubble, Bubble Swirl, Geometric, Geometric Swirl, Ring, Ring Swirl, Oval, Oval Swirl", with a preset Amount slider; they "use AI to identify the subject and scan the scene" [LrC]. |

Adobe's own caveats [Bury]: it "cannot remove existing blur"; "finely detailed or narrow subjects such as ropes, fly-away hair, or foliage" are hard; add Grain to the blurred areas, through a mask; turn off the phone's own Portrait blur before importing; and "adjusting Lens Blur will never be as fast as … adjusting Exposure".

### 1.2 Release history

| Date (version) | Change | Source |
|---|---|---|
| October 2023 (LrC 13.0, ACR 16) | Early Access; uses iPhone Portrait depth maps | [LRQ 2023-10](https://www.lightroomqueen.com/whats-new-in-lightroom-2023-10/); ExifTool's table marks `LensBlur` "new for ACR 16" ([XMP.pm](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/XMP.pm)) |
| December 2023 | Bug naming "Use Device Map" and the Focal Range histogram | [LRQ 2023-12](https://www.lightroomqueen.com/whats-new-in-lightroom-2023-12/) |
| February 2024 (13.2) | "Uses Lens Blur" filter for smart collections; Android: "Not rendering on export when using Lens Blur" | [LRQ 2024-02](https://www.lightroomqueen.com/whats-new-in-lightroom-2024-02/) |
| May 2024 (13.3) | General availability, "AI models have been improved", Copy/Paste/Sync/Auto Sync, Focus Range slider on mobile | [LRQ 2024-05](https://www.lightroomqueen.com/whats-new-in-lightroom-2024-05/) |
| October 2024 (14.0) | Bug: "Snapshots don't record Lens Blur brush refinements" | [LRQ 2024-10](https://www.lightroomqueen.com/whats-new-in-lightroom-2024-10/) |
| December 2024 (14.1) | Oval/Anamorphic shape; Cat Eye becomes a slider on desktop; Lens Blur presets in Adaptive: Blur Background | [LRQ 2024-12](https://www.lightroomqueen.com/whats-new-in-lightroom-2024-12/) |
| June 2025 (14.4) | AI settings status icon: Lens Blur listed among settings recreated when pixels change (after Remove); bug "Export Fails … when Lens Blur is used" | [LRQ 2025-06](https://www.lightroomqueen.com/whats-new-in-lightroom-2025-06/) |
| October 2025 (15.0) | Bug: "Focus On Subject ignored when copying Lens Blur from master to a virtual copy" | [LRQ 2025-10](https://www.lightroomqueen.com/whats-new-in-lightroom-2025-10/) |
| December 2025 | Bug: "Lens Blur Visualize Depth not working"; a reader on iPad: "Update AI edits, Some settings require online access … Lens blur ticked" | [LRQ 2025-12](https://www.lightroomqueen.com/whats-new-in-lightroom-2025-12/) |
| February 2026 | Bugs: "AI Edit Status > Update must be invoked twice for Lens Blur on top of Subject Mask"; "Using the Remove tool stops the display of Lens Blur settings" | [LRQ 2026-02](https://www.lightroomqueen.com/whats-new-in-lightroom-2026-02/) |
| April 2026 | Community thread "Lens Blur stopped working suddenly since 4/20/2026"; Adobe's reply (search snippet): "There is currently an outage related to this" | [community.adobe.com](https://community.adobe.com/questions-680/p-lens-blur-stopped-working-suddenly-since-4-20-2026-1558470) (thread not opened; snippet only, **UNVERIFIED** in full) |

The posts for April and June 2026 have no new Lens Blur features. The December 2025 comment and the April 2026 outage suggest that some step needs Adobe's servers, at least on some platforms. Neither source says which step, so this is **UNVERIFIED**.

### 1.3 What Lightroom writes to XMP

Field names come from ExifTool's tag table ([XMP.pm, `LensBlur`, `DepthMapInfo`, `DepthBasedCorrections`](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/XMP.pm); rendered at <https://exiftool.org/TagNames/XMP.html#crs>), checked against XMP files Lightroom wrote, found with `gh search code`:

- defaults, inactive: [Questtion/Lightroom-Presets `FDD Preset 1.xmp`](https://github.com/Questtion/Lightroom-Presets/blob/10e36149ab94e41a702946075ae30195c23af77e/Presets/FDD%20Preset%201.xmp)
- an applied blur: [sarahgretener1/mySpace `_DSC7053.xmp`](https://github.com/sarahgretener1/mySpace/blob/b841cc2f87885618c59578fc192507dbe8e4665a/img/_DSC7053.xmp)
- `FocalRangeSource="3"`: [GlutenJager/poland_rewritten_cop](https://github.com/GlutenJager/poland_rewritten_cop/blob/4c380f4ce5964740ce078d0cc46a6adf369544e2/dev_stuff/graficzki/logo/HTB1eu1py2iSBuNkSnhJq6zDcpXai.jpg_q50.xmp)

**`crs:LensBlur`** (one struct):

| Field | Type (ExifTool) | Seen | Meaning |
|---|---|---|---|
| `Version` | string | `1` | |
| `Active` | boolean | `false`, `true` | the Apply checkbox |
| `ImageOrientation` | — (not in ExifTool's table) | `0` | written by Lightroom; meaning **UNVERIFIED** |
| `BlurAmount` | real (flat name `LensBlurAmount`) | `50` | Blur Amount; 50 matches the documented default |
| `BokehShape` | real | `0` | shape index; only 0 seen, so the index-to-shape mapping is **UNVERIFIED** |
| `BokehShapeDetail` | real | `0` | **UNVERIFIED**, possibly a per-shape parameter |
| `BokehAspect` | real | `0` | probably Oval/Anamorphic's squeeze (**UNVERIFIED**) |
| `BokehRotation` | real | `0` | not in the UI; **UNVERIFIED** |
| `CatEyeAmount` | real | `0` | Cat Eye slider |
| `CatEyeScale` | real | `100` | not in the UI |
| `HighlightsBoost` | real | `50` | Boost |
| `HighlightsThreshold` | real | `50` | not in the UI; the light-source threshold |
| `SphericalAberration` | real | `0` | not in the UI; probably what makes Bubble (**UNVERIFIED**) |
| `FocalRange` | string, four numbers | `0 0 100 100` inactive; `-80 0 53 133`; `-80 0 100 180` | the Focus Range. In both applied samples the outer two numbers are the inner two ∓80, which reads as near-feather start, in-focus start, in-focus end, far-feather end on a 0–100 depth scale (inference, **UNVERIFIED**) |
| `FocalRangeSource` | real | `1` (with `SubjectRange`), `3` | how the range was set (subject, point, manual); mapping **UNVERIFIED** |
| `SubjectRange` | string | `0 53` | the range Select Subject found |
| `SampledArea` | string | `0.500000 0.500000 0.500000 0.500000` | Point/Area Focus rectangle, normalised |
| `SampledRange` | string | `0 0` | depth range under the sampled area |

**`crs:DepthMapInfo`**: `DepthSource` (seen `2`), and for each of `BaseRawDepth`, `BaseLayeredDepth` and `BaseHighlightGuide` a `…Table` (a 128-bit identifier), an `…InputDigest` and a `…Version` (seen 12, 1 and 1). The depth itself is not in the XMP: these name cached data Lightroom keeps elsewhere and rebuilds. The names match Bury's "depth information that's more sophisticated than a basic depth map", and match the claims of Adobe's filings in §6 ("layered depth map", "highlight guide image").

**`crs:DepthBasedCorrections`** (a `Seq` of structs, flat name `DepthBasedCorr`): `What`, `CorrectionActive`, `CorrectionAmount`, `CorrectionSyncID`, `LocalCorrectedDepth`, `LocalCurveRefineSaturation`, and `CorrectionMasks`, a mask list with the usual brush fields (`Dabs`, `Feather`, `Flow`, `CenterWeight`, `MaskVersion` and so on). These are the Focus and Blur brush strokes. No file in the wild with this list turned up (`gh search code "LocalCorrectedDepth"` found only copies of ExifTool), so how a stroke encodes Focus against Blur is **UNVERIFIED**.

Range masks also carry `DepthMin`, `DepthMax`, `DepthFeather` and `LuminanceDepthSampleInfo` (Depth Range masks; ExifTool, same file).

Redlamp ignores `LensBlur` when it reads a Lightroom preset today (`LightroomPresetMapping.swift`, `docs/recipes/lightroom-presets.md`: "ignored: Redlamp has no Lens Blur yet").

### 1.4 What users report

- Halos around the subject: "Every time I'm trying to apply Lens Blur in lightroom, I get a horirble halo effect around the subject. I'm able to fine tune this with a brush but it's so tedious"; a second user: "it is taking forever to brush the edges" (May 2025, [community.adobe.com](https://community.adobe.com/questions-675/lens-blur-halo-effect-982224)). A community expert put it down to "a very poor initial depth mask" and the GPU.
- Refinement brushes hanging: after 13.3 "the program just shows the spinning progress icon … and does nothing other than put streaks of blur following my cursor" (June 2024, [Lightroom Queen forum](https://www.lightroomqueen.com/community/threads/huge-lens-blur-problem-with-13-3.50491/)).
- Lens Blur that stops working after a while in Lightroom Classic 15, until the cache is cleared ([Ask Tim Grey, 24 November 2025](https://asktimgrey.com/2025/11/24/lens-blur-adjustment-failing/), from its search snippet; **UNVERIFIED** in full).
- Adobe's own list of hard subjects: ropes, fly-away hair, foliage [Bury].

### 1.5 Mobile and desktop

| | Desktop (Classic, Lightroom, ACR) | Mobile (iOS, Android) |
|---|---|---|
| Turn on | Apply checkbox | drag the Blur slider [Bury] |
| Focus Range slider | from launch | from May 2024 [LRQ 2024-05] |
| Refinement brushes | yes | no [Bury] |
| Cat Eye | slider since December 2024 | button [LRQ 2024-12] |
| Bugs specific to it | — | Android export didn't render Lens Blur (February 2024) |

Whether the mobile apps run depth estimation on the device is **UNVERIFIED** (a Reddit post about a modified Android build says the photo "is send to cloud for processed by AI", which isn't a reliable source).

## 2. Competitors

| Product | Depth source | Shapes | Beyond Lightroom | Source |
|---|---|---|---|---|
| Apple Photos (iPhone, iPad, Mac) | the capture's disparity and mattes | circular (**UNVERIFIED**) | refocus after capture; on iPhone 15 and later, "When there's a person, dog, or cat in the frame, or when a user taps to focus, iPhone automatically captures depth information, so users can turn photos into stunning portraits later in the Photos app on iPhone, iPad, or Mac … users can also adjust the focus point after the photo has been taken" | [Apple Newsroom, 12 September 2023](https://www.apple.com/newsroom/2023/09/apple-unveils-iphone-15-pro-and-iphone-15-pro-max/) |
| Core Image `CIDepthBlurEffect` (Apple's public renderer) | disparity plus portrait, hair and glasses mattes, gain map | `inputShape` (a string; values **UNVERIFIED**) | aperture (0–22, slider 1–22), focus rectangle, luma noise (0–0.1), face landmarks (eyes, nose, chin) | queried on this Mac, macOS 26.6.2 (§5.4) |
| Google Pixel / Google Photos | dual-pixel disparity plus person segmentation (Pixel 2) | disc | renders in linear light "to preserve highlights", composites disparity layers to avoid halos, adds synthetic noise afterwards | [Wadhwa et al. 2018](https://arxiv.org/abs/1806.04171); [Google Research blog](https://research.google/blog/portrait-mode-on-the-pixel-2-and-pixel-2-xl-smartphones/). Google Photos' Portrait blur for photos without depth: blog pages tried returned 404, **UNVERIFIED** |
| Samsung Galaxy (Portrait / Live focus) | dual camera or estimated | several styles | **UNVERIFIED**: the support page tried returned nothing useful | — |
| Photoshop, Filter › Blur › Lens Blur | an alpha channel, a layer mask or transparency, with "Blur Focal Distance" and Invert | iris from the blade count, Blade Curvature, Rotation | Specular Highlights Threshold and Brightness; Noise Amount, Uniform or Gaussian, Monochromatic; since 21.1 (February 2020) "blurrier edges for foreground objects, brighter bokehs, and more realistic specular highlights" | [Adobe help, Wayback copy 2023](http://web.archive.org/web/2023/https://helpx.adobe.com/photoshop/using/adjusting-image-sharpness-blur.html) |
| Photoshop Blur Gallery (Field, Iris, Tilt-Shift) | none (pins) | — | Light Bokeh, Bokeh Color, Light Range; Noise tab to restore grain | [Adobe help, Wayback copy 11 October 2026](https://web.archive.org/web/20261011225251/https://helpx.adobe.com/photoshop/using/blur-gallery.html) |
| Photoshop Neural Filter: Depth Blur | estimated | — | haze and warmth of the surroundings; "Depth Blur (Beta) process[es] some operations in the cloud" | [Neural Filters FAQ](https://web.archive.org/web/20260417012653/https://helpx.adobe.com/photoshop/using/neural-filters-list-and-faq.html) |
| Focos (iOS, iPadOS) | "The AI engine can calculate depth of field automatically for all photos", plus Portrait depth | "various simulated aperture diaphragms" | lens characters ("creamy, bilinear, swirly, and reflex"), 3D depth view, lights placed in 3D, depth-map patching on iPad, refocus with a tap | [App Store](https://apps.apple.com/us/app/focos/id1274938524) |
| RapidRAW | Depth Anything V2 Small | — | "turns depth into a signed blur radius that fades on either side of the range in focus, after refining the depth with a guided filter against the photo" | `docs/research/rapidraw-findings.md` |
| ON1 Photo RAW | "AI Depth Masks … foreground, midground, background" | — | no lens blur found on the product page | [on1.com](https://www.on1.com/products/photo-raw/) |
| Luminar Neo Portrait Bokeh | — | — | **UNVERIFIED** (product page 404) | — |
| Affinity Photo | — | — | Lens Blur and Depth of Field filters exist; **UNVERIFIED** (affinity.help returns 403) | — |
| Pixelmator Pro | — | — | **UNVERIFIED** (guide page 404) | — |

What the others have that Lightroom doesn't: aperture blades, curvature and rotation (Photoshop); noise or grain restored inside the blur (Photoshop, Pixel); an exposed highlight threshold (Photoshop; Lightroom stores one in XMP but doesn't show it); lens characters and lights placed in depth (Focos); the capture's own hair and glasses mattes at the edges (Core Image).

## 3. Methods

The classic real-time papers' DOIs resolve (checked with `doi.org/api/handles` on 2026-10-13), but their publishers refuse the proxy. Their descriptions below are from the literature as generally summarised and were not re-read for this draft: **UNVERIFIED** in detail. The phone and learned methods were read on arXiv in this session.

| Method | What it does | Cost | Depth edges and partial occlusion | Highlights | Aperture shapes |
|---|---|---|---|---|---|
| Potmesil & Chakravarty 1981, [10.1145/800224.806818](https://doi.org/10.1145/800224.806818) | post-process: each pixel spreads as its circle of confusion from a lens model | scatter, O(N·r²) | none: no visibility, so blurred foregrounds have hard edges | — | circle |
| Kass, Lefohn & Owens 2006, [Pixar memo 06-01](https://graphics.pixar.com/library/DepthOfField/paper.pdf) | blur as heat diffusion, solved with an implicit ADI step per row and column | linear in pixels, independent of radius | layers (midground, background) to limit bleeding; partial occlusion approximate | weak (diffusion has no bokeh shape) | Gaussian-like only |
| Kraus & Strengert 2007, [10.1111/j.1467-8659.2007.01064.x](https://doi.org/10.1111/j.1467-8659.2007.01064.x) | splits the image into depth layers, fills each hidden region by pyramid pull-push, blurs each with a pyramid and composites back to front | about constant per pixel | handles disocclusion behind foregrounds | weak | smooth |
| Lee, Eisemann & Seidel 2009, [10.1145/1618452.1618480](https://doi.org/10.1145/1618452.1618480); 2010, [10.1145/1778765.1778802](https://doi.org/10.1145/1778765.1778802) | layered depth images ray-traced through the lens aperture (2010: real-time lens blur and focus control) | GPU, many rays per pixel | correct partial occlusion from the layers | yes | any |
| McIntosh, Riecke & DiPaola 2012, [10.1111/j.1467-8659.2012.02097.x](https://doi.org/10.1111/j.1467-8659.2012.02097.x) | polygonal apertures from intersecting separable 1D line blurs | separable: O(r) per pixel per pass | gather with depth tests | yes | polygons |
| Jimenez 2014, [Call of Duty: Advanced Warfare post-processing, SIGGRAPH 2014 course](http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare) (link didn't load) | scatter-as-gather in half resolution, separate near and far fields, sample weights by circle of confusion | games-real-time | near field blurred over the in-focus image | yes | circle (polygons by sampling) |
| McGraw 2015, [10.1007/s00371-014-0986-6](https://doi.org/10.1007/s00371-014-0986-6) | aperture kernels approximated as sums of separable rank-1 filters (SVD) | a few separable passes | not addressed | yes | any shape, approximately |
| Garcia 2017, [10.1145/3084363.3085022](https://doi.org/10.1145/3084363.3085022) | circle as a sum of complex Gaussian-like separable kernels (EA Frostbite) | two passes per component | near and far handled separately | yes | circle |
| Abadie 2018, [A Life of a Bokeh, SIGGRAPH 2018 Advances](https://advances.realtimerendering.com/s2018/index.htm) | Unreal Engine 4's DoF: tile-based scatter of bright pixels, gather for the rest, careful near-field handling | games-real-time | slight foreground-over-focus bleed by design | scatters bright pixels as sprites | blade count, curvature |
| Gustafsson 2018, [single-pass bokeh](https://blog.voxagon.se/2018/05/04/bokeh-depth-of-field-in-single-pass.html) | one gather on a spiral, each sample weighted by whether its own circle reaches the pixel | one pass | approximate | yes | circle |
| Wadhwa et al. 2018, [arXiv 1806.04171](https://arxiv.org/abs/1806.04171) (Google Pixel) | disk kernels applied "to sub-images covering different ranges of disparity values", then "composite the intermediate results, gamma-correct, and add synthetic noise"; a forced-zero blur zone around the focal plane keeps the whole subject sharp | phone; radius capped at 30 px | the paper shows that a naive gather "causes the foreground to bleed into the background" and that a single pass blurs the background over the foreground; layered compositing prevents both | renders in "a linear color space … to preserve highlights" | disc |
| Ignatov et al. 2020, EBB!, [arXiv 2006.05698](https://arxiv.org/abs/2006.05698) | PyNET learns phone to DSLR bokeh end to end, with estimated depth as input | network | learned | learned | the Canon lens's |
| Peng et al. 2022, BokehMe, [arXiv 2206.12614](https://arxiv.org/abs/2206.12614) | classical scatter renderer plus a neural renderer that repairs errors at depth discontinuities | network on a few regions | the point of the paper | from the classical part | controllable |
| Peng et al. 2022, MPIB, [arXiv 2207.06917](https://arxiv.org/abs/2207.06917) | multiplane image with learned inpainting of hidden background, then layered rendering | network plus layers | partial occlusion of blurred foregrounds | yes | controllable |
| Sheng et al. 2024, Dr.Bokeh, [arXiv 2308.08843](https://arxiv.org/abs/2308.08843) | differentiable, occlusion-aware layered renderer; paper only (§3.2) | — | yes | yes | yes |
| Fortes et al. 2025, Bokeh Diffusion, [arXiv 2503.08434](https://arxiv.org/abs/2503.08434) | defocus as a control for text-to-image generation (FLUX) | diffusion | generated, not rendered | generated | — |
| Zhu et al. 2025, BokehDiff, [arXiv 2507.18060](https://arxiv.org/abs/2507.18060) (ICCV 2025) | one-step diffusion lens blur conditioned on depth, evaluated on EBB! | one diffusion step at full size | learned | learned | — |
| Seizinger et al. 2025, Bokehlicious, [arXiv 2503.16067](https://arxiv.org/abs/2503.16067) (ICCV 2025) | network with aperture control; introduces RealBokeh | network | learned | learned | aperture-controlled |
| Shi et al. 2026, MagicBokeh, [arXiv 2605.07429](https://arxiv.org/abs/2605.07429) (CVPR 2026, vivo) | diffusion bokeh for low-resolution, zoomed phone photos, on Stable Diffusion 2.1 | diffusion | learned | learned | — |
| Zhang et al. 2025, BokehDepth, [arXiv 2512.12425](https://arxiv.org/abs/2512.12425) | uses bokeh rendering to improve monocular metric depth, and the reverse | network | — | — | — |
| NTIRE 2026 Controllable Bokeh Rendering Challenge, [arXiv 2605.05510](https://arxiv.org/abs/2605.05510) | 8 valid entries, "most … refining and extending the Bokehlicious baseline" | — | — | — | — |

"GenRefocus" was not found on arXiv by that name (**UNVERIFIED**).

**Code and weights licences** (2026-10-13):

| Project | Code licence (verbatim or SPDX, source) | Weights | Verdict |
|---|---|---|---|
| BokehMe | Apache-2.0 ([LICENSE](https://github.com/JuewenPeng/BokehMe)) | in the repo, no separate terms | **UNCLEAR** weights; the classical part can be reimplemented from the paper |
| MPIB | Apache-2.0 ([LICENSE](https://github.com/JuewenPeng/MPIB)) | no separate terms | **UNCLEAR** |
| Dr.Bokeh | none: `gh api repos/ShengCN/DrBokeh/license` and `…/DrBokeh-Src/license` both 404 | — | **Avoid** code; paper only |
| Bokeh Diffusion | "S-Lab License 1.0 … Redistribution and use for non-commercial purpose" ([LICENSE](https://github.com/atfortes/BokehDiffusion/blob/main/LICENSE)) | FLUX-based | **Research-only** |
| BokehDiff | Apache-2.0 text ("Licensed under the Apache License, Version 2.0", [LICENSE](https://github.com/FreeButUselessSoul/bokehdiff)) | the paper mentions SDXL and FLUX; which base model the weights derive from is **UNVERIFIED** | **UNCLEAR** (base model terms) |
| Bokehlicious | no LICENSE file (API 404); README: "If you would like to use this code or dataset for commercial purposes, check the license and contact us" | — | **Avoid** |
| MagicBokeh | no LICENSE file (API 404); SD 2.1 base | — | **Avoid** |
| PyNET-Bokeh (EBB!) | CC BY-NC-SA 4.0 ([LICENSE](https://github.com/aiff22/PyNET-Bokeh)) | — | **Research-only** |

Assessment. Lightroom's described behaviour (layered depth, a separate highlight-detection step, edges rendered from extra depth information) is the Wadhwa / Kraus-Strengert family: layers composited back to front, in linear light, with highlights found before blurring. That family is classical, fits Metal, and needs no learned renderer. The learned renderers above either can't ship or add little that layering, a matte at the subject's edge (C's matting) and in-painted background behind foregrounds (MPIB's idea, with RM-07's fill) don't. The diffusion methods invent pixels and cost seconds; not suited to a slider.

### 3.1 Datasets for evaluation

| Dataset | Content | Terms, verbatim | Evaluation use |
|---|---|---|---|
| EBB! (Ignatov et al. 2020) | "200 image pairs were reserved for testing, while the other 4.8 thousand photo pairs can be used for training and validation"; shallow depth-of-field photos "captured with a professional Canon 7D DSLR camera" ([PyNET-Bokeh README](https://github.com/aiff22/PyNET-Bokeh)) | The page states no licence: "You can now download its training part (without the depth data) by registering in the above challenge" (AIM 2020) ([page](https://aiff22.github.io/pynet-bokeh.html)) | **UNCLEAR**: no terms stated; the challenge's registration terms were not read |
| BLB (BokehMe) | 10 Blender scenes, 5 blur amounts × 10 focal disparities each | README states none ("can be downloaded from Google Drive or Baidu Netdisk"); the repository's Apache-2.0 doesn't clearly cover data hosted elsewhere ([README](https://github.com/JuewenPeng/BokehMe#blb-dataset)) | **UNCLEAR** |
| RealBokeh 3MP (Bokehlicious) | real pairs at several apertures | HF `license: cc-by-nc-sa-4.0`; "the use of this dataset is only permitted for non-commercial purposes" ([card](https://huggingface.co/datasets/timseizinger/RealBokeh_3MP)) | **Research-only**; whether internal benchmarking for Redlamp is "non-commercial" is counsel's question |
| Our own | the same scenes, tripod, a fast lens wide open and stopped down; iPhone Portrait and Photo-mode captures with depth | ours | **Clean.** The owner can shoot them through Redlamp Bench (`.cursor/skills/redlamp-bench`) |
| Our own synthetic | Blender scenes rendered with a real thin-lens camera, like BLB | ours (Blender's GPL doesn't cover its renders) | **Clean**, and exact for edges and highlights |

## 4. Depth models for lens blur

What matters is depth at the subject's outline: a model that smears depth across an edge ("flying pixels") gives the halo users complain about. MoGe-2 measures boundary sharpness and reports that "training exclusively on synthetic data yields the highest sharpness but significantly reduces geometric accuracy" ([arXiv 2507.02546](https://arxiv.org/abs/2507.02546)); Pixel-Perfect Depth says a VAE "inevitably introduces flying pixels at edges", which is why it diffuses in pixel space ([arXiv 2510.07316](https://arxiv.org/abs/2510.07316)).

Training data was checked by searching each paper's arXiv HTML for dataset names, Places included. "No Places" means the paper never mentions Places or Places365.

| Candidate | Code licence | Weights licence (HF `cardData.license` unless noted) | Training data | Places2/365? | Conventions verdict | DEC-24 |
|---|---|---|---|---|---|---|
| **DA3-Small** (0.08B) | Apache-2.0 ([repo](https://github.com/ByteDance-Seed/Depth-Anything-3)) | `apache-2.0`; README "Apache 2.0" | the paper's Table 1 (AriaDigitalTwin, ArkitScenes, BlendedMVS, Co3dv2, DL3DV, HyperSim, MapFree …) with teacher pseudo-depth from a synthetic-trained teacher | not in the paper | **UNCLEAR** (mixed academic terms) | passes |
| **DA3-Base** (0.12B) | Apache-2.0 | `apache-2.0`; README "Apache 2.0" | same | not in the paper | **UNCLEAR** | passes |
| DA3Mono-Large (0.35B; shipped) | Apache-2.0 | `apache-2.0`; README "Apache 2.0" | "We follow the DA2 framework, training the monocular student on unlabeled images with teacher-generated pseudo-labels" (§4.3); the images aren't named. DA2's unlabeled set (its Table 7) includes "Places365" | **probably, UNVERIFIED** | **UNCLEAR** | probably fails; shipped under the DEC-02 exception |
| DA3Metric-Large | Apache-2.0 | `apache-2.0` | teacher labels and metric sets, not itemised here | **UNVERIFIED** | **UNCLEAR** | **UNVERIFIED** |
| DA3-Large, -Giant, Nested | Apache-2.0 | README "CC BY-NC 4.0"; HF `DA3-LARGE-1.1` says `apache-2.0` (contradiction) | — | — | **Research-only** (UNCLEAR for Large-1.1) | fails |
| **MoGe-2 ViT-S / B / L** | MIT, "except for DINOv2 code … Apache 2.0" ([README](https://github.com/microsoft/MoGe)) | `mit` (`Ruicheng/moge-2-vits-normal`, `-vitb-normal`, `-vitl-normal`, `-vitl`) | "a large corpus of mixed datasets", synthetic and real, the real filtered and completed by a synthetic-trained model. Names in the paper include Hypersim, TartanAir, IRS, Spring, Synscapes, MVS-Synth, UnrealStereo4K, Objaverse, MegaDepth, ScanNet, ARKitScenes and Waymo; which of them are training rather than test sets was not checked | not in the paper | **UNCLEAR** | passes |
| Depth Pro | Apple sample-code licence | `apple-amlr`, research only | — | — | **Research-only** | excluded |
| Apple SHARP (ml-sharp) | Apple sample-code licence | `apple/Sharp`: `apple-amlr`; LICENSE_MODEL "exclusively for Research Purposes" | — | — | **Research-only** | excluded |
| Marigold v1.1 / LCM | Apache-2.0 | v1.1 `openrail++` ("RAIL++-M", README); LCM v1.0 `apache-2.0` | Stable Diffusion 2 (LAION), Hypersim, Virtual KITTI | not in the paper | **UNCLEAR**; heavy | passes (RAIL use limits apply) |
| Lotus | Apache-2.0 | `apache-2.0` | SD2 lineage; Hypersim, Virtual KITTI | not in the paper | **UNCLEAR**; heavy | passes |
| Metric3D v2 | BSD-2-Clause | publisher's terms not stated; `onnx-community/metric3d-vit-small` says `cc0-1.0`, but it's a third party's conversion | 16M images from many sets | not in the paper | **UNCLEAR** | **UNVERIFIED** |
| UniDepth v2 | "Creatives Common BY-NC 4.0" (README) | HF has no `license` field | — | — | **Avoid** | fails |
| Distill-Any-Depth | MIT | `xingyang1/Distill-Any-Depth-{Small,Large}-hf`: `mit`; `xingyang1/Distill-Any-Depth`: `apache-2.0` | SA-1B images, distilled "from Genpercept and DepthAnythingv2" | not directly | **UNCLEAR** (a teacher may be DA-V2 Large, CC BY-NC) | passes on the letter |
| **Pixel-Perfect Depth** | Apache-2.0 ([repo](https://github.com/gangweix/pixel-perfect-depth)) | `apache-2.0` (`gangweix/Pixel-Perfect-Depth`) | Hypersim, Virtual KITTI, TartanAir, Spring …; semantics from a pretrained vision encoder | not in the paper | **UNCLEAR**; a diffusion transformer, seconds per image (**UNVERIFIED** on Apple silicon) | passes |
| PatchFusion / PatchRefiner | MIT | `zhyever/PatchFusion`: `mit` | UnrealStereo4K, MVS-Synth (synthetic), base models from ZoeDepth / DA | not in the paper | **UNCLEAR** | passes; PatchRefiner V2 has no licence (API 404) |
| Prompt Depth Anything | Apache-2.0 | `depth-anything/prompt-depth-anything-vits`, `-vitl`: `apache-2.0` | ARKitScenes, ScanNet++; prompted by LiDAR depth | not in the paper | **UNCLEAR** | passes |
| FoundationStereo | NVIDIA licence: "may be used or intended for use non-commercially … 'non-commercially' means for research purposes only" ([LICENSE](https://github.com/NVlabs/FoundationStereo/blob/master/LICENSE)) | — | — | — | **Research-only** | fails |
| C-FoundationStereo-S, C-Fast-FoundationStereo | — | `nvidia-open-model-license` ([card](https://huggingface.co/nvidia/c-foundationstereo-s)); README: "For commercial usage (adapted from Vit-small model)" | the card lists its data, the CREStereo dataset among them | — | **UNCLEAR** (data) | passes |
| RAFT-Stereo | MIT | weights in the repo, no separate terms | **UNVERIFIED** | — | **UNCLEAR** | passes |

Core ML conversions on Hugging Face: `apple/coreml-depth-anything-v2-small` (`apache-2.0`), `mlboydaisuke/Depth-Anything-3-Small-CoreML` and `-Base-CoreML` (`apache-2.0`), `ebowwa/moge-2-vits-normal-coreml` (`mit`), `mlboydaisuke/MoGe-2-ViT-B-CoreML`, `coreml-projects/DepthPro-coreml` (`apple-ascl`; the weights remain research-only). Redlamp already converted DA3 Mono-L itself (336 MB, 125 ms on the GPU; tracker, MSK-17). Third-party conversions are for timing only; ship our own conversion of the publisher's weights.

**Apple system depth.** No public API on macOS 26 estimates depth from a single photo, as far as the documentation shows. `ImagePresentationComponent.Spatial3DImage` ("Spatial scenes are created by an AI algorithm that leverages computational depth") is visionOS 26.0 only and returns no depth ([DocC](https://developer.apple.com/documentation/realitykit/imagepresentationcomponent/spatial3dimage)). `AVDepthData` comes only from capture (`AVCapturePhotoOutput.isDepthDataDeliverySupported`: iOS, iPadOS, Mac Catalyst, tvOS; no macOS). Whether Vision on macOS 26 has a depth request was not checked in this session (**UNVERIFIED**).

**iPhone spatial photos**: two views that a stereo model could turn into depth with a real baseline. Which iPhones take them, their container and their baseline are **UNVERIFIED** here. The only stereo weights that allow commercial use are NVIDIA's C-FoundationStereo (Open Model License, data unaudited).

Assessment. For the edge quality lens blur needs, evaluate MoGe-2 ViT-B (then ViT-S for iPhone) and DA3-Base against DA3 Mono-L and V2 Small, with Pixel-Perfect Depth as the reference ceiling. All are UNCLEAR on data under the conventions, as every depth model with real-image training is; under DEC-24, MoGe-2 and DA3-Small/Base pass, and Mono-L's standing should be recorded in DEC-02. With embedded phone depth, Prompt Depth Anything's approach (a coarse metric depth as prompt to a sharp model) is the right shape for raising Apple's low-resolution disparity to the photo's resolution, though it was trained with LiDAR prompts.

## 5. Phone depth formats

### 5.1 iPhone capture

- **Disparity.** "Images captured by Camera app, like Portrait images in photos, always store Depth as disparity maps with camera calibration metadata" (WWDC23, quoted in C-masking §1.3). `AVDepthData`: disparity is "in units of 1/meters: (`pixelShift / (pixelFocalLength * baselineInMeters)`)"; the maps are "nonrectilinear", "warped to match the lens distortion characteristics" of the image; and they carry `depthDataAccuracy`, `depthDataQuality`, `isDepthDataFiltered` and `cameraCalibrationData` ([DocC](https://developer.apple.com/documentation/avfoundation/avdepthdata)). Pixel formats: Redlamp's reader handles `DisparityFloat16`/`32` and `DepthFloat16`/`32` (`FileInspection.swift`). Resolutions per device and mode: **UNVERIFIED** (no HEIC samples in the repository).
- **Portrait effects matte.** "a depth-guided, people-focused segmentation mask … The matte image has higher resolution than the depth map" ([DocC](https://developer.apple.com/documentation/avfoundation/avportraiteffectsmatte)). Semantic mattes: hair, skin, teeth, glasses (`AVSemanticSegmentationMatte`), and sky as an ImageIO type (C-masking §1.3).
- **Photo mode, iPhone 15 and later**: depth is captured automatically "When there's a person, dog, or cat in the frame, or when a user taps to focus" (Newsroom, §2).
- **ProRAW**: the iPhone 12 Pro sample has one semantic mask (sky) and no depth (§0). DNG defines depth (DNG 1.5: `DepthFormat`, `DepthNear`, `DepthFar`, `DepthUnits`, `DepthMeasureType`; ExifTool's [Exif.pm](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/Exif.pm) "tags 0xc7e9-0xc7ee added by DNG 1.5.0.0") and semantic masks (DNG 1.6: `SemanticName`, `SemanticInstanceID`, PhotometricInterpretation 52527); PhotometricInterpretation 51177 is "Depth Map". Whether iPhone 15/16/17 ProRAW writes a depth IFD: **UNVERIFIED**.
- **Spatial photos**: **UNVERIFIED**.

### 5.2 Where the Portrait's aperture and focus are

- Apple's private capture framework exports these symbols (CMCapture, macOS 11.3 SDK stub, [phracker/MacOSX-SDKs](https://github.com/phracker/MacOSX-SDKs/blob/041600eda65c6a668f66cb7d56b7d1da3e8bcc93/MacOSX11.3.sdk/System/Library/PrivateFrameworks/CMCapture.framework/Versions/A/CMCapture.tbd)): `kFigApplePortraitMetadata` and its keys `_ApertureFocalRatio`, `_MinimumApertureFocalRatio`, `_MaximumApertureFocalRatio`, `_FocusRectangle`, `_LuminanceNoiseAmplitude`, `_PortraitLightingEffectStrength`, `_SDOFRenderingVersion`, `_SDOFFaceLandmarkIndexes`, `_FaceLandmarksData`, `_FaceOrientation`, `_Version`; and `FigDepthBlurEffectRenderingMinimumSimulatedAperture` / `…Maximum…`.
- Photos' private PhotoImaging (macOS 26.4 header dump, [thatmarcel/macOS-26.4-headers](https://github.com/thatmarcel/macOS-26.4-headers/blob/4d5d4f5eba9020ff6bf2879071d565dcce0f4db1/headers/PhotoImaging/PIValuesAtCapture.h)) has `PIValuesAtCapture` with `aperture`, `portraitStrength`, `focusRect`, `minimumAperture`, `maximumAperture`, `SDOFRenderingVersion`, `portraitMajorVersion`, `portraitMinorVersion`, `depthVersionInfo`, built by `+valuesAtCaptureFromImageProperties:error:`. So the capture-time values are in the image's own properties.
- Which container holds them is **UNVERIFIED**. ExifTool's Apple maker-note table ([Apple.pm](https://github.com/exiftool/exiftool/blob/master/lib/Image/ExifTool/Apple.pm)) names no Portrait aperture tag; it lists `ImageCaptureType` (tag 0x0014: 1 ProRAW, 2 Portrait, 10 Photo, 11 Manual Focus, 12 Scene) and several undecoded PLIST tags (0x004e, 0x004f, 0x0054, 0x005a). ExifTool's `apdi` XMP namespace (`AuxiliaryImageType`, `NativeFormat`, `StoredFormat`) describes auxiliary images, not Portrait settings.
- A change made later in Photos (another f-number or focus point) is an edit, presumably stored in Photos' adjustments (the `.AAE` file on export): **UNVERIFIED**.

What Photos' export paths keep (Export Unmodified Original, a normal export, AirDrop with All Photos Data): **UNVERIFIED**. A Redlamp Bench task should cover them all: one Portrait, one Photo-mode capture with a person, one ProRAW and one spatial photo from an iPhone 15, 16 and 17 if available, each exported all three ways, then read with ImageIO.

### 5.3 Android and Samsung

- **Dynamic Depth 1.0** (Google, [PDF](https://developer.android.com/static/media/camera/camera2/Dynamic-depth-v1.0.pdf), 49 pages; table of contents read): a JPEG with concatenated or ISO box containers and XMP elements (Device, Camera, Image, Imaging Model, Depth Map with "RangeLinear", "RangeInverse", "FocalTable" and "Confidence Maps", Point Cloud), with a "Depth Photo" profile. The FocalTable gives the capture's lens model, which Google's granted patent US12634429B2 uses for refocus (§6).
- **Samsung**: Live focus and Portrait photos keep depth in a proprietary trailer: **UNVERIFIED**, not researched here.

### 5.4 Core Image's depth blur

Queried with `CIFilter(name: "CIDepthBlurEffect")!.attributes` on this Mac (macOS 26.6.2 build 25G83; script `src/cifilt.swift`): `inputImage`, `inputDisparityImage`, `inputMatteImage`, `inputHairImage`, `inputGlassesImage`, `inputGainMap`, `inputAperture` (default 0, min 0, max 22, slider 1–22), `inputFocusRect`, `inputLumaNoiseScale` (0–0.1), `inputScaleFactor` (default 1), `inputShape` (string), `inputCalibrationData` (`AVCameraCalibrationData`), `inputAuxDataMetadata` (`CGImageMetadata`), and eye, nose and chin positions; available on the Mac since 10.13. `CIContext.depthBlurEffectFilter(forImageURL:options:)` (macOS 10.14) builds it from a file, and "The receiver context is used to render the image in order to get the facial landmarks"; the variant taking `disparityImage`, `portraitEffectsMatte`, `hairSemanticSegmentation`, `glassesMatte` and `gainMap` arrived in macOS 11 ([DocC](https://developer.apple.com/documentation/coreimage/cicontext/depthblureffectfilter(forimageurl:options:))). `CIBokehBlur` (radius, ring amount, ring size, softness) is uniform, with no depth input.

Assessment: `CIDepthBlurEffect` can render an iPhone Portrait as Apple does, from the file's own data, and is a ready reference to compare Redlamp's renderer with. Whether it works in a linear, scene-referred pipeline at full resolution is **UNVERIFIED**.

## 6. Patents a clean-room implementation might touch

**This is a list for counsel, for DEC-05. It is not a legal opinion.** Searched on Google Patents (US, through its query endpoint) on 2026-10-13; the status and expiry dates are Google's computed ones, not legal status, and the search is not exhaustive. Claim summaries paraphrase claim 1 as published; pending claims can change.

| Number | Owner | Status, expiry (Google) | Claim 1, in short | Touches |
|---|---|---|---|---|
| [US12586163B2](https://patents.google.com/patent/US20250104197A1/en) (pub. US20250104197A1), "Interactively refining a digital image depth map for non destructive synthetic lens blur" | Adobe | granted 2026-03-24; adjusted expiration 2044-04-16 | "a fused depth map comprising a combination of foreground depth values and background depth values from a layered depth map … and a focal matte indicating an in-focus range"; modify it "according to a selected focus range and a selected correction mode"; render the lens blur | Focus/Blur refinement brushes that follow the focus range; layered (foreground and background) depth. **High** |
| [US20250104198A1](https://patents.google.com/patent/US20250104198A1/en), "Interactively adjusting light source brightness … with non-destructive synthetic lens blur" | Adobe | pending | a gradient mask from luminance edges and a highlight mask from a luminance threshold, combined into a "highlight guide image" of light sources | Bokeh Boost by thresholding and edge tests. **High if granted** |
| [US20260170618A1](https://patents.google.com/patent/US20260170618A1/en), "Generating non-destructive synthetic lens blur with in-focus edge rendering" | Adobe | pending (filed 2026-02-09) | a focal range selected "via a focal range selection tool within a graphical user interface" sets an in-focus region; render the blur accordingly | Any focus-range UI. Broad as published; prior art includes Google's expired US10552947B2. **Watch** |
| [US11869172B2](https://patents.google.com/patent/US20230075050A1/en) (pub. US20230075050A1), "Kernel reshaping-powered splatting-based efficient image space lens blur" | Adobe | granted 2024-01-09; anticipated expiration 2040-11-17 | aggregating pixel influences with "reshaped kernel gradients" from several disparity maps (gradient-domain splatting) | Only a renderer that splats kernel gradients and integrates. **Medium** |
| [US10552947B2](https://patents.google.com/patent/US10552947B2/en), "Depth-based image blurring" (Lytro, priority 2012) | Google | **Expired – fee related** | a range bar with two sliders setting two focus depths | Free to use; useful prior art for focus-range UI |
| [US12634429B2](https://patents.google.com/patent/US12634429B2/en), "Techniques to capture and edit dynamic depth images" | Google | active; anticipated expiration 2039-11-19 | image metadata with "a lens focal model"; a user's target focal distance; modify pixels so objects at that distance are in focus | Refocusing Dynamic Depth photos from their FocalTable. **Medium** |
| [US20240394852A1](https://patents.google.com/patent/US20240394852A1/en), "Selective image blurring using machine learning" | Google | pending | a "focal table" with a focal range and front or back slope, adjusted to include detected faces' boxes | Automatic focus range from faces or subject (as Subject Focus). **Watch** |
| [US11210799B2](https://patents.google.com/patent/US20200242788A1/en), "Estimating Depth Using a Single Camera" | Google | granted 2021-12-28; adjusted expiration 2037-12-17 | depth from dual-pixel subpixel images | Only if Redlamp computes depth from dual pixels. **Low** |
| [US20260099245A1](https://patents.google.com/patent/US20260099245A1/en), "User interface camera effects" (priority 2017-06-04) | Apple | pending continuation; earlier family members likely granted (**UNVERIFIED** which) | applying a filter differently when the image has associated depth information | Depth-aware filters and Portrait-style UI. **Medium** |
| [US20260112046A1](https://patents.google.com/patent/US20260112046A1/en), "Displaying and editing images with depth information" (priority 2018-09-28) | Apple | pending continuation (claim 1 cancelled in this publication); family grants **UNVERIFIED** | — | Photos' depth control and refocus UI. **Medium** |
| [US20260089403A1](https://patents.google.com/patent/US20260089403A1/en), "Image processing with adjustable bokeh effect" | Qualcomm | pending | combining frames captured at two focus points for a chosen depth of focus | Multi-frame capture only. **Low** |

Not covered: Samsung (no direct hit), Lytro's light-field refocus families (mostly assigned to Google; many lapsed), and granted members of the Apple families. Assessment for counsel: what Redlamp would do most like Adobe is refine the depth with brushes that stay tied to the focus range (US12586163B2) and find light sources by thresholding (US20250104198A1). A design that edits a Redlamp-specific depth correction layer, or brightens highlights by their linear radiance rather than a detection mask, may sit apart from those claims; that is for counsel to judge.

## 7. Open questions

1. iPhone samples (a Redlamp Bench task): depth and matte resolutions per mode and device; where `kFigApplePortraitMetadata` sits in the file; whether iPhone 15–17 ProRAW carries depth; what each Photos export path keeps.
2. The `BokehShape` and `FocalRangeSource` codes and the brush encoding in `DepthBasedCorrections`: a few Lightroom edits saved to XMP, one per shape and per focus mode, would settle them (owner, in Lightroom).
3. DA3 Mono-L's unlabeled training set: ask ByteDance, or record it in DEC-02 as probably including Places365.
4. Whether evaluating on RealBokeh or EBB! is allowed for Redlamp (counsel); the clean alternative is our own set.
5. DEC-05: add the Adobe and Google patents above to the freedom-to-operate search.
