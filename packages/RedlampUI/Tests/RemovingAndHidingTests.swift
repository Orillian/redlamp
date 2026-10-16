import AppKit
import Foundation
import RedlampDesign
import RedlampEngineAPI
import RedlampRecipes
import Testing
@_spi(Harness) @testable import RedlampUI

/// Removing and hiding recipes and looks (UX-55): Show in Finder and Move to Trash for your own and installed
/// recipes and imported looks, Remove from Base Looks for an installed look no recipe uses, and Hide for the
/// built-in folders, shown again from the panels' header menus. Serialized: Show in Finder is noted through
/// `RecipeActions.reveal`, which is shared.
@MainActor
@Suite(.serialized)
struct RemovingAndHidingTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "removing-\(UUID().uuidString)")

    private var trash: URL {
        root.appending(path: "Trash")
    }

    /// The test's library, whose Trash is a folder of the test's own; made again, it's the library after a relaunch.
    private func library() -> RecipeLibrary {
        let library = RecipeLibrary(root: root.appending(path: "Library"))
        let folder = trash
        library.trash = { url in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let moved = folder.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: moved)
            return moved
        }
        return library
    }

    /// An editor with a photo open, its recipes kept in the test's library, and `engine`'s camera profiles listed.
    private func openEditor(_ engine: StubEngine = StubEngine()) async throws -> EditorModel {
        let folder = root.appending(path: "Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        engine.camera = ("Canon", "EOS R5")
        let model = EditorModel(engine: engine, recipes: RecipeCatalog(engine: engine, library: library()))
        let url = folder.appending(path: "IMG_0001.CR3")
        model.select(url)
        try await eventually { model.info != nil && model.cameraProfilesPhoto == url }
        try #require(model.info != nil)
        return model
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func showLists(_ model: EditorModel) -> (SidebarListView, NSWindow) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 800), styleMask: [.titled], backing: .buffered,
            defer: false,
        )
        let list = SidebarListView(model: model)
        window.contentView = list
        list.layoutSubtreeIfNeeded()
        return (list, window)
    }

    /// The titles of a row's right-click menu, separators left out; none when it has no menu.
    private func menu(_ kind: SidebarNode.Kind, _ model: EditorModel) -> [String] {
        (SidebarCellView(node: SidebarNode(kind), model: model).contextMenu()?.items ?? [])
            .filter { !$0.isSeparatorItem }.map(\.title)
    }

    /// Chooses `title` in a row's right-click menu.
    private func choose(_ title: String, in kind: SidebarNode.Kind, _ model: EditorModel) throws {
        let menu = try #require(SidebarCellView(node: SidebarNode(kind), model: model).contextMenu())
        try menu.performActionForItem(at: #require(menu.items.firstIndex { $0.title == title }))
    }

    /// The folders a panel's list shows, by name.
    private func folders(_ outline: SidebarOutlineView) -> [String] {
        (0 ..< outline.numberOfRows).compactMap {
            if case let .group(name, _, _)? = (outline.item(atRow: $0) as? SidebarNode)?.kind {
                name
            } else {
                nil
            }
        }
    }

    private func entries(_ model: EditorModel) -> [LookEntry] {
        BaseLookFolders.folders(model).flatMap(\.allEntries)
    }

    /// Imports a look table, which Base Looks lists under Imported.
    private func importLUT(_ name: String, into model: EditorModel) throws -> Recipe {
        let cube = root.appending(path: "\(name).cube")
        var lines = ["TITLE \"\(name)\"", "LUT_3D_SIZE 2"]
        for b in 0 ... 1 {
            for g in 0 ... 1 {
                for r in 0 ... 1 {
                    lines.append("\(Double(r)) \(Double(g) * 0.95) \(Double(b) * 0.9)")
                }
            }
        }
        try lines.joined(separator: "\n").write(to: cube, atomically: true, encoding: .utf8)
        let summary = model.recipes.install(RecipeLibrary.read(importing: [cube], reading: UnreadableFiles()))
        return try #require(summary.imported.first?.recipe)
    }

    /// Notes what Show in Finder shows while `body` runs, rather than opening Finder.
    private func revealed(_ body: () throws -> Void) rethrows -> [URL] {
        var shown: [URL] = []
        let reveal = RecipeActions.reveal
        RecipeActions.reveal = { shown += $0 }
        defer { RecipeActions.reveal = reveal }
        try body()
        return shown
    }

    // MARK: - Show in Finder and Move to Trash

    @Test func `a recipe's menu shows yours and installed ones in Finder and moves them to the Trash, not a bundled one`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let punchy = try #require(model.recipes.presets.first { $0.name == "Punchy" })
        let bundled = menu(.recipe(punchy), model)
        #expect(bundled.first == "Add to Favorites")
        #expect(!bundled.contains("Show in Finder") && !bundled.contains("Move to Trash") && !bundled
            .contains("Delete Recipe"))

        let mine = try #require(model.recipes.save(Recipe(
            id: RecipeNamespace.newLocalID(), name: "Bright", group: "Trips", includes: [.tone],
            settings: RecipeSettings(values: [.exposure: 0.3]),
        )))
        try model.recipes.library.install(RecipeImport(recipe: Recipe(
            id: "someone/warm", name: "Warm", group: "Theirs", includes: [.tone],
            settings: RecipeSettings(values: [.exposure: 0.1]),
        )))
        model.recipes.reload()
        let installed = try #require(model.recipes.recipe(id: "someone/warm"))
        for recipe in [mine, installed] {
            let items = menu(.recipe(recipe), model)
            #expect(Array(items.suffix(2)) == ["Show in Finder", "Move to Trash"], "\(recipe.name)")
            #expect(!items.contains("Delete Recipe"), "Move to Trash replaces it")
        }

        let shown = try revealed { try choose("Show in Finder", in: .recipe(installed), model) }
        let file = try #require(model.recipes.file(of: installed))
        #expect(shown == [file])
        #expect(file.deletingLastPathComponent().standardizedFileURL
            == model.recipes.library.locations.installed.standardizedFileURL)
        let mineFile = try #require(model.recipes.file(of: mine))
        #expect(try revealed { try choose("Show in Finder", in: .recipe(mine), model) } == [mineFile])

        try choose("Move to Trash", in: .recipe(mine), model)
        #expect(model.recipes.recipe(id: mine.id) == nil && !model.recipes.sections.contains { $0.name == "Trips" })
        #expect(!FileManager.default.fileExists(atPath: mineFile.path))
        #expect(FileManager.default.fileExists(atPath: trash.appending(path: mineFile.lastPathComponent).path))
        try choose("Move to Trash", in: .recipe(installed), model)
        #expect(model.recipes.recipe(id: installed.id) == nil)
        #expect(!model.recipes.sections.contains { $0.name == "Installed" })
    }

    @Test func `an imported look moved to the Trash keeps rendering in the photo, and is listed nowhere`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let lut = try importLUT("Teal Night", into: model)
        let entry = try #require(entries(model).first { $0.recipe?.id == lut.id })
        #expect(entry.folder == RecipeLibrary.importedLooksFolder)
        #expect(menu(.look(entry, current: false, showsFolder: false), model)
            == ["Add to Favorites", "Show in Finder", "Move to Trash"])
        for name in ["Redlamp Vivid", "Portra 400", "Redlamp Reproduction"] {
            let builtIn = try #require(entries(model).first { $0.name == name })
            let items = menu(.look(builtIn, current: false, showsFolder: false), model)
            #expect(
                !items.contains("Show in Finder") && !items.contains("Move to Trash")
                    && !items.contains("Remove from Base Looks"),
                "\(name)",
            )
        }

        model.chooseLook(entry.choice(in: model))
        let look = model.baseLook
        #expect(look.id == entry.look.id)
        let file = try #require(model.recipes.file(of: lut))
        #expect(
            try revealed { try choose("Show in Finder", in: .look(entry, current: true, showsFolder: false), model) }
                == [file],
            "the recipe that holds the look",
        )

        try choose("Move to Trash", in: .look(entry, current: true, showsFolder: false), model)
        #expect(model.recipes.recipe(id: lut.id) == nil)
        #expect(FileManager.default.fileExists(atPath: trash.appending(path: file.lastPathComponent).path))
        #expect(model.baseLook.id == look.id && !model.isBaseLookMissing, "the photo keeps rendering with it")
        #expect(!entries(model).contains { $0.look.id == look.id }, "Base Looks lists it nowhere")
        #expect(
            !BaseLookGroups.current(in: model.recipes).sections.contains { $0.looks.contains { $0.id == look.id } },
            "Basic's menu doesn't bring it back under Installed",
        )
        #expect(!PaletteCatalog.choiceItems(.baseLook, editor: model).map(\.kind).contains(.baseLook(look.id)))
    }

    @Test func `an installed look no recipe uses has Remove from Base Looks, which lists it nowhere and keeps its file`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let lut = try importLUT("Old Grade", into: model)
        model.recipes.delete(lut)
        let look = try #require(lut.baseLook)
        let entry = try #require(entries(model).first { $0.look.id == look.id })
        #expect(entry.recipe == nil && entry.folder == RecipeLibrary.importedLooksFolder, "left by Delete Recipe")
        #expect(menu(.look(entry, current: false, showsFolder: false), model)
            == ["Add to Favorites", "Remove from Base Looks"])

        try choose("Remove from Base Looks", in: .look(entry, current: false, showsFolder: false), model)
        #expect(!entries(model).contains { $0.look.id == look.id })
        #expect(!BaseLookGroups.current(in: model.recipes).sections.contains { $0.looks.contains { $0.id == look.id } })
        #expect(model.recipes.library.storedLooks.contains { $0.matches(look) }, "its file stays for its edits")
        #expect(model.recipes.isAvailable(look))
    }

    // MARK: - Hiding folders

    @Test func `a built-in folder's menu has Hide, Film Stocks' after Open Film Looks, and the other folders' none`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        #expect(BaseLookFolders.builtIn == [
            "Adobe Raw", "Camera Matching", "Creative", "Redlamp", "Film Styles", "Film Stocks", "Firmware Model",
            "Reproduction",
        ])
        for name in BaseLookFolders.builtIn where name != FilmLookCatalog.group {
            #expect(menu(.group(name, count: 1, panel: .baseLooks), model) == ["Hide “\(name)”"])
        }
        #expect(menu(.group(FilmLookCatalog.group, count: 36, panel: .baseLooks), model)
            == ["Open Film Looks", "Hide “Film Stocks”"])
        let notBuiltIn = [
            BaseLookFolders.favorites, BaseLookFolders.inThisPhoto, "Your Profiles", "Vintage", FujifilmLUT.group,
            RecipeLibrary.importedLooksFolder,
        ]
        for name in notBuiltIn {
            #expect(menu(.group(name, count: 1, panel: .baseLooks), model).isEmpty, "\(name)")
        }

        let groups = model.recipes.builtInFolders(in: .recipes)
        #expect(groups == model.recipes.library.bundledGroups && groups.contains("Mood") && groups
            .contains("Essentials"))
        for name in groups {
            #expect(menu(.group(name, count: 1, panel: .recipes), model) == ["Hide “\(name)”"])
        }
        for name in ["Favorites", "My Recipes", "Trips", "Installed", FilmLookCatalog.group, "Redlamp"] {
            #expect(menu(.group(name, count: 1, panel: .recipes), model).isEmpty, "\(name) in Recipes")
        }
        let row = SidebarCellView(node: SidebarNode(.group("Mood", count: 20, panel: .recipes)), model: model)
        #expect(row.accessibilityIdentifier() == "recipes.folder.Mood")
    }

    @Test func `a hidden folder leaves its panel, its search and ⌘K, and comes back from the panel's header menu`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        let portra = try #require(entries(model).first { $0.name == "Portra 400" })
        #expect(folders(list.baseLooks).contains(FilmLookCatalog.group))

        try choose("Hide “Film Stocks”", in: .group(FilmLookCatalog.group, count: 36, panel: .baseLooks), model)
        try await eventually { !folders(list.baseLooks).contains(FilmLookCatalog.group) }
        #expect(!folders(list.baseLooks).contains(FilmLookCatalog.group))
        #expect(!BaseLookFolders.search("portra", in: BaseLookFolders.folders(model)).contains { $0.film != nil })
        #expect(!PaletteCatalog.choiceItems(.baseLook, editor: model).map(\.kind).contains(.baseLook(portra.look.id)))
        #expect(menu(.group(FilmLookCatalog.group, count: 36, panel: .baseLooks), model) == ["Open Film Looks"])

        let mood = try #require(model.recipes.sections.first { $0.name == "Mood" }?.recipes.first)
        try choose("Hide “Mood”", in: .group("Mood", count: 20, panel: .recipes), model)
        try await eventually { !folders(list.recipes).contains("Mood") }
        #expect(!folders(list.recipes).contains("Mood"))
        #expect(!model.recipes.searchPresets(mood.name).contains { $0.id == mood.id })
        #expect(!PaletteCatalog.choiceItems(.recipes, editor: model).map(\.kind).contains(.recipe(mood.id)))

        let looksMenu = try #require(PanelSectionView(section: .baseLooks, model: model, rows: []).headerMenu?())
        #expect(looksMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
            == ["Expand All Panels", "Collapse All Panels", "Show “Film Stocks”"])
        try looksMenu
            .performActionForItem(at: #require(looksMenu.items.firstIndex { $0.title == "Show “Film Stocks”" }))
        try await eventually { folders(list.baseLooks).contains(FilmLookCatalog.group) }
        #expect(folders(list.baseLooks).contains(FilmLookCatalog.group))
        #expect(BaseLookFolders.search("portra", in: BaseLookFolders.folders(model))
            .contains { $0.name == "Portra 400" })

        let recipesMenu = try #require(PanelSectionView(section: .recipes, model: model, rows: []).headerMenu?())
        #expect(recipesMenu.items.last?.title == "Show “Mood”")
        recipesMenu.performActionForItem(at: recipesMenu.items.count - 1)
        try await eventually { folders(list.recipes).contains("Mood") }
        #expect(folders(list.recipes).contains("Mood"))
        #expect(model.recipes.hiddenFolders(in: .recipes).isEmpty && model.recipes.hiddenFolders(in: .baseLooks)
            .isEmpty)
        let snapshots = try #require(PanelSectionView(section: .snapshots, model: model, rows: []).headerMenu?())
        #expect(snapshots.items.map(\.title) == ["Expand All Panels", "Collapse All Panels"])
    }

    @Test func `Adobe's camera profile folders hide, and the photographer's own profiles don't`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = StubEngine()
        engine.cameraProfiles = CameraProfileMenuTests.looks
        let model = try await openEditor(engine)
        #expect(BaseLookFolders.folders(model).map(\.name).prefix(4)
            == [BaseLookFolders.adobeRaw, BaseLookFolders.cameraMatching, "Your Profiles", BaseLookFolders.creative])
        #expect(menu(.group("Your Profiles", count: 1, panel: .baseLooks), model).isEmpty)
        #expect(BaseLookFolders.search("vintage 01", in: BaseLookFolders.folders(model)).map(\.name) == ["Vintage 01"])
        for name in [BaseLookFolders.adobeRaw, BaseLookFolders.cameraMatching, BaseLookFolders.creative] {
            try choose("Hide “\(name)”", in: .group(name, count: 1, panel: .baseLooks), model)
        }
        #expect(BaseLookFolders.folders(model).map(\.name).first == "Your Profiles")
        #expect(
            BaseLookFolders.search("vintage 01", in: BaseLookFolders.folders(model)).isEmpty,
            "Creative's groups too",
        )
        let header = try #require(PanelSectionView(section: .baseLooks, model: model, rows: []).headerMenu?())
        #expect(header.items.filter { !$0.isSeparatorItem }.map(\.title).suffix(3)
            == ["Show “Adobe Raw”", "Show “Camera Matching”", "Show “Creative”"])
    }

    @Test func `hidden folders survive a relaunch, and the photo keeps a hidden look, which Basic still names`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let portra = try #require(entries(model).first { $0.name == "Portra 400" })
        model.chooseLook(portra.choice(in: model))
        model.recipes.setHidden(FilmLookCatalog.group, in: .baseLooks, true)
        model.recipes.setHidden("Mood", in: .recipes, true)
        #expect(model.baseLook.id == portra.look.id && !model.isBaseLookMissing, "the photo keeps rendering its look")
        #expect(model.baseLook.name == "Portra 400")
        let menu = BaseLookGroups.shown(in: model.recipes, photoLook: model.baseLook)
        #expect(menu.first?.name == BaseLookGroups.inUse && menu.first?.looks.map(\.id) == [portra.look.id])

        let engine = StubEngine()
        let relaunched = EditorModel(engine: engine, recipes: RecipeCatalog(engine: engine, library: library()))
        #expect(!BaseLookFolders.folders(relaunched).map(\.name).contains(FilmLookCatalog.group))
        #expect(!relaunched.recipes.sections.map(\.name).contains("Mood"))
        let header = try #require(PanelSectionView(section: .recipes, model: relaunched, rows: []).headerMenu?())
        #expect(header.items.last?.title == "Show “Mood”")
    }
}
