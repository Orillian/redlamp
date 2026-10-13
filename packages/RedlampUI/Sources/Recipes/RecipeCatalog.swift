import Foundation
import Observation
import RedlampEngineAPI
import RedlampRecipes

/// The recipe library as the UI sees it: observable, and kept in step with the engine so
/// every Base Look it lists can render.
@MainActor
@Observable
public final class RecipeCatalog {
    @ObservationIgnored public let library: RecipeLibrary
    @ObservationIgnored let engine: any EditingEngine
    /// Bumped on every change; list views observe it through the accessors below.
    public private(set) var revision = 0
    public private(set) var lastError: String?
    /// The Recipes panel's lists imports have added to since the panel last took them.
    @ObservationIgnored private var importedLists: Set<String> = []
    /// The looks given to the engine, by id, version and table hash.
    @ObservationIgnored private var registered: Set<String> = []
    /// The firmware model's folder while its switch is on, and what reading it found.
    public internal(set) var firmwareFolder: URL?
    public internal(set) var firmwareStatus: String?
    @ObservationIgnored var defaultsObserver: (any NSObjectProtocol)?

    public init(engine: any EditingEngine, library: RecipeLibrary = RecipeLibrary()) {
        self.engine = engine
        self.library = library
        engine.registerBaseLooks(BuiltInBaseLooks.all.map(Self.source))
        registerLooks()
        observeFirmwareSwitch()
    }

    private static func key(_ package: BaseLookPackage) -> String {
        "\(package.id)@\(package.version)#\(package.table?.sha256 ?? "")"
    }

    /// `package` for the engine to read when a render first uses it.
    private static func source(_ package: BaseLookPackage) -> BaseLookSource {
        BaseLookSource(reference: package.reference, parameters: package.parameters) { try? package.definition() }
    }

    /// Registers the installed and embedded looks the engine doesn't have yet; the bundled
    /// ones never change, and are registered once at launch.
    private func registerLooks() {
        let added = (library.storedLooks + library.all.flatMap(\.embeddedBaseLooks))
            .filter { registered.insert(Self.key($0)).inserted }
        guard !added.isEmpty else { return }
        engine.registerBaseLooks(added.map(Self.source))
    }

    func changed() {
        registerLooks()
        revision &+= 1
    }

    public func reload() {
        library.reload()
        changed()
    }

    // MARK: - Reading

    public var sections: [(name: String, recipes: [Recipe])] {
        _ = revision
        return library.sections
    }

    public var all: [Recipe] {
        _ = revision
        return library.all
    }

    /// Every Base Look version, including older ones edits have pinned.
    public var baseLooks: [BaseLookPackage] {
        _ = revision
        return library.baseLooks
    }

    /// Each look once, at its newest version: what menus and the browser offer. Looks
    /// embedded in photos are offered only with their photo.
    public var currentBaseLooks: [BaseLookPackage] {
        BuiltInBaseLooks.newest(baseLooks).filter { !$0.reference.isEmbedded && !$0.reference.isFirmwareModel }
    }

    /// The looks recipes stand for, by id: the film stocks' and the installed looks a recipe uses as
    /// its Base Look, such as an imported LUT's. The Base Look menu leaves them to the Recipes panel.
    public var recipeLookIDs: Set<String> {
        _ = revision
        let installed = library.all.compactMap(\.baseLook?.id).filter { !$0.hasPrefix(RecipeNamespace.bundled + "/") }
        return Set(FilmLookCatalog.looks.map(\.baseLookID)).union(installed)
    }

    /// The lists imports have added to since the last call, for the panel to open once.
    public func takeImportedLists() -> Set<String> {
        defer { importedLists = [] }
        return importedLists
    }

    public func recipe(id: String) -> Recipe? {
        _ = revision
        return library.recipe(id: id)
    }

    public func search(_ query: String) -> [Recipe] {
        _ = revision
        return library.search(query)
    }

    /// The Base Looks the menu lists that match `query` by name or summary, for the Recipes panel's
    /// search to list after the recipes. Lightroom's "profile", and "base" and "look", find them all.
    public func searchBaseLooks(_ query: String) -> [BaseLookPackage] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return BaseLookGroups.current(in: self).sections.flatMap(\.looks).filter { look in
            terms.allSatisfy { term in
                ["profile", "profiles", "base", "look", "looks"].contains(term)
                    || [look.name, look.summary ?? ""].contains { $0.lowercased().contains(term) }
            }
        }
    }

    public func isFavorite(_ recipe: Recipe) -> Bool {
        _ = revision
        return library.isFavorite(recipe)
    }

    public func package(for reference: BaseLookReference) -> BaseLookPackage? {
        library.package(for: reference)
    }

    public func isUserRecipe(_ recipe: Recipe) -> Bool {
        library.userRecipes.contains { $0.id == recipe.id } || library.installed.contains { $0.id == recipe.id }
    }

    /// Whether an edit's Base Look can render exactly here.
    public func isAvailable(_ reference: BaseLookReference) -> Bool {
        engine.canRender(reference) || library.isAvailable(reference)
    }

    /// Makes a recipe's embedded looks renderable before it is previewed or applied.
    public func prepare(_ recipe: Recipe) {
        for package in recipe.embeddedBaseLooks where registered.insert(Self.key(package)).inserted {
            if let definition = try? package.definition() {
                engine.registerBaseLook(definition)
            }
        }
    }

    // MARK: - Changing

    /// Keeps a look with the installed ones, so edits that use it render without its source,
    /// such as a photo's embedded camera profile look.
    public func remember(_ look: BaseLookDefinition) {
        guard package(for: look.reference) == nil else { return }
        perform {
            try library.lookStore.save(BaseLookPackage(
                id: look.id, version: look.version, name: look.name, parameters: look.parameters, table: look.table,
            ))
            library.reload()
        }
    }

    @discardableResult
    public func save(_ recipe: Recipe) -> Recipe? {
        perform { try library.save(recipe) }
    }

    /// Installs the files `RecipeLibrary.read(importing:)` read, reading the library once; what
    /// came in, with each preset's report, and what didn't, with the reasons.
    @discardableResult
    public func install(_ read: RecipeImportSummary) -> RecipeImportSummary {
        let summary = library.install(read)
        importedLists.formUnion(summary.lists)
        lastError = nil
        changed()
        return summary
    }

    public func delete(_ recipe: Recipe) {
        perform { try library.delete(recipe) }
    }

    public func setFavorite(_ recipe: Recipe, _ favorite: Bool) {
        perform { try library.setFavorite(recipe, favorite) }
    }

    public func export(_ recipe: Recipe, to url: URL) {
        perform { try library.export(recipe, to: url) }
    }

    /// Whether recipe cards' `slot` uses the LUT imported for it, or Redlamp's own look.
    public func setUsesImportedLook(_ slot: FilmSlot, _ imported: Bool) {
        perform { try library.setUsesImportedLook(slot, imported) }
    }

    @discardableResult
    private func perform<T>(_ work: () throws -> T) -> T? {
        do {
            let result = try work()
            lastError = nil
            changed()
            return result
        } catch {
            lastError = "\(error)"
            revision &+= 1
            return nil
        }
    }
}
