import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// What choosing a look applies, wherever it's chosen (DEC-104): a film stock brings its look and its
/// own grain, halation and bloom and nothing else, and leaving one for a look that isn't one takes them
/// away.
struct LookChoiceTests {
    private static func film(_ id: String, withFilmEffects: Bool = true) throws -> LookChoice {
        let stock = try #require(FilmLookCatalog.look(id))
        return try #require(LookChoice(film: stock, withFilmEffects: withFilmEffects))
    }

    private static func look(_ look: BuiltInBaseLook) -> LookChoice {
        LookChoice(look.reference, monochrome: look == .monochrome)
    }

    /// An edit with Effects of its own: a vignette, a light leak, dust and a frame.
    private static var edited: EditRecipe {
        var edit = EditRecipe()
        edit[.exposure] = 0.4
        edit[.vignetteAmount] = -25
        edit[.leakAmount] = 30
        edit[.dustAmount] = 15
        edit[.frameStyle] = Double(FrameStyle.printBorder.rawValue)
        return edit
    }

    @Test func `a film stock sets its look and its eight film settings, and keeps the rest of Effects`() throws {
        let portra = try #require(FilmLookCatalog.look("portra-400"))
        let edit = try Self.film("portra-400").apply(to: Self.edited)
        #expect(edit.baseLook.id == portra.baseLookID && edit.baseLook.version == portra.version)
        for parameter in LookChoice.filmParameters {
            #expect(edit[parameter] == portra.effects[parameter] ?? parameter.spec.defaultValue, "\(parameter)")
        }
        for parameter in [ParameterID.exposure, .vignetteAmount, .leakAmount, .dustAmount, .frameStyle] {
            #expect(edit[parameter] == Self.edited[parameter], "\(parameter)")
        }
        #expect(edit.treatment == .color)
        #expect(edit.appliedRecipe == nil, "choosing a look isn't applying a recipe")
    }

    @Test func `another stock replaces the last one's grain, and one without bloom takes its bloom away`() throws {
        let cinestill = try Self.film("cinestill-800t").apply(to: Self.edited)
        #expect(cinestill[.bloomAmount] > 0 && cinestill[.halationAmount] == 70)
        let portra = try Self.film("portra-400").apply(to: cinestill)
        #expect(portra[.bloomAmount] == ParameterID.bloomAmount.spec.defaultValue)
        #expect(portra[.bloomSize] == ParameterID.bloomSize.spec.defaultValue)
        #expect(portra[.halationAmount] == 8 && portra[.grainAmount] == 20)
        #expect(portra[.vignetteAmount] == -25 && portra[.leakAmount] == 30)
    }

    @Test func `a monochrome stock sets Black & White, with or without its grain`() throws {
        let trix = try Self.film("tri-x-400")
        #expect(trix.apply(to: Self.edited).treatment == .blackAndWhite)
        let alone = try Self.film("tri-x-400", withFilmEffects: false)
        #expect(alone.apply(to: Self.edited).treatment == .blackAndWhite)
        #expect(alone.apply(to: Self.edited)[.grainAmount] == 0)
    }

    @Test func `a look that isn't a film stock, chosen over one, returns the film's settings to their defaults`(
    ) throws {
        let portra = try Self.film("portra-400").apply(to: Self.edited)
        var tuned = portra
        tuned[.grainAmount] = 55
        let color = Self.look(.color).apply(to: tuned)
        #expect(color.baseLook.isSameLook(as: BuiltInBaseLook.color.reference))
        for parameter in LookChoice.filmParameters {
            #expect(color[parameter] == parameter.spec.defaultValue, "\(parameter)")
        }
        #expect(color[.vignetteAmount] == -25 && color[.leakAmount] == 30 && color[.exposure] == 0.4)
    }

    @Test func `chosen over a look that isn't a film stock, a look keeps the photographer's own grain`() {
        var edit = Self.look(.color).apply(to: Self.edited)
        edit[.grainAmount] = 40
        edit[.bloomAmount] = 12
        let vivid = Self.look(.vivid).apply(to: edit)
        #expect(vivid.baseLook.isSameLook(as: BuiltInBaseLook.vivid.reference))
        #expect(vivid[.grainAmount] == 40 && vivid[.bloomAmount] == 12)
    }

    @Test func `a film stock chosen without its grain is a look like any other`() throws {
        let portra = try #require(FilmLookCatalog.look("portra-400"))
        let alone = try Self.film("portra-400", withFilmEffects: false)
        var own = Self.edited
        own[.grainAmount] = 40
        #expect(alone.apply(to: own)[.grainAmount] == 40)
        let cinestill = try Self.film("cinestill-800t").apply(to: Self.edited)
        let replaced = alone.apply(to: cinestill)
        #expect(replaced.baseLook.id == portra.baseLookID)
        #expect(LookChoice.filmParameters.allSatisfy { replaced[$0] == $0.spec.defaultValue })
    }

    @Test func `the photo's look counts as a film stock when a mood set it`() throws {
        let mood = try #require(MoodLooks.recipes.first { $0.id.hasSuffix("/night-glow") })
        let moody = mood.apply(to: Self.edited)
        #expect(LookChoice.isFilmStock(moody.baseLook) && moody[.halationAmount] > 0)
        let color = Self.look(.color).apply(to: moody)
        #expect(color[.halationAmount] == 0 && color[.bloomAmount] == 0)
        #expect(color[.dustAmount] == moody[.dustAmount], "the mood's dust isn't the film's")
    }

    @Test func `choosing the photo's own look keeps its Amount; another look starts at its own`() throws {
        var edit = try Self.film("portra-400").apply(to: Self.edited)
        edit.baseLook = edit.baseLook.withAmount(60)
        #expect(try Self.film("portra-400").apply(to: edit).baseLook.amount == 60)
        #expect(try Self.film("gold-200").apply(to: edit).baseLook.amount == 100)
    }

    @Test func `leaving a film stock leaves a switched-off Effects panel off`() throws {
        var edit = try Self.film("portra-400").apply(to: Self.edited)
        edit.setPanel(.effects, on: false)
        #expect(!Self.look(.color).apply(to: edit).isOn(.effects))
    }

    @Test func `a look recipe's choice keeps the treatment it sets`() {
        let look = BaseLookPackage(id: "local/simulation/look", name: "Simulation", parameters: .identity)
        let recipe = Recipe(
            id: RecipeLibrary.firmwareIDPrefix + "acros", name: "ACROS", group: RecipeLibrary.firmwareGroup,
            includes: [.baseLook, .treatment], settings: RecipeSettings(treatment: .color), baseLook: look.reference,
        )
        var edit = Self.edited
        edit.treatment = .blackAndWhite
        let chosen = LookChoice(standingFor: recipe)?.apply(to: edit)
        #expect(chosen?.baseLook.id == look.id && chosen?.treatment == .color)
    }
}
