+++
deck = "Copy the albums you choose from Apple Photos into your own folders, with their favourites, dates and original names, each album a collection. Photos is only read, and the new photos that arrive in those albums are offered to you later."
sources = [
  "`docs/manual/facts/files.md`: Importing from Apple Photos, §A1 to §A9",
  "`packages/RedlampUI/Sources/Library/ApplePhotos/ApplePhotosScreen.swift` (every page's headings, lines and buttons), `ApplePhotosViews.swift` (the albums and their boxes), `ApplePhotosImportModel.swift` (choosing, Stop, Resume, Undo Import, Show in Library, Done), `ApplePhotosWindowController.swift` (the window and To)",
  "`packages/RedlampUI/Sources/Library/Import/ImportDestinationView.swift` (To); `Library/Rename/NamingTemplateField.swift` (the Apple Photos Album token)",
  "`packages/RedlampUI/Sources/Library/ApplePhotos/ApplePhotosFollower.swift`, `ApplePhotosSource.swift`; `Sidebar/AppKit/ApplePhotosRowViews.swift`, `SourceOutlineView.swift`; `Settings/LibrarySettings.swift` (followed albums)",
  "`packages/RedlampLibrary/Sources/ApplePhotos/ApplePhotosImport.swift`, `ApplePhotosStager.swift`, `ApplePhotosLibrary.swift`, `PhotoKitLibrary.swift` (what each photo becomes, and the fields each macOS gives)",
  "`apps/RedlampMac/Sources/AppCommands.swift`, `apps/RedlampMac/Project.swift` (the menu item and the usage string); `apps/RedlampCLI/Sources/LibraryCommand+Photos.swift` (`redlamp library photos`)",
]
+++

Import from Apple Photos copies the photos in the albums you choose out of your Photos library and into folders of your own, where Redlamp keeps them as it keeps every other photo. Each photo comes with its favourite, its dates and its original file name, and each album becomes a collection. Redlamp only reads your Photos library: it never adds, changes or deletes anything there, so the photos stay in Photos as they were.

## Opening the window

Choose File › Import from Apple Photos…, or find it in the command palette by a word such as photos, albums or icloud. It has no keyboard shortcut to start with. It opens Import from Apple Photos, a window of its own.

### Allowing Redlamp to read Photos

macOS asks once whether Redlamp may read Photos. The first time, the window explains why under Allow Redlamp to read Photos: click Continue, and macOS asks, saying that Redlamp copies the photos in the albums you choose into your folders and never changes your Photos library. Allow it, and the window reads Photos' albums.

If Redlamp can't read Photos, the window says why, and Open System Settings opens Privacy & Security › Photos, where Redlamp's access is changed. Then come back to the window.

Redlamp isn't allowed to read Photos
: Access was turned off for Redlamp. Turn Redlamp on in System Settings › Privacy & Security › Photos.

Photos is restricted on this Mac
: A profile or Screen Time keeps apps from reading Photos. Whoever manages the Mac can allow it.

Redlamp can read only some of your photos
: Access is limited to the photos chosen for Redlamp, and limited access gives none of your albums, so there's nothing to import. Choose Full Access for Redlamp.

## Choosing the albums

The window shows your albums on the left, under From, and on the right the To column that Import uses for cards, which says where the photos go and what they're called.

1. Tick the albums to bring across. Nothing is ticked to start with.
2. Choose whether to include hidden photos, and whether to follow these albums.
3. Under To, choose the Destination folder, and the Folders and Names the copies are given; the Example shows where a photo goes.
4. Click Review.

Review stays dimmed until an album is chosen. Below the lists, a line such as 3 albums chosen, about 840 photos adds up Photos' own estimates; Review counts them exactly.

### The albums

Albums
: Your albums and Photos' folders, in Photos' order, each album with how many photos Photos estimates it holds. A folder's albums are indented beneath it, and its count is theirs together. A folder's box ticks every album in it, however deep, and shows a dash while only some are ticked.

Smart Albums
: Each comes as a collection of the photos it holds now. Its rules stay in Photos.

Shared Albums
: Photos keeps shared albums' photos smaller, so these are reduced copies, not the originals.

Include hidden photos
: Off to start with. On, the photos in Photos' Hidden album come too, where they're in the albums chosen.

Follow these albums
: On to start with. Redlamp remembers the albums, and the Library panel offers the new photos that arrive in them, described under [](#files.apple-photos.new-photos-in-followed-albums).

### To

To is the same column as when importing from a card, with everything but its Card section: Destination, Folders, Names, Example, Backup, Files, Keywords and Metadata Preset. Until a Destination is chosen it reads Not chosen yet: Import asks for it. The Example shows a photo from the first album chosen, and until there is one it says Choose an album to see where its photos go.

The folder and name templates have a token of their own for this import, Apple Photos Album, `{album}` in the template, which is the name of the first chosen album the photo is in. A Folders template of `{album}` alone puts each album's photos in a folder named after it. For photos that come from anywhere else, the token is empty.

## Reviewing what comes across

Review reads the albums chosen without copying anything, then shows what an import would bring, under a heading such as 412 photos from 3 albums. It has three parts.

Comes across
: How many photos are copied, as how many files and at what size, and how many photos that makes in the library. Then each kind that needs saying: RAW+JPEG pairs, kept together under one name; raws on their own, and how many of them are DNGs such as ProRAW; photos edited in Photos, which come as their original with Photos' version stacked over it; Live Photos, as their still; bursts, with the frames shown or picked in Photos, stacked; favourites, flagged as picks; photos in more than one album, copied once; reduced copies from shared albums; and hidden photos, when you included them.

Stays in Photos
: Videos, since Redlamp edits photos; hidden photos, unless Include hidden photos is on; the frames of a burst not picked in Photos; photos an earlier import brought already; and items that aren't photos. Titles, people and pets, memories and Recently Deleted always stay, since Apple's Photos framework doesn't give them to apps. A photo's place stays too, where it was set only in Photos; the GPS position a file holds comes with it, as part of the file.

Fields
: What this Mac's Photos framework gives: favourites, dates, original names, albums and places, and what macOS 27 would add: ratings, captions and keywords.

Click Import with the number of photos, such as Import 412 Photos, to start, or Back to change the albums. When every photo in the albums is in the library already or left out, the heading reads Nothing new to import.

::: not-yet Ratings, captions and keywords
Photos gives apps each photo's rating, caption and keywords from macOS 27, and only to an app built with the macOS 27 SDK. Redlamp is built with the macOS 26.5 SDK for now, so they don't come across yet, even on macOS 27, and Fields doesn't list them.
:::

## Importing

The import runs in four stages, shown along the top of the window: Reading albums, From Photos, where Photos writes each photo's files, Copying, where they're copied to the destination, checked and added to the library, and Finishing. Below them, the stage under way counts the photos done, with how much has been written. Photos kept only in iCloud, as Optimize Mac Storage keeps them, are downloaded as they're reached, and the window says how many are downloading.

Closing the window lets the import carry on. Stop ends it once the photos being copied are done. A stopped import keeps what Photos has written so far, at the destination in a hidden folder, `.Redlamp Photos Import`, and Resume takes up where it stopped, without writing those files again. The hidden folder is removed once the import finishes.

### What each photo becomes

Each photo is copied once, however many of the chosen albums it's in, with the file name Photos had for it, unless the Names template gives it another. Its sidecar holds what came with it:

- A favourite is flagged as a pick.
- Each album it's in makes it part of that album's collection, and Photos' folders become collection sets, so the collections keep Photos' arrangement.
- A date changed in Photos becomes a correction to its capture time, and the date its file records is left as it is.
- A RAW+JPEG pair comes as both files under one name, and ProRAW as its DNG.
- A photo edited in Photos comes as its original, with Photos' version, `<name> (Photos edit)`, stacked over it and on top, so the grid shows the photo as Photos does. Both have the photo's favourite, dates and albums. Photos' own edit settings aren't read, so the original comes unedited.
- A burst comes as its key photo and the frames you picked in Photos, stacked, with the key photo on top.

## When it's done

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

When an import follows its albums, Redlamp counts the photos in them each time it opens and whenever Photos changes. While some are new, the Library panel shows From Apple Photos, with how many there are and Import: click Import to bring them with the last import's settings, as the window does, showing its progress. Click the row itself to open Import from Apple Photos. Its right-click menu has Import from Apple Photos… and Import with the number of new photos, such as Import 12 New Photos.

To have the new photos imported without asking, turn on Import new photos from followed albums automatically, under Apple Photos in Settings › Library. It's off to start with. Turned on, the new photos are imported a minute after Photos last changes, while Redlamp is open.

Nothing is removed from Redlamp when a photo leaves Photos or one of the albums: the copy stays in your folder.

::: note From the command line
`redlamp library photos` does the same in Terminal. `--albums` lists the albums with their IDs, `--census` prints what Review would show, `--apply --destination <folder>` imports, and `--undo` takes the last import back. `--album` names an album by its title, a path of titles such as `Trips/Lisbon`, or its ID, and can be repeated. `redlamp library photos --help` lists the rest.
:::
