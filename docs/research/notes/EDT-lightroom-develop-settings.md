# Lightroom Classic's Develop settings in a catalog (EDT-23)

What Redlamp reads of the edits in a Lightroom Classic catalog (`.lrcat`), where each fact comes from, and what stays unverified until a catalog made in Lightroom can be checked. Written on 15 October 2026 for the census (`redlamp library lightroom <catalog> --census`, step 2 of the [Lightroom edits design](../../plans/2026-10-13-lightroom-edits-design.md)) and the catalog reading the import of edits will share. Every source below was read that day.

As DEC-51 requires, the format is learnt from published sources and from catalogs Redlamp makes itself, never from Adobe's code. There is no catalog made in Lightroom to check against yet (the design's step 3 waits for one), so the tests use catalogs written from this note (`LightroomCatalogMaker`, `LightroomSettingsText`), and everything below about what Lightroom writes is unverified unless it says otherwise.

## Summary

- **A photo's edit is a Lua table** in `Adobe_imageDevelopSettings.text`: `s = { Exposure2012 = 0.35, CameraProfile = "Adobe Standard", … }`. Its keys are Camera Raw's setting names, the ones Lightroom writes to XMP as `crs:` properties ([E1]). `LuaTable` reads the text as data and never runs it.
- **The catalog reader reads it in parts while the catalog is open.** For each photo and virtual copy it reads the settings' text, the row's `processVersion` and `digest`, Lightroom's rotation code, the file's size, the snapshots and the number of history steps. A catalog with a `-wal` log is read from a temporary copy, deleted once everything has been read.
- **The census counts what the edits use** and names no photo, path, keyword or value: process versions, settings, mask components, spots, profiles and looks, Upright's modes, snapshots and history steps, and each rotation code with the EXIF orientations of the files the library has.
- **Not yet verified:** the tables' columns, that the text is always plain Lua, the vocabulary of mask and spot kinds, which settings Lightroom writes for a photo, and what the rotation codes mean. The census of a real catalog settles several of these, the rotation codes first.

## Sources

| | Source | What it gives |
| --- | --- | --- |
| [E1] | ExifTool, [XMP Tag Names, the crs table and its structures](https://exiftool.org/TagNames/XMP.html) | Setting names and types; the Correction, CorrectionMask, CorrRangeMask, RetouchArea and Look structures; `PerspectiveUpright`'s values; `WhiteBalance`'s values |
| [A1] | Adobe, [Lightroom Classic: tone and color](https://helpx.adobe.com/lightroom-classic/help/image-tone-color.html) | The profile groups: Adobe Raw (Adobe Color the default for raws, Adobe Monochrome for black and white), Camera Matching, Adaptive, and the creative Artistic, B&W, Modern and Vintage |
| [L1] | LIB-29's reader, `packages/RedlampLibrary/Sources/Migration/` | The catalog as an SQLite database; its tables for folders, files and images; opening it immutable or from a copy |
| [D1] | The [Lightroom edits design](../../plans/2026-10-13-lightroom-edits-design.md) | The Lua form, Lightroom 11's masks against the earlier one-shape corrections, what the import needs of each photo |

ExifTool's names are facts about the XMP form; the catalog's Lua form uses the same names ([D1]). Adobe's help names profile groups, not every profile.

## What's read from the catalog

Every table and column is looked up before it's read. A catalog that lacks one is still read, and the census's notes say what was missing and what didn't come from it.

| Table | Columns | Read for |
| --- | --- | --- |
| `Adobe_images`, joined to `AgLibraryFile` by `rootFile` | `id_local`, `masterImage`, `orientation`, `fileWidth`, `fileHeight` | Each photo and virtual copy (a row whose `masterImage` names another image is a virtual copy of it), Lightroom's rotation code as text, and the file's size in pixels. A size is read only when both columns are there |
| `Adobe_imageDevelopSettings` | `id_local`, `image`, `text`, `processVersion`, `digest` | The settings. Should an image have more than one row, the last written (the highest `id_local`) is read |
| `Adobe_imageDevelopSettings` | `hasDevelopAdjustmentsEx`, else `hasDevelopAdjustments` | How many photos Lightroom marks as adjusted, as LIB-29 counts them |
| `Adobe_libraryImageDevelopSnapshot` | `id_local`, `image`, `id_global`, `snapshotID`, `name`, `text`, `digest` | Each image's snapshots, in the order they were made |
| `Adobe_libraryImageDevelopHistoryStep` | `image` | How many history steps each image has. The steps' own settings aren't read |
| `Adobe_variablesTable` | `Adobe_DBVersion` | The catalog's version |
| `AgLibraryRootFolder`, `AgLibraryFolder`, `AgLibraryFile` | As LIB-29 reads them | Finding each photo's file in the library, to pair rotation codes with EXIF orientations |

A virtual copy has its own row in `Adobe_imageDevelopSettings`, keyed by its own image. Its rotation code pairs with its photo's file, since it has none of its own.

**Virtual copies as versions.** The import brings each virtual copy of a photo it finds as a version of the photo (EDT-09), named by its `Adobe_images.copyName` (Create Version's next name when that's empty), its edit converted from its own settings and snapshots with its photo's file for the context, and its provenance naming the copy's own `id_local`. Its fields are read as LIB-29 reads a photo's, from rows keyed by the copy's own image: its `rating`, `pick` and `colorLabels` in its `Adobe_images` row, its caption, copyright and title in `AgLibraryIPTC`, its title, creator, location and caption in `Adobe_AdditionalMetadata`'s XMP, its keywords in `AgLibraryKeywordImage` and its collections in `AgLibraryCollectionImage`, the Quick Collection giving its mark. A photo Redlamp has edited already keeps its edit and gets Lightroom's as a version named "Lightroom Classic". Before the report, the sidecars of the photos Redlamp has edited and of those with virtual copies are read for edits whose provenance names this catalog and the same image: those came across before, and are left as they are.

**How it's read.** The rows that say which settings, snapshots and history belong to each image are read first; then each image's text is fetched by its row's `id_local`, 500 images to a part. Each part goes to `make` on every core while the next is read, so only the parts in flight are in memory: at 4.7 KB a photo, about 2 MB a part. The import of edits gets the same records (`LightroomCatalog.Develop`, with `Snapshot`) through `LightroomCatalogReader.develop`, inside `LightroomCatalog.opened`, which keeps the copy of a catalog with a log until its reading returns.

## The Lua form

Lightroom writes each photo's settings as one assignment: `s = { name = value, … }`. Values are numbers, quoted strings, `true` and `false`, and tables. A list of numbers (`ToneCurvePV2012 = { 0, 0, 255, 255 }`) is a curve's x, y pairs written flat. A structure (`Look = { Name = "Adobe Color", Amount = 1, … }`) is a table with names, and an array of structures (`MaskGroupBasedCorrections = { { … }, { … } }`) is a list of them. The form comes from [D1]; how Lightroom spaces, orders and escapes it is unverified, and the reader takes any spacing, order, comments and Lua's string escapes. ExifTool gives the look's `Group` as localised text; the tests write it as a table keyed by language (`{ ["x-default"] = "Profiles" }`), an assumption the census doesn't depend on.

## The settings the census looks into

| Setting | Form ([E1]) | Counted as |
| --- | --- | --- |
| `ProcessVersion` | string: `11.0`, `6.7` | Photos by its value; the row's `processVersion` when the settings lack it |
| `CameraProfile` | string | Photos by profile, named when it's Adobe's or camera-matching |
| `Look` | structure: `Name`, `Amount`, `Cluster`, `Copyright`, `Group`, `Parameters`, `SupportsAmount`, `SupportsMonochrome`, `SupportsOutputReferred`, `UUID` | Photos by `Name`, as profiles are named |
| `PerspectiveUpright` | integer: 0 Off, 1 Auto, 2 Full, 3 Level, 4 Vertical, 5 Guided | Photos by mode |
| `MaskGroupBasedCorrections` | array of Correction: `What`, `CorrectionActive`, `CorrectionAmount`, `CorrectionName`, `CorrectionMasks`, `CorrectionRangeMask`, `CorrectionSyncID` and the `Local…` sliders | Masks and the photos with any; each mask's own settings |
| `CorrectionMasks` | array of CorrectionMask: `What`, `MaskSubType`, `MaskName`, `MaskActive`, `MaskBlendMode`, `MaskInverted`, `MaskValue`, `Masks`, `CorrectionRangeMask`, and the shape's fields (`ZeroX`, `ZeroY`, `FullX`, `FullY`; `Top`, `Left`, `Bottom`, `Right`, `Angle`, `Midpoint`, `Roundness`, `Feather`, `Flipped`; `Dabs`, `Radius`, `Flow`) | Components by `What`, with `MaskSubType` and the range mask's `Type` where they're written; a component inside another's `Masks` with the outer one's `What` |
| `CorrectionRangeMask` (ExifTool's `CorrRangeMask`) | structure: `Type`, `SampleType`, `LumMin`, `LumMax`, `LumFeather`, `LumRange`, `ColorAmount`, `AreaModels`, `DepthMin`, `DepthMax`, `DepthFeather`, `Invert`, `Version` | The `Type` beside the component's or earlier correction's kind |
| `GradientBasedCorrections`, `CircularGradientBasedCorrections`, `PaintBasedCorrections` | arrays of Correction, one shape each (Lightroom 10 and earlier, [D1]) | Corrections by array, with a range mask's `Type` where one is written |
| `RetouchAreas` | array of RetouchArea: `SpotType`, `Method`, `Masks` (CorrectionMasks), `Feather`, `Opacity`, `Seed`, `SourceState`, `SourceX`, `OffsetY` | Spots by `SpotType`, `Method` and their masks' `What` |
| `RetouchInfo` | list of strings | Spots by the `spotType` each string names |

Every other top-level key is counted as a setting: the photos carrying it and, of those, the ones whose value isn't the one most of them have.

## What the census names, and how it counts

- **Named:** setting names when they're Lua names (letters, digits and underscores, up to 64 bytes); the kinds, subtypes and methods of masks and spots when they're up to 40 bytes of letters, digits, spaces and `/ . _ - + &`; process versions of the form `11.0`; rotation codes of up to 8 letters or digits; Upright's modes as numbers; the catalog's version. A profile or look is named when it's one of Adobe's (Adobe Standard, Color, Monochrome, Landscape, Neutral, Portrait, Vivid and the Adaptive ones; the creative groups' `Artistic 01` form; `ACR 4.4`; `Embedded`) or begins `Camera ` ([A1]'s Camera Matching group, `Camera Standard`, `Camera PROVIA/Standard`). Anything else is `other`, since a photographer's own profile can name a client, and something missing is `none`.
- **Never named:** a photo, folder, path, keyword, title, a mask's or snapshot's name, a virtual copy's name, any setting's value.
- **Changed:** a setting's value counts as changed when it isn't the value most of the photos carrying the setting have. In a catalog of any size that value is Lightroom's default, so the census needn't know the defaults; it would undercount a setting only if most photos carrying it had the same non-default value. A setting whose values all differ, as masks' do, has no such value, and every photo carrying it counts as changed. A mask's own settings are counted the same way over the masks. Only photos carrying a setting are counted: a photo that lacks it is neither.
- **Settings that can't be read** (text that isn't a Lua table) are counted, and the photo's other counts (rotation, snapshots, history) still are.
- **Speed:** 100,000 photos and 5,000 virtual copies, their settings 4.7 KB each on average and a tenth with masks, counted and paired with the index in 1.17 s on the build Mac (M4 Max, 16 cores, 15 October 2026), against a budget of about 4.9 s for the report with edits (twice LIB-29's 2.45 s).

## Rotation codes

`Adobe_images.orientation` holds Lightroom's code for how a photo is turned and flipped, as text. What the codes mean isn't published. The census pairs each code with the EXIF orientation (1 to 8) the library's index holds for the photo's file (`PhotoRecord.orientation`, read with ImageIO when the file is indexed), for the photos the index has, found by path as LIB-29's plan finds them. A real catalog's census therefore says which code goes with which camera orientation, and the codes that differ from it are Lightroom's rotations and flips. The tests use `AB`, `BC`, `CD`, `DA` and `BA` as placeholders, not as Lightroom's codes.

## Unverified until a catalog made in Lightroom is checked

- The four tables' columns and types beyond those LIB-29 reads, and whether Lightroom indexes their `image` columns: counting history steps reads the table's `image` column, which is quick with an index and a whole scan of the table without one.
- That `text` is always plain Lua. The XMP the catalog keeps can be zlib-compressed behind a 4-byte length ([L1]); settings stored that way would count as unreadable, which the census would show.
- One row of settings per image, and that a virtual copy's settings are keyed by its own image.
- That a virtual copy's IPTC fields, XMP, keywords and collections are keyed by its own image, and that it shares its photo's `rootFile`; the tests' catalogs give a copy a file row of its own with its photo's name.
- Whether Lightroom writes every setting for a photo or only some; the census's "changed" relies on the most common value being the default.
- The values of `What`, `MaskSubType`, the range mask's `Type`, `SpotType` and `Method`. The census counts whatever is stored; the tests use `Mask/Gradient`, `Mask/CircularGradient`, `Mask/Paint`, `Mask/Image`, `Mask/RangeMask`, `Mask/Ellipse`, `heal` and `clone`.
- Whether the range mask is written `CorrectionRangeMask` (the specification's name, [E1]) or `CorrRangeMask` (ExifTool's), and whether a component's `Masks` holds one structure or a list: both are read.
- The form of `RetouchInfo`'s strings: [E1] says only that it's a list of strings. The census reads `spotType = …` from each as a comma-separated list of `name = value`, an assumption no published source or file made for Redlamp confirms; a string of another form counts as a spot of kind `none`.
- Which `ProcessVersion` values Process 2003, 2010 and 2012 write.
- Whether `fileWidth` and `fileHeight` are the stored pixels or the oriented ones, and whether Lightroom updates them.
- Every profile name in Adobe's groups: [A1] names the groups, so the census names Adobe's by the list and forms above, and counts any other Adobe profile as `other`.
- What each rotation code means: the census of a real catalog settles it.

## Running the census

On a catalog Lightroom has closed, or a copy of one, with Redlamp closed so the library's index is quiet:

```bash
redlamp library lightroom ~/Pictures/Lightroom/"Lightroom Catalog.lrcat" --census
redlamp library lightroom ~/Pictures/Lightroom/"Lightroom Catalog.lrcat" --census --json > census.json
```

Without `--index` it pairs the rotation codes with the app's own library when there is one; `--root <lightroom folder>=<folder>` finds a root folder that has moved, as the report does. It writes nothing.
