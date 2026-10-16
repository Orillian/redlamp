import Foundation
import RedlampEngineAPI
import RedlampRecipes
import Testing
@_spi(Harness) @testable import RedlampUI

/// Choosing a look in the editor (DEC-104, UX-55): one History step that keeps the rest of the edit, a
/// film stock's grain taken away by the next look that isn't one, hover previews, and a look moved to
/// the Trash with its recipe still rendering but listed nowhere.
@MainActor
struct LookChoiceEditorTests {
    private func openEditor() async throws -> (EditorModel, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = RecipeLibrary(root: root.appending(path: "library"))
        let trash = root.appending(path: "Trash")
        library.trash = { url in
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let moved = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: moved)
            return moved
        }
        let engine = StubEngine()
        let model = EditorModel(engine: engine, recipes: RecipeCatalog(engine: engine, library: library))
        let photo = root.appending(path: "IMG_0001.ARW")
        model.select(photo)
        for _ in 0 ..< 400 where model.info?.url != photo {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(model.info?.url == photo)
        return (model, { try? FileManager.default.removeItem(at: root) })
    }

    private static func film(_ id: String) throws -> LookChoice {
        let stock = try #require(FilmLookCatalog.look(id))
        return try #require(LookChoice(film: stock))
    }

    @Test func `choosing a film stock keeps the edit's vignette and frame, as one History step`() async throws {
        let (model, cleanUp) = try await openEditor()
        defer { cleanUp() }
        model.setValue(.vignetteAmount, -25)
        model.setValue(.frameStyle, Double(FrameStyle.printBorder.rawValue))
        let steps = model.history.count
        try model.chooseLook(Self.film("cinestill-800t"))
        #expect(model.history.count == steps + 1 && model.history.last?.title == "Base Look")
        #expect(model.value(.vignetteAmount) == -25)
        #expect(model.value(.frameStyle) == Double(FrameStyle.printBorder.rawValue))
        #expect(model.value(.halationAmount) == 70 && model.value(.bloomAmount) == 8)
        try model.chooseLook(Self.film("portra-400"))
        #expect(model.value(.bloomAmount) == 0 && model.value(.grainAmount) == 20)
        #expect(model.value(.vignetteAmount) == -25)
    }

    @Test func `Redlamp Color after a film stock takes its grain away; grain added on Color stays on Vivid`(
    ) async throws {
        let (model, cleanUp) = try await openEditor()
        defer { cleanUp() }
        try model.chooseLook(Self.film("portra-400"))
        model.setBaseLook(BuiltInBaseLook.color.reference)
        #expect(model.baseLook.isSameLook(as: BuiltInBaseLook.color.reference))
        #expect(LookChoice.filmParameters.allSatisfy { model.value($0) == $0.spec.defaultValue })
        model.setValue(.grainAmount, 30)
        model.setBaseLook(BuiltInBaseLook.vivid.reference)
        #expect(model.value(.grainAmount) == 30)
    }

    @Test func `a film stock's look chosen in Basic's menu brings its grain, and a monochrome one Black & White`(
    ) async throws {
        let (model, cleanUp) = try await openEditor()
        defer { cleanUp() }
        let trix = try Self.film("tri-x-400")
        model.setBaseLook(trix.look)
        #expect(model.treatment == .blackAndWhite && model.value(.grainAmount) == 37)
        model.setBaseLook(BuiltInBaseLook.monochrome.reference)
        #expect(model.treatment == .blackAndWhite && model.value(.grainAmount) == 0)
    }

    @Test func `hovering a look previews it as choosing it would, and leaves the edit alone`() async throws {
        let (model, cleanUp) = try await openEditor()
        defer { cleanUp() }
        let portra = try Self.film("portra-400")
        let before = model.recipe
        model.previewLook(portra)
        #expect(model.previewingLook == portra && model.previewingRecipe == nil)
        #expect(model.recipe == before)
        model.previewRecipe(nil)
        #expect(model.previewingLook == nil)
        model.previewLook(portra)
        model.chooseLook(portra)
        #expect(model.previewingLook == nil && model.value(.grainAmount) == 20)
    }

    @Test func `a LUT moved to the Trash still renders in the photo, and no menu lists its look`() async throws {
        let (model, cleanUp) = try await openEditor()
        defer { cleanUp() }
        let lut = try #require(model.recipes.save(LookTableImport.recipe(for: .identity(size: 3), name: "Teal")))
        let look = try #require(lut.baseLook)
        model.setBaseLook(look)
        model.recipes.moveToTrash(lut)
        #expect(model.recipes.recipe(id: lut.id) == nil)
        #expect(model.baseLook.isSameLook(as: look) && !model.isBaseLookMissing)
        #expect(!model.recipes.currentBaseLooks.contains { $0.reference.isSameLook(as: look) })
        model.setBaseLook(BuiltInBaseLook.color.reference)
        #expect(BaseLookPreviews.menuSections(model).allSatisfy { !$0.ids.contains(look.id) })
    }
}
