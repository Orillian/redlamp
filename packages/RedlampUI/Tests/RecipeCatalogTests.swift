import Foundation
import RedlampEngineAPI
import RedlampRecipes
import Testing
@_spi(Harness) @testable import RedlampUI

/// The catalog keeps the engine's Base Looks in step with the library, registering only
/// what a change adds.
@MainActor
struct RecipeCatalogTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "recipe-catalog-\(UUID().uuidString)")

    private func catalog(_ engine: StubEngine) throws -> RecipeCatalog {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return RecipeCatalog(engine: engine, library: RecipeLibrary(root: root, includeBundled: false))
    }

    private func grey(_ value: Float, id: String = "local/test/grey") throws -> BaseLookDefinition {
        try BaseLookDefinition(
            id: id, version: 1, name: "Grey", parameters: .identity,
            table: LookTable(size: 3) { _ in SIMD3(repeating: value) },
        )
    }

    @Test func `launch registers every look the library has, reading none of their tables`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = StubEngine()
        let catalog = try catalog(engine)
        #expect(engine.registeredLooks.isEmpty)
        let sources = engine.lookSources
        let read = sources.compactMap { $0.load() }
        #expect(read.count == sources.count)
        #expect(Set(read) == Set(catalog.baseLooks.compactMap { try? $0.definition() }))
        #expect(zip(sources, read).allSatisfy { $0.reference == $1.reference && $0.parameters == $1.parameters })
    }

    @Test func `Redlamp Reproduction has a section of its own, after the others`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(StubEngine())
        let sections = BaseLookGroups(catalog.currentBaseLooks).sections
        #expect(sections.last?.name == "Reproduction")
        #expect(sections.last?.looks.map(\.id) == [BuiltInBaseLook.reproduction.rawValue])
        let redlamp = try #require(sections.first { $0.name == "Redlamp" })
        #expect(Set(redlamp.looks.map(\.id)) ==
            Set(BuiltInBaseLook.allCases.filter { $0 != .reproduction }.map(\.rawValue)))
    }

    private func saveLUTRecipe(_ catalog: RecipeCatalog, look: BaseLookDefinition) {
        catalog.save(Recipe(
            id: "user/test/lut", name: "LUT", group: "Mine", includes: [.baseLook], settings: RecipeSettings(),
            baseLook: look.reference,
            embeddedBaseLooks: [BaseLookPackage(id: look.id, name: look.name, table: look.table)],
        ))
    }

    @Test func `the Base Look sections leave film stocks and the looks recipes use to the Recipes panel`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(StubEngine())
        let used = try grey(0.5, id: "local/test/used")
        saveLUTRecipe(catalog, look: used)
        let unused = try grey(0.25, id: "local/test/unused")
        catalog.remember(unused)
        let sections = BaseLookGroups.current(in: catalog).sections
        let listed = Set(sections.flatMap(\.looks).map(\.id))
        #expect(listed.isDisjoint(with: FilmLookCatalog.looks.map(\.baseLookID)))
        #expect(!listed.contains(used.id))
        #expect(listed.contains(unused.id))
        #expect(sections.first?.name == "Redlamp")
        #expect(!sections.contains { ["Film Stocks", FujifilmLUT.group].contains($0.name) })
    }

    @Test func `the photo's look comes first when no section lists it`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(StubEngine())
        let used = try grey(0.5, id: "local/test/used")
        saveLUTRecipe(catalog, look: used)
        let shown = BaseLookGroups.shown(in: catalog, photoLook: used.reference)
        #expect(shown.first?.name == BaseLookGroups.inUse)
        #expect(shown.first?.looks.map(\.id) == [used.id])
        #expect(BaseLookGroups.shown(in: catalog, photoLook: BuiltInBaseLook.vivid.reference).first?.name == "Redlamp")
    }

    @Test func `the Base Look search finds the looks the menu lists, and Lightroom's word finds them all`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(StubEngine())
        #expect(catalog.searchBaseLooks("vivid").map(\.id).contains(BuiltInBaseLook.vivid.rawValue))
        #expect(catalog.searchBaseLooks("ektar").isEmpty)
        #expect(catalog.searchBaseLooks("").isEmpty)
        let listed = BaseLookGroups.current(in: catalog).sections.flatMap(\.looks)
        #expect(catalog.searchBaseLooks("profile").map(\.id) == listed.map(\.id))
    }

    @Test func `toggling a favourite registers nothing`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = StubEngine()
        let catalog = try catalog(engine)
        let recipe = try #require(catalog.save(Recipe(
            id: "user/test/plain", name: "Plain", group: "Mine", includes: [.tone], settings: RecipeSettings(),
        )))
        let before = engine.lookSources.count
        catalog.setFavorite(recipe, true)
        catalog.setFavorite(recipe, false)
        #expect(engine.lookSources.count == before)
    }

    @Test func `adding a look registers that look alone`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = StubEngine()
        let catalog = try catalog(engine)
        let before = engine.lookSources.count
        let look = try grey(0.5)
        catalog.remember(look)
        #expect(engine.lookSources.count == before + 1)
        #expect(engine.lookSources.last?.load() == look)

        let changed = try grey(0.25)
        catalog.remember(changed)
        #expect(engine.lookSources.count == before + 2)
        #expect(engine.lookSources.last?.load() == changed)
    }

    @Test func `previewing a recipe again registers its embedded look once`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = StubEngine()
        let catalog = try catalog(engine)
        let look = try grey(0.5, id: "local/test/embedded")
        let recipe = Recipe(
            id: "user/test/embedded", name: "Embedded", group: "Mine", includes: [.tone], settings: RecipeSettings(),
            baseLook: look.reference,
            embeddedBaseLooks: [BaseLookPackage(id: look.id, name: look.name, table: look.table)],
        )
        let before = engine.registeredLooks.count
        catalog.prepare(recipe)
        catalog.prepare(recipe)
        #expect(engine.registeredLooks.count == before + 1)
    }
}
