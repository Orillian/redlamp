# iPhone photo editors: how they move between tools and set values

Written by the mobile editors analyst of the MOB-01 design study team, on 13 October 2026, for MOB-01 (the iPhone design study, [#406](https://github.com/pdcgomes/redlamp/issues/406)).

## In short

- Every app whose layout could be checked keeps the photo above and the controls below it, in reach of the thumb; Photomator, with its toolbar at the top, is the exception for undo and Done. They differ in what the controls below hold: one large control for one adjustment (Apple Photos, VSCO, Snapseed), or a panel with a scrolling list of sliders (Darkroom, Photomator, RAW Power, Capture One).
- Of the editors studied, Snapseed is the one whose values are set by dragging on the photo itself: a vertical drag picks the parameter, a horizontal drag sets it, and the same two gestures work in every tool. Its 2025 redesign kept the gesture and added an arc-shaped indicator and a Faves tab of pinned tools. The gesture model is fast and consistent but hidden, and it holds about seven parameters per tool, against roughly forty sliders across Lightroom's develop panels.
- The apps that cover a Lightroom-sized set of adjustments (Darkroom, Photomator, RAW Power, Capture One) all fall back to lists of sliders grouped into tools. What separates them is the help around the slider: double-tap to reset (Photomator, Darkroom), a 10× fine mode by moving the finger away from the slider (RAW Power), a list the user can trim and reorder (Photomator, RAW Power), and tap-and-hold on the photo to compare (all of them).
- Editing a Photos library photo in place, with the edit kept re-editable and Revert to Original available in Photos, is what Photomator and RAW Power do, what Darkroom does on Save, and what Snapseed's older help describes. PhotoKit stores one adjustment-data "recipe" per asset for this. VSCO and Capture One bring photos into a library of their own instead, and their reviews complain about it.
- Apple Photos itself is the baseline Redlamp's users will compare against: a row of round adjustment buttons under the photo, each with a ring that shows how far it has moved, one slider below them, tap the photo to compare. iOS 27, current since September 2026, adds a Tools tab (Clean Up, Extend, Reframe), star ratings and keywords, and a new system RAW engine (RAW 9).
- Patterns worth trying in Redlamp: a fixed module bar with one large control per adjustment, a two-axis drag on the photo as an expert shortcut rather than the only way in, a pinned row of the user's own adjustments, a fine mode on every slider, press-and-hold to compare, and editing in place in the Photos library with Redlamp's recipe as the adjustment data.

## Scope, versions and sources

All URLs below were checked on 2026-10-13. Versions and release dates come from the iTunes Lookup API (`https://itunes.apple.com/lookup?id=<id>&country=us`); review counts come from the App Store reviews feed (`https://itunes.apple.com/us/rss/customerreviews/id=<id>/sortBy=mostRecent/json`, the two most recent pages, up to 100 reviews).

| App | Maker | Version (date) | Price model | Ratings (US) |
|---|---|---|---|---|
| Photos | Apple | iOS 26 as asked; iOS 27 is current | Built in | — |
| [Snapseed](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619) | Google | 4.1.5 (6 Oct 2026) | Free, no purchases | 4.86 from 28,317 |
| [VSCO](https://apps.apple.com/us/app/vsco-photo-video-editor/id588013838) | Visual Supply Company | 461.9.3 (9 Oct 2026) | Subscription | 4.69 from 277,888 |
| [Darkroom](https://apps.apple.com/us/app/darkroom-photo-video-editor/id953286746) | Bergen Co. | 7.4.1 (13 Oct 2026) | Free, Darkroom+ subscription | 4.78 from 29,364 |
| [Photomator](https://apps.apple.com/us/app/photomator-photo-editor/id1444636541) | Apple (Pixelmator) | 3.4.15 (27 Aug 2026 in the version history; the Lookup API gives 6 Oct 2026) | Subscription or lifetime | 4.55 from 3,816 |
| [RAW Power](https://apps.apple.com/us/app/raw-power/id1250601531) | Gentlemen Coders | 3.5.6 (27 Jul 2026) | $12.99 | 4.58 from 875 |
| [Capture One](https://apps.apple.com/us/app/capture-one/id1514081672) | Capture One A/S | 4.1.1 (2 Oct 2026) | Subscription | 3.45 from 331 |
| [Halide Mark III](https://apps.apple.com/us/app/halide-mark-iii-pro-camera/id885697368) | Lux Optics | 3.2.1 (2 Oct 2026) | Subscription or lifetime | 4.45 from 13,581 |
| [Infltr](https://apps.apple.com/us/app/infltr-infinite-filters/id935623257) | YOOSHR | 6.15 (17 Jul 2025) | Free with purchases | 4.58 from 31,319 |

Halide and Infltr are the two additions, chosen for how they move between tools and set values (see their sections). Lightroom Mobile is studied by another team member and appears here only as a point of comparison; Prequel is left out at the owner's request.

**iOS version.** The brief asks for Photos on iOS 26. Apple's guide now defaults to iOS 27, which shipped in September 2026 ([9to5Mac, iOS 27 release notes](https://9to5mac.com/2026/09/09/ios-27-here-are-apples-full-release-notes/); the guide's own [iOS 27 edition](https://support.apple.com/guide/iphone/welcome/ios)). This note describes iOS 26 from the iOS 26 edition of the guide and adds what iOS 27 changes.

**What couldn't be reached.** MacStories and AppleInsider returned a Cloudflare challenge; PetaPixel, DPReview and Reddit returned 403 (tried once each). VSCO's help centre (`support.vsco.co`) and Capture One's help centre (`support.captureone.com`) returned 403 behind Cloudflare, so VSCO and Capture One are described from their product pages, App Store text and reviews, with gaps marked. DuckDuckGo and Bing returned no usable results, so reviews were found through the sites' own WordPress search API. Snapseed's help centre answered, but it describes the 2.x interface from before the 2025 redesign, and its tools overview didn't render. Nobody on the team can run the apps: behaviour that comes from a review rather than the maker says so.

---

## Apple Photos (iOS 26, and what iOS 27 changes)

### Evidence

**The library.** Photos opens on two tabs. Library shows everything by date, with Years and Months to jump through it; Collections holds Memories, Favorites, People & Pets, Albums and more ([Get started with Photos](https://support.apple.com/guide/iphone/get-started-with-photos-iphc259d0ac7/26/ios/26)). iOS 26's update was this split: "an updated design makes it easier to switch between your Library and Collections", with collections that can be reordered, pinned and shown at three sizes ([What's new in iOS 26](https://support.apple.com/guide/iphone/whats-new-in-ios-26-iphfed2c4091/26/ios/26); [Browse your photo collections](https://support.apple.com/guide/iphone/browse-your-photo-collections-iph4f36c4148/26/ios/26)). A pinch changes the grid's density, and View Options switches between square and aspect-ratio thumbnails and hides screenshots, items from the Mac and items shared in Messages ([Browse your photo library](https://support.apple.com/guide/iphone/browse-your-photo-library-iph7d24753a5/26/ios/26)). The library can be sorted by date added or date captured and filtered, with filters combinable, for example Photos with Edited, or Videos, Favorites, Not in an Album ([Sort and filter the photo library](https://support.apple.com/guide/iphone/sort-and-filter-the-photo-library-iph2e66e2f2c/26/ios/26)). Collections includes Media Types (Portrait, time-lapse and so on), which can be reordered and pinned ([Locate photos by media type](https://support.apple.com/guide/iphone/locate-photos-and-videos-by-media-type-iph8530ff6a2/26/ios/26)), and Utilities, which holds recently edited, receipts, QR codes, Hidden and Recently Deleted ([Find receipts, QR codes, edited photos](https://support.apple.com/guide/iphone/find-receipts-qr-codes-edited-photos-iph995007f21/26/ios/26)). Albums have their own filter and sort, including a custom order ([Filter and sort in albums](https://support.apple.com/guide/iphone/filter-and-sort-photos-and-videos-in-albums-iph9463b0c24/26/ios/26)). Third-party apps see the same smart albums through PhotoKit, including RAW, Live Photos, Portrait (Depth Effect), Panoramas, Selfies, Bursts, Spatial and Screenshots ([PHAssetCollectionSubtype](https://developer.apple.com/documentation/photos/phassetcollectionsubtype)).

iOS 27 adds star ratings (behind a setting), keywords added by swiping up on a photo, a Captured By Me collection under Utilities, and multi-selection review ([iDownloadBlog, iOS 27 Photos features](https://www.idownloadblog.com/2026/09/18/new-photos-app-features-ios-27/)). Gentlemen Coders' Nitro reads and writes ratings, keywords and captions in the Photos library on OS 27, so these are open to third-party apps ([Nitro Photo release notes](https://apps.apple.com/us/app/nitro-photo/id1591292532)).

**1. Moving between tools.** In the editor, tools are tabs: Adjust, Styles (on Photographic Styles models) or Filters, Crop, and Clean Up with Apple Intelligence ([Edit photos and videos, iOS 26](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/26/ios/26)). Within Adjust, a row of buttons sits under the photo; the user swipes left along it to reach Exposure, Brilliance, Highlights and the rest, and taps one to select it (same page). Crop has its own row of Straighten, Vertical and Horizontal perspective, swiped the same way ([Crop, rotate, flip, or straighten](https://support.apple.com/guide/iphone/crop-rotate-flip-straighten-photos-videos-iph0f3ebb1dd/26/ios/26)). In iOS 27, Clean Up moves into a Tools tab beside the new Extend and Reframe ([Clean up, extend, and reframe, iOS 27](https://support.apple.com/guide/iphone/clean-up-extend-and-reframe-photos-xy0grrlxue5w/27/ios/27)).

**2. Value control.** One slider under the button row sets the selected adjustment. "The outline around each button indicates the level of change for that setting", so the row doubles as an overview of the whole edit, and tapping a button toggles that adjustment off and on to compare ([Edit photos and videos, iOS 26](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/26/ios/26)). Apple's guide mentions no numeric entry, no fine mode and no reset gesture for a single slider; a haptic tick at zero is commonly described but couldn't be confirmed from Apple's pages (unverified). Photographic Styles use a different control: a square pad dragged in two dimensions sets tone and colour together, with an intensity slider below and a reset button ([Edit photos and videos, iOS 26](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/26/ios/26)); 9to5Mac's reviewer found the pad easier than "changing every single editing toggle" ([9to5Mac](https://9to5mac.com/2024/10/01/photographic-styles-favorite-iphone-16-feature/)).

**3. Looks.** Filters (Vivid, Dramatic and others) have a strength slider; on iPhone 16 and later, Photographic Styles replace filters unless the user turns Styles off ([Edit photos and videos, iOS 26](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/26/ios/26)). Edits can be copied with a checklist of which to keep and pasted onto a selection; Photos adjusts white balance and exposure of the target "to create a better match" (same page).

**4. Local edits.** None, apart from Clean Up, where the user taps, brushes or circles an object, and some items are highlighted automatically ([Use Apple Intelligence in Photos, iOS 26](https://support.apple.com/guide/iphone/use-apple-intelligence-in-photos-iphf7de217f0/26/ios/26)). iOS 27 adds Auto, Fast and High Quality processing for Clean Up, and Extend and Reframe, each reversible with Reset after saving ([iOS 27 guide](https://support.apple.com/guide/iphone/clean-up-extend-and-reframe-photos-xy0grrlxue5w/27/ios/27)).

**5. Before and after, undo, history.** Tap the photo to compare; undo and redo buttons at the top step through the session; after saving, Revert to Original restores the original ([Undo and revert photo edits](https://support.apple.com/guide/iphone/undo-and-revert-photo-edits-iph2413db0ab/26/ios/26)). There is no visible history list.

**6. One hand and landscape.** The tool tabs, button row and slider all sit below the photo. The guide doesn't describe landscape editing (unverified).

**7. Library, saving, raw.** Edits are saved to the library item and sync over iCloud Photos ([Edit photos and videos](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/26/ios/26)). Photos edits ProRAW, which is DNG ([About Apple ProRAW](https://support.apple.com/119916)). Third-party apps can add editing extensions to Photos' edit screen ([Edit with third-party apps and extensions](https://support.apple.com/102259)). iOS 27 brings RAW 9, a machine-learning demosaic and denoise in Core Image that also applies when reprocessing older raw files ([9to5Mac on RAW 9](https://9to5mac.com/2026/07/06/apple-overhauls-raw-photo-processing-with-ios-27-showcases-impressive-results/)).

**8. What people say.** Photos has no App Store reviews feed. Darkroom's comparison page, written by a competitor, calls its tools "a genuinely good set" for quick fixes and lists what it lacks: masks, curves, colour grading ([Darkroom vs Apple Photos](https://darkroom.co/blog/2026-01-01-darkroom-vs-apple-photos)).

### Assessment

The ring around each adjustment button is the idea from Photos worth taking for Redlamp: it shows which adjustments are in use without opening anything, and it costs no space. The single slider is easy to learn but slow across many adjustments, because every change is a swipe along the row, a tap, then a drag. The Photographic Styles pad shows that a two-axis control can replace two sliders when the two values belong together (temperature and tint, hue and saturation).

---

## Snapseed (Google)

### Evidence

**Redesign.** Snapseed 3.0 (June 2025) was the first major iOS update since 2021 and redesigned the app: a home grid of photos edited in Snapseed, a plus button that opens the system image picker, and an editor in three tabs, Looks, Faves and Tools ([9to5Google, 3.0](https://9to5google.com/2025/06/12/snapseed-3-0-update-iphone/)). Faves held up to four pinned tools ([9to5Google](https://9to5google.com/2026/01/06/snapseed-android-redesign/)). Version 4.0 (May 2026) refreshed the interface again and "expanded favorites", allowing more pinned tools ([App Store version history](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619)); on Android the 4.0 editor shows Looks, Tools and Export tabs, with Tools grouped as Refine, Fix, Style and All, and the histogram and theme switch in the top right ([9to5Google, 4.0](https://9to5google.com/2026/05/08/snapseed-4-android-update/)). Whether iOS 4.x uses exactly the Android tab names couldn't be confirmed (unverified). Since 3.11 the app also has a Snapseed Camera with film looks whose captures keep a full edit stack ([9to5Google](https://9to5google.com/2026/01/05/snapseed-camera-iphone-update/); [App Store version history](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619)).

**1. Moving between tools.** The Tools tab is a grid of about thirty tools in four groups (Adjust & Correct, Retouch & Transform, Style, Creative); Faves pins the ones the user wants at hand; Looks holds presets ([9to5Google, 3.0](https://9to5google.com/2025/06/12/snapseed-3-0-update-iphone/)). Each tool opens full screen and is confirmed or cancelled before returning to the editor.

**2. Value control.** Within a tool, "you drag left/right to make value adjustments, but you now get an arc-based controller at the bottom. In certain tools, you can still swipe up/down to access different options" (9to5Google's review of 3.0, [link](https://9to5google.com/2025/06/12/snapseed-3-0-update-iphone/)). The help centre, written for 2.x, gives the original model: in Tune Image, "swipe vertically on the image to access the edit menu. Once an option has been selected, swipe horizontally to enhance", over Brightness, Contrast, Saturation, Ambiance, Shadows, Highlights and Warmth ([Tune Image](https://support.google.com/snapseed/answer/6157802?hl=en)); RAW Develop uses the same gestures over Exposure, Shadows, Highlights, Contrast, Structure, Temperature and Tint ([Develop: RAW Editing](https://support.google.com/snapseed/answer/6312515?hl=en)). The gesture works anywhere on the photo, so the finger never has to find a control. Numeric entry, reset of one parameter and haptic detents aren't documented (unverified).

**3. Looks.** The Looks tab holds preset looks and lets the user save their own ([9to5Google](https://9to5google.com/2026/01/06/snapseed-android-redesign/)). A strength control for a Look isn't documented (unverified); individual tools such as Bloom have a Strength parameter ([App Store version history](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619)). The Film tool simulates historic stocks, and Batch Edit applies looks and edits to many photos ([App Store description](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619)).

**4. Local edits.** Selective places U Point control points: tap to place, pinch to size the affected area (shown in red), then the same vertical and horizontal swipes set Brightness, Contrast and Saturation ([Selective](https://support.google.com/snapseed/answer/6157827?hl=en)). Brush paints Dodge & Burn, Exposure, Temperature or Saturation, with brush size set by zooming the photo and an eraser ([Brush](https://support.google.com/snapseed/answer/6157715?hl=en)). Recent versions add one-tap subject or background masking and region selection in Motion Blur ([App Store description and 4.1.5 notes](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619)).

**5. Before and after, undo, history.** Tap and hold inside a tool to see the before image ([Getting Started](https://support.google.com/snapseed/answer/6155517?hl=en)). Stacks list every tool applied, in order; the user can reopen any step to change it, delete it, insert a tool at any point, and copy a whole stack to another photo with Replace or Insert ([Stacks](https://support.google.com/snapseed/answer/6155543?hl=en)). "The order in which Tools and Filters are applied matters" ([Getting Started](https://support.google.com/snapseed/answer/6155517?hl=en)). Undo, Redo and Revert sit in a menu ([Undo, Redo, Revert](https://support.google.com/snapseed/answer/6181627?hl=en)). Snapseed 4.1 for Android added undo and redo inside tools; Google said the iOS update would follow ([9to5Google, 4.1](https://9to5google.com/2026/07/13/snapseed-4-1-raw/)). The iOS 4.1.0 notes mention only raw support, so whether iOS has in-tool undo is unverified. How Stacks appear after the redesign couldn't be confirmed (unverified).

**6. One hand and landscape.** Drags on the photo can be made with the thumb anywhere on the screen; tabs and the arc control sit at the bottom (assessment from the reviews above). Landscape behaviour is undocumented (unverified).

**7. Library, saving, raw.** The app opens on its own grid of edited photos, not on the Photos library; photos come in through the system picker ([9to5Google, 3.0](https://9to5google.com/2025/06/12/snapseed-3-0-update-iphone/)). The 2.x help says Save keeps the original with its non-destructive stack, Save a copy writes a duplicate JPEG with the stack, and Export writes a flattened JPEG ([Save, Share, Export](https://support.google.com/snapseed/answer/6155519?hl=en)); current behaviour is unverified. Snapseed 4.1.0 (22 August 2026) extended raw support to "a huge new lineup" of formats ([App Store version history](https://apps.apple.com/us/app/snapseed-photo-editor/id439438619); the Android release names DNG, ARW, RAF, NEF, CR3, ORF and PEF, [9to5Google](https://9to5google.com/2026/07/13/snapseed-4-1-raw/)).

**8. What people say.** Of the 100 most recent US reviews (3 August to 11 October 2026), 81 give five stars and 4 give one. Praise centres on its being free and easy ("Easier than LR", "Solid Alternative to Lightroom"). Complaints are about the redesign ("a faux-retro mess of an interface", "needlessly complex", "Why do we need to add photos to an album in order to edit them?"), crashes, and dulled colours after a crop ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=439438619/sortBy=mostRecent/json)).

### Assessment

Snapseed's drag-on-photo model is what the owner's "novel interactions" brief points at, and it builds muscle memory well because the gesture is identical in every tool: one vertical stroke to choose, one horizontal stroke to set. Its limits are the number of parameters a vertical menu can hold before choosing becomes a hunt, the lack of any visible overview of what has been changed, and discoverability: nothing on screen says the photo is the control. Stacks are an ordered pipeline because Snapseed's tools are ordered filters; Redlamp's pipeline has a fixed order, so a stack in Redlamp would be a history or a list of what is in use, not a pipeline the user reorders.

---

## VSCO

### Evidence

**1. Moving between tools.** Photos are edited from the user's Studio ("select a photo and tap the edit icon to access the photo editor"); tools such as Dodge and Burn are chosen by name in the editor ([VSCO Dodge & Burn](https://www.vsco.co/features/dodge-burn)). The layout of the presets row and tools row couldn't be confirmed from VSCO's own pages, because its help centre refused (unverified: presets in one row, tools in another, at the bottom).

**2. Value control.** Each tool is a slider: Exposure, Highlights and Shadows (Tone), Temperature and Tint, HSL with colour swatches and three sliders, Skin Tone ([Exposure](https://www.vsco.co/features/exposure), [Tone](https://www.vsco.co/features/tone), [HSL](https://www.vsco.co/features/hsl), [Skin Tone](https://www.vsco.co/features/skin-tone)). The slider's range and any reset gesture are undocumented here (unverified).

**3. Looks.** Presets are the centre of the app: "Tap the filter again to quickly adjust the strength" ([Photo filters](https://www.vsco.co/features/photo-filters)). Pro Presets add Contrast, Color and Tone sliders beside Strength, and Film X presets add a Character slider ([Pro Presets](https://www.vsco.co/features/photo-filters/pro-presets), [Film filters](https://www.vsco.co/features/film-filters)). Recipes save a preset plus tool adjustments as one reusable look ([Recipes](https://www.vsco.co/features/recipes)). Batch editing of 2 to 100 photos arrived in May 2026 ([App Store version history](https://apps.apple.com/us/app/vsco-photo-video-editor/id588013838)).

**4. Local edits.** Dodge and Burn is a brush with a Size slider; strokes build up where repeated ([Dodge & Burn](https://www.vsco.co/features/dodge-burn)). AI Lab adds Remove, Upscale and a text Prompt tool, built with Black Forest Labs' FLUX.1 Kontext ([9to5Mac](https://9to5mac.com/2026/01/16/vsco-adds-prompt-based-image-editing/)); whether these run on device is unverified. No subject, gradient or range masks are documented.

**5. Before and after, undo, history.** "Long press your image after editing to preview before and after looks" ([Skin Tone](https://www.vsco.co/features/skin-tone)). Undo and any history view are undocumented (unverified).

**6. One hand and landscape.** Not documented (unverified).

**7. Library, saving, raw.** Photos are captured or imported into the Studio ("Capture or import photos ... with the VSCO mobile app", [Exposure](https://www.vsco.co/features/exposure)); Darkroom's comparison says VSCO "asks you to import and upload your photos into its library" ([Darkroom vs VSCO](https://darkroom.co/blog/2024-02-28-darkroom-vs-vsco)). Edits therefore don't live on the Photos item; export to the Photos library is a copy (unverified). Raw editing works "on supported iOS devices" ([Photo filters FAQ](https://www.vsco.co/features/photo-filters)). VSCO also sells a separate Studio Pro app for high-volume work ([9to5Mac](https://9to5mac.com/2026/06/17/vsco-unveils-studio-pro-app-as-it-pushes-further-into-professional-photography-workflows/)).

**8. What people say.** Of the 100 most recent reviews (23 May to 11 October 2026), 47 give one star and 20 give five. Nearly every complaint is about money and accounts: a sign-in before any editing, features moved to the higher tier, copying edits now paid, hard cancellation. Others report a Studio that empties unless every photo in the camera roll is shared with the app, and burnt-looking uploads ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=588013838/sortBy=mostRecent/json)).

### Assessment

VSCO's lasting contribution is "tap the preset again for its strength", which keeps the usual follow-up to a look, making it weaker, one tap away. Its own-library model is the opposite of what the owner wants, and the reviews show how much friction it causes once Photos access is limited.

---

## Darkroom (Bergen Co.)

### Evidence

**1. Moving between tools.** The library uses iOS 26's floating tab bar with a Library tab for albums ([Interface overview](https://darkroom.co/help/guide/interface-overview)). In the editor, "the tool bar runs along the bottom on a phone"; tap a tool to open it, "or swipe up on iPhone and iPad to jump straight to the adjustment sliders" (same page). Tools are Crop/Rotate/Transform, Presets, Adjustments, Curves (RGB and HSL), Color (HSL), Color Grading, Masks, Bloom & Halation, Frames, Histogram, Metadata and History ([Edit view](https://darkroom.co/help/edit/edit-view)). When a tool is open, swiping the toolbar right reveals Flag and Reject ([Interface overview](https://darkroom.co/help/guide/interface-overview)).

**2. Value control.** Adjustments are a list of sliders grouped by Exposure, Color, Texture and Effects ([Adjustment Sliders](https://darkroom.co/help/edit/adjustment-sliders)). Double-tapping a slider knob resets it (mentioned in the [7.2.2 release notes](https://apps.apple.com/us/app/darkroom-photo-video-editor/id953286746)). For raw photos the temperature control shows Kelvin and starts from the camera's as-shot value, with Auto and a picker ([White Balance](https://darkroom.co/help/edit/white-balance)). Curves handles can leave the track, double-tap to reset, and "tapping just above or below the curve nudges it 1% at a time"; long-pressing a channel selector hides that curve ([Curves](https://darkroom.co/help/edit/curves-rgb)). Numeric entry exists on the Mac (crop size, straighten angle) ([Crop, Rotate, Transform](https://darkroom.co/help/edit/crop-rotate-transform)); on iPhone it isn't documented (unverified).

**3. Looks.** Presets are "transparent": after applying one, every adjustment it made is visible and editable. Users can create, update, favourite, reorder, hide and share presets as web links, and browse community presets ([Presets](https://darkroom.co/help/edit/presets)). A strength slider for presets isn't documented (unverified).

**4. Local edits.** Masks (a Darkroom+ feature) are added with a plus button; each carries a full set of adjustments and appears as a thumbnail in a mask list. Kinds: Subject, Foreground, Background and Depth Range from an on-device depth model; Sky, Skin, Hair, Glasses and Teeth on Portrait and ProRAW photos; Linear and Radial gradients; Color Range and Luminance Range, with independent falloff at each end of a range; masks can be combined ([Masks & Local Adjustments](https://darkroom.co/help/edit/masks-local-adjustments)). There is no brush; a reviewer asks for one ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=953286746/sortBy=mostRecent/json)).

**5. Before and after, undo, history.** Tap and hold anywhere on the photo to flash the original, and an eye icon beside each tool title shows the photo without that tool ([Interface overview](https://darkroom.co/help/guide/interface-overview)). History holds undo, redo, Reset Edits and copy/paste, where the user chooses which groups to paste: Adjustments, Aspect Ratio, Transform, Masks, Frames ([History](https://darkroom.co/help/edit/history)).

**6. One hand and landscape.** "We designed Darkroom specifically so you can operate it using just your thumb through explicit navigation and gestures" ([Darkroom vs Capture One](https://darkroom.co/blog/2026-01-02-darkroom-vs-capture-one)). Gestures: double-tap or pinch to zoom, swipe left or right to move between photos even with a tool open, a single tap hides all controls, swipe down closes the editor ([Interface overview](https://darkroom.co/help/guide/interface-overview)). In the 7.3 redesign, a zoomed photo extends behind the glass tool area and the top actions float over it ([Liquid Glass for iPhone](https://darkroom.co/blog/2026-08-03-liquid-glass)). Landscape isn't documented (unverified).

**7. Library, saving, raw.** Darkroom reads the Photos library directly, without importing, and mirrors Apple's smart albums (Recents, Favorites, Edited, RAW, Videos, Live Photos), adds Imported, Flagged and Rejected, shows shared and user albums, and offers grid density by pinch, square or aspect thumbnails, and three sort orders ([Interface overview](https://darkroom.co/help/guide/interface-overview); [Library view](https://darkroom.co/help/manage/library-view)). Edits stay in Darkroom until export: Save (Modify Original) writes a new version to the Photos item, "still reversible later in Apple Photos" with Revert to Original, and Save Copy adds a separate photo ([Export](https://darkroom.co/help/export/export-view)). The slider stack stays on the device where the edit was made; "another device only received the exported image, not those sliders" (same page). Raw decoding uses Apple's system engine, so camera support follows iOS; rendering is in linear colour ([RAW & ProRAW](https://darkroom.co/help/edit/raw-files)).

**8. What people say.** Of the 100 most recent reviews (11 November 2025 to 9 October 2026), 37 give one star and 31 give five. Complaints are crashes with raw files during the Darkroom 7 engine rewrite, upselling, missing brush and colour-picker masks, and edits that don't sync between iPhone and Mac; praise is for the interface and the histogram. One reviewer believed every photo has to be imported, which contradicts the documentation ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=953286746/sortBy=mostRecent/json)). Reviewers outside the App Store call it "extremely intuitive and easy to use" ([9to5Mac](https://9to5mac.com/2024/12/31/best-camera-photo-editing-apps-iphone/)).

### Assessment

Darkroom is the closest existing model for what the owner describes: Photos library first, tools in a bottom bar, sliders in a list, masks as a list of layers with their own adjustments, and a gesture vocabulary (hold to compare, tap to hide, swipe between photos, swipe down to close) that is the same across the app. Its weak point for Redlamp is that the edit's slider stack doesn't travel with the Photos item, which is the problem Redlamp's adjustment data in PhotoKit would solve.

---

## Photomator (Pixelmator, now Apple)

### Evidence

**Status.** Apple bought Pixelmator in 2024. In January 2026 it launched Pixelmator Pro for iPad in the Creator Studio subscription, said Pixelmator Classic for iOS "is no longer being updated", and said only that Photomator "remains available as a separate purchase" ([9to5Mac](https://9to5mac.com/2026/01/13/apple-confirms-pixelmator-for-ios-will-no-longer-receive-updates/)). Its last feature release was 3.4 in October 2024 (ratings and flags); releases since are fixes and camera support, such as compressed raw formats in 3.4.14 ([App Store version history](https://apps.apple.com/us/app/photomator-photo-editor/id1444636541)).

**1. Moving between tools.** On iPhone the toolbar is at the top: Cancel, undo, Compare, the tools, More and Done ([Interface overview](https://support.pixelmator.com/photomator-user-guide/get-started/interface-overview.md)). Below the photo sit either a presets bar or a filmstrip; swiping up from the presets bar opens the Color Adjustments pane (same page; [About color adjustments](https://support.pixelmator.com/photomator-user-guide/color-adjustments/about-color-adjustments.md)).

**2. Value control.** The Color Adjustments pane is a vertical list of adjustments, each switched on or off and opened to its sliders. The user can trim the list to the adjustments they use (Customize Adjustments), jump to one with Go to Adjustment, lock an adjustment so presets don't change it, and reset one adjustment, all of them, or one slider by double-tapping it ([About color adjustments](https://support.pixelmator.com/photomator-user-guide/color-adjustments/about-color-adjustments.md)). Numeric entry on iPhone isn't documented (unverified). A reviewer misses Kelvin values for temperature ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1444636541/sortBy=mostRecent/json)).

**3. Looks.** The presets bar has six categories on iPhone (Black and White, Cinematic, Classic Films, Landscape, Night, Custom) ([Interface overview](https://support.pixelmator.com/photomator-user-guide/get-started/interface-overview.md)). An Adjust Intensity slider scales every applied adjustment at once ([About color adjustments](https://support.pixelmator.com/photomator-user-guide/color-adjustments/about-color-adjustments.md)). LUTs can be applied and exported ([App Store description](https://apps.apple.com/us/app/photomator-photo-editor/id1444636541)).

**4. Local edits.** Selective edits are layers: on iPhone the user taps Image Layer and adds an Adjustments layer, Select Subject, Select Sky, Select Background, Brush, Linear or Radial Gradient (with on-image handles) or Color Range, and can combine selections with blend modes ([Masking and selections](https://support.pixelmator.com/photomator-user-guide/working-with-selective-adjustments.md)). Repair removes objects, and Denoise, Super Resolution and Smart Deband use machine learning ([App Store description](https://apps.apple.com/us/app/photomator-photo-editor/id1444636541)).

**5. Before and after, undo, history.** Touch and hold the photo to see the original; Compare shows a split view with a draggable divider; two-finger tap undoes and three-finger tap redoes; touching and holding undo offers Redo and Revert to Original ([Basic gestures](https://support.pixelmator.com/photomator-user-guide/get-started/basic-gestures.md); [Interface overview](https://support.pixelmator.com/photomator-user-guide/get-started/interface-overview.md)). No history list is documented.

**6. One hand and landscape.** Swipe left or right on the photo to move to the next one, swipe down to close ([Basic gestures](https://support.pixelmator.com/photomator-user-guide/get-started/basic-gestures.md)); one reviewer says swiping between photos doesn't work while editing ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1444636541/sortBy=mostRecent/json)), which matches the guide's note that it fails while Crop or Repair is selected. The top toolbar places undo and Done out of the thumb's reach on large phones (assessment). Landscape isn't documented (unverified).

**7. Library, saving, raw.** Photomator opens on a Photos browser with All Photos, Edited, Favorites and Albums along the bottom, or on a Files browser; it "doesn't import your photos but edits them in place" ([Open or import a photo](https://support.pixelmator.com/photomator-user-guide/get-started/open-a-photo.md)). Edits save automatically when the user moves to another photo, stay editable, and are marked with a badge; Revert to Original is in the quick actions ([Save, share, and export](https://support.pixelmator.com/photomator-user-guide/save-share-and-export/save-share-and-export.md)). It opens over 750 raw formats including ProRAW and compressed Fujifilm raw ([App Store description](https://apps.apple.com/us/app/photomator-photo-editor/id1444636541)).

**8. What people say.** Of the 100 most recent reviews (11 December 2025 to 9 October 2026), 36 give one star and 31 give five. Praise is for replacing Lightroom at a one-time price and for ease of use; complaints are subscription trial charges, weak masking, missing Kelvin and dehaze, batch-edit errors, iPad library limits with external drives, and worry that Apple has abandoned it ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1444636541/sortBy=mostRecent/json)).

### Assessment

Photomator shows how a full set of adjustments fits a phone: a single long list the user can prune, with each adjustment collapsible and resettable. It also shows the cost: the list scrolls, positions shift as adjustments open and close, and muscle memory has to be for names rather than places. Its layer-based masks and global intensity slider are worth noting. Its edit-in-place, auto-save model is the one Redlamp's brief describes.

---

## RAW Power (Gentlemen Coders)

### Evidence

**Status.** RAW Power for iOS gets camera-support updates (3.5.6, July 2026); its App Store text points users on iOS 16 or later to Nitro, the same developer's newer app with masking and XMP sidecars ([App Store description](https://apps.apple.com/us/app/raw-power/id1250601531)). Its founder led engineering for Aperture and iPhoto at Apple ([9to5Mac](https://9to5mac.com/2017/11/14/raw-power-photo-editor-ios/)).

**1. Moving between tools.** The editor is a set of collapsible sections and tabs holding toggles and sliders; 9to5Mac found it "a little cramped on the iPhone" at launch ([9to5Mac, 2017](https://9to5mac.com/2017/11/14/raw-power-photo-editor-ios/)). From version 1.1, controls "defer to your photos" and are reached by scrolling ([9to5Mac, 2018](https://9to5mac.com/2018/04/10/raw-power-photo-editor-ios-update/)). The user chooses which adjustments appear by default and in what order ([App Store description](https://apps.apple.com/us/app/raw-power/id1250601531)).

**2. Value control.** Sliders have a "gear down" mode: after starting a drag, moving the finger above or below the slider gives 10× precision ([9to5Mac, 2018](https://9to5mac.com/2018/04/10/raw-power-photo-editor-ios-update/), quoting the release notes). The adjustments expose Apple's raw decoder directly: Boost, Recovery, noise reduction, black point, gamut mapping, plus Curves in linear and Lab modes with samplers ([App Store description](https://apps.apple.com/us/app/raw-power/id1250601531)). A histogram shows and hides itself while adjusting (2018 notes, same 9to5Mac article).

**3. Looks.** Presets and LUTs, including built-in film simulations and the user's own; presets and pasted adjustments apply to many photos ([App Store description](https://apps.apple.com/us/app/raw-power/id1250601531)). A strength control isn't documented (unverified).

**4. Local edits.** None in RAW Power apart from Depth Effect on dual-camera photos; reviewers ask for masks ([App Store description](https://apps.apple.com/us/app/raw-power/id1250601531); [reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1250601531/sortBy=mostRecent/json)). Nitro adds brushing, gradients and AI masks ([Gentlemen Coders](https://www.gentlemencoders.com/)).

**5. Before and after, undo, history.** Not documented in the sources reached (unverified).

**6. One hand and landscape.** In landscape, an inspector lets the user jump between albums and view metadata ([RAW Power for iOS](https://www.gentlemencoders.com/raw-power-for-ios/)).

**7. Library, saving, raw.** It opens on the Photos library with its full album and folder hierarchy, a RAW Images smart album, and filters by file type, rating, flag and edit state; edits are non-destructive, stored in the Photos library, and continue on the Mac ([App Store description](https://apps.apple.com/us/app/raw-power/id1250601531); [9to5Mac, 2018](https://9to5mac.com/2018/04/10/raw-power-photo-editor-ios-update/)). Files are also supported. Raw support follows Apple's engine.

**8. What people say.** The feed holds 95 reviews from 2017 to 2026 (40 five-star, 20 one-star): praise for the raw controls, no subscription and Aperture's heritage; complaints about a buggy zoom, LUT names, regressions now that development has moved to Nitro, and missing masks ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1250601531/sortBy=mostRecent/json)).

### Assessment

The gear-down slider is a cheap, discoverable-enough answer to precision on a phone, and it suits raw controls where small moves matter. RAW Power shows that an Aperture-style inspector of sections works on iPhone only when the user can choose and order what it holds.

---

## Capture One (iPhone)

### Evidence

Capture One's help centre refused, so this section rests on the product page, the App Store text and reviews.

**1–2. Tools and values.** Tools include Crop, Keystone, Enhanced Denoise, Color Balance, Heal/Clone, Exposure, White Balance, HDR and Color Editor, with edits stacked as layers ([Capture One mobile](https://www.captureone.com/products/capture-one-mobile)). Version 4.0 (August 2026) added Enhanced Denoise, Color Balance, Heal and Clone and keywords ([App Store version history](https://apps.apple.com/us/app/capture-one/id1514081672)). How tools are switched and how sliders behave couldn't be confirmed (unverified). A reviewer reports that curve points don't snap and that the curve's end points lock when tapping outside the box ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1514081672/sortBy=mostRecent/json)).

**3. Looks.** Styles and presets can be AirDropped in or created, applied in a tap, and applied automatically while tethered ([App Store description](https://apps.apple.com/us/app/capture-one/id1514081672)).

**4. Local edits.** Layers with automatic masks, People masking (with a Clothes option since 3.1) and Retouch Faces ([App Store description](https://apps.apple.com/us/app/capture-one/id1514081672); [version history](https://apps.apple.com/us/app/capture-one/id1514081672)). A reviewer calls switching to the mask screen "weird" and notes no colour mask; another says layer selection is lost when leaving the app ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1514081672/sortBy=mostRecent/json)).

**5–6.** Undo, history, one-handed use and landscape couldn't be confirmed (unverified).

**7. Library, saving, raw.** Capture One keeps its own library with Sessions and external storage, takes tethered captures, and sends work with edits and ratings to Capture One Pro on the desktop; it supports more than 550 cameras ([App Store description](https://apps.apple.com/us/app/capture-one/id1514081672)). A reviewer says there is "no way to navigate to any individual album when opening a photo" from Photos ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1514081672/sortBy=mostRecent/json)). Whether Photos items are edited in place is unverified; the evidence points to a copy in its own library.

**8. What people say.** Of the 100 most recent reviews (June 2023 to October 2026), 47 give one star and 4 give five. Tethering is praised; editing is called "very awkward", "not intuitive at all", slow, and missing tools that Lightroom Mobile has ([reviews feed](https://itunes.apple.com/us/rss/customerreviews/id=1514081672/sortBy=mostRecent/json)).

### Assessment

Capture One's iPhone app is a cautionary case: a desktop editor's model (sessions, layers, a separate library) carried to a phone, with reviewers finding it hard to use for editing even when they value the colour and tethering.

---

## Additions

### Halide Mark III Photo Lab (Lux Optics)

Included because it moves between sections with a rotary "tab-dial" and sets values with dials, and because it deliberately limits what the editor shows.

**Evidence.** The Photo Lab opens on a Quick Edit pane for auditioning looks, toggling HDR and film simulation, and setting exposure. "If you want more control, you can flip to detailed section from the tab-dial above. Scroll or tap to 'Frame'". Sections are Frame (crop, level, output resolution), Exposure (exposure dial, histogram, Tone Fusion), Film (toggles and strength for grain, halation, micro-contrast and vignette) and Balance (white balance and presets); "whenever you toggle them on and off using the bottom toolbar, we show a brief reminder of what that dial does". Lux's stated aim: "Have you ever opened an editor and felt like you're staring at an airplane cockpit?" ([Halide Mark III](https://www.lux.camera/halide-mark-iii/)). Looks can be applied to existing ProRAW files, including those from Apple's Camera app ([App Store description](https://apps.apple.com/us/app/halide-mark-iii-pro-camera/id885697368)). Whether edits are saved back to the Photos item, and how undo works, couldn't be confirmed (unverified).

**Assessment.** The tab-dial is a carousel of section names that can be scrolled with the thumb or tapped, so it serves both the user who knows where they are going and the one browsing. The reminder shown when a control is toggled is a light way to teach a dense panel.

### Infltr (YOOSHR)

Included because it takes drag-on-the-photo further than Snapseed: a single two-dimensional drag explores a continuous space of filters.

**Evidence.** "Infltr is the only app that allows you to change filters by simply dragging your finger on the screen: just drag it in any direction and the filter will magically change" ([App Store description](https://apps.apple.com/us/app/infltr-infinite-filters/id935623257)). It was last updated in July 2025.

**Assessment.** A two-axis drag over the photo is fast for exploring and hard to repeat exactly; it suits finding a look, not setting a value.

---

## Comparison

| App | Moving between tools | Value control | Looks and strength | Local edits | Compare, undo, history | One hand, landscape | Library and saving | Raw |
|---|---|---|---|---|---|---|---|---|
| Apple Photos (iOS 26) | Tabs (Adjust, Styles or Filters, Crop, Clean Up); swipe a row of buttons | One slider; ring on each button shows amount; 2D pad for Styles | Filters with strength; Styles pad and intensity; copy/paste edits | Clean Up only (iOS 27: Extend, Reframe) | Tap photo; undo/redo; Revert to Original | All controls below photo; landscape unverified | Is the library; edits on the item, iCloud sync | ProRAW, DNG; RAW 9 in iOS 27 |
| Snapseed 4.1.5 | Looks, Faves (pinned tools), Tools grid; each tool full screen | Vertical drag picks, horizontal drag sets, on the photo; arc indicator | Looks tab, own looks; strength unverified | U Point control points, brush, one-tap subject mask | Hold to compare; Stacks (ordered, editable); undo menu | Thumb anywhere on photo; landscape unverified | Own grid of edited photos, system picker; save modes from 2.x help | Develop tool; expanded formats in 4.1 |
| VSCO 461.9.3 | Presets and tools in the editor (layout unverified) | Sliders per tool | Tap preset again for strength; Pro sliders; Recipes | Dodge and Burn brush; AI Lab | Long press to compare; history unverified | Unverified | Own Studio, import; export a copy (unverified) | On supported devices |
| Darkroom 7.4.1 | Bottom tool bar; swipe up to sliders; floating tab bar in library | Slider list; double-tap knob resets; Kelvin for raw; curve nudge 1% | Transparent, shareable presets; strength unverified | Mask list: subject, depth, sky/skin, gradients, colour and luminance ranges with falloff | Hold to compare; per-tool eye; undo/redo; selective paste | Thumb-first by design; swipe between photos; landscape unverified | Reads Photos; Save writes a revertible version; stack stays on device | Apple engine, linear rendering |
| Photomator 3.4.15 | Top toolbar; adjustments pane swiped up from presets bar | Prunable list; double-tap slider resets; lock; Go to Adjustment | Presets bar; global Intensity; LUTs | Layers: subject, sky, background, brush, gradients, colour range | Hold to compare; split compare; 2-finger undo, 3-finger redo | Undo and Done at top; swipe between photos | Edits in place, auto-saved, re-editable, revert | 750+ formats, ProRAW |
| RAW Power 3.5.6 | Collapsible sections, scrolled; user picks and orders | Sliders with 10× gear-down; Apple decoder controls | Presets, LUTs | None (Nitro has masks) | Unverified | Landscape inspector | Photos library with hierarchy; edits in place, Mac sync | Apple engine |
| Capture One 4.1.1 | Unverified | Unverified; curves criticised | Styles, auto-apply when tethered | Layers, AI and people masks, heal/clone | Unverified | Unverified | Own library, sessions, external drives | 550+ cameras |
| Halide Mark III | Quick Edit, then a tab-dial of sections | Dials; reminder on toggle | Looks; film components with strength | None | Unverified | Bottom toolbar | Unverified | Halide RAW, existing ProRAW |
| Infltr 6.15 | Unverified | 2D drag on photo changes the filter | Continuous filter space | Unverified | Unverified | Drag anywhere | Unverified | Unverified |

---

## Patterns worth considering for Redlamp

Each pattern below names the apps that use it, its strengths and weaknesses for a raw editor with Lightroom's full set of sliders (roughly forty across Light, Color, Effects, Detail and Geometry by this analyst's count, plus masks, retouching and looks), and how well it builds muscle memory. These are assessments drawn from the evidence above.

### 1. Drag on the photo to adjust

Used by Snapseed (vertical to choose, horizontal to set, in every tool), Infltr (two-dimensional drag through filters), and in a dedicated square by Apple's Photographic Styles pad.

- **Strengths.** The whole screen is the control, so the thumb never looks for a slider and the photo stays visible at full size. One gesture vocabulary across all tools. Works one-handed anywhere on the screen.
- **Weaknesses.** Invisible: nothing on screen says the photo responds to drags, and reviewers of Snapseed's redesign still describe it as hard to learn. A vertical menu stops working well past about seven or eight items, so it can't carry a Lightroom module of fifteen sliders without nesting. It conflicts with pan, zoom, mask placement and swipe-between-photos, which also want the photo. It has no resting overview of what has changed. VoiceOver users need a separate path.
- **Muscle memory.** High for the gesture, low for finding a parameter in a long vertical menu. Works best as an expert shortcut over a visible control, for example dragging horizontally on the photo to set the adjustment currently selected below it.

### 2. One adjustment at a time with a large control under the photo

Used by Apple Photos (row of round buttons, one slider), VSCO (one tool slider at a time), Snapseed (one tool full screen), and Halide (dials).

- **Strengths.** The control is large enough for precise thumb movement; the photo stays large; easy to learn. Apple's ring on each button gives an overview of the whole edit in the same row.
- **Weaknesses.** Slow across many adjustments: each needs a swipe along the row, a tap, then a drag. Comparing two related values (Highlights against Whites) means switching back and forth.
- **Muscle memory.** Good if the order of buttons is fixed and never changes with context; Apple keeps the order, which lets users learn positions.

### 3. A bottom bar of modules opening a panel with a list of sliders

Used by Darkroom (bottom tool bar, slider list), Photomator (list of adjustments in a pane), RAW Power (collapsible sections), Capture One, and, as a point of comparison, Lightroom Mobile.

- **Strengths.** Scales to the full Lightroom set; matches Redlamp's Mac app and Lightroom users' expectations; several related sliders are visible together.
- **Weaknesses.** The panel takes half the screen or more and shrinks the photo; long lists scroll, so a slider's position isn't fixed and the thumb learns names rather than places. Reviewers find dense versions cramped (RAW Power at launch, Capture One).
- **Muscle memory.** Strong for the module bar (fixed positions along the bottom), weaker inside long lists. Short, fixed lists per module (Light, Colour, Effects, Detail, Geometry, Masks, Retouch, Looks) keep both.

### 4. A rotary or carousel selector for modules

Used by Halide (tab-dial of section names, scroll or tap) and Snapseed 3.0's arc-shaped value indicator; Apple's adjustment row is a straight carousel.

- **Strengths.** A dial of module names can be flicked with the thumb from one place and also tapped directly; it holds more modules than fit as fixed buttons, and it makes moving to the neighbouring module a small gesture, which suits the order Light, Colour, Effects, Detail.
- **Weaknesses.** If it scrolls, positions move, and some modules are always off screen; flicking past the target is common on carousels.
- **Muscle memory.** Good when the order is fixed and short enough that every module stays visible, as with eight Redlamp modules; weaker when it scrolls.

### 5. The user's own set of adjustments

Used by Snapseed (Faves, pinned tools, expanded in 4.0), Photomator (Customize Adjustments, Go to Adjustment, lock), and RAW Power (choose and order adjustments).

- **Strengths.** If, as seems likely but hasn't been measured, each user relies on a handful of the forty sliders, a pinned row puts their handful one tap away without hiding the rest. Locks stop presets overwriting a chosen value (Darkroom's 7.4.1 notes fix a preset that overwrote Temperature and Tint).
- **Weaknesses.** Another place to configure; if defaults are poor, new users never find the rest.
- **Muscle memory.** Strong, because the user sets the positions once and they stay.

### 6. Precision aids on every slider

Used by RAW Power (10× gear-down by moving the finger away), Photomator and Darkroom (double-tap to reset), Darkroom (Kelvin for raw, 1% curve nudge, handles that leave the track). Numeric entry on iPhone wasn't documented in any app studied.

- **Strengths.** Raw edits need small, repeatable moves (a third of a stop, 100 K); these aids give them without extra screens. Double-tap to reset is shared by two apps and by the Mac convention, so users may already expect it.
- **Weaknesses.** Gear-down is undiscoverable without a hint; numeric entry needs the keyboard, which covers the photo.
- **Muscle memory.** High: they are the same on every slider once learned.

### 7. Press and hold to compare

Used by Darkroom, Photomator, VSCO and Snapseed (press and hold the photo), Apple (tap the photo, or tap an adjustment's button to toggle it), Darkroom (an eye per tool), Photomator (split view).

- **Strengths.** Universal across these apps, so users arrive knowing it. Per-tool or per-adjustment comparison (Darkroom's eye, Apple's button) answers "is this tool helping?" rather than "is the whole edit helping?".
- **Weaknesses.** Conflicts with press-and-hold for other meanings on the photo (mask points, Snapseed's control point menu).
- **Muscle memory.** High; the convention already exists.

### 8. Gestures for moving through photos and the editor

Used by Darkroom and Photomator (swipe left and right between photos while editing, swipe down to close), Darkroom (single tap hides all controls, swipe up for sliders), Photomator (two-finger tap undo, three-finger tap redo, as in iPadOS text editing).

- **Strengths.** Keeps the hand on the photo; edits through a set without returning to the grid.
- **Weaknesses.** Horizontal swipe between photos competes with horizontal drag to adjust (pattern 1) and with pan when zoomed; Photomator turns it off while Crop or Repair is active, and a reviewer took that as a bug.
- **Muscle memory.** High for close and hide; swipe-between-photos needs one consistent rule about when it applies.

### 9. Edits as a visible list

Used by Snapseed (Stacks: an ordered pipeline the user edits), Darkroom (mask list with thumbnails), Photomator and Capture One (layers).

- **Strengths.** Shows what has been done and lets the user return to any part. For masks, a list of masks each with its own adjustments matches Lightroom and Redlamp's Mac app.
- **Weaknesses.** Snapseed's stack is a pipeline because its tools are ordered filters; Redlamp's develop order is fixed, so reordering would mean nothing for global adjustments. A history list is a different thing from a layer list, and mixing them confuses.
- **Muscle memory.** Moderate; lists change length and order per photo.

### 10. Looks with one strength control

Used by VSCO (tap the preset again for strength), Apple (filter strength, Styles intensity), Photomator (one Intensity for every adjustment), Halide (strength per film component); Darkroom keeps presets transparent so every value they set is visible.

- **Strengths.** The usual follow-up to a look is "less", and one tap reaches it. Transparent presets let users learn from a look.
- **Weaknesses.** A single strength has to be defined for a recipe that mixes curves, colour and masks; Photomator's global intensity scales everything, including corrections the user wanted at full value.
- **Muscle memory.** High for "tap again".

### 11. Edit the Photos item in place

Used by Photomator (edits in place, auto-save, Revert to Original), RAW Power (edits in the library, continued on the Mac), Darkroom (Save writes a revertible version; slider stack stays on the device), Apple Photos itself, and the 2.x Snapseed Save. VSCO and Capture One keep their own library, and their reviews complain about it.

- **Strengths.** It is what the owner asks for: the app opens on the Photos library and the edit belongs to the photo. PhotoKit stores one adjustment-data object per asset, "an application-defined recipe" that lets the edit be resumed on another device or reverted ([PHAdjustmentData](https://developer.apple.com/documentation/photos/phadjustmentdata)); Redlamp's JSON recipe fits it. iOS 27 opens ratings and keywords to apps, so culling can live in Photos too.
- **Weaknesses.** Photos keeps one adjustment data per asset, the most recent; an edit made afterwards in Photos or another app replaces Redlamp's recipe with one Redlamp may not understand. Darkroom's choice to keep the stack local shows the sync question is real.
- **Muscle memory.** Not a gesture question, but it removes the import step, the friction reviewers report most.

### Assessment: what to try first

For a raw editor with Lightroom's sliders, the evidence points to combining patterns rather than choosing one: a fixed bar of eight modules at the bottom (pattern 3 or 4), each opening a short fixed list whose adjustments show Apple-style rings of how far they have moved (pattern 2), a large slider for the selected adjustment with gear-down and double-tap reset (pattern 6), a horizontal drag on the photo that sets the selected adjustment as an expert shortcut (pattern 1), a pinned row of the user's own adjustments (pattern 5), press and hold to compare (pattern 7), and edits written to the Photos item as adjustment data (pattern 11). Two conflicts need a decision before prototyping: whether a horizontal drag on the photo adjusts or moves to the next photo, and whether press and hold compares or places a mask point.
