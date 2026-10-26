# Import from Apple Photos: design

Many photographers starting with Redlamp keep their photos in Apple Photos, sorted into albums, and want to edit new photos in Redlamp without leaving that library behind. This design brings chosen albums across, as the import from Lightroom Classic brings a catalog: a window that finds what's there, a report before anything is written, the import in parts with Stop, and Undo Import. Then it keeps those albums in step, offering the new photos that arrive in them. Tracker: LIB-54 (the import), LIB-55 (followed albums), DEC-106 (Photos is only read), and EXT-05 (Save to Photos, proposed for later).

**Status (2026-10-26):** designed; the owner made the decisions below the same day, for 0.3.5.

## Where it starts

**The Lightroom import** (LIB-29, `packages/RedlampLibrary/Sources/Migration/`) reads a catalog whose photos are already files in folders, so it only writes sidecars: `LightroomImport` runs `LibraryMetadata`'s batches in parts, with Stop, Undo Import and a record of imports in the library's folder. Its window (`packages/RedlampUI/Sources/Library/Migration/`) goes from setup to the report, then to progress (LIB-52) and the result.

**Photos is different:** it keeps its originals inside its library package, or only in iCloud with Optimize Mac Storage, and Apple's framework for it, PhotoKit, gives an app a photo's data, never a path. So this import also copies, and the copying is the card import's (LIB-27, `packages/RedlampLibrary/Sources/Import/`): `ImportPlanner` names files by the folder and name templates, `Importer` copies, reads each copy back, journals, settles and indexes, skips photos the library has by content key, and rolls a finished import back (`ImportRollback`), its copies to the Trash and their rows out of the index. That whole path works on files in a folder on a source (`ImportSource.Kind` is `card` or `folder`).

**PhotoKit, as Apple documents it** (checked 26 October 2026 against Apple's documentation; the platform research is [MOB-platform-and-architecture.md](../research/notes/MOB-platform-and-architecture.md)):

- `PHAssetCollection` and `PHCollectionList` give the albums, smart albums, shared albums and folders, with `estimatedAssetCount`. `PHAsset` gives `localIdentifier`, `creationDate`, `location`, `isFavorite`, `isHidden`, `mediaType` and `mediaSubtypes` (Live, HDR, panorama, depth), `burstIdentifier` and `burstSelectionTypes`, `sourceType` and `hasAdjustments`.
- `PHAssetResource.assetResources(for:)` lists an asset's files: `.photo` (the original; the JPEG of a RAW+JPEG pair), `.alternatePhoto` (the pair's raw), `.fullSizePhoto` (the rendered edit), `.adjustmentData`, `.pairedVideo` (a Live Photo's video), each with its `originalFilename`. `PHAssetResourceManager.writeData(for:toFile:options:)` writes one to a file, downloading it from iCloud when `isNetworkAccessAllowed` is true, with a progress handler.
- `PHCloudIdentifier` names the same asset on every device on the same iCloud Photos library ([docs](https://developer.apple.com/documentation/photos/phcloudidentifier)).
- From macOS 27 only: `PHAsset.rating` ([docs](https://developer.apple.com/documentation/photos/phasset/rating-swift.property)), `PHAsset.extendedMetadata` with `caption`, `keywords` and `originalFilename` ([docs](https://developer.apple.com/documentation/photos/phassetextendedmetadata)), fetched with the assets by `PHFetchOptions.prefetchAssetExtendedMetadata`, and `originalResourceChoice` for RAW+JPEG pairs ([docs](https://developer.apple.com/documentation/photos/phasset/originalresourcechoice-swift.property)).
- Not in PhotoKit on any version: titles, people and pets, memories, and a smart album's rules.
- An app asks with `NSPhotoLibraryUsageDescription`; with the hardened runtime and in the sandbox it needs the `com.apple.security.personal-information.photos-library` entitlement. PhotoKit on the Mac reads the System Photo Library.

## Decisions (2026-10-26, the owner)

- **Photos is only read, through PhotoKit alone** (DEC-106): never Photos' own database, never AppleScript, and nothing written back. Edits going back to Photos are EXT-05, a later row.
- **A photo edited in Photos** comes as its original, with Photos' rendered version stacked over it. Photos' edit data, an undocumented format, isn't read.
- **Metadata through PhotoKit only:** favourites, albums, dates and original names on macOS 26; ratings, captions and keywords too from macOS 27. The report says what stays in Photos and what macOS 27 would bring.
- **Keeping in step:** the chosen albums are remembered, the new photos in them are offered in the Library panel with Import, and a setting, off by default, imports them as they arrive.

## What each photo becomes

- **Files.** The original, as Photos has it, named by Import's templates: a RAW+JPEG photo as a pair with one stem, ProRAW as its DNG, a Live Photo as its still (its video left), HEIC, JPEG, PNG and TIFF as they are. Videos are left out and counted. Shared albums hold reduced copies, not originals: they're listed, off by default, and marked so.
- **Edited in Photos.** Its `.fullSizePhoto` comes as a second photo, `<name> (Photos edit).<ext>`, stacked with the original, on top so the grid shows the photo as Photos does. Both get the photo's metadata.
- **Bursts.** The burst's key photo and the frames the photographer picked, stacked, the key photo on top.
- **Fields,** in the photo's sidecar: the favourite as the pick flag (the pairing MOB §7 proposes for the iPhone); from macOS 27 the rating, the caption and the keywords (flat, as Photos has them); the original's file name as `originalName`; a date changed in Photos as `captureShift` and `captureOffset`, against the time the file records.
- **Collections.** Each album a collection, Photos' folders as collection sets, by path in the sidecar as LIB-23 keeps them; a smart album a plain collection of the photos it holds at the import. A photo in several albums is copied once and joins each album's collection.
- **Where it came from:** a new `applePhotos` object in the sidecar's `metadata`, with `id` (the asset's local identifier), `cloud` (its cloud identifier, when it has one) and `version` (`original` or `edited`). Later imports skip photos by it, and EXT-05 will find the asset by it. Builds before it keep it as an unknown key.
- **Left in Photos, and counted in the report:** titles, people, memories, hidden photos unless the import includes them, Recently Deleted, and a place set only in Photos: a photo's own GPS stays in its file, but sidecars have no field for coordinates (a later row could add one with the Map, LIB-35).

## How it runs

1. **Census** (`ApplePhotosCensus`): the chosen albums' assets, read without copying anything, become the report: photos and pairs, edited photos, Live Photos, bursts, videos and hidden photos left, shared albums' reduced copies, those already imported (by `applePhotos.id`), and the fields this Mac's PhotoKit gives.
2. **Staging** (`ApplePhotosStager`): each chosen asset's files written by `writeData` into a hidden staging folder on the destination's volume (`.Redlamp Photos Import/<import id>/`), one folder per asset so names never collide, downloading from iCloud with progress; a staged file that's already complete is kept, so a stopped import resumes.
3. **Copy** by the card import's `Importer`, with the staging folder as a `folder` source and Import's destination and templates: naming, collisions, verification, the journal and the content-key check all as LIB-27 has them. The naming grammar gets an `{album}` token, the photo's first chosen album, empty elsewhere.
4. **Sidecars.** The fields, collections, stack and `applePhotos` go on the plan's items and are written with the sidecar the importer writes anyway, one write per photo.
5. **Record.** `Apple Photos.json` in the library's folder keeps each import (its id, date, albums, settings), the followed albums, and the assets imported, by local identifier, with their paths; it can be rebuilt from the sidecars.
6. **Undo Import** rolls the import back as `Importer` does: its copies to the Trash, their rows out of the index, and the record updated. The staging folder is removed once an import ends.

**Followed albums (LIB-55).** The record's albums are recounted at launch and whenever PhotoKit reports a change (`PHPhotoLibraryChangeObserver`): their assets not in the record are the new photos. The Library panel shows "From Apple Photos" with their count and Import, which runs steps 1 to 6 with the last import's settings and shows the window's progress. Settings › Library's Import new photos from followed albums automatically (off by default) runs it without asking, a minute after the last change. A photo that leaves Photos or an album is never removed from Redlamp.

## The parts

- **`packages/RedlampLibrary/Sources/ApplePhotos/`:** `ApplePhotosLibrary`, a protocol over what the import needs from Photos (access, the collection tree, assets with their fields and resources, writing a resource to a file, change notices); `PhotoKitLibrary`, its PhotoKit implementation, with `@available(macOS 27, *)` branches; `SimulatedPhotosLibrary`, read from a manifest of albums and assets over fixture files, for the tests, the harness, the CLI's tests and the regression suite, since none of them can be given Photos access; and the census, stager, import and record.
- **`apps/RedlampCLI`:** `redlamp library photos` with `--albums`, `--census` and `--apply`, `--album` naming the albums, `--simulated <manifest>`, and `--json`, beside `lightroom`.
- **`packages/RedlampUI/Sources/Library/ApplePhotos/`:** File › Import from Apple Photos… (a `ShortcutAction`), a window of its own as the Lightroom import has: access (asking, denied with a button to System Settings, limited), setup (the album tree with counts and checkboxes, the destination and templates with a live example, Include hidden photos), the report, progress and the result with Undo Import; each state in the harness's Library section. The Library panel's entry and the setting for LIB-55.
- **`apps/RedlampMac`:** the usage string, and the Photos entitlement in the direct download and the App Store build.

## Budgets

On the simulated library: a census of 10,000 assets in 2 s, staging bounded by the disk, a recount of followed albums holding 10,000 photos in 100 ms, and the import's own steps within LIB-27's budgets. The owner's census of his own library checks them against a real one, with its iCloud downloads.

## Steps

1. Tracker rows and this design.
2. The source: protocol, PhotoKit implementation, simulated library, census and report, and `redlamp library photos --albums` and `--census`; a Redlamp Bench task for the owner's census.
3. Staging and the copy through `Importer`, the `{album}` token, edited versions and bursts stacked.
4. Sidecar fields, the `applePhotos` object (sidecar format, schema, `SidecarSchemaTests`), the record, Undo Import, `--apply`.
5. The window and its harness scenes; the app's usage string and entitlement.
6. Followed albums and the setting.
7. Regression scenarios on the simulated library; the README, the Lightroom comparison, the manual and the App Store compliance notes.

## Open questions, settled by the owner's census

- How limited access behaves on the Mac, and what a limited app can list.
- How long originals in iCloud take to download, and how cancelling behaves.
- Which type `.fullSizePhoto` is for HEIC, JPEG and raw originals.
- Which resources RAW+JPEG photos and bursts have in practice.
- Whether macOS shows the Photos prompt for the CLI run from Terminal.
