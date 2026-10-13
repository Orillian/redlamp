# iPhone and iPad: findings

How Redlamp should work on an iPhone, before any of it is built: what the Mac editor needs on a phone and where it sits, what Lightroom for iPhone and eight other iPhone editors teach, what iOS and Redlamp's own code allow, and which ways of moving between modules and making an edit are worth prototyping. Researched on 13 October 2026 for MOB-01 ([#406](https://github.com/pdcgomes/redlamp/issues/406)), at the owner's request, by a team of five specialists (agents) and a design critic; the source tag in the [research tracker](research-tracker.md) is **MOB**. The track's rows are in section 14 of the tracker, and its wireframes are a canvas, `iphone-wireframes.canvas.tsx`.

The owner's direction for the study: the app opens on the iPhone's own Photos library, with its albums and filters, as Lightroom Mobile does, and a tap opens a photo to edit; editing should feel intuitive and simple and build muscle memory, and moving between develop modules should be easy; Lightroom Mobile is studied but not copied, and new interactions are welcome; nothing is cut just to simplify the screen, since Lightroom Mobile's missing features have always irritated him. iPhone comes first, iPad after. Prequel was left out at his request.

The evidence is in five notes:

- [The Mac editor, distilled](notes/MOB-desktop-distilled.md): 116 capabilities of the Mac editor placed on the phone, with proposed modules and 15 open questions.
- [Lightroom for iPhone](notes/MOB-lightroom-mobile.md): version 11.6.10, its navigation and edit screen, a 42-line checklist of what it lacks against the desktop, 1,087 App Store reviews counted, and seven screen recordings for the owner to make.
- [iPhone photo editors](notes/MOB-mobile-editors.md): Apple Photos on iOS 26 and 27, Snapseed, VSCO, Darkroom, Photomator, RAW Power, Capture One, Halide and Infltr, and eleven interaction patterns.
- [Platform and architecture](notes/MOB-platform-and-architecture.md): PhotoKit, keeping edits, Files, the engine on an iPhone, what the UI can reuse, iOS 26 and 27's design language, and which iPhones to support.
- [Interaction concepts](notes/MOB-interaction-concepts.md): eight principles, five concepts with storyboards, layouts and counts, the parts every concept shares, and the design critic's review.

Each note keeps its sources and what it couldn't reach. Adobe's help pages, Reddit, DPReview, PetaPixel, MacStories and some makers' help centres refused automated requests, and no one on the team can use the apps, so how Lightroom for iPhone behaves under the finger waits on the owner's recordings, and claims marked (unverified) in the notes stay so here.

## 1. Summary

- **Nothing has to be left off the phone.** All 116 of the Mac's capabilities have a place: 12 one tap from the photo, 74 inside a module, 26 behind search or More, and 4 on iPad and Mac only (keyboard shortcuts, the Lens Profiles folder, Auto Sync and focus stacking, each for a stated reason). Lightroom for iPhone lacks 42 things its desktop has, among them Point Color, Calibration, People and Object masks in its masking tools, Red Eye, a full history and zoom beyond 2:1; Redlamp keeps them, in folded groups or behind More ([distilled](notes/MOB-desktop-distilled.md), [Lightroom §4](notes/MOB-lightroom-mobile.md#4-whats-missing-against-lightroom-classic-and-lightroom-desktop)).
- **The edit itself carries over unchanged:** the Mac's slider names, ranges and defaults, the sidecar format, process versions and recipes. What could still make a Mac edit render differently on the phone is a resource that lives only on the Mac (a lens profile, an imported LUT) and GPU results not yet compared on A-series chips.
- **Edit Photos photos in place; don't import them.** Lightroom for iPhone copies a Photos photo into its own library on the first edit and returns it only as an exported copy, and reviewers ask for a round trip; Photomator, RAW Power and Darkroom edit the Photos item itself, re-editable and revertible in Photos ([Lightroom §2](notes/MOB-lightroom-mobile.md#2-navigation), [editors](notes/MOB-mobile-editors.md)). Photos can hold only a short edit, one per photo, and asks permission on each save, so the full edit lives in Redlamp's own sidecar and a compact copy with a rendered version goes into Photos on Done ([platform §2](notes/MOB-platform-and-architecture.md#2-keeping-edits)).
- **Lightroom for iPhone's critics are mostly about money.** Of 222 critical reviews in the last year, 123 are about price, the paywall or billing and 55 about crashes; 19 are about a confusing or changed layout. Its praise is for ease of use and working across devices ([Lightroom §5](notes/MOB-lightroom-mobile.md#5-what-users-praise-and-complain-about)).
- **Every editor keeps the photo above and the controls below, in the thumb's reach.** They differ in what's below: one large control for one adjustment (Apple Photos, VSCO, Snapseed), or a list of sliders (Darkroom, Photomator, RAW Power, Capture One). The editors with a Lightroom-sized set of adjustments all fall back to lists ([editors, In short](notes/MOB-mobile-editors.md#in-short)).
- **The engine can run on an iPhone with less work than a port.** Its layers already build for iOS, and the Mac uses no Metal feature an A17 Pro lacks. The work is decoding (iOS 26's `AppExtensionProcess` could carry the Mac's decoder protocol in a sandboxed process of its own), memory budgets, tiled export, background GPU rules, golden renders on iPhone GPUs and an iOS build on CI. In the Mac UI's model, 4 of 53 files import AppKit ([platform §4, §5](notes/MOB-platform-and-architecture.md#4-running-redlamps-engine-on-an-iphone)).
- **iOS 27 adds what a raw editor wants from Photos:** star ratings, keywords and captions apps can write, a choice of base for raw and JPEG pairs, and a persistent change observer, on the same iPhones as iOS 26 ([platform §1](notes/MOB-platform-and-architecture.md#1-photokit-for-a-lightroom-style-gallery)).
- **Of five interaction concepts, Bar and ruler ranks first:** eight fixed modules along the bottom, a strip of adjustments with Apple Photos' rings, and one full-width ruler, keeping 60% of the screen for the photo. The design critic scores it 33 of 40, then My sliders 28, the Slider sheet and the Flick compass 26 each, and the photo as the control 24 ([concepts](notes/MOB-interaction-concepts.md)).
- **Recommendation:** prototype Bar and ruler with its layers (a pull-up list, a sideways drag on the photo, search) against the Slider sheet, Lightroom's model, and test the Flick compass first with a small rig that records strokes (section 6). Seven decisions for the owner are in section 7; the build rows the study proposes are in section 8.

## 2. What the phone keeps, and where

The distiller's tiers ([distilled, Tiers](notes/MOB-desktop-distilled.md#tiers)):

| Tier | Where | Capabilities | Examples |
| --- | --- | --- | --- |
| T1 | One tap from the photo | 12 | The modules, before and after, undo, Done |
| T2 | Inside a module | 74 | Every Basic slider, Curve, Color Mixer, Color Grading, mask kinds, crop ratios |
| T3 | Behind search or More | 26 | Calibration, Process version, Copy Settings, RGB readout, reference view |
| iPad and Mac | Not on an iPhone | 4 | Keyboard shortcuts, the Lens Profiles folder, Auto Sync, focus stacking |

**The modules.** The distiller proposed an Auto button and nine modules. The interaction designer made it eight fixed slots, Looks, Light, Colour, Effects, Crop, Masks, Remove and Detail, with Optics inside Detail and Auto inside Looks, because ten slots on an iPhone SE leave 37.5 points each, under Apple's 44-point minimum, and a scrolling bar moves things. Basic splits three ways (tone into Light, white balance, Vibrance and Saturation into Colour, Texture, Clarity and Dehaze into Effects); Transform and Upright join Crop, as in Apple Photos and, since February 2026, Lightroom for iPhone; Paste and Previous sit in Looks with the recipes, as ways to bring in an edit from elsewhere ([concepts §3](notes/MOB-interaction-concepts.md#3-shared-parts)).

**A mask is a context, not a place.** While a mask is selected, Light, Colour, Effects and Detail edit the mask, with every adjustment where it is for the whole photo, so one map of positions is learnt and masks reuse it ([concepts §3](notes/MOB-interaction-concepts.md#3-shared-parts)).

**What a phone takes away, and what stands in.** Hover previews become press-and-hold or scrolling previews; ⌥-drag clipping, a second finger resting on the photo; scroll-wheel zoom, pinch; keyboard stepping, a haptic tick at the default and at each whole unit, a ten-times finer drag as the finger moves up off the ruler (RAW Power's), and typed values; the ⌘K palette, a search field that keeps its "exposure 0.7" syntax ([distilled](notes/MOB-desktop-distilled.md#what-a-phone-takes-away)).

**Phone-only opportunities:** the Photos library itself, ProRAW and Portrait depth from the iPhone's camera, Live Photos, the share sheet and haptics.

## 3. What Lightroom for iPhone teaches

From [the Lightroom note §6](notes/MOB-lightroom-mobile.md#6-keep-do-better-avoid):

- **Keep:** the gallery that starts on the Photos library (Device tab, since June 2023); the two-level toolbar's grouping of tools and panels (October 2023); the desktop's slider names and order; named versions; press and hold for the before.
- **Do better:** editing Photos photos in place rather than copying them; parity with the desktop (the 42 gaps); a full history; zoom past 2:1; controls that stay where they are between releases.
- **Avoid:** moving controls between releases (the 19 layout complaints followed such changes); permanent AI controls on the edit screen; tools that need a server; anything between an edit and saving it.

What the edit screen does under the finger (sheet heights, slider reset, typing values, gestures, landscape) is unverified until the owner's seven recordings arrive ([§7 of the note](notes/MOB-lightroom-mobile.md#7-screen-recordings-for-the-owner-to-make)).

## 4. What the other editors teach

The eleven patterns from [the editors note](notes/MOB-mobile-editors.md#patterns-worth-considering-for-redlamp), and where the concepts use them:

| Pattern | Apps | Used in |
| --- | --- | --- |
| One large control under the photo, rings on each adjustment | Apple Photos | Bar and ruler |
| A bottom bar of modules opening a list of sliders | Darkroom, Photomator, RAW Power | Slider sheet; Bar and ruler's pull-up |
| Drag on the photo: vertical picks, horizontal sets | Snapseed | The photo as the control; a layer of Bar and ruler, off by default |
| A dial or carousel to switch sections | Halide | Flick compass, by way of a marking menu |
| A pinned set of the photographer's own tools | Snapseed Faves, Photomator | My sliders |
| Fine mode when the finger moves off the slider, double-tap to reset | RAW Power, Photomator, Darkroom | Every concept |
| Press and hold to compare | All of them | Every concept |
| Swipe to the next photo, swipe down to close | Darkroom, Photomator | Every concept but the photo as the control |
| Edits shown as a list or stack | Snapseed Stacks | History |
| One strength control for a look | VSCO | Looks |
| Editing the Photos item in place | Photomator, RAW Power, Darkroom | Keeping edits (section 5) |

Apple Photos is the baseline Redlamp's users will compare against; iOS 27 gives it a Tools tab (Clean Up, Extend, Reframe), star ratings and keywords, and a new system raw engine.

## 5. The platform and the engine

From [the platform note](notes/MOB-platform-and-architecture.md):

- **The gallery** is Redlamp's own grid over `PHAsset`, with Photos' albums, smart albums (RAW, Depth Effect, Live Photos), favourites, media subtypes and, from iOS 27, its ratings, keywords and captions. With limited access the app can't fetch user albums, so the gallery needs a limited mode, and the system picker stays the fallback for people who refuse access.
- **Keeping edits: both places, Redlamp's sidecar the source of truth.** The full `.redlamp` package autosaves to Redlamp's iCloud Drive container, keyed by the photo's iCloud identifier, which also carries it to the Mac; on Done, a compact copy of `edit.json` goes into Photos as `PHAdjustmentData` with a rendered version, once per batch, since each save asks permission. Photos stores one adjustment per photo and asks that it stay short and hold no images, so masks, history and autosaves can't live there.
- **Files and cards:** single files from Files and the share sheet in the first release; folders on drives and cards later, on the iPad first.
- **The engine on an iPhone:** decoding through a decoder extension started with `AppExtensionProcess` (iOS 26), with its memory limit measured before it is relied on; budgets from `os_proc_available_memory()` (opening a 48 MP ProRAW is estimated to peak near 1.2 GB); tiled export (ARC-05); no GPU work while the app is off screen; long exports through `BGContinuedProcessingTask`; goldens recorded on A-series GPUs; a photo identity that isn't a file path; and an iOS build on CI, which no workflow runs today.
- **What the UI reuses:** 4 of the 53 files in RedlampUI's model import AppKit, each for one call, and RedlampCanvas's controller and renderer import none. The obstacles are that `EditorModel` imports the macOS-only canvas module and identifies photos by file URL. The note proposes `RedlampEditing`, the editor's platform-neutral logic out of RedlampUI, and `RedlampPhotos`, the Photos library and its edits.
- **Which iPhones:** A17 Pro with 8 GB and later (iPhone 15 Pro, every iPhone 16 and 17, the iPhone Air), enforced with the App Store's `iphone-performance-gaming-tier` capability. That leaves out about 30% of the ten most-used iPhones in TelemetryDeck's data (the iPhone 13, 14 and 15); a required capability can be relaxed in an update but never raised.
- **Design language:** iOS 26's Liquid Glass bars, sheets with detents and tab bars that minimise; iOS 26's horizontal back swipe from anywhere in a view, which competes with horizontal drags on the photo (the critic's finding); the bottom 34 points and the top edge belong to the system.

## 6. The concepts, and what to prototype

From [the concepts note](notes/MOB-interaction-concepts.md) and the critic's review in it:

| Concept | Idea | Photo, standard iPhone | Critic (of 40) | Main risk |
| --- | --- | --- | --- | --- |
| A: Bar and ruler | Eight fixed modules, a strip of adjustments with rings, one full-width ruler | 60% | 33 | The same tap sets different adjustments if a module opens on its last one |
| E: My sliders | Pinned sliders suggested from the Mac's history, and search by name | 57% | 28 | Everyone's pins differ; the suggestions are unmeasured |
| B: Slider sheet | Lightroom's list of sliders in a sheet with three heights | 41% at medium height | 26 | A 2:3 photo fills 23% of the screen; 225 points on an iPhone SE |
| D: Flick compass | A marking menu: a ring of modules for a tap, two flicks from one spot once learnt | 66% | 26 | People may stay on taps, at three per adjustment |
| C: The photo is the control | Snapseed's drags on the photo | 72% | 24 | The main gesture is hidden from VoiceOver and fights the system's swipes |

The three tasks each concept was storyboarded against (brighten and warm, darken the sky with a Sky mask, crop to 4:5 and straighten) cost about the same everywhere: 2 taps and 1 or 2 drags in A, B and C. The concepts part on less common adjustments: lifting Shadows and lowering Orange Luminance takes 8 actions in A, 6 in B, C and D flicking, and 4 plus typing in E.

**What to prototype.** The interaction designer recommends A with three layers, each a switch in the harness (B's list pulled up from the strip, C's sideways drag on the photo, E's search), against D in full. The critic agrees with A, with changes: search a first-level button in both prototypes (it is Voice Control's way in), a visible grabber on the pull-up, the drag on the photo off by default, Undo within the thumb's reach, and a slide from a module's tab up onto its strip as a shortcut. The critic would not build D in full yet: its tap path doesn't rehearse the flick, which the marking-menu research relies on, so a small stroke-recording rig should first measure how accurately thumbs flick eight directions and whether people move to flicking; and the second full prototype should be B, the Lightroom model photographers bring with them.

**The owner chose on 13 October to prototype all five concepts (DEC-80),** to try each; eight fixed modules (DEC-81); and both places for a Photos photo's edit (DEC-76). **Before that, this study recommended the critic's version:** Prototype 1 is A with its layers; Prototype 2 is B; and the compass is a stroke rig first, built in full only if its errors and the move to flicking justify it. Each is measured on the phone, on an iPhone SE and the largest iPhone, with each hand, over three short sessions, on the three tasks and the fourth: time, taps and drags, wrong modules opened, accidental changes and where the thumb lands. This is DEC-80, for the owner.

**Problems every concept shares, from the critic:** Undo in the top bar is out of reach one-handed on a 440 × 956 phone; an eight-button top bar doesn't fit an iPhone SE; VoiceOver stepping by the catalog's step takes 180 swipes for a −1.8° straighten, so it needs coarse and fine steps; iOS 27's foldable iPhone (the critic's "iPhone Duo", unverified here) leaves A's photo under half its outer screen.

## 7. Decisions for the owner

Added to section 1 of the tracker as Proposed:

| ID | Decision | Recommended |
| --- | --- | --- |
| DEC-76 | Where does a Photos photo's edit live? | Both: the full sidecar in Redlamp's iCloud Drive container as the source of truth, and a compact edit with a rendered version in Photos |
| DEC-77 | When does Redlamp write to Photos? | On Done, once per batch; the sidecar autosaves meanwhile |
| DEC-78 | Which iPhones does the app support? | A17 Pro with 8 GB and later, through the App Store's performance tier, relaxed later if measurements allow |
| DEC-79 | How is decoding isolated on iOS? | A decoder extension started with `AppExtensionProcess`, its memory limit measured first; in-process decoding only for files that can't fit, after fuzzing |
| DEC-80 | Which concepts become prototypes? | Bar and ruler with its layers, and the Slider sheet; the Flick compass as a stroke rig first |
| DEC-81 | Eight fixed modules, with Optics inside Detail and Auto inside Looks? | Yes: every module in sight and in place on every iPhone |
| DEC-82 | Files and cards in the first release? | The Photos library and single files from Files and the share sheet; folders on drives and cards later, on the iPad first |

Smaller questions are on the wireframes canvas (whether a module opens on its first adjustment, what a sideways swipe on the photo does, where Undo goes, where making a mask lands, when a look applies, landscape) and in the notes: the distiller's fifteen, the platform note's nine (the deployment target, iOS 26 or 27, is best decided when the build starts) and the critic's nine.

## 8. Proposed tracker rows

Added to section 14 of the tracker as Proposed, in Phase 5:

| ID | Item | Size |
| --- | --- | --- |
| MOB-05 | The gallery over the Photos library: Photos' albums, smart albums and filters, ratings from iOS 27, a limited-access mode, originals downloaded from iCloud with progress, and the zoom into the editor | M |
| MOB-06 | Edits of Photos photos kept in Redlamp's sidecar, in its iCloud Drive container keyed by the photo's iCloud identifier, and written to Photos on Done as adjustment data with a rendered version; the same sidecar opens on the Mac | L |
| MOB-07 | The engine on the iPhone: decoding in a sandboxed extension, memory budgets, background GPU rules, golden renders on A-series GPUs, and an iOS build on CI (with ARC-05 and DN-04) | L |
| MOB-08 | The editor's logic shared by Mac and iPhone: `EditorModel`'s platform-neutral parts in a new `RedlampEditing` module, photos identified by more than a file path, and `RedlampPhotos` for the Photos library | L |
| MOB-09 | The iPhone editor, in the concept the prototypes choose: the eight modules, the ruler and its aids, masks as a context, crop, Looks, history, search and before and after | XL |
| MOB-10 | Accessibility from the start: the ruler adjustable for VoiceOver with coarse and fine steps, every gesture with a visible path, Voice Control through search, Dynamic Type to AX5 on an iPhone SE, Reduce Motion | M |

## 9. What waits on the owner

- **Seven screen recordings of Lightroom for iPhone,** whose steps are in [§7 of the Lightroom note](notes/MOB-lightroom-mobile.md#7-screen-recordings-for-the-owner-to-make): they confirm how its edit screen behaves under the finger.
- **The gaps that bother him,** ticked in the checklist in [§4 of the Lightroom note](notes/MOB-lightroom-mobile.md#4-whats-missing-against-lightroom-classic-and-lightroom-desktop): they become the phone's must-haves.
- **The decisions in section 7,** and the wireframes canvas's questions, first among them which concepts become prototypes (DEC-80), which MOB-04 waits on.
- **Trying the harness** on the Mac and the iPhone (MOB-02, MOB-03), on the branch `iphone-harness`, before it merges.
