# Sky offers its models (MSK-37)

27 October 2026. The owner's decisions, from the chat that found the problem.

## What happened

On a MacBook Air with a fresh install of 0.3.4, the first Sky mask left chunks of an obvious sky unmasked. Sky is made by Segment Anything 2.1, with Depth Anything 3 when it's there too (`RedlampEngine.modelSky`), but only once they've been downloaded. Without them it falls back to the classical estimate (`SkyEstimator.estimate`), which grows sky down from the top edge as one connected region of smooth, bright, sky-coloured pixels at 512 px. Sky that objects cut off from the top (below a walkway, between a pylon's struts, behind wires) is never reached, and `SkyMatte` only takes walled-in sky back where a model saw some.

Nothing offers the models for Sky: `modelID(for: .sky)` is nil, so `modelNeeded(for: .sky)` never asks, and Settings › Models and the manual say Sky uses models built into macOS. A Mac where the models were downloaded for Objects or from Settings › Models never shows the difference.

Through `redlamp mask` on 12 of the evaluation set's sky photos, with `REDLAMP_SKY_METHOD=classical` against the default: the estimate left out 70% of the models' sky on sky-leafy-trees-01 (8 chunks, below a walkway), 56% on sky-wires-01 (51 chunks, between a pylon's struts), 13% on sky-overcast-02, 10% and 9% on sky-leafy-trees-03 and -04, and 0.1% to 2.5% on the rest. The bake-off (MSK-17) measured the same gap: IoU 0.898 against 0.945, and on the edge benchmark, after `SkyMatte`, 0.800 against 0.988.

## Design

- **The engine names the models that make a mask better.** `EditingEngine.modelsImproving(_:)` lists the downloadable models that improve a mask kind without being needed for it, and aren't on this Mac yet. For Sky: Segment Anything 2.1, then Depth Anything 3, each only if offered to everyone (cleared, not evaluation only), published and fitting this Mac. None for a photo with an iPhone sky matte, which Sky uses instead. The protocol's default is none.
- **Picking Sky asks once.** Choosing Sky in the mask picker or Create New Mask, while either model is missing, shows the download notice worded as an offer: the models' names, their size together (416 MB for both), what they find that the estimate doesn't, that they run on this Mac and can be removed in Settings › Models, and their licence. With one already here, it offers the other.
  - **Download** fetches the missing models in turn, with one progress bar weighted by size, then makes the Sky mask with them. A failed download says which and makes no mask, as for any model; the offer comes back the next time.
  - **Not Now** makes the Sky mask with what's on the Mac (the estimate) and is remembered in the user's defaults: on this Mac the offer isn't made again. Settings › Models has the downloads any time.
- **Only picking Sky asks.** Mask presets, Update AI Masks, Paste and Sync use what's on the Mac without asking.
- **The required-model question is untouched.** The offer is its own state (`offeredModels`) beside `pendingModel`, sharing its notice and its identifiers (`masks.download`, `masks.download.notNow`).
- **The copy says what Sky uses.** Settings › Models' footer, Segment Anything 2.1's purpose and the manual's AI masks chapter (and its facts) stop saying Sky uses models built into macOS.
- **Nothing renders differently.** Existing Sky masks keep their bitmaps; Update AI Masks recomputes them with whatever is on the Mac, as before. No process version.

## Steps

1. A workstream canvas (`ws-sky-model-offer`).
2. The tracker row MSK-37, and this plan, committed on branch `sky-model-offer`.
3. Engine: `modelsImproving(_:)` in `RedlampEngineAPI/Sources/EditingEngine.swift` (with its default) and `RedlampEngine/Sources/RedlampEngine+Models.swift`, its choice of models a static function tested in `RedlampEngine/Tests`.
4. Editor: `offeredModels`, `asksBeforeMaking(_:)`, `downloadOfferedModels()`, `declineOfferedModels()` and the Not Now flag (`app.redlamp.skyModelsDeclined`, in `library.defaults`), tests first in `RedlampUI/Tests/MaskEditingTests.swift`: Sky without the models offers them and makes nothing yet; Not Now makes it and isn't asked again; Download fetches each, then makes it.
5. Notice and picker: the offer's wording and buttons in `ModelDownloadNotice` (`MaskingPanel.swift`), the picker staying open while it's asked (`MasksPanel.swift`), the panel's messages (`MasksPanelView.swift`), the activity log (`ActivityRecorder.swift`), and the offer cleared when another photo opens (`EditorModel.swift`).
6. Copy: `ModelsSettings.swift`, `sam2.1-tiny.json`'s purpose, `docs/manual/content/masking/ai-masks.md` and `docs/manual/facts/masking.md`.
7. Scenario: the Sky step of `MasksPanelScenarios` answers Not Now when offered, and `pick` waits for an offer as it does for a download's question.
8. Checks: SwiftFormat; RedlampEngine's and RedlampUI's suites on the build Mac; `scripts/roadmap-sync.py`; the regression suite's smoke tier.
