import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// Recipe cards and the library with the firmware model's switch on and off.
@Suite(.enabled(if: FirmwareTestModel.isAvailable))
struct FirmwareCardTests {
    static let card = CameraRecipeCard(
        filmSimulation: .chrome, dynamicRange: .dr400, highlight: -1, shadow: 1, color: -2, colorChrome: .strong,
        whiteBalance: .init(mode: "auto", shiftRed: 2, shiftBlue: -4), grain: .init(strength: .weak),
    )

    static func library() throws -> RecipeLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return RecipeLibrary(root: root)
    }

    @Test func `through the model, a card's look takes its simulation and tone settings`() throws {
        let model = try FirmwareTestModel.model()
        let recipe = Self.card.recipe(id: "local/card", name: "Card", firmware: model)
        let look = try #require(recipe.baseLook)
        let settings = try #require(FirmwareLook.settings(for: look))
        #expect(settings == FirmwareLookSettings(
            simulation: .chrome, dynamicRange: 400, highlight: -1, shadow: 1, color: -2,
        ))
        #expect(recipe.embeddedBaseLooks.map(\.reference) == [look])
        #expect(recipe.embeddedBaseLooks.first?.slot == FilmSlot.chrome.rawValue)
        let values = recipe.settings.values
        for parameter in [ParameterID.highlights, .whites, .shadows, .blacks, .saturation, .dynamicRange] {
            #expect(values[parameter] == nil, "\(parameter)")
        }
        #expect(values[.colorChrome] != nil && values[.wbShiftRed] != nil && values[.grainAmount] != nil)
    }

    @Test func `without the model a card resolves as it always has`() {
        #expect(Self.card.recipe(id: "local/card", name: "Card", firmware: nil)
            == Self.card.recipe(id: "local/card", name: "Card"))
    }

    @Test func `a black-and-white card keeps colour, so the model's toning shows`() throws {
        let model = try FirmwareTestModel.model()
        let sepia = CameraRecipeCard(filmSimulation: .sepia, monochromeWarmCool: 3)
        let recipe = sepia.recipe(id: "local/sepia", name: "Sepia", firmware: model)
        #expect(recipe.settings.treatment == .color)
        #expect(recipe.settings.values[.gradeGlobalSaturation] == nil)
        #expect(try FirmwareLook.settings(for: #require(recipe.baseLook))?.warmCool == 3)
    }

    @Test func `the library offers every simulation while the switch is on`() throws {
        let library = try Self.library()
        #expect(library.firmwareRecipes.isEmpty)
        library.firmwareModel = try FirmwareTestModel.model()
        #expect(library.firmwareRecipes.count == FirmwareSimulation.allCases.count)
        #expect(!library.firmwareRecipes.contains { !$0.isLook }, "listed in Base Looks")
        #expect(!library.sections.contains { $0.name == RecipeLibrary.firmwareGroup })
        let acros = try #require(library.recipe(id: "local/firmware-model/acros"))
        #expect(acros.baseLook?.isFirmwareModel == true && acros.settings.treatment == .color)
        #expect(library.exportable(acros).embeddedBaseLooks.isEmpty)
        library.firmwareModel = nil
        #expect(library.firmwareRecipes.isEmpty)
    }

    @Test func `card recipes follow the switch, and go back to Redlamp's looks when it's off`() throws {
        let library = try Self.library()
        let bundled = try #require(library.bundled.first { $0.cameraCard?.slot == .chrome })
        #expect(library.resolvingCard(bundled) == bundled)
        library.firmwareModel = try FirmwareTestModel.model()
        let through = library.resolvingCard(bundled)
        #expect(through.baseLook?.isFirmwareModel == true && through.id == bundled.id)
        library.firmwareModel = nil
        let back = library.resolvingCard(through)
        #expect(back.baseLook == bundled.baseLook && back.settings == bundled.settings)
    }
}
