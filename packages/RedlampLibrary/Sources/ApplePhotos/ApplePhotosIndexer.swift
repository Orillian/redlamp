import Foundation
import RedlampDocument
import Synchronization

/// Albums of Apple Photos kept in place (LIB-58, DEC-107): their photos are rows of the Apple Photos root, made from
/// what PhotoKit gives of each asset without reading a file, with what Redlamp keeps of them read from their sidecars
/// on
/// this Mac, so a rating, a keyword or an edit made in Redlamp stands over Photos' fields. Rows are written
/// `batchSize` assets at a time, each batch in a transaction of its own, so the first photos list while the rest are
/// written; an asset whose fields, albums and sidecars are as they were when its rows were written isn't written again.
/// A photo that leaves every album kept leaves the library, its sidecar kept, as a removed folder's photos do (LIB-10).
///
/// An asset gives a row for its original's photo, one for a RAW+JPEG pair's raw, named after the photo so the two pair,
/// and one for Photos' rendering of its edit, stacked over the original, which goes on top once it has a Redlamp edit;
/// a burst gives its key photo and the frames picked, stacked. Videos and photos hidden in Photos are left out. Photos
/// is only read (DEC-106).
public final class ApplePhotosIndexer: Sendable {
    /// What a pass found and did.
    public struct Outcome: Sendable, Hashable {
        /// Assets of the albums kept in place with rows in the library.
        public var assets = 0
        public var inserted: [Int64] = []
        public var updated: [Int64] = []
        public var removed: [Int64] = []
        /// Assets whose rows stand as they were.
        public var unchanged = 0
        /// Left out: videos, photos hidden in Photos, and frames of bursts neither the key photo nor picked.
        public var videos = 0
        public var hidden = 0
        public var frames = 0
        /// How long the pass took, and how long until its first batch was written.
        public var elapsed = Duration.zero
        public var firstBatch: Duration?

        public init() {}
    }

    /// Assets written in one transaction.
    public static let batchSize = 1000
    static let albumsKey = "library.applePhotos.albums"

    public let photos: any ApplePhotosLibrary
    public let index: LibraryIndex
    public let paths: LibraryPaths
    /// Hears of the photos each batch adds, changes and takes out, so open lists show them.
    public let live: LibraryLive?
    private let last = Mutex<Task<Outcome, any Error>?>(nil)

    public init(
        photos: any ApplePhotosLibrary, index: LibraryIndex, paths: LibraryPaths? = nil, live: LibraryLive? = nil,
    ) {
        self.photos = photos
        self.index = index
        self.paths = paths ?? LibraryPaths(root: index.url.deletingLastPathComponent())
        self.live = live
    }

    // MARK: - Albums kept in place

    /// The albums kept in place, as they were chosen.
    public func albums() async throws -> [ApplePhotosCollection] {
        try await index.read { try Self.chosen($0) }
    }

    /// Keeps the collections `ids` names in place beside those kept already, then indexes them: an album, a smart album
    /// (Photos' Library for every photo) or a shared album, whose photos are reduced copies, or a folder for the albums
    /// in it, those added to it later included.
    @discardableResult
    public func keep(_ ids: [String]) async throws -> Outcome {
        let tree = try await ApplePhotosTree(photos.collections())
        let found = try ids.map { id in
            guard let collection = tree[id] else { throw ApplePhotosError.notFound(id) }
            return collection
        }
        try await index.write { writer in
            var chosen = try Self.chosen(writer)
            for collection in found where !chosen.contains(where: { $0.id == collection.id }) {
                chosen.append(collection)
            }
            try Self.setChosen(chosen, writer)
        }
        return try await index()
    }

    /// Stops keeping `ids` in place, then indexes what's left: the photos no other album kept holds leave the library,
    /// their sidecars kept.
    @discardableResult
    public func stopKeeping(_ ids: [String]) async throws -> Outcome {
        let leaving = Set(ids)
        try await index.write { writer in
            try Self.setChosen(Self.chosen(writer).filter { !leaving.contains($0.id) }, writer)
        }
        return try await index()
    }

    static func chosen(_ reader: some IndexQueries) throws -> [ApplePhotosCollection] {
        guard let text = try reader.setting(albumsKey) else { return [] }
        return (try? JSONDecoder().decode([ApplePhotosCollection].self, from: Data(text.utf8))) ?? []
    }

    private static func setChosen(_ chosen: [ApplePhotosCollection], _ writer: LibraryIndex.Writer) throws {
        try writer.setSetting(
            chosen.isEmpty ? nil : String(decoding: JSONEncoder().encode(chosen), as: UTF8.self),
            for: albumsKey,
        )
    }

    // MARK: - Indexing

    /// Indexes the albums kept in place: rows added for their new photos, written again for those whose picture,
    /// fields, albums or sidecars changed, and taken out for those no album kept holds. One pass runs at a time, each
    /// after the one asked for before it.
    @discardableResult
    public func index() async throws -> Outcome {
        let task = last.withLock { last -> Task<Outcome, any Error> in
            let previous = last
            let task = Task { [self] in
                _ = await previous?.result
                return try await pass()
            }
            last = task
            return task
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func pass() async throws -> Outcome {
        let started = ContinuousClock.now
        var outcome = Outcome()
        let chosen = try await albums()
        var assets: [ApplePhotosAsset] = []
        if !chosen.isEmpty {
            let tree = try await ApplePhotosTree(photos.collections())
            assets = try await Self.kept(photos.assets(in: tree.albums(in: chosen.map(\.id)).map(\.id)), &outcome)
        }
        let rootPath = LibraryIndexer.path(ApplePhotosPlace.root(in: paths))
        let making = !assets.isEmpty
        let known = try await index.write { writer -> (root: RootRecord, assets: [String: KnownAsset])? in
            if making {
                _ = try writer.applePhotosRoot(at: rootPath)
            }
            guard let root = try writer.applePhotosRoot() else { return nil }
            return try (root, Self.knownAssets(writer))
        }
        guard let known else { return outcome }
        let locator = try await LibrarySidecars(index: index, paths: paths).locator()
        let withSidecars = Self.keysWithSidecars(root: known.root.path, locator: locator)
        for start in stride(from: 0, to: assets.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = assets[start ..< min(start + Self.batchSize, assets.count)]
            try await write(
                batch,
                root: known.root,
                known: known.assets,
                locator: locator,
                sidecars: withSidecars,
                into: &outcome,
            )
            if outcome.firstBatch == nil {
                outcome.firstBatch = ContinuousClock.now - started
            }
        }
        outcome.assets = assets.count
        let kept = Set(assets.map(\.id))
        try await sweep(known.assets.filter { !kept.contains($0.key) }.flatMap(\.value.rows.values), &outcome)
        outcome.elapsed = ContinuousClock.now - started
        return outcome
    }

    /// The assets that give rows: photos, not hidden, a burst's key photo and picked frames.
    private static func kept(_ assets: [ApplePhotosAsset], _ outcome: inout Outcome) -> [ApplePhotosAsset] {
        assets.filter { asset in
            if asset.mediaType != .image {
                outcome.videos += 1
                return false
            }
            if asset.isHidden {
                outcome.hidden += 1
                return false
            }
            if let burst = asset.burst, !burst.isKey, !burst.isUserPick {
                outcome.frames += 1
                return false
            }
            return asset.resource(.photo) != nil
        }
    }

    /// An asset as the index has it: its folder, its rows by name and the signature they were written at.
    struct KnownAsset {
        var key: String
        var folder: String
        var signature: Int64?
        var rows: [String: Int64]
    }

    private static func knownAssets(_ reader: some IndexQueries) throws -> [String: KnownAsset] {
        var known: [String: KnownAsset] = [:]
        try reader.database.cached("""
        SELECT a.local_id, a.asset_key, f.path, f.indexed_signature, p.name, p.id FROM photo_assets a
        JOIN photos p ON p.id = a.photo JOIN folders f ON f.id = p.folder WHERE p.version = ''
        """).forEachRow { row in
            let local = row.string(at: 0) ?? ""
            var asset = known[local] ?? KnownAsset(
                key: row.string(at: 1) ?? "", folder: row.string(at: 2) ?? "", signature: row.optionalInt64(at: 3),
                rows: [:],
            )
            asset.rows[row.string(at: 4) ?? ""] = row.int64(at: 5)
            known[local] = asset
        }
        return known
    }

    /// The asset keys with a folder of sidecars on this Mac: only theirs are looked for.
    private static func keysWithSidecars(root: String, locator: SidecarLocator) -> Set<String> {
        guard let folder = locator.onThisMac(URL(fileURLWithPath: root + "/key/photo"))?
            .deletingLastPathComponent().deletingLastPathComponent(),
            let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return Set(names)
    }

    // MARK: - Rows

    /// One of an asset's rows: its name in the asset's folder, which file it is, and the file as Photos has it.
    private struct Planned {
        let name: String
        let resource: ApplePhotosRow.Resource
        let file: ApplePhotosResource
    }

    private static func planned(_ asset: ApplePhotosAsset) -> [Planned] {
        var rows = ApplePhotosNames.originals(of: asset).map { original in
            Planned(
                name: original.name, resource: original.resource.kind == .alternatePhoto ? .alternate : .original,
                file: original.resource,
            )
        }
        if let edit = ApplePhotosNames.edit(of: asset) {
            rows.append(Planned(name: edit.name, resource: .edit, file: edit.resource))
        }
        return rows
    }

    /// A sidecar as read: what it says, and when it was saved.
    private struct ReadSidecar {
        let summary: SidecarSummary
        let modified: Date?
    }

    /// An asset of a batch whose rows are to be written.
    private struct Changed {
        let asset: ApplePhotosAsset
        let key: String
        let folder: String
        let signature: Int64
        let rows: [Planned]
        let sidecars: [String: ReadSidecar]
        let known: KnownAsset?
    }

    private func write(
        _ batch: ArraySlice<ApplePhotosAsset>, root: RootRecord, known: [String: KnownAsset], locator: SidecarLocator,
        sidecars: Set<String>, into outcome: inout Outcome,
    ) async throws {
        var changed: [Changed] = []
        for asset in batch {
            let existing = known[asset.id]
            // An asset keeps the key its rows have until it's keyed again (LIB-61), so it's never in two folders.
            let key = existing?.key ?? ApplePhotosPlace.key(cloud: asset.cloud, local: asset.id)
            let folder = existing?.folder ?? root.path + "/" + key
            let rows = Self.planned(asset)
            var read: [String: ReadSidecar] = [:]
            if sidecars.contains(key) {
                for row in rows {
                    let photo = URL(fileURLWithPath: folder + "/" + row.name, isDirectory: false)
                    guard let url = locator.onThisMac(photo), let modified = LibraryIndexer.Run.modified(url),
                          let summary = SidecarStore.summary(atSidecar: url) else { continue }
                    read[row.name] = ReadSidecar(summary: summary, modified: modified)
                }
            }
            let signature = Self.signature(of: asset, key: key, rows: rows, sidecars: read)
            if let existing, existing.signature == signature, Set(existing.rows.keys) == Set(rows.map(\.name)) {
                outcome.unchanged += 1
                continue
            }
            changed.append(Changed(
                asset: asset, key: key, folder: folder, signature: signature, rows: rows, sidecars: read,
                known: existing,
            ))
        }
        guard !changed.isEmpty else { return }
        let ids = changed.flatMap { $0.known.map { Array($0.rows.values) } ?? [] }
        let records = try await index.read { reader in
            try Dictionary(ids.compactMap { try reader.photo(id: $0) }.map { ($0.id, $0) }) { first, _ in first }
        }
        var items: [LibraryIndexer.Batcher.Item] = []
        var gone: [Int64] = []
        let now = Date()
        for asset in changed {
            items.append(.folder(LibraryIndexer.FolderListing(
                path: asset.folder, root: root.id, parent: root.path, signature: asset.signature, listedAt: now,
            )))
            for row in asset.rows {
                let id = asset.known?.rows[row.name]
                var photo = LibraryIndexer.PendingPhoto(
                    folder: asset.folder, record: Self.record(row, of: asset, existing: id.flatMap { records[$0] }),
                    keywords: Self.keywords(of: asset.asset, sidecar: asset.sidecars[row.name]),
                    collections: asset.sidecars[row.name]?.summary.metadata.collections ?? [], isNew: id == nil,
                )
                photo.versions = asset.sidecars[row.name]?.summary.versions ?? []
                photo.listed = id.flatMap { records[$0] }
                items.append(.photo(photo))
            }
            let names = Set(asset.rows.map(\.name))
            gone += asset.known?.rows.filter { !names.contains($0.key) }.map(\.value) ?? []
            items.append(.complete(LibraryIndexer.FolderCompletion(
                signature: asset.signature, counts: FolderIndexed(path: asset.folder),
            )))
        }
        let writing = index.photoWrites
        let (writes, assets, leaving) = (items, changed, gone)
        let written = try await index.write { writer in
            let applied = try LibraryIndexer.Batcher.apply(writes, writer, writing: writing)
            var rows: [(row: ApplePhotosRow, albums: [String])] = []
            for asset in assets {
                guard let folder = try writer.folder(path: asset.folder)?.id else { continue }
                for row in asset.rows {
                    guard let photo = try writer.photo(folder: folder, name: row.name) else { continue }
                    rows.append((ApplePhotosRow(
                        photo: photo.id, local: asset.asset.id, cloud: asset.asset.cloud, key: asset.key,
                        resource: row.resource, contentVersion: Self.contentVersion(of: row, in: asset.asset),
                        pixelWidth: row.file.pixelWidth, pixelHeight: row.file.pixelHeight,
                        subtypes: asset.asset.subtypes, isFavorite: asset.asset.isFavorite,
                        isHidden: asset.asset.isHidden,
                    ), asset.asset.albums))
                }
            }
            try writer.setApplePhotosRows(rows)
            return try (applied, writer.removeApplePhotos(leaving))
        }
        outcome.inserted += written.0.inserted
        outcome.updated += written.0.updated
        outcome.removed += written.1
        live?.receive(.photosInserted(written.0.inserted))
        live?.receive(.photosUpdated(written.0.updated))
        live?.receive(.photosRemoved(written.1))
    }

    /// Takes out `ids`, rows of assets no album kept holds, a batch at a time.
    private func sweep(_ ids: [Int64], _ outcome: inout Outcome) async throws {
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            let part = Array(ids[start ..< min(start + Self.batchSize, ids.count)])
            let removed = try await index.write { try $0.removeApplePhotos(part) }
            outcome.removed += removed
            live?.receive(.photosRemoved(removed))
        }
    }

    /// The row's content version: Photos' edit's changes with each edit, an original's never.
    private static func contentVersion(of row: Planned, in asset: ApplePhotosAsset) -> Date {
        row.resource == .edit ? asset.contentVersion : asset.created ?? Date(timeIntervalSince1970: 0)
    }

    private static func record(_ row: Planned, of changed: Changed, existing: PhotoRecord?) -> PhotoRecord {
        let asset = changed.asset
        let kind = PhotoRecord.Kind(pathExtension: (row.name as NSString).pathExtension)
        var record = existing ?? PhotoRecord(folder: 0, name: row.name, kind: kind)
        record.name = row.name
        record.kind = kind
        record.modified = contentVersion(of: row, in: asset)
        if record.contentKey == nil {
            record.size = row.file.size ?? 0
        }
        record.captured = asset.created
        record.capturedOffset = nil
        record.cameraCaptured = nil
        record.cameraOffset = nil
        record.width = row.file.pixelWidth ?? record.width
        record.height = row.file.pixelHeight ?? record.height
        record.latitude = asset.location?.latitude
        record.longitude = asset.location?.longitude
        record.state = []
        record.missingSince = nil
        record.indexed = 1
        let sidecar = changed.sidecars[row.name]
        LibraryIndexer.Run.show(organising(asset, sidecar: sidecar?.summary), in: &record)
        if let sidecar {
            LibraryIndexer.Run.place(sidecar.summary.metadata, in: &record)
        } else {
            record.marked = false
            record.stack = nil
            record.customLabelColor = nil
        }
        if record.stack == nil {
            record.stack = stack(of: row, in: changed)
        }
        record.edited = sidecar?.summary.hasEdits ?? false
        record.sidecarModified = sidecar?.modified
        return record
    }

    /// The stack Photos makes of the row where Redlamp's sidecar makes none: Photos' edit over its original, the
    /// original on top once it has a Redlamp edit; a burst's key photo over the frames picked.
    private static func stack(of row: Planned, in changed: Changed) -> PhotoStack? {
        let asset = changed.asset
        if asset.edit != nil, row.resource != .alternate {
            let original = asset.resource(.photo).flatMap { photo in
                ApplePhotosNames.originals(of: asset).first { $0.resource == photo }?.name
            }
            let originalEdited = original.flatMap { changed.sidecars[$0]?.summary.hasEdits } ?? false
            return PhotoStack(
                id: ApplePhotosPlace.stackID(changed.key),
                top: row.resource == .edit ? !originalEdited : originalEdited,
            )
        }
        if let burst = asset.burst, row.resource == .original {
            return PhotoStack(id: ApplePhotosPlace.stackID("burst:" + burst.id), top: burst.isKey)
        }
        return nil
    }

    /// Photos' fields beside Redlamp's: a favourite as a pick (decision 8), and from macOS 27 a rating, a caption and
    /// keywords, each standing where the photo's sidecar has nothing of its own for it.
    private static func organising(_ asset: ApplePhotosAsset, sidecar: SidecarSummary?) -> LibraryIndexer.Run
        .Organising {
        var given = XMPFields()
        var present: Set<XMPField> = []
        if asset.isFavorite {
            given.flag = .pick
            present.insert(.flag)
        }
        if let rating = asset.rating, rating > 0 {
            given.rating = rating
            present.insert(.rating)
        }
        if let caption = XMPFields.text(asset.caption) {
            given.caption = caption
            present.insert(.caption)
        }
        guard let sidecar else { return LibraryIndexer.Run.Organising(fields: given, others: present) }
        let redlamp = XMPFields(sidecar.metadata)
        var shown = redlamp
        var others: Set<XMPField> = []
        for field in present where !redlamp.holds(field) {
            shown.take(field, from: given)
            others.insert(field)
        }
        return LibraryIndexer.Run.Organising(fields: shown, others: others)
    }

    /// The row's keywords: its sidecar's where it holds them, and otherwise Photos' from macOS 27.
    private static func keywords(of asset: ApplePhotosAsset, sidecar: ReadSidecar?) -> [String] {
        if let held = sidecar?.summary.metadata.keywords {
            return KeywordPath.texts(held)
        }
        return asset.keywords ?? []
    }

    /// A hash of everything an asset's rows are made from, FNV-1a over its text, the same in every launch: its fields,
    /// albums and files as Photos gives them, its key, and when each of its sidecars was saved.
    private static func signature(
        of asset: ApplePhotosAsset, key: String, rows: [Planned], sidecars: [String: ReadSidecar],
    ) -> Int64 {
        var text = "\(key)|\(asset.contentVersion.timeIntervalSince1970)|\(asset.created?.timeIntervalSince1970 ?? -1)"
        text += "|\(asset.location.map { "\($0.latitude),\($0.longitude)" } ?? "")|\(asset.isFavorite)"
        text += "|\(asset.rating ?? -1)|\(asset.caption ?? "")|\((asset.keywords ?? []).joined(separator: ","))"
        text += "|\(asset.albums.sorted().joined(separator: ","))|\(asset.burst.map { "\($0.isKey)\($0.isUserPick)" } ?? "")"
        text += "|\(ApplePhotosRow.bits(asset.subtypes))"
        for row in rows {
            text += "|\(row.name):\(row.resource.rawValue):\(row.file.size ?? -1):\(row.file.pixelWidth ?? -1)x"
                + "\(row.file.pixelHeight ?? -1):\(sidecars[row.name]?.modified?.timeIntervalSince1970 ?? -1)"
        }
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return Int64(bitPattern: hash)
    }
}
