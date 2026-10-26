import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary

extension EditDigest {
    /// The digest the store keeps renders of `recipe` under (LIB-17): SHA-256 over a line naming how
    /// the library renders edits, then the recipe's JSON with sorted keys, so the same edit has the same
    /// digest however it was saved, and a change to how edits are rendered makes every render again.
    /// As Shot's temperature and tint are the photo's own, so they're left out. Nil when the recipe
    /// can't be written out.
    init?(rendering recipe: EditRecipe) {
        var recipe = recipe
        if recipe.whiteBalanceMode == .asShot {
            recipe.reset([.temperature, .tint])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan",
        )
        guard let json = try? encoder.encode(recipe) else { return nil }
        self.init(hashing: Data(EditRenders.renderVersion.utf8) + json)
    }
}

extension EditRenders {
    /// The edits in `photo`'s sidecar as `store` reads them, the photo's own under nil and each version's under its
    /// ID, from its `edit.json` alone, as its summary is read: no mask bitmaps, history or file coordination, since the
    /// JSON is only ever replaced atomically. None when there's no sidecar or it can't be read.
    nonisolated static func recipes(of photo: URL, in store: SidecarStore) -> [UUID?: EditRecipe] {
        let sidecar = store.locator.readURL(for: photo)
        guard let data = (try? Data(contentsOf: sidecar.appending(path: SidecarStore.editFile)))
            ?? (try? Data(contentsOf: sidecar))
        else { return [:] }
        struct Version: Decodable {
            var id: UUID
            var recipe: EditRecipe
        }
        struct Probe: Decodable {
            var recipe: EditRecipe
            var versions: [Version]?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(Probe.self, from: data) else { return [:] }
        var recipes: [UUID?: EditRecipe] = [nil: probe.recipe]
        for version in probe.versions ?? [] {
            recipes[version.id] = version.recipe
        }
        return recipes
    }
}
