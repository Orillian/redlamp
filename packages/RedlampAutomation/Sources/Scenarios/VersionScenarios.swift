#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import Foundation
    import ImageIO
    import RedlampDocument
    import RedlampEngineAPI
    import RedlampLibrary
    @_spi(Harness) import RedlampUI

    /// Versions of a photo's edit (EDT-09), as Lightroom Classic's virtual copies are: made with ⌘', opened, renamed
    /// and removed from the Photo menu, and kept through saving, opening the photo again, Sync and export; and in the
    /// library (LIB-48), each a photo of its own beside its file.
    enum VersionScenarios {
        static let all: [Scenario] = [versions, library]

        static let versions = Scenario(
            "develop.versions",
            "A version is another edit of the photo, kept through saving, reopening, Sync and export",
            claims: [.action(.createVersion)],
        ) { app in
            try app.openRaw(1)
            let name = try app.main { $0.selection?.lastPathComponent ?? "" }
            try app.set(.exposure, 0.3)

            try app.press(.createVersion)
            try app.wait("Copy 1, open") { $0.versions.map(\.name) == ["Copy 1"] && $0.openVersion != nil }
            try app.expect(try app.main { abs($0.value(.exposure) - 0.3) < 1e-6 }, "Copy 1 isn't the edit it copied")
            try app.set(.contrast, 25)

            try app.choose(EditorModel.originalName)
            try app.wait("the photo's own edit") { $0.openVersion == nil && $0.value(.contrast) == 0 }
            try app.choose("Copy 1")
            try app.wait("Copy 1 again") { $0.openVersion != nil && abs($0.value(.contrast) - 25) < 1e-6 }

            try app.choose("Rename Version…")
            try app.waitForSheet("Rename Version")
            try app.selectSheetField()
            try app.typeInAttachedSheet("Contrast")
            try app.pressInSheet(KeyCombo(.character("\r")))
            try app.waitForNoSheet("Rename Version")
            try app.wait("the new name") { $0.versions.map(\.name) == ["Contrast"] }
            try app.waitSaved(name, containing: "\"name\" : \"Contrast\"")

            // Opening the photo again opens its own edit, with the version beside it.
            try app.openRaw(2)
            try app.openRaw(1)
            try app.wait("the photo with its version") { model in
                model.selection?.lastPathComponent == name && model.versions.map(\.name) == ["Contrast"]
                    && model.openVersion == nil && abs(model.value(.exposure) - 0.3) < 1e-6
            }
            try app.choose("Contrast")
            try app.wait("the version's edit") { $0.openVersion != nil && abs($0.value(.contrast) - 25) < 1e-6 }

            try syncsFromVersion(app, open: name)
            try exportsVersion(app)

            try app.choose("Remove Version…")
            try app.waitForSheet("Remove Version")
            try app.pressInSheet(KeyCombo(.character("\r")))
            try app.waitForNoSheet("Remove Version")
            try app.wait("the version removed") { $0.versions.isEmpty && $0.openVersion == nil }
            try app.wait("the sidecar without it", timeout: 15) { _ in !app.sidecarJSON(name).contains("\"versions\"") }
            try app.choose(.resetAll)
            app.covered(.action(.createVersion), via: .key)
        }

        /// Sync Settings from the version open onto the rest of the folder, then Undo Sync.
        private static func syncsFromVersion(_ app: RunningApp, open name: String) throws {
            let other = try app.photoNames().first { $0 != name && $0.uppercased().hasSuffix(".NEF") }
                ?? app.photoNames().first { $0 != name } ?? ""
            try app.choose(.selectAllPhotos)
            try app.wait("every photo selected") { $0.selectedPhotos.count == $0.items.count }
            try app.choose(.syncSettingsAgain)
            try app.wait("the sync", timeout: 180) { $0.settingsSync.progress == nil && $0.settingsSync.canUndo }
            try app.expect(
                app.sidecarJSON(other).contains("basic.contrast"), "\(other) didn't get the version's Contrast",
            )
            try app.expect(try app.main { $0.openVersion != nil }, "Sync left the version")
            try app.choose(.undoSync)
            try app.wait("Undo Sync", timeout: 180) { $0.settingsSync.progress == nil && !$0.settingsSync.canUndo }
            try app.choose(.deselectOtherPhotos)
        }

        /// Exports the version open, rated as the photo isn't, named by its name, and finds its edit and its rating in
        /// the file.
        private static func exportsVersion(_ app: RunningApp) throws {
            try app.press(.rating4)
            try app.wait("the version's rating") { $0.openVersion != nil && $0.photoMetadata.rating == 4 }
            try app.wait("the library to open", timeout: 60) { $0.library.service?.isReady == true }
            let settings = try app.host.map { host in try app.main { _ in host.exports.initialSettings } }
                ?? ExportSettings()
            let folder = settings.destinationFolder ?? app.photos
            let file = folder.appending(path: "Version-Contrast.\(settings.format.fileExtension)")
            try? FileManager.default.removeItem(at: file)
            defer { try? FileManager.default.removeItem(at: file) }
            try app.choose(Menus.title(of: .export))
            try app.waitForSheet("the Export dialog")
            app.pause(0.5)
            try app.clickInSheet("export.naming")
            try app.selectSheetField()
            try app.typeInAttachedSheet("Version-{version}")
            app.pause(0.5)
            try app.expect(
                try app.pressInSheet(KeyCombo(.character("\r"))),
                "The Export dialog's Export button didn't take Return",
            )
            try app.waitForNoSheet("the Export dialog")
            try app.wait("the export", timeout: 120) { _ in FileManager.default.fileExists(atPath: file.path) }
            try app.wait("the export written", timeout: 30) { _ in EmbeddedEdit.read(file) != nil }
            let contrast = EmbeddedEdit.read(file)?.recipe[.contrast]
            try app.expect(contrast == 25, "The export carries Contrast \(contrast.map { "\($0)" } ?? "none"), not 25")
            let rating = CGImageSourceCreateWithURL(file as CFURL, nil)
                .flatMap { CGImageSourceCopyMetadataAtIndex($0, 0, nil) }
                .flatMap { CGImageMetadataCopyStringValueWithPath($0, nil, "xmp:Rating" as CFString) as String? }
            try app.expect(rating == "4", "The export's rating is \(rating ?? "none"), not the version's 4")
        }

        static let library = Scenario(
            "library.versions",
            "A version made in Develop with ⌘' is a photo of its own in Library, beside its file: rated, flagged, "
                + "marked and keyworded alone by the grid's keys and its menu, left out or shown alone by Copy Status, "
                + "renamed in the Metadata panel's Copy Name and from Photo › Versions, moved with its file to another "
                + "folder and back with ⌘Z, and opened in Develop from the grid in its own edit",
            claims: [
                .action(.createVersion), .action(.rating3), .action(.flagPick), .action(.toggleMark),
                .action(.keywordSet1), .action(.moveToFolder), .action(.undo), .action(.editTool),
                .feature("library.grid"), .feature("library.ratings"), .feature("library.keywords"),
                .feature("library.filter"), .feature("library.metadata"), .feature("library.rename"),
            ],
        ) { app in
            let token = UUID().uuidString.prefix(8)
            let (a, b) = ("Versions A \(token).jpg", "Versions B \(token).jpg")
            let scratch = try DragScratch(app, names: [a, b])
            let photo = scratch.photo(b)
            let panel = try app.main { model in
                (model.rightPanelVisible, model.libraryPanels.isExpanded(.metadata))
            }
            defer {
                try? app.main { model in
                    model.libraryFilters?.setFilter(LibraryFilter())
                    model.rightPanelVisible = panel.0
                    if model.libraryPanels.isExpanded(.metadata) != panel.1 {
                        model.libraryPanels.toggle(.metadata)
                    }
                }
                try? app.choose(KeywordSet.recentName)
                try? app.showRunPhotos()
                try? app
                    .wait("the scratch photos' saves", timeout: 30) { $0.unsavedPhotos(under: scratch.base).isEmpty }
                scratch.remove(app)
            }
            try scratch.show(app)

            // Develop: ⌘' makes Copy 1 of B, given a Contrast of its own.
            try app.click(.identifier("grid.\(b)"))
            try app.wait("B alone") { $0.selectedPhotos.map(\.lastPathComponent) == [b] }
            try app.press(.editTool)
            try app.wait("B open in Develop", timeout: 30) { model in
                model.module == .develop && model.info?.url == photo
            }
            try app.press(.createVersion)
            try app.wait("Copy 1, open") { $0.versions.map(\.name) == ["Copy 1"] && $0.openVersion != nil }
            let id = try app.main { $0.openVersion } ?? UUID()
            let version = PhotoAddress(url: photo, version: id)
            try app.set(.contrast, 25)
            app.covered(.action(.createVersion), via: .key)

            // Library: the version's cell after B's, its tooltip naming it and its file.
            try app.press(.gridView)
            try app.wait("Library's grid") { $0.module == .library && $0.libraryView == .grid }
            try app.wait("the version beside B", timeout: 30) { model in
                let own = model.library.index(of: PhotoAddress(url: photo))
                return own != nil && model.library.index(of: version) == own.map { $0 + 1 }
                    && Self.item(version, in: model)?.title == "Copy 1, a version of \(b)"
            }
            try app.waitForCell(version)
            app.covered(.feature("library.grid"), via: .mouse)

            // Culled alone, one by one, B's own row as it was: 3 rates it, P flags it, the cell's menu marks it, and ⌥1
            // gives it the keyword set's first keyword.
            try app.clickCell(version)
            try app.press(.rating3)
            try app.wait("the version rated 3", timeout: 30) { model in
                Self.item(version, in: model)?.metadata.rating == 3
            }
            try app.press(.flagPick)
            try app.wait("the version picked", timeout: 30) { Self.item(version, in: $0)?.metadata.flag == .pick }
            let mark = ShortcutAction.toggleMark
            try app.rightClick(
                .identifier(app.cellIdentifier(version)),
                choosing: mark.title + (mark.combos.first.map { "    \($0.display)" } ?? ""),
            )
            try app.wait("the version marked", timeout: 30) { Self.item(version, in: $0)?.metadata.mark == true }
            app.covered(.action(.toggleMark), via: .mouse)
            try app.choose("Wedding Photography")
            try app.wait("the wedding set chosen") { $0.libraryPanels.activeSet?.name == "Wedding Photography" }
            let keyword = try app.main { $0.libraryPanels.activeSet?.keyword(forShortcut: 1) }
            guard let keyword else { throw ScenarioFailure("The wedding set has no first keyword") }
            try app.clickCell(version)
            try app.press(.keywordSet1)
            try app.wait("⌥1 to give the version \(keyword.name)", timeout: 30) { model in
                model.libraryPanels.selection.hasEverywhere(keyword) == true
            }
            try app.waitForPanels()
            @MainActor func culled(_ model: EditorModel) -> Bool {
                let edit = Self.sidecar(of: photo, in: model)?[edit: id]?.metadata
                return edit?.rating == 3 && edit?.flag == .pick && edit?.mark == true
                    && edit?.keywords?.contains(keyword.text) == true
            }
            _ = try? app.wait("the version's culling saved", timeout: 30, until: culled)
            let (saved, own, ids) = try app.main { model in
                (
                    Self.sidecar(of: photo, in: model)?[edit: id]?.metadata,
                    Self.sidecar(of: photo, in: model)?.metadata,
                    "the panels' \(model.libraryPanels.selection.ids), the selection's \(model.selectedIDs)",
                )
            }
            try app.expect(
                try app.main(culled),
                "The version's sidecar holds rating \(saved?.rating ?? 0), flag \(String(describing: saved?.flag)), "
                    + "mark \(saved?.mark ?? false) and keywords \(saved?.keywords ?? []), not 3, pick, a mark and "
                    + "\(keyword.text); B's own keywords \(own?.keywords ?? []); \(ids)",
            )
            try app.expect(
                (own?.rating ?? 0) == 0 && own?.flag == nil && own?.mark != true && (own?.keywords ?? []).isEmpty,
                "B's own metadata changed with its version's: \(String(describing: own))",
            )
            try app.wait("B's own row as it was") { model in
                let row = Self.item(PhotoAddress(url: photo), in: model)?.metadata
                return row?.rating == 0 && row?.flag == nil && row?.mark == false
            }
            app.covered(
                [
                    .action(.rating3),
                    .action(.flagPick),
                    .action(.keywordSet1),
                    .feature("library.ratings"),
                    .feature("library.keywords"),
                ],
                via: .key,
            )

            try copyStatus(app, version: version, file: photo, other: scratch.photo(a))
            try rename(app, version)
            try moves(app, version, scratch: scratch)

            // Opened in Develop from the grid: D shows the version's own edit, and its file's own beside it.
            try app.clickCell(version)
            try app.wait("the version active") { $0.activeAddress == version }
            try app.press(.editTool)
            try app.wait("the version open in Develop, in its own edit", timeout: 30) { model in
                model.module == .develop && model.info?.url == photo
                    && model.openVersion == id && abs(model.value(.contrast) - 25) < 1e-6
            }
            app.covered(.action(.editTool), via: .key)
            try app.choose(EditorModel.originalName)
            try app.wait("B's own edit") { $0.openVersion == nil && $0.value(.contrast) == 0 }
        }

        /// The filter bar's Copy Status: Originals leaves the version out, Versions shows it alone.
        private static func copyStatus(_ app: RunningApp, version: PhotoAddress, file: URL, other: URL) throws {
            let all = Set([PhotoAddress(url: other), PhotoAddress(url: file), version])
            if try !app.main({ $0.libraryFilters?.isBarShown ?? false }) {
                try app.press(.toggleFilterBar)
            }
            try app.wait("the filter bar") { $0.libraryFilters?.isBarShown == true }
            if try !app.main({ $0.libraryFilters?.filter.sections.contains(.attribute) ?? false }) {
                try app.clickButton("library.filter.attribute")
            }
            try app.wait("the Attribute row") { $0.libraryFilters?.filter.sections.contains(.attribute) == true }
            try app.clickButton("library.filter.original")
            try app.wait("Originals: A and B, without the version", timeout: 30) { model in
                Set(model.items.map(\.address)) == all.subtracting([version])
            }
            try app.clickButton("library.filter.version")
            try app.wait("Versions: the version alone", timeout: 30) { model in
                model.items.map(\.address) == [version]
            }
            try app.clickButton("library.filter.version")
            try app.wait("every photo again", timeout: 30) { Set($0.items.map(\.address)) == all }
            app.covered(.feature("library.filter"), via: .mouse)
            try app.leaveFilterText()
            try app.press(.toggleFilterBar)
            try app.wait("the filter bar away") { $0.libraryFilters?.isBarShown == false }
        }

        /// Renamed in the Metadata panel's Copy Name, ⌘Z giving it its name back, then from Photo › Versions ›
        /// Rename Version…; its sidecar, its row and its cell following each.
        private static func rename(_ app: RunningApp, _ version: PhotoAddress) throws {
            try app.main { model in
                model.rightPanelVisible = true
                if !model.libraryPanels.isExpanded(.metadata) {
                    model.libraryPanels.toggle(.metadata)
                }
            }
            try app.clickCell(version)
            try app.wait("Copy Name with the version's name") { _ in
                Views.editorWindow.flatMap { Views.shown("metadata.copyName", in: $0) as? NSTextField }?
                    .stringValue == "Copy 1"
            }
            // The click puts the insertion point after the name, which ⌫ takes back.
            try app.clickControl("metadata.copyName", across: 0.9)
            try app.wait("Copy Name to take the keyboard") { _ in RunningApp.editedText("metadata.copyName") != nil }
            for _ in "Copy 1" {
                try app.pressInWindow(KeyCombo(.delete))
            }
            try app.typeQuery("Contrast")
            try app.pressInWindow(KeyCombo(.character("\r")))
            try renamed(app, version, "Contrast")
            app.covered(.feature("library.metadata"), via: .key)

            try app.clickCell(version)
            try app.press(.undo)
            try renamed(app, version, "Copy 1")
            app.covered(.action(.undo), via: .key)

            try app.choose("Rename Version…")
            try app.waitForSheet("Rename Version")
            try app.selectSheetField()
            try app.typeInAttachedSheet("Portrait")
            try app.pressInSheet(KeyCombo(.character("\r")))
            try app.waitForNoSheet("Rename Version")
            try renamed(app, version, "Portrait")
        }

        /// Waits for `name` in the version's sidecar, on its row and on its cell.
        private static func renamed(_ app: RunningApp, _ version: PhotoAddress, _ name: String) throws {
            try app.wait("“\(name)” in the sidecar", timeout: 30) { model in
                sidecar(of: version.url, in: model)?.versions.first { $0.id == version.version }?.name == name
            }
            try app.wait("the version's row named “\(name)”", timeout: 30) { model in
                item(version, in: model)?.title == "\(name), a version of \(version.url.lastPathComponent)"
            }
            try app.waitForCell(version)
        }

        /// B moved to Picked by Photo › Move to Folder…, its version going with it, and ⌘Z bringing both back.
        private static func moves(_ app: RunningApp, _ version: PhotoAddress, scratch: DragScratch) throws {
            let photo = version.url
            let moved = scratch.picked.appending(path: photo.lastPathComponent)
            try app.click(.identifier("grid.\(photo.lastPathComponent)"))
            try app.wait("B's own row alone") { $0.activeAddress == PhotoAddress(url: photo) && $0.selectedCount == 1 }
            try app.main { _ in EditorModel.moveToFolderAnswer = scratch.picked }
            try app.choose(.moveToFolder)
            try app.wait("B in Picked with its version", timeout: 60) { model in
                !FileManager.default.fileExists(atPath: photo.path)
                    && sidecar(of: moved, in: model)?.versions.contains { $0.id == version.version } == true
            }
            try app.run("the move", timeout: 60) { await $0.filesMade() }
            try app.wait("the grid without B and its version", timeout: 30) { model in
                model.library.index(of: PhotoAddress(url: photo)) == nil && model.library.index(of: version) == nil
            }
            app.covered([.action(.moveToFolder), .feature("library.rename")], via: .menu)

            try app.press(.undo)
            try app.run("the Undo", timeout: 60) { await $0.filesMade() }
            try app.wait("⌘Z to bring B back with its version", timeout: 30) { model in
                FileManager.default.fileExists(atPath: photo.path) && !FileManager.default
                    .fileExists(atPath: moved.path)
                    && model.library.index(of: PhotoAddress(url: photo)) != nil
                    && model.library.index(of: version) == model.library.index(of: PhotoAddress(url: photo))
                    .map { $0 + 1 }
            }
            try app.waitForCell(version)
        }

        /// The item the library shows for `photo`.
        @MainActor private static func item(_ photo: PhotoAddress, in model: EditorModel) -> RedlampUI.LibraryItem? {
            model.library.index(of: photo).map { model.items[$0] }
        }

        /// The sidecar of `photo` as it is on disk, where the library keeps it.
        @MainActor private static func sidecar(of photo: URL, in model: EditorModel) -> Sidecar? {
            model.library.sidecars.store(for: photo).load(for: photo)
        }
    }

    extension RunningApp {
        /// The accessibility identifier of the grid's cell of `photo`, a version's naming the version as its row does.
        func cellIdentifier(_ photo: PhotoAddress) throws -> String {
            try main { model in
                let item = model.library.index(of: photo).map { model.items[$0] }
                let name = photo.url.lastPathComponent
                return "grid." + (photo.version == nil ? name : "\(name):\(item?.versionName ?? "")")
            }
        }

        /// Waits for the grid's cell of `photo` on screen.
        func waitForCell(_ photo: PhotoAddress) throws {
            let identifier = try cellIdentifier(photo)
            try wait("\(identifier) on screen", timeout: 20) { _ in
                Views.editorWindow.flatMap { Views.find(identifier, in: $0) } != nil
            }
        }

        /// Clicks the grid's cell of `photo`, which is then the only photo selected.
        func clickCell(_ photo: PhotoAddress) throws {
            try waitForCell(photo)
            try click(.identifier(cellIdentifier(photo)))
            try wait("\(photo.url.lastPathComponent) alone") { $0.activeAddress == photo && $0.selectedCount == 1 }
        }
    }
#endif
