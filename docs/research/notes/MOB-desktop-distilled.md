# MOB-01: the Mac editor, distilled for the iPhone

Written by the desktop distiller of the mobile UX team (an agent), on 13 October 2026, for MOB-01 ([#406](https://github.com/pdcgomes/redlamp/issues/406)), the iPhone design study.

## In short

- **116 capabilities** of the Mac editor are inventoried below: Develop, and the parts of Library a phone edit touches. **12 go on the editor's first level (T1), 74 inside a module (T2), 26 behind search or the More menu (T3), 4 to iPad and Mac, and none are left off the phone.** Fourteen more that are planned on the Mac are placed the same way in a table of their own.
- **Nine modules, plus an Auto button, keep everything without crowding the screen:** Looks, Light, Colour, Effects, Crop, Masks, Remove, Detail and Optics. Each module shows its common sliders first and folds the rest into named groups, so the depth is a tap away rather than gone. History, Versions and Snapshots share one sheet from the top bar.
- **The modules depart from the Mac's panel order in four places**, each for a reason given below. Basic splits three ways: tone into Light, white balance, Vibrance and Saturation into Colour, and Texture, Clarity and Dehaze into Effects. Transform and Upright join the crop tool. Copy, paste and recipes all live in Looks, as ways to bring in settings from somewhere else. Detail and Optics move to the end of the bar, because photographers set them once or leave them at their defaults.
- **Four capabilities go to iPad and Mac, each for a stated reason.** Keyboard shortcuts need a keyboard. The Lens Profiles folder is file management. Auto Sync needs a multi-photo selection visible while editing. Focus stacking needs tens of camera frames, memory and time.
- **Lightroom Mobile lacks several things Redlamp would keep:** Point Color, the Calibration sliders, colour labels, Red Eye, Background, Object and People masks in its masking tools (offered instead through Quick Actions), reference view, RGB readouts, and full history ([Q1](#sources)). Keeping all of them is affordable once they sit in folded groups or behind More.
- **Five Mac interactions have no direct phone equivalent, and each gets a stand-in.** Hover previews become press-and-hold or scrolling previews. ⌥-drag clipping becomes a second finger resting on the photo. Scroll-wheel zoom becomes pinch. Keyboard stepping becomes ± buttons with a haptic tick. The ⌘K palette becomes a search field that keeps its "exposure 0.7" syntax. Eyedroppers and point handles need a loupe offset above the finger.
- **Everything about the edit carries over unchanged:** the parameter catalog (names, ranges, defaults), the sidecar format, process versions, recipes and looks. Two things could still stop a Mac edit from rendering the same on the phone. One is a resource that lives only on the Mac: a lens profile, an imported LUT, or Fujifilm's personal-use LUTs. The other is the question of where a Photos-library photo's edit is stored. Both are questions for the owner.

## How it was done

- **Redlamp.** I read the code on `main` on 13 October 2026: the parameter catalog (`packages/RedlampEngineAPI/Sources/ParameterSpec.swift`), the panels (`packages/RedlampUI/Sources/Model/EditorTypes.swift`, `Inspector/ReferencePanels.swift`, `Inspector/BasicPanel.swift`, `Inspector/ColorPanels.swift`, `Inspector/CropToolPanel.swift`, `Inspector/HealToolPanel.swift`), the panel switches (`packages/RedlampEngineAPI/Sources/PanelSwitches.swift`), the action registry (`packages/RedlampUI/Sources/Shortcuts/ShortcutAction.swift`), the README's "What works today" and Roadmap, `docs/lightroom-comparison.md`, `docs/recipes/sidecar-format.md`, and the UX-17 and UX-30 notes.
- **Lightroom Mobile.** Adobe's help pages refused automated requests on 13 October 2026: `helpx.adobe.com/lightroom-cc/using/edit-photos-ios.html` and `…/masking-mobile.html` both returned HTTP 403. Instead I used The Lightroom Queen's comparison table, which has a Mobile column and was updated on 9 October 2026, and her release posts from May 2024 to August 2026. Section 20 of `docs/lightroom-feature-inventory.md` gives the edit tabs; it was written from working knowledge as of mid-2025, so claims taken only from it are marked (unverified). I haven't used Lightroom Mobile myself.
- **Apple Photos on iOS.** I used Apple's iPhone User Guide, whose current edition is iOS 27; for the Adjust tool, the iOS 26 edition has the same text. For PhotoKit I used Apple's developer documentation.
- **Frequencies are my assessment.** I judged them from three things: what the two phone apps offer and how prominently, what a photographer editing a phone or camera photo for sharing reaches for, and how often the setting is left at its default. No usage data was available. The Evidence column gives the facts, and the On a phone column gives my assessment.

## Tiers

| Tier | Where it sits |
| --- | --- |
| **T1** | On the editor's first level, one tap or one gesture from the photo: the module bar, the top bar, and gestures on the photo |
| **T2** | Inside a module, or inside one of the editor's own sheets (History, Share). A **folded group** is a named, collapsed section at the end of a module; it still counts as T2 |
| **T3** | Behind search, the More (⋯) menu, a long-press menu, or a module's own More |
| **iPad and Mac** | Left off the iPhone for a stated reason: precision, screen size, keyboard or file management |
| **Not on a phone** | Left off everywhere but the Mac for a stated reason. None is proposed |

In the tables, **LrM** means Lightroom Mobile on iPhone and **Photos** means Apple Photos on iOS. Bracketed labels such as [Q1] and [A2] point to the [Sources](#sources).

## The inventory

### 1. The editor's frame: viewing, history and search

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 1.1 | Open a photo (Folders panel, filmstrip, ⌘O) | Often | LrM imports from Photos, "but not organization" [Q1]; Photos opens on its library, with filters such as Edited and Rating [A9] | T1 | The Photos library is the starting point, with its albums, smart albums such as RAW, Depth Effect and Live Photos [P3], and its filters. A tap opens the editor. Folders stay on the Mac |
| 1.2 | Next and previous photo (filmstrip, ← →) | Sometimes | LrM has a filmstrip (unverified) | T2 | A filmstrip pulled up from the bottom edge of the photo. Swiping sideways at Fit is Photos' habit, but it would clash with panning and with the tools, so it isn't proposed |
| 1.3 | Zoom and pan: Fit, Fill, 1:1, 2:1, click to zoom, wheel and pinch | Often | Photos pinches, zooms and pans in Clean Up [A3] | T1 | Pinch to zoom, and double-tap to switch between Fit and 1:1. Inside a tool, two fingers pan, because one finger draws |
| 1.4 | Navigator (left panel) | Rarely | Neither app describes one [A1] | T1 | A small map in a corner, shown only while zoomed. Dragging its frame pans the photo |
| 1.5 | Before / After (`\`) | Often | Photos: tap the photo to compare [A4]. LrM: press and hold (I20, unverified) | T1 | Press and hold the photo, which leaves a tap free to hide the controls |
| 1.6 | Before / After layouts: Side by Side and Diagonal Split (`Y`, `⇧Y`) | Rarely | LrM has a Before/After preview [Q1] | T3 | A layout menu in More. Side by Side becomes top and bottom while the phone is held upright |
| 1.7 | Lights Out, Full Screen Preview, Hide All Panels (`L`, `F`, ⇥) | Sometimes | — | T1 | A tap on the photo hides every control, and another tap brings them back |
| 1.8 | Info overlay (`I`) | Rarely | — | T3 | In More |
| 1.9 | Histogram with clipping indicators | Sometimes | LrM: "Histogram only" [Q1]. Photos: the guide describes none [A1] | T2 | At the top of Light, folded by default to save height |
| 1.10 | Drag the histogram to set Blacks, Shadows, Exposure, Highlights or Whites | Rarely | — | T2 | Once the histogram is open it works well for a finger: drag a region sideways, with the name of the slider it moves shown above the finger |
| 1.11 | Clipping overlay (`J`), and ⌥-drag on a tone slider | Sometimes | LrM shows clipping with a second finger (unverified) | T2 | A clipping switch on the histogram. While dragging Exposure, Highlights, Shadows, Whites or Blacks, a second finger resting on the photo shows clipping, where ⌥ does on the Mac |
| 1.12 | Show Sensor Clipping (`⌥J`) | Rarely | Neither app has it | T3 | In More |
| 1.13 | Color Assessment View (`⇧L`) | Rarely | Neither app has it | T3 | In More. True Tone and Night Shift change the screen's white point (unverified), which limits its use on a phone |
| 1.14 | Pixel readout under the pointer, RGB or L*a*b* | Rarely | LrM shows no RGB values [Q1] | T3 | With no hover, press and hold opens a loupe, offset above the finger, that shows the values |
| 1.15 | Panel switches (the eye on each panel header) and Edited chips ("Edited · 2") | Sometimes | Photos: the outline around each adjustment's button shows how much it changed, and tapping the button compares [A1] | T2 | A dot on each module's tab shows it holds edits, visible at T1. The switch sits in the module's header, and holding it previews the photo without the module, as Lightroom Classic's eye does (`UX-develop-panels.md`) |
| 1.16 | Reset a panel (double-click its title) | Sometimes | — | T2 | Reset is in the module header's menu. A double-tap on a slider resets that slider |
| 1.17 | Undo and Redo (⌘Z, ⇧⌘Z) | Often | Photos: undo and redo buttons at the top of the screen [A4] | T1 | Two buttons in the top bar |
| 1.18 | History panel: each step with its before and after values, and the last 20 sessions | Sometimes | LrM: History "Partial (Auto Versions)" [Q1] | T2 | A History sheet from the top bar, listing the steps as the Mac does |
| 1.19 | Snapshots | Rarely | LrM: snapshots "using Versions" [Q1] | T2 | In the History sheet, beside Versions |
| 1.20 | Reset All Settings | Sometimes | Photos: Revert to Original is in a menu [A4] | T3 | In More, and Undo brings the edit back |
| 1.21 | Command Palette (⌘K) and Find Adjustment (⌘F) | A way in, not an edit | Neither app has a search I could find | T3 | A search field in More. It finds sliders by name or by the words people use (`packages/RedlampUI/Sources/Model/AdjustmentSearch.swift`), and it accepts "exposure 0.7" as the palette does |
| 1.22 | Keyboard shortcuts (186 actions) and your own keymaps | — | LrM added shortcuts for a keyboard connected to an iPad or iPhone [Q7, Q8] | iPad and Mac | Needs a keyboard. An iPhone with a keyboard connected could use the same registry at little cost |

### 2. Looks: recipes and Base Looks

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 2.1 | Apply a recipe (Recipes panel: hover to preview, click to apply) | Often | LrM: Presets is its first edit tab (I20, unverified). Photos: Filters and Photographic Styles [A1] | T1 | The Looks module. With no hover to preview, the photo shows whichever look is at the centre of a scrolling strip, and lifting the finger applies it. Holding a thumbnail compares it with the edit as it was |
| 2.2 | Recipe Amount | Often | Photos: drag a slider to adjust a filter [A1] | T2 | Appears under the strip once a recipe is applied |
| 2.3 | Recipe groups and search (Lightroom's words work) | Sometimes | — | T2 | Group tabs above the strip, and a search field |
| 2.4 | Favorites | Sometimes | LrM couldn't set preset favourites as of October 2024 [Q3] | T2 | A Favorites group, shown first |
| 2.5 | Film Looks (window) | Sometimes | Neither app has film simulations | T2 | The Film group in Looks, with each film's icon |
| 2.6 | Base Look menu, Browse Base Looks…, and Amount from 0 to 200 (Basic panel) | Sometimes | LrM applies profiles [Q1] | T2 | A Base segment in Looks: a grid of the looks rendered on the photo, as the Mac's browser is |
| 2.7 | Apply Base Look Only (a recipe's right-click menu) | Rarely | — | T3 | In a recipe's long-press menu |
| 2.8 | New Recipe… with a settings checklist (`⇧⌘N`) | Rarely | LrM creates presets [Q1] | T3 | In More, with the checklist as a sheet |
| 2.9 | Import and export: `.redrecipe`, `.cube`, `.3dl`, HaldCLUT, Lightroom `.xmp` presets, and Fujifilm's LUT folder | Rarely | LrM installs downloaded presets [Q1] | T3 | Through Files and the share sheet ("Open in Redlamp"). Dropping files on the panel has no phone equivalent |
| 2.10 | Camera recipe cards, typed in as the card lists them | Rarely | Neither app has them | T3 | A form in the Looks module's More, typed on the phone's keyboard |

### 3. Light

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 3.1 | Auto Settings (Basic panel's Auto button) | Often | Photos: a button that enhances light and colour automatically [A1]. LrM: an Auto tab (I20, unverified) | T1 | A button at the start of the module bar. Tapping it again takes Auto off |
| 3.2 | Exposure, Contrast | Often | Photos' Adjust names Exposure [A1]. LrM has both [Q1] | T2 | The first two sliders in Light |
| 3.3 | Highlights, Shadows | Often | Photos names Highlights [A1]. LrM has both [Q1] | T2 | Next in Light |
| 3.4 | Whites, Blacks | Often | LrM has both [Q1] | T2 | Next in Light, with clipping shown by a second finger (1.11) |
| 3.5 | Tone Curve, parametric: Highlights, Lights, Darks and Shadows, and three split points | Sometimes | LrM has tone curves [Q1] | T2 | A folded Curve group. The region sliders are listed, and the split points are handles on the curve |
| 3.6 | Point curve, with the Linear, Medium Contrast and Strong Contrast presets | Sometimes | LrM has tone curves [Q1] | T2 | Points dragged on a curve that fills the panel's width. The finger hides the point being dragged, so its Input and Output values show above it, and ± buttons nudge it |

### 4. Colour

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 4.1 | Treatment: Color or B&W (`V`) | Sometimes | LrM converts to B&W (unverified) | T2 | The first control in Colour |
| 4.2 | White balance presets, As Shot and Auto included | Often | LrM: white balance [Q1] | T2 | A menu at the top of Colour |
| 4.3 | White Balance Selector, the eyedropper (`W`) | Sometimes | LrM (unverified) | T2 | A loupe sits above the finger to show the pixel being picked, and lifting the finger samples it |
| 4.4 | Temp, Tint | Often | LrM: white balance [Q1]. Photos has Warmth and Tint (unverified) | T2 | Under the presets |
| 4.5 | Vibrance, Saturation | Often | LrM has both [Q1]. Photos has both (unverified) | T2 | Under Temp and Tint |
| 4.6 | Color Mixer: HSL and Color modes, eight bands, with Hue, Saturation, Luminance and All | Sometimes | LrM: HSL [Q1] | T2 | A folded group. Color mode, a row of eight colour dots with three sliders under them, fits the phone's width; HSL mode is offered beside it |
| 4.7 | Point Color: swatches, shifts, ranges and uniformity, globally and in masks | Rarely | LrM: Point Color "No" [Q1] | T2 | A folded group. Colours are sampled with the offset loupe |
| 4.8 | Color Grading wheels: Shadows, Midtones, Highlights and Global, three at a time or one | Sometimes | LrM: Color Grading [Q1] | T2 | A folded group showing one wheel at a time, with a selector for the range. The thumb hides the puck, so Hue and Saturation show as values beside the wheel, with the Luminance slider under it |
| 4.9 | Blending, Balance | Rarely | Part of Color Grading in LrM [Q1] | T2 | Under the wheel |
| 4.10 | Calibration: Shadows Tint, and the Red, Green and Blue primaries' Hue and Saturation | Rarely | LrM: Calibration "No" [Q1] | T3 | In Colour's More. Kept so that an edit made on the Mac can still be adjusted on the phone |
| 4.11 | Process version (Calibration panel) | Rarely | Lightroom has a process version selector (`docs/lightroom-feature-inventory.md` §11) | T3 | In Colour's More. A notice appears when the photo's version is older than the current one |
| 4.12 | Calibrate from Target… (Basic panel, CAM-28) | Rarely | Neither app has it | T3 | Tap a patch of the chart and type its reference L*. The Mac's popover becomes a sheet |

### 5. Effects

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 5.1 | Texture, Clarity, Dehaze (Basic › Presence) | Often | LrM has all three [Q1], in its Effects tab (I20, unverified) | T2 | First in Effects |
| 5.2 | Post-Crop Vignetting: Amount, Midpoint, Roundness, Feather, Highlights | Sometimes | LrM: post-crop vignette [Q1] | T2 | A group with Amount shown first |
| 5.3 | Grain: Amount, Size, Roughness, Color | Sometimes | LrM: grain [Q1] | T2 | A group with Amount shown first |
| 5.4 | Halation, Bloom | Rarely | Neither app has them | T2 | In a folded Film group |
| 5.5 | Light Leak: Amount, Warmth, Variation | Rarely | Neither app has it | T2 | In the folded Film group |
| 5.6 | Dust & Scratches | Rarely | Neither app has it | T2 | In the folded Film group |
| 5.7 | Frame: Style, Size | Rarely | Neither app has it | T2 | In the folded Film group |
| 5.8 | Camera Recipe: Dynamic Range, Color Chrome, Chrome FX Blue, Red Shift, Blue Shift | Rarely | Neither app has them | T2 | A folded Camera Recipe group, last in Effects. Recipe cards set these values more often than people do |

### 6. Detail

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 6.1 | Sharpening: Amount, Radius, Detail, Masking | Sometimes | LrM: sharpening [Q1] | T2 | Sharpening can only be judged at 1:1, so opening Detail could show an inset at 1:1 at the place last looked at |
| 6.2 | Noise Reduction: Luminance, Detail, Contrast | Sometimes | LrM: noise reduction [Q1] | T2 | Under Sharpening, with the same 1:1 inset |
| 6.3 | Color noise reduction: Color, Detail, Smoothness | Rarely | LrM: noise reduction [Q1] | T2 | A folded group |

### 7. Optics

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 7.1 | Remove Chromatic Aberration | Rarely | LrM: "Chromatic Aberration/Defringe" [Q1] | T2 | A switch |
| 7.2 | Enable Profile Corrections, and the profile's Distortion and Vignetting (0 to 200) | Rarely | LrM: lens corrections, "limited controls" [Q1] | T2 | A switch with the lens's name under it, and the two amounts |
| 7.3 | The Lens Profiles folder, which holds Adobe LCP files | Rarely | — | iPad and Mac | File management. An edit that uses a profile from that folder raises a question about how it renders on the phone (open question 9) |
| 7.4 | Defringe: Purple and Green, each an Amount and a hue range | Rarely | LrM: "Chromatic Aberration/Defringe" [Q1] | T2 | A folded group. Each Hue Low and Hue High pair becomes one control with two thumbs |
| 7.5 | Manual: Distortion, Vignetting, Midpoint | Rarely | Lightroom: manual lens corrections (`docs/lightroom-feature-inventory.md` §8) | T2 | A folded group |

### 8. Crop and Geometry

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 8.1 | Crop & Straighten (`R`): drag the frame | Often | Photos: drag the corners or pinch [A2]. LrM: cropping [Q1] | T1 | The Crop module. Corner handles are larger than the Mac's, sized for fingers |
| 8.2 | Aspect presets, Lock Crop Aspect (`A`), swap orientation (`X`) | Often | Photos: presets such as Square, 9:16 and 5:7, and a lock [A2]. LrM added pop-ups for social media aspect ratios in February 2026 [Q6] | T2 | A row of presets under the photo. The common ratios for sharing, 4:5 and 9:16 among them, come first |
| 8.3 | Custom aspect ratios | Rarely | — | T3 | At the end of the aspect menu |
| 8.4 | Composition overlays (`O` cycles them, `⇧O` turns them) | Sometimes | — | T2 | Shown while the frame is dragged. A button cycles them |
| 8.5 | Angle, the Straighten tool, and turning by dragging outside the crop | Sometimes | Photos: a straighten slider [A2] | T2 | A dial under the photo, with a haptic tick at 0°. Drawing a line along the horizon with one finger straightens to it |
| 8.6 | Rotate Left and Right (⌘[ ⌘]), Flip Horizontal and Vertical | Sometimes | Photos: rotate 90 degrees and flip [A2] | T2 | Buttons in the Crop segment |
| 8.7 | Constrain to Image | Rarely | — | T3 | In Crop's More |
| 8.8 | Upright: Off, Auto, Level, Vertical, Full | Sometimes | LrM: Upright [Q1]. Photos: tilt vertically and horizontally [A2] | T2 | The Upright segment of the Crop module |
| 8.9 | Upright: Guided, with up to four guides | Rarely | LrM has Upright [Q1]; whether it has Guided is unverified | T2 | Each end of a guide is placed with the offset loupe |
| 8.10 | Transform: Vertical, Horizontal, Rotate, Aspect, Scale, X Offset, Y Offset | Rarely | LrM: geometric corrections [Q1] | T2 | The Transform segment of the Crop module |

### 9. Masks

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 9.1 | Masks panel: the list with coverage thumbnails, select, hide, Show Overlay (`O`), pins (`H`) | Sometimes | LrM: gradients, brushes, ranges, Sky and Subject [Q1] | T1 | The Masks module. On the Mac the pointer over a row shows its overlay; on a phone, pressing the row does. Tapping a pin selects its mask |
| 9.2 | Create New Mask: one picker for every kind | Sometimes | — | T2 | A sheet with presets first, then AI kinds, then drawn ones |
| 9.3 | Subject, Sky, Background | Often, while masking | LrM: Sky and Subject yes, Background no [Q1] | T2 | The first row of the picker |
| 9.4 | People: a picker of who is in the photo, with parts and an option for one mask per person | Sometimes | LrM: People masking "No" [Q1], but portrait masking is offered through Quick Actions [Q5] | T2 | The picker's crops to tick suit touch as they are |
| 9.5 | Objects (Segment Anything 2.1): hover to preview, click, drag a box, or brush | Sometimes | LrM: Object masking "No" [Q1]. Photos' Clean Up: "Tap, brush, or circle" [A3] | T2 | With no hover, a touch shows the outline under the finger and lifting selects it. A drag draws a box, and a scribble brushes over the thing |
| 9.6 | Landscape: a picker of the regions found (SAM 3, an evaluation model) | Rarely | LrM: the October 2025 post lists Landscape Masking for Mobile and Desktop in its summary [Q4], and Quick Actions offer it [Q5]. This conflicts with [Q1]'s "No" for Object and People; unverified | T2 | Needs a 988 MB model (README) on a phone with 8 GB of memory (open question 8) |
| 9.7 | Depth Range: from the photo's depth map, or estimated | Rarely | Lightroom: Depth Range (`docs/lightroom-feature-inventory.md` §14) | T2 | iPhone Portrait photos carry their own depth (see Phone-only opportunities) |
| 9.8 | Linear Gradient, Radial Gradient with Feather | Sometimes | LrM: gradients [Q1] | T2 | Handles sized for fingers. Two fingers turn and scale a radial |
| 9.9 | Brush (`K`): A and B brushes, Erase, Size, Feather, Flow, Density, Auto Mask, pen pressure | Sometimes | LrM: brushes [Q1] | T2 | Erase is a button, since there is no ⌥. Size is set by a slider along the edge under the thumb, two fingers pan, and an inset loupe shows what the fingertip covers |
| 9.10 | Luminance Range (`⇧Q`) and Color Range (`⇧J`) | Rarely | LrM: range masks [Q1] | T2 | Sampled with the offset loupe. The range's four handles get a full-width control |
| 9.11 | Add, Subtract, Intersect, and Invert for a component or a whole mask | Sometimes | — | T2 | Buttons under the selected mask, opening the same picker as 9.2 |
| 9.12 | Existing Mask as a component, and a mask's Detail | Rarely | Neither app has them (Redlamp goes beyond Lightroom here) | T3 | In the component's long-press menu |
| 9.13 | AI masks: Feather, Edge, Refine Edges, Refine Edge Brush | Rarely | Lightroom added Feather and Edge in August 2026 [Q9] | T2 | A folded group on the AI component. The Refine Edge Brush is used zoomed in, with the inset loupe |
| 9.14 | Update AI Masks, on one photo or on N photos | Rarely | — | T3 | In the module's More |
| 9.15 | Mask presets: Blue Sky, Brighten Subject, Darken Background, Smooth Skin, Even Skin Tone, Whiten Teeth, Pop Eyes, Brighten Snow, Enhance Vegetation, and your own | Sometimes | LrM: adaptive presets on Desktop and Mobile [Q4] | T2 | The first row of the picker. On a phone, one tap does what a tool's whole workflow does |
| 9.16 | Local adjustments and the mask's Amount (0 to 200) | Often, while masking | LrM: local adjustments with masks [Q1] | T2 | Grouped as the global modules are (Light, Colour, Effects, Detail), so the same muscle memory works inside a mask |
| 9.17 | A mask's Color swatch, Curves, and Point Color | Rarely | — | T2 | Folded groups in the mask |
| 9.18 | Effects for a mask: Dodge, Burn, Warm, Cool, Add Detail, Reduce Haze, Smooth Skin, Whiten Teeth, Pop Eyes, and your own | Sometimes | LrM: local adjustment brush presets "No" [Q1] | T2 | A strip at the top of the mask's adjustments |
| 9.19 | Mask and component menus: Rename, Duplicate, Duplicate and Invert, Reset, Delete, and reordering | Sometimes | UX-17 found that menus hidden behind a right-click confused people (`UX-17-masks-panel-audit.md`) | T2 | A visible ⋯ button on each row, rather than a long press alone, and a handle to drag for reordering |
| 9.20 | Overlay modes, colour and opacity; ⌥-click an eye to show one mask alone | Rarely | — | T3 | In the module's More |

### 10. Remove

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 10.1 | Remove (`Q`): content-aware fill, and Click picks set to Person or Object | Often | Photos: Clean Up [A3]. LrM: Remove [Q1] | T1 | The Remove module. Tap a spot or brush over it |
| 10.2 | Heal and Clone: Size, Feather, Opacity, dragging the source, Find Source | Sometimes | LrM: Clone and Heal [Q1] | T2 | A mode switch at the top of the module. The source handle is offset from the spot so the finger doesn't cover it |
| 10.3 | Find things named in words (OWLv2), and Remove All | Sometimes | Photos highlights some items automatically so they can be tapped [A3] | T2 | Found things are outlined, and a tap removes one |
| 10.4 | Remove Dust, on one photo or several | Rarely | LrM: Dust Removal is desktop only [Q4] | T2 | A button in Remove |
| 10.5 | Visualize Spots | Rarely | — | T3 | In the module's More |
| 10.6 | Show Spots (`H`) | Sometimes | — | T2 | A switch at the top of the module |
| 10.7 | Generative fill: Fill Generatively, variations, More | Sometimes | LrM downloads the original from the cloud for generative tools [Q10]. Photos' Clean Up offers Auto, Fast and High Quality processing [A3] | T2 | Tested only on Macs with 16 GB of memory or more (README), so whether an 8 GB iPhone can run it is open (open question 8) |

### 11. The parts of Library a phone edit touches

| # | Capability (Mac name) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- | --- |
| 11.1 | Star ratings (`0` to `5`) | Sometimes | LrM: star ratings [Q1]. Photos has optional ratings from 1 to 5 stars in iOS 27 [A8] | T2 | In the photo's info strip in the editor, and on the grid. How these map to Photos' own ratings is open question 4 |
| 11.2 | Pick and reject flags (`P`, `X`, `U`) | Sometimes | LrM: flags [Q1] | T2 | Beside the rating |
| 11.3 | Colour labels (`6` to `9`) | Rarely | LrM: colour labels "No" [Q1] | T3 | In More |
| 11.4 | Mark | Rarely | — | T3 | In More |
| 11.5 | Copy Settings… with its checklist (`⇧⌘C`) | Sometimes | Photos: Copy Edits, then review and turn off the edits not to copy [A1]. LrM: copy and paste [Q1] | T3 | In More, with the checklist as a sheet that remembers its last choice |
| 11.6 | Paste Settings (`⇧⌘V`) and Paste Settings from Previous (`⌥⌘V`) | Sometimes | Photos: Paste Edits [A1] | T2 | Paste and Previous chips at the start of Looks |
| 11.7 | Sync Settings… to a selection | Sometimes | Photos: select thumbnails, then Paste Edits [A1] | T3 | From the grid's selection menu. It runs in the background, with Undo |
| 11.8 | Auto Sync (`⌥⇧⌘A`) | Rarely | — | iPad and Mac | Screen size: it repeats each change across a selection that has to stay visible while editing, and the iPhone's editor shows one photo. Pasting to a selection gives the same result |
| 11.9 | Export dialog: format, quality, size, bit depth, colour space, metadata, file name, presets | Sometimes | LrM: JPG, AVIF, JXL, TIFF, DNG, resizing and watermarks [Q1]. Its device export uses the share menu [Q6] | T2 | The share sheet's first row is Redlamp's export settings, with a summary such as "JPEG · 2048 px · P3" |
| 11.10 | Export with Previous (`⌥⇧⌘E`) | Often | — | T1 | The Share button in the top bar exports with the last settings |
| 11.11 | Report a Bug or Send Feedback | Rarely | — | T3 | In More |
| 11.12 | Settings › Models: downloading and removing models | Rarely | — | T3 | In More › Settings, which shows each model's size against the phone's free space |
| 11.13 | Focus stacking: Merge to Focus Stack, and the Stack workspace | Rarely | Neither app has it | iPad and Mac | Its input is tens of camera frames in a folder, which a Photos library rarely holds. Merging takes memory and time (25 frames of 17 MP took about 8 s on an M1 Ultra, per the README), and the retouch brush needs precision. Whether a merged stack opens on the phone is open question 10 |

### Planned on the Mac, placed the same way

| Capability (tracker) | Use | Evidence | Tier | On a phone |
| --- | --- | --- | --- | --- |
| Versions, as Lightroom's virtual copies (EDT-09, LIB-48; Create Virtual Copy, ⌘') | Sometimes | LrM: a Versions tab (I20, unverified) | T2 | In the History sheet |
| Red Eye and Pet Eye (Phase 3) | Rarely | LrM: Red Eye "No" [Q1] | T2 | In Remove |
| Targeted Adjustment Tool (UX-35) | Sometimes | Lightroom has it (`docs/lightroom-comparison.md`) | T2 | Dragging on the photo inside Light's curve and Colour's mixer. A finger on the photo is the most direct touch control there is, so this suits the phone even better than the Mac (see Phone-only opportunities) |
| AI Denoise (DN-06, DN-07, DN-08) | Sometimes | LrM brought Denoise to the iPad, with an M1 chip or later, in August 2026 [Q9]; whether the iPhone has it is unverified | T2 | A switch in Detail, once on-device timing (DN-04) says the iPhone can run it |
| HDR editing and export (TON-42) | Sometimes | LrM: HDR editing "on supported devices" [Q1] | T2 | iPhone screens show HDR |
| Removing an object picked by rectangle or brush (RM-19) | Sometimes | Photos: "Tap, brush, or circle" [A3] | T2 | In Remove |
| Edit in another app (EDT-29) | Rarely | LrM sends to other editors [Q1] | T2 | The share sheet |
| Watermarks and output sharpening (EDT-25, EDT-28) | Rarely | LrM: watermarks and output sharpening [Q1] | T2 | Export options |
| Super Resolution (SR-01, SR-02) | Rarely | — | T3 | In More, or as an export option |
| Batch export (EDT-16) | Sometimes | — | T3 | From the grid's selection menu |
| Readout points pinned on the photo (UX-40) | Rarely | — | T3 | In More |
| Content Credentials (RM-03) | Rarely | — | T3 | An export option |
| Reference view (UX-34) | Rarely | LrM: "No" [Q1] | iPad and Mac | Screen size: two photos side by side on a phone are too small to judge colour against each other |
| Soft proofing (TON-10) | Rarely | LrM: "No" [Q1] | iPad and Mac | Precision: proofing for print is judged on a large, profiled display. I couldn't verify whether an iPhone's display can be profiled |

### Counts

| Tier | Inventory | Planned | Total |
| --- | --- | --- | --- |
| T1 | 12 | 0 | 12 |
| T2 | 74 | 8 | 82 |
| T3 | 26 | 4 | 30 |
| iPad and Mac | 4 | 2 | 6 |
| Not on a phone | 0 | 0 | 0 |
| **All** | **116** | **14** | **130** |

Assessment: most capabilities land in T2, which is where the owner's rule pushes them: layered, not cut. The editor's first level stays small: nine module tabs, Auto, Undo, Redo, Before, History, Share and More, plus gestures on the photo.

## What changes on a phone

### What a phone takes away

- **No hover.** The Mac previews recipes, masks, components, pins, objects and history steps as the pointer passes over them. On a phone a preview needs a touch: either a press and hold, which shows the preview and leaves things as they were when the finger lifts, or a scroll, where the item at the centre of a strip is previewed.
- **No keyboard.** About 186 actions have keys on the Mac. On a phone, the common ones become buttons, and the rest are reached through search and More.
- **No right-click.** UX-17 found that actions kept in context menus go unnoticed. iOS has long-press menus, but they are just as hidden, so every row that has actions also gets a visible ⋯ button.
- **A small screen.** One module is open at a time, and each module shows its common sliders and folds the rest. The photo needs to keep at least half the screen's height while sliders are showing (assessment; MOB-04's prototypes should test it).
- **One thumb.** Controls sit in the bottom third of the screen, with the module bar along the bottom edge and sliders above it. The top bar holds only actions that are used less often while dragging: Undo, Redo, History, Share and More.
- **Fingers hide what they touch.** Anything aimed at a pixel needs a loupe offset above the finger, or a handle offset from the point it moves: the white balance and range eyedroppers, Point Color's sample, the ends of Guided Upright's guides, a curve's points, the Refine Edge Brush, and Heal and Clone sources.
- **Imprecise drags.** Sliders move relative to where the finger lands, never jumping to the tap's position, so a thumb resting on a slider doesn't change it. Moving the finger slowly gives finer control, ± buttons step a value, and a haptic tick marks the default value and each step.

### Mac interactions with no direct phone equivalent

| On the Mac | What could stand in for it |
| --- | --- |
| Hover previews: recipes, masks and components, mask pins, Objects, history steps | Press and hold to preview, with lifting the finger leaving things unchanged. A scrolling strip previews the item at its centre. For Objects, a touch shows the outline and lifting selects it |
| ⌥-drag on a tone slider to see clipping | A second finger resting on the photo while dragging, and a clipping switch on the histogram |
| ⌥-click an eye to show one mask alone; ⌥-click a header for Solo Mode | A "Show only this" item in the row's ⋯ menu. Solo Mode isn't needed, since one module is open at a time |
| ⌥ to erase while brushing; Space-drag to pan while painting | An Erase button; two fingers pan |
| Scroll-wheel and pinch zoom; ⌘-scroll or `[` `]` to size the brush | Pinch to zoom. The brush is sized by a slider along the edge, which shows its ring at the new size, as the Mac's does |
| Keyboard stepping of sliders (`,` `.` to move between sliders, `+` `−` to step, ⇧ for ten steps) | ± buttons on the selected slider, with a haptic tick on each step, and the value typed with arithmetic as the Mac allows (`ParameterSpec.parse` accepts `x+10`) |
| Shift-drag for fine control; click to jump; double-click to reset | Slower finger movement for fine control, no jumping, and a double-tap to reset |
| Right-click menus: a filmstrip photo's Copy and Paste, a recipe's Apply Base Look Only, a mask's actions | Visible ⋯ buttons, with long-press menus as well |
| ⌘K command palette, and its slider bar | A search field that keeps the palette's "exposure 0.7" and "temp 5600k" syntax. App Intents could put actions such as applying a recipe into Shortcuts (assessment) |
| The filmstrip sliding in when the pointer reaches the bottom of the window | Swiping up from the bottom edge of the photo |
| Pen pressure on the brush | Apple Pencil, on the iPad. On the iPhone, the Flow slider does the job |

## A proposed grouping into phone modules

The module bar, from left to right: **Auto** (a button) · **Looks** · **Light** · **Colour** · **Effects** · **Crop** · **Masks** · **Remove** · **Detail** · **Optics**. Nine tabs need a scrolling bar on smaller iPhones, as Lightroom Mobile's twelve tabs do (I20, unverified). The order follows how often each module is used, not the Mac's panel order. Slider names, ranges and defaults are the Mac's, from `ParameterCatalog` in `packages/RedlampEngineAPI/Sources/ParameterSpec.swift`.

| Module | Shown first | Folded groups, in order | Comes from on the Mac |
| --- | --- | --- | --- |
| **Looks** | Paste and Previous chips; recipe strip with groups (Favorites first, then Film and the rest); the recipe's Amount | Base: Base Look grid and Amount (0 to 200). More: New Recipe…, import, camera recipe card | Recipes panel; Basic's Base Look; Paste and Paste from Previous; Film Looks |
| **Light** | Exposure (−5 to +5), Contrast, Highlights, Shadows, Whites, Blacks | Histogram (with clipping and dragging); Curve: parametric Highlights, Lights, Darks, Shadows and splits, then the point curve with its presets | Basic's Tone; Tone Curve |
| **Colour** | Treatment (Color or B&W); White Balance preset and eyedropper; Temp (2000 to 50000 K), Tint (−150 to +150); Vibrance, Saturation | Color Mixer (Color, HSL, Point Color); Color Grading (wheels, Blending, Balance). More: Calibration and Process | Basic's white balance and Presence (Vibrance, Saturation); Color Mixer; Color Grading; Calibration |
| **Effects** | Texture, Clarity, Dehaze | Vignette (Amount, Midpoint, Roundness, Feather, Highlights); Grain (Amount, Size, Roughness, Color); Film (Halation, Bloom, Light Leak, Dust & Scratches, Frame); Camera Recipe (Dynamic Range, Color Chrome, Chrome FX Blue, Red Shift, Blue Shift) | Basic's Presence (Texture, Clarity, Dehaze); Effects |
| **Crop** | Crop segment: frame, aspect presets and lock, swap, Angle dial, rotate, flip, overlay | Upright segment: Off, Auto, Level, Vertical, Full, Guided. Transform segment: Vertical, Horizontal, Rotate, Aspect, Scale, X Offset, Y Offset. More: custom aspects, Constrain to Image | Crop & Straighten tool; Transform panel |
| **Masks** | Mask list with thumbnails; Add (the picker: presets, then Subject, Sky, Background, People, Objects, Landscape, Depth Range, then Brush, Linear, Radial, Color Range, Luminance Range) | The selected mask: components, then Amount and Effects, then adjustments grouped as Light, Colour, Effects and Detail, then Color swatch, Curves and Point Color | Masking tool and Masks panel |
| **Remove** | Mode (Remove, Heal, Clone); tap or brush; Size, Feather, Opacity | Find; Remove Dust; Generative fill. More: Visualize Spots | Healing tool |
| **Detail** | Sharpening Amount, Radius, Detail, Masking; Noise Reduction Luminance, Detail, Contrast | Color noise: Color, Detail, Smoothness | Detail panel |
| **Optics** | Remove Chromatic Aberration; Enable Profile Corrections, with the profile's Distortion and Vignetting | Defringe (Purple and Green, Amount and hue range); Manual (Distortion, Vignetting, Midpoint) | Lens Corrections panel |

Outside the bar: Undo and Redo, History (steps, past sessions, Snapshots and, once built, Versions), Share (export with the last settings, with the settings on the share sheet's first row), and More (search, Copy Settings…, Reset All, viewing modes, Report a Bug, Settings).

### Where it departs from the Mac's panel order, and why

1. **Basic splits three ways.** Basic's tone sliders go to Light. White balance, Treatment, Vibrance and Saturation go to Colour. Texture, Clarity and Dehaze go to Effects. On the Mac, Basic holds 16 controls in a tall column. On a phone that would push the photo off the screen, and each of the three groups answers a different question: how bright, what colour, what character. Lightroom Mobile splits it the same way (I20, unverified). The cost is that a Lightroom Classic user looks for Dehaze in Basic first; the search field and module dots (1.15) help them find it.
2. **Transform and Upright join Crop.** All three change the photo's geometry, all three want the photo framed with its edges visible, and Apple Photos keeps straighten and both tilts inside its crop tool [A2]. Lightroom keeps Geometry separate, but in August 2026 it moved Constrain Crop from Geometry into the Crop panel [Q9], which brings it a step closer.
3. **Looks comes first, and holds Paste and Previous.** Recipes, the previous photo's settings and copied settings are three ways to bring an edit in from elsewhere, and on a phone they are often the whole edit. Lightroom Mobile puts Presets first (I20, unverified), and Photos opens its Adjust tool next to Filters or Styles [A1].
4. **Detail and Optics move to the end.** Lens corrections apply by default (process 5 and later, `docs/recipes/sidecar-format.md`). Sharpening and noise reduction have defaults (`ParameterSpec.swift`: Amount 40, Color 25), and can only be judged at 1:1. Masks and Remove come before them, because phone edits reach for them more often (assessment).

Calibration doesn't get a module of its own: it moves into Colour's More. Lightroom Mobile has no Calibration sliders at all [Q1]. Redlamp keeps them because an edit made on the Mac may already use them.

## What carries over unchanged

- **Slider names, ranges, steps and defaults.** Both apps read them from the one catalog in `packages/RedlampEngineAPI/Sources/ParameterSpec.swift`. Examples: Temp runs from 2000 to 50000 K on a mired scale, Exposure from −5 to +5, the mask Amount from 0 to 200 with a default of 100, and Sharpening Amount from 0 to 150 with a default of 40. Lightroom's names stay, as the project's principle requires.
- **The edit format.** The sidecar is edit format 3 with history format 1 (`docs/recipes/sidecar-format.md`). Its principles are what make an edit render the same on Mac and iPhone: it is sparse, resolved rather than recomputed, and keeps a stable rendering. Auto settings and AI masks are stored as the values and bitmaps they produced, so the phone computes nothing again. The process version (15 today, `EditRecipe.currentProcessVersion` in `packages/RedlampEngineAPI/Sources/EditRecipe.swift`) is never changed silently. An edit from a newer Redlamp opens read-only, and fields the reader doesn't know are kept.
- **Panel switches, mask presets, mask Effects and the Copy Settings checklist.** They are the same data: `SwitchablePanel` in `PanelSwitches.swift`, and the Copy Settings groups that `PanelID.settingsItemIDs` lists in `EditorTypes.swift`.
- **Recipes and looks.** There is one `.redrecipe` format (`docs/recipes/recipe-format.md`), with Base Looks pinned by content hash. The film looks and the bundled recipes ship with the app.
- **History.** Steps keep their before and after values, and sessions are kept with the photo.

Things that may not carry over, and need a decision:

- **Resources that live only on the Mac.** These are lens profiles in the Lens Profiles folder, imported LUTs, and the looks imported from Fujifilm's LUTs. Fujifilm's terms allow personal use only, "so the looks stay on your Mac and exported recipes carry only a reference to them" (README, Recipes and looks). An edit that uses one of them may render differently on the phone, or not at all. I didn't check whether the sidecar holds a profile's or LUT's data, or only a reference to it (unverified).
- **GPU arithmetic.** Golden renders exist on the Mac. Whether an A-series GPU renders every process version within the same tolerance as the M-series GPUs is unmeasured (unverified); Phase 5's performance-lab tiers (README Roadmap) are the place to check it.

## Phone-only opportunities

- **The Photos library as the starting point.** PhotoKit offers the user's albums and smart albums, among them RAW, Depth Effect, Live Photos, Favorites and Recently Added [P3]. Photos' own filters (Edited, Rating, Captured by Me) and its sort by date added or taken [A9] show what photographers expect. Photos can store an app's own "recipe" with each edited asset as `PHAdjustmentData`, "which allows your app to reconstruct or revert the effects of prior editing sessions" [P1]. That lets an edit made in Redlamp stay editable in Redlamp, and other apps see the rendered result. Two constraints follow:
  - **One adjustment-data object per asset.** Photos keeps only one, "representing the most recent edit" [P1], so Redlamp's whole edit would have to fit in it, versions included.
  - **A permission prompt on each save.** "Each PHPhotoLibrary performChanges call prompts the user for permission to edit the contents of the photo library"; several assets can be edited in one batch [P2]. Saving should happen once, on Done, and pasting to a selection should commit as one batch.
- **The Photo Editing Extension (EXT-04)** would let a photographer edit with Redlamp's engine and recipes from inside Photos itself, keeping the adjustment data [P2].
- **Saving and favouriting in Photos.** A Redlamp rating or flag could also set Photos' Favorite, which PhotoKit can write [P4]. iOS 27 Photos has star ratings, turned on in the user's profile, and filters by them [A8]; whether third-party apps can read or write those ratings through PhotoKit is unverified.
- **ProRAW.** Redlamp already decodes Apple ProRAW and applies its gain table map, so it renders as the iPhone does (README, process 5). The iPhone's Camera takes ProRAW at 12 MP or 48 MP [A7]. A 48 MP ProRAW on an 8 GB phone is the memory case that Phase 5's tiled rendering (ARC-05) exists for.
- **Portrait depth and mattes.** Depth Range masks read a photo's own depth map, and People parts use the iPhone's hair, skin and teeth mattes, with nothing to download (README, Masking). A phone photo arrives with these, which makes Depth Range and People more useful on the iPhone than on the Mac. Photos itself edits depth, the Portrait Lighting effects and the focus point [A5]; Lens Blur, a later item (OTH-03), would build on the same depth.
- **Live Photos.** Photos changes a Live Photo's key photo, trims it, mutes it, and offers Loop, Bounce and Long Exposure [A6]. PhotoKit treats the paired video as a resource of its own [P5]. At the least, Redlamp should keep the Live Photo intact when it saves an edit (open question 11).
- **The camera.** An in-app camera that shoots ProRAW straight into an edit is a Lightroom Mobile feature (`docs/lightroom-feature-inventory.md` §1) and a Later item for Redlamp. Opening the photo just taken, from Photos, is enough to start with.
- **The share sheet.** It works in both directions. Out of Redlamp, it sends exports to other apps and AirDrop. Into Redlamp, it brings raws from Files, AirDrop and Mail ("Open in Redlamp"), and recipes, LUTs and Lightroom presets to import (2.9).
- **Haptics.** A tick when a slider crosses its default and on each ± step, when the crop snaps to an aspect ratio or the angle reaches 0°, when a slider starts to clip, and when an AI mask is ready.
- **Touch on the photo itself.** The Targeted Adjustment Tool (UX-35, planned) and dragging on the histogram (1.10) are both direct manipulation, which a finger does better than a pointer (assessment). On a phone they could become the first way people learn the curve and the mixer.
- **Quick, task-sized layers.** Lightroom Mobile added Quick Actions, which are AI "shortcuts to existing tools to save you hopping around the different panels" [Q3]. They have since gained portrait and landscape masks and blemish removal "not yet available in the main editing tools" [Q5]. Redlamp's mask presets and mask Effects are already task-sized; on a phone they could form a layer like Quick Actions without hiding the full tools.

## Open questions for the owner

1. **Where does a Photos-library photo's edit live?** It could be in `PHAdjustmentData`, which travels with iCloud Photos but is one object per asset [P1]. It could be a sidecar in Redlamp's own storage, keyed by the asset. Or it could be both. The answer decides whether the Mac can open an edit made on the iPhone (EXT-04).
2. **Saving an edit into Photos writes a rendered version into the library.** The original is kept and can be restored with Revert to Original [A4], but the sidecar format's first principle is "beside the photo, never in it". Is that acceptable for Photos assets?
3. **When should the phone save?** Each save to Photos prompts for permission [P2]. Should Redlamp save on Done only, keeping the edit in its own storage until then?
4. **How do ratings and flags map to Photos?** Options are Photos' Favorite [P4], its iOS 27 star ratings [A8] (if PhotoKit exposes them, which is unverified), or Redlamp's own data only.
5. **Which order for the module bar?** By frequency, as proposed (Detail and Optics last), or Lightroom Mobile's order (I20, unverified) for the muscle memory of people coming from it?
6. **Where do Texture, Clarity and Dehaze go?** In Effects, as proposed and as in Lightroom Mobile, or in Light, closer to the Mac's Basic?
7. **Should Transform and Upright join the Crop module** (Apple Photos' way), or stay in a Geometry module of their own (Lightroom Mobile's way)?
8. **Which AI features does a phone with 8 GB of memory get?** Candidates are SAM 3 (988 MB), Depth Anything 3 (336 MB) and generative fill, which has been tested only on Macs with 16 GB or more. Are they offered on the iPhone once on-device timing (DN-04) is measured, offered on the iPad first, or offered everywhere with a warning?
9. **How should the phone show an edit that uses a Mac-only resource?** The resources are a lens profile from the Lens Profiles folder, an imported LUT, and Fujifilm's personal-use LUT looks. The options are read-only, a warning, or rendering without the missing part.
10. **Should a focus stack merged on the Mac open and edit on the phone,** given that its result is cached and rebuilt when needed (README, Focus stacking)?
11. **What happens to Live Photos?** Should Redlamp's edit also apply to the paired video, as Photos' own edits do [A6], or should Redlamp save a still?
12. **Is search worth a first-level spot** rather than a place in More, for photographers coming from the Mac's ⌘K and ⌘F?
13. **Is Auto Sync wanted on the iPad,** where a selection can stay visible while editing, or nowhere but the Mac?
14. **Should raws from Files be in the first release** beside the Photos library, for camera raws copied to the phone outside Photos?
15. **Is an in-app ProRAW camera wanted in the first release,** or later, as now planned?

## Sources

Every page was fetched on 13 October 2026.

**Apple, iPhone User Guide (current edition: iOS 27)**

- [A1] Edit photos and videos on iPhone: <https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/ios>. The Adjust text is the same in the iOS 26 edition: <https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/26/ios/26>. The page names only Exposure, Brilliance and Highlights among Adjust's settings; the rest of the list is unverified.
- [A2] Crop, rotate, flip, or straighten photos and videos: <https://support.apple.com/guide/iphone/crop-rotate-flip-straighten-photos-videos-iph0f3ebb1dd/ios>
- [A3] Clean up, extend, and reframe photos: <https://support.apple.com/guide/iphone/clean-up-extend-and-reframe-photos-xy0grrlxue5w/ios>
- [A4] Undo and revert photo edits: <https://support.apple.com/guide/iphone/undo-and-revert-photo-edits-iph2413db0ab/ios>
- [A5] Edit Portrait mode photos: <https://support.apple.com/guide/iphone/edit-portrait-mode-photos-iph310a9a220/ios>
- [A6] Edit Live Photos: <https://support.apple.com/guide/iphone/edit-live-photos-iphd8dbb3291/ios>
- [A7] Take Apple ProRAW photos: <https://support.apple.com/guide/iphone/take-apple-proraw-photos-iphae1e882a3/ios>
- [A8] Apply star ratings to photos and videos: <https://support.apple.com/guide/iphone/apply-star-ratings-c64zplz6wcgr/ios>
- [A9] Sort and filter the photo library: <https://support.apple.com/guide/iphone/sort-and-filter-the-photo-library-iph2e66e2f2c/ios>

**Apple Developer, PhotoKit**

- [P1] `PHAdjustmentData`: <https://developer.apple.com/documentation/photos/phadjustmentdata>
- [P2] `PHContentEditingOutput`: <https://developer.apple.com/documentation/photos/phcontenteditingoutput>
- [P3] `PHAssetCollectionSubtype`: <https://developer.apple.com/documentation/photos/phassetcollectionsubtype>
- [P4] `PHAssetChangeRequest.isFavorite`: <https://developer.apple.com/documentation/photos/phassetchangerequest/isfavorite>
- [P5] `PHAssetResourceType`: <https://developer.apple.com/documentation/photos/phassetresourcetype>

**The Lightroom Queen**

- [Q1] Lightroom cloud ecosystem vs. Lightroom Classic, updated 9 October 2026, the feature table's Mobile column: <https://www.lightroomqueen.com/lightroom-cc-vs-classic-features/>
- [Q2] What's New, May 2024 (Lens Blur's Focus Range on mobile): <https://www.lightroomqueen.com/whats-new-in-lightroom-2024-05/>
- [Q3] What's New, October 2024 (Quick Actions; no preset favourites on mobile; Detect Objects in Remove): <https://www.lightroomqueen.com/whats-new-in-lightroom-2024-10/>
- [Q4] What's New, October 2025 (Landscape Masking for Mobile and Desktop in the summary; adaptive presets; Dust Removal desktop only; no colour labels on mobile): <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-10/>
- [Q5] What's New, December 2025 (Quick Actions on iPad, giving portrait and landscape masking and blemish removal): <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-12/>
- [Q6] What's New, February 2026 (the iPhone's Crop redesigned, with social media aspect ratios; device export through the share menu): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-02/>
- [Q7] What's New, April 2026 (keyboard shortcuts with a keyboard connected to an iPhone or iPad): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-04/>
- [Q8] What's New, June 2026 (many more keyboard shortcuts on iOS and iPadOS): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-06/>
- [Q9] What's New, August 2026 (Crop & Expand on iPhone; Constrain Crop moved into Crop; Denoise on the iPad; AI masks' Feather and Edge): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-08/>
- [Q10] What's New, June 2025 (mobile downloads originals for AI tools): <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-06/>

**Redlamp**

- [I20] `docs/lightroom-feature-inventory.md`, section 20, which lists Lightroom Mobile's edit tabs: Presets, Auto, Light, Color, Effects, Detail, Optics, Geometry, Masking, Remove, Crop and Versions. It was written from working knowledge as of mid-2025, so it is unverified here.

**Refused:** Adobe's help pages returned HTTP 403 to both requests: <https://helpx.adobe.com/lightroom-cc/using/edit-photos-ios.html> and <https://helpx.adobe.com/lightroom-cc/using/masking-mobile.html>.
