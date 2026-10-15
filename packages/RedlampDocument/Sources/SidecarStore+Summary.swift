import Foundation
import RedlampEngineAPI

/// What the filmstrip shows of a sidecar: whether the photo is edited, and its rating, flag
/// and label.
public struct SidecarSummary: Sendable, Hashable {
    public var hasEdits: Bool
    public var metadata: PhotoMetadata
    /// The photo's versions (EDT-09), in the order they were made.
    public var versions: [VersionSummary]

    public init(hasEdits: Bool = false, metadata: PhotoMetadata = PhotoMetadata(), versions: [VersionSummary] = []) {
        self.hasEdits = hasEdits
        self.metadata = metadata
        self.versions = versions
    }
}

/// What the library shows of one of a photo's versions, as it shows a photo.
public struct VersionSummary: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var created: Date
    public var hasEdits: Bool
    /// The version's own; the file's name and capture time are the photo's.
    public var metadata: PhotoMetadata

    public init(id: UUID, name: String, created: Date, hasEdits: Bool, metadata: PhotoMetadata = PhotoMetadata()) {
        self.id = id
        self.name = name
        self.created = created
        self.hasEdits = hasEdits
        self.metadata = metadata
    }
}

public extension SidecarStore {
    /// The badge-level summary of the image's sidecar, from its `edit.json` alone: no mask
    /// bitmaps, history or conflict resolution, and no file coordination. That is safe because
    /// the JSON is only ever replaced atomically (on its own or with the whole package). Nil when
    /// there is no sidecar or it can't be read. Don't call it for a sidecar iCloud Drive hasn't
    /// downloaded: reading it would wait for the download.
    func summary(for image: URL) -> SidecarSummary? {
        Self.summary(atSidecar: locator.readURL(for: image))
    }

    /// The summary of the sidecar at `sidecar`, a package or a single file, as `summary(for:)`
    /// reads it.
    static func summary(atSidecar sidecar: URL) -> SidecarSummary? {
        guard let data = (try? contents(of: sidecar.appending(path: editFile))) ?? (try? contents(of: sidecar))
        else { return nil }
        struct Version: Decodable {
            var id: UUID
            var name: String
            var created: Date
            var recipe: EditRecipe
            var metadata: PhotoMetadata?
        }
        struct Probe: Decodable {
            var recipe: EditRecipe
            var metadata: PhotoMetadata?
            var versions: [Version]?
        }
        guard let probe = try? JSONDecoder.sidecar.decode(Probe.self, from: data) else { return nil }
        let versions = (probe.versions ?? []).map { version in
            VersionSummary(
                id: version.id, name: version.name, created: version.created, hasEdits: !version.recipe.isPristine,
                metadata: version.metadata ?? PhotoMetadata(),
            )
        }
        return SidecarSummary(
            hasEdits: !probe.recipe.isPristine, metadata: probe.metadata ?? PhotoMetadata(), versions: versions,
        )
    }
}
