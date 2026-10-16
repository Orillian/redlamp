import Foundation
import RedlampEngineAPI

/// What choosing a Base Look applies (DEC-104), wherever it's chosen: the Base Looks panel, Basic's
/// Base Look menu and browser, the Film Looks window and the command palette.
///
/// A film stock sets its look, its own grain, halation and bloom (each of the eight it doesn't list
/// at its default) and Black & White when it's a monochrome stock. Any other look sets the look and
/// the treatment it asks for, and, chosen while the edit's look is a film stock, returns the film's
/// eight to their defaults. Nothing else in the edit changes. An edit's look counts as a film stock
/// whether a choice or a recipe, such as a mood, set it.
public struct LookChoice: Sendable, Hashable {
    public var look: BaseLookReference
    /// The treatment the look sets; nil leaves the edit's.
    public var treatment: Treatment?
    /// The film stock whose grain, halation and bloom come with its look; nil for any other look,
    /// and for a film stock chosen without them.
    public var film: FilmLookDefinition?

    /// What a film stock sets, and what leaving one for another look takes away.
    public static let filmParameters: [ParameterID] = [
        .grainAmount, .grainSize, .grainRoughness, .grainColor, .halationAmount, .halationSize, .bloomAmount,
        .bloomSize,
    ]

    /// `look`, setting Black & White when `monochrome`. A film stock's look comes with its grain,
    /// halation and bloom unless `withFilmEffects` is false (Apply Without Grain, Halation and Bloom),
    /// and a monochrome stock sets Black & White either way.
    public init(_ look: BaseLookReference, monochrome: Bool = false, withFilmEffects: Bool = true) {
        let stock = FilmLookCatalog.look(forBaseLookID: look.id)
        self.look = look
        treatment = monochrome || stock?.isMonochrome == true ? .blackAndWhite : nil
        film = withFilmEffects ? stock : nil
    }

    /// A film stock at its current version; nil when its look isn't bundled.
    public init?(film: FilmLookDefinition, withFilmEffects: Bool = true) {
        guard let package = BuiltInBaseLooks.package(id: film.baseLookID, version: film.version) else { return nil }
        self.init(package.reference, withFilmEffects: withFilmEffects)
    }

    /// The look a recipe that's a look stands for (`Recipe.isLook`), with the treatment it sets, such
    /// as the colour the firmware model's simulations keep so their own monochrome shows. Nil for a
    /// recipe without a Base Look.
    public init?(standingFor recipe: Recipe, withFilmEffects: Bool = true) {
        guard let look = recipe.baseLook, recipe.includes.contains(.baseLook) else { return nil }
        self.init(look, withFilmEffects: withFilmEffects)
        if recipe.includes.contains(.treatment), let treatment = recipe.settings.treatment {
            self.treatment = treatment
        }
    }

    /// Whether `look` is one of the film stocks', at any of its versions.
    public static func isFilmStock(_ look: BaseLookReference) -> Bool {
        FilmLookCatalog.look(forBaseLookID: look.id) != nil
    }

    /// The edit with the look chosen. A look that's already the edit's keeps its Amount.
    public func apply(to edit: EditRecipe) -> EditRecipe {
        var result = edit
        result.baseLook = look.withAmount(edit.baseLook.isSameLook(as: look) ? edit.baseLook.amount : look.amount)
        if let treatment {
            result.treatment = treatment
        }
        if let film {
            for parameter in Self.filmParameters {
                result[parameter] = film.effects[parameter] ?? parameter.spec.defaultValue
            }
        } else if Self.isFilmStock(edit.baseLook) {
            for parameter in Self.filmParameters {
                result[parameter] = parameter.spec.defaultValue
            }
            // Taking the film's effects away leaves a switched-off Effects panel off.
            if !edit.isOn(.effects) {
                result.setPanel(.effects, on: false)
            }
        }
        return result
    }
}
