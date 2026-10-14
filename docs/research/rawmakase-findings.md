# What Redlamp Can Learn from RAWmakase

**Date:** 7 October 2026; second pass 14 October 2026. **Subject:** RAWmakase v0.2.0 (`main` at `cfe010d`, 7 October 2026), the LibRaw commit its releases ship (master at `4f01440`, 2 October 2026), its documentation, release notes and issues; the second pass, v0.3.0 and `main` at `17b70e8a` (14 October 2026).
**Decisions and status:** on 7 October 2026 the owner accepted the slider work (UX-28, UX-29) and asked for the study's other lessons as Proposed rows in the [research intake tracker](research-tracker.md), for a decision later ([section 8](#8-decisions-and-tracker-rows)). On 9 October 2026 the owner chose to move LibRaw to master's head (`7bfffe2`), and CAM-13 is done. On 14 October 2026 a second pass read RAWmakase 0.3.0, with camera and lens profiles first, and a reviewer's side-by-side ([section 9](#9-second-pass-14-october-2026)); the owner accepted its nine recommendations, Adobe's profiles on the photographer's Mac (DEC-85) and DEC-41 the same day.

RAWmakase is an open-source raw editor by Piotr Chmolowski, written in Rust, for macOS, Linux and Windows. It was started on 26 September 2026 and shipped 17 releases in its first eleven days; on 7 October it had 249 stars, 1,327 commits and 296 pull requests, almost all from agent branches. Its aim is "close, not exact, Lightroom parity": Lightroom Classic's Develop module rebuilt control by control, its responses fitted to Camera Raw's renders, with a way in for a Lightroom user's catalog, presets and profiles. This study asked how it compares with Redlamp, what it does differently or better, how it uses LibRaw, and what Redlamp should take from it.

## How this was done

- RAWmakase was read from a clone at `cfe010d` in `build/oss/rawmakase` (gitignored), with its documentation, release notes and issues on GitHub. It is MIT-licensed, so its source may be read and, with attribution, adapted; none was copied into Redlamp.
- LibRaw's master branch, its 0.22.2 tag and pull request [#826](https://github.com/LibRaw/LibRaw/pull/826) were read on GitHub on 7 October 2026.
- Nothing was run: RAWmakase wasn't built or installed. Its figures come from its own documents, on an Apple M1 Pro; Redlamp's come from its README, on an M1 Ultra, so speeds compare only roughly.
- Licences were read from GitHub's licence API and the repository's `licenses/` folder on 7 October 2026.
- Redlamp's side was checked against the README, the tracker and the code on 7 October 2026.

## Contents

1. [Executive summary](#1-executive-summary)
2. [RAWmakase at a glance](#2-rawmakase-at-a-glance)
3. [How RAWmakase chases Lightroom](#3-how-rawmakase-chases-lightroom)
4. [Compared with Redlamp](#4-compared-with-redlamp)
5. [What to adopt](#5-what-to-adopt)
6. [What not to follow](#6-what-not-to-follow)
7. [Licensing](#7-licensing)
8. [Decisions and tracker rows](#8-decisions-and-tracker-rows)
9. [Second pass, 14 October 2026](#9-second-pass-14-october-2026)

---

## 1. Executive summary

**RAWmakase's lesson for Redlamp is in the details of the Develop module, and in measuring Lightroom rather than guessing it.** Its raw processing is simpler than Redlamp's, it works and exports in sRGB, it has no AI tools and no accessibility support. What it does better is the last few per cent of Lightroom Classic's interface: numbers you can drag as well as type, a switch on each panel, Before/After with Copy and Swap, the pixel's values under the histogram, and a way in for everything a Lightroom user already has. It also shows the way to EDT-11's unfinished half: slider responses fitted to Camera Raw's renders of synthetic charts, checked in CI.

**Lessons, in priority order:**

| # | Lesson | Verdict | Phase |
| --- | --- | --- | --- |
| 1 | **A value on every control, and numbers that read as fields and scrub.** Redlamp's slider rows already take typed values with arithmetic (UX-01); seven other controls show no value or can't be typed into, and no number shows it's editable or can be dragged | Adopt | P2 |
| 2 | **Pin LibRaw master `4f01440` for CAM-13 now,** as RAWmakase's releases do: it opens the Sony A7 V and the A1 II's compressed files, and needn't wait for Nikon's High Efficiency decoder (CAM-12), which isn't merged | Adopt | P2 |
| 3 | **A Lightroom parity corpus for EDT-11:** synthetic chart DNGs of an invented camera, rendered by Camera Raw, reduced to patch means; conversions fitted to them, and a CI check that fails when one drifts | Do better | P2–P3 |
| 4 | **Import a Lightroom Classic catalog,** read-only: develop settings through EDT-11's converter, ratings, flags and labels | Adopt | P4 |
| 5 | **Lightroom's panel on/off switches,** each a History step saved with the edit | Adopt | P2 |
| 6 | **Before/After as Lightroom has it:** left/right or top/bottom by choice, Copy Before's and After's settings, Swap | Adopt | P2 |
| 7 | **The pixel's R, G and B under the histogram,** and a clipping preview while the pointer is over a triangle | Adopt | P2 |
| 8 | **The embedded JPEG while a slow raw opens,** labelled as a preview, instead of a spinner | Adopt | P2 |
| 9 | **Save a recipe as a Lightroom preset,** with EDT-11's report in reverse | Adopt | P3 |
| 10 | **Match Total Exposures** | Adopt | P2 |
| 11 | **MIDI controllers** through Core MIDI | Adopt | P4 |
| 12 | **Rows for Lightroom features planned without one:** Reference View, the Targeted Adjustment Tool, watermarks | Adopt | P2, P4 |
| 13 | **VoiceOver for slider rows,** found while auditing them: they carry identifiers but no role, value or actions | Build | P4 |

**What Redlamp already does better, and should keep:** edits that render the same in every release, against recorded references (applying a preset in RAWmakase can move an old edit to a newer engine); a linear Rec. 2020 working space with sRGB or Display P3 output at up to 16 bits; a stronger demosaic; the whole pipeline on the GPU, at 0.6–3 ms per interactive render at Fit; AI masks and Generative Remove; no telemetry; typed arithmetic in value fields; and AppKit's accessibility for every standard control.

---

## 2. RAWmakase at a glance

| | RAWmakase | Redlamp |
| --- | --- | --- |
| Licence | MIT; two Adobe DNG SDK tables under the SDK's licence | MPL-2.0 |
| Platforms | macOS 15 (Apple Silicon and Intel), Linux (DEB, RPM, Arch), Windows 10 | macOS 26 on Apple Silicon; iPad and iPhone in Phase 5 |
| Stack | Rust, egui (eframe 0.36.2), wgpu 30 on Metal, Vulkan or DirectX 12 | Swift, AppKit and Metal |
| Raw decoding | LibRaw (master `4f01440` in releases) to unpack; its own demosaic; Little CMS | LibRaw 0.22.2 to unpack, in a sandboxed service; Redlamp's own demosaic and colour |
| Colour | LibRaw's Adobe-derived matrix as a D50 forward matrix, with the DNG SDK's ACR3 tone curve; the photographer's own DCPs | Linear Rec. 2020 from camera RGB; Redlamp's own looks; DNG profiles (CAM-04, TON-09) |
| Output | JPEG (8-bit) or TIFF (16-bit), sRGB only | JPEG, HEIC, AVIF, PNG or TIFF, at 8, 10 or 16 bits, sRGB or Display P3 |
| Where edits live | A SQLite catalog (`.rawmakase`), with previews in a second database | A `.redlamp` package beside each photo |
| Old edits after an update | An engine number (2, 3 or 4) and a model flag per operator; Calibration › Process › Update moves an edit on | Never change: each process version renders as it did, checked against recorded references |
| GPU | Previews' colour and tone stage; exports on the CPU | Every stage, previews and exports |
| Preview speed | 11–17 ms per change at Fit on the GPU, 95–166 ms on the CPU (M1 Pro) | 0.6–3 ms per change at Fit (M1 Ultra) |
| AI | None yet; masks and removal are "coming soon" | Vision, SAM 2.1 and 3, Depth Anything, FLUX.2 Generative Remove |
| Library | A catalog: grid, filters, collections, keywords, Survey, Compare, metadata | A working set of folders with ratings, flags and labels; a catalog is Later |
| Accessibility | None: eframe is built without AccessKit | AppKit's; custom slider rows carry identifiers only |
| Telemetry | An opt-in weekly report that shows its exact contents | None |
| Cadence and reach | 17 releases from 26 September to 6 October 2026; 249 stars, 31 issues, 296 pull requests | — |

---

## 3. How RAWmakase chases Lightroom

### 3.1 Responses fitted to Camera Raw

Nearly every Develop control in RAWmakase's current engine was fitted to Camera Raw's output, not designed from a description. Camera Raw 18.6 and 18.7, driven from Photoshop by scripts in `scripts/corpus/`, render the same inputs with each setting; RAWmakase renders them too and its operator is fitted until the two agree. The fitted results ship as tables in the source: colour grading curves from about 740 Camera Raw renders (`color_grade_curves.bin`), the parametric curve from about 380, the Color Mixer from a 1,728-colour chart at 60 settings, and models for Clarity, Texture, sharpening, colour noise reduction, vignettes, grain, Point Color and calibration. Auto Tone is fitted to 452 Auto Settings steps in 439 photos of the author's own Lightroom catalog, and Auto white balance to 133 photos.

`docs/parity-gaps.md` keeps the result honest: each control's distance from Camera Raw, and what isn't measured. On the synthetic chart, the default render is a mean ΔE2000 0.66 from Camera Raw's (0.91 before out-of-gamut colours were clipped per channel, as Camera Raw clips them); single Color Mixer bands sit at 0.64–1.31 and colour grading at 0.56–1.43. The worst are Highlights at +100 (8.66) and Dehaze at ±100. On real photos, Lightroom's X100F exports and Camera Raw's A7 II renders differ from RAWmakase's by a mean of 0.009 and 0.0065 (encoded sRGB, 0 to 1).

### 3.2 The chart corpus and its check

The inputs are synthetic: 970 × 742 mosaic DNGs (`tests/corpus/charts/`) with a grey ramp from −8 to +3.5 EV, 24 hues at three lightnesses and chromas, a ColorChecker, skin tones and near-neutrals. Most are of an invented camera with its own matrices ("no manufacturer or Adobe data"), the rest one per camera from LibRaw's matrix. `cases.json` holds about 360 settings cases as Camera Raw XMP attributes. Camera Raw's renders are reduced to patch means (`tests/corpus/camera-raw/*.json`) and `baseline.json` records RAWmakase's accepted distance per case.

Every `cargo test` renders the charts on the CPU and fails when a patch moves more than ΔE2000 0.5 against its snapshot, or when a case moves further from Camera Raw than its baseline (mean +0.1, 95th percentile +0.3). Raising a baseline is a reviewed decision: "accepting a larger distance should be a decision, not a side effect." A private tier, outside the repository, adds 1,305 photo references. The corpus's own README lists what it doesn't cover: the tolerances are guesses, the GPU preview path isn't checked, and content-adaptive controls (Shadows, Highlights, Dehaze, Clarity) say little on flat patches.

### 3.3 Lightroom's data, in

- **Catalogs.** Catalog › Import Lightroom catalog takes a snapshot of a closed `.lrcat` under 2 GB and imports, in one transaction: folders, photos and virtual copies, ratings, flags, colour labels, collections, keywords, descriptive metadata, each photo's develop settings and its history steps. A byte-exact copy of the source catalog is kept inside RAWmakase's, so nothing it doesn't read yet is lost. Develop settings convert through the same XMP path as presets; masks and spots convert, AI and colour range masks are reported and left out. It was checked on an 8,115-photo catalog, every rating, flag and label compared with the source. "No Lightroom file or RAW is modified."
- **Presets and curves.** Lightroom XMP presets import into a library of their own (the author's archive held 921); 26 MIT-licensed presets ship with the app.
- **Profiles and lenses.** DCP and Adobe XMP look profiles, and LCP lens profiles, import from files the photographer chooses. On a Mac or PC, the Profile menu looks in Camera Raw's profile folder for the current camera and offers to import what it finds. No Adobe file is bundled.
- **What it never does:** write XMP sidecars, or write to a Lightroom catalog.

### 3.4 Lightroom's data, out

Settings › New Develop Preset writes an XMP preset "laid out as Lightroom writes presets", so Lightroom and Camera Raw can read it (checked with ExifTool, not yet in Lightroom). Exports carry the edit as `crs:` settings, as Lightroom's exports do. Saved tone curves are XMP files in Lightroom's layout.

---

## 4. Compared with Redlamp

### 4.1 Raws, LibRaw and cameras

**Both use LibRaw the same way: to unpack the sensor data, and nothing after it.** RAWmakase's C++ shim (`native/raw.cpp`) copies the mosaic out of LibRaw with its black levels subtracted, and RAWmakase demosaics it; LibRaw's own development (`dcraw_process`) remains for half-size drafts, for layouts its demosaic doesn't handle, and as a choice in Preferences.

| | RAWmakase | Redlamp |
| --- | --- | --- |
| LibRaw | Master `4f01440` (2 October 2026) in release builds, which still calls itself 0.22.0; a system LibRaw 0.22 or later for source builds | 0.22.2, pinned by hash in `config/vendored-libs.json`; a commit can be pinned by its SHA |
| Bayer demosaic | Hamilton–Adams green, blended by inverse gradient, then red and blue from colour differences; LibRaw's AHD as an option | Menon, Andriani and Calvagno (2007), with a dual pass where neighbours differ only by noise |
| X-Trans demosaic | The same two passes; LibRaw's one-pass Markesteijn as an option | A first-generation interpolation; Markesteijn is CAM-07, ported under CDDL (DEC-40) |
| Highlights | Clipped channels estimated from nearby unclipped ratios, neutral when there's no evidence | Clipped photosites rebuilt on the mosaic from unclipped neighbours |
| Canon's black levels | LibRaw reads 0 for the EOS R6 Mark III and PowerShot V1; RAWmakase takes the left optical-black border's median when LibRaw's is below a quarter of it | The same bug, found separately: the masked photosites the CR3 declares replace the stated levels (CAM-21) |
| Not opened | Foveon, monochrome sensors, linear DNGs | Monochrome sensors (CAM-20), High Efficiency NEFs (CAM-12), bodies newer than 0.22.2 (CAM-13) |
| Per-camera exposure | A table of 180 bodies' baseline exposure, mostly from Adobe DNG Converter's BaselineExposure plus the white-level difference, so renders aren't 0.3 EV darker than Lightroom's | A DNG's BaselineExposure; none for other raws |

**The LibRaw commit is the useful find.** LibRaw's master at `4f01440` is 106 commits ahead of the 0.22.2 tag and 58 behind it (0.22.2 was cut from a stable branch, and its fixes were applied to master separately). Its additions include Sony's ARW6 decoder and the A7 V (ILCE-7M5), the A1 II's compressed files, the Canon EOS R50 V and the Hasselblad X2D II 100C, and a run of decoder hardening, among them fixes for TALOS-2026-2330, -2331, -2358, -2359, -2363 and -2364. CAM-13 waits for LibRaw's next public snapshot, expected this autumn with Nikon's High Efficiency decoder, but that decoder ([#826](https://github.com/LibRaw/LibRaw/pull/826)) is still an open pull request, and RAWmakase shows the master commit is fit to ship on three platforms. Pinning it now, apart from CAM-12, gives the A7 V without waiting. The camera bench and the decode regression set would show what else it changes; whether it fixes the A1 II's black strip has to be checked.

**The per-camera exposure table** comes from Adobe DNG Converter's output, and stays out for the reason rawler's camera files did in the [RapidRAW study](rapidraw-findings.md#42-raws-cameras-and-colour). Whether Redlamp's default renders differ in brightness between bodies is a question for the camera bench, which compares each body with its own JPEG.

### 4.2 Colour, tone and edit stability

RAWmakase renders a raw as Camera Raw would render a DNG carrying only a colour matrix: LibRaw's matrix (the Adobe-derived coefficients) adapted to D50, the ACR3 default tone curve from the DNG SDK, and tone applied as the DNG SDK applies it. Its colour operators work in ProPhoto primaries as Camera Raw's do, and it clips to sRGB at output; there's no wide-gamut export. Redlamp keeps its own look, splits a DNG profile into calibration and a Base Look (TON-09), and keeps colours outside sRGB until the output.

On stability the two differ in kind. RAWmakase records an engine number and a model flag for each operator it has fitted (`contrast_model`, `gamut_model` and a dozen more), so an older edit keeps its earlier operators until the photographer runs Calibration › Process › Update; older releases refuse newer files rather than misreading them. But applying any preset moves an edit older than its process 3 to process 3, "so an old edit can change appearance beyond the settings applied". Redlamp's process versions keep every edit rendering as it did, and the process-stability gate checks it against recorded references.

### 4.3 The Develop interface

RAWmakase's interface is close to a copy of Lightroom Classic's, in a Lightroom-like palette of nine greys. Most of it Redlamp already has; the rest is the lesson.

| | RAWmakase | Redlamp |
| --- | --- | --- |
| Slider values | An egui `DragValue` 52 points wide: drag it to scrub, click to type; values beyond the range kept as imported | Every slider row shows its value and takes typed values with arithmetic (`x+15`), clamped as Lightroom clamps them (UX-01). No hover state, and the number can't be dragged |
| Controls without a value | None found | The 3-way Color Grading Luminance sliders and the wheels' Hue and Saturation; the tone curve's split handles and point Input and Output; Base Look Amount (shown, not typeable); mask overlay Opacity (shown, not typeable); the Refine Edge brush Size; the Luminance and Depth range stops |
| Nudging | Hover a slider and press Up or Down, Shift for ten | ⌘-scroll over a slider (UX-02); `,` and `.` choose a slider, `-` and `=` nudge it |
| Rails | Fill from zero for sliders that start at zero, else from the default with a tick; Temp, Tint and hue rails coloured | The same: fill from the origin, a tick on bipolar sliders, coloured Temp, Tint and Color Mixer rails |
| History | Each step names its value ("Exposure +0.35") | The same |
| Panel headers | Lightroom's on/off switch on eight panels, a reset button, Solo Mode | Solo Mode, the edited dot, reset from the header; no on/off switch |
| Histogram | Five drag regions; triangles toggle and preview clipping on hover; the pointer's R, G, B in Melissa RGB below | Five drag regions; triangles toggle clipping; no hover preview; the capture summary below, no readout |
| Tone curve | A readout of the point's Input and Output, typeable; the parametric regions dragged on the graph | Neither readout; region sliders and split handles |
| Before/After | Before alone, left/right, top/bottom, split; Copy Before's Settings to After, After's to Before, Swap; Before set from a History step or snapshot | Full frame, side by side (oriented automatically), a diagonal split; no Copy or Swap |
| Reference View, Targeted Adjustment Tool, Match Total Exposures, Red Eye, watermarks | All built | Reference View and the Targeted Adjustment Tool are planned in the Lightroom comparison without tracker rows; Red Eye is OTH-01; watermarks are planned without a row; Match Total Exposures appears nowhere |
| Opening a raw | The camera's embedded JPEG at once, while the raw develops | A spinner until the raw is ready |
| Status line | The render stage ("Draft • refining", "Fit • full quality"), GPU or CPU, and the time | Not needed: Fit renders are final in milliseconds |
| Masks and removal | Brush, linear, radial and range masks, Heal and Clone, all marked experimental | AI masks, content-aware Remove, Generative Remove, Remove Dust, edges solved per pixel |
| Accessibility | None | AppKit's controls; the custom slider rows have identifiers, no VoiceOver semantics |

The value field is where the two meet. Redlamp's is the more capable (arithmetic, units accepted, arrow-key stepping, a scenario that types `x+15`), but nothing about it says it can be edited, and it can't be dragged. RAWmakase's number does both: a drag scrubs it, a click types into it.

### 4.4 Interoperability and automation

| | RAWmakase | Redlamp |
| --- | --- | --- |
| Lightroom presets | Read; written in Lightroom's layout | Read, with a report of what maps (EDT-11, in progress); not written |
| Lightroom catalogs | Imported, read-only, with develop history | Not tracked |
| Lightroom sidecars | Read for metadata; never written | Import planned, never writing (EDT-12) |
| Adobe profiles | The photographer's own DCP and XMP looks, found in Camera Raw's folder | DNG profiles; the photographer's own DCPs deferred on 2 October |
| Lens profiles | The photographer's own LCP files | The photographer's own LCP files (LNS-04), but each used only on the body it was made on ([§9.3](#93-lens-profiles), 14 October) |
| Agents | A local control socket (off by default, a token in an owner-only file) and an MCP server of 16 tools inside the app; every edit can name the photo, generation and revision it expects, and is refused when they've moved | An internal MCP server for look development (EXT-01); a public one and App Intents planned (EXT-02) |
| MIDI | Core MIDI on macOS: controls mapped to sliders and actions, absolute and relative encoders, a Loupedeck+ profile, following the selected mask | None |

### 4.5 Positioning

RAWmakase competes as Lightroom Classic rebuilt in the open: free, on every desktop, measured against Camera Raw, with a catalog importer as the way out of Adobe. Redlamp competes as a native Mac app that a Lightroom user already knows how to use, whose edits never change, with private AI. RAWmakase makes one gap plain: a Lightroom user can bring their whole catalog to it and to no other open editor, and Redlamp can't take even their develop settings yet. Lessons 3 and 4 address that.

---

## 5. What to adopt

### 5.1 Value fields everywhere (lesson 1)

**Every control with a value shows it and takes a typed one** (UX-28): a value beside each 3-way Color Grading Luminance slider, each wheel's Hue and Saturation readable and typeable, the tone curve's selected point (Input and Output) and split positions in a readout row, Base Look Amount, mask overlay Opacity, the Refine Edge brush Size, and the four stops of the Luminance and Depth ranges. UI-only values (Opacity, brush Size) take a value field with a spec of their own, so the parameter catalogue, the MCP server and the sidecar schema don't change.

**The number reads as a field, and scrubs** (UX-29): with the pointer over it, a faint well and the left-right cursor (since 10 October the well always shows, subtle at rest, stronger under the pointer and darker while typing); a drag scrubs it in the slider's own scale (mireds for Temp), Shift for fine control as on the track, one History step per drag; a click without movement types, as today. Size S–M for both.

### 5.2 LibRaw master for CAM-13 (lesson 2)

Pin `4f01440` by its SHA in `config/vendored-libs.json`, as the raw pipeline document already allows, and run the camera bench and the decode regression set: the A7 V and the other new bodies should open, and any other moved file has to be explained. The A7 V's decoder was written to "match Adobe highlight handling", which the camera bench's comparison with the body's own JPEG will show. CAM-12 stays on its own: Nikon's High Efficiency decoder isn't in master. Size S.

### 5.3 A Lightroom parity corpus (lesson 3)

EDT-11 imports Lightroom presets today, but its "response curves fitted by rendering in both apps" wait on the owner's Lightroom renders. RAWmakase's corpus shows how to get them without photos anyone owns: synthetic chart DNGs of an invented camera, written by a script, rendered by Camera Raw or exported from Lightroom Classic with each setting, reduced to patch means. EDT-11's conversion of each Lightroom setting into Redlamp's is then fitted to those means, and a CI check fails when a conversion drifts from its recorded distance. Redlamp's sliders keep their own feel; what's fitted is the conversion, so a Lightroom preset looks the same in Redlamp. Size M, plus the owner's time to run the renders.

Whether Camera Raw's patch means may sit in the repository, as RAWmakase keeps them, is DEC-41. DEC-17 and DEC-19 let measurements of other software's output into Redlamp's tables, never their files.

### 5.4 Lightroom Classic catalog import (lesson 4)

Read a closed `.lrcat` (SQLite) without changing it, and write what it holds as Redlamp edits beside each photo: develop settings through EDT-11's converter, with its report, and ratings, flags and colour labels, which Redlamp already stores. Keywords, collections and virtual copies wait for the library track. Lightroom keeps develop settings as serialized Lua tables; RAWmakase reads them as data, never as code, which Redlamp must do too. Size L, after EDT-11.

### 5.5 Smaller Lightroom features (lessons 5 to 12)

- **Panel switches** (UX-30): the switch in the header of Tone Curve, Color Mixer, Color Grading, Detail, Lens Corrections, Transform, Effects and Calibration. Each toggle is a History step, stored with the edit in a new sidecar field that defaults to on, so existing edits render as before; a change in a switched-off panel turns it back on. Size M.
- **Before/After** (UX-31): the side-by-side's orientation by choice (`Y` left/right, `⌥Y` top/bottom, as the README's shortcut table already lists), Copy Before's Settings to After, Copy After's Settings to Before and Swap, and Before set from a History step or a snapshot. Size S.
- **Histogram** (UX-32): the R, G and B percentages of the pixel under the pointer, read from the render (not the screen), and a clipping preview while the pointer is over a triangle. Size S.
- **Opening** (UX-33): when a raw takes more than a moment to open (a large file, a slow disk), show its embedded JPEG, labelled Preview, until the develop is ready. Redlamp already decodes it for the filmstrip. Size S.
- **Lightroom presets out** (EDT-22): save a recipe as a Lightroom XMP preset, the settings that map converted back, with the same report EDT-11 gives on import. Size M.
- **Match Total Exposures** (EDT-21): set the other selected photos' Exposure so their aperture, shutter speed and ISO come out as bright as the open photo's, as one Undo step. Size S.
- **MIDI controllers** (EXT-03): Core MIDI input mapped to sliders and actions, absolute and relative encoders (64 as zero for bipolar sliders), a profile for a common controller, one History step per gesture, following the selected mask. Lightroom users drive Lightroom this way through [MIDI2LR](https://github.com/rsjaffe/MIDI2LR), a plug-in. Size M.
- **Rows for features already planned:** Reference View (UX-34, P4), the Targeted Adjustment Tool (UX-35, P2) and watermarks on export (EDT-25, P4) are in the Lightroom comparison as Planned, without a row to deliver them.

### 5.6 Smaller points

- **VoiceOver** (UX-36): slider rows as accessibility sliders, with their label, value and increment and decrement actions, as the command palette's slider bar already has. RAWmakase has nothing here; it is Redlamp's to win.
- **Target guards for EXT-02:** every mutating command names the photo, generation and revision it expects, and is refused when they've moved. It lets an agent and a person share one editor safely; it belongs in EXT-02's design.
- **Quit while work is pending:** RAWmakase routes ⌘Q, the Dock and logout through one guard that waits for exports and saves, and brings a minimised window forward to ask. Worth checking Redlamp does the same.
- **Measurement conditions:** RAWmakase's performance pages state the load average and the spread of every run, as `.cursor/rules/performance.mdc` asks of Redlamp's.
- **Opt-in usage statistics:** RAWmakase asks once, shows the exact report and sends it weekly, with no identifier. Not proposed: the README says Redlamp sends nothing about its users.

---

## 6. What not to follow

- **Adobe DNG SDK code in the app.** RAWmakase compiles the ACR3 tone table and the temperature table from the SDK's sources; Redlamp implements from the DNG specification, and the SDK's licence asks a commercial distributor to indemnify Adobe.
- **RAWmakase's fitted tables and camera exposures.** They are MIT-licensed, but derived from Camera Raw's renders and Adobe DNG Converter's output. Redlamp measures its own (5.3, under DEC-41).
- **Importing Adobe's profiles from Camera Raw's folder.** The photographer's own DCPs were deferred on 2 October; TON-09 keeps Redlamp's own look for new edits. Revisited in [§9.2](#92-camera-profiles) (14 October).
- **sRGB-only output,** and colours clipped to sRGB before the photographer sees them.
- **Edits that move to a newer engine when a preset is applied.**
- **Keyboard control that only works under the pointer,** and an interface without an accessibility tree.

---

## 7. Licensing

Read from GitHub's licence API and the repository's `licenses/` folder on 7 October 2026.

| Piece | Licence | Verdict for Redlamp |
| --- | --- | --- |
| RAWmakase | MIT | Could be adapted with attribution; it is Rust and egui, so its ideas carry over and its code doesn't |
| Its fitted tables (`src/develop/*.bin`, `*_data.rs`) | MIT, derived from Camera Raw's renders | Not used: Redlamp fits its own (DEC-41) |
| Its camera table (`data/cameras.toml`) | MIT, derived from Adobe DNG Converter's output | Not used |
| The ACR3 tone table and temperature table | Adobe DNG SDK licence: permissive, with notices, and indemnification for commercial distribution | Not used; Redlamp works from the DNG specification |
| LibRaw | LGPL-2.1 or CDDL-1.0 | Already Redlamp's decoder; the master commit changes nothing about its licence |
| Little CMS | MIT | Not needed: Redlamp uses ColorSync |
| Inter, Lucide | OFL-1.1, ISC | Not needed |

---

## 8. Decisions and tracker rows

**Decided by the owner on 7 October 2026:**

1. **The slider work, now** (UX-28, UX-29): a value on every control that lacks one, a field that shows it's editable, and a drag that scrubs. Nudging with Up and Down over a hovered slider stays out (UX-02's ⌘-scroll remains), and so does VoiceOver (UX-36, Proposed).
2. **The other lessons as Proposed rows,** for a decision later.

**Open:** DEC-41, whether Camera Raw's renders of Redlamp's own charts may be kept in the repository as patch means.

**Tracker rows:**

| ID | Item | Recommended | Phase | Size | Depends on |
| --- | --- | --- | --- | --- | --- |
| UX-28 | A value on every control that lacks one (accepted 7 October) | Adopt | P2 | M | UX-01 |
| UX-29 | Value fields that show they're editable and scrub when dragged (accepted 7 October) | Adopt | P2 | S | UX-01 |
| UX-30 | Panel on/off switches, saved with the edit | Adopt | P2 | M | — |
| UX-31 | Before/After: orientation by choice, Copy and Swap, Before from History or a snapshot | Adopt | P2 | S | — |
| UX-32 | The pixel's R, G and B under the histogram; clipping preview on hover | Adopt | P2 | S | — |
| UX-33 | The embedded JPEG while a slow raw opens | Adopt | P2 | S | — |
| UX-34 | Reference View | Adopt | P4 | M | — |
| UX-35 | Targeted Adjustment Tool | Adopt | P2 | M | — |
| UX-36 | VoiceOver for slider rows and value fields | Build | P4 | S | — |
| EDT-21 | Match Total Exposures | Adopt | P2 | S | EDT-08 |
| EDT-22 | Save a recipe as a Lightroom XMP preset | Adopt | P3 | M | EDT-11 |
| EDT-23 | Import a Lightroom Classic catalog, read-only | Adopt | P4 | L | EDT-11 |
| EDT-24 | A Lightroom parity corpus for EDT-11's conversions | Do better | P2–P3 | M | EDT-11, DEC-41 |
| EDT-25 | Watermarks on export | Adopt | P4 | M | — |
| EXT-03 | MIDI controllers | Adopt | P4 | M | — |

CAM-13 keeps its row, with the LibRaw master commit as its recommended route.

---

## 9. Second pass, 14 October 2026

**Subject:** RAWmakase 0.3.0 (13 October 2026) and `main` at `17b70e8a` (14 October 2026), 472 commits after the first pass, read from the same clone: the release notes of 0.2.1 to 0.3.0, `docs/lightroom-profiles.md`, `docs/lens-corrections.md`, `docs/parity-gaps.md`, `src/app/onboarding.rs`, `crates/rawmakase-model/src/lens/lcp.rs`, and pull requests #361, #405, #428, #429, #431 and #458. Redlamp's side was checked against the tracker, the Lightroom comparison and the code on 14 October. As before, nothing was run.

### 9.1 What changed in RAWmakase

Five releases in a week:

| Release | Date | What it added |
| --- | --- | --- |
| 0.2.1 | 7 October | The app split into bounded parts (#216); quitting saves the edit and asks before cutting off an export; Texture, Vibrance beyond ±50 and the black-and-white mix refitted to Camera Raw for new edits; values beyond a slider's range can be typed |
| 0.2.2 | 8 October | Select Subject, Sky and Background, marked experimental: DETR finds people, animals and sky and SAM 2 outlines them, both Apache-2.0, on the CPU, 270 MB downloaded on request (IS-Net and BiRefNet were turned down for their training data's licences); Lightroom's panel shortcuts (Tab, ⇧Tab, F6 to F8); Standard and 1:1 previews, which also let offline photos zoom; Sony custom white balance from each body's own calibration |
| 0.2.3 | 9 October | Canon sRAW and mRAW and Nikon's small raws; the A7R VI's calibration from Adobe DNG Converter; Lightroom catalogs over 1 GB |
| 0.2.4 | 9 October | A first launch opens a Photos catalog; a setup screen for Lightroom users finds their catalog, camera profiles, lens profiles and presets, each with an Import button |
| 0.3.0 | 13 October | A new layout; Synchronize Folder; a scene-referred tone stage fitted to Camera Raw, which moved the median distance from Camera Raw across its comparison sets from ΔE2000 1.73 to 1.48, and renders every existing edit anew; PNG export; colour noise reduction from each photo's own noise; more Adobe camera and lens profiles matched (#428, #429, #431, #458) |

Two things the first pass found have grown. RAWmakase's edits move: with 0.3.0 "existing edits render with the new engine and look different", and earlier releases refuse a catalog 0.3.0 has saved. And its way in for Lightroom users is now one screen, which brings Adobe's own profiles across with the catalog.

### 9.2 Camera profiles

**RAWmakase renders a Lightroom user's photos with their own copy of Adobe's profiles.** The photographer chooses `.dcp` and `.xmp` files (the Profile menu, Preferences, `rawmakase import-profiles`), or accepts what the Profile menu and the setup screen find in Camera Raw's folder (`/Library/Application Support/Adobe/CameraRaw`): each catalog camera's Adobe Standard and Camera Matching DCPs, the Adobe Raw looks under `Settings/Adobe/Profiles/Adobe Raw`, and the photographer's own DCPs for those cameras. The files are copied into its data folder; none ships with the app.

- **What renders:** an XMP look over its camera's DCP: the six Adobe Raw looks (Color, Portrait, Neutral, Landscape, Vivid, Monochrome), the creative looks (Artistic, B&W, Modern, Vintage), and the camera-matching XMPs that carry an RGB table. It decodes Adobe's big-table encoding (base85 and zlib) for HSV look tables and RGB tables (1D and 3D, interpolated tetrahedrally), and applies the look's own tone curve, the Profile Amount from 0 to 200% (fitted to Camera Raw: tables scale with it, a curve is applied twice at 200%, settings inside the look grow half as fast above 100%), and the develop settings a few looks carry (Exposure, Saturation, the colour mixer, the parametric curve, split toning, a vignette).
- **What it refuses, with a message:** adaptive and AI profiles, Fujifilm's camera-matching XMPs (their tables are kept elsewhere), looks that need a DNG's own RGB tables, and settings it doesn't apply inside a look.
- **Defaults:** a new photo opens in an imported Adobe Color, else Adobe Standard, else a DNG's own profile, else RAWmakase Color. Once a Lightroom user has imported Adobe's profiles, their photos open looking as they do in Lightroom.
- **Edits keep the profile:** the resolved tables are stored in each edit, so it renders without the files.
- **Matching:** Adobe's camera names are mapped to LibRaw's (26 of 270 validation photos had found no profile; 1 does now, #458), and phones' profiles for each camera module are chosen by focal length (#431).
- **Measured:** on six X100F photos, against Lightroom Classic's exports, Adobe Color came 20% closer than its Adobe Standard baseline, Neutral 52% and Portrait 3% (encoded sRGB, mean absolute error).

**Redlamp reads profiles that come inside DNGs, and nothing else.** TON-09 applies an embedded profile's matrices and HueSatMap (process 4), bakes its LookTable and tone curve into a Base Look offered under In This Photo, and applies Apple's ProfileGainTableMap with Apple's look (process 5). `DNGProfile` already parses `.dcp` files, but importing them (TON-09's third slice) was deferred on 2 October because the owner doesn't use DCP files, and the comparison lists custom `.dcp` profiles as Later. Adobe's XMP looks aren't read at all. The preset importer ignores `CameraProfile` and `Look` ([Lightroom presets](../recipes/lightroom-presets.md)), and the [Lightroom edits design](../plans/2026-10-13-lightroom-edits-design.md) of 13 October maps them by name to Redlamp's looks (Adobe Color to Color, and so on), noting that "Adobe's profiles are never read or converted". What Redlamp already has for it: a Base Look Amount from 0 to 200, as Lightroom's Profile Amount runs; LUT import; and DEC-73's route for Fujifilm's own LUTs, kept on the Mac they were imported on.

**This is now the largest gap for a Lightroom user, and the accepted work doesn't close it.** EDT-23 and EDT-12 bring each photo's settings across, and EDT-24 will fit how far each slider moves the photo; but EDT-24 measures each app's change from its own default render, which by design "takes the difference between the profiles out". Lightroom has opened raws in Adobe Color since 2018, so nearly every imported photo will look different in Redlamp before any slider is touched, by the distance between Adobe Color and Redlamp Color. RAWmakase closes that distance with the photographer's own files.

**Most of the engine work is done.** Calibration (the matrices and HueSatMap) is TON-09's first slice, a look as a Base Look its second, and the `.dcp` parser exists. What's new is Adobe's XMP encoding (documented by the DNG SDK's source and by RAWmakase's MIT reader), RGB tables, the Amount's rules, and a choice about the settings inside a few looks: carry them as offsets, or leave them out with a report. Redlamp's sliders stay Redlamp's: the photo starts as it looks in Lightroom, and how far each slider moves it is EDT-24's to fit.

**It needs the owner's decision, and perhaps counsel's.** It reverses the 2 October deferral, which was a preference, and the edits design's "never read or converted", which is a rule; and AGENTS.md says Redlamp never ships or converts Adobe's files. Reading the photographer's own installed profiles to render their photos is neither shipping nor converting. Baking one into a Base Look on their Mac is close to what TON-09 already does with profiles inside DNGs, many of which are Adobe Standard, written by DNG Converter. Storing Adobe's tables in a sidecar that travels with the photo, as RAWmakase stores them in its edits, would be distributing them. DEC-73 is the model: the photographer's own files, used on the Mac they're on, never bundled, never in exported recipes or `.cube` exports; the sidecar names the profile and never holds its tables, and where the profile isn't on the Mac (another Mac, a photo someone shared) Redlamp's look of the same name stands in, with a notice. The DNG specification gives every profile an embed policy (ProfileEmbedPolicy: allow copying, embed if used, embed never, no restrictions), and Redlamp can honour it. Lightroom Classic and Photoshop's Camera Raw install the profiles; whether Adobe's free DNG Converter installs them too wasn't checked here.

### 9.3 Lens profiles

**The first pass called the two the same; they aren't.** Both read the photographer's LCP files with a reader of their own, but RAWmakase uses Adobe's collection as Lightroom does, and Redlamp in practice can't.

| | RAWmakase | Redlamp |
| --- | --- | --- |
| Where profiles come from | Files imported by a command or the CLI, copied into its data folder; the setup screen takes Camera Raw's `LensProfiles/1.0` folders for the catalog's camera makers and 12 third-party brands, and the user's own `LensProfiles` | Only `~/Library/Application Support/Redlamp/Lens Profiles/`, filled by hand (LNS-04); nothing looks in Camera Raw's folders |
| Which body's profile | Any body whose sensor covers the photo's: the photo's own make first, then makes sharing a mount (L-mount: Sigma, Panasonic, Leica; Micro Four Thirds: Olympus, OM System, Panasonic), then any make; a smaller sensor's profile is refused (`make_rank`) | Only a profile made on the photo's own body: `LCPProfileLibrary.correction` keeps the sub-profiles whose camera matches, and a test holds it ("another lens, camera or make … gives no correction") |
| A file that names no lens | Nikon's matched by the maker note's lens ID (#429: a D600's photo takes Adobe's profile made on a D3) | No correction |
| Choosing by hand | Lightroom's Setup (Default, Auto, Custom), Make, Model and Profile menus; Custom for an adapted or manual lens; `crs:LensProfileSetup`, `LensProfileName`, `LensProfileFilename` and `LensProfileDigest` read and written; a named profile that isn't imported is reported with what stands in | None. The panel names the matched profile (LNS-11), and the preset importer notes `LensProfileSetup` and `LensProfileName` without acting on them |
| The model | Rectilinear distortion, lateral chromatic aberration and vignetting, interpolated in focal length and aperture at the farthest focus distance; PreferMetadataDistort honoured; no fisheye | The same model (Chen et al., 2010) and interpolation; fisheye profiles skipped and reported; no tangential terms or focus distance |
| Built-in corrections | Fujifilm, Sony and DNG | Sony, Fujifilm and DNG, with Panasonic and OM System accepted for 0.3.2 (LNS-02). Redlamp's Sony reader takes the stated count and ignores the padding after it, so RAWmakase's #405 doesn't apply |
| Checked against Camera Raw | 8 A7 II photos with profile corrections on: 0.0088 mean absolute error, corners within ±0.02 EV | The Sony sample's frame edge against the camera's JPEG (LNS-02) |

Adobe makes each lens's profile on one body or a few (its files are named for them, as `NIKON D3 (Nikon AF-S VR Micro-Nikkor 105mm f2.8G IF-ED) - RAW.lcp`), and Lightroom applies it to other bodies. With Adobe's files, Redlamp corrects a lens only on the body Adobe happened to use. That leaves out the photographers LCP files serve most: Canon, Nikon and Pentax users, whose raws carry no correction Redlamp reads, and anyone with an adapted or third-party lens. Matching across bodies changes the render of any existing edit whose Lens Profiles folder holds such a profile, so it comes with a new process version.

### 9.4 One place to bring Lightroom across

RAWmakase's setup screen opens on a first launch when Lightroom's catalog (`~/Pictures/Lightroom`) or Camera Raw's folders are on the Mac, and later from the catalog menu: the catalog, camera profiles, lens profiles and presets, each with what was found and an Import button. Redlamp has or plans each piece in a different place: presets in the Recipes panel (EDT-11), the catalog's metadata (LIB-29, in progress) and its edits (EDT-23, planned as File › Import from Lightroom Classic…), sidecars (EDT-12), lens profiles by hand, camera profiles not at all. EDT-23's import window can be that one place: it finds the catalog, the presets in Camera Raw's `Settings` folder and, with the decision in 9.2, the profiles and lens profiles, and imports each on its own.

### 9.5 Smaller gaps

- **Small raws.** RAWmakase has opened Canon sRAW and mRAW and Nikon's small raws since 0.2.3, checked against the cameras' JPEGs. Redlamp's decoder takes LibRaw's three- and four-colour buffers as linear RGB (`RawDecoder`), so they may open, but the camera bench's seed run left reduced modes out, no sample is in the decode suite, and Sony's YCbCr files, the nearest case, render magenta (CAM-21). A raw.pixls.us sample of each through the camera bench would say.
- **Sony white balance by body.** Bodies of one Sony model differ. Adobe's DNG Converter writes a calibration for each body, Camera Raw renders a custom Temperature and Tint with it, and RAWmakase now reads it from the file's own daylight preset (#361: custom white balance on two A7CR bodies at a median ΔE2000 of 0.45 to 1.01 from Camera Raw). Redlamp's Temperature and Tint come from the model's matrix, the same for every body, so two bodies may render the same setting differently. It matters for a shoot with two bodies, and for EDT-23's "same neutral for the same temperature and tint"; raws of one grey card from two bodies would show whether it's worth a row.
- **The Targeted Adjustment Tool** is built in RAWmakase (the tone curve's regions, the Color Mixer and the black-and-white mix); Redlamp's UX-35 is Proposed.
- **Fisheye lens profiles:** neither app reads them. The Adobe Camera Model paper LNS-04 follows describes the fisheye model too.
- **Not gaps:** RAWmakase's AI masks (Subject finds people and animals only) are behind Redlamp's; Point Color, the point curve's presets and the panel switches are in both.

### 9.6 Where the first pass's rows stand

| State | Rows |
| --- | --- |
| Done | UX-28, UX-29, UX-30, UX-32, CAM-13 |
| Accepted, not started | UX-39; EDT-23 and EDT-24 (13 October) |
| Proposed | UX-31, UX-33, UX-34, UX-35, UX-36, EDT-21, EDT-22, EDT-25, EXT-03 |
| Open decision | DEC-41, which EDT-24 has waited on since 13 October |

### 9.7 Recommendations

| # | What | Needs | Phase | Size |
| --- | --- | --- | --- | --- |
| 1 | **Lens profiles across bodies:** a profile of the photo's lens made on another body whose sensor is at least as large, preferring the photo's body, then its make, then makes sharing the mount; the lens ID where the file names no lens; camera names compared as LibRaw's canonical names; from a new process version | — | P2 | S |
| 2 | **Choosing a lens profile by hand:** Lightroom's Setup, Make, Model and Profile menus, listing the profiles on the Mac that cover the photo's sensor; the choice stored by name and file name, as `crs:LensProfileName` and `LensProfileFilename` store it, so imported Lightroom edits keep theirs | 1 | P2 | M |
| 3 | **Lens profiles where Adobe installs them:** Camera Raw's `LensProfiles/1.0` and the user's `LensProfiles`, read where they are, beside Redlamp's folder; the panel says which folder a profile came from | The decision below; 1's process version | P2 | S |
| 4 | **The photographer's own camera profiles:** `.dcp` import (TON-09's third slice), then Adobe's XMP looks over their camera's Adobe Standard (the six Adobe Raw looks first, the creative looks after) with the Amount, chosen in the Base Look menu, kept on the Mac as DEC-73 keeps Fujifilm's LUTs | The decision below | P2 | L |
| 5 | **Imported Lightroom edits use them:** a converted edit naming Adobe Color renders with the photographer's Adobe Color when it's on the Mac, else Redlamp's Color, as the design maps it now, with the report saying which | 4, EDT-23 | P4 | S |
| 6 | **One import window for Lightroom:** EDT-23's window finds the catalog, Camera Raw's presets and, with the decision, the profiles and lens profiles | EDT-23 | P4 | S |
| 7 | **Small raws through the camera bench:** Canon sRAW and mRAW and Nikon's small raws, refused or fixed as the bench finds | — | P2 | S |
| 8 | **Fisheye lens profiles,** from the Adobe Camera Model paper | 1 | P3 | M |
| 9 | **Sony white balance by body:** a check on two bodies of one model, then each body's own calibration if they differ | — | P3 | S |

**Decided by the owner on 14 October 2026:**

1. **Adobe's profiles on the photographer's Mac** (a new decision row, DEC-85): yes, camera and lens profiles both, read where Lightroom Classic or Camera Raw installs them or from files the photographer chooses, on DEC-73's terms: used on that Mac, never bundled, never in exported recipes, `.cube` exports or sidecars, each profile's embed policy honoured. Counsel is asked whether Adobe's terms for the installed profiles allow it, as DEC-73 asked about Fujifilm's.
2. **All nine recommendations, as Accepted rows,** and UX-35, the Targeted Adjustment Tool, accepted.
3. **DEC-41:** yes, as numbers only.
4. **After the review in 9.8:** recommendations 1 and 3 join the process version planned for 0.3.2, with CAM-29, DN-12 and LNS-02's Panasonic and OM System corrections; recommendation 4's two parts, `.dcp` profiles and Adobe's XMP looks, are both Phase 2; EDT-23 comes in the releases right after 0.3.2, with recommendations 5 and 6 and versions (EDT-09, LIB-48), everything but masks and spots; raw defaults (EDT-06) may choose the photographer's own Adobe Color; ARC-16 stays Proposed.

**Rows,** with the IDs free on 14 October:

| ID | Recommendation | Phase | Size | Depends on |
| --- | --- | --- | --- | --- |
| DEC-85 | Adobe's camera and lens profiles on the photographer's Mac *(counsel)* | — | — | — |
| LNS-14 | 1, lens profiles across bodies, in 0.3.2's process version | P2 | S | LNS-04 |
| LNS-15 | 2, choosing a lens profile by hand | P2 | M | LNS-14 |
| LNS-16 | 3, lens profiles where Adobe installs them, in 0.3.2's process version | P2 | S | LNS-14, DEC-85 |
| LNS-17 | 8, fisheye lens profiles | P3 | M | LNS-04 |
| TON-51 | 4, the photographer's own `.dcp` profiles (TON-09's third slice) | P2 | M | TON-09, DEC-85 |
| TON-52 | 4, Adobe's XMP looks over their camera's Adobe Standard | P2 | L | TON-51 |
| EDT-33 | 5, imported Lightroom edits in the photographer's Adobe profile | P4 | S | EDT-23, TON-52 |
| EDT-34 | 6, one import window for Lightroom | P4 | S | EDT-23, LNS-16, TON-51 |
| CAM-33 | 7, small raws through the camera bench | P2 | S | CAM-14 |
| CAM-34 | 9, Sony white balance by body | P3 | S | CAM-14 |

### 9.8 A reviewer's side-by-side

On 14 October the owner heard of a video review that compared the two apps. It preferred Redlamp for its speed and interface, found RAWmakase's colours slightly better, and brought a Lightroom catalog into RAWmakase with its collections and edits. The video wasn't watched for this study, so its camera and photos are unknown; what follows is what the code and the tracker say could explain it.

**Colour.** Four differences, any of which a side-by-side would show:

- **Edited against unedited.** RAWmakase converts a catalog's develop settings along with its collections. Redlamp's import (LIB-29) brings the metadata and collections and lists the edits without converting them (EDT-23). Photos from a Lightroom catalog show their Lightroom edits in RAWmakase and Redlamp's defaults in Redlamp.
- **The profile.** RAWmakase's setup screen imports the photographer's Adobe profiles with the catalog, and photos then open in Adobe Color, or in the profile each edit names; without them, RAWmakase Color makes hue shifts of the same kind (reds, skin, yellows, foliage, aqua, sky). Redlamp Color is the camera's matrix and Redlamp's tone curve, with no look table. For raws other than DNGs, nothing corrects the 3 × 3 matrix's errors per camera, as Adobe Standard's HueSatMap does (on the Pixel 4a it moved the render by a mean ΔE2000 of 3.0, worst patch 6.1), and nothing shifts hues for taste, as Adobe Color does.
- **Brightness by camera.** RAWmakase sets each body's exposure from a table of 180 bodies. Redlamp applies a DNG's BaselineExposure and nothing for other raws, and the camera bench finds its default 1.7 stops darker than the Canon 5D Mark IV's own JPEG, 2.2 stops darker than the R6 Mark III's, and up to ±0.9 EV from Fujifilm bodies' (CAM-29, TON-14). A darker render reads as duller colour.
- **Bright colours.** Redlamp's tone map takes bright colours towards white with their hue kept (TON-02, TON-03). Camera Raw clips each channel, and RAWmakase clips as Camera Raw does, which keeps bright skies, flowers and lit skin more saturated.

Which of these the reviewer saw would take their photos, or ARC-16's comparison with Lightroom, which stays Proposed. What's planned addresses each: EDT-23 after 0.3.2; TON-51, TON-52 and EDT-33 for the profile, with EDT-06's raw defaults able to open new photos in the photographer's Adobe Color; CAM-29 in 0.3.2 for brightness; TON-14's chart matrix solve for Redlamp's own correction per camera. Bright colours are a matter of Redlamp's look, left as it is.

**The catalog.** Redlamp isn't at RAWmakase's point yet:

| From a Lightroom Classic catalog | RAWmakase | Redlamp |
| --- | --- | --- |
| Folders, ratings, flags, labels, keywords, descriptive metadata | Brought across | Brought across (LIB-29, on main since 11 October) |
| Collections | Brought across | Brought across with their sets, and the smart collections whose rules map (LIB-29) |
| Develop settings | Converted | Listed, not converted (EDT-23, after 0.3.2) |
| Masks and spots | Converted; AI and colour range masks reported and left out | After EDT-23's first delivery, once the test catalog checks their placement |
| Virtual copies | Brought across | Listed (EDT-09 and LIB-48, with EDT-23) |
| History steps | Brought across | Left out by the edits design, and counted |
