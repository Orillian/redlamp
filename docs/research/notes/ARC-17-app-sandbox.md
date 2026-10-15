# ARC-17: Redlamp in the App Sandbox

[#371](https://github.com/pdcgomes/redlamp/issues/371) asked for the App Sandbox, as Pixelmator Pro has it, so that Redlamp reaches only the files the photographer gives it; the Mac App Store requires it (guideline 2.4.5(i)). This note is the study ARC-17's handover asks for: everything the app does with files, the network and devices, what the sandbox needs for each, and what changes for people. It folds in the App Store's constraints: ARC-17's row, DEC-90, DEC-91, DEC-96 and DEC-97, the build audit's section 4 and [docs/app-store/compliance.md](../../app-store/compliance.md). The plan it leads to, and the owner's questions, are at the end.

## In short

- **The folders people added can stay reachable without anyone being asked again.** The unsandboxed app can make security-scoped bookmarks for folders it was never given, and the sandboxed app, with the same bundle ID and signature, resolves them with read-write access. The plain bookmarks Redlamp keeps today don't carry over: resolved with security scope they're refused, and without it they open through a token that most likely ends at the next restart. So a release that makes security-scoped bookmarks for every folder Redlamp remembers, before the sandbox turns on, keeps them all.
- **Only the working set keeps bookmarks today.** The library's roots (a bookmark column that is never written), the import destination and its backup, export destinations, Export with Previous, export presets and the Lightroom catalog's folders are kept as bare paths, which the sandbox can't reach after a relaunch.
- **Related items don't reach Redlamp's sidecars.** For a photo opened on its own, the sandbox let the spike write `IMG_0001.redlamp` and `IMG_0001.xmp` beside it, as Apple documents (the same name with another extension), but refused `IMG_0001.ARW.redlamp`, the name Redlamp gives sidecars, for writing and for reading. A photo opened on its own can keep its edit beside it only once its folder is granted. Renaming sidecars would break every existing one, and a raw and a JPEG of the same name would share one.
- **The app opens nothing from the Finder or the Dock today,** sandbox or not: it declares no document types and handles no open event.
- **The container takes everything with it, once.** Migration moves what its manifest names, as a rename (models of a gigabyte aren't copied or downloaded again), and the preferences move with it unasked. With one bundle ID for both builds (DEC-91), the App Store build's first launch on a Mac with the unsandboxed direct download takes the direct download's settings, and its data too if the App Store build migrates it. Both builds should turn sandboxed in the same release, or the App Store build needs a bundle ID of its own.
- **A card can't be told from another drive before it's granted.** A sandboxed app sees a volume mount, its name, UUID and that it's ejectable, but can't list it or its `DCIM`, and no entitlement covers removable volumes. DEC-96's panel at the volume's root works.
- **No temporary exceptions and no app-scope bookmark entitlement are needed** in the App Store build. Crash reports come from MetricKit alone, without the message an abort leaves. The direct download, once sandboxed, needs Sparkle's installer service and two temporary exceptions, and the `redlamp` CLI has to find the app's data in its container.

## How it was done

- **Code:** origin/main at 4a2fa5fc3 (15 October 2026), surveyed for every file, network, device and process operation, with file and line references.
- **Documentation:** Apple's current pages and its archived *App Sandbox Design Guide*, Sparkle's sandboxing guide, and Developer Forums threads, all read on 15 October 2026. The forums refuse automated reads, so threads were read from Wayback Machine snapshots, dated below.
- **A spike** (`scripts/sandbox-spike/`): a small app built twice from one file, sandboxed and not, signed with one Apple Development identity under one bundle ID, and opened by Launch Services, which grants it the documents it's given. Run on this Mac, macOS 26.6.2 (25G83), on 15 October 2026; `scripts/sandbox-spike/run.sh` runs it again. The sandboxed copy has the App Store build's file entitlements: `app-sandbox` and `files.user-selected.read-write`, nothing else.
- **Not checked:** macOS 27; a restart between making a bookmark and resolving it; the App Store's re-signed build, whose signature differs from the direct download's (whether it resolves bookmarks the direct download made is settled on TestFlight, ARC-23).

## 1. The entitlements

| Entitlement | Build | What needs it |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | Both: the App Store build first | The sandbox |
| `com.apple.security.files.user-selected.read-write` | Both | Folders, photos and destinations people choose; sidecars and exports are written |
| `com.apple.security.network.client` | Both | Model downloads, Report a Bug, Your Reports' status, the Camera Bench, What's New; in the direct download, Sparkle and the firmware model |
| `com.apple.security.application-groups` | The App Store build, with INF-07 | Apple-hosted model packs, shared with their downloader extension |
| `com.apple.security.device.usb` | Both, with TET-04 | Tethering through ImageCaptureCore (Apple: "In macOS 14 and later, use the `com.apple.security.device.usb` entitlement key") |
| `com.apple.security.temporary-exception.mach-lookup.global-name` | The direct download only | Sparkle's installer service (section 8) |

Not needed:

- **`com.apple.security.files.bookmarks.app-scope`.** Apple's page for it is gone, and DTS wrote in August 2025 that "User selected read/write are both accepted as well" ([thread 798402](https://developer.apple.com/forums/thread/798402), snapshot of 21 February 2026). The spike made and later resolved a security-scoped bookmark without it.
- **`com.apple.security.assets.pictures.read-write`:** none, as DEC-96 decides.
- **`network.server`:** nothing in the app listens. `NWListener` is only in RedlampBench (`BenchHTTPServer.swift:105`), for the CLI's `task serve` and the harness.
- **Hardened-runtime exceptions and temporary exceptions** in the App Store build.

The decode service is already sandboxed with `app-sandbox` alone (`RedlampDecoder.entitlements`). It receives a photo's bytes, read by the app (`DecodeService.swift:316-325`), so it needs nothing more.

## 2. Folders and volumes people add

### What Redlamp remembers, and how

| What | Chosen by | Kept as | Bookmark today |
| --- | --- | --- | --- |
| The working set's folders (UX-08) | Add Folder…, File › Open, a drop | `folders.roots` (`FolderLibrary+WorkingSet.swift:245`) | Yes, plain while unsandboxed (`WorkingFolder.swift:67-91`) |
| The open folder, expanded folders, last photo per folder | Derived | `folders.open`, `folders.expanded`, `folders.lastPhotos` | No; inside a root |
| The library's roots (LIB-05 to LIB-10) | Adding to the library, import | `roots` in `Index.sqlite` | Column `bookmark` (`LibraryIndexSchema.swift:126`), never written (`LibraryIndex+Roots.swift:50,136`) |
| The import destination and backup (LIB-27) | A panel (`ImportWindowController.swift:239`) | `import.settings` (`ImportSettings.swift:87,90`) | No |
| Export destinations, Export with Previous, presets | A panel (`ExportSheetSections.swift:94-103`) | `exportPresets`, `exportPrevious`, `exportPreviousPreset` (`ExportPresetStore.swift:87-90`) | No |
| Staged exports left by a crash | Derived | `export.staging` (`ImageExporter.swift:194-211`), swept at launch | No |
| The Lightroom catalog's photo folders | Read from the catalog (`LightroomCatalog+Reading.swift:68,81`) | Library roots | No |
| The firmware model's folder (a development switch) | Typed | `app.redlamp.firmwareFilmModelFolder` | No; out of the App Store build (DEC-89) |

LUT, HALD and recipe imports are read once and copied into Redlamp's own folders (`RecipeActions.swift:79,167`), so they need no bookmark, though ARC-17's row lists them.

### What the sandbox needs

- **A security-scoped bookmark made when the folder is chosen,** while the panel's or the drop's access lasts, resolved at launch with `.withSecurityScope`, and access started for as long as the folder is in use and stopped when it's removed. Apple: "If sufficient kernel resources leak, your app loses its ability to add file-system locations to its sandbox… until relaunched", and it gives no number.
- **The bookmark first, the path second.** `WorkingFolder.resolve()` tries the path and turns to the bookmark only when the path is gone; in the sandbox, the path alone is refused (the spike listed the folder by path before resolving: refused).
- **The bookmark before the folder is saved.** `add(_:)` saves a root with no bookmark, then makes it on the scheduler (`FolderLibrary+WorkingSet.swift:19-32`), and `locate` does the same; a quit in between leaves a folder the sandbox can't reach. `startAccess` is keyed by path (`:231`), so a root whose path changed is started twice and stopped once.
- **Every other remembered folder gets one:** the library's roots fill their column; the import destination and backup, export destinations, Export with Previous and presets keep a bookmark beside the URL; the staging sweep runs inside the destination's access. The Lightroom import asks for each root the catalog names, root by root, as it already does for a missing one (`LightroomWindowController.swift:305`).
- **The import destination starts unset.** Its default is `~/Pictures` (`ImportPreferences.swift:25-29`), which the sandboxed app can't reach without the Pictures entitlement, so the first import asks for it, in both builds.

Inside a granted folder, the spike found everything Redlamp does works: listing subfolders, writing, renaming, moving to the Trash (to the volume's `.Trashes`), FSEvents for the folder's changes, and an export staged in the system's item-replacement folder and moved in, on the Mac's own disk and on an external SSD. Access ends when it's stopped.

Building step 2 (15 October 2026) found three more things, with an app opened by Launch Services and from the shell of an agent:

- **A process inside a sandbox of another kind can't make a security-scoped bookmark at all:** macOS refuses with "Required entitlement com.apple.security.files.bookmarks.app-scope is missing or false", whether the process is signed with a team or ad hoc. Agents' shells run in such a sandbox (Cursor's, as Meta launches it), and so do the tests and the regression suite started from them; the build Mac's aren't. An app opened by Launch Services, ad hoc signed or not, makes them. So a bookmark is security-scoped wherever one can be made, and plain otherwise, and the working set says which it keeps.
- **Unsandboxed, a plain bookmark resolved with security scope is refused** (`NSCocoaErrorDomain` 259), as in the sandbox, while a security-scoped one resolves either way. Earlier versions' bookmarks are resolved as plain ones.
- **A bookmark resolves to whatever is at its recorded path when something is there,** so a folder replaced at its path is found there, as when the path was tried first, and only a folder renamed or moved is followed. It resolves to the folder's real path (`/private/tmp` for `/tmp`), so a folder added through a symbolic link keeps the path it was added by, or the library would take it for a new folder.

### Folders added before the update

The spike made three bookmarks of a folder from the unsandboxed copy, with no panel, and resolved each in a sandboxed launch of its own:

| Bookmark made unsandboxed | Resolved with security scope | Resolved without |
| --- | --- | --- |
| Plain, as Redlamp makes today | Refused (`NSCocoaErrorDomain` 259) | Reads and writes |
| Security-scoped | Reads and writes | Refused |
| Security-scoped, read-only | Reads; writing refused | Refused |

- A plain bookmark carries a sandbox extension issued when it was made; Microsoft's analysis of CVE-2025-31191 says that token is signed with a key "generated in each new boot", and Apple says that only security-scoped bookmarks restore access after the app relaunches. Redlamp's plain bookmarks would open on the first sandboxed launch and fail after a restart, so they are used only to find a folder again, never for access.
- A security-scoped bookmark is signed with the app's own key, which ScopedBookmarksAgent keeps, and is what sandboxed apps rely on across restarts. Whether one made by the unsandboxed app survives a restart wasn't tried; `run.sh mint`, a restart, then `run.sh use` tries it.
- **So:** from the release before the sandbox, the unsandboxed app makes a security-scoped bookmark for every folder it remembers, as it can without asking, and makes it again when it's stale. The first sandboxed launch resolves them, nobody is asked, and each is made again from inside the sandbox. Whatever doesn't resolve (a folder that moved off a volume, or a bookmark the App Store build's signature won't accept) is listed once, with its last path, and each opens a panel at that path.
- **Settings written just before the first sandboxed launch can stay behind.** In the spike's second run, a setting written three seconds before the first sandboxed launch missed the move: cfprefsd wrote it to a new plist at the old path after the migration had moved the file. The bookmarks and the settings that hold folders are kept in a file in Redlamp's own folder as well, which the manifest moves, and the first sandboxed launch takes from it what the settings lack.

## 3. Photos and the sidecars beside them

### A photo inside a granted folder

Its `.redlamp` sidecar (`SidecarLocator.swift:50-52`), its `.xmp` (`XMPSidecarFiles.swift:4-6,111`), iCloud Drive's placeholders (`SidecarLocator.swift:115`), Move Edits, renames and the Trash work as they do today: the folder's grant covers them.

### A photo on its own

Opened from the Finder, the Dock, a drop or File › Open, only the photo itself is granted. Apple's rule for reaching a file beside it: related items "access files that have the same name as a user-chosen file, but a different extension" (*App Sandbox in Depth*), declared with `NSIsRelatedItemType` and reached through `NSFileCoordinator` with a file presenter whose `primaryPresentedItemURL` is the photo. The spike declared `app.redlamp.edit` and an XMP type as related types and opened five photos:

| Beside `A.ARW` to `E.ARW` | Result |
| --- | --- |
| `A.ARW.redlamp`, a package written in place | Refused |
| `B.ARW.redlamp`, built in a hidden sibling and moved in, as Redlamp builds a new one (`Sidecar.swift:547-557`) | Refused |
| `C.redlamp`, a package written in place, its files written atomically | Written |
| `C.xmp`, written atomically | Written |
| `D.ARW.redlamp`, already there, read | Refused |
| `D.ARW.xmp` (darktable's naming), read | Refused |
| `D.xmp`, read | Read |
| `E.ARW.redlamp` with no file presenter; `E-unrelated.txt` | Refused |

- A package can be a related item, built in place; a hidden sibling can't.
- Redlamp names a sidecar for the photo's whole name (`IMG_0001.ARW.redlamp`) so that a raw and a JPEG of the same name keep edits of their own. The related-items name, `IMG_0001.redlamp`, would be shared by the pair, and every existing sidecar would need renaming. So a photo opened on its own can't keep its edit beside it until its folder is granted: question 1 at the end.
- Redlamp's own `.xmp` (`IMG_0001.xmp`) works as a related item; darktable's `IMG_0001.ARW.xmp`, which Redlamp reads, can't be read for a photo opened on its own.
- macOS declares no type for `.xmp` (a dynamic type on this Mac), so the app imports one to mark it related; the spike used `com.adobe.xmp`, conforming to `public.xml`.
- File › Open adds a photo's folder to the working set (`EditorModel+Library.swift:9-21`); in the sandbox the panel grants the photo, not its folder.

### Opening photos from the Finder and the Dock

`apps/RedlampMac/Project.swift` declares `UTExportedTypeDeclarations` for the sidecar and no `CFBundleDocumentTypes`, and nothing implements `application(_:open:)`, so Open With, a photo dropped on the Dock icon and Open Recent don't work in either build. The sandboxed app receives files that way, so the document types (the raw types Redlamp opens, JPEG, HEIF, TIFF and DNG, with an Alternate rank so Preview stays the default) and the open event come with the sandbox, with the sidecar and XMP types marked related.

## 4. Cards and other volumes (LIB-27)

The import window opens when a card is inserted: it follows mount notifications (`ImportCards.swift:41-55`) and treats an ejectable volume with a `DCIM` folder as a card (`ImportSource.swift:96,126`). The spike mounted a disk image with a `DCIM` folder while the sandboxed copy waited:

- It listed `/Volumes` and enumerated mounted volumes, each with its name, UUID and whether it's ejectable.
- It received the mount notification, with the new volume's name, UUID and ejectability.
- It couldn't list the new volume or its `DCIM`, nor any volume but the startup disk.

No entitlement covers removable volumes (`files.all` was retired in macOS 10.11), and whether ImageCaptureCore lists a card reader to a sandboxed app is unverified. DEC-96's answer works: when a volume arrives, the window offers it, an open panel at its root grants it, and a bookmark kept by the volume's UUID opens the same card directly next time; a card formatted in the camera has a new UUID and is asked for again. What changes is that the app can't see `DCIM` before the grant, so it can't tell a card from another drive: question 3 at the end. Eject keeps working (`ImportCards.swift:108-111`).

## 5. What Redlamp keeps on this Mac, and the container

| Path | Holds | Used by |
| --- | --- | --- |
| `~/Library/Application Support/Redlamp/Library/` | The index, its snapshots, thumbnails and previews, sidecars kept on this Mac, keywords and collections | App, CLI |
| `…/Redlamp/Models/` | Models: SAM 3 988 MB, Depth Anything 3 336 MB, ViTMatte 111 MB, SAM 2.1 80 MB | App, CLI, the regression suite |
| `…/Redlamp/Lens Profiles/` | The photographer's `.lcp` files | App |
| `…/Redlamp/Recipes/`, `…/Redlamp/Looks/` | Recipes, favourites, film slots, Base Looks | App, CLI |
| `…/Redlamp/Film Model/`, `…/Redlamp/Feedback/`, `…/Redlamp/Bench/` | The firmware model; Your Reports, the outbox and session journals; Bench tasks | App; Bench also the CLI |
| `~/Library/Caches/app.redlamp/` | Thumbnail packs, embeddings, focus stacks, compiled models | App, CLI |
| `~/Library/Caches/Redlamp/WhatsNew` | What's New's last feed | App |
| `~/Library/Preferences/app.redlamp.mac.plist` | Settings | App |

In the sandbox all of these resolve inside `~/Library/Containers/app.redlamp.mac/Data`. The spike's sandboxed copy found `NSHomeDirectory()`, `HOME`, `CFFIXED_USER_HOME`, the temporary folder, Application Support and Caches all there, and the real `~/Library/Application Support` refused.

- **Migration:** a `container-migration.plist` in the bundle's Resources, with `Move` for `${ApplicationSupport}/Redlamp`, `${Caches}/app.redlamp` and `${Caches}/Redlamp`. The spike's manifest moved a 64 MB file into the container at the first sandboxed launch, keeping its inode: a rename, not a copy, so the models move at once. The originals were gone, as the archived guide says ("macOS moves—it does not copy"), though Apple's current page says it copies. The preferences moved without being named. Apple: "If a container directory already exists, then no migration is needed", so it runs once. What happens when a destination exists is unverified; a new container has none.
- **The Lens Profiles folder** moves into the container, where people adding profiles with the Finder won't find it. The Lens Corrections panel and Settings get Add Lens Profiles…, which copies the chosen `.lcp` files in, and Show in Finder.
- **The Homebrew cask's `zap`** names `~/Library/Caches/app.redlamp.mac`, but the caches are in `app.redlamp` and `Redlamp`; it also needs `~/Library/Containers/app.redlamp.mac`.

### Both builds under one bundle ID (DEC-91)

After the spike's first sandboxed launch, the unsandboxed copy found none of its Application Support data. Its settings were only in cfprefsd's memory: the plist had moved, and a setting the sandboxed copy wrote didn't reach it. So on a Mac with both, the App Store build's first launch takes the settings of a direct download that isn't sandboxed yet (the folders, export presets and every other setting), and its data as well if the App Store build migrates it. The manifest's only other keys (`Symlink`, `MigrateScriptsForApplication`) can't prevent it; `Symlink` links out of the container and needs temporary exceptions. Once both are sandboxed they share the container; Apple: "Two different versions of your app can have different designated requirements, leading the operating system to request permission when the second version tries to access the sandbox container", and an app whose access is denied doesn't launch. Question 2 at the end.

The App Store build takes models from Apple-hosted packs (DEC-97), so in a shared container it downloads them again rather than using the direct download's; INF-07 settles whether it may use files already there.

## 6. The network

All of it is outgoing HTTPS, which `network.client` covers.

| What | Where | Code |
| --- | --- | --- |
| Model downloads | Each manifest's source, Hugging Face or a GitHub release; the App Store build uses packs only (DEC-97) | `ModelStore.swift:102-108,206-228` |
| Report a Bug, Your Reports' status | `redlamp.app/api/feedback` | `FeedbackClient.swift:52`, `FeedbackHistory.swift:57-62` |
| The Camera Bench | `redlamp.app/api/bench` | `CameraBenchRelay.swift:36` |
| What's New | `redlamp.app/api/whats-new` | `WhatsNewRelay.swift:13` |
| The firmware model (direct download only, DEC-89) | Two addresses from the Info.plist | `FirmwareModelHost.swift:48-55` |
| Updates (direct download only) | `SUFeedURL` | `Updates.swift:17-21` |

## 7. Processes, the CLI and the decode service

- The app starts no processes and sends no Apple Events; it opens URLs and reveals files with `NSWorkspace`, which the sandbox allows.
- The decode service is unchanged (section 1); the App Store build re-signs it with Apple Distribution (ARC-23).
- **The CLI** isn't in the App Store build (DEC-90). In the direct download it shares the library's index, recipes, Bench folders, models and caches with the app by path (`LibraryCommand+Lightroom.swift:33`, `RecipeCommands.swift:89`, `TaskCommands.swift:30`, `MaskCommand.swift:95`). Once the direct download is sandboxed, those are in the container, so the CLI looks for them there when the container exists. An unsandboxed process reading another app's container is asked about, unless it's signed by the same team (WWDC23 session 10053); for a tool run from Terminal, which macOS holds responsible, that is unverified.

## 8. Updates in the direct download

The App Store build has no Sparkle (ARC-22; guideline 2.4.5(vii)). A sandboxed direct download, from Sparkle's [sandboxing guide](https://sparkle-project.org/documentation/sandboxing/):

- `SUEnableInstallerLauncherService` set, and Sparkle's `Installer.xpc` kept in the bundle: "The Installer XPC Service is required for Sandboxed applications". The release removes both of Sparkle's services today (`mise/tasks/release:217-218`).
- `com.apple.security.temporary-exception.mach-lookup.global-name` with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`, which a Developer ID app may carry.
- No downloader service: with `network.client`, "you should not enable the Downloader XPC Service".
- The update from today's unsandboxed release is installed by that release's own Sparkle, and the new build's first launch migrates the container. A maintainer wrote that a 1.x Sparkle "can upgrade a non-sandboxed app to an app using Sparkle v2.x" ([issue 1342](https://github.com/sparkle-project/Sparkle/issues/1342)).

## 9. Crash and hang reports

`MacCrashReport` reads `~/Library/Logs/DiagnosticReports` (`MacCrashReport.swift:9`), which the spike's sandboxed copy couldn't list. The incident check merges that report with MetricKit's diagnostic (`IncidentCheck.swift:90-100`), so the sandboxed build reports from MetricKit alone, whose crash diagnostics arrive within a second of the next launch (measured 14 October, `MetricKitDiagnostics.swift`). What a crash report gives that MetricKit doesn't: what the app and its libraries said as it ended (the report's `asi`, where Swift's fatal error messages are), the termination's details and the memory region a bad access fell in. Hangs keep the watchdog's own record. The check waits 6 seconds for a crash report (`IncidentCheck.swift:59`), which in the sandbox never comes, so it doesn't wait there.

## 10. Testing and the release

- **The regression suite** runs a test build in a home of its own by setting `CFFIXED_USER_HOME` (`scripts/e2e.py:617`); the sandbox sets it, and `HOME`, to the container, so a sandboxed build ignores it. The suite keeps driving the unsandboxed Debug build, where the grant prompts are reached as they are in the sandbox, when a folder has no bookmark that resolves. The sandboxed App Store build is tried by hand and on TestFlight (ARC-23).
- **Test targets** run without a host app and get no container.
- **`check-release-bundle.sh --app-store`** (ARC-22) checks that the app's entitlements are exactly the App Store build's.
- **The release** signs the app with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` and preserves its entitlements (`mise/tasks/release:200,227-229`), so the direct download carries its entitlements file once it turns sandboxed.

## 11. What changes for people

| Change | In which build | When |
| --- | --- | --- |
| Photos open from the Finder and the Dock | Both | With the document types |
| A photo opened on its own keeps its edit beside it only once its folder is granted | Both, once sandboxed | Question 1 |
| A card is granted once, by a panel at its root | Both, once sandboxed | DEC-96, question 3 |
| The import destination is chosen at the first import | Both | With the bookmarks |
| Lens profiles are added with Add Lens Profiles… | Both, once sandboxed | Container |
| darktable's `IMG_0001.ARW.xmp` isn't read for a photo opened on its own | Both, once sandboxed | — |
| Crash reports lose what an abort said | Both, once sandboxed | — |
| macOS asks once when the other build opens the shared container | Both, once both are sandboxed | DEC-91, question 2 |
| No `redlamp` CLI, no Sparkle | App Store | DEC-90, ARC-22 |

## 12. The plan

Each step lands with its tests, a regression scenario for anything a person does, and nothing built before the owner approves.

1. **This study.**
2. **Bookmarks for everything Redlamp remembers, in both builds, while unsandboxed.** `FolderAccess` makes security-scoped bookmarks always (the unsandboxed app can), resolves the bookmark first, and makes it before a folder is saved; the library's roots fill their column; the import and export destinations, Export with Previous and presets keep bookmarks; the Lightroom import asks root by root; at launch, anything remembered without a security-scoped bookmark gets one, and a copy goes in a file in Redlamp's folder. People see nothing, except the import destination chosen at the first import.
3. **Opening photos.** Document types and the open event, so Open With and the Dock work in both builds; for a photo whose folder isn't granted, question 1's answer.
4. **Grants.** The list of folders to give back, shown when a bookmark doesn't resolve; cards as DEC-96 and question 3 decide; Add Lens Profiles… and Show in Finder; crash reports without the wait when sandboxed.
5. **The App Store build sandboxed,** behind ARC-22's entitlements file (`app-sandbox`, `files.user-selected.read-write`, `network.client`), with the migration manifest question 2 decides, the bundle check, and a sandboxed build for the owner to try on his folders. It needs ARC-22 on main.
6. **The direct download sandboxed,** last: its entitlements, Sparkle's installer service and exceptions, the release keeping `Installer.xpc`, the CLI finding the container, the cask's `zap`, the migration manifest; then the README's Known limitations and the comparison's Mac row.

Steps 2 to 4 change nothing in how an edit renders and fit 0.3.3. Steps 5 and 6 follow ARC-22 and question 2.

## Questions for the owner

1. **A photo opened on its own whose folder isn't granted.** Keep its edit on this Mac (the library's sidecars, DEC-43) and offer to grant the folder, after which Move Edits puts the edits beside the photos *(lean)*; or ask for the folder before the photo opens; or rename sidecars to `IMG_0001.redlamp`, which breaks existing sidecars and pairs.
2. **Both builds on one Mac.** Sandbox the direct download in the release the App Store build first ships, after the release that makes the bookmarks, so both share one container and settings and macOS asks once when switching *(lean)*; or give the App Store build its own bundle ID (reversing DEC-91), so the two keep apart and the App Store build ships sandboxed on its own schedule, with an import from the direct download's folder for people who switch.
3. **Which arriving volumes the import window offers,** since it can't see `DCIM` first: ejectable volumes not yet granted or declined, with Not a Card remembered by UUID *(lean)*; or none by themselves, cards chosen with File › Import Photos….

The owner chose the lean for each on 15 October 2026, and the plan goes ahead with them; ARC-17's row and DEC-91 record the answers.

## Sources

All read on 15 October 2026.

- Apple: [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox); [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox); [Migrating your app's files to its App Sandbox container](https://developer.apple.com/documentation/security/migrating-your-app-s-files-to-its-app-sandbox-container); [startAccessingSecurityScopedResource()](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()); [securityScopeAllowOnlyReadAccess](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/securityscopeallowonlyreadaccess); [primaryPresentedItemURL](https://developer.apple.com/documentation/foundation/nsfilepresenter/primarypresenteditemurl); [NSHomeDirectory()](https://developer.apple.com/documentation/foundation/nshomedirectory()); [ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore); [MetricKit](https://developer.apple.com/documentation/metrickit); [com.apple.security.application-groups](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups); [macOS 15 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes); [Embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app); [App Sandbox information in App Store Connect](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-sandbox-information); WWDC23 session 10053, [What's new in privacy](https://developer.apple.com/videos/play/wwdc2023/10053/).
- Apple's archive (snapshots of 20 September 2018): *App Sandbox Design Guide*, [Migrating an App to a Sandbox](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/MigratingALegacyApp/MigratingAnAppToASandbox.html) and [App Sandbox in Depth](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AppSandboxInDepth/AppSandboxInDepth.html); [Entitlement Key Reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html).
- Developer Forums, from Wayback snapshots: [798402](https://developer.apple.com/forums/thread/798402) (21 February 2026), [742147](https://developer.apple.com/forums/thread/742147) (7 August 2026), [721701](https://developer.apple.com/forums/thread/721701) (9 October 2026), [764435](https://developer.apple.com/forums/thread/764435) (19 December 2025).
- Sparkle: [Sandboxing](https://sparkle-project.org/documentation/sandboxing/); issues [1342](https://github.com/sparkle-project/Sparkle/issues/1342), [2098](https://github.com/sparkle-project/Sparkle/issues/2098), [2880](https://github.com/sparkle-project/Sparkle/issues/2880).
- Microsoft Security, [Analyzing CVE-2025-31191](https://www.microsoft.com/en-us/security/blog/2025/05/01/analyzing-cve-2025-31191-a-macos-security-scoped-bookmarks-based-sandbox-escape/) (1 May 2025).
- The spike: `scripts/sandbox-spike/`, run on macOS 26.6.2 (25G83).
