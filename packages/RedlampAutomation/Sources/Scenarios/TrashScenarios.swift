#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import Foundation
    import RedlampLibrary
    @_spi(Harness) import RedlampUI

    /// Move to Trash (LIB-46): the photo being edited, or the photos selected, to the Trash with their sidecars from a
    /// photo's menu in the grid and the filmstrip, ⌫ and ⌘⌫, the Photo menu and the palette, in Library and Develop;
    /// the
    /// photo after them active, opening in Develop, and the one before it at the end; ⌘Z and Put Back bringing them
    /// back. And ⌫'s other meanings, each photo staying where it is: a photo out of a collection and out of Marked, and
    /// the selected mask deleted, with nothing done in the Masking and Healing tools when nothing is selected. The
    /// photos
    /// are copies in the scratch folder, named for the run so the Trash holds no other of their names; none is left
    /// there.
    enum TrashScenarios {
        static let all: [Scenario] = [moveToTrash, deleteKey]

        static let moveToTrash = Scenario(
            "library.move-to-trash",
            "Move to Trash from the grid's and the filmstrip's menus, ⌫ and ⌘⌫ in Library and Develop, the Photo menu "
                + "and the palette: the photo after it active and open in Develop, the one before it at the end; ⌘Z "
                + "brings one back selected, and Put Back the rest",
            claims: [
                .action(.moveToTrash), .action(.undo), .action(.putBack), .action(.showRecentlyTrashed),
                .feature("library.rename"), .feature("library.folders"),
            ],
        ) { app in
            let token = UUID().uuidString.prefix(8)
            let names = ["A", "B", "C", "D", "E", "F", "G", "H"].map { "Trash \($0) \(token).jpg" }
            let (a, b, c, d, e, f, g, h) = (
                names[0],
                names[1],
                names[2],
                names[3],
                names[4],
                names[5],
                names[6],
                names[7],
            )
            let scratch = try DragScratch(app, names: names)
            let hides = try app.main { $0.filmstripHidesAutomatically }
            defer {
                try? app.main { $0.filmstripHidesAutomatically = hides }
                try? app.showRunPhotos()
                try? app
                    .wait("the scratch photos' saves", timeout: 30) { $0.unsavedPhotos(under: scratch.base).isEmpty }
                scratch.remove(app)
            }
            try scratch.show(app)
            func gone(_ name: String) -> Bool {
                !FileManager.default.fileExists(atPath: scratch.photo(name).path)
            }
            @MainActor func open(_ model: EditorModel, _ name: String) -> Bool {
                model.module == .develop && model.info?.url == scratch.photo(name)
            }

            // Library: the grid's menu moves A, with its sidecar, to the Trash, and B after it becomes active.
            try app.click(.identifier("grid.\(a)"))
            try app.wait("A alone") { $0.selectedPhotos.map(\.lastPathComponent) == [a] }
            try app.rightClick(.identifier("grid.\(a)"), choosing: ShortcutAction.moveToTrash.title)
            try app.wait("A and its sidecar in the Trash, B active", timeout: 30) { model in
                gone(a) && !scratch.files(in: scratch.folder).contains("\(a).redlamp")
                    && !model.items.contains { $0.name == a } && model.selection?.lastPathComponent == b
            }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }
            app.covered(.action(.moveToTrash), via: .mouse)

            // ⌫ moves B, the photo selected, and C becomes active; ⌘Z puts B back, selected.
            try app.press(KeyCombo(.delete))
            try app.wait("B in the Trash, C active", timeout: 30) { model in
                gone(b) && model.selection?.lastPathComponent == c
            }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }
            app.covered(.action(.moveToTrash), via: .key)
            try app.press(.undo)
            try app.run("the Undo", timeout: 60) { await $0.filesMade() }
            try app.wait("⌘Z to put B back, selected", timeout: 30) { model in
                !gone(b) && model.items.contains { $0.name == b } && model.selection?.lastPathComponent == b
            }

            // Develop: ⌫ moves the photo being edited, and the photo after it opens. The filmstrip stays up, as View ›
            // Filmstrip › Hide Automatically turned off keeps it, for its cells to be clicked.
            try app.click(.identifier("grid.\(e)"))
            try app.wait("E alone") { $0.selectedPhotos.map(\.lastPathComponent) == [e] }
            try app.main { $0.filmstripHidesAutomatically = false }
            try app.press(.developModule)
            try app.wait("E open in Develop", timeout: 30) { open($0, e) }
            try app.press(KeyCombo(.delete))
            try app.wait("E in the Trash, F open", timeout: 30) { model in gone(e) && open(model, f) }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }

            // The last photo: ⌘⌫, the Photo menu's key, moves H, and G before it opens.
            try app.wait("H in the filmstrip", timeout: 20) { _ in
                Views.editorWindow.flatMap { Views.find(Target.filmstrip(h).identifier, in: $0) } != nil
            }
            try app.click(.filmstrip(h))
            try app.wait("H open", timeout: 30) { open($0, h) }
            try app.press(.moveToTrash)
            try app.wait("H in the Trash, G open", timeout: 30) { model in gone(h) && open(model, g) }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }

            // The filmstrip's menu on D, which isn't selected, moves D alone, and G stays open.
            try app.rightClick(.filmstrip(d), choosing: ShortcutAction.moveToTrash.title)
            try app.wait("D in the Trash, G still open", timeout: 30) { model in gone(d) && open(model, g) }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }

            // The Photo menu moves G, then the palette F, each the last, the one before it opening.
            try app.choose(.moveToTrash)
            try app.wait("G in the Trash, F open", timeout: 30) { model in gone(g) && open(model, f) }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }
            try app.runFromPalette(.moveToTrash)
            try app.wait("F in the Trash, C open", timeout: 30) { model in gone(f) && open(model, c) }
            try app.run("the batch", timeout: 60) { await $0.filesMade() }

            // Recently Trashed: a photo's menu puts A back with its sidecar, then ⌘⌫, Put Back's key there, the rest.
            try app.runFromPalette(.showRecentlyTrashed)
            try app.wait("Recently Trashed with the six", timeout: 30) { model in
                model.library.showsRecentlyTrashed && model.items.count == 6
            }
            let place = try app.main { model -> String? in
                model.items.first { model.library.trashedPhoto(at: $0.url)?.original == scratch.photo(a).path }?.name
            }
            guard let shown = place else { throw ScenarioFailure("Recently Trashed doesn't list A") }
            try app.wait("A in the filmstrip") { _ in
                Views.editorWindow.flatMap { Views.find(Target.filmstrip(shown).identifier, in: $0) } != nil
            }
            try app.rightClick(.filmstrip(shown), choosing: ShortcutAction.putBack.title)
            try app.wait("A back with its sidecar", timeout: 30) { model in
                !gone(a) && scratch.files(in: scratch.folder).contains("\(a).redlamp") && model.items.count == 5
            }
            app.covered(.action(.putBack), via: .mouse)
            try app.main { $0.selectAllPhotos() }
            try app.press(.putBack)
            try app.wait("every photo back where it was", timeout: 30) { model in
                names.allSatisfy { !gone($0) } && model.items.isEmpty && model.library.trashedCount == 0
            }
        }

        static let deleteKey = Scenario(
            "library.delete-key",
            "⌫ takes a photo out of a collection and the mark off it in Marked, and deletes the selected mask, each "
                + "photo staying; in the Masking and Healing tools with nothing selected it does nothing",
            claims: [
                .action(.removeFromCollection), .action(.deleteMask), .mask(.linear), .feature("library.collections"),
                .feature("library.ratings"),
            ],
        ) { app in
            let token = UUID().uuidString.prefix(8)
            let names = ["A", "B", "C"].map { "Delete \($0) \(token).jpg" }
            let (a, b, c) = (names[0], names[1], names[2])
            let scratch = try DragScratch(app, names: names)
            let collection = "Delete Key \(token)"
            defer {
                try? app.main { model in
                    if let path = CollectionPath(collection) {
                        model.librarySources.delete(path)
                    }
                    model.activeTool = .edit
                }
                try? app.run("the collection deleted", timeout: 30) { await $0.libraryPanels.written() }
                try? app.showRunPhotos()
                try? app
                    .wait("the scratch photos' saves", timeout: 30) { $0.unsavedPhotos(under: scratch.base).isEmpty }
                scratch.remove(app)
            }
            try scratch.show(app)
            func stays(_ name: String) -> Bool {
                FileManager.default.fileExists(atPath: scratch.photo(name).path)
            }

            // A collection with A and B: ⌫ takes A out of it, and A stays in its folder.
            try app.main { model in
                model.select(scratch.photo(a))
                model.click(scratch.photo(b), toggling: true)
            }
            try app.wait("A and B selected") { $0.selectedPhotos.count == 2 }
            try app.main { model in
                _ = model.librarySources.create(.collection, named: collection, adding: true)
            }
            try app.wait("the collection with A and B", timeout: 30) { _ in
                app.sourceRowLabel("collections.\(collection)") == "\(collection), 2 photos"
            }
            try app.clickSourceRow("collections.\(collection)")
            try app.waitForSource("the collection shown", timeout: 20) { model in
                !model.librarySources.isListing && model.items.count == 2
            }
            try app.main { $0.select(scratch.photo(a)) }
            try app.press(KeyCombo(.delete))
            try app.wait("A out of the collection", timeout: 30) { $0.items.map(\.name) == [b] }
            try app.expect(stays(a), "A left its folder")
            app.covered([.action(.removeFromCollection), .feature("library.collections")], via: .key)

            // Marked: C marked with B, then ⌫ there takes the mark off, and C stays in its folder.
            try app.main { $0.showFolder(scratch.folder) }
            try app.wait("the folder again", timeout: 30) { model in
                model.folder == scratch.folder && !model.library.isListing && model.items.count == names.count
            }
            try app.click(.identifier("grid.\(c)"))
            try app.wait("C alone") { $0.selectedPhotos.map(\.lastPathComponent) == [c] }
            try app.press(.toggleMark)
            try app.wait("C marked", timeout: 30) { $0.library.item(for: scratch.photo(c))?.metadata.mark == true }
            try app.wait("Marked counted with C, Show Marked on", timeout: 30) { $0.canPerform(.showMarked) }
            try app.press(.showMarked)
            try app.waitForSource("Marked with C", timeout: 30) { model in
                model.librarySources.shown == .marked && !model.librarySources.isListing
                    && model.items.contains { $0.name == c }
            }
            try app.main { $0.select(scratch.photo(c)) }
            try app.press(KeyCombo(.delete))
            try app.wait("C out of Marked", timeout: 30) { model in
                !model.isWritingCulling && !model.items.contains { $0.name == c }
            }
            try app.expect(stays(c), "C left its folder")
            app.covered(.feature("library.ratings"), via: .key)

            // Develop: a gradient, selected, deleted by ⌫; then ⌫ in the Masking and Healing tools with nothing
            // selected, the photo staying open.
            try app.main { $0.showFolder(scratch.folder) }
            try app.wait("the folder again", timeout: 30) { model in
                model.folder == scratch.folder && !model.library.isListing && model.items.count == names.count
            }
            try app.click(.identifier("grid.\(b)"))
            try app.wait("B alone") { $0.selectedPhotos.map(\.lastPathComponent) == [b] }
            try app.press(.developModule)
            try app.wait("B open in Develop", timeout: 30) { $0.module == .develop && $0.info?.url == scratch.photo(b) }
            try app.drawGradient(.linear)
            try app.wait("the gradient selected") { $0.selectedMaskID != nil && $0.activeTool == .masking }
            try app.press(KeyCombo(.delete))
            try app.wait("⌫ to delete the mask") { $0.masks.isEmpty }
            app.covered(.action(.deleteMask), via: .key)
            try app.press(KeyCombo(.delete))
            try app.press(.healTool)
            try app.wait("the Healing tool") { $0.activeTool == .heal }
            try app.press(KeyCombo(.delete))
            app.pause(0.5)
            try app.run("anything asked for", timeout: 30) { await $0.filesMade() }
            let left = try app.main { model in model.info?.url == scratch.photo(b) && model.module == .develop }
            try app.expect(stays(b) && left, "⌫ with nothing selected in the tools took the photo")
        }
    }
#endif
