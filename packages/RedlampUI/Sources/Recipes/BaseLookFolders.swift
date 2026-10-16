import Foundation
import RedlampEngineAPI
import RedlampRecipes

/// A look the Base Looks panel lists (DEC-104): one of the photo's camera profiles, Redlamp's own, a
/// Film Style, a film stock, one of the firmware model's simulations, or an imported LUT.
struct LookEntry {
    /// What a look is, for the words that list a whole kind: profile, film, simulation and LUT.
    enum Kind {
        case profile, film, simulation, lut
    }

    var look: BaseLookReference
    var name: String
    var summary: String?
    /// The folder it's listed in, which a search result shows.
    var folder: String
    /// The recipe the look stands for: a film stock, one of the firmware model's simulations, an
    /// imported LUT.
    var recipe: Recipe?
    var kinds: Set<Kind>
    /// What search matches, lowercased: the name, summary and folder, and a film stock's maker, format
    /// and kind.
    var text: String

    /// What its favourite is kept by: its recipe's id for a look a recipe stands for, so a film stock
    /// keeps the favourite the Film Looks window gave it, and the look's own id otherwise.
    var favoriteID: String {
        recipe?.id ?? look.id
    }

    /// The film stock whose look it is.
    var film: FilmLookDefinition? {
        FilmLookCatalog.look(forBaseLookID: look.id)
    }

    /// Whether it's the look `reference` names, whatever its Amount; an Adobe look over another
    /// camera's profile is the same look.
    func isLook(of reference: BaseLookReference) -> Bool {
        look.isAdobeProfile ? look.isSameAdobeLook(as: reference) : look.isSameLook(as: reference)
    }

    /// What choosing it applies (`LookChoice`): a film stock comes with its grain, halation and bloom
    /// unless `withFilmEffects` is false. A recipe's look is made renderable first.
    @MainActor func choice(in model: EditorModel, withFilmEffects: Bool = true) -> LookChoice {
        if let recipe {
            model.recipes.prepare(recipe)
            if let choice = LookChoice(standingFor: recipe, withFilmEffects: withFilmEffects) {
                return choice
            }
        }
        return model.lookChoice(for: look, withFilmEffects: withFilmEffects)
    }
}

/// One of the Base Looks panel's folders: its looks, and for Adobe's creative profiles a folder for
/// each group.
struct LookFolder {
    var name: String
    var entries: [LookEntry]
    var subfolders: [LookFolder] = []

    var count: Int {
        entries.count + subfolders.reduce(0) { $0 + $1.count }
    }

    /// Its looks and its subfolders', in order.
    var allEntries: [LookEntry] {
        entries + subfolders.flatMap(\.allEntries)
    }
}

/// The Base Looks panel's folders for the open photo, which ⌘K's Base Look page lists too.
@MainActor
enum BaseLookFolders {
    static let favorites = "Favorites"
    static let inThisPhoto = "In This Photo"
    static let adobeRaw = "Adobe Raw"
    static let cameraMatching = "Camera Matching"
    static let creative = "Creative"

    /// The folders that come with Redlamp or with Adobe's camera profiles, which can be hidden (UX-55), in the
    /// panel's order. Favorites, In This Photo, the photographer's own profiles, Fujifilm LUTs and Imported can't.
    static let builtIn = [
        adobeRaw, cameraMatching, creative, BaseLookGroups.redlamp, BaseLookGroups.filmStyles, FilmLookCatalog.group,
        RecipeLibrary.firmwareGroup, BaseLookGroups.reproduction,
    ]

    /// Favorites, In This Photo, the photo's camera profiles, Redlamp, Film Styles, Film Stocks,
    /// Firmware Model, Fujifilm LUTs, Imported and Reproduction, each only when it has looks and isn't
    /// hidden (UX-55). Favorites holds the favourite looks of the others.
    static func folders(_ model: EditorModel) -> [LookFolder] {
        let recipes = model.recipes
        var folders: [LookFolder] = []
        if let embedded = BaseLookMenu.embeddedLook(in: model) {
            folders.append(LookFolder(name: inThisPhoto, entries: [entry(
                embedded, summary: "The look of the camera profile embedded in this file", folder: inThisPhoto,
                kinds: [.profile],
            )]))
        }
        folders += cameraProfileFolders(model)
        let groups = BaseLookGroups.current(in: recipes)
        let lookRecipes = recipes.lookRecipes
        func recipeFolder(_ name: String, kinds: Set<LookEntry.Kind>) -> LookFolder {
            LookFolder(name: name, entries: lookRecipes.filter { $0.lookFolder == name }.compactMap {
                entry($0, folder: name, kinds: kinds)
            })
        }
        func packageFolder(_ name: String, from group: String, kinds: Set<LookEntry.Kind>) -> LookFolder {
            LookFolder(name: name, entries: groups.looks(in: group).map { entry($0, folder: name, kinds: kinds) })
        }
        folders.append(packageFolder(BaseLookGroups.redlamp, from: BaseLookGroups.redlamp, kinds: [.profile]))
        folders.append(packageFolder(
            BaseLookGroups.filmStyles, from: BaseLookGroups.filmStyles, kinds: [.film, .simulation],
        ))
        folders.append(recipeFolder(FilmLookCatalog.group, kinds: [.film]))
        folders.append(recipeFolder(RecipeLibrary.firmwareGroup, kinds: [.simulation]))
        folders.append(recipeFolder(FujifilmLUT.group, kinds: [.lut, .simulation]))
        var imported = recipeFolder(RecipeLibrary.importedLooksFolder, kinds: [.lut])
        imported.entries += packageFolder(imported.name, from: BaseLookGroups.installed, kinds: [.lut]).entries
        folders.append(imported)
        folders.append(packageFolder(
            BaseLookGroups.reproduction, from: BaseLookGroups.reproduction, kinds: [.profile],
        ))
        let hidden = recipes.hiddenFolders(in: .baseLooks)
        folders = folders.filter { $0.count > 0 && !hidden.contains($0.name) }
        var listed: Set<String> = []
        let favorite = folders.flatMap(\.allEntries).filter {
            recipes.isFavorite(id: $0.favoriteID) && listed.insert($0.favoriteID).inserted
        }
        if !favorite.isEmpty {
            folders.insert(LookFolder(name: favorites, entries: favorite), at: 0)
        }
        return folders
    }

    /// The looks matching every word of `query`, in the folders' order and each once: names,
    /// summaries, makers and kinds ("kodak", "slide", "black and white"). Profile, film, simulation
    /// and LUT list a whole kind, as Lightroom's words do in the Recipes panel's search.
    static func search(_ query: String, in folders: [LookFolder]) -> [LookEntry] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return folders.filter { $0.name != favorites }.flatMap(\.allEntries).filter { entry in
            terms.allSatisfy { term in
                switch term {
                case "profile", "profiles": entry.kinds.contains(.profile)
                case "film", "films": entry.kinds.contains(.film)
                case "simulation", "simulations": entry.kinds.contains(.simulation)
                case "lut", "luts", "cube": entry.kinds.contains(.lut)
                default: entry.text.contains(term)
                }
            }
        }
    }

    /// The folders holding `look`, outermost first, Favorites left out: those that open to show it.
    static func path(to look: BaseLookReference, in folders: [LookFolder]) -> [String] {
        for folder in folders where folder.name != favorites {
            if folder.entries.contains(where: { $0.isLook(of: look) }) {
                return [folder.name]
            }
            let inner = path(to: look, in: folder.subfolders)
            if !inner.isEmpty {
                return [folder.name] + inner
            }
        }
        return []
    }

    /// The look the panel lists with the id `id`.
    static func entry(id: String, in model: EditorModel) -> LookEntry? {
        folders(model).flatMap(\.allEntries).first { $0.look.id == id }
    }

    // MARK: - Entries

    /// The photo's camera profiles as Basic's menu lists them: Adobe Raw, Camera Matching and your
    /// own, then Adobe's creative groups inside one Creative folder.
    private static func cameraProfileFolders(_ model: EditorModel) -> [LookFolder] {
        var folders: [LookFolder] = []
        var creative: [LookFolder] = []
        for section in model.cameraProfileSections {
            let folder = LookFolder(name: section.name, entries: section.looks.map { look in
                entry(
                    look.reference, summary: look.summary, folder: section.name, kinds: [.profile],
                    monochrome: look.isMonochrome,
                )
            })
            let isCreative = section.looks.allSatisfy {
                if case .creative = $0.group {
                    true
                } else {
                    false
                }
            }
            if isCreative {
                creative.append(folder)
            } else {
                folders.append(folder)
            }
        }
        if !creative.isEmpty {
            folders.append(LookFolder(name: Self.creative, entries: [], subfolders: creative))
        }
        return folders
    }

    private static let monochromeWords = "black and white b&w monochrome"

    private static func entry(
        _ look: BaseLookReference, summary: String?, folder: String, kinds: Set<LookEntry.Kind>,
        monochrome: Bool = false,
    ) -> LookEntry {
        LookEntry(
            look: look, name: look.name, summary: summary, folder: folder, kinds: kinds,
            text: words([look.name, summary, folder, monochrome ? monochromeWords : nil]),
        )
    }

    private static func entry(_ package: BaseLookPackage, folder: String, kinds: Set<LookEntry.Kind>) -> LookEntry {
        LookEntry(
            look: package.reference, name: package.name, summary: package.summary, folder: folder, kinds: kinds,
            text: words([
                package.name,
                package.summary,
                folder,
                package.parameters.isMonochrome ? monochromeWords : nil,
            ]),
        )
    }

    /// A film stock with its maker, format and kind; one of the firmware model's simulations, which
    /// are Fujifilm's; an imported LUT.
    private static func entry(_ recipe: Recipe, folder: String, kinds: Set<LookEntry.Kind>) -> LookEntry? {
        guard let look = recipe.baseLook else { return nil }
        var parts: [String?] = [recipe.name, recipe.summary, folder]
        if let film = FilmLookCatalog.look(forBaseLookID: look.id) {
            parts += [film.maker, film.format, kindWords(film)]
        } else if recipe.settings.treatment == .blackAndWhite {
            parts.append(monochromeWords)
        }
        if folder == RecipeLibrary.firmwareGroup || folder == FujifilmLUT.group {
            parts.append("fujifilm")
        }
        return LookEntry(
            look: look, name: recipe.name, summary: recipe.summary, folder: folder, recipe: recipe, kinds: kinds,
            text: words(parts),
        )
    }

    /// The kind a film stock is browsed by in the Film Looks window.
    private static func kindWords(_ film: FilmLookDefinition) -> String {
        if film.isMonochrome {
            return monochromeWords
        }
        if film.icon.shape == .reel || film.film.contains("cinestill") {
            return "cinema motion picture"
        }
        return film.icon.shape == .slide ? "slide reversal" : "colour color negative"
    }

    private static func words(_ parts: [String?]) -> String {
        parts.compactMap(\.self).joined(separator: " ").lowercased()
    }
}
