import Foundation
import RedlampEngineAPI

public extension Recipe {
    /// Whether the recipe stands for a look, listed in Base Looks rather than with the presets in
    /// Recipes (DEC-104): a bundled film stock, one of the firmware model's simulations, or an imported
    /// LUT, which sets nothing but its Base Look. A LUT made into a fuller recipe is a preset.
    var isLook: Bool {
        if isBundled {
            return FilmLookCatalog.look(forBundledID: id) != nil
        }
        return id.hasPrefix(RecipeLibrary.firmwareIDPrefix) || isImportedLookTable
    }

    /// Whether the recipe is an imported look table that sets nothing but its Base Look.
    var isImportedLookTable: Bool {
        tags.contains("lut") && includes == [.baseLook] && baseLook != nil
    }

    /// The Base Looks panel's folder a look is listed in; nil for a preset.
    var lookFolder: String? {
        guard isLook else { return nil }
        if isBundled {
            return FilmLookCatalog.group
        }
        if id.hasPrefix(RecipeLibrary.firmwareIDPrefix) {
            return RecipeLibrary.firmwareGroup
        }
        return tags.contains("fujifilm") ? FujifilmLUT.group : RecipeLibrary.importedLooksFolder
    }
}

/// The Base Looks panel and the Recipes panel, whose built-in folders can be hidden (UX-55).
public enum RecipePanel: String, Codable, Sendable, CaseIterable {
    case baseLooks, recipes
}

public extension RecipeLibrary {
    /// The Base Looks panel's folder of the LUTs the photographer imported.
    static let importedLooksFolder = "Imported"

    /// The recipes the Recipes panel lists: every recipe that isn't a look, those in hidden folders
    /// left out.
    var presets: [Recipe] {
        all.filter { !$0.isLook && !isHidden($0) }
    }

    /// The recipes that stand for looks, which the Base Looks panel lists.
    var lookRecipes: [Recipe] {
        all.filter(\.isLook)
    }

    // MARK: - Hidden folders

    /// The built-in folders hidden from `panel`, by name.
    func hiddenFolders(in panel: RecipePanel) -> Set<String> {
        hiddenByPanel[panel] ?? []
    }

    func isHidden(_ folder: String, in panel: RecipePanel) -> Bool {
        hiddenFolders(in: panel).contains(folder)
    }

    /// Whether a recipe is in a bundled group hidden from the Recipes panel.
    func isHidden(_ recipe: Recipe) -> Bool {
        recipe.isBundled && isHidden(recipe.group, in: .recipes)
    }

    /// Hides one of a panel's built-in folders, or shows it again. Both panels' hidden folders are
    /// kept together, as one preference.
    func setHidden(_ folder: String, in panel: RecipePanel, _ hidden: Bool) throws {
        var folders = hiddenFolders(in: panel)
        if hidden {
            folders.insert(folder)
        } else {
            folders.remove(folder)
        }
        hiddenByPanel[panel] = folders.isEmpty ? nil : folders
        let saved = Dictionary(uniqueKeysWithValues: hiddenByPanel.map { ($0.key.rawValue, $0.value.sorted()) })
        try FileManager.default.createDirectory(at: locations.recipes, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try encoder.encode(saved).write(to: locations.hiddenFolders, options: .atomic)
    }

    // MARK: - Removing

    /// The file Redlamp keeps a recipe made here or installed in; nil for a bundled recipe and the
    /// firmware model's.
    func file(of recipe: Recipe) -> URL? {
        files[RecipeVersion(id: recipe.id, version: recipe.version)]
    }

    /// Moves a recipe made here or installed, every version of it, to the Trash, where it can be
    /// recovered from. Its Base Looks stay, so the edits that use them keep rendering, but a look no
    /// other recipe uses is listed nowhere afterwards. Returns where the files went.
    @discardableResult
    func moveToTrash(_ recipe: Recipe) throws -> [URL] {
        let doomed = files.filter { $0.key.id == recipe.id }.map(\.value)
            .sorted { $0.path < $1.path }
        guard !doomed.isEmpty else { return [] }
        var trashed: [URL] = []
        for url in doomed {
            trashed += try trash(url).map { [$0] } ?? []
        }
        let remaining = (userRecipes + installed).filter { $0.id != recipe.id }
        let used = Set(remaining.flatMap { $0.embeddedBaseLooks.map(\.reference) + [$0.baseLook].compactMap(\.self) }
            .map(Self.key))
        let looks = recipe.embeddedBaseLooks.map(\.reference) + [recipe.baseLook].compactMap(\.self)
        let unlisted = looks.filter { BuiltInBaseLooks.package(id: $0.id, version: $0.version) == nil }
            .map(Self.key).filter { !used.contains($0) }
        if !unlisted.isEmpty {
            try saveUnlistedLooks(unlistedLooks.union(unlisted))
        }
        if favorites.contains(recipe.id) {
            try setFavorite(recipe, false)
        }
        reload()
        return trashed
    }

    /// Lists an installed look no recipe uses nowhere (Remove from Base Looks): its file stays in `Looks/`,
    /// named by its content, so the edits that use it keep rendering. Redlamp's own looks are never unlisted.
    func unlist(_ look: BaseLookReference) throws {
        guard BuiltInBaseLooks.package(id: look.id, version: look.version) == nil else { return }
        try saveUnlistedLooks(unlistedLooks.union([Self.key(look)]))
        if favorites.contains(look.id) {
            try setFavorite(id: look.id, false)
        }
    }

    /// Whether a look went to the Trash with its recipe, or was removed from Base Looks: the edits that
    /// use it still render with it, but no list shows it.
    func isUnlisted(_ package: BaseLookPackage) -> Bool {
        unlistedLooks.contains(Self.key(package.reference))
    }

    /// A look version's key: its id, version and table.
    internal static func key(_ look: BaseLookReference) -> String {
        "\(look.id)@\(look.version)#\(look.contentHash ?? "")"
    }

    private func saveUnlistedLooks(_ looks: Set<String>) throws {
        try FileManager.default.createDirectory(at: locations.recipes, withIntermediateDirectories: true)
        try JSONEncoder().encode(looks.sorted()).write(to: locations.unlistedLooks, options: .atomic)
        unlistedLooks = looks
    }

    /// Moves a file to the Trash, returning where it went.
    static func moveToSystemTrash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
}

/// A recipe version, as the files it was read from are known by.
struct RecipeVersion: Hashable {
    var id: String
    var version: Int
}
