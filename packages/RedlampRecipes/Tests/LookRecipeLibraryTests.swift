import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// Which recipes are looks and which presets (DEC-104), hidden folders, and Move to Trash (UX-55).
struct LookRecipeLibraryTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "looks-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A library whose Trash is a folder of the test's own.
    private func library(bundled: Bool = true) -> RecipeLibrary {
        let library = RecipeLibrary(root: root.appending(path: "library"), includeBundled: bundled)
        let trash = root.appending(path: "Trash")
        library.trash = { url in
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            let moved = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: moved)
            return moved
        }
        return library
    }

    private static func lut(_ name: String) throws -> Recipe {
        let table = try LookTableImport.parseCube(LookTableFixtures.cube(size: 5, LookTableFixtures.grade)).table
        return LookTableImport.recipe(for: table, name: name)
    }

    @Test func `film stocks, the firmware model's simulations and imported LUTs are looks, and presets aren't`() throws {
        #expect(!FilmLookCatalog.bundledRecipes.contains { !$0.isLook })
        #expect(!StarterPack.recipes.contains { $0.isLook }, "a starter recipe with a look is a preset")
        #expect(!MoodLooks.recipes.contains { $0.isLook }, "a mood is a preset built on a film stock")
        var lut = try Self.lut("Teal")
        #expect(lut.isLook)
        lut.includes.insert(.effects)
        lut.settings.values[.vignetteAmount] = -20
        #expect(!lut.isLook, "a LUT made into a fuller recipe is a preset")
        let simulation = Recipe(
            id: RecipeLibrary.firmwareIDPrefix + "chrome", name: "Classic Chrome", group: RecipeLibrary.firmwareGroup,
            includes: [.baseLook, .treatment], settings: RecipeSettings(treatment: .color),
            baseLook: BaseLookReference(id: "local/firmware/chrome", name: "Classic Chrome"),
        )
        #expect(simulation.isLook)
    }

    @Test func `each look has its Base Looks folder, and an import says which panel each file went to`() throws {
        let lut = try Self.lut("Teal")
        var fujifilm = lut
        fujifilm.tags = ["lut", "fujifilm"]
        let portra = try #require(FilmLookCatalog.bundledRecipes.first)
        #expect(lut.lookFolder == RecipeLibrary.importedLooksFolder && fujifilm.lookFolder == FujifilmLUT.group)
        #expect(portra.lookFolder == FilmLookCatalog.group)
        let preset = Recipe(
            id: RecipeNamespace.newLocalID(), name: "Fade", group: "Lightroom", includes: [.tone],
            settings: RecipeSettings(),
        )
        #expect(preset.lookFolder == nil)
        let summary = RecipeImportSummary(items: [
            .init(file: URL(fileURLWithPath: "/Imports/teal.cube"), outcome: .imported(RecipeImport(recipe: lut))),
            .init(file: URL(fileURLWithPath: "/Imports/fade.xmp"), outcome: .imported(RecipeImport(recipe: preset))),
        ])
        #expect(summary.lists == ["Lightroom"] && summary.lookFolders == [RecipeLibrary.importedLooksFolder])
        #expect(summary.placement == "In the Recipes panel under Lightroom, and the Base Looks panel under Imported")
    }

    @Test func `the Recipes panel lists presets only, in its sections, favourites and search`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library()
        let lut = try library.install(RecipeImport(recipe: Self.lut("Teal"))).recipe
        let stock = try #require(FilmLookCatalog.look("portra-400"))
        let portra = try #require(library.recipe(id: stock.recipeID))
        let essential = try #require(library.bundled.first { $0.group == "Essentials" })
        try library.setFavorite(portra, true)
        try library.setFavorite(essential, true)
        let sections = library.sections
        let names = sections.map(\.name)
        #expect(!names.contains(FilmLookCatalog.group) && !names.contains("Imported"))
        #expect(names.contains("Mood") && names.contains("Essentials"))
        #expect(sections.first { $0.name == "Favorites" }?.recipes.map(\.id) == [essential.id])
        #expect(sections.flatMap(\.recipes).allSatisfy { !$0.isLook })
        #expect(library.lookRecipes.contains { $0.id == lut.id } && library.lookRecipes.contains { $0.id == portra.id })
        let found = library.search("portra", among: library.presets)
        #expect(!found.contains { $0.isLook } && found.contains { $0.name == "Golden Leak" })
        #expect(library.search("portra").contains { $0.id == portra.id }, "the command line still finds film stocks")
    }

    @Test func `hidden folders are saved and read again, and leave the Recipes panel, but not your own lists`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library()
        #expect(library.bundledGroups.contains("Portrait") && !library.bundledGroups.contains(FilmLookCatalog.group))
        try library.setHidden("Portrait", in: .recipes, true)
        try library.setHidden(FilmLookCatalog.group, in: .baseLooks, true)
        var mine = try #require(library.bundled.first { $0.group == "Portrait" })
        mine.id = RecipeNamespace.newLocalID()
        mine.name = "My Portrait"
        try library.save(mine)

        let reopened = self.library()
        #expect(reopened.hiddenFolders(in: .recipes) == ["Portrait"])
        #expect(reopened.isHidden(FilmLookCatalog.group, in: .baseLooks))
        #expect(!reopened.isHidden(FilmLookCatalog.group, in: .recipes), "each panel hides its own folders")
        let portrait = reopened.sections.first { $0.name == "Portrait" }
        #expect(portrait?.recipes.map(\.name) == ["My Portrait"], "your list named Portrait stays")
        #expect(!reopened.presets.contains { $0.isBundled && $0.group == "Portrait" })
        #expect(!reopened.search("portrait", among: reopened.presets)
            .contains { $0.isBundled && $0.group == "Portrait" })

        try reopened.setHidden("Portrait", in: .recipes, false)
        #expect(self.library().hiddenFolders(in: .recipes).isEmpty)
        #expect(reopened.presets.contains { $0.isBundled && $0.group == "Portrait" })
    }

    @Test func `Move to Trash moves the file, and leaves its look renderable but listed nowhere`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(bundled: false)
        let lut = try library.install(RecipeImport(recipe: Self.lut("Teal"))).recipe
        try library.setFavorite(lut, true)
        let file = try #require(library.file(of: lut))
        #expect(file.deletingLastPathComponent().standardizedFileURL == library.locations.recipes.standardizedFileURL)
        let look = try #require(lut.baseLook)
        let package = try #require(library.package(for: look))
        #expect(!library.isUnlisted(package))

        let trashed = try library.moveToTrash(lut)
        #expect(trashed.count == 1 && trashed.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(library.recipe(id: lut.id) == nil && !library.favorites.contains(lut.id))
        #expect(library.isAvailable(look) && library.definition(for: look) != nil, "its edits keep rendering")
        #expect(library.isUnlisted(package))
        #expect(self.library(bundled: false).isUnlisted(package), "kept across launches")
    }

    @Test func `a look another recipe uses stays listed, and Redlamp's own looks are never unlisted`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library()
        let lut = try library.install(RecipeImport(recipe: Self.lut("Teal"))).recipe
        let look = try #require(lut.baseLook)
        var edit = EditRecipe()
        edit.baseLook = look
        let preset = try library.save(Recipe.capture(
            edit, name: "Teal Preset", includes: [.baseLook], embedding: lut.embeddedBaseLooks,
        ))
        try library.moveToTrash(lut)
        let package = try #require(library.package(for: look))
        #expect(!library.isUnlisted(package))

        let portra = try #require(FilmLookCatalog.look("portra-400"))
        let film = try #require(BuiltInBaseLooks.package(id: portra.baseLookID, version: portra.version))
        edit.baseLook = film.reference
        let onFilm = try library.save(Recipe.capture(edit, name: "On Portra", includes: [.baseLook]))
        try library.moveToTrash(onFilm)
        try library.moveToTrash(preset)
        #expect(!library.isUnlisted(film))
        #expect(library.isUnlisted(package))
    }

    @Test func `an installed recipe goes to the Trash with every version of it`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(bundled: false)
        for version in [1, 2] {
            try library.install(RecipeImport(recipe: Recipe(
                id: "someone/warm", version: version, name: "Warm", group: "Theirs", includes: [.tone],
                settings: RecipeSettings(values: [.exposure: 0.1 * Double(version)]),
            )))
        }
        let installed = try #require(library.recipe(id: "someone/warm"))
        #expect(library.file(of: installed)?.deletingLastPathComponent().standardizedFileURL
            == library.locations.installed.standardizedFileURL)
        #expect(try library.moveToTrash(installed).count == 2)
        #expect(library.installed.isEmpty)
    }
}
