# Import from Lightroom Classic: progress, and slow disks: design

File › Import from Lightroom Classic… (LIB-29) works, but while it imports it shows a 140-point bar and one sentence. A photographer whose import ran for hours from a 2.5-inch USB disk asked why it was so slow, and the window couldn't tell them which stage it was in, how fast it was going or whether it had stopped. This design makes the window a screen people can read while it works (LIB-52), and makes the import faster on spinning disks (LIB-53).

**Status (2026-10-16):** on main. The window is a screen people can read while it works (LIB-52): the new screens drawn from the model, with Found's Done row, as the approved wireframes draw them (Decisions below). Left of it: the import's progress in the library toolbar once the window is closed, and an estimate on Review once there's a model per kind of disk. Spinning disks through the whole import (LIB-53) are done: the simulated disk, the indexing fixes and the import's five write fixes (Measurements): sidecars written one folder at a time on a disk that spins, fewer operations per write, the window's poll counted in the index, the import's root folders read first, and the folders it writes held from change detection. On the simulated 2.5-inch disk the import's writes take 0.2 to 0.3 h at 100,000 photos, where they took 0.9 to 1.1 h; a real spinning disk would confirm one reader and the hold. The owner chose to wireframe the whole window, EDT-34's first screen included, and to measure on a simulated spinning disk, as he has none.

## The screen (LIB-52)

The wireframes are a canvas, `lightroom-import-wireframes.canvas.tsx` in the Cursor project's canvases: Found (EDT-34's first screen), Review, Importing, Result, Details and a playground of a simulated import, with the questions left for the owner. In short:

- **Found:** one card each for the catalog, Camera Raw's presets and the Adobe profiles, each imported on its own (EDT-34).
- **Review:** the headline counts, the root folders with Locate… and Allow Access…, a bar per field that comes across with the part that replaces a value the library has, step 9's Edits section as a bar, what stays behind, and Import N Photos.
- **Importing:** a rail of stages; photos done of total in a bar split into the import's parts of 10,000 (Stop ends at the end of a part); the rate and time left from the last minute, shown once steady and replaced by Paused when nothing moves; photos a second over the last ten minutes; done, now and next; each root folder's progress on its disk; notices for Low Power Mode, heat and spinning disks; Stop.
- **Result:** done, stopped, failed and taken back, each saying what the library now holds, with Undo Import.
- **Details:** the timestamped log with Copy, and the report's text as the CLI prints it.

**Decisions (2026-10-16, the owner):** the wireframes approved as drawn, and each question they left open answered with its lean: once the window is closed, the import's progress shows in the library toolbar's activity, a click opening the window; no estimate before the import runs, until LIB-53's measurements give a model per kind of disk that holds up; indexing the new folders is a stage of its own, with its own rate and time left; the chart of photos a second over the last ten minutes stays, pauses marked; the log starts closed and remembers how it was left; Show Imported Photos is left out until the library has a source that lists a set of photos.

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

### Baselines

On the simulated 2.5-inch disk, 16 October: file operations traced on the build Mac and replayed through `usb-2.5` (`FileTrace`, `DiskReplay`, `LightroomDiskBenchTests` on `lib-53/spinning-disks`, 382826b16), projected to 100,000 photos.

- **The import's writes** (2,000 bench photos in folders of 200): 1.7 h on main (16.5 operations a photo, 4.5 reaching the disk, 6,072 moves between folders); 1.0 h with step 9's one write per photo (10 operations, 3 reaching the disk, 3,660 moves); 0.3 h for step 9's writes regrouped one folder at a time (10 moves), which is what writing one folder at a time on a spinning disk would give.
- **Indexing the catalog's new folders** (600 clones of the fixture raws, read as an external disk's two readers read them, each thumbnail's read charged at the raw's preview: ARW 1,150 KB, CR3 458 KB, DNG 186 KB, NEF 701 KB, RAF 2,667 KB): 0.9 h as run; 0.4 h of it the reads the import waits for, and 0.4 h thumbnails, which can follow the import.

So an import of 100,000 photos into new folders on such a disk waits about 2.6 h on main, about 1.9 h with step 9, and about 0.7 h with step 9, thumbnails after the import's reads and writes one folder at a time. Low Power Mode or heat can still stop the indexing outright until the import's folders are read first.

### The indexing fixes

`LightroomDiskBenchTests`' index bench (LIGHTROOM-DISK-INDEX-BENCH), 600 clones of the CC0 raws in folders of 200, its operations replayed through `usb-2.5` and projected to 100,000 photos. *Until the import could start* is the replay up to the indexing's last operation, thumbnails left out; *as run* is every operation in the order they ran. The indexer reads through a volume that answers at once (*external*) or through the 2.5-inch disk simulated in real time (*usb-2.5*), on the build Mac but where it says. Since `spinning` and `usb-2.5` now say their disks spin, anything that reads through either has one reader, where it had two or more; so has an external disk that doesn't say.

| | Until the import could start | Thumbnails | As run | Readers at the end |
|---|---|---|---|---|
| Before (317ab168e), external | 0.75 h | 0.4 h | 0.9 h | 5 |
| Before, usb-2.5 | 0.87 h | 0.4 h | 0.9 h | 5 |
| Thumbnails behind the indexer's reads (e61522fe8), external | 0.44 h | 0.9 h | 1.3 h | 4 |
| The same, usb-2.5 | 0.45 h | 1.0 h | 1.4 h | 7 |
| Spinning disks recognised (3553a897c, on this Mac at a load of 45), usb-2.5 | 0.45 h | 0.7 h | 1.2 h | 1 |
| An import's folders first (86ab44378), external | 0.47 h | 0.7 h | 1.2 h | 1 |
| The same, usb-2.5 | 0.44 h | 0.7 h | 1.1 h | 1 |
| The same, usb-2.5 in Low Power Mode until the folders are indexed, the root read first | 0.45 h | 0.7 h | 1.1 h | 1 |

- The indexing's own operations stay at 1.5 a photo and 0.4 to 0.5 h throughout; the import waits for them alone once thumbnails wait behind them.
- Thumbnails cost more than before because the bench now counts what they read. Before, it charged each one a single read of its preview; now it counts the reads made through the volume: the head again (the decode reads it too, which the bench didn't count before), the preview's first bytes and the preview, 2.7 reads a photo. Read side by side by several readers, each one's reads were apart, each paying a seek (1.0 h); one reader on a disk that spins keeps them together (0.7 h).
- In Low Power Mode the import's folders weren't indexed at all before, the background lane running nothing (`LibraryIndexerTests`: nothing in a second); read first, they're indexed as fast as otherwise.
- On the simulated disk in real time, which counts the Mac's own delays as well, the times swung with the Mac's load: the photos' folders indexed in 21.0 s before (0.97 h), 20.6 s with seven readers, 65.9 s with one at utility priority on a busy build Mac, and 23.7 s with one at user-initiated priority (the root read first). The delay was the simulation's: it waited out each operation with `nanosleep` on the reader's own thread, which macOS lets wake late on a thread at utility priority, as the readers' operations run, to coalesce its timers. A disk's answer wakes a real read, not a timer, so the simulation's waits are now woken by a strict timer at the highest priority (cd9be56e0). On the build Mac a 10 ms wait on a utility thread took 65.9 ms in `nanosleep` and 14.1 ms on the new clock.

The same bench on the build Mac at 07a0de0ee and at 703e40bba (the waits woken when due, and an external disk that doesn't say read as one that spins, 1637d50a1), the 2.5-inch disk saying it spins, not saying, as some USB bridges don't, and saying it's solid state, so it's read by an SSD's readers, which may widen:

| | Until the import could start | Thumbnails | As run | Readers at the end |
|---|---|---|---|---|
| Saying it spins, 07a0de0ee | 0.44 h | 0.7 h | 1.1 h | 1 |
| Not saying, 07a0de0ee: read as an external disk | 0.45 h | 1.0 h | 1.5 h | 9 |
| Not saying, 703e40bba: read as a disk that spins | 0.44 h | 0.7 h | 1.1 h | 1 |
| Saying it's solid state, 703e40bba | 0.44 h | 1.0 h | 1.4 h | 2 |

And on the simulated disk itself, in real time, projected to 100,000 raws:

| | The photos' folders indexed | Thumbnails made by |
|---|---|---|
| `nanosleep` (07a0de0ee): saying it spins, one reader | 114.5 s (5.30 h) | 231.5 s (10.72 h) |
| `nanosleep`: not saying, nine readers | 24.1 s (1.12 h) | 65.1 s (3.01 h) |
| `nanosleep`: one reader, the root read first in Low Power Mode | 28.0 s (1.30 h) | 144.2 s (6.68 h) |
| Woken when due (703e40bba): saying it spins, one reader | 24.2 s (1.12 h) | 47.4 s (2.19 h) |
| Woken when due: not saying, one reader | 20.5 s (0.95 h) | 44.5 s (2.06 h) |
| Woken when due: saying it's solid state, two readers | 20.3 s (0.94 h) | 59.6 s (2.76 h) |
| Woken when due: one reader, the root read first in Low Power Mode | 20.4 s (0.94 h) | 43.9 s (2.03 h) |

- One reader indexes the folders as fast as an SSD's readers once the simulation's waits end when they're due, and makes the thumbnails sooner, its reads of each photo kept together. A real spinning disk would still confirm it.
- An external disk whose device doesn't say whether it spins is now read as one that does, by one reader that never widens, and recorded as `unknown` (1637d50a1): on the 2.5-inch disk behind such a bridge, thumbnails take 0.7 h rather than 1.0 h at 100,000 raws, the wait before the import the same. An external SSD that doesn't say pays for it with one read in flight, where it had two or more; not measured, as the bench has no USB SSD.
- The external row moves from run to run, 0.44 h until the import could start in one run and 1.00 h in another at the same code: a volume that answers at once leaves the readers free whenever the indexer's own work holds it up, and thumbnails take those turns. It stands for an SSD's order of operations, replayed on the 2.5-inch disk.

### The write fixes

`LightroomDiskBenchTests`' write bench (LIGHTROOM-DISK-BENCH) on the build Mac, after `lib-53/spinning-disks` was rebased onto main with step 9 (e27b44558): 2,000 photos in folders of 200, without sidecars or each with one holding an edit made in Redlamp, which the import writes over; their operations replayed through `usb-2.5` and projected to 100,000 photos, as run. From 5c19ba29e the bench tells the import its photos are on the 2.5-inch disk. Each cell gives the hours, the operations a photo, those reaching the disk and the moves between folders; the job is the build Mac's.

| | No sidecars before | A sidecar each before | Job |
|---|---|---|---|
| Before: the rebased head (c07100339) | 0.9 h: 10.0 operations a photo, 3.0 reaching the disk, 2,902 moves between folders | not in the bench yet | 20261016-150044-test-583a268 |
| Before, both kinds of photo (5014e07f6, the bench alone changed) | 1.1 h: 10.0, 3.0, 3,649 moves | 1.1 h: 13.0, 3.0, 3,761 moves | 20261016-152235-test-739360b |
| One folder at a time on a disk that spins or may (5c19ba29e) | 0.2 h: 10.0, 3.0, 26 moves | 0.3 h: 13.0, 3.0, 26 moves | 20261016-152747-test-046ce24 |
| Fewer operations per write (4af452a8d) | 0.2 h: 9.0, 3.0, 26 moves | 0.3 h: 8.0, 3.0, 26 moves | 20261016-153633-test-0feb05a |
| The window's poll counted in the index (d54d749f7) | 0.2 h: 9.0, 3.0, 26 moves | 0.3 h: 8.0, 3.0, 26 moves | 20261016-154049-test-22a8fe8 |
| The import's root folders read first (4514ae499) | not run: it changes no write | | 20261016-154302-test-0d1903e, the window's tests |
| The folders it writes held from change detection (06377e009), change detection following | 0.2 h: 9.0, 3.0, 25 moves, 13 listings of the folders; not held, 0.2 h: 9.0, 3.0, 26 moves, 16 listings | not measured | 20261016-165525-test-a7da735 |

- **One folder at a time.** On a disk that spins, or an external disk that doesn't say (`VolumeIO.maySpin`), each part's sidecars are written one at a time, folder by folder and each folder's photos by name; on an SSD, 8 writers of 64 as before. The import asks the photos' root folders' volumes, through a file system `LightroomImport` is given (`LocalFileSystem` in the app). The order as run varies with the writers' timing, 2,902 moves in one run before and 3,649 in the next, which is why the two rows before differ; regrouped one folder at a time, the same operations took 0.3 to 0.4 h, as the writers' operations within a folder interleaved. At 5c19ba29e the bench's check of the order failed for the disk that doesn't say, which it simulated over the Mac's own SSD; from 4189da70e it simulates it over a file system that doesn't say, and the check passes (20261016-153633-test-0feb05a).
- **Fewer operations per write.** A rewrite looks for unused mask bitmaps (three listings of the package) only when it drops a bitmap the edit had or changes history, and then lists `masks/` first; iCloud Drive's conflicting copies are asked for only where iCloud Drive can be, which isn't a volume mounted in /Volumes but the home folder's; a batch gives each sidecar's date as it wrote it, so the library no longer looks for the sidecar to read its date, and doesn't look the package up twice before writing. The date still takes one look once the write is done, since the file system sets it at the write's last change. The bench's photos are on the build Mac's startup disk, so they keep the conflict check: 7.0 operations a photo with a sidecar each on a disk in /Volumes. The times don't move, since the replay answers these lookups from the Mac's cache; the edits written are the same, byte for byte (RedlampDocument's suite, its golden and schema tests among them).
- **The window's poll** while the catalog's folders are indexed counts the photos under each root folder in the index, kept by root as `indexedRoots`, rather than fetching every photo's ID every 500 ms (d54d749f7). LIGHTROOM-POLL-BENCH, 100,000 photos under one root folder in folders of 200: one poll took 10.8 ms fetching their IDs and takes 1.4 ms counting them in the index (medians of 7, 20261016-154049-test-22a8fe8).
- **The import reads its root folders first** while it waits for them (4514ae499), and stops once they're indexed, stopped or failed. The index bench's last row already reads the root first, so it doesn't move; `LightroomWindowTests` imports a catalog whose other folder is added and indexed in Low Power Mode (12 of 12 of the window's, edits' and undo's tests, 20261016-154302-test-0d1903e).
- **The folders the import writes are held from change detection** until each batch is written (06377e009). Each batch of a volume's events named the folders being written, and `ChangeTracker` listed each again while the import was still writing it. Now `LightroomImport` holds each batch's folders (`ChangeTracker.hold` and `release`, the app's tracker given by `LightroomImportModel`): what the events name in a held folder, or below it, is kept, and once the folder's last hold ends it's listed once, with what the events named below it meanwhile, so a photo someone else adds there is still found; the volume's history isn't recorded past a kept event until then, so a quit during the hold loses nothing (`ChangeTrackerTests`). The write bench's new case, LIGHTROOM-DISK-CHANGES-BENCH, runs the photos without sidecars with change detection following their root through FSEvents on the build Mac, each photo given an empty file so its first pass finds them. There the import writes at the SSD's pace, a folder in a fraction of a second, so the events name each folder once or twice while it's written: 16 listings not held and 13 held, 10 at the holds' ends and 3 for events that came after them, and the time doesn't move. On the 2.5-inch disk a folder of 200 takes about 1.4 s to write (0.2 h for 500 folders), about five of the events' 300 ms batches, so about five listings a folder become one; each listing a folder just written is mostly answered from the Mac's cache, so the time it saves wants a real disk to measure.

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
