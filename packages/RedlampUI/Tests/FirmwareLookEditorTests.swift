import Foundation
import RedlampEngineAPI
import RedlampRecipes
import Testing
@testable import RedlampUI

/// The firmware model's prototype in the editor: the Camera Recipe controls' look and recipe
/// cards, with the switch on and off. Skipped on a Mac without the model's folder.
/// The model's folder for these tests: `REDLAMP_FIRMWARE_MODEL`, or the default folder.
private let firmwareFolder = FirmwareFilmModel.environmentFolder ?? FirmwareFilmModel.defaultFolder

@MainActor
@Suite(.enabled(if: FirmwareFilmModel.isAvailable(at: firmwareFolder)))
struct FirmwareLookEditorTests {
    private func openEditor() async throws -> (EditorModel, RecipeCatalog, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let engine = StubEngine()
        let recipes = RecipeCatalog(engine: engine, library: RecipeLibrary(root: root))
        recipes.library.firmwareModel = try FirmwareFilmModel.shared(at: firmwareFolder)
        let model = EditorModel(engine: engine, recipes: recipes)
        let photo = root.appending(path: "IMG_0001.ARW")
        model.select(photo)
        for _ in 0 ..< 400 where model.info?.url != photo {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(model.info?.url == photo)
        return (model, recipes, { try? FileManager.default.removeItem(at: root) })
    }

    @Test func `the controls set the photo's look, keep it on this Mac and leave the menus alone`() async throws {
        let (model, recipes, cleanUp) = try await openEditor()
        defer { cleanUp() }
        #expect(model.usesFirmwareModel && model.firmwareSettings == nil)
        model.setFirmwareLook(FirmwareLookSettings(simulation: .chrome, shadow: 1))
        #expect(model.recipe.baseLook.isFirmwareModel && model.firmwareSettings?.shadow == 1)
        model.updateFirmwareLook { $0.color = 2 }
        #expect(model.firmwareSettings?.color == 2 && model.firmwareSettings?.simulation == .chrome)
        #expect(recipes.library.storedLooks.contains { $0.matches(model.recipe.baseLook) })
        #expect(!recipes.currentBaseLooks.contains { $0.reference.isFirmwareModel })
        model.setFirmwareLook(nil)
        #expect(model.recipe.baseLook == BuiltInBaseLook.color.reference)
    }

    @Test func `a black-and-white simulation keeps the colour treatment, so its toning shows`() async throws {
        let (model, _, cleanUp) = try await openEditor()
        defer { cleanUp() }
        model.setTreatment(.blackAndWhite)
        model.setFirmwareLook(FirmwareLookSettings(simulation: .sepia))
        #expect(model.recipe.treatment == .color)
    }

    @Test func `camera recipes apply through the model while the switch is on`() async throws {
        let (model, recipes, cleanUp) = try await openEditor()
        defer { cleanUp() }
        let card = try #require(recipes.library.bundled.first { $0.cameraCard?.slot == .chrome })
        let bundledLook = try #require(card.baseLook)
        model.applyRecipe(card)
        try await waitFor { model.recipe.baseLook.isFirmwareModel }
        #expect(FirmwareLook.settings(for: model.recipe.baseLook)?.simulation == .chrome)
        recipes.library.firmwareModel = nil
        model.applyRecipe(card)
        try await waitFor { model.recipe.baseLook.isSameLook(as: bundledLook) }
    }

    /// Applying a card waits for the photo's auto white balance.
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
