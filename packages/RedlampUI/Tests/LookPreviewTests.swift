import AppKit
import Foundation
import RedlampEngineAPI
import RedlampRecipes
import Testing
@_spi(Harness) @testable import RedlampUI

/// Hovering a look in the Recipes panel previews it, wherever it's listed (UX-45, DEC-74).
@MainActor
struct LookPreviewTests {
    private func openEditor() async throws -> (EditorModel, () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = EditorModel(engine: StubEngine())
        model.select(folder.appending(path: "IMG_0001.ARW"))
        for _ in 0 ..< 200 where model.info == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.info != nil)
        return (model, { try? FileManager.default.removeItem(at: folder) })
    }

    private func portra(_ model: EditorModel) throws -> Recipe {
        let look = try #require(FilmLookCatalog.look("portra-400"))
        return try #require(model.recipes.recipe(id: look.recipeID))
    }

    private static let event = NSEvent.enterExitEvent(
        with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, trackingNumber: 0, userData: nil,
    )!

    @Test func `hovering a recipe row previews the recipe, and leaving clears it`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        let recipe = try portra(model)
        let cell = SidebarCellView(node: SidebarNode(.recipe(recipe)), model: model)
        cell.mouseEntered(with: Self.event)
        #expect(model.previewingRecipe?.id == recipe.id)
        cell.mouseExited(with: Self.event)
        #expect(model.previewingRecipe == nil)
    }

    @Test func `a film recipe's row shows its film's icon`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        let recipe = try portra(model)
        #expect(LookIconImage.image(for: recipe, points: SidebarCellView.Layout.lookIconSize) != nil)
        let essentials = try #require(model.recipes.all.first { $0.group == "Essentials" })
        #expect(LookIconImage.image(for: essentials, points: SidebarCellView.Layout.lookIconSize) == nil)
    }

    @Test func `hovering a Base Look found by search previews the look alone`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        let look = try #require(model.recipes.searchBaseLooks("vivid").first)
        let cell = SidebarCellView(node: SidebarNode(.baseLook(look)), model: model)
        cell.mouseEntered(with: Self.event)
        #expect(model.previewingRecipe?.baseLook?.id == look.id)
        #expect(model.previewingRecipe?.includes == [.baseLook])
        cell.mouseExited(with: Self.event)
        #expect(model.previewingRecipe == nil)
    }

    @Test func `Apply Base Look Only previews the look alone while highlighted, and sets only the look`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        let recipe = try portra(model)
        let cell = SidebarCellView(node: SidebarNode(.recipe(recipe)), model: model)
        let menu = try #require(cell.contextMenu())
        let item = try #require(menu.items.first { $0.title == "Apply Base Look Only" })
        #expect(menu.delegate === cell)
        cell.menu(menu, willHighlight: item)
        #expect(model.previewingRecipe?.baseLook?.id == recipe.baseLook?.id)
        #expect(model.previewingRecipe?.includes == [.baseLook])
        cell.menu(menu, willHighlight: menu.items.first)
        #expect(model.previewingRecipe == nil)
        cell.menuDidClose(menu)
        #expect(model.previewingRecipe == nil)
        let action = try #require(item.action)
        NSApplication.shared.sendAction(action, to: item.target, from: item)
        #expect(model.baseLook.id == recipe.baseLook?.id)
        #expect(model.value(.grainAmount) == 0)
    }

    @Test func `the Base Look menu lists a film stock only while it's the photo's look`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        let recipe = try portra(model)
        let filmLooks = Set(FilmLookCatalog.looks.map(\.baseLookID))
        #expect(BaseLookPreviews.menuSections(model).allSatisfy { Set($0.ids).isDisjoint(with: filmLooks) })
        model.applyRecipe(recipe)
        let sections = BaseLookPreviews.menuSections(model)
        #expect(sections.first?.name == BaseLookGroups.inUse)
        #expect(sections.first?.ids == [recipe.baseLook?.id].compactMap(\.self))
        #expect(sections.dropFirst().allSatisfy { Set($0.ids).isDisjoint(with: filmLooks) })
    }
}
