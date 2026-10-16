# Import from Lightroom Classic: progress, and slow disks: design

File › Import from Lightroom Classic… (LIB-29) works, but while it imports it shows a 140-point bar and one sentence. A photographer whose import ran for hours from a 2.5-inch USB disk asked why it was so slow, and the window couldn't tell them which stage it was in, how fast it was going or whether it had stopped. This design makes the window a screen people can read while it works (LIB-52), and makes the import faster on spinning disks (LIB-53).

**Status (2026-10-16):** the wireframes are drawn and wait on the owner's review; the rows are accepted; the simulated disk and its baselines are built on `lib-53/spinning-disks` (Measurements), and the indexing fixes are next. The window and the model are being changed today by EDT-23's step 9 (one sidecar write per photo, `edt-23/catalog-edits`) and EDT-34 (the window's first screen, `edt-34/import-window`), so what touches them waits until those land. The owner chose to wireframe the whole window, EDT-34's first screen included, and to measure on a simulated spinning disk, as he has none.

## The screen (LIB-52)

The wireframes are a canvas, `lightroom-import-wireframes.canvas.tsx` in the Cursor project's canvases: Found (EDT-34's first screen), Review, Importing, Result, Details and a playground of a simulated import, with the questions left for the owner. In short:

- **Found:** one card each for the catalog, Camera Raw's presets and the Adobe profiles, each imported on its own (EDT-34).
- **Review:** the headline counts, the root folders with Locate… and Allow Access…, a bar per field that comes across with the part that replaces a value the library has, step 9's Edits section as a bar, what stays behind, and Import N Photos.
- **Importing:** a rail of stages; photos done of total in a bar split into the import's parts of 10,000 (Stop ends at the end of a part); the rate and time left from the last minute, shown once steady and replaced by Paused when nothing moves; photos a second over the last ten minutes; done, now and next; each root folder's progress on its disk; notices for Low Power Mode, heat and spinning disks; Stop.
- **Result:** done, stopped, failed and taken back, each saying what the library now holds, with Undo Import.
- **Details:** the timestamped log with Copy, and the report's text as the CLI prints it.

**How it's built.** SwiftUI hosted in the AppKit window (`NSHostingView`, ending in `.focusEffectDisabled()`), drawn from a value describing the screen, `LightroomImportScreen`, which the model fills in the app and the harness fills with made-up values. Import, Stop and Undo Import stay AppKit buttons in the window's bottom bar, since the `library.lightroom` scenario clicks `lightroom.import` and `lightroom.undo` with the mouse through the view tree. The bars, the stage rail and the throughput chart are small components in `packages/RedlampUI/Sources/DesignSystem/`, drawn with the theme's tokens; the design system has no progress components today. The harness gets `library-lightroom-states`, every state side by side from made-up values as `export-states` does, beside the live `library-lightroom` scene. The window stays within the 700-point height of CI's screen.

## Why the import is slow on a spinning disk

Two stages touch the photos' disk: indexing the catalog's folders the library doesn't have, then writing each photo's sidecar beside it. From reading the code on main (276611202) and step 9's branch:

1. **Each sidecar is written twice,** once for its keywords and once for its other fields. Step 9 writes it once (`dd2015abe`), with the edit; it lands with EDT-23.
2. **Thumbnails compete with the reads the import waits for.** The indexer reads each photo's first 256 KB through the volume's readers, two at a time on an external disk (`VolumeIO.initialWidth`). Thumbnails go to the scheduler's background lane as each batch commits, one per performance core, outside that limit (`LibraryIndexer+Batches.swift`, `LibraryIndexer.scheduler`), each mapping the raw and decoding its embedded preview. On one disk head the two pull the head between files. The import doesn't need thumbnails to start.
3. **The import's indexing can stop without the window saying so.** Its folders aren't prioritised, so their photos are read on the background lane (`LibraryIndexer+Photos.swift`), which starts nothing in Low Power Mode, when the Mac is hot, or while on-screen work waits, rechecking every 2 s (`WorkScheduler.pump`). The window's count doesn't move.
4. **Spinning disks aren't recognised.** LIB-07 promises one or two readers in folder order on them, but `kind(of:)` gives only `ssd`, `unknown` and `network`; the schema's `spinning` is never written. `VolumeConcurrency` also probes a third reader from time to time.
5. **Writes jump between folders.** Sidecar batches write with 8 workers of 64 photos each, 512 photos apart (`SidecarStore.batchWidth`): right for an SSD, the worst order for one head.
6. **Each write does more than it needs:** three listings of the package for unused mask bitmaps on every rewrite (`Sidecar.removeUnusedBitmaps`), an iCloud conflict check on volumes that aren't iCloud Drive, and a stat for a date the write already knows. Change detection then lists each written folder again after every batch.
7. **Smaller costs.** The 500 ms poll while folders are indexed fetches every photo ID in them to count them (`LightroomImportModel.waitForIndexing`); CR3 and HEIF files get up to 16 small reads each for Library Health's end checks after indexing; CR3, RAF, IIQ, SRW and some NEF need a second read for their metadata. With Settings' writing of `.xmp` for other apps turned on (off by default), each photo gets a third pass and an `.xmp`.

What's not slow: the plan and the report read only the index and the catalog (2.45 s at 100,000 photos); the journals and the index live on the Mac's own disk; nothing is fsynced per photo.

## Measuring on a simulated disk (LIB-53)

`VolumeProfile.spinning` already models one head: operations take turns, moving to another file costs a seek (8 ms) and bytes move at 160 MB/s (`SimulatedFileSystem`, `VolumeModel.schedule`). Only what goes through `LibraryFileSystem` sees it, which is the indexer's reads, change detection and file operations; thumbnails and sidecar writes don't.

- Thumbnail reads and sidecar file operations are charged to the simulated volume in benches, through a hook in `SidecarStore` (RedlampDocument) that RedlampLibrary's simulation fills.
- A `usb-2.5` profile: about 12 ms to seek and 5.5 ms of rotation, about 100 MB/s, one operation at a time. `spinning` stays as it is, so earlier results stay comparable.
- A virtual clock, so thousands of photos take seconds, and each photo's operations counted by kind, with how often the head moves to another folder.
- A `lightroom` bench scenario: a catalog's folders indexed, then the import, with each stage's simulated time projected to 100,000 photos; recorded on main and on step 9's branch, then after each fix.

It compares one way of working with another; it doesn't stand for a real disk. APFS's metadata flushing, the drive's own cache and USB bridges aren't modelled.

## Order

1. The wireframes, the owner's review and EDT-34's agent briefed to build its first screen to them.
2. The simulated disk and its baselines, which touch nothing being changed today.
3. The screens in the harness, in files of their own.
4. The indexing fixes: the import's folders first and their pauses said, thumbnails off the disk while the import waits, spinning disks recognised and read one at a time in folder order.
5. Once step 9 lands: the write fixes. Once step 9 and EDT-34 land: the window shows the new screens, and the scenario and tests follow.

## Measurements

On the simulated 2.5-inch disk, 16 October: file operations traced on the build Mac and replayed through `usb-2.5` (`FileTrace`, `DiskReplay`, `LightroomDiskBenchTests` on `lib-53/spinning-disks`, 531ff5fcb), projected to 100,000 photos.

- **The import's writes** (2,000 bench photos in folders of 200): 1.7 h on main (16.5 operations a photo, 4.5 reaching the disk, 6,072 moves between folders); 1.0 h with step 9's one write per photo (10 operations, 3 reaching the disk, 3,660 moves); 0.3 h for step 9's writes regrouped one folder at a time (10 moves), which is what writing one folder at a time on a spinning disk would give.
- **Indexing the catalog's new folders** (600 clones of the fixture raws, read as an external disk's two readers read them, each thumbnail's read charged at the raw's preview: ARW 1,150 KB, CR3 458 KB, DNG 186 KB, NEF 701 KB, RAF 2,667 KB): 0.9 h as run; 0.4 h of it the reads the import waits for, and 0.4 h thumbnails, which can follow the import.

So an import of 100,000 photos into new folders on such a disk waits about 2.6 h on main, about 1.9 h with step 9, and about 0.7 h with step 9, thumbnails after the import's reads and writes one folder at a time. Low Power Mode or heat can still stop the indexing outright until the import's folders are read first.

## Reply to the report

For the owner to send where the report came from:

> Thank you for telling us, and sorry it took so long. We looked into it. A Lightroom import does two things on the disk your photos are on: it first indexes the catalog's folders that Redlamp didn't have yet, then writes Lightroom's ratings, keywords and other fields into a small file beside each photo. Both were built and measured on SSDs, and on a 2.5-inch spinning disk they do more back-and-forth than they need: thumbnails are made at the same time as the indexing, each photo's file is written twice, and writes go to several folders at once. The indexing also pauses while the Mac is in Low Power Mode without saying so. We're fixing these, and redesigning the import window so it shows which stage it's in, how fast it's going and how long is left.
>
> To be sure we fix what you saw, could you tell us:
>
> 1. What the window said while it was slow: "Adding the catalog's folders: … photos indexed" or "Importing: … of … photos"?
> 2. About how many photos the catalog has, and the camera or file type of most of them (CR3, NEF, ARW, JPEG…)?
> 3. How the disk is formatted, which Disk Utility shows (APFS, Mac OS Extended or ExFAT)?
> 4. Whether the Mac was on battery or in Low Power Mode at the time?
> 5. Whether Settings › Library has "Write .xmp sidecars for other apps" turned on?
