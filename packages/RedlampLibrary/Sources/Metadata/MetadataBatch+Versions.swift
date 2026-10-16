import Foundation
import RedlampDocument
import RedlampEngineAPI

/// What an edit a batch brings does to its photo's sidecar (EDT-23): its `recipe` and `snapshots`, and the versions
/// it adds (EDT-09) under the sidecar's `versions` key, which Undo takes back one by one, so the versions the
/// photographer had are left as they are.
extension MetadataBatch.Develop {
    /// The sidecar's `recipe`, `snapshots` and `versions` once the batch is done, from `current`'s and from
    /// `sidecar`, the whole of it, whose metadata `fields` changes. An unedited photo takes the edit, and the
    /// snapshots after those it has; an edited one keeps its edit, which with `whileEdited` goes in a version of
    /// its own. `versions` follow those it has. An edit converted from the same photo of the same catalog as the
    /// photo's edit or one of its versions isn't brought again.
    func applied(to current: MetadataValues, of sidecar: Sidecar, fields: MetadataValues) -> MetadataValues {
        let snapshots = current["snapshots"] ?? .null
        let had = current["versions"]?.arrayValue ?? []
        var values: MetadataValues = [
            "recipe": current["recipe"] ?? .null, "snapshots": snapshots, "versions": current["versions"] ?? .null,
        ]
        let origins = Self.origins(of: current["recipe"], had)
        let unedited = sidecar.recipe.isPristine
        if unedited, let recipe, Self.isNew(recipe, origins) {
            values["recipe"] = recipe
            values["snapshots"] = .array((snapshots.arrayValue ?? []) + self.snapshots)
        }
        let added = added(after: had, origins: origins, edited: !unedited) { sidecar.setting(fields) ?? sidecar }
        if !added.isEmpty {
            values["versions"] = .array(had + added)
        }
        return values
    }

    /// The versions the batch gives `sidecar`, as it is, after those it has: the edit in a version of its own while
    /// the photo is `edited`, and `versions`.
    func added(to sidecar: Sidecar, edited: Bool) -> [JSONValue] {
        let had = sidecar.versionsValue.arrayValue ?? []
        return added(after: had, origins: Self.origins(of: JSONValue(sidecar: sidecar.recipe), had), edited: edited) {
            sidecar
        }
    }

    /// The versions the batch adds after `had`, a sidecar's as it writes them: while the photo is `edited`, the
    /// edit in a version of its own, made from `photo`; and `versions`, each named. None converted from where the
    /// photo's edit or one of `had` was (`origins`).
    private func added(
        after had: [JSONValue], origins: Set<EditOrigin>, edited: Bool, photo: () -> Sidecar,
    ) -> [JSONValue] {
        var added: [JSONValue] = []
        if edited, let recipe, Self.isNew(recipe, origins), let whileEdited,
           let version = version(whileEdited, of: photo()) {
            added.append(version)
        }
        for version in versions ?? [] where Self.isNew(version.objectValue?["recipe"], origins) {
            added.append(Self.named(version, after: had + added))
        }
        return added
    }

    /// Where the photo's edit (`recipe`) and its versions (`had`) were converted from.
    private static func origins(of recipe: JSONValue?, _ had: [JSONValue]) -> Set<EditOrigin> {
        Set(([recipe] + had.map { $0.objectValue?["recipe"] }).compactMap { EditOrigin(recipe: $0) })
    }

    /// Whether `edit` wasn't converted from any of `origins`: one made in Redlamp never was.
    private static func isNew(_ edit: JSONValue?, _ origins: Set<EditOrigin>) -> Bool {
        EditOrigin(recipe: edit).map { !origins.contains($0) } ?? true
    }

    /// The version `named`, with this edit and its snapshots, made from `photo` as Create Version makes one: its
    /// metadata the photo's, but for what describes the file, its stack and its mark. Nil without an edit.
    private func version(_ named: Version, of photo: Sidecar) -> JSONValue? {
        var photo = photo
        guard let recipe, let made = photo.addVersion(of: nil, id: named.id, named: named.name, created: named.created),
              case var .object(version)? = JSONValue(sidecar: made)
        else { return nil }
        version["recipe"] = recipe
        version["snapshots"] = .array(snapshots)
        return .object(version)
    }

    /// `version`, named as Create Version would name the next after `versions` when it has no name.
    static func named(_ version: JSONValue, after versions: [JSONValue]) -> JSONValue {
        guard case var .object(object) = version, (object["name"]?.textValue ?? "").isEmpty else { return version }
        var sidecar = Sidecar(recipe: EditRecipe())
        sidecar.versions = versions.compactMap { $0.objectValue?["name"]?.textValue }.map {
            PhotoVersion(name: $0, recipe: EditRecipe())
        }
        object["name"] = .string(sidecar.nextVersionName)
        return .object(object)
    }
}

/// Where an edit converted from Lightroom's settings came from, as its recipe's provenance says (EDT-23): edits with
/// the same one were converted from the same photo or virtual copy of the same catalog, or from the same file.
struct EditOrigin: Hashable {
    let source: JSONValue
    let path: JSONValue
    let photo: JSONValue

    /// `recipe`'s, as the sidecar writes it; nil for an edit made in Redlamp.
    init?(recipe: JSONValue?) {
        guard let provenance = recipe?.objectValue?["provenance"]?.objectValue else { return nil }
        source = provenance["source"] ?? .null
        path = provenance["path"] ?? .null
        photo = provenance["photo"] ?? .null
    }
}

extension Sidecar {
    /// Its versions as it writes them.
    var versionsValue: JSONValue {
        JSONValue(sidecar: versions) ?? .null
    }

    /// The sidecar with `value`'s versions in place of its own; nil when they aren't what it can hold.
    func setting(versions value: JSONValue) -> Sidecar? {
        var sidecar = self
        if value == .null || value.arrayValue?.isEmpty == true {
            sidecar.versions = []
        } else {
            guard let list = value.decoded(as: [PhotoVersion].self) else { return nil }
            sidecar.versions = list
        }
        return sidecar
    }
}

/// `now`'s versions with what a batch did to them (`was` before it, `made` after it) taken back one at a time, by
/// their IDs: one it added goes, one it changed is as it was and one it took off comes back, each unless it changed
/// since; the others stay as they are.
func undoneVersions(_ now: JSONValue, was: JSONValue, made: JSONValue) -> JSONValue {
    func id(_ version: JSONValue) -> JSONValue {
        version.objectValue?["id"] ?? .null
    }
    let before = Dictionary((was.arrayValue ?? []).map { (id($0), $0) }) { first, _ in first }
    let after = Dictionary((made.arrayValue ?? []).map { (id($0), $0) }) { first, _ in first }
    var versions: [JSONValue] = []
    for version in now.arrayValue ?? [] {
        guard let given = after[id(version)], given == version else {
            versions.append(version)
            continue
        }
        if let old = before[id(version)] {
            versions.append(old)
        }
    }
    let kept = Set(versions.map(id))
    for version in was.arrayValue ?? [] where after[id(version)] == nil && !kept.contains(id(version)) {
        versions.append(version)
    }
    return .array(versions)
}
