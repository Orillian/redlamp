import AppKit
import Foundation
import RedlampDesign
import RedlampEngineAPI
import RedlampRecipes
import Testing
@_spi(Harness) @testable import RedlampUI

/// The Base Looks panel before Recipes, and Recipes as presets (DEC-104, UX-54).
@MainActor
struct BaseLooksPanelTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "base-looks-\(UUID().uuidString)")

    /// An editor with a photo open, its recipes kept in a folder of the test's own.
    private func openEditor() async throws -> EditorModel {
        let folder = root.appending(path: "Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let engine = StubEngine()
        let model = EditorModel(
            engine: engine,
            recipes: RecipeCatalog(engine: engine, library: RecipeLibrary(root: root.appending(path: "Library"))),
        )
        model.select(folder.appending(path: "IMG_0001.ARW"))
        try await eventually { model.info != nil }
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

    private func rows(_ outline: SidebarOutlineView) -> [SidebarNode.Kind] {
        (0 ..< outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? SidebarNode)?.kind }
    }

    private func look(_ name: String, in model: EditorModel) throws -> LookEntry {
        try #require(BaseLookFolders.folders(model).flatMap(\.allEntries).first { $0.name == name })
    }

    private func search(_ text: String, in field: NSSearchField, of list: SidebarListView) {
        field.stringValue = text
        list.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    // MARK: - The column

    @Test func `the left column lists Base Looks after Folders and before Recipes`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        #expect(SidebarSection.allCases == [.navigator, .folders, .baseLooks, .recipes, .snapshots, .history])
        #expect(SidebarSection.baseLooks.title == "Base Looks")
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        let looks = list.baseLooks.convert(list.baseLooks.bounds, to: nil)
        let recipes = list.recipes.convert(list.recipes.bounds, to: nil)
        #expect(looks.minY > recipes.maxY, "Base Looks sits above Recipes")
    }

    // MARK: - Folders and search

    @Test func `Base Looks lists every kind of look in its folders, and Recipes only the presets`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let folders = BaseLookFolders.folders(model)
        let names = folders.map(\.name)
        let order = [
            BaseLookGroups.redlamp,
            BaseLookGroups.filmStyles,
            FilmLookCatalog.group,
            BaseLookGroups.reproduction,
        ]
        #expect(names.filter(order.contains) == order)
        #expect(folders.first { $0.name == BaseLookGroups.redlamp }?.count == BuiltInBaseLook.allCases.count - 1)
        #expect(folders.first { $0.name == FilmLookCatalog.group }?.entries.map(\.name)
            == FilmLookCatalog.bundledRecipes.map(\.name))
        #expect(!model.recipes.sections.map(\.name).contains(FilmLookCatalog.group))
        #expect(model.recipes.presets.allSatisfy { !$0.isLook })
    }

    @Test func `searching Base Looks finds looks by maker and kind, and Lightroom's words list a whole kind`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let folders = BaseLookFolders.folders(model)
        func found(_ query: String) -> [LookEntry] {
            BaseLookFolders.search(query, in: folders)
        }
        let kodak = Set(folders.flatMap(\.allEntries).filter { $0.film?.maker == "Kodak" }.map(\.look.id))
        #expect(!kodak.isEmpty && kodak.isSubset(of: found("kodak").map(\.look.id)))
        #expect(found("kodak").allSatisfy { $0.film != nil }, "only film stocks name Kodak")
        #expect(found("slide").contains { $0.name == "Velvia 50" })
        let monochrome = found("black and white").map(\.name)
        #expect(monochrome.contains("Tri-X 400") && monochrome.contains("Redlamp Monochrome"))
        #expect(Set(found("profile").map(\.folder)) == [BaseLookGroups.redlamp, BaseLookGroups.reproduction])
        #expect(Set(found("film").map(\.folder)) == [BaseLookGroups.filmStyles, FilmLookCatalog.group])
        #expect(found("lut").isEmpty, "nothing is imported")
        #expect(found("").isEmpty && found("polaroid sx-70").isEmpty)
    }

    @Test func `a favourite look is listed under Favorites, a film stock's shared with the Film Looks window`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let vivid = try look("Redlamp Vivid", in: model)
        let portra = try look("Portra 400", in: model)
        model.recipes.setFavorite(id: vivid.favoriteID, true)
        model.recipes.setFavorite(id: portra.favoriteID, true)
        let folders = BaseLookFolders.folders(model)
        #expect(folders.first?.name == BaseLookFolders.favorites)
        #expect(folders.first?.entries.map(\.name) == ["Redlamp Vivid", "Portra 400"])
        #expect(try model.recipes.isFavorite(#require(portra.recipe)), "the Film Looks window shows it as a favourite")
        #expect(BaseLookFolders.search("vivid", in: folders).filter { $0.name == "Redlamp Vivid" }.count == 1)
        let cell = SidebarCellView(node: SidebarNode(.look(vivid, current: false, showsFolder: false)), model: model)
        #expect(cell.contextMenu()?.items.first?.title == "Remove from Favorites")
        #expect(cell.contextMenu()?.items.contains { $0.title.hasPrefix("Apply Without") } == false)
    }

    // MARK: - The panel

    @Test func `the panel shows the photo's look by highlighting it in its open folder, and leaves its Amount to Basic`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let portra = try look("Portra 400", in: model)
        model.chooseLook(portra.choice(in: model))
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        func current() -> [String] {
            rows(list.baseLooks).compactMap {
                if case let .look(entry, true, _) = $0 {
                    entry.name
                } else {
                    nil
                }
            }
        }
        guard case .group = rows(list.baseLooks).first else {
            Issue.record("Base Looks doesn't start with its folders")
            return
        }
        #expect(list.expandedLookFolders.contains(FilmLookCatalog.group), "the photo's look's folder opens")
        #expect(current() == ["Portra 400"])

        model.setBaseLook(BuiltInBaseLook.vivid.reference)
        try await eventually { current() == ["Redlamp Vivid"] }
        #expect(current() == ["Redlamp Vivid"], "the panel follows a look chosen elsewhere")

        let shown = list.baseLooks.view(atColumn: 0, row: 0, makeIfNecessary: false)
        model.setBaseLookAmount(150)
        try await Task.sleep(for: .milliseconds(50))
        #expect(
            list.baseLooks.view(atColumn: 0, row: 0, makeIfNecessary: false) === shown,
            "Basic's Amount doesn't list the looks again",
        )
    }

    @Test func `a folder's looks line up with its icon and name, a search's results too`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        let outline = list.baseLooks
        func frame(where matches: (SidebarNode.Kind) -> Bool) throws -> CGRect {
            let row = try #require((0 ..< outline.numberOfRows).first { row in
                (outline.item(atRow: row) as? SidebarNode).map { matches($0.kind) } ?? false
            })
            return outline.frameOfCell(atColumn: 0, row: row)
        }
        let redlamp = try frame {
            if case let .group(name, _, _) = $0 {
                name == BaseLookGroups.redlamp
            } else {
                false
            }
        }
        let color = try frame {
            if case let .look(entry, _, _) = $0 {
                entry.name == "Redlamp Color"
            } else {
                false
            }
        }
        #expect(color.minX == redlamp.minX, "its looks start where the folder does, past its chevron's place")
        search("ektar", in: list.lookSearchField, of: list)
        let found = try frame {
            if case .look = $0 {
                true
            } else {
                false
            }
        }
        #expect(found.minX == redlamp.minX)
    }

    @Test func `choosing a film stock keeps the vignette, and a look that isn't a film takes its grain away`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        model.setValue(.vignetteAmount, -30)
        let steps = model.history.count
        let portra = try look("Portra 400", in: model)
        model.chooseLook(portra.choice(in: model))
        #expect(model.history.count == steps + 1, "one History step")
        #expect(model.value(.vignetteAmount) == -30)
        #expect(model.value(.grainAmount) == portra.film?.effects[.grainAmount])
        try model.chooseLook(look("Redlamp Vivid", in: model).choice(in: model))
        #expect(model.value(.grainAmount) == 0)
        #expect(model.value(.vignetteAmount) == -30)
    }

    @Test func `Base Looks' search lists each look with its folder, or says nothing matched`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        search("ektar", in: list.lookSearchField, of: list)
        let found = rows(list.baseLooks).compactMap {
            if case let .look(entry, _, showsFolder) = $0 {
                showsFolder ? entry.name : nil
            } else {
                nil
            }
        }
        #expect(found == ["Ektar 100"])
        search("polaroid", in: list.lookSearchField, of: list)
        #expect(rows(list.baseLooks).contains {
            if case .placeholder("No matching Base Looks") = $0 {
                true
            } else {
                false
            }
        })
    }

    // MARK: - Recipes

    @Test func `Recipes' search finds presets only, and says where looks are when nothing matches`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        search("t-max", in: list.searchField, of: list)
        let placeholders = rows(list.recipes).compactMap {
            if case let .placeholder(text) = $0 {
                text
            } else {
                nil
            }
        }
        #expect(placeholders == ["No matching recipes", "Looks and film stocks are in Base Looks"])
        search("street", in: list.searchField, of: list)
        let recipes = rows(list.recipes).compactMap {
            if case let .recipe(recipe) = $0 {
                recipe
            } else {
                nil
            }
        }
        #expect(!recipes.isEmpty && recipes.allSatisfy { !$0.isLook })
    }

    @Test func `Recipes' Amount is the panels' slider row, a drag one History step that doesn't reload the list`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        let punchy = try #require(model.recipes.presets.first { $0.name == "Punchy" })
        model.applyRecipe(punchy)
        func amountCell() -> SidebarCellView? {
            guard case .recipeAmount? = (list.recipes.item(atRow: 0) as? SidebarNode)?.kind else { return nil }
            return list.recipes.view(atColumn: 0, row: 0, makeIfNecessary: false) as? SidebarCellView
        }
        try await eventually { amountCell() != nil }
        let cell = try #require(amountCell())
        let row = try #require(cell.subviews.compactMap { $0 as? SliderRowView }.first)
        let track = try #require(row.subviews.compactMap { $0 as? SliderTrackView }.first)
        let field = try #require(row.subviews.compactMap { $0 as? ValueFieldView }.first)
        #expect(row.accessibilityIdentifier() == "recipes.amount")
        #expect(row.toolTip?.hasPrefix("Strength of “Punchy”") == true)
        #expect(track.value == 100 && field.value == 100)
        #expect(list.recipes.validateProposedFirstResponder(track, for: nil), "the list lets the slider take a press")

        let steps = model.history.count
        track.onBegin()
        for amount in [120.4, 150, 160] {
            track.onChange(amount)
        }
        try await eventually { track.value == 160 }
        #expect(track.value == 160 && field.value == 160, "the row follows its drag")
        #expect(amountCell() === cell, "the list doesn't reload while the Amount is dragged")
        track.onEnd()
        #expect(model.recipeAmount == 160)
        #expect(model.history.count == steps + 1 && model.history.last?.name.hasPrefix("Recipe Amount") == true)
        field.onCommit(80)
        #expect(model.recipeAmount == 80 && model.history.count == steps + 2, "a typed Amount is a step of its own")
    }

    @Test func `Basic's Base Look Amount is the panels' slider row, which a double-click returns to 100`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        model.expandedPanels = [.basic]
        _ = NSApplication.shared
        let panel = BasicPanelView.make(model: model)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 316, height: 900), styleMask: [.borderless], backing: .buffered,
            defer: true,
        )
        window.contentView = panel
        defer { window.contentView = nil }
        panel.layoutSubtreeIfNeeded()
        func sliders(in view: NSView) -> [SliderRowView] {
            view.subviews.flatMap { ($0 as? SliderRowView).map { [$0] } ?? sliders(in: $0) }
        }
        func trackSpan(_ row: SliderRowView) throws -> ClosedRange<CGFloat> {
            let track = try #require(row.subviews.first { $0 is SliderTrackView })
            let frame = track.convert(track.bounds, to: nil)
            return frame.minX ... frame.maxX
        }
        let row = try #require(sliders(in: panel).first { $0.accessibilityIdentifier() == "baseLook.amount" })
        let temperature = try #require(sliders(in: panel).first { $0.parameter == .temperature })
        let track = try #require(row.subviews.compactMap { $0 as? SliderTrackView }.first)
        let field = try #require(row.subviews.compactMap { $0 as? ValueFieldView }.first)
        let label = try #require(row.subviews.first { $0.accessibilityIdentifier() == "baseLook.amount.label" })
        let span = try trackSpan(row)
        #expect(span.upperBound - span.lowerBound > 100, "\(span)")
        #expect(try span == trackSpan(temperature), "its track spans Temp's")
        #expect(track.value == 100 && field.value == 100)

        let steps = model.history.count
        track.onBegin()
        for amount in [80.4, 60, 43] {
            track.onChange(amount)
        }
        track.onEnd()
        #expect(model.baseLook.amount == 43)
        #expect(model.history.count == steps + 1 && model.history.last?.name.hasPrefix("Base Look Amount") == true)

        let doubleClick = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, eventNumber: 0, clickCount: 2, pressure: 1,
        ))
        track.mouseDown(with: doubleClick)
        #expect(model.baseLook.amount == 100, "a double-click on the slider returns it to 100")
        #expect(model.history.count == steps + 2 && model.history.last?.name.hasPrefix("Base Look Amount") == true)
        model.undo()
        try await eventually { track.value == 43 }
        #expect(track.value == 43 && field.value == 43, "the row follows the edit")
        label.mouseDown(with: doubleClick)
        #expect(model.baseLook.amount == 100, "and so does one on its label")
    }

    @Test func `a recipe that sets a Base Look says so, and one that doesn't says nothing of it`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let punchy = try #require(model.recipes.presets.first { $0.name == "Punchy" })
        let look = try #require(punchy.baseLook.flatMap(model.recipes.package(for:)))
        let marked = SidebarCellView(node: SidebarNode(.recipe(punchy)), model: model)
        #expect(marked.toolTip?.hasPrefix("Also sets the Base Look: \(look.name)") == true)
        let plain = try #require(model.recipes.presets.first { $0.baseLook == nil })
        #expect(SidebarCellView(node: SidebarNode(.recipe(plain)), model: model).toolTip?
            .contains("Also sets") == false)
    }

    // MARK: - ⌘K

    @Test func `⌘K's Base Look page lists the film stocks, and its Recipes page only presets`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let portra = try look("Portra 400", in: model)
        let looks = PaletteCatalog.choiceItems(.baseLook, editor: model).map(\.kind)
        #expect(looks.contains(.baseLook(portra.look.id)))
        let recipes = PaletteCatalog.choiceItems(.recipes, editor: model).map(\.kind)
        #expect(try !recipes.contains(.recipe(#require(portra.recipe).id)))
        #expect(recipes.count == model.recipes.presets.count)
    }

    @Test func `⌘K applies a film stock as the panel does, keeping the vignette`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        model.setValue(.vignetteAmount, -30)
        let ektar = try look("Ektar 100", in: model)
        model.openCommandPalette()
        let palette = try #require(model.commandPalette)
        palette.setText("ektar")
        let item = try #require(palette.rows.first { $0.kind == .baseLook(ektar.look.id) })
        palette.select(item)
        palette.activate(item)
        #expect(model.baseLook.id == ektar.look.id)
        #expect(model.value(.grainAmount) == ektar.film?.effects[.grainAmount])
        #expect(model.value(.vignetteAmount) == -30)
    }

    // MARK: - Imports

    @Test func `an imported LUT opens the Base Looks folder it went to`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await openEditor()
        let (list, window) = showLists(model)
        defer { window.contentView = nil }
        #expect(!list.expandedLookFolders.contains(RecipeLibrary.importedLooksFolder))
        let cube = root.appending(path: "Warm.cube")
        var lines = ["TITLE \"Warm\"", "LUT_3D_SIZE 2"]
        for b in 0 ... 1 {
            for g in 0 ... 1 {
                for r in 0 ... 1 {
                    lines.append("\(Double(r)) \(Double(g) * 0.95) \(Double(b) * 0.9)")
                }
            }
        }
        try lines.joined(separator: "\n").write(to: cube, atomically: true, encoding: .utf8)
        model.recipes.install(RecipeLibrary.read(importing: [cube], reading: UnreadableFiles()))
        try await eventually { list.expandedLookFolders.contains(RecipeLibrary.importedLooksFolder) }
        #expect(list.expandedLookFolders.contains(RecipeLibrary.importedLooksFolder))
        #expect(BaseLookFolders.folders(model).first { $0.name == RecipeLibrary.importedLooksFolder }?.count == 1)
        #expect(model.recipes.sections.isEmpty == false && !model.recipes.sections.map(\.name).contains("Installed"))
    }
}
