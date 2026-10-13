# MOB-01: the iPhone platform, and what Redlamp's code needs for it

Written by the iOS platform and architecture engineer of the mobile UX team (an agent), on 13 October 2026, for MOB-01 ([#406](https://github.com/pdcgomes/redlamp/issues/406)), the iPhone design study.

## In short

- **PhotoKit supports a Lightroom-style gallery built by Redlamp itself.** A custom grid over `PHAsset` sees the user's albums, smart albums (RAW, Depth Effect, Live Photos and others), favourites, media subtypes and, from iOS 27, Photos' own star ratings, captions and keywords. With limited access the app can't fetch user albums at all, so the gallery needs a limited mode, and the system picker remains the fallback for people who refuse access.
- **iOS 27 adds what a raw editor needs most from Photos.** It adds `PHAsset.rating`, keywords and captions that apps can write, `originalResourceChoice` for RAW+JPEG pairs, and an observer for persistent library changes. iOS 27 runs on the same iPhones as iOS 26, from the iPhone 11 on, so moving the deployment target to iOS 27 would cost reach only among people who haven't updated.
- **Recommendation for keeping edits: both places, with Redlamp's sidecar as the source of truth.** The full `.redlamp` package would live in Redlamp's iCloud Drive container, keyed by the asset's cloud identifier. A compact copy of `edit.json` would go into Photos as `PHAdjustmentData`, with a rendered version, when the user taps Done. Photos stores only one adjustment per asset, asks that it stay short and hold no image data, and asks permission on every save, so it can't hold masks, history or autosaves.
- **The engine can run on an iPhone with less work than a port.** Its layers already build for iOS, IOSurface and `CAMetalDisplayLink` exist there, and the Mac uses no Metal feature an A17 Pro lacks: the A17 Pro is in the same GPU family as the M3 and M4. The work is in decoding, memory budgets, tiling, background GPU rules and goldens recorded on A-series GPUs, listed in section 4.
- **iOS has no XPC service bundles, but iOS 26 gives an equivalent.** ExtensionFoundation's `AppExtensionProcess` launches an app's own bundled extension in a process of its own, optionally in a restrictive sandbox, and returns an `NSXPCConnection`. That could carry the Mac's existing `DecodeServiceProtocol` unchanged. Extensions have lower memory limits than apps, so it must be measured before it is relied on.
- **The UI layer is more portable than its module boundary suggests.** In `packages/RedlampUI/Sources/Model`, 4 of 53 files import AppKit, each for one call. `CanvasController` and `CanvasRenderer` in `RedlampCanvas` import no AppKit. The obstacles are that `EditorModel` imports the macOS-only `RedlampCanvas` module, and that it identifies photos by file URL through `FolderLibrary`.
- **Recommended floor: A17 Pro with 8 GB, enforced with the App Store's `iphone-performance-gaming-tier` capability.** That is the iPhone 15 Pro and later, every iPhone 16 and 17, and the iPhone Air. Among users of the ten most-used iPhones in TelemetryDeck's data, it leaves out about 30% (the iPhone 13, 14 and 15). A required capability can be relaxed in an update but never raised, so starting high keeps the choice open.
- **Nine decisions need the owner;** they are at the end, each with options and a recommendation.

## How it was done

- **Apple's documentation**, fetched as JSON from `developer.apple.com/tutorials/data/…` on 13 October 2026, gave each API's text and the OS version it was introduced in. The PhotoKit class pages live under `documentation/photos/…`, not `documentation/photokit/…`. Apple's Metal feature set tables (the PDF dated 21 May 2026) gave GPU families and limits. I also used the Human Interface Guidelines pages, Apple's design "What's new" page, two WWDC25 sessions, the iPhone User Guide for iOS 26 and 27, and `apple.com/os/ios`.
- **Apple doesn't publish iPhone memory sizes.** RAM, GPU core counts and the iPhone 18 Pro's and iPhone Duo's chips come from Wikipedia's [List of iPhone models](https://en.wikipedia.org/wiki/List_of_iPhone_models), a secondary source. Model popularity comes from TelemetryDeck's survey, updated 1 October 2026. Both are marked where used.
- **Redlamp:** I read `main` as of 13 October 2026, and the `iphone-harness` branch for `RedlampMobile` and the module graph there. I didn't build or run anything.
- **What I couldn't see:** the wording of the Photos permission prompts on iOS 26 and 27 (the iPhone User Guide's privacy page loads its text dynamically), and anything that needs a device. Both are marked (unverified), and the screen recordings MOB-03 makes possible would settle them.

Every claim below cites its source. The labels in brackets, such as [P1], point to the [Sources](#sources), all checked on 13 October 2026. Paths are in this repository.

## 1. PhotoKit for a Lightroom-style gallery

### Evidence

**Access levels.** An app asks for `.readWrite` or `.addOnly` access (`PHAccessLevel`, iOS 14) [P16]. Apple's privacy article describes the prompt as offering full access, no access, or **Select Photos**, which opens a picker. Whatever the user picks there is the only part of the library the app can see [P16]. With limited access "you can't create or fetch user albums" [P16]. By default the system prompts the user to update the selection once per app life cycle; the `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` key turns that off, and `presentLimitedLibraryPicker(from:completionHandler:)` (iOS 15) shows the picker when the app chooses [P16]. Apple advises making PhotoKit calls in response to a user action, not at first launch [P16]. Accessing the library without an `NSPhotoLibraryUsageDescription` crashes the app [P16]. I couldn't confirm the exact wording and layout of the prompt on iOS 26 or 27 from Apple's pages (unverified).

**The system picker against a custom grid.** `PHPickerViewController` (iOS 14) runs in a separate process, needs no authorization, handles RAW and panoramas, can't be subclassed, and ignores touches unless fully opaque [P17][P16]. Apple recommends it for apps that only need to retrieve images; apps that need assets, collections or library changes need authorization [P16].

**Albums and media types.** Smart album subtypes include `smartAlbumRAW`, `smartAlbumDepthEffect`, `smartAlbumLivePhotos`, `smartAlbumFavorites`, `smartAlbumRecentlyAdded`, `smartAlbumUserLibrary`, `smartAlbumSelfPortraits`, `smartAlbumPanoramas`, `smartAlbumSpatial` and others. User albums are `albumRegular`, plus synced and imported albums and shared albums [P18]. `PHAssetMediaSubtype` includes `photoLive`, `photoDepthEffect`, `photoHDR`, `photoPanorama`, `photoScreenshot` and `spatialMedia` [P18][P19]. There is no ProRAW subtype. From iOS 26, `PHAsset.contentType` gives the type of the data presented for the asset, and `PHAssetResource.contentType` gives each resource's type. The older `PHAssetResource.uniformTypeIdentifier` is marked deprecated in 27.2 [P8][P11].

**Favourites, ratings, captions, keywords.** `isFavorite` has always been readable, fetchable and writable [P8][P9]. **iOS 27 adds star ratings to PhotoKit:** `PHAsset.rating` returns a `PHAsset.Rating` from `unset` to `five`, and `PHAssetChangeRequest.rating` sets it. The same release adds `caption`, `addKeyword(_:)` and `removeKeyword(_:)` on the change request, and `PHAsset.extendedMetadata` (caption, keywords, original file name), with `PHFetchOptions.prefetchAssetExtendedMetadata` to fetch it together with the assets [P8]. So the teammate's report of star ratings in iOS 27 Photos ([MOB-desktop-distilled.md](MOB-desktop-distilled.md), [A8]) is confirmed, and they are open to apps.

**Filtering and sorting.** `PHFetchOptions` supports only a fixed set of keys for predicates and sort descriptors. For assets these are `localIdentifier`, `creationDate`, `modificationDate`, `mediaType`, `mediaSubtypes`, `duration`, `pixelWidth`, `pixelHeight`, `isFavorite`, `isHidden` and `burstIdentifier` [P9]. The page's table doesn't list `rating` or `addedDate` (I checked it on 13 October; whether they work in a predicate on iOS 27 is unverified). Collections sort and filter by `localizedTitle`, `startDate`, `endDate` and `estimatedAssetCount` [P9].

**RAW and JPEG pairs.** A camera photo imported as RAW+JPEG is one asset: the JPEG is its `.photo` resource ("the primary form") and the raw is `.alternatePhoto` [P10]. An edited asset also has `.fullSizePhoto` (the rendered edit), `.adjustmentData` and `.adjustmentBasePhoto` resources [P10][P11]. `PHAssetResourceManager` reads any of them [P11]. iOS 27 adds `PHAsset.originalResourceChoice`, which says whether the raw or the JPEG is the unadjusted base of a RAW+JPEG asset, and `revertAssetContent(to:)`, which reverts all adjustments and picks the raw or the JPEG as the base for every later render [P8].

**Originals in iCloud.** `requestContentEditingInput` "downloads the asset's image or video data (if necessary)" [P7]. Image and resource requests download from iCloud only when `isNetworkAccessAllowed` is true, and report through a `progressHandler` that can also cancel. Without network access, a cloud-only image comes back flagged `PHImageResultIsInCloudKey` [P11][P12].

**Thumbnails at scale.** `PHCachingImageManager` prepares images in the background for a set of assets at a target size and returns them at once when later requested with the same parameters. It is meant for collection views [P13].

**Change observation.** `PHPhotoLibraryChangeObserver` reports changes from the app, from Photos and from other apps to every fetched asset and collection, with incremental details for a collection view [P14]. Since iOS 16, `fetchPersistentChanges(since:)` returns what changed since a saved token, across launches. iOS 27 adds an observer that is told when persistent changes are committed, which needs read-write access [P14].

### Assessment

- **Build the grid on PhotoKit; keep the picker as a fallback.** The owner's direction (the app opens on the Photos library, with its albums and filters) needs `PHAsset` fetches: the picker can't show albums inside Redlamp's own screen, carry badges, or sort and filter by Redlamp's criteria. Offer the system picker when access is denied, and as Redlamp's "Add photos" when access is limited.
- **Ask in context, and design a limited mode.** Ask for access on the first tap of Library, not at launch, with a screen before the prompt that explains why full access is useful. Set `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`, and give limited mode its own "Manage selection" control. In limited mode the Albums area must say why it is empty, since user albums can't be fetched [P16].
- **Filters Redlamp can offer.** These are Raw (the RAW smart album, then each resource's `contentType` to tell ProRAW, a camera raw or a RAW+JPEG pair apart), Favourites, Edited in Redlamp (from `adjustmentFormatIdentifier`, see section 2), Portrait, Live, and, from iOS 27, Rating. Filters without a fetch key (the rating, if it turns out not to be one) are applied in memory over a fetch result. For a 50,000-photo library that must be measured on a device (unverified).
- **Thumbnails.** Use `PHCachingImageManager` for the visible rows and a margin, with network access off in the grid and a cloud badge from `PHImageResultIsInCloudKey`. Photos' own thumbnail already shows a Redlamp edit once it is saved to Photos. A draft that is only in Redlamp's sidecar needs Redlamp's own thumbnail (`ThumbnailLoader` in `packages/RedlampUI/Sources/Model/ThumbnailLoader.swift`), drawn over Photos' one.
- **Opening from iCloud.** Opening a cloud-only original should show progress and allow Cancel, using the progress handlers. A raw opened over the cellular network can be tens of megabytes (assessment).

## 2. Keeping edits

### Evidence

**How editing in place works.** The app asks the asset for a `PHContentEditingInput`, applies its edit, writes the rendered result to `PHContentEditingOutput.renderedContentURL`, attaches a `PHAdjustmentData`, and commits a `PHAssetChangeRequest` with the output inside `performChanges` [P3][P7]. The rendered file must have its orientation baked in [P4]. The page asks for a JPEG at `renderedContentURL`. Since iOS 17 the output also has `supportedRenderedContentTypes`, `defaultRenderedContentType` and `renderedContentURL(for:)`, whose pages have no description [P4], so which types (HEIC, and whether more than 8 bits) are offered for a given asset is unverified. Live Photos are not written to `renderedContentURL`: they go through `PHLivePhotoEditingContext` [P4].

**Adjustment data.** `PHAdjustmentData` holds an app-defined `formatIdentifier` (reverse DNS), a `formatVersion` (Apple suggests monotonically increasing versions) and `data`. Apple writes: "Because Photos limits the size of adjustment data, you should keep your edit information short and descriptive. Don't use image data to describe an edit" [P2]. The limit itself isn't published on the pages I read (unverified). "For each asset, Photos stores only one `PHAdjustmentData` object, representing the most recent edit", and "when iCloud Photos is enabled, a user can revert or resume edits made on a different device" [P1].

**Re-opening an edit.** On a later edit, Photos calls the app's `canHandleAdjustmentData` block. If the app accepts, it receives the original and the adjustment data; if it declines, it receives "the rendered output of all previous edits" [P5]. `PHAsset.hasAdjustments` and `adjustmentFormatIdentifier` (iOS 15) tell, without opening the asset, whether it was edited and in which format. `adjustmentTimestamp` and `adjustmentsState` (iOS 18) say when it was edited and whether the camera or the user made the change [P8].

**What others see.** Other apps that read the asset through PhotoKit get the rendered version by default; apps that understand the format can resume the edit [P1][P5]. Apple Photos keeps the original, and Revert to Original restores it ([MOB-desktop-distilled.md](MOB-desktop-distilled.md) [A4]). What Photos' own editor does with an asset whose adjustment data it can't read isn't documented; by the API's rule it would edit the rendered output (unverified).

**The permission prompt.** "Each `PHPhotoLibrary` `performChanges` call prompts the user for permission to edit the contents of the photo library." Several assets edited in one change block need one prompt [P3]. Whether setting only metadata (a favourite or a rating) prompts as well isn't stated (unverified).

**Redlamp's sidecar.** A `.redlamp` package holds `edit.json`, mask bitmaps as PNG files named by their SHA-256, and one history file per editing session. Its principles include "beside the photo, never in it" and "resolved, not recomputed": AI masks are stored as the bitmaps they produced [S-sidecar]. DEC-43 already lets a folder keep its sidecars "in Redlamp on this Mac", keyed by the photo's volume and path (`packages/RedlampDocument/Sources/SidecarLocator.swift`; tracker DEC-43). Every read and write is coordinated with `NSFileCoordinator` so that iCloud Drive syncs it safely, and conflicting copies are merged [S-sidecar].

**Identity across devices.** A local identifier is valid on one device only. A `PHCloudIdentifier` (iOS 15, macOS 12) identifies the same asset on every device signed in to the same iCloud Photos library. Apple notes that mapping identifiers "can be an expensive operation" to be done "at load and save points" [P15]. iOS 27 adds `localIdentifierMappings(forSynced:)` [P15].

**The Photo Editing Extension.** A photo editing extension implements `PHContentEditingController` and works with the same input, output and adjustment data; it appears in Photos' editor once the app is installed, on iOS and macOS [P20]. App extensions have "a much lower per-process memory limit than foreground apps" [P21].

### Options

| Option | What it gives | What it costs |
| --- | --- | --- |
| A. In place only (adjustment data and a rendered version) | The edit belongs to the photo, syncs with iCloud Photos, shows in every app, and Revert works | No masks' bitmaps or history (size, no image data); another app's later edit replaces Redlamp's recipe; a prompt on every save; a full-size render on every save |
| B. Redlamp's sidecar only (app container or iCloud Drive) | The whole edit, autosaved without prompts | Photos and other apps never see it; sharing needs an export that adds a second item to the library, as Lightroom Mobile's does ([MOB-lightroom-mobile.md](MOB-lightroom-mobile.md) §2.3) |
| C. Both | The whole edit in Redlamp, the result in Photos | Two copies to keep in step; more code |

### Recommendation: C, with the sidecar as the source of truth

1. **While editing,** autosave the full `.redlamp` package to Redlamp's iCloud Drive container (its ubiquity container, shared by the Mac and iPhone apps of the same team), named by the asset's `PHCloudIdentifier`. Before iCloud Photos has given the asset a cloud identifier, or when iCloud is off, use the local identifier and the app container, and move the package once a cloud identifier exists. No Photos prompt appears while editing.
2. **On Done** (and once for a pasted batch), render the full-size result and commit it to Photos in one `performChanges`. Its `PHAdjustmentData` would be `formatIdentifier` `app.redlamp.edit`, `formatVersion` the edit format and process version, and `data` a compressed `edit.json` without history and without mask pixels, with the SHA-256 of the sidecar's `edit.json`.
3. **On reopening,** compare the asset's `adjustmentFormatIdentifier` and the hash with the sidecar. If they match, open the sidecar. If the sidecar is missing (Redlamp just installed, or iCloud Drive off), open the adjustment data: brushes, gradients and ranges are JSON and come back whole, while AI masks whose bitmaps aren't there cover nothing, as the format already says of missing bitmaps [S-sidecar], and are flagged so the user can recompute them. If another app edited the photo after Redlamp, offer two choices: continue Redlamp's edit from the original, which replaces the other app's edit, or start a new Redlamp edit on top of the rendered version.
4. **To the Mac,** the edit travels through iCloud Photos (the rendered version and the adjustment data) and through iCloud Drive (the package). The Mac can open the same asset through PhotoKit, which supports content editing on macOS from 10.15 [P7]. That is EXT-04's first half on the Mac, and it finds the package by the cloud identifier. Files and AirDrop remain the route for photos that aren't in Photos (section 3).

**Reasons.** The owner wants the app to open on the Photos library as Lightroom Mobile does, but Lightroom's copy-on-first-edit is the friction its reviewers complain about ([MOB-lightroom-mobile.md](MOB-lightroom-mobile.md) §2.2–2.3), while Photomator and RAW Power edit in place ([MOB-mobile-editors.md](MOB-mobile-editors.md)). Option A alone would break the sidecar's "resolved, not recomputed" principle for AI masks, and the prompt makes autosave into Photos impossible. Option C keeps the published format whole and still gives Photos a real, revertible edit.

**Risks.** If the user turns iCloud Drive off for Redlamp, AI masks and history stay on one device; the parametric part still travels in the adjustment data. The adjustment data's size limit is unpublished; a long brush stroke adds about 10 KB to an edit ([S-sidecar], embedding section), so Redlamp must measure the limit and, past it, write a smaller adjustment that names the sidecar only. Two copies can drift: if Photos, another device or the user changes one without the other, the hash catches it, and the rule in step 3 decides. The design departs from "beside the photo, never in it" for Photos assets, which teammates already raised as an open question ([MOB-desktop-distilled.md](MOB-desktop-distilled.md), question 2).

**The Photo Editing Extension (EXT-04)** should come after the app. It would run the same engine in an extension's smaller memory budget [P21], so a 48 MP ProRAW would need tiled rendering (ARC-05) from the start. It would also need the same adjustment-data reader. It fits a second release, once the app's memory use is measured.

## 3. Files, card readers and cameras

### Evidence

- `UIDocumentPickerViewController` opens files or, since iOS 13, a whole folder, from any file provider, iCloud Drive and external drives included. It returns security-scoped URLs that need `startAccessingSecurityScopedResource()`, file coordination, and a file presenter while shown. A bookmark keeps access across launches; the folder article uses a `.minimalBookmark`. Access can be revoked in Settings › Privacy › Files and Folders [P28].
- The iPhone reads USB drives and SD cards through the Files app and "other supported apps"; a drive must have a single data partition. Photos itself can import from a memory card [A-ext].
- ImageCaptureCore (iOS 13) finds connected cameras, browses their files and imports them, with `NSCameraUsageDescription` [P29].
- In the code, `FolderAccess` already has an iOS branch for bookmarks with no security-scope option and `.withoutUI` (`packages/RedlampDocument/Sources/WorkingFolder.swift`, lines 66–90). `FolderWatcher` and the library's `VolumeEventStream` are FSEvents and macOS-only, and on iOS the library's change tracker polls instead (`packages/RedlampDocument/Sources/FolderWatcher.swift`; `packages/RedlampLibrary/Sources/Changes/ChangeTracker.swift`, line 73).

### Assessment

- **In the first release:** opening a single raw from Files, the share sheet or AirDrop ("Open in Redlamp"), with its sidecar beside the file when the location is writable, and in Redlamp's container when it isn't (DEC-43's rule). This is the sidecar format's native case, and it costs little.
- **Later, iPad first:** folders on drives and cards as a library source, which needs folder watching through `NSFilePresenter` and Redlamp's own library index. For cards on the iPhone, Photos' own import puts camera raws into the library and the RAW smart album, where Redlamp already looks.
- **Not planned:** an in-app ImageCaptureCore importer. Photos and Files already do it, and an importer is a library feature rather than an editing one.

## 4. Running Redlamp's engine on an iPhone

### What exists

The engine layers build for macOS, iOS and iPadOS from one graph, with `scripts/check-engine-purity.sh` keeping AppKit, UIKit and SwiftUI out (`Tuist/ProjectDescriptionHelpers/Module.swift`, lines 1–8 and 54–59). LibRaw and libjxl are vendored with `iphoneos` slices (`scripts/vendor-libraw.sh`, line 79; `vendor/build/LibRaw.xcframework/ios-arm64`). No workflow under `.github/` builds an iOS destination, so nothing checks that the engine still compiles for iOS (I searched for `platform=iOS` and `iphoneos`).

### Decoding without `RedlampDecoder.xpc`

**Evidence.** On the Mac, `DecodeServiceClient` sends a file's bytes over `NSXPCConnection` to a service with no file system access. It never decodes in the app, and the app rebuilds the result only if `Header.isValid` accepts it (`packages/RedlampServices/Sources/DecodeService.swift`, lines 269–303; `docs/raw-pipeline.md`, "The decode service"). It is `#if os(macOS)`. `InProcessDecoder` already exists for the CLI, the tests and "platforms without the decode service" (same file, lines 17–24). On iOS 26, ExtensionFoundation lets an app "run potentially risky code in an isolated process": `AppExtensionProcess` (iOS 26) launches the app's own bundled extension and `makeXPCConnection()` returns an `NSXPCConnection`. An extension point can ask for "Enhanced security", a restrictive sandbox "if an app extension processes unknown data". Extension points are bundle-only by default, and the system enables extensions inside the host app's bundle by default [P27]. Extensions have lower memory limits than apps [P21].

**Assessment.** What the Mac's arrangement gives is that a hostile or damaged file crashes only the service, and that the code parsing it can read nothing else. On an iPhone with full Photos access, LibRaw in the app would run with the app's rights: the whole photo library, the network, every sidecar. So the in-process decoder trades a crash for a much larger exposure if a parser bug is exploitable. **Recommended:** a decoder extension with enhanced security, serving the existing `DecodeServiceProtocol` over the connection `AppExtensionProcess` returns, tried in MOB-03's iPhone build. Its memory limit must be measured with `os_proc_available_memory()` inside the extension on an 8 GB phone, on a 61 MP and a 100 MP raw. If it is too small for the largest files, decode those in the app, and fuzz LibRaw's paths for them. The reads the README already lists as parsed in the app (thumbnails through LibRaw, embedded mattes, metadata) should move to the same extension (README, "What works today"). Apple's own ProRAW and JPEG XL DNGs decode through ImageIO in Redlamp's side decoder (`docs/raw-pipeline.md`), which is Apple's code but still runs in whichever process calls it.

### Metal on A-series against M-series

**Evidence.** Apple's feature set tables put the A14 and M1 in Apple family 7, the A15, A16 and M2 in family 8, the A17 Pro, A18, M3 and M4 in family 9, and the A19 and M5 in family 10. All are Metal 3 and 4 [P24]. Wikipedia lists the A20 Pro as family 11 [X1]; Apple's table, dated May 2026, doesn't list it yet. Families 4 to 9 share the limits Redlamp's kernels touch: 1,024 threads per threadgroup, 32 KB of threadgroup memory, and 2D textures up to 16,384 pixels (32,768 on family 10). SIMD-group matrix multiply and floating-point atomics need family 7 [P24]. Redlamp dispatches 16 × 16 and 16 × 8 threadgroups, and its non-local means denoiser declares two threadgroup `float` arrays (`packages/RedlampKernels/Sources/Shaders/Denoise.metal`, lines 240–241). IOSurface and `makeTexture(descriptor:iosurface:plane:)` are available on iOS 11 and later, `CAMetalDisplayLink` on iOS 17, and EDR content on a `CAMetalLayer` on iOS 16 [P31]. The engine uses no `.managed` storage, which is macOS-only (I searched the engine's sources). ProMotion iPhones run above 60 Hz only with `CADisableMinimumFrameDurationOnPhone` [P31]. The A17 Pro has 6 GPU cores, against 48 or 64 in the M1 Ultra the project measures on [X1]. RenderedRecipeTests already keeps goldens for each GPU, because the M4 Max's renders differ from the M1 Ultra's by a level in 2 to 12% of their pixels (tracker ARC-15).

**Assessment.** No shader needs a feature the A17 Pro lacks; the M1, the project's oldest Mac, is a family below it. The differences are speed, about a tenth of the M1 Ultra's GPU cores, and arithmetic: A-series GPUs need their own goldens for each process version, recorded on a device in Phase 5's performance-lab tiers. float16 is the pyramid's format already (`rgba16Float`, `docs/raw-pipeline.md`), so nothing changes there.

### Memory and jetsam

**Evidence.** iOS terminates an app that crosses its per-process limit (`per-process-limit` in a jetsam report). The limit isn't the device's memory and can change while the app runs; `os_proc_available_memory()` returns what is left, cheaply [P21][P22]. The `com.apple.developer.kernel.increased-memory-limit` entitlement raises the limit "on supported devices" only, and extended virtual addressing enlarges the address space [P22]. `recommendedMaxWorkingSetSize` exists on iOS 16 and later [P23]. The engine sizes its photo cache as `min(recommendedMaxWorkingSetSize / 4, 3 GB)`, and on a memory-pressure event it frees sessions, unloads mask models and empties the detail stage (`packages/RedlampEngine/Sources/RedlampEngine.swift`, lines 182–198). Mask models decide whether they fit from `ProcessInfo.physicalMemory` (`packages/RedlampMasking/Sources/Models/ModelManifest.swift`, line 51). Decoded samples are `UInt16` (`packages/RedlampServices/Sources/DecodedImage.swift`, line 55), and the pyramid is mipmapped `rgba16Float` (`packages/RedlampEngine/Sources/SessionBuilder.swift`, line 119).

**Assessment.** By my arithmetic, a 48 MP ProRAW (8,064 × 6,048, linear RGB) holds about 290 MB of decoded samples. Its pyramid is about 390 MB at full size and 520 MB with its mips. With the non-mipmapped full-size texture `SessionBuilder` also makes (line 213), opening one photo peaks near 1.2 GB before masks, the detail stage and the screen. A 24 MP Bayer raw needs about 300 MB. On an 8 GB iPhone with an unpublished app limit, the engine must take its budgets from `os_proc_available_memory()`, not from the device's memory. It should keep one photo open rather than reading neighbours ahead, render exports in tiles (ARC-05), and consider building the pyramid in bands for files over about 40 MP. Adopting the increased-memory-limit entitlement costs nothing and helps where it applies.

### Thermal state and Low Power Mode

**Evidence.** The render scheduler pauses after work in proportion to the thermal state: none at nominal or fair, as long as the work at serious, three times as long at critical (`packages/RedlampEngine/Sources/RenderScheduling.swift`, line 136). Background analysis waits while Low Power Mode is on or the state is serious or worse (`packages/RedlampDocument/Sources/WorkScheduler.swift`, line 94).

**Assessment.** These carry over unchanged. A phone reaches serious sooner than a Mac (assessment, to be measured), so the editor should also lower the preview's resolution while dragging at serious, before pausing.

### Background work

**Evidence.** iOS doesn't run a background app's Metal command buffers: after the app is in the background they fail with `notPermitted`, and Apple asks apps to stop committing work when deactivated [P25]. `BGContinuedProcessingTask` (iOS 26) exists. It must start in the foreground from a user's action, shows its progress in a Live Activity the user can cancel, reports progress through `ProgressReporting`, and may be ended under resource pressure, tasks showing little progress first. It can use the GPU in the background with `requiredResources = .gpu`, the `com.apple.developer.background-tasks.continued-processing.gpu` entitlement, and only where `BGTaskScheduler.supportedResources` contains `.gpu`, which "not all devices" do [P26][W2]. Which iPhones support background GPU isn't listed (unverified).

**Assessment.** A batch export or a paste to many photos should run as a continued-processing task with GPU where supported, and pause when it isn't, resuming in the foreground. The engine needs a lifecycle hook that stops committing command buffers on deactivation, and it must treat `notPermitted` as "try again later", not as a failed render.

### Core ML and the Neural Engine

**Evidence.** Masking already uses Core ML and Vision (`packages/RedlampMasking/Sources/Inference.swift`, `VisionMasks.swift`), both available on iOS. `MLComputeUnits.all` lets the system choose the Neural Engine; Apple suggests `cpuOnly` for work that may run in the background or beside heavy GPU work [P30]. Model downloads use Background Assets' managed asset packs (`packages/RedlampMasking/Sources/Models/ModelStore.swift`, line 46), a framework available on iOS 16 [P41]. Wikipedia lists neural accelerators in the GPU from the A19 on [X1] (not checked with Apple). On-device timing of the models is tracker DN-04, not started.

**Assessment.** Nothing blocks Core ML. What is open is time and memory: SAM 3's 988 MB and Depth Anything 3's 336 MB ([MOB-desktop-distilled.md](MOB-desktop-distilled.md), question 8) against an app limit that isn't published. `ModelManifest.fits(memory:)` should take the app's available memory on iOS, and its caution text names "Macs" (`packages/RedlampEngineAPI/Sources/Models.swift`, lines 71–82).

### What needs work, by layer

1. **Services:** a `DecodeServiceClient` for iOS that connects through `AppExtensionProcess`, a decoder extension target with enhanced security, and the same `Header.isValid` check, or a deliberate fallback to `InProcessDecoder` for files the extension can't hold.
2. **Engine memory:** budgets from `os_proc_available_memory()` instead of `recommendedMaxWorkingSetSize` and `physicalMemory` (`RedlampEngine.swift`, line 183; `ModelManifest.swift`, line 51), no read-ahead of neighbours on phones, and a measured peak for opening 48 MP and 100 MP files.
3. **Tiling:** ARC-05's tiled export, and possibly a pyramid built in bands for the largest files.
4. **GPU lifecycle:** stop committing at deactivation, retry on `notPermitted`, and run exports in `BGContinuedProcessingTask` with `.gpu` where supported.
5. **Goldens for A-series GPUs:** process-version references recorded on an iPhone, as RenderedRecipeTests does for each Mac GPU.
6. **CI:** an iOS build of the engine layers, so they keep compiling for the platform they claim.
7. **Photo identity:** `EditingEngine.open(_:)` takes a file URL (`packages/RedlampEngineAPI/Sources/EditingEngine.swift`, line 11). That can stay, opening the content editing input's `fullSizeImageURL` [P6] or a raw resource written to the cache, but the app needs a photo identity that is a Photos asset rather than a path, for sidecars, history and thumbnails.
8. **Library layer:** FSEvents-based watching and Trash handling are Mac features (`FolderWatcher.swift`, `VolumeEventStream.swift`, `FileOperations.swift`, line 44, and `LibraryFileSystem`'s `trashItem`). For Photos assets, deletion goes through `PHAssetChangeRequest.deleteAssets` [P8]; whether `trashItem` behaves usefully on iOS is unverified.
9. **Display:** a UIKit Metal view hosting `CanvasRenderer`, with a P3 or extended linear P3 layer as on the Mac (`packages/RedlampCanvas/Sources/CanvasMetalView.swift`, line 104), and `CADisableMinimumFrameDurationOnPhone` for 120 Hz.
10. **Mac-only resources:** lens profiles from the Lens Profiles folder and imported LUTs, which teammates raised ([MOB-desktop-distilled.md](MOB-desktop-distilled.md), question 9).

## 5. What the UI can reuse, and a module plan

### Evidence

- **`ParameterEditing`** (`packages/RedlampDesign/Sources/Binding/ParameterEditing.swift`) is a `@MainActor` protocol over `ParameterID`: read, set, reset, begin and end a continuous edit (one history step per drag), temporary clipping, and the focused and revealed parameter. It imports only `RedlampEngineAPI`. Three members are Mac input (`optionKeyHeld`, and comments naming `,` `.` `-` `=` and ⌘F), but nothing in it is AppKit. `Tracker.swift` beside it imports Foundation and Observation only.
- **`RedlampUI/Sources/Model`** has 53 files and 14,372 lines. Four import AppKit, each for one thing: `EditorModel+Crop.swift` calls `NSSound.beep()` (line 248), `EditorModel+Heal.swift` reads a mask PNG with `NSBitmapImageRep` (line 131), and `FolderLibrary.swift` and `FolderLibrary+Watching.swift` use `NSWorkspace` (lines 212 and 100). The rest import Foundation, Observation, CoreGraphics and Redlamp's engine-side modules.
- **But `EditorModel` can't build for iOS as it stands.** It imports `RedlampCanvas`, which is macOS-only, for `CanvasController` (`EditorModel.swift`, lines 4 and 17). Its library is `FolderLibrary`, and the open photo is a `URL` (lines 28 and 47).
- **`RedlampCanvas`** mixes portable and AppKit code. `CanvasController.swift` and `CanvasController+Comparison.swift` import CoreGraphics, Observation and `RedlampEngineAPI`. `CanvasRenderer.swift` imports Foundation, Metal and QuartzCore and drives a `CAMetalDisplayLink`. `CanvasMetalView`, its two extensions and `CanvasView` are AppKit (file imports, `packages/RedlampCanvas/Sources`).
- **`RedlampDesign`** is AppKit apart from its binding, a few tokens and helpers. On the `iphone-harness` branch, its tokens build for iOS behind `#if os(macOS)`, and `RedlampMobile` (SwiftUI) depends on `.engineAPI` and `.design`. That branch's `Module.swift` builds every module for iPhone and iPad except `generative`, `canvas`, `ui`, `lab` and `automation`.

### Assessment

The editor's logic (history, saving, copy settings, masks, crop and Transform state, recipes, culling) is shared work worth keeping in one place, but it sits in a module that also holds the Mac's views. The way to share it is to move that logic into a UI-neutral layer, not to make `RedlampUI` cross-platform. The proposed graph keeps the existing rule that UI layers reach the engine only through `RedlampEngineAPI` and the pure-value layers (`Module.swift`, lines 67–70).

| Layer (proposed) | Holds | Upstream | Destinations |
| --- | --- | --- | --- |
| Engine layers, as today | Engine, services, document, library, recipes, masking | As today | Mac, iPhone, iPad |
| **`RedlampPhotos`** (new, engine side) | PhotoKit fetches, collections and filters, caching, change observation, content editing input and output, the adjustment-data codec, and the sidecar store keyed by cloud identifier | `engineAPI`, `document` | Mac, iPhone, iPad (PhotoKit is on macOS too, for EXT-04) |
| `RedlampCanvas`, made multi-platform | `CanvasController`, `CanvasRenderer` and the shader on every platform; `CanvasMetalView` under `#if os(macOS)`; a UIKit Metal view under `#if os(iOS)` | `engineAPI` | Mac, iPhone, iPad |
| **`RedlampEditing`** (new, UI side, no AppKit, UIKit or SwiftUI) | `EditorModel` and its extensions, behind a photo-source protocol that `FolderLibrary` (Mac) and a Photos source (iPhone) implement; `SaveQueue`, `ThumbnailLoader`, `SearchMatcher`, `ParameterNames` | `engineAPI`, `canvas`, `design`, `document`, `library`, `recipes` | Mac, iPhone, iPad |
| `RedlampDesign` | Tokens and `ParameterEditing` everywhere; the AppKit controls on the Mac | `engineAPI` | Mac, iPhone, iPad (as on `iphone-harness`) |
| `RedlampUI` | The Mac's AppKit and SwiftUI views and `FolderLibrary` | adds `editing` | Mac |
| `RedlampMobile` | The iPhone and iPad SwiftUI views | adds `editing`, `canvas`, `photos` | iPhone, iPad, Mac (for the harness) |
| Apps | `RedlampMac`; a new iOS app; a decoder extension (ExtensionFoundation, enhanced security); later the Photo Editing Extension (EXT-04) | — | — |

The steps, each landing on its own: make `RedlampCanvas` multi-platform; replace the four AppKit uses in the model (a beep callback, a CoreGraphics PNG read, `NSWorkspace` moved into the Mac's `FolderLibrary`); introduce the photo-source protocol, with `FolderLibrary` as its first implementation; move `Model/` into `RedlampEditing`; extend the purity check to `RedlampEditing`. The Mac-input members of `ParameterEditing` (`optionKeyHeld`, the shortcut comments) can stay, since a phone simply doesn't set them. The keyboard shortcut registry (`packages/RedlampUI/Sources/Shortcuts/ShortcutAction.swift`) is a later candidate for the iPad's `UIKeyCommand`s.

## 6. iOS 26 and 27's design language and system behaviour

### Evidence

- **Liquid Glass (iOS 26)** is "a distinct functional layer for controls and navigation elements" that floats over content. It isn't for the content layer, except that controls such as sliders and toggles "take on a Liquid Glass appearance" while being used. Its clear variant is for "components that float above media backgrounds — such as photos and videos", with a 35% dimming layer behind it over bright content. People can choose a preferred look and turn on Reduce Transparency or Increase Contrast [H1][P40]. Standard bars, sheets, popovers and controls adopt it automatically; custom backgrounds in bars interfere with it [P40].
- **Tab bars** float at the bottom and can minimise when the user scrolls (`tabBarMinimizeBehavior(.onScrollDown)`). A bottom accessory sits above the tab bar and moves inline with it when the bar is minimised (`tabViewBottomAccessory`, `UITabBarController.bottomAccessory`, iOS 26) [H2][P32][W1]. The HIG asks that the tab bar stay visible across sections, except under a modal [H2].
- **Toolbars** hold up to about three groups, top or bottom, and may hide for a distraction-free view if they can be restored reliably [H3]. iOS 27's SwiftUI adds `visibilityPriority(_:)`, `ToolbarOverflowMenu` and the `topBarPinnedTrailing` placement [P37].
- **Sheets** rest at detents (medium and large, and custom ones since iOS 16). A nonmodal sheet lets people keep working in the view beneath, as Notes' formatting sheet does, and `largestUndimmedDetentIdentifier` leaves the view undimmed up to a detent. For "multistep tasks like document or photo editing", the HIG suggests a full-screen modal [H4][P42].
- **iOS 27** adds a slider for how Liquid Glass looks, "from ultraclear to fully tinted" [A-ios]. Apps built with the iOS 27 SDK must use the scene-based life cycle or they fail to launch [P37]. iOS 27.1, in beta, adds APIs for the iPhone Duo, the first folding iPhone: arrangement view controllers, hinge state, reserved regions such as the hinge and camera, and toolbars and tab bars placed on the vertical axis [P37][P38][H10]. The iPhone Duo goes on sale on 23 October 2026 [X1].
- **System gestures.** Normally the system's screen-edge gestures (Control Centre, the Home indicator) take precedence. `preferredScreenEdgesDeferringSystemGestures` lets an immersive app take an edge first, and the HIG asks apps to keep the default, at most making the user swipe twice to leave [P33][H6]. A three-finger swipe means undo and redo on iOS [H5]. `UIScreenEdgePanGestureRecognizer` is what navigation's back swipe uses [P33].
- **Haptics.** Standard sliders, switches and pickers play system haptics. `UIFeedbackGenerator` offers notification, impact and selection patterns, `UICanvasFeedbackGenerator` (iOS 17.5) is for snapping on a canvas, and SwiftUI has `sensoryFeedback` (iOS 17). The HIG asks that haptics be optional and not overused [H7][P35].
- **Accessibility.** An element with the `adjustable` trait must implement `accessibilityIncrement()` and `accessibilityDecrement()`. Custom actions appear in VoiceOver's Actions rotor, and `UIFontMetrics` scales custom fonts with Dynamic Type [P34]. The HIG suggests pairing a slider with a text field and a stepper when its range is wide [H8].
- **Keyboard and pointer** (for the iPad later): `UIKeyCommand`, `UIPointerInteraction` (iPadOS 13.4) and, in iPadOS 26, a menu bar configured with `UIMainMenuSystem` [P36][P37].

### Assessment

- **The editor is the content; the tools are glass.** The photo fills the screen, while the top bar (Done, undo, compare, More) and the module bar float over it in clear glass, dimmed over bright photos. A slider list that covers the photo is better on a standard material (it is content to read, not a floating control), with each slider's knob turning to glass while dragged, as the system's do.
- **The gallery uses a tab bar; the editor doesn't.** Library, Albums and Search as tabs minimise as the grid scrolls; a bottom accessory can show an export's or a batch's progress. The editor opens as a full-screen modal with no tab bar, as the HIG suggests for photo editing.
- **Adjustments in a nonmodal sheet.** A sheet with a small custom detent (one module's sliders), medium (the module with its folded groups) and large (search, history), undimmed up to medium, keeps the photo live while sliders move. That fits the bottom-bar pattern teammates favour ([MOB-mobile-editors.md](MOB-mobile-editors.md), "Assessment: what to try first").
- **Leave the edges to the system.** No custom gesture should start at the top edge or the bottom edge, and the editor should not defer them. A horizontal swipe to the next photo must start away from the leading edge if the editor sits in a navigation stack. Supporting the three-finger undo through `UndoManager` gives Redlamp's history the system gesture for free.
- **Haptics with meaning:** selection feedback when a slider crosses its default or a ± step lands, canvas feedback when the crop snaps, and a setting to turn them off.
- **Every Redlamp slider is an adjustable element:** increment and decrement by the parameter's step, the value spoken with its unit ("Exposure, plus 0.7 stops"), and custom actions for Reset and for typing a value. Labels scale with Dynamic Type through `UIFontMetrics`, or SwiftUI's text styles in `RedlampMobile`'s `MobileTextStyle`.
- **The iPhone Duo** is new enough that its layout should be a follow-up. But if the editor uses system toolbars, they move to the vertical axis on the Duo by themselves [P37], which is a reason to prefer system bars to custom ones.

## 7. Which iPhones to support

### Evidence

Every iPhone below runs iOS 26 and iOS 27: Apple's lists start at the iPhone 11 and the iPhone SE (2nd generation) for both, and add the iPhone 18 Pro and Pro Max for iOS 27 [A-models]. The iPhone Duo isn't on the iOS 27 list yet; it ships on 23 October 2026 [X1]. Apple publishes chips and GPU families [P24], but not memory; the RAM and GPU-core columns are from Wikipedia [X1].

| Model | Chip | GPU family | GPU cores | RAM | ProRAW |
| --- | --- | --- | --- | --- | --- |
| iPhone 12 mini, 12 | A14 | Apple 7 | 4 | 4 GB | No |
| iPhone 12 Pro, Pro Max | A14 | Apple 7 | 4 | 6 GB | Yes |
| iPhone 13 mini, 13; SE (3rd generation) | A15 | Apple 8 | 4 | 4 GB | No |
| iPhone 13 Pro, Pro Max | A15 | Apple 8 | 5 | 6 GB | Yes |
| iPhone 14, 14 Plus | A15 | Apple 8 | 5 | 6 GB | No |
| iPhone 14 Pro, Pro Max | A16 | Apple 8 | 5 | 6 GB | Yes |
| iPhone 15, 15 Plus | A16 | Apple 8 | 5 | 6 GB | No |
| **iPhone 15 Pro, Pro Max** | A17 Pro | Apple 9 | 6 | 8 GB | Yes |
| iPhone 16, 16 Plus | A18 | Apple 9 | 5 | 8 GB | No |
| iPhone 16e | A18 | Apple 9 | 4 | 8 GB | No |
| iPhone 16 Pro, Pro Max | A18 Pro | Apple 9 | 6 | 8 GB | Yes |
| iPhone 17 | A19 | Apple 10 | 5 | 8 GB | No |
| iPhone 17e | A19 | Apple 10 | 4 | 8 GB | No |
| iPhone Air | A19 Pro | Apple 10 | 5 | 12 GB | No |
| iPhone 17 Pro, Pro Max | A19 Pro | Apple 10 | 6 | 12 GB | Yes |
| iPhone 18 Pro, Pro Max | A20 Pro | Apple 11 [X1] | 7 | 12 GB | Yes |
| iPhone Duo | A20 Pro | Apple 11 [X1] | 7 | 12 GB | No |

**Enforcing a floor.** The App Store blocks installs on devices that lack an app's `UIRequiredDeviceCapabilities`. `iphone-performance-gaming-tier` requires "graphics performance and gaming features equivalent to the iPhone 15 Pro and iPhone 15 Pro Max" (iOS 17), and `iphone-ipad-minimum-performance-a12` requires an A12 or later. No value names a memory size. "For app updates, you can only maintain or relax capability requirements" [P39]. Whether the gaming tier admits the 4-core-GPU iPhone 16e and 17e is unverified.

**Reach.** TelemetryDeck's ten most-used iPhones in the week of 28 September 2026 were the iPhone 17 Pro (11.38%), 13 (11.24%), 17 Pro Max, 15, 17, 16 Pro, 16, 16 Pro Max, 14 and 15 Pro (8.15%) [X2]. Its counts show these shares adding up to 100% across the ten, so they are shares of the top ten, not of all iPhones (my calculation from its CSV).

### Assessment

- **Recommended floor: A17 Pro and 8 GB, the iPhone 15 Pro and later, through `iphone-performance-gaming-tier`.** It is the research conventions' floor (`docs/research/notes/_conventions.md`), it is the first GPU family shared with the M3 and M4, every phone in it has 8 GB or more, and the App Store can enforce it. Of the top ten's users, it leaves out the iPhone 13, 15 and 14: about 30% (11.24 + 10.91 + 8.28). Across all iPhones the share left out is larger, since every less common model (the 12s, 13 Pros, 14 Pros, 15 Plus and the SE) is below the floor too.
- **The alternative is A12 with runtime tiers:** install everywhere iOS 26 runs, and limit 4 and 6 GB phones to smaller previews, tiled everything and no large models. It gains the iPhone 15 and 14 (6 GB, about 19% of the top ten), and the iPhone 13's 4 GB is a poor fit for 1.2 GB per open ProRAW. The costs are a second performance tier to test and record, and reviews from people whose phones run Redlamp badly.
- **Start high.** A capability can be relaxed in an update but not raised, so the 15 Pro tier at launch keeps the owner free to admit 6 GB phones later, once tiling and memory use are measured on them. The reverse isn't possible.

## 8. Decisions for the owner

1. **Where does a Photos photo's edit live?** Options: in Photos only, as adjustment data; in Redlamp only, as a sidecar; or both. **Recommended: both,** with the full sidecar in Redlamp's iCloud Drive container keyed by the asset's cloud identifier as the source of truth, and adjustment data with a rendered version written to Photos on Done (section 2).
2. **When does Redlamp write to Photos?** Options: on every change; on Done; or only on an explicit Save to Photos. **Recommended: on Done,** and once per batch, since each save prompts. Redlamp's sidecar autosaves meanwhile.
3. **The iPhone floor.** Options: A17 Pro and 8 GB through the gaming tier; A12 with runtime tiers. **Recommended: the A17 Pro tier for the first release,** relaxed later if measurements allow (section 7).
4. **How is decoding isolated?** Options: a decoder extension with enhanced security (iOS 26 ExtensionFoundation); in the app, as the CLI does. **Recommended: the extension,** tried in MOB-03 with its memory limit measured, with in-process decoding only for files that can't fit and only after fuzzing.
5. **The deployment target.** Options: iOS 26, as `Module.swift` has it; iOS 27, which adds ratings, keywords, captions, RAW+JPEG base choice and the persistent-change observer on the same iPhones. **Recommended: decide when the app's build starts.** If that is after mid-2027, iOS 27 costs little reach and removes a set of `#available` branches (assessment).
6. **Ratings and flags in Photos.** Options: Redlamp's sidecar only; mirror the rating into Photos' iOS 27 rating and picks into Favourite; or read Photos' ratings as Redlamp's. **Recommended: sidecar first, with mirroring to Photos as a setting,** once it is known whether a rating change prompts (unverified).
7. **Limited library access.** Options: require full access; support limited access as a reduced mode. **Recommended: support it,** with the picker to add photos and an explanation where albums are missing.
8. **Files and cards in the first release.** Options: the Photos library only; plus single files from Files and the share sheet; plus folders on drives and cards. **Recommended: Photos plus single files,** with folders later, on the iPad first.
9. **The Photo Editing Extension (EXT-04).** Options: in the first release; in a later one. **Recommended: later,** after the app's memory use is measured, since extensions run under a lower memory limit.

## Sources

All checked on 13 October 2026.

**Apple Developer documentation** (each page also at `https://developer.apple.com/tutorials/data/<path>.json`)

- [P1] `PHAdjustmentData`: <https://developer.apple.com/documentation/photos/phadjustmentdata>
- [P2] `PHAdjustmentData.init(formatIdentifier:formatVersion:data:)` and `data`: <https://developer.apple.com/documentation/photos/phadjustmentdata/init(formatidentifier:formatversion:data:)>
- [P3] `PHContentEditingOutput`: <https://developer.apple.com/documentation/photos/phcontenteditingoutput>
- [P4] `renderedContentURL`, `supportedRenderedContentTypes`, `defaultRenderedContentType`, `renderedContentURL(for:)` (iOS 17): <https://developer.apple.com/documentation/photos/phcontenteditingoutput/renderedcontenturl>
- [P5] `PHContentEditingInputRequestOptions.canHandleAdjustmentData`: <https://developer.apple.com/documentation/photos/phcontenteditinginputrequestoptions/canhandleadjustmentdata>
- [P6] `PHContentEditingInput.fullSizeImageURL`, `contentType` (iOS 26): <https://developer.apple.com/documentation/photos/phcontenteditinginput>
- [P7] `PHAsset.requestContentEditingInput(with:completionHandler:)` (macOS 10.15): <https://developer.apple.com/documentation/photos/phasset/requestcontenteditinginput(with:completionhandler:)>
- [P8] `PHAsset` and `PHAssetChangeRequest`, including `rating`, `PHAsset.Rating`, `caption`, `addKeyword(_:)`, `extendedMetadata`, `originalResourceChoice`, `revertAssetContent(to:)` and `setLivePhotoVideoPlaybackEnabled(_:)` (iOS 27), `contentType` (iOS 26), `adjustmentTimestamp` and `adjustmentsState` (iOS 18), `hasAdjustments` and `adjustmentFormatIdentifier` (iOS 15): <https://developer.apple.com/documentation/photos/phasset>, <https://developer.apple.com/documentation/photos/phassetchangerequest>
- [P9] `PHFetchOptions` (supported keys; `prefetchAssetExtendedMetadata`, iOS 27): <https://developer.apple.com/documentation/photos/phfetchoptions>
- [P10] `PHAssetResourceType` (`alternatePhoto`, `adjustmentBasePhoto`, `photoProxy`): <https://developer.apple.com/documentation/photos/phassetresourcetype>
- [P11] `PHAssetResource` (`contentType`, iOS 26; `uniformTypeIdentifier`, deprecated 27.2), `PHAssetResourceManager`, `PHAssetResourceRequestOptions.isNetworkAccessAllowed`: <https://developer.apple.com/documentation/photos/phassetresource>
- [P12] `PHImageRequestOptions.isNetworkAccessAllowed` and `progressHandler`: <https://developer.apple.com/documentation/photos/phimagerequestoptions/isnetworkaccessallowed>
- [P13] `PHCachingImageManager`: <https://developer.apple.com/documentation/photos/phcachingimagemanager>
- [P14] `PHPhotoLibraryChangeObserver`; `PHPersistentChange` (iOS 16); `PHPhotoLibrary.register(_:)` for persistent changes (iOS 27): <https://developer.apple.com/documentation/photos/phphotolibrarychangeobserver>, <https://developer.apple.com/documentation/photos/phphotolibrary/register(_:)-7lhue>
- [P15] `PHCloudIdentifier`, `cloudIdentifierMappings(forLocalIdentifiers:)`, `localIdentifierMappings(forSynced:)` (iOS 27): <https://developer.apple.com/documentation/photos/phcloudidentifier>
- [P16] Delivering an Enhanced Privacy Experience in Your Photos App; `PHAuthorizationStatus.limited`; `PHAccessLevel`: <https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app>
- [P17] `PHPickerViewController`: <https://developer.apple.com/documentation/photosui/phpickerviewcontroller>
- [P18] `PHAssetCollectionSubtype`, `PHAssetMediaSubtype`: <https://developer.apple.com/documentation/photos/phassetcollectionsubtype>, <https://developer.apple.com/documentation/photos/phassetmediasubtype>
- [P19] PhotoKit updates: <https://developer.apple.com/documentation/updates/photokit>
- [P20] Creating Photo Editing Extensions; `PHContentEditingController`: <https://developer.apple.com/documentation/photokit/creating-photo-editing-extensions>
- [P21] Identifying high-memory use with jetsam event reports: <https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports>
- [P22] `os_proc_available_memory`; `com.apple.developer.kernel.increased-memory-limit`; `com.apple.developer.kernel.extended-virtual-addressing`: <https://developer.apple.com/documentation/os/os_proc_available_memory>, <https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit>
- [P23] `MTLDevice.recommendedMaxWorkingSetSize` (iOS 16): <https://developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize>
- [P24] Metal feature set tables, dated 21 May 2026: <https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf>; `MTLGPUFamily`: <https://developer.apple.com/documentation/metal/mtlgpufamily>
- [P25] Preparing your Metal app to run in the background: <https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background>
- [P26] `BGContinuedProcessingTask`, `BGContinuedProcessingTaskRequest`, `BGTaskScheduler.supportedResources`, and Performing long-running tasks on iOS and iPadOS (iOS 26): <https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask>, <https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados>
- [P27] ExtensionFoundation; Adding support for app extensions to your app; Discovering app extensions from your app; `AppExtensionProcess`, `makeXPCConnection()` and `AppExtensionPoint` (iOS 26): <https://developer.apple.com/documentation/extensionfoundation>, <https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app>, <https://developer.apple.com/documentation/extensionfoundation/appextensionprocess>
- [P28] `UIDocumentPickerViewController`; Providing access to directories: <https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller>, <https://developer.apple.com/documentation/uikit/providing-access-to-directories>
- [P29] ImageCaptureCore (iOS 13): <https://developer.apple.com/documentation/imagecapturecore>
- [P30] `MLComputeUnits`: <https://developer.apple.com/documentation/coreml/mlcomputeunits>
- [P31] IOSurface (iOS 11); `makeTexture(descriptor:iosurface:plane:)`; `CAMetalDisplayLink` (iOS 17); `CAMetalLayer.wantsExtendedDynamicRangeContent` (iOS 16); `CADisableMinimumFrameDurationOnPhone`: <https://developer.apple.com/documentation/iosurface>, <https://developer.apple.com/documentation/quartzcore/cametaldisplaylink>, <https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone>
- [P32] `tabBarMinimizeBehavior(_:)`, `tabViewBottomAccessory(content:)`, `UITabBarController.bottomAccessory`, `UIGlassEffect`, `glassEffect(_:in:)` (iOS 26): <https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)>, <https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)>, <https://developer.apple.com/documentation/uikit/uitabbarcontroller/bottomaccessory>
- [P33] `preferredScreenEdgesDeferringSystemGestures`, `prefersHomeIndicatorAutoHidden`, `UIScreenEdgePanGestureRecognizer`: <https://developer.apple.com/documentation/uikit/uiviewcontroller/preferredscreenedgesdeferringsystemgestures>
- [P34] `UIAccessibilityTraits.adjustable`, `UIAccessibilityCustomAction`, `UIFontMetrics`: <https://developer.apple.com/documentation/uikit/uiaccessibilitytraits/adjustable>
- [P35] `UICanvasFeedbackGenerator` (iOS 17.5), `sensoryFeedback(_:trigger:)` (iOS 17): <https://developer.apple.com/documentation/uikit/uicanvasfeedbackgenerator>
- [P36] `UIKeyCommand`, `UIPointerInteraction`: <https://developer.apple.com/documentation/uikit/uikeycommand>, <https://developer.apple.com/documentation/uikit/uipointerinteraction>
- [P37] UIKit updates and SwiftUI updates (June 2025, June 2026, September 2026): <https://developer.apple.com/documentation/updates/uikit>, <https://developer.apple.com/documentation/updates/swiftui>
- [P38] `UIArrangementViewController`, `UIHinge`, `preferredVerticalBarBehavior` (iOS 27.1 beta): <https://developer.apple.com/documentation/uikit/uiarrangementviewcontroller>
- [P39] `UIRequiredDeviceCapabilities`: <https://developer.apple.com/documentation/bundleresources/information-property-list/uirequireddevicecapabilities>
- [P40] Liquid Glass; Adopting Liquid Glass: <https://developer.apple.com/documentation/technologyoverviews/liquid-glass>, <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>
- [P41] Background Assets (iOS 16): <https://developer.apple.com/documentation/backgroundassets>
- [P42] `UISheetPresentationController.Detent`, `custom(identifier:resolver:)` (iOS 16), `largestUndimmedDetentIdentifier`: <https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/detent>

**Human Interface Guidelines** (each also at `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`)

- [H1] Materials: <https://developer.apple.com/design/human-interface-guidelines/materials>
- [H2] Tab bars: <https://developer.apple.com/design/human-interface-guidelines/tab-bars>
- [H3] Toolbars: <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- [H4] Sheets (updated 24 March 2026): <https://developer.apple.com/design/human-interface-guidelines/sheets>
- [H5] Gestures: <https://developer.apple.com/design/human-interface-guidelines/gestures>
- [H6] Going full screen: <https://developer.apple.com/design/human-interface-guidelines/going-full-screen>
- [H7] Playing haptics: <https://developer.apple.com/design/human-interface-guidelines/playing-haptics>
- [H8] Sliders: <https://developer.apple.com/design/human-interface-guidelines/sliders>
- [H9] Design, What's new (the dated list of HIG changes through 18 September 2026): <https://developer.apple.com/design/whats-new/>
- [H10] Designing for iPhone Duo (new 9 September 2026): <https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo>

**WWDC**

- [W1] Build a UIKit app with the new design, WWDC25: <https://developer.apple.com/videos/play/wwdc2025/284/>
- [W2] Finish tasks in the background, WWDC25: <https://developer.apple.com/videos/play/wwdc2025/227/>

**Apple, other**

- [A-models] iPhone models compatible with iOS 27, and with iOS 26: <https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-27-iphe3fa5df43/ios>, <https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/26/ios/26>
- [A-ext] Connect external storage devices to iPhone: <https://support.apple.com/guide/iphone/external-storage-devices-iph95baac91f/ios>
- [A-ios] iOS 27: <https://www.apple.com/os/ios/>

**Secondary**

- [X1] Wikipedia, List of iPhone models (chips, GPU families and cores, RAM, release dates, ProRAW): <https://en.wikipedia.org/wiki/List_of_iPhone_models>. Apple doesn't publish RAM.
- [X2] TelemetryDeck, iPhone Models Market Share in 2026, updated 1 October 2026, with its CSV: <https://telemetrydeck.com/survey/apple/iPhone/models/>

**Redlamp** (on `main` unless noted)

- [S-sidecar] `docs/recipes/sidecar-format.md`
- `Tuist/ProjectDescriptionHelpers/Module.swift`; on the `iphone-harness` branch, the same file and `packages/RedlampMobile/Sources`
- `docs/raw-pipeline.md`; `packages/RedlampServices/Sources/DecodeService.swift`, `DecodedImage.swift`
- `packages/RedlampEngine/Sources/RedlampEngine.swift`, `RenderScheduling.swift`, `SessionBuilder.swift`, `SurfacePool.swift`; `packages/RedlampEngineAPI/Sources/Rendering.swift`, `EditingEngine.swift`, `Models.swift`
- `packages/RedlampMasking/Sources/Models/ModelManifest.swift`, `ModelStore.swift`; `packages/RedlampKernels/Sources/Shaders/Denoise.metal`
- `packages/RedlampDocument/Sources/WorkingFolder.swift`, `FolderWatcher.swift`, `SidecarLocator.swift`, `WorkScheduler.swift`; `packages/RedlampLibrary/Sources/Changes/ChangeTracker.swift`, `VolumeEventStream.swift`, `Files/FileOperations.swift`
- `packages/RedlampUI/Sources/Model/` (`EditorModel.swift`, `EditorModel+Crop.swift`, `EditorModel+Heal.swift`, `FolderLibrary.swift`, `FolderLibrary+Watching.swift`); `packages/RedlampCanvas/Sources/`; `packages/RedlampDesign/Sources/Binding/ParameterEditing.swift`
- `docs/research/research-tracker.md`: EXT-04, ARC-05, ARC-15, DN-04, DEC-20, DEC-43, DEC-75, MOB-01 to MOB-04
- Teammates' notes: [MOB-desktop-distilled.md](MOB-desktop-distilled.md), [MOB-lightroom-mobile.md](MOB-lightroom-mobile.md), [MOB-mobile-editors.md](MOB-mobile-editors.md)
