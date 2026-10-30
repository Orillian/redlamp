+++
deck = "Add the albums you choose from Apple Photos to the library, kept where they are in Photos or copied into your own folders. Kept in Photos, they're shown from Photos' own thumbnails, each original is downloaded from iCloud only when you need it, and your culling and edits stay on this Mac. Photos is only read."
sources = [
  "`docs/manual/facts/files.md`: Apple Photos, §A1 to §A18",
  "`packages/RedlampUI/Sources/Library/ApplePhotos/ApplePhotosWindowController.swift`, `ApplePhotosScreen.swift`, `ApplePhotosViews.swift`, `ApplePhotosImportModel.swift` (Add Albums from Apple Photos: the access pages, the way, the albums, Add Albums, Review, the progress and the result)",
  "`Library/ApplePhotos/EditorModel+KeptInPhotos.swift`, `EditorModel+CopyToFolder.swift`, `ApplePhotosCopyWindowController.swift`, `ApplePhotosCopyModel.swift` (what's refused, Remove from Library, Copy to Folder)",
  "`Sidebar/AppKit/SourcePanels.swift`, `ApplePhotosRowViews.swift`, `SourceOutlineView.swift`; `Library/Collections/LibrarySources+ApplePhotos.swift` (the Apple Photos section, its menus and From Apple Photos)",
  "`Model/EditorModel+Originals.swift`, `Editor/OriginalDownloadStatus.swift`, `Filmstrip/FilmstripView.swift`, `Export/ExportSheetSections.swift`, `Settings/LibrarySettings.swift`; `packages/RedlampLibrary/Sources/ApplePhotos/ApplePhotosOriginals.swift`, `ApplePhotosPlace.swift` (originals from iCloud, where they and the edits are kept, the budget)",
  "`packages/RedlampLibrary/Sources/ApplePhotos/ApplePhotosIndexer.swift`, `ApplePhotosIndexer+Changes.swift`, `ApplePhotosIndexer+Copies.swift`, `ApplePhotosLibrary.swift`, `PhotoKitLibrary.swift` (what's listed, favourites, Photos' changes, copies standing in, limited access)",
  "`packages/RedlampLibrary/Sources/Query/LibraryQuery.swift`, `QueryEngine+Columns.swift`; `Library/Collections/SmartRules.swift` (source: and the Source column); `Library/Health/EditorModel+Missing.swift`, `packages/RedlampLibrary/Sources/Health/HealthCheck.swift` (Missing Photos)",
  "`apps/RedlampMac/Sources/AppCommands.swift`, `apps/RedlampMac/Project.swift`, `Shortcuts/ShortcutAction.swift`, `CommandPalette/ShortcutAction+Palette.swift` (menus, titles, palette words and the usage string); `apps/RedlampCLI/Sources/LibraryCommand+Photos.swift` (`redlamp library photos`)",
  "`docs/lightroom-comparison.md`: Apple Photos albums used where they are",
]
+++

File › Add Albums from Apple Photos… brings the albums you choose from your Photos library into Redlamp's library, in one of two ways. **Keep in Photos**, the way the window starts with, copies nothing: the albums appear in an Apple Photos section of their own beside Folders, their photos are shown from Photos' own thumbnails and previews, and an original is downloaded from iCloud only when you look at it at full size, edit it or export it. You cull, keyword and edit those photos as any other, and Redlamp keeps all of that on this Mac. **Copy into a Folder** copies the albums' photos into folders of your own instead, as an import, each album becoming a collection.

Either way, Redlamp only reads your Photos library. It never adds, changes, moves or deletes anything there, and nothing you do in Redlamp goes back to Photos.

::: lightroom
Lightroom has no way to use Apple Photos albums where they are, as Keep in Photos does: it brings photos in by copying them.
:::

## Adding albums

Choose File › Add Albums from Apple Photos…, or find it in the command palette by a word such as albums, keep, photos or icloud. It has no keyboard shortcut to start with. In the Library panel, Folders' **+** is a menu of Add Folder… and Add Albums from Apple Photos…, and the Apple Photos section's **+** opens the window too. It's a window of its own, Add Albums from Apple Photos.

1. Choose Add Albums from Apple Photos… from the File menu.
2. Leave Keep in Photos chosen at the top of the right-hand column.
3. Tick the albums to add, or a folder to add every album in it.
4. Click Add Albums, or press [[Return]].

The window closes, and the grid shows the first album you chose, its photos appearing as Photos gives them. The Apple Photos section lists the albums, described under [](#files.apple-photos.the-apple-photos-section), and from then on Redlamp follows what changes in them, as [](#files.apple-photos.when-photos-changes) describes.

### Allowing Redlamp to read Photos

macOS asks once whether Redlamp may read Photos. The first time, the window explains why under Allow Redlamp to read Photos: click Continue, and macOS asks, saying that Redlamp shows or copies the photos in the albums you choose and never changes your Photos library. Allow it, and the window reads Photos' albums.

If Redlamp can't read Photos, the window says why, and Open System Settings opens Privacy & Security › Photos, where Redlamp's access is changed. The window reads Redlamp's access again when you come back to it.

Redlamp isn't allowed to read Photos
: Access to Photos was turned off for Redlamp. Turn Redlamp on in System Settings › Privacy & Security › Photos.

Photos is restricted on this Mac
: A profile or Screen Time keeps apps from reading Photos. Whoever manages the Mac can allow it there.

When Redlamp has limited access, to only the photos chosen for it, the window opens on its albums all the same, with one entry, described under [](#files.apple-photos.limited-access).

### Keep in Photos or Copy into a Folder

The control at the top of the right-hand column chooses the way. Keep in Photos is chosen each time the window opens, and the column below it says what keeping does: nothing is copied, the albums appear in the Apple Photos section, and they follow Photos. Copy into a Folder shows To in its place, where the copies go, and runs the import described under [](#files.apple-photos.copying-albums-into-a-folder). Each way remembers its own albums ticked, so you can switch between them until you add or review.

### The albums

The albums are on the left, under From, in Photos' order. Each shows Photos' estimate of the photos it holds. A folder's albums are indented beneath it, and its count is theirs together.

Albums
: Your albums and Photos' folders. A folder's box ticks every album in it, however deep, and shows a dash while only some are ticked. Added with all its albums ticked, a folder is kept as a folder, so an album you later make in it in Photos is kept too.

In Library
: An album you've kept already is dimmed, with In Library beside it. In Keep in Photos it stays ticked; in Copy into a Folder it can't be ticked, and Copy to Folder… in the Apple Photos section copies it with its edits instead. A folder is In Library once all its albums are.

Smart Albums
: Kept in Photos, a smart album holds the photos its rules find in Photos, now and later. Copied, each becomes a collection of the photos it holds then.

Shared Albums
: Photos keeps shared albums' photos smaller, so these are reduced copies, not the originals.

Below the lists, a line such as 3 albums chosen, about 840 photos adds up Photos' estimates for the albums not kept yet. Add Albums stays dimmed until one of those is ticked.

### What's listed

Each photo keeps the file name Photos had for it, with Photos' date, place and pixel size, and a date changed in Photos is the photo's date in Redlamp too.

Photos edited in Photos
: Two photos, stacked: the original, as it was before Photos' edit, and Photos' version, named like `IMG_0421 (Photos edit).HEIC`, on top. Once you edit the original in Redlamp, it goes on top.

RAW+JPEG pairs
: Both files, paired under one name. ProRAW comes as its DNG.

Bursts
: The key photo and the frames you picked in Photos, stacked, the key photo on top.

Live Photos
: Their still photo.

Left out
: Videos, since Redlamp edits photos, and photos hidden in Photos. Photos' Hidden and Recently Deleted albums aren't listed.

### Photos you copied before

If you copied photos into your folders from Photos before, with Copy into a Folder or Copy to Folder…, keeping their album in Photos lists your copies in their places. No second photo is made from Photos, so each photo keeps one edit. A copy you move or rename in Redlamp still stands in. Once a copy leaves the library or goes missing, the album shows the photo from Photos again, with what Redlamp kept of it.

## The Apple Photos section

Once an album is kept, the Library panel has an Apple Photos section, after Folders and before Collections. It lists the albums you've kept inside Photos' folders, in Photos' order and under the titles Photos gives them now, each with the number of its photos in the library. Its **+** opens Add Albums from Apple Photos.

Click an album to show its photos in the grid and the filmstrip, or a folder to show the photos of every album kept in it. Right-click an album or a folder for its menu:

Show in Photos
: Opens Photos. Photos can't be asked to show one album, so it opens at its own window.

Download Originals
: Downloads the originals of its photos that are only in iCloud, described under [](#files.apple-photos.download-originals).

Copy to Folder…
: Copies the album's photos into a folder of your own, described under [](#files.apple-photos.copying-photos-to-a-folder). Albums only.

Remove from Library…
: Stops keeping it, after asking. Its photos leave Redlamp's lists, but for those another album you've kept holds, and what Redlamp kept of them stays on this Mac. Apple Photos isn't changed. Add Albums from Apple Photos… brings the album back, with its photos' edits. The section goes once no album is kept.

## Photos kept in Photos

### Originals from iCloud

The grid, the filmstrip and the loupe show Photos' own thumbnails and previews, so browsing, culling, keywording and searching never download anything. A photo Photos has no picture of on this Mac shows a placeholder with a cloud.

When a photo's original is only in iCloud, it's downloaded when you open the photo in Develop, look at it at 1:1 in the loupe, Compare or Survey, use focus peaking in Judging on it before it's edited, export it or copy it to a folder, or choose Download Originals. A photo you're waiting for goes first, then exports and copies, then Download Originals. An edit you paste or sync onto photos not downloaded is shown on each once its original arrives.

### Opening one in Develop

A photo whose original is only in iCloud opens in Develop at once on Photos' preview, with Downloading from iCloud and its progress over it, as a percentage, or as 18 of 42 MB where Photos gives the size. Its panels wait as they do before a photo is open, and it opens as any photo does once the original arrives.

Cancel
: Stops the download, leaving the photo on its preview with Download Again.

Try Again
: Shown with the reason when a download fails: iCloud can't be reached, since the original isn't on this Mac; Apple Photos no longer has the photo; or Redlamp isn't allowed to read Photos.

While a photo is open in Develop, the next one in the grid's order, in the direction you're going, is downloaded ahead, one at a time, except on a network macOS marks as expensive, such as a phone's hotspot, or as constrained, in Low Data Mode.

### Download Originals

To have originals on this Mac before you need them, select the photos and choose Photo › Download Originals, or choose it from a selected photo's menu or an album's. It has no keyboard shortcut, and it's dimmed unless a photo selected is kept in Photos with its original only in iCloud. While originals download, the filmstrip says how many, as Downloading 3 originals from iCloud, with a bar and **Cancel All**; those downloaded already stay.

Export downloads three originals ahead of the photo it's writing, and the filmstrip shows the downloads beside Exporting; Cancel stops both. A photo kept in Photos can't be exported to Same Folder as Original, which would be Redlamp's cache: choose a folder to export to.

### Originals kept on this Mac

Downloaded originals are kept in Redlamp's cache, `~/Library/Caches/Redlamp/Apple Photos`, which Time Machine leaves out and macOS may empty when it needs the space. One that goes is downloaded again the next time it's needed. Under Apple Photos in Settings › Library:

Keep downloaded originals up to
: 5, 10, 20, 50, 100 or 200 GB; 20 GB to start with. Past it, the originals opened longest ago go first, never the photo open in Develop, one being exported or copied, or one downloading.

Downloaded originals
: The space they take and how many there are, such as 3.2 GB in 84 originals. **Empty Cache** takes them all out, but the photo open and those being read.

### Culling, metadata and edits

Photos kept in Photos are culled, keyworded, collected and edited as any other. Their edits, history, snapshots, versions, ratings, flags, labels, keywords and collections are kept on this Mac, in Redlamp's library, `~/Library/Application Support/Redlamp/Library/Sidecars/apple-photos`, never beside the original or in Photos. No `.xmp` is written for them, even with Write .xmp sidecars for other apps turned on. A photo that leaves the library keeps what Redlamp kept of it there, for when it comes back.

::: not-yet On your other Macs
What Redlamp keeps of photos kept in Photos is on this Mac only, so Redlamp on another Mac doesn't see it.
:::

A favourite in Photos is a pick in Redlamp when its photo is added, and the pick follows the favourite as you change it in Photos. A pick or reject you set in Redlamp stays, whatever Photos does. A pick you clear stays cleared until the photo is no longer a favourite in Photos; from then on, the pick follows the favourite again.

::: not-yet Ratings, captions and keywords from Photos
Photos gives apps each photo's rating, caption and keywords from macOS 27, and only to an app built with the macOS 27 SDK. Redlamp is built with the macOS 26.5 SDK for now, so they don't come yet, even on macOS 27, whether the albums are kept or copied.
:::

Photos doesn't give the camera, lens and exposure, so Redlamp reads them from the original when it's first downloaded. Until then, the photo has none, and searches and the filter bar's Camera and Lens columns don't find it.

### Renaming, moving and the Trash

Redlamp doesn't move, rename or delete photos in Photos, so those commands work differently on photos kept there.

Rename Photos… and Move to Folder…
: Refused for the whole selection while it holds a photo kept in Photos, in an alert that says why. Nothing changes: select the other photos alone to rename or move them. In a photo's menu, Copy to Folder… and Download Originals take their place.

Move to Trash and the Delete key
: [[⌘⌫]] or [[⌫]] moves the other photos selected to the Trash and leaves these, in an alert that says why. Its Remove from Library button takes them out of Redlamp's lists at once.

Remove from Library…
: In a photo's menu in Library, where Move to Trash is dimmed. After asking, every photo of it leaves Redlamp's lists, its pair's raw, Photos' version and its versions too, with what Redlamp kept of it still on this Mac and Photos unchanged. Photos' changes don't bring it back; Add Albums keeping an album that holds it does, and so does [[⌘Z]], which brings it back with its culling.

Show in Photos
: In a photo's menu in the grid, or [[⌘R]]. Photos opens at its own window, since it can't be asked to show one photo. Photo › Show in Finder does the same for them.

Dragging photos kept in Photos onto one of Folders' folders copies them there, with Copy to Folder, rather than moving them. An album in the Apple Photos section takes no photos dropped on it. Remove Version… works as for any photo, since a version is Redlamp's own.

## Copying photos to a folder

Copy to Folder… copies photos kept in Photos into a folder of your own, with everything Redlamp keeps of them. Select the photos and choose Photo › Copy to Folder… or Copy to Folder… in a photo's menu, choose it from an album's menu in the Apple Photos section, or drag the photos onto one of Folders' folders. It opens the Copy to Folder window.

1. Check what's copied, on the left, once it's counted.
2. Under To, choose the destination, and the folders and names the copies are given, as for an import from a card.
3. Click Copy with the number of photos, such as Copy 12 Photos.

On the left, the window counts what's chosen, such as 12 photos kept in Apple Photos, or for an album “Lisbon”: 12 photos kept in Apple Photos. It lists what's copied: RAW+JPEG pairs, kept together under one name; photos edited in Photos, each original with Photos' version stacked with it; Live Photos as their still, and bursts, stacked. Originals that aren't on this Mac are downloaded from iCloud first. Videos aren't copied, nor photos copied to a folder already, and a place set only in Photos stays there: the copies keep the GPS their files hold.

To is Import's own column, shared with importing from cards: its destination, folders and names, backup and metadata preset. From an album's menu, the Apple Photos Album token, `{album}` in a template, is that album's title, so a Folders template of `{album}` puts the copies in a folder named after it. Dropped onto a folder, the photos go straight into it, without a backup, and Import's settings are left as they were.

Each copy carries the photo's edit, versions, history, snapshots and metadata, its collections, and the rating, flag and label it shows. No album becomes a collection, and none is followed. In the library, each copy then stands in for its photo: the album and All Photographs list the copy, and the photo's original leaves the cache.

The window shows the copy's progress, with **Stop**, which ends it once the photos being copied are done; closing the window lets it carry on. When it's done:

Undo Copy
: Moves the copies to the Trash, and the photos kept in Apple Photos come back to the library, with what Redlamp keeps of them.

Show in Library
: Shows the copies, selected in the grid.

Resume
: After Stop, carries on with the photos still to come.

Done
: Closes the window.

## Searching by source

Photos kept in Photos are in All Photographs, searches and smart collections with every other photo. To tell them apart, type `source:photos` in the filter bar, or `source:folders` for the photos in your folders, copies of photos from Photos among them; `-source:photos` leaves Photos' out. Typing `source:`, photos, folders or Apple Photos offers both, each with the photos it finds, and the command palette offers them too.

Source
: A column of the filter bar, chosen from a column's header menu, with Folders and Apple Photos and the photos of each. A side no photo is on is left out.

In the smart collection editor, the Source field takes is or isn't, with folders or photos.

## When Photos changes

Redlamp follows the albums you've kept when it opens, and a moment after each change Photos tells it of while it's running.

A photo added to an album
: Appears in the album and the library.

A photo deleted in Photos
: Leaves every list but Missing Photos, in Library Health, which lists it as no longer in Apple Photos since the time it went, with what Redlamp kept of it. Remove from Library takes it out, and Photos isn't changed. Locate… isn't offered, since there's no file to find.

A photo taken out of an album
: Leaves that album, and the library too unless another album you've kept holds it. What Redlamp kept of it stays.

An album renamed
: Takes its new title in the Apple Photos section.

An album made in a folder you've kept
: Is kept with it.

A favourite added or taken away
: Changes the pick, as described under [](#files.apple-photos.culling-metadata-and-edits).

A photo edited in Photos
: Gets new thumbnails and previews, and its Photos version is downloaded again when it's next needed.

A photo you've taken out with Remove from Library doesn't come back whatever Photos changes, until Add Albums keeps an album that holds it.

## Limited access

macOS can give Redlamp access to only the photos you choose for it. Then Photos gives Redlamp none of your albums, so Add Albums from Apple Photos lists one entry, **Photos Chosen for Redlamp**, which holds every photo Redlamp may read. A line under it says so, and that Full Access for Redlamp, in System Settings › Privacy & Security › Photos, shows your albums.

Add it as you would an album. It's kept and followed as one: photos you choose for Redlamp later appear in it, and those no longer chosen leave the lists, with what Redlamp kept of them still on this Mac.

## Copying albums into a folder

Copy into a Folder copies the photos of the albums you choose into folders of your own, where Redlamp keeps them as it keeps every other photo. Each photo comes with its favourite, its dates and its original file name, and each album becomes a collection. It starts with the albums the last import brought ticked, where they're still in Photos, or otherwise every album, but for smart and shared albums and those kept in Photos.

1. Choose File › Add Albums from Apple Photos…, then Copy into a Folder.
2. Tick the albums to bring across.
3. Choose whether to include hidden photos, and whether to follow these albums.
4. Under To, choose the Destination folder, and the Folders and Names the copies are given; the Example shows where a photo goes.
5. Click Review, or press [[Return]].

Include hidden photos
: Off to start with. On, the photos in Photos' Hidden album come too, where they're in the albums chosen.

Follow these albums
: On to start with. Redlamp remembers the albums, and the Library panel offers the new photos that arrive in them, described under [](#files.apple-photos.new-photos-in-followed-albums).

To is the column Import uses for cards, without its Card section: Destination, Folders, Names, Example, Backup, Files, Keywords and Metadata Preset. When no Destination is chosen yet, Review asks for one first. The Example shows a photo from the first album chosen. The folder and name templates have a token of their own for this, Apple Photos Album, `{album}` in a template, which is the name of the first chosen album the photo is in, so a Folders template of `{album}` alone puts each album's photos in a folder named after it.

### Reviewing what comes across

Review reads the albums chosen without copying anything, then shows what an import would bring, under a heading such as 412 photos from 3 albums.

Comes across
: How many photos are copied, as how many files and at what size, and how many photos that makes in the library. Then each kind that needs saying: RAW+JPEG pairs, kept together under one name; raws on their own, and how many of them are DNGs such as ProRAW; photos edited in Photos, which come as their original with Photos' version stacked over it; Live Photos, as their still; bursts, with the frames shown or picked in Photos, stacked; favourites, flagged as picks; photos in more than one album, copied once; reduced copies from shared albums; and hidden photos, when you included them.

Stays in Photos
: Videos, since Redlamp edits photos; hidden photos, unless Include hidden photos is on; the frames of a burst not picked in Photos; photos an earlier import brought already; and items that aren't photos. Titles, people and pets, memories and Recently Deleted always stay, since Apple's Photos framework doesn't give them to apps. A photo's place stays too, where it was set only in Photos; the GPS position a file holds comes with it, as part of the file.

Fields
: What this Mac's Photos framework gives: favourites, dates, original names, albums and places, and what macOS 27 would add: ratings, captions and keywords.

Click Import with the number of photos, such as Import 412 Photos, to start, or Back to change the albums. When every photo in the albums is in the library already or left out, the heading reads Nothing new to import.

### Importing

The import runs in four stages, shown along the top of the window: Reading albums, From Photos, where Photos writes each photo's files, Copying, where they're copied to the destination, checked and added to the library, and Finishing. Below them, the stage under way counts the photos done, with how much has been written. Photos kept only in iCloud are downloaded as they're reached, and the window says how many are downloading.

Closing the window lets the import carry on. Stop ends it once the photos being copied are done. A stopped import keeps what Photos has written so far, at the destination in a hidden folder, `.Redlamp Photos Import`, and Resume takes up where it stopped, without writing those files again. The hidden folder is removed once the import finishes.

Each photo is copied once, however many of the chosen albums it's in, with the file name Photos had for it, unless the Names template gives it another. Its sidecar holds what came with it:

- A favourite is flagged as a pick.
- Each album it's in makes it part of that album's collection, and Photos' folders become collection sets, so the collections keep Photos' arrangement.
- A date changed in Photos becomes a correction to its capture time, and the date its file records is left as it is.
- A RAW+JPEG pair comes as both files under one name, and ProRAW as its DNG.
- A photo edited in Photos comes as its original, with Photos' version, `<name> (Photos edit)`, stacked over it and on top, so the grid shows the photo as Photos does. Both have the photo's favourite, dates and albums. Photos' own edit settings aren't read, so the original comes unedited.
- A burst comes as its key photo and the frames you picked in Photos, stacked, with the key photo on top.

### When the import is done

The window says how many photos were imported, and in how long, how many photos are now in the library, how many collections were made, one for each album, and where the photos were copied. Under Left in Photos it lists any photo Photos couldn't give, any file that couldn't be copied, and what Review said would stay.

Undo Import
: Moves the import's copies to the Trash and takes them out of the library. Photos is as it was, since nothing in it changed. Albums that only this import followed are no longer followed.

Show in Library
: Shows the photos the import brought in Library's grid, selected.

Resume
: After Stop, carries on with the photos still to come.

Done
: Shows the albums again, with their counts read afresh.

## New photos in followed albums

When an import follows its albums, Redlamp counts the new photos in them each time it opens and whenever Photos changes. While some are new, the Library panel shows From Apple Photos, after Rejected, with how many there are and Import: click Import to bring them with the last import's settings, as the window does, showing its progress. Click the row itself to open Add Albums from Apple Photos with Copy into a Folder chosen. Its right-click menu has Add Albums from Apple Photos… and Import with the number of new photos, such as Import 12 New Photos.

To have the new photos imported without asking, turn on Import new photos from followed albums automatically, under Apple Photos in Settings › Library. It's off to start with. Turned on, the new photos are imported a minute after Photos last changes, while Redlamp is open.

An album you've kept in Photos isn't offered here, nor imported automatically, even if an import followed it before: it follows Photos by itself. A copy an import made stays in your folder when its photo leaves Photos or the album.

::: note From the command line
`redlamp library photos` works with Photos in Terminal. `--keep --album <title>` keeps albums in Photos as Add Albums does, and `--list` lists those kept, with their photos. `--originals` says how much the downloaded originals take, and `--evict` empties their cache. For copying, `--albums` lists the albums with their IDs, `--census` prints what Review would show, `--apply --destination <folder>` imports, and `--undo` takes the last import back. `--album` names an album by its title, a path of titles such as `Trips/Lisbon`, or its ID, and can be repeated. `redlamp library photos --help` lists the rest.
:::
