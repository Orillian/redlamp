# Sony white balance by body: design (CAM-34)

**Status:** proposed on 30 October 2026, for the owner's approval before anything is built. It follows the study, [CAM-34-sony-wb-by-body.md](../research/notes/CAM-34-sony-wb-by-body.md), whose numbers it relies on, and waits on the owner's grey card raws, which check that the presets' differences are the bodies' own.

## Goal

One Temperature and Tint gives every body of a model one neutral, as in Camera Raw: from process 20, each body's calibration, the model's reference over the daylight preset the body stores in its raw, enters the conversion between Temperature and Tint and a balance. Edits made before process 20 render as they do today.

## Decisions for the owner

1. **Whether to build it,** with what the grey card raws show beside the study.
2. **Where the references come from** (study, section 6):
   - *Adobe's,* RAWmakase's table of 50 Sony references (MIT, its licence in `LICENSES/` and its source named beside the table), each reproducing DNG Converter's calibrations of the model's bodies exactly. They are numbers measured from DNG Converter's output on public files, as LibRaw's colour matrices are, and nothing of Adobe's is read or shipped. Bodies of a model then agree with each other and with Lightroom. *The lean.*
   - *Measured again* with DNG Converter on raw.pixls.us's CC0 samples, on the owner's Mac: the same numbers, made here.
   - *Redlamp's own,* each model's median public body: bodies agree with each other, not with Lightroom, and a model with one public body is calibrated relative to that body.
3. **Scope:** Sony ARWs, and a DNG's own CameraCalibration in Temperature and Tint from the same process (*the lean*: a DNG Converter DNG of a calibrated body has the same dependence on the body today, and the calibration is in the file); or Sony ARWs only. Canon, Fujifilm, Olympus and OM System bodies are calibrated by Adobe from presets of their own (Daylight or Shade, D65, 5300 K); each would be a row of its own on this design, after it.

## What changes

1. **The preset in the decode.** A shim accessor for LibRaw's `color.WB_Coeffs` (`rl_wb_coeffs`, `vendor/shims/redlamp_libraw.h`, which rebuilds the framework); `RawDecoder` keeps the daylight preset of a non-DNG raw as `DecodedImage.daylightPreset` (green 1), carried in the decode service's header, checked by `Header.isValid` (finite and positive) and recorded in the decode goldens, where only the Sony samples' records gain it.
2. **The references.** `Resources/UnitCalibrations.json` beside `ExposureAnchors.json` in RedlampEngineAPI, read by a table like `ExposureAnchorTable`: make, LibRaw's canonical model (`ImageInfo`'s, as lens profiles match), the models sharing its reference, the preset and the reference. A body whose model has no row, or whose file has no usable preset, keeps no calibration; nothing borrows another model's.
3. **The calibration.** `CameraColorModel(xyzToCameraRowMajor:calibration:)` takes a diagonal calibration, so that XYZ to camera is calibration × matrix, as the DNG specification's CameraCalibration × ColorMatrix; its two directions, `multipliers(for:)` and `whiteBalance(forCameraNeutral:)`, both use it. The camera-to-working matrix stays the model's: for a diagonal calibration, balancing by the calibrated neutral already gives the reference body's balanced camera RGB.
4. **Process 20.** `ImageSession` keeps the model with and without the calibration and chooses by the edit's process: `whiteBalanceRatio(for:)` uses the calibrated one from process 20. `EditRecipe.currentProcessVersion` becomes 20, with its row in the sidecar format and the schema's maximum. The pyramid doesn't change, so there is no raw revision.
5. **The numbers shown, by the edit's process.** As Shot's Temperature and Tint (`ImageInfo.asShotWhiteBalance`) for the edit's process, so that leaving As Shot doesn't jump; and Auto and the eyedropper given the edit (`EditingEngine.autoWhiteBalance(for:)`, `whiteBalance(sampledAt:for:)`), so that an edit made before process 20 still gets a neutral its own process renders as neutral. Their callers: `EditorModel` (white balance modes, the selector, resets, matching As Shot), Copy Settings, Sync, recipes, the command palette, `RecipeRenderer` and the CLI.
6. **DNGs,** if chosen: from process 20 the model's matrix is AnalogBalance × CameraCalibration × ColorMatrix, the D65 calibration's, where today it leaves CameraCalibration out (`RawDecoder.dngColorMatrix`).

## What renders differently

From process 20 only, and only a custom white balance (a Temperature and Tint, the presets, Auto and the selector) on a raw whose body has a calibration: its neutral moves by the body's calibration, a median 2.7 ΔE2000 for the study's 107 Sony bodies. As Shot renders don't change at any process; Auto and the selector render the same neutral, with other numbers. Every other camera renders at 20 as at 19. New edits start at process 20; an older edit moves to it only when its process is changed, as every process version works.

## Tests

- **The calibration:** a unit test that a body's multipliers for one Temperature and Tint are the reference body's times its preset over the reference, and that Temperature and Tint survive the round trip through a calibrated model.
- **Two bodies, one neutral:** the public a7R III pair (study, section 3) added to the decode suite, which has only the a7 IV's two samples of Sony's today: at one Temperature and Tint their balances are the same at process 19 and differ by exactly their presets' ratio at process 20, which makes one grey card neutral on both; at As Shot each renders as before.
- **The grey card:** the owner's raws, if he publishes them, or the measurement recorded in the study if he doesn't.
- **Older edits:** `ProcessStabilityTests` passing at every version from 1 to 19, and process 20's references recorded (`TEST_RUNNER_REDLAMP_RECORD_PROCESS_GOLDEN=1`, which writes only missing ones); Auto, the selector and leaving As Shot on an edit at process 19 giving its own process's neutral.
- **The decode:** the decode goldens regenerated, with only the Sony samples' records gaining the preset; the camera bench on the bodies measured.
- **Through the app:** a regression scenario that, through the user's own input, sets one custom Temperature and Tint on the two a7R III bodies' photos with Sync and finds each balanced by its own body's calibration.

## Cost

About three to four days of agent work, more than the row's S: the decode and its goldens half a day; the references, their table and licence half a day; the calibration, the per-process models and the numbers shown by the edit's process, with their callers, one and a half days; process 20, its references and the tests half a day; DNGs a quarter of a day; the scenario, the camera bench and the docs (`docs/raw-pipeline.md` §9 and §11, the sidecar format, the known gaps) half a day. No measurable cost in rendering: one diagonal more where a balance is worked out. Process 20 is the next process version for every new edit, so any other rendering change that comes before its release joins it, and its references are recorded once.

## Risks

- **A reference that's wrong for a model** moves every body of it; each one reproduces DNG Converter's calibrations of the model's sampled bodies exactly, and a model without one keeps today's rendering.
- **A body whose preset doesn't describe its sensor** would be moved the wrong way; that's what the grey card raws check, and Adobe calibrates every body this way.
- **The numbers people know change:** As Shot's Temperature and Tint, and Auto's, read differently from process 20, as Lightroom reads them for the same photo.
