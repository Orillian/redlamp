# Versions in the library (LIB-48): design

Versions are Lightroom Classic's virtual copies ([Lightroom edits](2026-10-13-lightroom-edits-design.md#virtual-copies-as-versions-edt-09-lib-48), decision 2): another edit of the same file, kept in the file's sidecar (`versions` in [the sidecar format](../recipes/sidecar-format.md#versions)), which the library shows as a photo of its own, with its own rating, flag, label, keywords, title, caption and collections. This note says how the index keeps them, what that costs at two million photos, how a version gets an identity of its own in the library's UI, where a photo is known today by its file's URL, which a version shares, and how the rest of LIB-48 (#399) is done.

## A row for each version

Built in fe06cca00. Each version is a row of `photos` beside its file's own:

- **Its place.** The file's `folder` and `name`, and `version`, the version's UUID, empty for the file's own row. A row is unique by the three (`photos_place`), in place of the table's `UNIQUE (folder, name)`. Empty rather than NULL, which a unique index takes as distinct.
- **The file's fields** are the file's own row's: kind, size, dates, file identifier, content key, the capture time with the photo's shift and zone (a version's metadata doesn't hold them), camera, lens and exposure, pixel size and orientation, GPS, the sidecar's and the `.xmp`'s dates and the state (missing, offline, settling, unreadable). `carryFile(of:)` copies them onto the versions' rows whenever the indexer writes the file's.
- **Its own fields:** rating, flag, label or custom label with its colour, mark, title, caption, creator, copyright, location, stack, whether it's edited, its keywords, collections, text and edit record (`photo_edits`), each by its own row ID. Other apps' files give it nothing: what they hold is the file's own metadata, which the XMP sync reads and writes.
- **Rows follow the sidecar.** Whenever the indexer reads a photo's sidecar, its versions' rows are made to match the versions `SidecarStore.summary(for:)` lists: kept under their IDs, written again, added and removed, and the library told so (`photosInserted`, `photosUpdated`, `photosRemoved`). A photo without a readable sidecar has none. An index rebuilt from the sidecars gets them back.
- **Lookups by place** (`photo(folder:name:)`, `photo(path:)`, by file identifier, by content key, a folder's photos for the indexer's listing) give the file's own row; `versions(folder:name:)` and `versions(inFolder:)` give its versions, and `fileRow(of:)` the file's own row of any of its rows. Lists of rows (All Photographs, a folder's or a collection's photos, searches) hold versions with the rest, since they're rows.
- **What changes the file changes all its rows:** a move or rename through any of them, parking a name while photos swap names, a relink, missing and found, the file identifier and the sidecar's date. Removing the file's own row removes its versions'; a version's row alone goes when the version leaves the sidecar.

Two other keys were ruled out: a table of versions apart from `photos` (every list and query would need a union with it), and names with a hidden suffix (they'd leak into what's shown, sorting, naming templates and file operations).

## The migration, measured

SQLite can't drop a table's own `UNIQUE`, so schema version 15 makes `photos` again: a new table with every column as the old one has it, and `version`; every row copied under its ID, which the text index, keywords, collections, hashes, health and edit records name; the old table dropped and the new one renamed; its indexes and the view made again from their SQL. It runs in one transaction when the index opens, as every migration does.

At two million photos (`IndexVersionsBenchTests`: an index of version 14 configured as the app's, one photo in seven with a sidecar, a title and a caption, 397 MB; on the build Mac, an M4 Max, quiet at a load of about 2.6, job `20261026-124925`, in the tests' Debug build; 4.28 s at a load of about 14 on 16 October, job `20261016-143828-test-e4b0daa`):

| | Measured |
| --- | --- |
| The migration | 3.22 s |
| The index file after it | 709 MB, from 397 MB: the old table's pages stay in the file, free, and are used again as it grows |
| Its log before the checkpoint | 398 MB |
| `quick_check` after it | 0.53 s, ok |
| The new unique index alone | made in 0.44 s, dropped in 0.01 s |

Nothing can search while it runs, as with schema version 7's text index, the one migration before it that rewrote every row (5.7 and 9.6 s at a million photos, on the M1 Ultra under load). A migration that kept the table would cost about the unique index alone, 0.6 s: `ALTER TABLE ADD COLUMN`, then the table's SQL edited in `sqlite_schema` under `PRAGMA writable_schema` to take out its `UNIQUE`, the automatic index made an ordinary one and dropped, and the new one made. SQLite documents editing `sqlite_schema` for changes that leave the file's contents as they are, such as constraints and defaults; this one also changes an index's kind, which it doesn't list.

The owner chose the rebuild, as built, on 26 October: it's SQLite's own procedure for a change a table can't take in place, and 3.2 to 4.3 s once, at the first launch of 0.3.4 on a library of two million photos, is within what version 7 took at half that size.

## The index's timings with versions

`IndexBenchmarkTests` at two million photos, without versions and with a version of every tenth photo (`REDLAMP_INDEX_BENCH_VERSIONS=10`: 200,000 versions, each edited and rated, a third with a keyword, written as the indexer writes them); on the build Mac, quiet, in the tests' Debug build, the first at a load of about 2.1 (job `20261026-125711`), the second at about 2.8 (`20261026-125254`). On 16 October, at loads of 14 to 87, the same runs took 27.6 and 23.4 s to insert and 33.0 s to write the versions (jobs `20261016-144045-test-116effb` and `20261016-144449-test-46d3944`).

| Two million photos | Without versions | With 200,000 versions |
| --- | --- | --- |
| Inserting the photos, in batches of 1,000 | 20.6 s, 97,313 a second | 19.3 s, 103,839 a second |
| Writing the versions, as the indexer does | | 14.6 s, 13,697 a second |
| The index file | 546 MB | 623 MB |
| A full scan of the hot columns | 463 and 457 ms | 514 and 512 ms |
| A photo by path | 6.7 µs | 6.3 µs |
| By file identifier on a volume | 5.7 µs | 5.7 µs |
| By content key (no index, as designed) | 70.9 ms | 78.2 ms |
| The photos under one year's folder | 13.3 ms (100,000) | 14.7 ms (110,000) |
| A trigram search for 4 characters of names | 0.23 ms (600 names) | 0.24 ms (640, versions sharing their files' names) |
| `count(*)` of rating ≥ 3 and one camera | 78.4 ms | 86.3 ms |
| Rating 10,000 photos, consecutive and spread | 21.1 and 45.3 ms | 21.3 and 46.6 ms |
| `quick_check` | 1.68 s | 1.82 s |
| A snapshot (`VACUUM INTO`) | 0.65 s, 536 MB | 0.75 s, 609 MB |

Lookups by place are unchanged; the rest grows about as the rows do, a tenth. Writing a version costs about 73 µs, its lookups, its row and its keywords: an import of 10,000 virtual copies takes about 0.7 s of index writes, and an index rebuilt from sidecars holding 200,000 versions about 15 s more than the 2,642 s the index build took at two million.

`QueryMillionTests` at two million rows, on the base commit (`bcfaaf904`, before versions) and on this branch, and at 2,200,000 rows, which is two million photos with a version of every tenth to the column store (jobs `20261016-151416-test-bcfaaf9`, `20261016-145152-test-0cdfaad` and `20261016-151427-test-e17cd57`, at loads of 9 to 65), two runs each:

| | Budget | Base, 2,000,000 | Branch, 2,000,000 | Branch, 2,200,000 |
| --- | --- | --- | --- | --- |
| First page and count, p95 | under 16 ms | 6.22 and 6.17 ms | 6.77 and 6.58 ms | 6.89 and 7.50 ms |
| Every photo in order, p95 | | 12.57 and 12.72 ms | 13.96 and 12.89 ms | 13.85 and 14.45 ms |
| Facet counts, p95 | under 100 ms | 185 and 188 ms | 187 and 183 ms | 214 and 217 ms |
| The column store | | 92.4 bytes a photo | 92.4 bytes a photo | 92.4 bytes a photo |

On 26 October, on the quiet build Mac (loads of about 2.6, in the tests' Debug build), the branch again at two million rows (job `20261026-130047`) and at 2,200,000 (`20261026-144919`), two runs each:

| | Budget | Branch, 2,000,000 | Branch, 2,200,000 |
| --- | --- | --- | --- |
| First page and count, p95 | under 16 ms | 6.13 and 6.43 ms | 6.32 and 6.52 ms |
| Every photo in order, p95 | | 12.17 and 12.78 ms | 12.83 and 12.91 ms |
| Facet counts, p95 | under 100 ms | 183.6 and 181.6 ms | 197.1 and 196.5 ms |
| The column store | | 92.4 bytes a photo | 92.4 bytes a photo |

Search holds its budget with versions. Facets miss theirs at two million rows on the base as on the branch: the facets by folder, over 10,000 folders, take 210 to 420 ms a pass under load, and the slowest passes of the quiet runs at 2,200,000 rows, 212 to 219 ms, are all by folder, with a few passes of 3 to 5 s under load on both. That miss predates versions; this bench hadn't been run at two million before (the design's two-million facets, p95 7.9 ms, are `redlamp library bench`'s over lib-2m's 43 queries, in a Release build). Versions add a tenth to it, as they add a tenth of the rows. LIB-56 takes it up: the folder facet scans its whole column on every pass.

## An identity of its own in the library's UI

Today the grid, the filmstrip, selections, thumbnails, culling and Develop's open photo know a photo by its file's URL: `LibraryItem.id` is its URL, `FolderLibrary.positions` and `PhotoPaths` find a row from a URL, `SelectedPhotos` hands actions URLs, `ThumbnailLoader` keys an image by URL, edit and size, culling's steps list URLs, and `EditorModel.selection` is a URL. A version shares its file's URL, so each would find the file's own row for it, or one of its versions.

**What identifies a version: both, each where it serves.**

- **The index row's ID** for what lists, selects, counts and follows changes: `PhotoList`, selections' bitsets, `FolderLibrary.photoIDs`, `LibraryDiff`, the column store. They go by ID already for the library's sources, so lists, selections, filters, search and smart collections take a version's row as they take any photo's.
- **`PhotoAddress`**, the file's URL and the version's UUID (nil for the file's own edit), for what reads or writes the file or its sidecar: Develop's open photo, a thumbnail's render, saves, the library's metadata writes, export, Copy and Paste, Settings Sync. EDT-09 addresses edits so (`EditorModel.select(PhotoAddress)`, `openPhoto`). The row gives it: its folder, name and `version`.

What changes, type by type:

| Type | Today | With versions |
| --- | --- | --- |
| `LibraryItem` | `id` is its URL | gains `version: UUID?` and the version's name, for its badge; `id` becomes its `PhotoAddress`; `url` stays the file's |
| `FolderLibrary` | `positions: [URL: Int]`, `index(of: URL)`, `photoID(of: URL)`, `url(ofPhoto:)` | `positions` and `index(of:)` by address, `index(of: URL)` meaning the file's own row; `address(ofPhoto:)` beside `url(ofPhoto:)` |
| `PhotoPaths`, a large source's rows by place | name to ID, by folder | the same for files' own rows, and a second table, of versions' rows only, by folder, name and version |
| `LibrarySourceList.Read` and the reads of a source's rows | folder, name and fields | `version` and the version's name too |
| A folder the library hasn't indexed, listed from the disk | items from the listing, badges from sidecar probes | a photo's versions inserted after it, as a diff, once its sidecar's summary is read (`SidecarSummary.versions`) |
| `SelectedPhotos` | URLs | addresses: actions on files (move, rename, trash, Show in Finder, the XMP sync) take each file once, actions on edits and metadata (rate, flag, label, keywords, paste, sync, export) each address |
| `ThumbnailLoader` | keyed by URL, edit digest and size | unchanged: rows of one file with the same edit show the same image, and a version with its own edit has its own digest; `protected` and `promote` take the addresses' URLs |
| `EditRenders` (LIB-17) | renders a URL's edit | renders an address's edit (`sidecar[edit: version]`), recorded under the row's ID in `photo_edits`, as now |
| The grid and the filmstrip | cells by row; menus and drags by URL | cells by row, as now; a version's cell has a badge, as Lightroom's page curl, and its name in the tooltip; menus act on addresses; a drag carries each file's URL once |
| Culling | steps list URLs | steps list addresses |
| Develop's open photo | `EditorModel.selection: URL` | the library's active photo is a row ID (`FolderLibrary.activePhoto`, as now), which Develop opens by its address through `select(PhotoAddress)`; `selection` stays the file's URL, which the engine decodes once for all the file's versions |

**What it costs at two million photos.** Lists and selections cost nothing more: a version is an ID. The column store gains one bit, the packed organising field's last free one (bit 15; rating, flag, label, mark, edited and five detail bits take the others), so Copy Status takes no memory and one mask in the column pass. A `LibraryItem` gains 17 bytes and a name, for rows read only (`LibraryItems` reads a large source's rows as they're asked for). `PhotoPaths`'s second table holds versions only. Turning a selection into addresses reads folder, name and version for each ID, a batch at a time off the main thread, as `SelectedPhotos` reads URLs now.

## The rest of LIB-48

Built, each with its tests:

- **Copy Status** (614968249): `version:yes` and `version:no` in the query language, as `edited:` and `marked:` are, from the column store's packed field's last free bit (bit 15) and from `p.version` in SQL; smart collections take it as any term, and their editor names the field Version.
- **Duplicates (LIB-39)** (3dea248ff): candidates are the files' own rows; a version shares its file's content key and is never a copy of it.
- **The XMP metadata sync (LIB-24)** (3dea248ff) takes a version's row for its file and writes the file's own metadata, never a version's.
- **Library Health (LIB-40)** (3dea248ff): its Missing and Damaged checks list each file once, by its own row, and its pairs are of files; a version given to them stands for its file.
- **Move Edits and Metadata's count (LIB-11)** (3dea248ff) counts files, from `photos_sidecars` less `photos_versions`, an index of versions' rows by folder that schema 15 makes before the rows are copied.
- **File operations (LIB-26)** (bfb5e19e9): move, copy, rename, trash, Remove from Library and relink take a version's row for its file, each file once; the journal keeps each file's versions' rows (`IndexedPhoto.version`), so Undo, Put Back and undoing a relink bring them back under their IDs once their file is back; a copy gets rows of its own for its file's versions, which its copied sidecar holds; Recently Trashed lists files; the library hears of the versions whose rows went where their files did.
- **Metadata and keyword batches and their Undo** (df3df9904) write a version's fields in its own edit (`sidecar[edit: version]`), never the file's, one write a sidecar for a file and its versions; the keys that describe the file go to the file's own metadata, and a capture time changed through a version is its file's, which its versions' rows show. A batch holds the files' own rows of its versions while it runs, so the indexer doesn't write a version's row over it.

- **Stacks (LIB-28)** (fb038a50d): in a found pair each file is followed by its versions, the raw's own row on top, as Lightroom stacks a virtual copy with its master; a file with versions and no pair makes a pair's stack with them; versions are never frames of a burst or a focus suggestion; a stack made by hand that takes a file takes its versions. A found pair holding versions starts open, as found bursts do, a pair that gains versions opens, and one the person closed stays closed (b5a047410), as the owner chose on 26 October.
- **A version's name in the index** (c7eacba65): `version_name`, written from the sidecar's summary with the version's row, for the grid's badge and tooltip and the Metadata panel, as Lightroom's Copy Name. A `copyname:` term isn't built.
- **The UI's items and lookups** (ab7f58005): `LibraryItem` has its `version` and the version's name, and its `id` is its `PhotoAddress`; a source's rows read both, `PhotoPaths` keeps versions' rows in a table of their own, and `FolderLibrary.index(of: PhotoAddress)` and `address(ofPhoto:)` find them. The library's sources (its panel's entries, collections, smart collections, search) and folders large enough to be listed as they are (`LibraryFolderList.Large`) list versions. A smaller folder's own list (`LibraryFolderList.Mapping`) lists them too since 7479aed6a (below).
- **The filter bar's Attribute row** (bbbe086d8): Originals and Versions, two symbols after the kinds of file, as Lightroom's Kind has Master Photos and Virtual Copies, writing `version:no` and `version:yes`.

- **Culling by address** (b7e6493fb): culling's steps, their Undo and Redo, the background writes and a culling problem's photos are `PhotoAddress`es, and `LibraryService.cull` finds a version's own row, so rating, flagging or labelling a version changes only its row and its edit; a cell's stars, flag, mark, label and menu, Auto Advance and Develop's culling act on the version.
- **Rows follow the library's writes** (17cbd8701): a catalog import's virtual copies, a batch finished or rolled back after a forced quit, Undo Import and Develop's saves make, change or remove versions' rows.
- **Naming (LIB-25)** (36babadec): a naming preview and a rename name each file once, its versions standing for it.
- **Clicks and Develop** (bca7dbc2f, 92382b42d, 9188146bc): a click selects a version's own row, plain, ⌘ and ⇧, in stacks and groups, in the grid and the filmstrip; the filmstrip's menu culls its cell's version; Develop switches to the row chosen in Library, ← and → stepping through a photo's versions, and opens a version known from the start, so its placeholder, badges and first frame are its own and a rating given while it opens reaches it.
- **A version's badge** (73aa7e7a1): a copy mark on its cell in the grid and the filmstrip, as Lightroom's page curl marks a virtual copy, and its tooltip and accessibility name, "Copy 1, a version of B.JPG".
- **Folders' own lists** (7479aed6a, 63f20c62e, b6fb6fb06, 014e494b0): a smaller folder's own list shows each version after its file; a version made, renamed or removed in Develop comes, changes and goes there, the new one becoming the active cell; a folder listed from the disk, before the index has it, shows each photo's versions from its sidecar's summary (`SidecarSummary.versions`), follows the disk and Develop's saves, and keeps them in place when the library's list takes over; a rename or move takes a file's versions with it at once, and Undo brings them back.
- **Move to Trash on a version** (5bd985239, 9fe643ced): a version selected without its file leaves its sidecar alone, its file and other versions staying, in the step that takes files to the Trash, and Library's Undo puts it back under its ID with its edit, snapshots and history, as the owner chose on 26 October; in Develop with a version open, Move to Trash removes that version and opens the photo's own edit.
- **Selections, Copy, Paste, Sync and export** (cee0d2c3e, ccca4de2a, 8920624e4, 9fe643ced): selections hand actions addresses, actions on files taking each file once; Copy, Paste, Sync, Auto Sync, Update AI Masks, mask presets and Remove Dust reach each version's own edit, one sidecar write a file, with Undo; batch export exports each version with its own edit, metadata and name; the filmstrip's menu on a version's cell copies from and pastes onto that version.
- **Thumbnails and read-ahead** (f1ee2eb2d, 62750e0f8, b07cbdee4, 6ce2c63a2): a version's thumbnails and previews render its own edit, recorded under its own row, rows of one file with one edit sharing a render, the active version first; the grid's, the filmstrip's and held arrow keys' read-ahead go by address.
- **Compare and Survey** (33ad7efe1): a version beside its file, or two versions of one file, each show their own edit, name, rating, flag and label; choosing the select and the candidate, swapping them, culling and Survey's × act on the photo itself.
- **Renaming a version in Library** (f7c440f31, 9d232cbd9): the Metadata panel's Copy Name field, as Lightroom Classic renames a virtual copy, hidden for a file's own row, and Photo › Versions › Rename Version…, each one step on Library's Undo; Library's panels find a version's row by its address in a folder's own list.
- **The scenario** (1006cf878): `library.versions`, through the user's own input: a version made in Develop with Create Version, culled and keyworded alone in the grid, filtered by Copy Status, renamed in Library, moved with its file to another folder and back with Undo, and opened in Develop from the grid.
- **Library's panels on the active version** (80e4d3403): with a version the active photo, Edit Capture Time sets its file's time, which the version shares, and the Photo panel shows the version's own rating, flag and label.
- **Keywords and collections on a version** (22b4e60ef): a keyword dropped or painted on a version's cell, Add to Collection, B on the target collection and a drag onto a collection reach the version's own row and its edit, in the library's sources and in a folder's own list; Move to Trash on a version selected in a folder's own list takes that version alone.
- **Stacks and groups in a folder's own list** (f67156249, 099173560): rows are found by address, so a version is in its file's pair and its group as itself, and moves in its open stack as itself.
- **Develop's saves** (c9325cbdd): a batch on any row of the file Develop has open, a version's too, saves Develop's photo first and waits for its saves, in a large source as in a small one.
- **Missing photos in no pair** (14044d781): a photo whose name the stacks' names leave out, a missing one, is in no pair, as before versions; with the pair key fb038a50d gave files that aren't raws, JPEGs or HEICs, a folder's missing photos had made one closed pair, so in Missing Photos a click on one selected them all with the first active, and Locate… relinked the first.

Still to do:

- **Facets at two million rows** (LIB-56): the facet counts' p95 is 182 to 197 ms against 100 ms at two to 2.2 million rows, as before versions, from the folder facet scanning its whole column on every pass.
- **A version put back in a folder listed from the disk:** Undo of Move to Trash puts it after its file's other versions rather than in its old place, as the library's own list does until it's listed again.
- **A filtered list holding a file's versions without its own row:** a rename or move shows them moved when the library's list brings them, a moment later, rather than at once.
- **Selections kept by file:** a view kept as it's left (`LibraryViewState.SourceView`) and a file step's Undo (`LibraryFileStep.selected`), a move's or Move to Trash's, find their photos by path, so a version selected comes back selected as its file.
- **Dragging a version with its file** carries the file's URL twice; what a drop onto a folder does with it isn't checked.
- **Suggested focus stacks** are marked by URL in the grid and the filmstrip, so a frame's version is marked too, though versions are never frames; scroll positions (`filmstripPlace`, the grid's `topPhoto`, `selectionIndex`) are URLs, so a version's place lands on its file.
- **A large source's selection** is grouped by file a batch of 256 rows at a time, so a file whose rows fall in two batches is written twice, each edit once.
- **Undo Import from Lightroom Classic** leaves a photo with one of its versions open in Develop alone (`changeFromLightroom`), where Undo of Convert Lightroom Edits puts back its own edit; the owner chose on 26 October to give it Convert's rule after LIB-48 (EDT-23).
- Not tried in the app by hand: versions in the grid, the filmstrip, Compare and Survey, the Copy Name row's layout, Tab order and VoiceOver, the Versions submenu in Library.

## The owner's answers (26 October)

1. **The migration:** made again, as built (3.22 s once at two million photos on a quiet Mac), rather than changed in place through `writable_schema`.
2. **How a version's stack starts:** open, as Lightroom shows a virtual copy beside its master, until the person closes it.
3. **A version alone moved to the Trash:** only that version is removed, through EDT-09's Remove Version, as Lightroom's Remove on a virtual copy; the Trash takes files.
