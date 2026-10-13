# Lightroom for iPhone: from the gallery to export

Written by the Lightroom Mobile analyst of the mobile UX team, on 13 October 2026, for the iPhone design study (MOB-01, [#406](https://github.com/pdcgomes/redlamp/issues/406)). All sources were checked on **2026-10-13**. **Evidence** is what a source says; **Assessment** is our reading of it.

**What this rests on.** The agents can't use the app. Until the owner's screen recordings arrive (§7), this note rests on published material: Apple's App Store data and its customer reviews, and The Lightroom Queen (Victoria Bampton's site), whose release posts and feature chart are the most detailed public record of the mobile app. Adobe's own help pages refused every request (§9). Claims about how the edit screen behaves under the finger (sheets, sliders, gestures, landscape) come from no source we could reach; they are collected in §3.4 as **(unverified)**, each with the recording that will settle it.

## In short

- **The current version is 11.6.10, released on 12 October 2026** (bug fixes only), under the name "Lightroom: AI Photo Editor". It needs iOS 18 and has 4.77 stars from 336,956 ratings in the US store ([AS1]).
- **Two redesigns shape today's app.** June 2023 gave the app three tabs, Device, Lightroom and Discover, so it can browse the Photos library directly; October 2023 replaced the single scrolling tool strip with two rows, tool families below and panels above ([LQ-2306], [LQ-2310]). Since then it has mostly gained AI shortcuts (Quick Actions, adaptive presets, Generative Remove and Expand) and moved controls (Geometry went into Crop in February 2026) ([LQ-2410], [LQ-2602], [LQ-2604], [LQ-2608]).
- **A photo from the Photos library isn't edited in place.** The first edit copies it into Lightroom's library (and, with a subscription, the cloud); the result reaches Photos only as an exported copy ([LQ-2306], [LQ-CMP]). Reviewers ask for a round trip to the iCloud Photo Library ([RV us 2026-07-29 ★3]).
- **The gaps against the desktop are real and long-lived.** The checklist in §4 has **42 lines**, among them Point Color, Calibration, Background, Objects and People masks in the Masking tool, Red Eye, Photo Merge, a full history, zoom beyond 2:1, duplicates and Denoise on the iPhone (it reached M1 iPads in August 2026) ([LQ-CMP], [LQ-2608]).
- **Reviews are mostly about money, not design.** Of 222 critical reviews in the last 12 months across five storefronts, 123 are about price, the paywall or billing; 55 about crashes and slowness; 36 mention AI (the new name, an AI bar, generative tools); 30 about presets (Recommended preset categories removed in August 2026); 19 about a confusing or changed layout ([RV]).
- **Praise is for ease and continuity.** Among 865 positive reviews, the most common themes are ease of use (157), results (118), depth of tools (111) and working across phone, iPad and desktop (106) ([RV]).
- **For Redlamp:** keep the Photos-library-first gallery, the two-level toolbar's grouping, desktop names and order for sliders, named versions and press-and-hold before; do better on parity, round-tripping with Photos, history, zoom and stable positions for controls; avoid moving controls between releases, permanent AI chrome, cloud-dependent tools and any wall between an edit and saving it (§6).

---

## 1. The current version and its recent history

**Evidence.** The iTunes Lookup API gives version **11.6.10**, released **2026-10-12**, with the release note "bug fixes and stability improvements"; app id 878783582, seller Adobe Inc., free with in-app purchases, minimum iOS 18.0, 367 MB, average rating 4.77 from 336,956 ratings ([AS1]). The iTunes Search API confirms the id as the first result for "lightroom" ([AS3]). The App Store page lists the in-app purchases: Premium at $1.99 a month (40 GB) to $7.99 a month (100 GB), $49.99 a year (100 GB), weekly plans, and a "Lightroom plan 1TB" at $9.99, its period not shown ([AS2]).

The store description leads with AI: Quick Actions, adaptive presets, background blur, Generative Remove, community presets, batch edits and video ([AS1]). The name became "Lightroom: AI Photo Editor"; reviewers first complain about the name on 15 June 2026, with version 11.4 ([RV us 2026-06-15 ★1]), so the rename probably came then (unverified).

Version numbers and dates below are the App Store's version history ([AS2]) for 11.0 onwards. Before that they come from The Lightroom Queen's release posts, and for 10.1 to 10.3 from the first review of each version in the review feed ([RV]).

| When | Version | Change to the UI or workflow | Source |
|---|---|---|---|
| June 2023 | 8.4 | Major redesign: three tabs at the bottom, **Device**, **Lightroom** and **Discover**. The Device tab shows the Photos library and its albums; the Lightroom tab is the cloud library, with albums behind a pop-up at the top of the grid. On iOS, Versions and Reset moved under the Undo button. Edit Replay (a time-lapse video of an edit) added to Share. | [LQ-2306] |
| October 2023 | 9.0 | **New Edit view** for everyone on iPhone: a bottom row of Presets, Crop, Sliders, Masking and Healing; tapping one shows a second row of panel buttons or that tool's options. Ratings and flags moved to Info & Rating in the "…" menu. Lens Blur (early access) and HDR editing. | [LQ-2310] |
| May 2024 | 9.3 | Healing renamed **Remove**, with Generative Remove (runs on Adobe's servers) beside Heal and Clone; Lens Blur out of early access, with a Focus Range slider on mobile. | [LQ-2405] |
| October 2024 | 10.0 | **Quick Actions** (early access on iPhone): AI shortcuts to enhance a subject, blur a background, retouch portraits. Generative Remove generally available; Detect Objects added to Remove on mobile. Content Credentials. Swiping between photos in the Device detail view made the default. | [LQ-2410] |
| December 2024 | 10.1 | An **i** button at the top of the detail view opens the Info panel (EXIF copy, keywords, a Location tab). | [LQ-2412] |
| February 2025 | 10.2 | Adaptive Color and B&W profiles; Quick Actions gain Fix Angle (auto Geometry) and a shimmer that shows the detected area. | [LQ-2502] |
| April 2025 | 10.3 | Quick Actions can pick individual people; a carousel in Share to add nearby photos. | [LQ-2504] |
| June 2025 | 10.4 | A preference to download the original when using generative tools (mobile edits a smart preview by default); Scene quick actions (Water and others); an icon in the toolstrip when AI settings need updating. | [LQ-2506] |
| October 2025 | 11.0 | Blemish removal in Quick Actions; Snow in Scene Enhance; Adaptive: Landscape presets; object detection in Generative Remove that takes shadows and reflections. | [AS2], [LQ-2510] |
| December 2025 | 11.1 | Free users can share web albums by link or QR code. | [AS2], [LQ-2512] |
| February 2026 | 11.2 | iOS 18 minimum. **Crop redesigned** on iPhone, with pop-ups for social media aspect ratios; Geometry moved into a tab of Crop. Device photos export through the same Share menu as the Lightroom tab; several device photos can be selected to share. | [AS2], [LQ-2602], [LQ-2604] |
| April 2026 | 11.3 | Twelve film-inspired presets; better opening of several photos from the native photo apps. | [AS2], [LQ-2604] |
| May 2026 | 11.3.2 | Blemish touch-up tools in Quick Actions › Retouch; many keyboard shortcuts for iPhone and iPad. | [AS2], [LQ-2604], [LQ-2606] |
| June 2026 | 11.4 | Edit a photo's location on a map; an improved Select Subject model (all apps). | [AS2], [LQ-2606] |
| August 2026 | 11.5 | **Generative Expand**; Crop renamed **Crop & Expand**; Animate (photo to video, generative credits). Reviewers report that the Recommended presets lost their categories (Cinematic, HDR, B&W and others) from about 12 August. | [AS2], [LQ-2608], [RV] |
| September 2026 | 11.5.30 | Photo to Video and an improved AI search. From 2 September, reviewers describe an **AI assistant bar** at the bottom of the edit screen that can't be hidden (not in Adobe's notes; unverified). | [AS2], [RV] |
| September 2026 | 11.6 | Camera and lens support (the iPhone 18 Pro among them). | [AS2], [LQ-2609] |
| 12 October 2026 | 11.6.10 | Bug fixes. | [AS1] |

**Assessment.** The two 2023 redesigns set the structure that exists today; everything since has been added inside it. The additions of the last two years are mostly AI shortcuts layered over the classic tools (Quick Actions, adaptive presets, generative tools, and now an AI bar), while some classic tools moved (Healing to Remove, Geometry into Crop). Redlamp's feature inventory still describes the pre-2023 single strip of tabs (`docs/lightroom-feature-inventory.md`, §20); it should be updated when the study's findings are merged.

---

## 2. Navigation

### 2.1 How the app opens: two libraries

**Evidence.** Since June 2023 the app has three tabs at the bottom: Device, Lightroom and Discover ([LQ-2306]).

- **Device** shows the photos in Apple's Photos app, with a pop-up at the top of the grid to browse its albums. Seeing a photo there doesn't put it in Lightroom ([LQ-2306]).
- **Lightroom** is Lightroom's own library (cloud-synced with a subscription), with albums behind a pop-up at the top of the grid ([LQ-2306]). It searches by content without keywords (AI search), filters by rating, flag, file type, people, location, keywords and edit status, and sorts six ways; it has no smart albums, stacks, colour labels or renaming ([LQ-CMP]). Adobe's notes for 11.5.30 mention an improved AI search ([AS2]).
- **Discover** holds community edits and tutorials ([LQ-2306]).

Which tab the app opens on, and whether it remembers the last one, isn't stated in any source we reached (unverified). One reviewer reports that the Lightroom tab jumps back to the first photo of a large library each time it is opened ([RV us 2026-05-07 ★1]). The Lightroom Queen's members' guide has a section on filtering and sorting in the mobile grid views, but its text is behind a paywall, so whether the Device tab filters by anything other than the album is unverified ([LQ-M4]).

### 2.2 Opening a photo, and whether it's imported

**Evidence.** Tapping a photo in the Device grid opens it in the Edit view. **Any edit**, whether a slider, a crop or metadata, adds the photo to Lightroom's library, and with a subscription uploads it to the cloud. Edited photos then carry an LR badge in the Device grid, and tapping a badged photo opens Lightroom's copy with its edits ([LQ-2306]). Swiping left and right moves between photos in the Device detail view, by default since October 2024 ([LQ-2410]). Version 11.3 improved opening several photos "directly from your native photo apps" ([AS2]), which suggests a share-sheet or Open In path from Photos (unverified).

**Assessment.** So a Device photo is *imported on first edit*, not edited in place. The Photos library keeps the untouched original; Lightroom holds a second copy with the edit.

### 2.3 Where the edit is saved and how it travels

**Evidence.**

- Mobile edits are stored in the cloud, not in the file; originals are uploaded and downloaded on demand, and the app manages local space ([LQ-CMP]). By default mobile edits a smart preview, downloading the original only when needed; since June 2025 a preference downloads it for generative tools, whose fills are otherwise made from the low-resolution preview ([LQ-2506]).
- Lightroom Desktop sees the same cloud library ([LQ-CMP]). Lightroom Classic syncs one catalog with the cloud: photos added on mobile download into Classic, while Classic uploads only 2,560-pixel smart previews, and only of the collections chosen for sync. Keywords have synced since June 2026; versions and album folders don't reach Classic ([LQ-SYNC], [LQ-CMP], [LQ-2606]).
- To reach the Photos library, the photo is exported through Share (Save to the camera roll, Export As with format, size and other options); device photos use the same Share menu since February 2026 ([LQ-2602], [LQ-2306]). Mobile exports Original, JPEG, AVIF, JPEG XL, TIFF and DNG in sRGB, Display P3, Adobe RGB or ProPhoto, with resizing, output sharpening, a watermark and limited metadata, and has no saved export presets ([LQ-CMP]).

**Assessment.** The export lands in Photos as a new item beside the original rather than as an edit of it (unverified, to be seen in recording 7). A reviewer contrasts this with Darkroom, which round-trips edits with the iCloud Photo Library ([RV us 2026-07-29 ★3]). Two reviewers report that the saved image looks warmer or darker than the edit on screen ([RV gb 2026-03-02 ★2], [RV us 2026-07-06 ★2]), and one that exported metadata is unreadable ([RV ca 2026-09-05 ★2]).

---

## 3. The edit screen

### 3.1 The toolbar and its tools

**Evidence.** Since October 2023 the Edit view has a bottom row of tool families; tapping one shows, above it, either a second row of panel buttons (for the sliders) or that tool's own options ([LQ-2310]). The families and panels named in the sources, as of October 2026:

| Bottom row | What opens | Source |
|---|---|---|
| Quick Actions | AI shortcuts by content: Subject, Background, Sky, Retouch (people, blemishes), Scene (water, snow and other landscape elements), Fix Angle | [LQ-2410], [LQ-2502], [LQ-2506], [LQ-2510], [LQ-2606] |
| Presets | Preset groups, including Recommended, Premium, adaptive groups (Portrait, Landscape, Blur Background), film-inspired presets and the user's own | [LQ-2310], [LQ-2510], [LQ-2412], [AS2], [RV] |
| Edit (sliders) | A second row of panels: Light, Color, Effects, Detail, Optics, and also Profile, Auto, Lens Blur; Optics and Profile were hidden by default in the 2023 early-access design, shown from "…" › View Options | [LQ-2310], [LQ-2306], inventory §20 |
| Crop & Expand | Crop with aspect pop-ups for social formats, Geometry as a tab, Generative Expand, Constrain Crop | [LQ-2602], [LQ-2604], [LQ-2608], [LQ-M5] |
| Masking | Subject, Sky, Brush, Linear and Radial Gradient, Color and Luminance Range; Depth Range (unverified) | [LQ-CMP] |
| Remove | Remove (with Detect Objects and Generative), Heal, Clone; People distraction removal | [LQ-2405], [LQ-2410], [LQ-M1], [LQ-M2] |

The top bar holds Undo, with Versions and Reset under it (since June 2023, on iOS), and the **i** button for Info (since December 2024) ([LQ-2306], [LQ-2412]). Ratings and flags are in Info & Rating ([LQ-2310]). Whether Quick Actions sits in the bottom row or elsewhere, the exact order of the row, and the place of the AI bar reviewers describe, are unverified.

### 3.2 Tools, one by one

- **Sliders and panels.** Mobile has the global Basic tone and colour sliders, tone curves, colour mixer, colour grading, sharpening, noise reduction, grain, effects, lens corrections with limited controls, Upright, Lens Blur with limited controls and HDR editing on supported devices; it has no Point Color and no Calibration ([LQ-CMP]). White balance sits in the Color panel, as on Desktop, not in a Basic panel as in Classic ([LQ-SYNC]). Denoise came to iPads with M1 or later in August 2026, in the Detail panel; not to the iPhone ([LQ-2608]).
- **Presets and adaptive presets.** Presets can be created, applied and imported, and sync to the other cloud apps; Recommended presets are AI-chosen ([LQ-CMP]). Adaptive presets carry AI masks and recompute them for each photo ([LQ-2410]); Adaptive: Landscape (October 2025) can target up to eight landscape elements ([AS2], [LQ-2510]). Reviewers say the Recommended tab lost its categories in August 2026 ([RV], §5), and that an ended subscription locks presets bought elsewhere ([RV ca 2026-03-07 ★2]).
- **Masking.** The Masking tool has gradients, brushes, range masks, Subject and Sky; Background, Objects and People aren't in it ([LQ-CMP]). People and landscape masking are reached only through Quick Actions ([LQ-2512], [LQ-2504]). The improved Select Subject model of June 2026 is in all apps; the Feather and Edge sliders for AI masks (August 2026) are Classic and Desktop only ([LQ-2606], [LQ-2608]). There are no brush presets for local adjustments ([LQ-CMP]). How a brush is sized and how fingers refine a mask is described only in members' pages (unverified).
- **Remove.** On mobile the tool is split into an **Add** view, where the mode and brush size are chosen and spots brushed, and a **Refine** view, where each repair is adjusted ([LQ-M1]). Generative Remove needs internet and uses Adobe's servers ([LQ-2405]); Detect Objects selects the object from a rough stroke ([LQ-2410]); since 11.0 it removes shadows and reflections with the object ([AS2]). People removal is on mobile, blemish removal mobile only, reflection and dust removal desktop only ([LQ-M2]).
- **Versions, undo and history.** Versions save named states and stand in for snapshots; history is partial (automatic versions), not a full list ([LQ-CMP]). Real copies (duplicates) are desktop only ([LQ-CMP], [LQ-M3]).
- **Copy and paste.** Settings can be copied and pasted to several photos ([LQ-CMP]); a Copy Settings dialog exists on iOS ([LQ-2412], in its bug list). Presets that contain AI masks recompute them when applied ([LQ-2410]); whether pasted AI masks are recomputed is for recording 6. One reviewer finds pasting with masks inconsistent ([RV de 2026-04-18 ★1]).
- **Before and after; zoom.** Mobile has a before/after preview ([LQ-CMP], [LQ-M3]); zoom goes from Fit to 2:1, against 1,600% on the desktop; it shows a histogram but no RGB values ([LQ-CMP]).
- **Crop.** Redesigned in February 2026: features moved, social aspect pop-ups added, Geometry folded in; 11.2 also made crop handles scroll and zoom more smoothly ([LQ-2602], [AS2]). A reviewer counts six taps to rotate 270° in the new menu ([RV ca 2025-12-16 ★2]).

### 3.3 Landscape orientation and the iPad

**Evidence.** Sources say little. The iPad got Quick Actions in December 2025 and the redesigned Crop in April 2026, where Geometry likewise moved from the main Edit panels into Crop ([LQ-2512], [LQ-2604]); it has keyboard shortcuts, shown in iPadOS 26's menu bar ([LQ-2606]), and Denoise on M1 or later ([LQ-2608]). Reviewers praise the iPad with a pencil for editing on the go ([RV gb 2025-12-06 ★5]). How the iPhone layout changes in landscape is unverified (§3.4).

### 3.4 Behaviour to confirm in the recordings

These are believed from general knowledge of the app, Redlamp's own inventory (which records press-and-hold before from working knowledge) or older versions; none is confirmed by a source we reached. Each names the recording in §7 that will settle it.

| Claim | Status | Recording |
|---|---|---|
| A panel opens as a sheet over the lower part of the screen, the photo shrinking to stay visible above it | unverified | 2 |
| Sliders are horizontal, with the value at the right; double-tapping a slider resets it | unverified | 2 |
| Values can't be typed on the iPhone | unverified | 2 |
| Holding two fingers on a tone slider shows clipping | unverified | 2 |
| Pressing and holding the photo shows the before | unverified (inventory §20) | 2 |
| Pinching zooms; double-tapping the photo toggles fit and 100% | unverified | 2 |
| A two-finger tap cycles the info overlays and histogram | unverified | 1, 2 |
| In landscape, the tool rows move to a column at the right edge | unverified | 2 |
| Mask brushing has Size, Feather and Flow, with Erase as a mode; adding and subtracting via + and − on the mask | unverified | 3 |
| Copy Settings is in the "…" menu of the Edit view, Paste in the grid's selection mode, both with category checkboxes | unverified | 6 |
| The Device tab can filter (favourites, edited, media type) and search | unverified | 1 |
| Saving to the camera roll creates a new item in Photos | unverified | 7 |
| An AI assistant bar sits at the bottom of the edit screen and can't be hidden | reported by reviewers only | 2 |

---

## 4. What's missing against Lightroom Classic and Lightroom Desktop

For the owner to mark. Each line says what the iPhone app lacks, and where Classic (C) or Desktop (D) has it. [LQ-CMP] is The Lightroom Queen's feature chart, updated 9 October 2026, whose Mobile column covers iPhone, iPad and Android together.

**Editing**

- [ ] Point Color, with its Variance slider (C, D) ([LQ-CMP], [LQ-2510]; a reviewer, [RV us 2026-09-20 ★1])
- [ ] Calibration panel (C, D) ([LQ-CMP])
- [ ] AI Denoise on the iPhone; iPads with M1 or later have it since August 2026 (C, D) ([LQ-2608]; reviewers, [RV de 2025-12-08 ★3], [RV gb 2026-05-02 ★1])
- [ ] Raw Details and Super Resolution (C, D) (unverified; one reviewer asks for them, [RV us 2026-05-16 ★4])
- [ ] Full lens correction controls: manual profile choice and manual distortion, vignetting and defringe sliders (C, D); mobile has "limited controls" ([LQ-CMP]; a reviewer asks for manual chromatic aberration sliders, [RV ca 2026-10-01 ★4])
- [ ] Full Lens Blur controls, such as the Cat Eye slider (C, D); mobile has a Cat Eye button ([LQ-CMP], [LQ-2412])
- [ ] HDR Limit slider (C, D) ([LQ-2510])
- [ ] RGB readout under the finger (C, D); mobile shows a histogram only ([LQ-CMP])
- [ ] Interactive histogram, dragging it to adjust (D) ([LQ-2606])
- [ ] Zoom beyond 2:1, to 1,600% (C, D) ([LQ-CMP])
- [ ] Soft proofing (C) ([LQ-CMP])
- [ ] Per-camera raw defaults (C); mobile has a single default ([LQ-CMP])

**Masking and removal**

- [ ] Background, Objects and People masks in the Masking tool (C, D); People only through Quick Actions ([LQ-CMP], [LQ-2504])
- [ ] Landscape masks in the Masking tool (C, D); only through Quick Actions' Scene ([LQ-2512], [LQ-2506], [LQ-2510])
- [ ] Feather and Edge sliders for AI masks (C, D) ([LQ-2608])
- [ ] Brush presets for local adjustments (C; built-in only on D) ([LQ-CMP])
- [ ] Curves inside masks (D has had them since April 2023) (unverified for mobile; [LQ-2310] for D)
- [ ] Red Eye and Pet Eye correction (C; Red Eye on D) ([LQ-CMP])
- [ ] Reflection removal (C, D) ([LQ-M2], [LQ-2510])
- [ ] Dust removal (C, D) ([LQ-M2], [LQ-2510])

**History, copies and comparison**

- [ ] A full history list, stepping back to any state (C); mobile keeps automatic versions only ([LQ-CMP]; a reviewer wants history to reach Classic, [RV ca 2025-12-06 ★5])
- [ ] Duplicates or virtual copies (C, D) ([LQ-CMP], [LQ-M3])
- [ ] Reference or Compare view, two photos side by side (C, D) ([LQ-CMP]; [RV gb 2026-03-22 ★3])
- [ ] Sync settings across a selection, Auto Sync and Match Total Exposures (C) (unverified; mobile has copy and paste, [LQ-CMP])
- [ ] Flatten AI edits and Render to DNG (C, D) ([LQ-2608])

**Merging and AI services**

- [ ] Panorama merge (C, D) ([LQ-CMP])
- [ ] HDR merge (C, D) ([LQ-CMP]; [RV gb 2026-03-22 ★3], [RV gb 2026-06-13 ★5])
- [ ] Generative Upscale and AI sharpening by Topaz (D, generative credits) ([LQ-2602], [LQ-2606])
- [ ] Prompt to Edit (D, early access) (unverified for the iPhone: Android has Edit Using Describe since April 2026, and iPhone reviewers describe an AI assistant bar) ([LQ-2609], [LQ-2604], [RV])

**Library**

- [ ] Smart albums (C, D) ([LQ-CMP])
- [ ] Stacks (C, D) ([LQ-CMP])
- [ ] Colour labels (C, D) ([LQ-CMP])
- [ ] Renaming photos (C, D) ([LQ-CMP])
- [ ] Editing capture time (C, D) ([LQ-CMP])
- [ ] Hierarchical keywords (C); mobile and D keep them flat ([LQ-CMP])
- [ ] Batch metadata editing on iOS (C, D; Android has it) ([LQ-CMP])
- [ ] Assisted Culling, visual-similarity stacks and duplicate detection (C, D; duplicates C) ([LQ-2510], [LQ-2606])
- [ ] Editing photos on an SD card or USB drive without adding them to the library (C, D Local mode) (unverified; reviewers ask for it, [RV ca 2025-12-12 ★1], [RV us 2026-05-29 ★5])

**Export and output**

- [ ] Saved export presets (C) ([LQ-CMP])
- [ ] PNG and PSD export (C) ([LQ-CMP])
- [ ] Export to any ICC profile (C); mobile offers sRGB, Display P3, Adobe RGB and ProPhoto ([LQ-CMP])
- [ ] Third-party plug-ins, tethering, and the Book and Web modules (C) ([LQ-CMP])

That is **42 lines**, of which **5** are (unverified).

---

## 5. What users praise and complain about

### 5.1 Method

**Evidence.** The public review feed returns at most 500 reviews per storefront (ten pages of 50). We read all of them for the US, UK, Canada, Australia and Germany: 2,500 reviews, averaging 4.22 stars, against the store's 4.77 from all ratings ([RV], [AS1]). The US storefront's 500 cover only 15 March to 11 October 2026; the others reach back to 2024 (Australia to 2020). For the counts we kept the **last 12 months** (13 October 2025 to 11 October 2026): **1,087 reviews**, of which 865 have 4 or 5 stars and 222 have 1 to 3 (US 500, Germany 206, UK 177, Canada 135, Australia 69; German-store reviews are in German and English).

Themes were counted by keyword in English and German, and the critical reviews were all read to check them. A review can count under several themes. Counts are indicative, not exact.

### 5.2 Complaints (222 reviews of 1 to 3 stars)

| Theme | Reviews | Notes |
|---|---|---|
| Price, subscription, paywall, billing | 123 | Within it: features moved behind Premium or a free tier that does little (36); cancellation charges and annual contracts billed monthly (25); price rises of 25 to 60% (16). Several report editing a photo and only then being asked to pay to save it ([RV us 2026-07-18 ★1], [RV gb 2026-01-18 ★1]). |
| Crashes, freezes, slowness, lost edits | 55 | Crashes on launch since 11.5 ([RV us 2026-09-04 ★3], [RV us 2026-10-06 ★1]); edits reverting while working ([RV us 2026-03-29 ★2]); editing tools greyed out in 11.6.1 ([RV gb 2026-10-09 ★1]). |
| AI: the name, the AI bar, generative tools | 36 | The "AI Photo Editor" name (8, from June 2026); an AI assistant bar that takes space and can't be hidden (6, from September 2026: [RV us 2026-09-07 ★3], [RV gb 2026-09-07 ★1], [RV us 2026-09-07 ★1]); a wish for a toggle even from a 5-star reviewer ([RV us 2026-10-01 ★5]); generative results that add objects ([RV us 2026-09-13 ★1]). |
| Presets | 30 | Recommended presets lost their categories in August 2026 (12 reviews since 1 August: [RV us 2026-08-17 ★2], [RV us 2026-08-23 ★1], [RV de 2026-09-17 ★1]); presets that vanished ([RV gb 2026-02-06 ★2]); presets that can't be deleted ([RV us 2026-10-07 ★2]). |
| Sync, cloud storage, offline, sign-in | 29 | Where photos are and what syncing does is unclear ([RV ca 2026-03-10 ★2], [RV ca 2026-10-06 ★1]); photos uploaded to the cloud can't be edited offline later ([RV de 2026-07-30 ★2], [RV de 2026-06-02 ★2]). |
| Remove and retouch results | 21 | Removal not as advertised, mostly from people who bought Premium for it ([RV gb 2026-04-21 ★1]). |
| Confusing layout, moved controls | 19 | Crop's new menu ([RV ca 2025-12-16 ★2]); nothing can be found since the update ([RV de 2026-09-04 ★2]); controls hidden and spread around ([RV us 2026-08-23 ★2]); an accidental tap on the magic wand spoils the photo ([RV us 2026-09-03 ★2]). |
| Exported image differs from the edit | 16 | Warmer, darker or lower in resolution than on screen ([RV gb 2026-03-02 ★2], [RV us 2026-07-06 ★2], [RV us 2026-05-21 ★1]). |
| Support | 12 | No way to reach anyone, especially when signed out. |
| Missing desktop features | 11 | Denoise, Point Color, side-by-side comparison, HDR merge ([RV de 2025-12-08 ★3], [RV us 2026-09-20 ★1], [RV gb 2026-03-22 ★3]). |

### 5.3 Praise (865 reviews of 4 and 5 stars)

Half (431) are under 60 characters, such as "great app". Among the rest:

| Theme | Reviews | Example |
|---|---|---|
| Easy, simple, intuitive | 157 | Simple enough for a JPEG shooter to move to raw ([RV gb 2026-01-31 ★5]) |
| Results and quality | 118 | |
| Depth of tools, control | 111 | Presets for speed and sliders for depth ([RV gb 2026-03-20 ★5]) |
| Working across phone, iPad and desktop | 106 | Edit on the train, finish on the iPad ([RV gb 2025-12-13 ★5]); controls are the ones known from the desktop ([RV gb 2026-06-09 ★5]) |
| Presets | 27 | |
| Masking | 21 | Masks the main reason to use it ([RV au 2026-02-16 ★5], [RV de 2026-02-08 ★5]) |
| Raw support | 18 | |
| Remove | 13 | |

### 5.4 Forums and articles

Adobe's community forum, Reddit, DPReview and PetaPixel refused automated requests (§9), so this section rests on App Store reviews and The Lightroom Queen. The Lightroom Queen's own verdict on the June 2023 redesign is that the new app with two grid views "might look a bit confusing" at first ([LQ-2306]).

**Assessment.** Interface complaints are a small share (19 of 222), but they cluster after releases that moved things: Crop in February 2026, preset categories in August, the AI bar in September. People who praise the app praise continuity with the desktop and how quickly it gets a result. The largest complaint, money, doesn't apply to a free, open-source app, but the pattern inside it does: people are angriest when the app lets them work and then stops them keeping the result.

---

## 6. Keep, do better, avoid

### Keep

| What | Why |
|---|---|
| Open on the Photos library, with its albums, and edit with a tap | The owner's direction; Lightroom added the Device tab for people who organise in Photos and want only the editor ([LQ-2306]). |
| A badge on photos that have an edit | Shows at a glance which photos are done, in a grid Lightroom doesn't own ([LQ-2306]). |
| Grouping the tools into a few families, with panels a second level down | Adobe's stated aim was less scrolling along the toolbar ([LQ-2306]); a phone can't show all panels at once. |
| The desktop's slider names, ranges and order | Reviewers who use both value finding the same controls ([RV gb 2026-06-09 ★5]); it is Redlamp's own principle. |
| Advanced panels out of the way until asked for | The cloud apps hide many sliders by default so as not to intimidate ([LQ-CMP]); Optics and Profile were behind View Options ([LQ-2306]). |
| Named versions | A cheap way to try alternatives on a phone ([LQ-CMP]). |
| Press and hold for before | The quickest comparison on a touch screen (to be confirmed, §3.4). |
| Remove in two steps, adding then refining | Keeps brushing and adjusting from fighting over the same gestures ([LQ-M1]). |
| A carousel in Share to add nearby photos | Exporting a few photos from the same moment is common ([LQ-2504], [AS2]). |

### Do better

| What | Why |
|---|---|
| Edit a Photos-library photo in place, with the edit stored as Photos adjustment data and Redlamp's recipe, so Photos shows it and can revert it | Lightroom copies the photo into its own library and sends back an export ([LQ-2306]); reviewers ask for a round trip ([RV us 2026-07-29 ★3]). Whether PhotoKit can carry a Redlamp recipe is for the platform study. |
| Parity on the tools Lightroom leaves out: Point Color, Calibration, every mask type inside Masking, Denoise on the iPhone, zoom past 2:1 | These are the gaps users name (§4, §5.2); Redlamp runs on-device on an A17 Pro floor and has no reason to hold back tools for the phone. |
| A full history, not only automatic versions | Mobile history is partial ([LQ-CMP]); stepping back through an edit matters more where precise input is harder. |
| Stable positions, so muscle memory survives releases | Lightroom moved Geometry into Crop, rebuilt Crop's menu and removed preset categories, each followed by complaints (§5.2). Moving between panels should be one consistent gesture in a fixed order (the team's concepts). |
| Masks in one place | Lightroom splits AI masks between Masking and Quick Actions ([LQ-CMP], [LQ-2512]); one Masking tool with every kind is easier to learn. |
| Make it clear where a photo and its edit live | Reviewers can't tell what syncs or where photos are stored ([RV ca 2026-03-10 ★2]); Redlamp has no cloud, so it can say plainly that the edit lives with the photo. |
| Work at full resolution and offline | Mobile edits smart previews and makes generative fills from them unless set otherwise ([LQ-2506]); cloud copies can't be edited offline ([RV de 2026-07-30 ★2]). |

### Avoid

| What | Why |
|---|---|
| Moving or removing controls without a path back | The crop and preset changes are among the few design complaints, and they came from long-time users (§5.2). |
| Permanent AI chrome on the edit screen | The AI bar takes screen space that can't be reclaimed; even satisfied users ask for a toggle ([RV us 2026-09-07 ★3], [RV us 2026-10-01 ★5]). |
| Tools that need a server | Generative Remove needs internet ([LQ-2405]); Redlamp is on-device by design. |
| Letting someone edit and then stopping them saving | The angriest reviews (§5.2). Redlamp should never put anything between an edit and keeping it. |
| One-tap buttons that rewrite the whole edit | An accidental tap on the "magic wand" spoils a photo ([RV us 2026-09-03 ★2]); anything automatic should be undoable in one step and visible as ordinary slider values. |
| Hiding everyday commands in "…" | Lightroom moved ratings into "…" in 2023 and then brought Info back to a top-bar button in 2024 ([LQ-2310], [LQ-2412]). |
| An export that doesn't match the screen | Reported colour and resolution changes (§5.2) undermine trust in every other tool. |

---

## 7. Screen recordings for the owner to make

Each recording should be under two minutes, on the iPhone in portrait unless stated, with Lightroom 11.6.10, using a raw photo from a camera and an iPhone photo where possible. iOS screen recordings don't show touches, so turn the microphone on (long-press the record button in Control Centre) and say each gesture as you make it. These are the primary evidence for this note; §3.4 lists what each should settle.

1. **Opening a photo from the Photos library.** Quit Lightroom fully, then open it and wait for the first screen. Tap the Device tab. Open the album pop-up and choose Favorites, then another album. Look for filter, sort and search controls and try each. Tap a photo you haven't edited. Swipe left and right to the next photos. Make one small edit, go back to the grid, and show the LR badge. Tap the Lightroom tab and show its album pop-up, filters and search, then back to Device.
2. **Every edit tool and panel.** Open an unedited raw photo. Tap each button in the bottom row in turn. In the sliders tool, tap each panel (Light, Color, Effects, Detail, Optics and any others) and scroll through its sliders. On Exposure: drag slowly, drag fast, double-tap the slider, tap its number, hold two fingers on it. Press and hold the photo. Pinch to zoom, double-tap the photo, tap it with two fingers. Show the AI bar if there is one, and whether it can be hidden. Turn the phone to landscape and tap through two panels there.
3. **A local edit with a mask.** Open a portrait or a photo with a clear subject. Masking › new mask › Select Subject, and wait for it. Raise Exposure. Add to the mask with a brush: change its size, feather and flow, brush while zoomed in, then subtract a part. Invert the mask and back. Show the overlay options. Add a second mask with Select Sky and a linear gradient, then rename, hide and delete one.
4. **Remove.** Open a photo with a small spot and a larger object. In Remove, brush the spot in Remove mode. Turn on Detect Objects and circle the larger object. Try Generative on it (it needs a connection and may ask for credits; note what it asks). Switch to Heal, then Clone, on another spot. Open the Refine view and adjust one repair. Show any People or distraction option. Undo the last repair.
5. **Presets, an adaptive preset and Quick Actions.** Open Presets and scroll the groups (Recommended, Premium, adaptive, yours). Tap several to preview, then apply one and change its amount. Apply an Adaptive preset (Sky, Portrait or Landscape) and show the masks it made. Create a preset from the current settings and show the category choices. Open Quick Actions and try Subject, Background and Scene.
6. **Versions, undo and copying settings.** Make three edits, then Undo twice and Redo once. Open Versions under Undo: save a named version, make another edit, switch between versions, and show the automatic versions. Show Reset's choices. Copy the settings and show the category checkboxes. Go to the grid, select three other photos and paste. Open one to check that its masks were recomputed.
7. **Export and share.** Open an edited photo. Share › Export As: show format, size, colour space, metadata, watermark and other options, then export a JPEG to the camera roll. Open Photos and show whether the export is a new item beside the original or replaces it, and whether the original is still unedited. Back in Lightroom, select three photos in the Device grid and share them to another app. Show Save to Files if offered.

Seven recordings, one more than suggested, so that presets and versions each get their own. An eighth, optional one for later: recording 2 repeated on an iPad, in both orientations.

---

## 8. What this note couldn't establish

- **Everything in §3.4,** the behaviour of sheets, sliders, gestures and landscape, until the recordings arrive.
- **The AI assistant bar:** reported by reviewers from 2 September 2026, absent from Adobe's release notes and The Lightroom Queen's September post; what it does and whether it relates to Android's Edit Using Describe is unknown.
- **The removal of Recommended preset categories:** reported by many reviewers from August 2026, not in Adobe's notes.
- **The current free tier:** reviewers disagree about which adjustments need Premium (some say only presets and masks, others that even Light and Color do); not checked against Adobe.
- **The rename to "Lightroom: AI Photo Editor":** current name confirmed ([AS1]); its date is inferred from reviews.
- **Five checklist lines** in §4 marked (unverified).

## 9. Sources not reached

- **helpx.adobe.com** (Adobe's help, including the mobile feature summary and keyboard shortcuts): HTTP 403 on four pages, tried once each.
- **Reddit:** www.reddit.com returned 403; old.reddit.com returned its sign-in page.
- **DPReview:** HTTP 403.
- **PetaPixel:** a Cloudflare challenge on the site and its search API.
- **Adobe Community** (community.adobe.com): the forum page is a JavaScript shell with no posts; its RSS address returned 404.
- **Search engines:** DuckDuckGo answered with a captcha; Bing returned the same generic Lightroom results for every query, so no article search was possible.
- **The Lightroom Queen's members' guide** (premium-cloud pages): only each page's outline and first lines are public; those outlines are cited as [LQ-M1] to [LQ-M5] and nothing beyond them is claimed.
- **YouTube:** not tried, as advised.

---

## References

All checked 2026-10-13.

**Apple**

- [AS1] iTunes Lookup API, Lightroom: AI Photo Editor: <https://itunes.apple.com/lookup?id=878783582&country=us>
- [AS2] App Store page, with version history and in-app purchases: <https://apps.apple.com/us/app/lightroom-ai-photo-editor/id878783582>
- [AS3] iTunes Search API: <https://itunes.apple.com/search?term=lightroom&entity=software&country=us>
- [RV] Customer reviews feed, pages 1 to 10 for each of the us, gb, ca, au and de storefronts: `https://itunes.apple.com/<country>/rss/customerreviews/page=<n>/id=878783582/sortBy=mostRecent/json`. A single review is cited as [RV *storefront* *date* ★*stars*].

**The Lightroom Queen** (release posts, one per release)

- [LQ-2306] June 2023 (mobile 8.4): <https://www.lightroomqueen.com/whats-new-lightroom-2023-062/>
- [LQ-2310] October 2023 (mobile 9.0): <https://www.lightroomqueen.com/whats-new-in-lightroom-2023-10/>
- [LQ-2405] May 2024 (mobile 9.3): <https://www.lightroomqueen.com/whats-new-in-lightroom-2024-05/>
- [LQ-2410] October 2024 (mobile 10.0): <https://www.lightroomqueen.com/whats-new-in-lightroom-2024-10/>
- [LQ-2412] December 2024: <https://www.lightroomqueen.com/whats-new-in-lightroom-2024-12/>
- [LQ-2502] February 2025: <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-02/>
- [LQ-2504] April 2025: <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-04/>
- [LQ-2506] June 2025 (mobile 10.4): <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-06/>
- [LQ-2510] October 2025: <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-10/>
- [LQ-2512] December 2025: <https://www.lightroomqueen.com/whats-new-in-lightroom-2025-12/>
- [LQ-2602] February 2026: <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-02/>
- [LQ-2604] April 2026 (includes iOS 11.3.2 and 11.3.3): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-04/>
- [LQ-2606] June 2026 (mobile 11.4): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-06/>
- [LQ-2608] August 2026 (mobile 11.5): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-08/>
- [LQ-2609] September 2026 (mobile 11.6): <https://www.lightroomqueen.com/whats-new-in-lightroom-2026-09/>

**The Lightroom Queen** (other pages)

- [LQ-CMP] Lightroom cloud ecosystem vs. Lightroom Classic, feature chart, updated 9 October 2026: <https://www.lightroomqueen.com/lightroom-cc-vs-classic-features/>
- [LQ-SYNC] What are the limitations of syncing Lightroom Classic with the cloud?: <https://www.lightroomqueen.com/limitations-syncing-classic-with-cloud/>
- [LQ-M1] Members' guide, Remove on mobile (public outline): <https://www.lightroomqueen.com/premium-cloud/edit-remove/remove-mobile/>
- [LQ-M2] Members' guide, AI distraction removal (public outline): <https://www.lightroomqueen.com/premium-cloud/edit-remove/ai-distractions/>
- [LQ-M3] Members' guide, versions and copies (public outline): <https://www.lightroomqueen.com/premium-cloud/edit-tools/versions-copies/>
- [LQ-M4] Members' guide, viewing photos on a mobile device (public outline): <https://www.lightroomqueen.com/premium-cloud/viewing/viewing-mobile/>
- [LQ-M5] Members' guide, Generative Expand, including on iPhone (public outline): <https://www.lightroomqueen.com/premium-cloud/edit-crop/expand/>

**Redlamp**

- Inventory §20: `docs/lightroom-feature-inventory.md`, section 20 (Lightroom Mobile), written from working knowledge as of mid-2025.
