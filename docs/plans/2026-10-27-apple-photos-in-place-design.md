# Apple Photos in place: design

Many photographers keep their photos in Apple Photos, with Optimize Mac Storage leaving most originals in iCloud. 0.3.4's import copies a chosen album's originals into folders, which takes their space again and splits each photo in two. This design leaves them in Photos: the albums a photographer chooses appear in the library beside its folders, each photo known by its Photos identifiers, shown from Photos' own thumbnails and previews, its original downloaded only when it's viewed at full size, edited or exported, and Redlamp's culling, metadata and edits kept on this Mac. Copying stays a choice. Tracker: LIB-57 ([#495](https://github.com/pdcgomes/redlamp/issues/495)) and DEC-107, building on LIB-54 ([#488](https://github.com/pdcgomes/redlamp/issues/488), the import) and LIB-55 ([#489](https://github.com/pdcgomes/redlamp/issues/489), followed albums), within DEC-106 (Photos only read, through PhotoKit), DEC-43 (sidecars on this Mac), DEC-76 (the iPhone's edits), EXT-04 ([#386](https://github.com/pdcgomes/redlamp/issues/386), favourites and ratings), EXT-05 ([#487](https://github.com/pdcgomes/redlamp/issues/487), Save to Photos) and MOB-08 ([#413](https://github.com/pdcgomes/redlamp/issues/413), photos identified by more than a path).

**Status (2026-10-27):** the owner answered every decision below on 27 October, each with its recommended option (A), and the parts became LIB-58 to LIB-65 under LIB-57. LIB-58, Photos as a source of the index, is on main (a732fdfb8 to 69e0d620c), reviewed for 0.3.5 at the owner's request: schema 16, the Apple Photos root and its indexer, `ApplePhotosLibrary`'s additions, `PhotoKitLibrary` on `archivalStringValue` and `redlamp library photos --keep` and `--list`; on the build Mac it indexed 50,000 simulated assets (57,500 rows) in 1.7 s, its first batch in 0.06 s. LIB-61, following Photos' changes, is on main too (0cb57fd49 to 98fca2c52): on the same 50,000 assets a launch with Photos unchanged reads its changes in 0.1 ms, fetching no album, and a change in Photos is listed 497 ms after its notice; photos deleted in Photos are kept as missing for Library Health. LIB-59, thumbnails and previews from PhotoKit, is on main (6f9a73ead to a5dae0949): each row's store key from its asset key and resource, standing as its content key; Photos' images at the store's sizes without the network (`ApplePhotosImages`, PhotoKit's through `PHCachingImageManager` on RedlampUI's side); the rows on and near the screen cached; the cloud mark. At 50,000 simulated assets the grid met every budget below, nothing downloaded (main-thread p99 6.0 ms, a screenful from Photos at p95 53 ms, a row from the store at p95 5.1 ms, 22.6 KB a thumbnail). LIB-65, favourites followed from Photos, is on main (9b715ef9c and 0a376e4c3): a favourite is a pick, the photo's own, so the grid shows it, and the pick follows the favourite while the photo still shows what the favourite gave it when last read; a pick set in Redlamp stays, and one cleared in Redlamp, which a sidecar can't hold, stays until the favourite comes to agree with it. LIB-60, originals on demand, is on main (642236030 to ceb631bbc): `ApplePhotosOriginals`, the cache of originals downloaded from iCloud by priority, with progress, Cancel, partial files and offline errors, within the 20 GB budget; Develop's preview at once with the download's progress and Cancel (the download shown 5 µs after the photo is chosen, its preview 7 ms after, on the build Mac); 1:1, Compare, Survey, focus peaking and export downloading first; Download Originals; Settings › Library › Apple Photos; `--originals` and `--evict`; the grid's rings and `redlamp export` left. LIB-63, Copy to Folder for photos kept in Photos, is on main in part (ffe4974fd, 0f61fa45c and e3289cf6f): LIB-54's import over photos kept in place, their files from the cache of originals and their sidecars going with them, Redlamp's fields over Photos' and no album made a collection, in a Copy to Folder window of its own that Photo › Copy to Folder… and a drop onto a folder open; each copy stands in for its photo by LIB-64's rule, in All Photographs too, until Undo Copy gives the photo back; the album's Copy to Folder… waits for LIB-62's section. LIB-64, copies beside albums kept in place, is on main (e9efb4c56 to 79e55d81f): a photo LIB-54's import or Copy to Folder copied stands in for its asset, listed in its albums with no row made from Photos, found by its identifiers and its sidecar, `photo_copies` (schema 17) keeping which copy stands in; From Apple Photos leaves out albums kept in place; with 10,000 of 50,000 simulated assets copied, the first keep took 1.9 s. Nothing shows the albums in the app yet (LIB-62). The census of the owner's own library, which settles the points marked unverified below and checks the budgets on it, is on main (637b63ec8 to 8571bb90e): `PhotoKitCensus`, run as `--photos-census` in a Redlamp build on the Mac with his library from the kit `scripts/photos-census-kit.sh` makes; it waits on his run on his MacBook Air.

## Where it starts

**What ships in 0.3.4.** LIB-54 (`packages/RedlampLibrary/Sources/ApplePhotos/`, [design](2026-10-26-apple-photos-import-design.md)) reads Photos through `ApplePhotosLibrary`, a protocol with two implementations: `PhotoKitLibrary`, Photos itself, and `SimulatedPhotosLibrary`, a manifest of albums and assets over fixture files (`tests/fixtures/apple-photos/manifest.json`) for the tests, the harness, the CLI's tests and the regression suite. The protocol gives access, the collection tree, the assets of chosen albums with their fields and resources (`ApplePhotosAsset`, `ApplePhotosResource`), a resource written to a file with progress and cancelling (through `PHAssetResourceManager.requestData`, so Stop can cancel a download), and a stream of change notices. `ApplePhotosCensus`, `ApplePhotosStager` and `ApplePhotosImport` stage each asset's files and hand them to the card import's `Importer`; `ApplePhotosRecord` keeps `Apple Photos.json` in the library's folder; each copy's sidecar names its asset in `applePhotos` (`id`, `cloud`, `version`). LIB-55's `ApplePhotosFollower` (`packages/RedlampUI/Sources/Library/ApplePhotos/`) counts new photos in followed albums at launch and on each change notice and shows From Apple Photos in the Library panel (`SidebarOutlineView.Kind.applePhotos`). All of it is reusable here; what it lacks for in-place photos is thumbnails, previews, persistent change history, lookups by identifier and content versions.

**PhotoKit, as Apple documents it** (checked on 27 October 2026 against Apple's documentation JSON; the platform research is [MOB-platform-and-architecture.md](../research/notes/MOB-platform-and-architecture.md)):

- **Thumbnails and previews.** `PHImageManager.requestImage(for:targetSize:contentMode:options:resultHandler:)` gives an image "at, or near, the size you specify", may call its handler first with a degraded image and again with the final one (`PHImageResultIsDegradedKey`), and downloads only when `PHImageRequestOptions.isNetworkAccessAllowed` is true; without it, an image that needs iCloud comes back empty with `PHImageResultIsInCloudKey`. `version` chooses `current` (with edits), `unadjusted` or `original`. `PHCachingImageManager.startCachingImages(for:targetSize:contentMode:options:)` prepares images in the background for later requests with exactly the same size, mode and options. `allowsCachingHighQualityImages` is deprecated from macOS 26.
- **Originals.** `PHAssetResourceManager.requestData(for:options:dataReceivedHandler:completionHandler:)` delivers a resource's bytes in chunks, downloading when `PHAssetResourceRequestOptions.isNetworkAccessAllowed` is true, with a progress handler, and can be cancelled by its request ID; without network access a cloud-only resource fails with an error. `requestImageDataAndOrientation(for:options:resultHandler:)` gives "the largest represented image" as data, the rendered edit for `version = .current`. `PHAssetResource` gives `pixelWidth` and `pixelHeight` (macOS 13), and `dataSize` from macOS 27 only.
- **Identity.** A local identifier is valid on one device. `PHCloudIdentifier` names an asset synced through iCloud Photos on every device on the same account; `cloudIdentifierMappings(forLocalIdentifiers:)` and `localIdentifierMappings(for:)` (macOS 12) map them in batches, and Apple calls the mapping "an expensive operation" to do "at load and save points". `PHCloudIdentifier.stringValue`, which `PhotoKitLibrary` uses today, is deprecated in macOS 27; `archivalStringValue` and `init(archivalStringValue:)` (macOS 15.2) replace it, in a compatible format.
- **Changes.** `PHPhotoLibraryChangeObserver` hears every change while the app runs. `fetchPersistentChanges(since:)` (macOS 13) returns what changed since a saved `PHPersistentChangeToken` (`currentChangeToken`), across launches, as inserted, updated and deleted local identifiers per object type (`PHPersistentObjectChangeDetails`), or fails when the token has expired. macOS 27 adds `register(_:)` for an observer told when persistent changes are committed, which needs read-write access. `PHAsset.modificationDate` changes when content or metadata change; `adjustmentTimestamp` (macOS 15) is when the asset was last edited or reverted, and `adjustmentsState` (macOS 15) says none, camera auto-adjusted or user-adjusted.
- **Limited access.** With limited access an app can't fetch user albums. `presentLimitedLibraryPicker(from:)` lists iOS, iPadOS, Mac Catalyst and visionOS, not macOS.
- **Not documented, so unverified until the owner's census:** which derivatives Photos keeps on the Mac under Optimize Mac Storage and at what size; whether a derivative of the `original` version is local for an asset edited in Photos; whether local derivatives keep the camera's EXIF; whether Photos keeps an original it downloaded for an app; how long downloads take and how cancelling behaves; whether local identifiers survive Recently Deleted's Recover; whether PhotoKit names the System Photo Library, so that a switch of library can be told; how limited access's selection is changed on the Mac.

### Where the library and editor assume a photo is a file at a path

Counted on main at 5c67b5ae8, sources only, tests left out.

- **The index's rows and keys** (`packages/RedlampLibrary/Sources/Index/LibraryIndexSchema.swift`). A photo is a `folders` row, under a `roots` row with a `volume` and a bookmark, plus a `name`: `photos_place` is unique on `(folder, name, version)` (schema 15, LIB-48). `PhotoRecord.Kind` comes from the extension, `size` and `modified` from the file, `content_key` from its first 64 KiB (`Indexing/ContentKey.swift`), `file_id` from the inode. Needs: a root that is Photos, a folder per asset so names never collide, and a table naming each row's asset, its resource and its content version.
- **The indexer** (`Indexing/LibraryIndexer+Photos.swift`) reads each file's head through its volume's readers (`VolumeIO.read`, 19 reads in 5 files) for `PhotoMetadataReader`, and lists folders by signature (`Indexing/FolderSignature.swift`). Needs: rows built from PhotoKit's fields, with camera, lens and exposure only once an original is read.
- **The column store and queries** (`Query/ColumnStore.swift`, `HotColumns.folder` and `name`; `Query/ColumnNames.swift`; `Query/QueryEngine+Facets.swift`, whose folder facet is one of nine). Folder names are matched in their own small table. Needs: Photos' per-asset folders left out of the folder facet, folder search and the Folders panel's counts, as a removed root's folders already are (LIB-10), and a source term (`source:photos`) and album term.
- **Photo lists** (`Lists/PhotoSource.swift`: `.folder(URL, …)`, `.collection`, `.allPhotographs`, …; `packages/RedlampUI/Sources/Library/Collections/LibrarySource.swift`). Needs: a Photos album as a source, and All Photographs holding Photos photos or not (decision 5).
- **Folders and the sidebar** (`packages/RedlampUI/Sources/Sidebar/AppKit/FolderOutlineView.swift`, `SidebarOutlineView.swift`; `Library/LibraryFolderList.swift`, which lists folders the index doesn't have from the disk; `Model/FolderLibrary+Watching.swift`, FSEvents on each root). Needs: an Apple Photos section listing albums, always from the index, never from the disk, and the Photos root left out of Folders and the watchers.
- **What the UI calls a photo.** `PhotoAddress` (`packages/RedlampDocument/Sources/Sidecar+Versions.swift`) is a URL and a version, in 305 lines of 60 files of RedlampUI; `LibraryItem` (`Model/EditorTypes.swift`) has `url`, `folderPath`, `size` and `modified` (which key its thumbnail), and `isLocal`, false for a file iCloud Drive has evicted. Needs: an address that stays a URL (this design) or a new kind of address throughout (MOB-08; decision 11).
- **Thumbnails and previews** (LIB-09, `Store/PhotoStore.swift`, `StoreRecord`, keyed by content key, edit digest, size and date; `packages/RedlampUI/Sources/Library/StoreThumbnails.swift`, whose `StoreThumbnailMaker.ImageSource` makes a missing image from the file; `Library/Grid/GridThumbnails.swift`; `Modules/PhotoPreviews.swift`, which skips a photo that isn't local; `Model/ThumbnailLoader.swift`, packs keyed by path). `decodeThumbnail(for:)` reads the file in 8 files (the loupe's 1:1, Compare, focus peaking in Judging, the editor's preview). Needs: an image source that asks PhotoKit, a key that doesn't need the file's bytes, and a date that changes only when the picture does.
- **The editor's open path** (`Model/EditorModel.swift`, `open(_:keepingSelection:)`): `engine.openIfReady(url)` or `engine.open(url)` (11 calls in 5 files), the sidecar read beside it through `library.sidecars.store(for:)`. Needs: the original made local first, with progress and Cancel, then the same path.
- **Decode** (`packages/RedlampServices/Sources/DecodeService.swift`): `DecodeServiceClient` maps the file (`Data(contentsOf:options: .alwaysMapped)`) and sends its bytes and path over XPC to a service with no file system access ([raw pipeline](../raw-pipeline.md)). The bytes could come from `requestData` directly, but lens profiles, DNG profiles, gain maps, embedded mattes, AF points and Adobe profiles read the file by URL after decoding (15 mapped reads in 10 files). Needs: the original as a file, which is why downloaded originals go to a cache on disk.
- **Sidecars** (`packages/RedlampDocument/Sources/SidecarLocator.swift`, `packages/RedlampLibrary/Sources/Sidecars/LibrarySidecars.swift`): a sidecar is beside the image URL or, for a root kept on this Mac, at `Sidecars/<volume>/<path in volume>/<name>.redlamp`; reads and writes are coordinated (`NSFileCoordinator`) by URL in 38 lines of 28 files. Needs: a root kept on this Mac whose path in its "volume" is the asset's key, and no writing beside the photo, ever.
- **Change detection** (`Changes/ChangeTracker.swift`, `ChangeTracker+Volumes.swift`, `VolumeEventStream.swift`): FSEvents per volume, folder signatures when history is lost. Needs: Photos' persistent changes in its place, and the cache's files ignored.
- **Culling and metadata batches** (`Metadata/LibraryMetadata.swift`, `MetadataBatch.swift`, `Keywords/KeywordBatch.swift`): each photo's change written to its sidecar by URL. Works unchanged once the locator places Photos sidecars.
- **Collections and keywords** (`Collections/CollectionIndex.swift`, membership kept in sidecars by path, LIB-23). Work unchanged; Photos albums are a different thing (below).
- **Stacks and pairs** (`Stacks/StackFinder.swift`, `Health/HealthPairs.swift`): a pair is a raw and a JPEG or HEIC in one folder whose names differ only in extension. A RAW+JPEG asset's two resources in its own folder, named as LIB-54 names them (`ApplePhotosNames.originals`), pair unchanged.
- **XMP sync** (`XMP/LibraryXMP.swift`, `XMPSidecarFiles.swift`: `.xmp` beside the photo, 27 lines in 16 files). Must refuse: there's nowhere to write.
- **Export** (`packages/RedlampUI/Sources/Export/BatchExport.swift`): `beforeExporting(url)`, then `FileManager.default.fileExists(atPath:)` (one of 41 such checks in 26 files) and `engine.open(url)`. Needs: the batch's originals downloaded first, counted in its progress.
- **File operations** (`Files/FilePlanner.swift`, `FileOperations+Move.swift`, `+Rename.swift`, `+Copy.swift`, `+Trash.swift`; `packages/RedlampUI/Sources/Library/Trash/EditorModel+Trash.swift`; Show in Finder in 7 files). Must refuse with a reason, or adapt (Copy becomes Copy to Folder).
- **Library Health** (`Health/HealthChecker+Missing.swift` and the other checks; `Duplicates/DuplicateQueries.swift`, which builds `folder + "/" + name`, one of 81 such joins in 37 files). Missing must come from Photos' deletions, never from an absent cache file; duplicates, damaged files, extensions and pairs apply only to downloaded originals or not at all.
- **Report a Bug** (`packages/RedlampUI/Sources/Feedback/FeedbackContext.swift`, whose Disk comes from the URL's volume; `FeedbackReport.swift`; `FeedbackRedaction.swift`, which redacts folders and photo names). Needs: "Apple Photos" with the original's state as the disk, and asset identifiers redacted as paths are.
- **The CLI's library commands** (`apps/RedlampCLI/Sources/LibraryCommand*.swift`, 25 subcommands taking paths). `redlamp library photos` exists for imports. Needs: albums kept in place, the originals cache, and file commands refusing Photos photos.
- **The regression suite** (`packages/RedlampAutomation/Sources/Scenarios/`, 72 files; `ApplePhotosScenarios.swift` and `ApplePhotosFollowScenarios.swift` on the simulated library). `RedlampAutomationTests` fail when an action or panel has no scenario, so each new action needs one.

## A Photos photo in the library

### Identity and address

- **Its key** is its asset key: the first 16 bytes of SHA-256 over its cloud identifier's archival string, in hexadecimal, or over `local:` and its local identifier while it has no cloud identifier (iCloud Photos off, or not yet synced). Hashing keeps the key safe in a path (cloud identifiers hold colons, local identifiers slashes) and derivable again from the identifier. When a cloud identifier appears, the asset is keyed again: its folder and sidecar move, journaled as Move Edits moves sidecars (LIB-11). MOB-06 should key the iPhone's sidecars the same way.
- **Its address** stays a URL, so `PhotoAddress`, `LibraryItem`, the sidecar locator and the engine keep working: `~/Library/Caches/Redlamp/Apple Photos/System/<asset key>/<name>`, where `<name>` is the resource's original file name. That is also where its original lands when it's downloaded. While it isn't there, `LibraryItem.isLocal` is false, as for a file iCloud Drive has evicted, and every path that reads the file asks for it first (below). Decision 11 weighs this against a new kind of address.
- **What the index adds** (schema 16, a new table and a column; the photos table isn't made again): `roots.kind` (0 a folder, 1 Apple Photos), the Photos root at the address above on a volume named `apple-photos`, with its sidecars on this Mac; and `photo_assets` (photo, local identifier, cloud identifier, asset key, resource kind: original, alternate or Photos' edit, content version, pixel size, media subtypes, the favourite as last read, hidden). The **content version** is `adjustmentTimestamp`, or the creation date for an asset never edited: it changes when the picture changes, not when a favourite or an album does, so thumbnails aren't made again for nothing.
- **Its store key** is derived from the asset key and resource kind, as no bytes are needed; `size` is 0 until the original's size is known and `modified` is the content version. The original's real content key is recorded once it's downloaded, to match copies LIB-54 made.

### How it's listed and indexed

- **Choosing albums.** Add Albums from Apple Photos… (the Folders panel's + menu, File, the palette) shows LIB-54's album tree with counts and no destination. Photos' Library smart album may be chosen, for every photo. Smart albums list what Photos puts in them; shared albums hold reduced copies and are marked so, off by default, as in LIB-54. With limited access the one entry is Photos Chosen for Redlamp.
- **Rows.** The Photos indexer fetches the chosen albums' assets and writes rows in batches of 1,000 through the index's writer, from PhotoKit's fields alone: kind from the resource's type, the date (Photos' own, a changed date included), location, pixel size, the favourite as a pick (decision 8), from macOS 27 rating, caption and keywords. A RAW+JPEG asset gives two rows that pair; an asset edited in Photos gives a third, `<name> (Photos edit).<ext>`, stacked over its original as LIB-54 stacks it, its original on top once it has a Redlamp edit; a burst gives its key photo and picked frames, stacked. Videos and Live Photos' videos are left out and counted on the album's row.
- **Camera, lens and exposure** aren't among `PHAsset`'s properties; only a file (an original, or a derivative that keeps the camera's EXIF) has them. They're read when an original is first downloaded; until then those filters leave the photo out and its Metadata panel says so (decision 10).
- **Sweeps.** A photo that leaves every chosen album leaves the library's lists, as a removed folder's photos do (LIB-10): its sidecar stays, so choosing an album that holds it brings everything back. A Redlamp collection holding it keeps its row.

### Albums, collections and folders

- **A Photos album is a source, not a collection.** Its photos are whatever Photos says, kept in a `photo_albums` table by the Photos indexer, and Redlamp can't change it (DEC-106). The Apple Photos section lists the chosen albums in Photos' folder tree, each with its count, beside Folders. Dropping photos onto an album is refused with the reason.
- **Redlamp's collections** hold Photos photos as they hold any photo, membership kept in the photo's sidecar.
- **All Photographs, searches and smart collections** include Photos photos, with `source:photos` and `source:folders` to tell them apart and a Source facet (decision 5).

### A photo both copied by LIB-54 and in Photos

LIB-54's copies name their asset in `applePhotos`. When an album kept in place holds an asset the library already has as a copy, the copy stands in for it: the album lists the copy's row and no row is made from Photos, so one photo has one edit (decision 9). A photo copied later by Copy to Folder stands in the same way.

As built (LIB-64): a copy is found in `Apple Photos.json` by the asset's local identifier, then by its cloud identifier as Photos gives it, then, for a copy recorded under an identifier this Mac's Photos doesn't have (made on another Mac, or before the library changed), by the cloud identifier Photos reads back, as 0.3.4 recorded `stringValue`'s text; and the copy's sidecar must name the asset as the record does. The index keeps which copy stands in for which asset in `photo_copies` (schema 17), so a copy moved or renamed in Redlamp, keeping its row, still stands in. Rows the asset had from Photos are taken out as a sweep takes them, their sidecars kept, so a copy taken out of the library (Undo Import among the ways) or missing gives the asset its rows back with what Redlamp kept of them, and one put back or found again stands in again. The albums imports follow (LIB-55) leave out those kept in place.

## Viewing and editing under Optimize Mac Storage

- **Before the original arrives.** The grid, the filmstrip and the loupe at fit show Photos' images: the grid tier from `requestImage` at the grid's size with network access off, kept in the store like any thumbnail; the loupe from Photos' largest local image, the preview tier, until the original arrives. An asset whose images Photos can't give without iCloud shows its placeholder with a cloud mark. A photo with a Redlamp edit shows the store's render of its edit (LIB-17), which outlives the original's eviction; one whose edit was never rendered (Sync Settings across photos not downloaded) shows Photos' image with the edited badge and Render waiting for the original in its tooltip.
- **When a download starts.** Opening the photo in Develop; the loupe, Compare or Survey at 1:1; focus peaking in Judging; exporting; Copy to Folder; and Download Originals on a selection. Browsing never downloads (decision 3). While a photo is open in Develop, the next one in the filmstrip's order downloads ahead, unless macOS marks the network as expensive (`NWPath.isExpensive`) (decision 4).
- **Progress and Cancel.** In Develop, the photo shows from its preview with a ring and Downloading from iCloud, 18 of 42 MB, and Cancel, which leaves Develop on the preview, its sliders off, with Download again. In the grid and the filmstrip a cell being downloaded carries a small ring; the toolbar's activity shows the queue (Downloading 3 originals), with Cancel All. Export and Copy to Folder count downloads in their own progress. A download is one `requestData` per resource, written to a partial file in the asset's folder and renamed when complete, so a cancelled or failed one leaves nothing behind.
- **Offline.** A download that fails for want of the network says so on the photo (iCloud can't be reached: this photo's original isn't on this Mac) with Try Again; browsing, culling, keywords and editing metadata go on, and edits to photos already downloaded go on. Export skips what it can't get and names them in its report.
- **The cache** is `~/Library/Caches/Redlamp/Apple Photos/`, on the Mac's own disk, excluded from backups (`URLResourceKey.isExcludedFromBackupKey`). It keeps downloaded originals up to a budget, 20 GB by default, set in Settings › Library › Apple Photos with the space used and Empty Cache, removing the least recently opened first, never the open photo nor one an export or a copy is reading (decision 2). macOS may also purge Caches under pressure; a photo whose file went is simply not local again. `redlamp library photos --originals` reports the cache and `--evict` empties it.

## Where Redlamp's sidecars for these photos live

The sidecar is the same `.redlamp` package as any photo's (edit, history, snapshots, versions, metadata, `applePhotos`), so everything that reads and writes sidecars works on it. The choice is its place (decision 1):

1. **The DEC-43 store on this Mac**, keyed by asset key: `~/Library/Application Support/Redlamp/Library/Sidecars/apple-photos/System/<asset key>/<name>.redlamp`. No new entitlement, works with iCloud Photos off, backed up by Time Machine with the rest of the library; other Macs and the iPhone don't see it.
2. **Redlamp's iCloud Drive container,** as DEC-76 chose for the iPhone: the same layout under the container's `Documents`, so another Mac on the same iCloud Photos library and, later, the iPhone app find the same edits. It needs an iCloud container entitlement and a provisioning profile in both the direct download and the App Store build (neither has one today: `apps/RedlampMac/Redlamp.entitlements` holds only the Photos entitlement), coordination with iCloud Drive's downloads (which `FolderScanner` and `sidecarIsLocal` already handle for folders in iCloud Drive), and a fallback on this Mac while iCloud is off.
3. **Either, with a compact copy in Photos** (EXT-05): on demand, Save to Photos writes the rendered edit and a short adjustment data into Photos, so Photos and other devices show it. It doesn't remove the need for 1 or 2, since Photos keeps one short edit per asset with no history, masks or versions.

Recommended: 1 for the first release, with the layout the container would use, so moving to 2 when MOB-06 starts is Move Edits (LIB-11) between two places, not a new format. EXT-05 stays its own later row.

## File operations

- **Refused, with the reason** ("This photo is in Apple Photos. Redlamp doesn't move, rename or delete photos in Photos."): Move, Rename, Rename Photos…, Move to Trash, Write .xmp and Read .xmp, Move Edits for the Photos root, Locate…, dropping onto a folder (which offers Copy to Folder instead) and dropping onto a Photos album.
- **Adapted:** Show in Finder becomes Show in Photos, which opens Photos (opening Photos at one asset isn't documented, so unverified); Copy becomes Copy to Folder; Remove Version (LIB-48) works, being the sidecar's; Remove from Library on a Photos photo leaves it out of Redlamp's lists until its album is chosen again, nothing changed in Photos.
- **Library Health:** Missing lists photos deleted in Photos (below), with Remove and no Locate…; Damaged and Unreadable apply to downloaded originals that fail to decode; Duplicates, Extensions and Pairs leave Photos photos out.

## Export

Export, Export with Previous and `redlamp export` take Photos photos as any photos: the batch first asks the cache for its originals (in its order, the open photo's first), shows Downloading 4 of 40 from iCloud in its progress, and exports each as it arrives, so the first files appear before the last download ends. Cancel stops both. Exporting doesn't keep originals beyond the cache's budget. Export metadata comes from Redlamp's fields, and the file's own EXIF from the original.

## Following Photos' changes

- **The token.** The Photos indexer keeps `currentChangeToken` in the index's `settings` after each pass. At launch it applies `fetchPersistentChanges(since:)`, then, while Redlamp runs, does the same a moment after each `PHPhotoLibraryChangeObserver` notice (and from macOS 27 on `register(_:)`'s commits). An expired token, or a library that no longer resolves the albums' identifiers, sends it back to comparing the chosen albums whole, as a lost FSEvents history does for folders.
- **New photos** in a chosen album are added as they arrive, no prompt.
- **Changed in Photos:** a new content version brings new thumbnails and previews for the asset's rows; a changed favourite, date, location or (macOS 27) rating, caption or keyword updates the fields that came from Photos and haven't been changed in Redlamp since; an album's membership changes its list.
- **Edited in Photos after Redlamp edited it:** Redlamp's edit is of the original and stays as it is. Photos' new rendering replaces the Photos edit row's images, and the row appears if it wasn't there. Photos' Revert to Original takes the row out (marked Missing if it has a Redlamp edit of its own).
- **Deleted in Photos:** its rows are marked missing (DEC-59) and listed only by Library Health's Missing, their sidecars kept; Remove takes them out. If Photos gives the asset back (Recently Deleted's Recover), the rows return, unverified until the census.
- **Keyed again:** an asset that gains a cloud identifier moves to its new key, journaled.

## Copying (LIB-54) and following (LIB-55)

- **Copy to Folder…** (decision 7) runs LIB-54's import on the selected Photos photos or a Photos album, with Import's destination and templates, and carries each photo's Redlamp sidecar (edits, versions, history, metadata, collections) to its copy, which then stands in for it (decision 9). Undo Import brings the Photos rows back.
- **File › Import from Apple Photos…** becomes Add Albums from Apple Photos…, with Copy into a Folder as a choice on its setup screen that runs the import as shipped.
- **LIB-55** (decision 6): albums kept in place follow Photos by themselves; the Library panel's From Apple Photos and the automatic setting remain only for albums chosen for copying.

## The parts, in order

Each is a proposed tracker row, IDs to be assigned when the owner accepts them.

1. **Photos as a source of the index** (L). Schema 16 (`roots.kind`, `photo_assets`, `photo_albums`); the Photos root, its per-asset folders and its locator root on this Mac; the Photos indexer writing rows from PhotoKit's fields and sweeping what leaves; the folder facet, folder search, Folders' counts, Missing, watchers and the change tracker leaving the Photos root out; `ApplePhotosLibrary` gaining lookups by identifier, content versions, persistent changes and images; `PhotoKitLibrary` on `archivalStringValue`; `redlamp library photos --keep <albums>` and `--list`. Depends on LIB-54.
2. **Thumbnails and previews from PhotoKit** (M). An image source for `StoreThumbnailMaker` that asks PhotoKit at the grid's and the preview's sizes without the network; the derived store key and content version; `PHCachingImageManager` for the visible rows and a margin; the cloud mark; the Photos edit row's images from the `current` version and the original's from `original` where local.
3. **Originals on demand** (L). An originals cache in RedlampLibrary (a queue with priorities, progress, Cancel, partial files, the budget and its eviction, offline errors), and its callers: Develop's open path, the loupe, Compare and Survey at 1:1, Judging's focus peaking, export, Copy to Folder, Download Originals; Develop's ring and Cancel, the cells' rings, the toolbar's queue; reading camera, lens and exposure on first download; Settings › Library › Apple Photos; `--originals` and `--evict`.
4. **Following Photos' changes** (M). The token, launch catch-up and live notices; inserts, updates, deletions, edits in Photos and new keys; recomparing on an expired token.
5. **Apple Photos in the sidebar and the views** (L). The Apple Photos section and album sources; Photos photos in All Photographs, searches and smart collections with `source:` and the Source facet; Add Albums; file operations refused and adapted; Show in Photos; Report a Bug's disk, state and redaction; the harness's states; scenarios for each new action; the manual.
6. **Copy to Folder** (M). LIB-54's import over in-place photos and albums, carrying Redlamp's sidecar, the copy standing in, with Undo. Depends on 1 and 3.
7. **Copies and followed albums beside in-place albums** (S). Copies standing in for their assets; LIB-55 kept for copied albums only.
8. **Favourites followed from Photos** (S). Favourites read as picks when photos are added and when Photos changes them, nothing written (decision 8); EXT-04 later writes picks back.

Rows 1 and 2 make a first release that browses and culls; 3 makes it edit; 4 to 8 complete LIB-57.

## Budgets

On the simulated library at 50,000 assets, and checked on the owner's library by the census:

| | Budget |
| --- | --- |
| Grid scrolling over 50,000 Photos photos | main-thread p99 under 8.3 ms, as for folders |
| A thumbnail the store has | on screen within a frame, as for folders |
| A screenful of thumbnails the store hasn't, from Photos' local images | p95 under 250 ms (to confirm in the census) |
| Adding albums of 50,000 photos | the first 1,000 listed in 1 s, all indexed in 15 s |
| Launch with Photos unchanged | persistent changes applied in under 200 ms, no album fetched whole |
| A change in Photos | in Redlamp's lists within 2 s of the notice |
| The index | about 35 MB more for 50,000 photos (600 bytes a row at a million, LIB-05, plus their folders and asset rows) |
| The store's grid tier | about 1.1 GB at 22 KB a thumbnail, within its budget; previews only as they're shown |
| Develop on a photo not downloaded | its preview at once, the download's progress within 100 ms |
| Memory | within the library's 250 MB browsing budget: fetch results stay lazy |

## Tests

- **The simulated library grows:** each asset's derivatives (made from its fixture file at load, at the grid's and preview's sizes, or named in the manifest), simulated iCloud latency and rate for `inCloud` resources (`"latency": ms`, `"rate": bytes a second`), an `offline` switch, failures after a number of bytes, scripted changes (insert, update, edit, delete, re-key) with change tokens that can expire, limited access, and a generator for 50,000 assets (`redlamp library fixture --photos`).
- **Unit tests** in RedlampLibrary for the asset key and re-keying, the indexer's rows (pairs, edits, bursts, videos left out), sweeps, the cache's budget and eviction, Cancel leaving no partial file, persistent changes and an expired token, and the locator; in RedlampUI for the open path while downloading, export with downloads, each file operation refusing, and Report a Bug's fields.
- **Scenarios** on the simulated library: `library.apple-photos-in-place` (add albums, scroll, cull, keyword, search), `library.apple-photos-download` (Develop with progress, Cancel, offline, Try Again), `library.apple-photos-changes`, `library.apple-photos-copy-to-folder`, `export.apple-photos`; the existing `library.apple-photos` and follow scenarios kept for copying.
- **PhotoKit itself** is compile-checked and then measured by the owner's census (`PhotoKitCensus` in RedlampLibrary, tested end to end on the simulated library), which runs in a Redlamp build on the Mac with his library, in the editor's place (`--photos-census`), from a kit he runs as the perf kit is run (`scripts/photos-census-kit.sh`; a Bench task carries steps to the phone, and this needs none): derivatives kept under Optimize Mac Storage and their sizes, the `original` version's availability for edited assets, EXIF in derivatives, download times and cancelling, whether Photos keeps what it downloaded, the persistent change history over a week, and a deleted and recovered asset's identifier.

## Risks

- **Photos' local images may be smaller than the screen** under Optimize Mac Storage, leaving the loupe soft until the original arrives. The census measures it; the fallback is the loupe's own download on zoom.
- **Disk used twice:** if Photos keeps originals it downloads for Redlamp, the cache doubles them. The census checks the Photos library's size before and after.
- **Photos' daemon under load:** thousands of image requests while scrolling. Requests are cancelled as cells leave, and the store keeps what it got, so each is asked once.
- **Identifier mappings are expensive:** done in batches when albums are added and when changes arrive, never per cell.
- **A switched System Photo Library** gives new local identifiers and an unknown token. It's detected when the chosen albums no longer resolve; the photos are matched again by cloud identifier where the account is the same, and otherwise kept as missing.
- **The path namespace leaking:** a file operation or a check that forgets the Photos root would act on cache files. Each refusal has a test, and the cache's files are never anyone's but the cache's.
- **Edits only on this Mac** (decision 1's first option) are lost with the Mac unless it's backed up; Time Machine covers the library's folder.
- **0.3.4's copies:** photographers who imported by copying get both until decision 9's rule applies; it's applied the first time an album is kept in place.
- **macOS 27's SDK** brings ratings, captions, keywords, `dataSize` and the persistent observer, all behind `#if compiler(>=6.4)` as LIB-54's fields are.

## Decisions for the owner

**Answered (2026-10-27, the owner): A, the recommended option, on all eleven.**

1. **Where do Redlamp's edits and metadata for photos left in Photos live?**
   - A. In Redlamp's store on this Mac, keyed by the photo's iCloud identifier, in the layout iCloud Drive would use. No new entitlement; only this Mac sees them; moved to iCloud Drive with Move Edits when the iPhone app starts.
   - B. In Redlamp's iCloud Drive container from the start (DEC-76). Other Macs see them; needs an iCloud entitlement and profile in both builds, and a fallback while iCloud is off.
   - C. On this Mac, with a compact copy and rendered version written into Photos on demand (EXT-05 brought into this work). Photos shows the edit; each save asks Photos' permission.
   - **Recommended: A.** It ships without new accounts or entitlements, and B stays a move, not a format change.
2. **Are downloaded originals kept, and how much?**
   - A. Kept up to a budget, 20 GB by default, set in Settings, the least recently opened removed first. Reopening is instant for recent work; the space is bounded.
   - B. Released once the photo is closed and its edit rendered. Least disk; every reopening downloads again.
   - C. Kept until emptied by hand. Fastest; can fill the disk Optimize Mac Storage was saving.
   - **Recommended: A.**
3. **Does browsing ever download originals?**
   - A. Never: the grid, filmstrip and loupe at fit show Photos' images; 1:1, Develop, export and copying download, and Download Originals fetches a selection on request.
   - B. Also in the background, for photos whose Redlamp edit waits to be rendered (after Sync Settings), within the cache's budget.
   - C. Every original in the chosen albums, in the background, within the cache's budget.
   - **Recommended: A.** Browsing stays as fast offline as online, and nothing is downloaded that isn't asked for.
4. **While a photo is open in Develop, is the next one's original downloaded ahead?**
   - A. Yes, the next in the filmstrip's order, on networks macOS doesn't mark as expensive. Moving on is usually instant; one extra download at most.
   - B. No: only the photo opened downloads.
   - C. Yes, the next and the previous.
   - **Recommended: A.**
5. **Do Photos photos share All Photographs with folder photos, or have a section of their own?**
   - A. Shared: in All Photographs, searches and smart collections, told apart by `source:` and a Source facet, with the albums in an Apple Photos section beside Folders.
   - B. Separate: only in the Apple Photos section; All Photographs stays the folders'.
   - **Recommended: A,** since it's one library to cull and search.
6. **Does LIB-55's following become the in-place albums?**
   - A. In-place albums follow Photos by themselves; LIB-55's offer and automatic setting remain only for albums chosen for copying.
   - B. LIB-55 retired: only in-place albums follow; copying is one-off.
   - C. Both kept as they are.
   - **Recommended: A.**
7. **What does Copy to Folder mean once in place is the default?**
   - A. It copies the chosen photos' originals into a folder by Import's templates, carrying their Redlamp edits and metadata; the copy then stands in for the Photos photo.
   - B. It stays 0.3.4's import: a separate copy with Photos' metadata only, Redlamp's edits left with the Photos photo.
   - C. A per-album setting that keeps a copy in a folder and copies new photos as they arrive.
   - **Recommended: A.**
8. **Do culling changes go back to Photos in the first release?**
   - A. No: favourites are read as picks, and Photos' changes followed; nothing written to Photos until EXT-04.
   - B. Favourites read once, when photos are added; nothing followed or written.
   - C. Both ways at once: a Pick sets the favourite, with Photos' permission prompt per batch (EXT-04 brought forward).
   - **Recommended: A,** within DEC-106.
9. **A photo copied out by 0.3.4's import is also in an album kept in place. How does it show?**
   - A. The copy stands in: it's listed in the album, and no second photo is made from Photos.
   - B. Both are listed, linked, each with its own edit.
   - C. Redlamp offers to move the copy's edits to the Photos photo and put the copy in the Trash.
   - **Recommended: A.**
10. **Camera, lens and exposure aren't among a Photos asset's properties. How do photos never downloaded get them?**
    - A. Read when an original is first downloaded, and from Photos' local images if the census shows they keep the camera's EXIF; until then those filters leave the photo out.
    - B. A background pass downloads each original once to read them, keeping nothing, on networks that aren't expensive.
    - **Recommended: A.**
11. **How is a photo left in Photos addressed inside Redlamp?**
    - A. As a path in Redlamp's cache folder named for its iCloud identifier, where its original lands when downloaded, so most of the library and editor work unchanged and file operations refuse it.
    - B. As a new kind of address throughout the library and editor (MOB-08 first): cleaner, and a larger change, across 60 files of the UI, before anything ships.
    - **Recommended: A,** with MOB-08 later generalising it.

## Steps

Each step has the ID its todo and the canvas's plan step use.

1. **`canvas`:** the workstream canvas, `ws-apple-photos-in-place`. Done when it shows this plan.
2. **`decisions`:** the owner's answers, recorded here, in DEC-107 and in the tracker as the rows above. Done when each decision has an answer and the rows have IDs.
3. **`census`:** the census of the owner's library, run from its kit on the Mac that has the library: the unverified points above, and the budgets on that library. Done when its results are recorded here and the budgets confirmed or changed.
4. **`source-index`** (row 1): schema 16, the Photos root and indexer, the protocol's additions, the CLI. Done when 50,000 simulated assets index within budget, pairs, edits and bursts list as designed, and the folder views leave the root out.
5. **`thumbnails`** (row 2). Done when the grid scrolls 50,000 simulated Photos photos within budget from Photos' images, with nothing downloaded.
6. **`originals`** (row 3). Done when Develop, 1:1, export and Download Originals download with progress and Cancel on the simulated library's latency, offline is handled, and the cache keeps its budget.
7. **`changes`** (row 4). Done when scripted inserts, edits, deletions, re-keys and an expired token reach the lists within budget.
8. **`sidebar`** (row 5). Done when the Apple Photos section, album sources, file operations' refusals and Report a Bug's fields work in the app on the simulated library, each with its scenario.
9. **`copy`** (rows 6 and 7). Done when Copy to Folder carries a photo's edits and the copy stands in, with Undo, and LIB-55 offers only copied albums.
10. **`favourites`** (row 8). Done when favourites changed in the simulated Photos reach picks.
11. **`docs`:** the README's roadmap, the Lightroom comparison, the manual, the sidecar format (the Photos root's layout) and the tracker. Done when `scripts/roadmap-sync.py` reports nothing.

Step 3 can run beside 4 and 5. Steps 4 and 5 come first; 6 follows 4; 7 follows 4; 8 follows 5 and 6; 9 follows 6; 10 follows 7; 11 comes last. A first release can stop after step 6 and the parts of 8 that show albums.
