# Versions in the library (LIB-48): design

Versions are Lightroom Classic's virtual copies ([Lightroom edits](2026-10-13-lightroom-edits-design.md#virtual-copies-as-versions-edt-09-lib-48), decision 2): another edit of the same file, kept in the file's sidecar (`versions` in [the sidecar format](../recipes/sidecar-format.md#versions)), which the library shows as a photo of its own, with its own rating, flag, label, keywords, title, caption and collections. This note says how the index keeps them, what that costs at two million photos, how a version gets an identity of its own in the library's UI, where a photo is known today by its file's URL, which a version shares, and how the rest of LIB-48 (#399) is done.

## A row for each version

Built in 66f1e2469. Each version is a row of `photos` beside its file's own:

- **Its place.** The file's `folder` and `name`, and `version`, the version's UUID, empty for the file's own row. A row is unique by the three (`photos_place`), in place of the table's `UNIQUE (folder, name)`. Empty rather than NULL, which a unique index takes as distinct.
- **The file's fields** are the file's own row's: kind, size, dates, file identifier, content key, the capture time with the photo's shift and zone (a version's metadata doesn't hold them), camera, lens and exposure, pixel size and orientation, GPS, the sidecar's and the `.xmp`'s dates and the state (missing, offline, settling, unreadable). `carryFile(of:)` copies them onto the versions' rows whenever the indexer writes the file's.
- **Its own fields:** rating, flag, label or custom label with its colour, mark, title, caption, creator, copyright, location, stack, whether it's edited, its keywords, collections, text and edit record (`photo_edits`), each by its own row ID. Other apps' files give it nothing: what they hold is the file's own metadata, which the XMP sync reads and writes.
- **Rows follow the sidecar.** Whenever the indexer reads a photo's sidecar, its versions' rows are made to match the versions `SidecarStore.summary(for:)` lists: kept under their IDs, written again, added and removed, and the library told so (`photosInserted`, `photosUpdated`, `photosRemoved`). A photo without a readable sidecar has none. An index rebuilt from the sidecars gets them back.
- **Lookups by place** (`photo(folder:name:)`, `photo(path:)`, by file identifier, by content key, a folder's photos for the indexer's listing) give the file's own row; `versions(folder:name:)` and `versions(inFolder:)` give its versions, and `fileRow(of:)` the file's own row of any of its rows. Lists of rows (All Photographs, a folder's or a collection's photos, searches) hold versions with the rest, since they're rows.
- **What changes the file changes all its rows:** a move or rename through any of them, parking a name while photos swap names, a relink, missing and found, the file identifier and the sidecar's date. Removing the file's own row removes its versions'; a version's row alone goes when the version leaves the sidecar.

Two other keys were ruled out: a table of versions apart from `photos` (every list and query would need a union with it), and names with a hidden suffix (they'd leak into what's shown, sorting, naming templates and file operations).

## The migration, measured

SQLite can't drop a table's own `UNIQUE`, so schema version 15 makes `photos` again: a new table with every column as the old one has it, and `version`; every row copied under its ID, which the text index, keywords, collections, hashes, health and edit records name; the old table dropped and the new one renamed; its indexes and the view made again from their SQL. It runs in one transaction when the index opens, as every migration does.

At two million photos (`IndexVersionsBenchTests`: an index of version 14 configured as the app's, one photo in seven with a sidecar, a title and a caption, 397 MB; on the build Mac, an M4 Max, at a load of about 14, job `20261016-143828-test-e4b0daa`):

| | Measured |
| --- | --- |
| The migration | 4.28 s |
| The index file after it | 709 MB, from 397 MB: the old table's pages stay in the file, free, and are used again as it grows |
| Its log before the checkpoint | 398 MB |
| `quick_check` after it | 0.68 s, ok |
| The new unique index alone | made in 0.57 s, dropped in 0.02 s |

Nothing can search while it runs, as with schema version 7's text index, the one migration before it that rewrote every row (5.7 and 9.6 s at a million photos, on the M1 Ultra under load). A migration that kept the table would cost about the unique index alone, 0.6 s: `ALTER TABLE ADD COLUMN`, then the table's SQL edited in `sqlite_schema` under `PRAGMA writable_schema` to take out its `UNIQUE`, the automatic index made an ordinary one and dropped, and the new one made. SQLite documents editing `sqlite_schema` for changes that leave the file's contents as they are, such as constraints and defaults; this one also changes an index's kind, which it doesn't list.

Lean: the rebuild, as built. It's SQLite's own procedure for a change a table can't take in place, and 4.3 s once, at the first launch of 0.3.4 on a library of two million photos, is within what version 7 took at half that size. The owner decides (below).

## The index's timings with versions

`IndexBenchmarkTests` at two million photos, without versions and with a version of every tenth photo (`REDLAMP_INDEX_BENCH_VERSIONS=10`: 200,000 versions, each edited and rated, a third with a keyword, written as the indexer writes them); on the build Mac, the first at a load of 14 to 87 (job `20261016-144045-test-116effb`), the second at 14 to 65 (`20261016-144449-test-46d3944`):

| Two million photos | Without versions | With 200,000 versions |
| --- | --- | --- |
| Inserting the photos, in batches of 1,000 | 27.6 s, 72,368 a second | 23.4 s, 85,328 a second |
| Writing the versions, as the indexer does | | 33.0 s, 6,067 a second |
| The index file | 544 MB | 617 MB |
| A full scan of the hot columns | 470 and 463 ms | 528 and 529 ms |
| A photo by path | 6.6 µs | 6.5 µs |
| By file identifier on a volume | 5.7 µs | 5.7 µs |
| By content key (no index, as designed) | 75.8 ms | 84.5 ms |
| The photos under one year's folder | 13.3 ms (100,000) | 14.7 ms (110,000) |
| A trigram search for 4 characters of names | 0.23 ms (600 names) | 0.24 ms (640, versions sharing their files' names) |
| `count(*)` of rating ≥ 3 and one camera | 79.5 ms | 89.8 ms |
| Rating 10,000 photos, consecutive and spread | 19.7 and 49.3 ms | 22.3 and 66.6 ms |
| `quick_check` | 1.68 s | 1.84 s |
| A snapshot (`VACUUM INTO`) | 0.68 s, 534 MB | 0.78 s, 603 MB |

Lookups by place are unchanged; the rest grows about as the rows do, a tenth. Writing a version costs about 165 µs, its lookups, its row and its keywords: an import of 10,000 virtual copies takes about 1.6 s of index writes, and an index rebuilt from sidecars holding 200,000 versions about 33 s more than the 2,642 s the index build took at two million.

`QueryMillionTests` at two million rows, on the base commit (`bcfaaf904`, before versions) and on this branch, and at 2,200,000 rows, which is two million photos with a version of every tenth to the column store (jobs `20261016-151416-test-bcfaaf9`, `20261016-145152-test-0cdfaad` and `20261016-151427-test-e17cd57`, at loads of 9 to 65), two runs each:

| | Budget | Base, 2,000,000 | Branch, 2,000,000 | Branch, 2,200,000 |
| --- | --- | --- | --- | --- |
| First page and count, p95 | under 16 ms | 6.22 and 6.17 ms | 6.77 and 6.58 ms | 6.89 and 7.50 ms |
| Every photo in order, p95 | | 12.57 and 12.72 ms | 13.96 and 12.89 ms | 13.85 and 14.45 ms |
| Facet counts, p95 | under 100 ms | 185 and 188 ms | 187 and 183 ms | 214 and 217 ms |
| The column store | | 92.4 bytes a photo | 92.4 bytes a photo | 92.4 bytes a photo |

Search holds its budget with versions. Facets miss theirs at two million rows on the base as on the branch: the facets by folder, over 10,000 folders, take 210 to 420 ms a pass, with a few passes of 3 to 5 s under load on both. That miss predates versions; this bench hadn't been run at two million before (the design's two-million facets, p95 7.9 ms, are `redlamp library bench`'s over lib-2m's 43 queries). Versions add a tenth to it, as they add a tenth of the rows.

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

- **Copy Status** (76380f1d9): `version:yes` and `version:no` in the query language, as `edited:` and `marked:` are, from the column store's packed field's last free bit (bit 15) and from `p.version` in SQL; smart collections take it as any term, and their editor names the field Version.
- **Duplicates (LIB-39)** (42e8d53d4): candidates are the files' own rows; a version shares its file's content key and is never a copy of it.
- **The XMP metadata sync (LIB-24)** (42e8d53d4) takes a version's row for its file and writes the file's own metadata, never a version's.
- **Library Health (LIB-40)** (42e8d53d4): its Missing and Damaged checks list each file once, by its own row, and its pairs are of files; a version given to them stands for its file.
- **Move Edits and Metadata's count (LIB-11)** (42e8d53d4) counts files, from `photos_sidecars` less `photos_versions`, an index of versions' rows by folder that schema 15 makes before the rows are copied.
- **File operations (LIB-26)** (075971c22): move, copy, rename, trash, Remove from Library and relink take a version's row for its file, each file once; the journal keeps each file's versions' rows (`IndexedPhoto.version`), so Undo, Put Back and undoing a relink bring them back under their IDs once their file is back; a copy gets rows of its own for its file's versions, which its copied sidecar holds; Recently Trashed lists files; the library hears of the versions whose rows went where their files did.
- **Metadata and keyword batches and their Undo** (c76a824d5) write a version's fields in its own edit (`sidecar[edit: version]`), never the file's, one write a sidecar for a file and its versions; the keys that describe the file go to the file's own metadata, and a capture time changed through a version is its file's, which its versions' rows show. A batch holds the files' own rows of its versions while it runs, so the indexer doesn't write a version's row over it.

Still to do, in this order:

- **The filter bar's Attribute row:** Originals and Versions, as Lightroom's Kind has Master Photos and Virtual Copies, writing `version:no` and `version:yes` as Edited writes `edited:` (`FilterAttributes`, `toggleEdited` beside it).
- **A version's name in the index:** `version_name`, a column added with no row rewritten, written from the sidecar's summary with the version's row, for the grid's badge and tooltip, the Metadata panel and a `copyname:` term, as Lightroom's Copy Name.
- **The UI identity** above, opening a version in Develop through EDT-09's `EditorModel.select(PhotoAddress)`.
- **Stacks (LIB-28):** a file's versions as a found stack with its own row on top, as Lightroom stacks a virtual copy with its master; a stack made by hand that holds the file's own row takes its versions too.
- **Naming (LIB-25):** a naming preview names each file once; `NamingJob` is EDT-09's to change for `{version}`, and `planRename` already takes a version's rename for its file's.
- **The scenario** (`library.versions`): a photo with versions in the grid, rated and keyworded one by one through the grid's own keys and menus, filtered by Copy Status, moved to another folder and back with Undo, and opened in Develop by its version.

## For the owner

1. **The migration:** made again, 4.3 s once at two million photos, as built; or changed in place, 0.6 s, through `writable_schema`. Lean: made again.
2. **How a version's stack starts:** open, as Lightroom shows a virtual copy beside its master; DEC-64 says how each kind of stack starts.
3. **A version alone moved to the Trash:** Lightroom's Remove on a virtual copy removes the copy, never the file. Lean: the same here, through EDT-09's Remove Version; the Trash takes files.
