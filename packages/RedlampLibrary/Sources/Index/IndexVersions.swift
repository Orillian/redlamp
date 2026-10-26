import Foundation
import RedlampDocument

/// The rows of versions of photos (LIB-48, EDT-09): each version of a file's edit, Lightroom Classic's virtual copy, is
/// a photo of its own to the library, a row with its file's folder, name and file fields and its own organising fields,
/// keywords, collections and edit, written from the version's metadata in the file's sidecar.
extension LibraryIndex.Writer {
    /// The columns a file's versions take from its own row: what describes the file, its capture time with the shift
    /// and zone its sidecar gives the photo, and its state. The rest are each version's own.
    static let fileFields = [
        "kind", "size", "modified", "file_id", "content_key", "captured", "captured_offset", "camera", "lens", "iso",
        "aperture", "shutter", "focal", "width", "height", "orientation", "latitude", "longitude", "sidecar_modified",
        "xmp_modified", "state", "indexed", "xmp_signature", "camera_captured", "camera_offset", "missing_since",
        "widest_aperture", "focal35",
    ]

    /// What `setVersions` changed: the versions' rows added, written again and removed.
    public struct VersionRows: Sendable, Hashable {
        public var inserted: [Int64] = []
        public var updated: [Int64] = []
        public var removed: [Int64] = []

        /// Every row it names.
        public var all: [Int64] {
            inserted + updated + removed
        }
    }

    /// Gives the file whose own row is `photo` a row for each of `versions` and no others, each with its version's
    /// organising fields, keywords and collections and the file's fields as its row has them now.
    @discardableResult
    public func setVersions(_ versions: [VersionSummary], ofPhoto photo: Int64) throws -> VersionRows {
        guard let file = try self.photo(id: photo), file.version == nil else { return VersionRows() }
        let had = try self.versions(folder: file.folder, name: file.name)
        let wanted = Set(versions.map(\.id))
        var rows = VersionRows(removed: had.filter { !wanted.contains($0.version ?? UUID()) }.map(\.id))
        try deletePhotos(rows.removed)
        guard !versions.isEmpty else { return rows }
        let existing = Set(had.map(\.id))
        let ids = try upsertPhotos(versions.map { PhotoRecord(version: $0, of: file) })
        for (version, id) in zip(versions, ids) {
            try setKeywords(version.metadata.keywords.map(KeywordPath.texts) ?? [], forPhoto: id)
            try setCollections(version.metadata.collections, forPhoto: id)
            if existing.contains(id) {
                rows.updated.append(id)
            } else {
                rows.inserted.append(id)
            }
        }
        return rows
    }

    /// `setVersions` for the file of `photo`, its own row or a version's, unless its versions' rows are already
    /// `versions` under their names: what a sidecar the library has written holds of its versions, which the batch,
    /// or a writer before it, may have added, renamed or removed.
    @discardableResult
    func followVersions(_ versions: [VersionSummary], ofFileOf photo: Int64) throws -> VersionRows {
        guard let row = try self.photo(id: photo) else { return VersionRows() }
        let had = try self.versions(folder: row.folder, name: row.name)
        let names = Dictionary(versions.map { ($0.id, $0.name) }) { first, _ in first }
        let rows = Dictionary(had.compactMap { row in row.version.map { ($0, row.versionName ?? "") } }) { first, _ in
            first
        }
        guard names != rows else { return VersionRows() }
        guard let file = row.version == nil ? row.id : try self.photo(folder: row.folder, name: row.name)?.id
        else { return VersionRows() }
        return try setVersions(versions, ofPhoto: file)
    }

    /// Gives the versions of `photo`'s file the file's fields as `photo`'s row has them; returns the versions' rows.
    /// Nothing for a photo that's a version itself.
    @discardableResult
    func carryFile(of photo: Int64) throws -> [Int64] {
        let statement = try database.cached("""
        UPDATE photos SET \(Self.fileFields.map { "\($0) = file.\($0)" }.joined(separator: ", "))
        FROM photos AS file WHERE file.id = ?1 AND file.version = '' AND photos.folder = file.folder
          AND photos.name = file.name AND photos.version != '' RETURNING photos.id
        """)
        try statement.bind(photo, at: 1)
        return try statement.map { $0.int64(at: 0) }
    }
}

extension LibraryIndex {
    /// `photos` with the files' own rows of the versions among them (LIB-48): what a batch writing their sidecars
    /// registers as being written, since the indexer writes a version's row with its file's.
    func withFileRows(_ photos: [Int64]) async throws -> [Int64] {
        try await Array(Set(photos).union(read { try $0.fileRows(of: photos) })).sorted()
    }
}

public extension IndexQueries {
    /// The file's own row of the file whose row is `photo`: `photo` itself unless it's a version (LIB-48). Nil when
    /// the index has no such row.
    func fileRow(of photo: Int64) throws -> Int64? {
        let statement = try database.cached("""
        SELECT file.id FROM photos AS row JOIN photos AS file
          ON file.folder = row.folder AND file.name = row.name AND file.version = '' WHERE row.id = ?
        """)
        try statement.bind(photo, at: 1)
        return try statement.first { $0.int64(at: 0) }
    }

    /// The files' own rows of `photos`, each once, in the order they first come: a version stands for its file
    /// (LIB-48). Rows the index doesn't have are left out.
    func fileRows(of photos: [Int64]) throws -> [Int64] {
        var seen = Set<Int64>()
        return try photos.compactMap { try fileRow(of: $0) }.filter { seen.insert($0).inserted }
    }

    /// The versions among `photos`, by row: each one's UUID (LIB-48). Files' own rows aren't in it.
    func photoVersions(_ photos: [Int64]) throws -> [Int64: UUID] {
        let statement = try database.cached("SELECT version FROM photos WHERE id = ? AND version != ''")
        var versions: [Int64: UUID] = [:]
        for photo in photos {
            try statement.bind(photo, at: 1)
            versions[photo] = try statement.first { PhotoRecord.version(code: $0.string(at: 0)) } ?? nil
        }
        return versions
    }
}

extension PhotoRecord {
    /// The row of `version` of the file whose own row is `file`: the file's fields, and the organising fields and edit
    /// the version's metadata gives it, none of them other apps'. The capture time is the file's, which takes the
    /// shift and zone the photo's own metadata gives it.
    init(version: VersionSummary, of file: PhotoRecord) {
        self = file
        id = 0
        self.version = version.id
        versionName = version.name
        let metadata = version.metadata
        let fields = XMPFields(metadata)
        rating = fields.rating ?? 0
        flag = fields.flag
        label = fields.label
        customLabel = fields.label == nil ? XMPFields.text(fields.customLabel) : nil
        title = XMPFields.text(fields.title)
        caption = XMPFields.text(fields.caption)
        creator = XMPSource.joined(XMPFields.names(fields.creator))
        copyright = XMPFields.text(fields.copyright)
        location = XMPFields.place(fields.location)
        otherFields = []
        edited = version.hasEdits
        LibraryIndexer.Run.place(metadata, in: &self)
    }
}

extension VersionSummary {
    /// What the library shows of `version`, as `SidecarStore.summary(for:)` reads it from its sidecar.
    init(_ version: PhotoVersion) {
        self.init(
            id: version.id, name: version.name, created: version.created, hasEdits: !version.recipe.isPristine,
            metadata: version.metadata ?? PhotoMetadata(),
        )
    }
}
