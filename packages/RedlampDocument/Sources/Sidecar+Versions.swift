import Foundation
import RedlampEngineAPI

/// One of a photo's edits, as the editor, saves, Settings Sync and export address it (EDT-09): the file's own
/// edit, or one of its versions. Each is a photo of its own to the library, a row beside its file's (LIB-48).
public struct PhotoAddress: Sendable, Hashable {
    public var url: URL
    /// The version's `id`; nil for the file's own edit.
    public var version: UUID?

    public init(url: URL, version: UUID? = nil) {
        self.url = url
        self.version = version
    }
}

/// What one of a photo's edits holds besides its name: the edit, its snapshots and its metadata.
public struct SidecarEdit: Sendable, Hashable {
    public var recipe: EditRecipe
    public var snapshots: [Snapshot]
    public var metadata: PhotoMetadata?

    public init(recipe: EditRecipe, snapshots: [Snapshot] = [], metadata: PhotoMetadata? = nil) {
        self.recipe = recipe
        self.snapshots = snapshots
        self.metadata = metadata
    }
}

public extension Sidecar {
    /// The version `id`, if the photo has it.
    func version(_ id: UUID) -> PhotoVersion? {
        versions.first { $0.id == id }
    }

    /// The photo's own edit for a nil `version`, or the version's; nil for a version the photo doesn't have.
    /// Setting a version the photo doesn't have changes nothing.
    subscript(edit version: UUID?) -> SidecarEdit? {
        get {
            guard let version else { return SidecarEdit(recipe: recipe, snapshots: snapshots, metadata: metadata) }
            return self.version(version).map {
                SidecarEdit(recipe: $0.recipe, snapshots: $0.snapshots, metadata: $0.metadata)
            }
        }
        set {
            guard let newValue else { return }
            guard let version else {
                recipe = newValue.recipe
                snapshots = newValue.snapshots
                metadata = newValue.metadata
                return
            }
            guard let index = versions.firstIndex(where: { $0.id == version }) else { return }
            versions[index].recipe = newValue.recipe
            versions[index].snapshots = newValue.snapshots
            versions[index].metadata = newValue.metadata
        }
    }

    /// The name Create Version gives the next version: "Copy 1", then one more than the highest copy's number.
    var nextVersionName: String {
        let numbers = versions.compactMap { version -> Int? in
            guard version.name.hasPrefix("Copy ") else { return nil }
            return Int(version.name.dropFirst(5))
        }
        return "Copy \((numbers.max() ?? 0) + 1)"
    }

    /// Adds a version made from the photo's own edit (`source` nil) or from the version `source`, and returns it;
    /// nil for a source the photo doesn't have. It takes the source's edit and its metadata but for what a version
    /// doesn't hold of its own, the file's name and capture time, and for its place in a stack and the quick
    /// collection; it starts without snapshots.
    @discardableResult
    mutating func addVersion(
        of source: UUID?, id: UUID = UUID(), named name: String? = nil, created: Date = Date(),
    ) -> PhotoVersion? {
        guard let edit = self[edit: source] else { return nil }
        var metadata = edit.metadata ?? PhotoMetadata()
        metadata.originalName = nil
        metadata.captureShift = 0
        metadata.captureOffset = nil
        metadata.stack = nil
        metadata.mark = false
        let version = PhotoVersion(
            id: id, name: name ?? nextVersionName, created: created, recipe: edit.recipe,
            metadata: metadata.isEmpty ? nil : metadata,
        )
        versions.append(version)
        return version
    }
}

extension PhotoVersion {
    /// The version as a sidecar of its own, dated `modified`, so it merges by the rules the photo's edit does.
    func asSidecar(modified: Date) -> Sidecar {
        var sidecar = Sidecar(recipe: recipe, snapshots: snapshots, metadata: metadata, modified: modified)
        sidecar.unknownFields = unknownFields
        return sidecar
    }

    /// The version holding `merged`'s edit, snapshots, metadata and unknown fields.
    func holding(_ merged: Sidecar) -> PhotoVersion {
        var version = self
        version.recipe = merged.recipe
        version.snapshots = merged.snapshots
        version.metadata = merged.metadata
        version.unknownFields = merged.unknownFields
        return version
    }
}
