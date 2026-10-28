import Foundation
import RedlampDocument

/// Copies beside albums kept in place (LIB-64, decision 9). A photo LIB-54's import or Copy to Folder copied into the
/// library's folders stands in for its asset once an album holding the asset is kept in place, so one photo has one
/// edit: the album lists the copy's rows (`photo_albums`), and no row is made from Photos, those the asset had taken
/// out
/// as a sweep takes them, their sidecars kept. A copy is found from Apple Photos.json, which names each asset copied by
/// the local identifier it had where it was copied: by the asset's own, or else by its cloud identifier, as Photos
/// gives it now or as Photos reads back the one the copy recorded (0.3.4 recorded `stringValue`'s text); and the copy's
/// sidecar must name the asset as the record does. Which copy stands in for which asset is kept in `photo_copies`, so a
/// copy moved or renamed in Redlamp, keeping its row, stands in still; one taken out of the library or missing gives
/// its
/// asset its rows from Photos back, and one put back or found again stands in again.
extension ApplePhotosIndexer {
    /// A copy Apple Photos.json names, under the local identifier its asset had where it was copied, with the paths of
    /// its photos.
    struct RecordedCopy: Hashable {
        var local: String
        var paths: [String]
    }

    /// What a pass knows of the copies of its assets, by the assets' local identifiers on this Mac: the rows of the
    /// copies the index links that are there and not missing, every asset the index links a copy to at all, and the
    /// copies Apple Photos.json names of the assets with none standing.
    struct Copies {
        var standing: [String: [Int64]] = [:]
        var linked: Set<String> = []
        var recorded: [String: RecordedCopy] = [:]
    }

    /// The copies of `assets`, the index's links read for those `ids` names (for every asset when it's nil), as the
    /// type
    /// says. With `readingBack`, Photos reads back the cloud identifiers of the copies Apple Photos.json names under a
    /// local identifier it doesn't have, recorded on another Mac or before its library changed, for the assets nothing
    /// else names.
    func copies(of assets: [ApplePhotosAsset], among ids: Set<String>?, readingBack: Bool) async throws -> Copies {
        var copies = try await index.read { try Self.linkedCopies(of: ids, $0) }
        let waiting = assets.filter { copies.standing[$0.id] == nil }
        guard !waiting.isEmpty else { return copies }
        let record = (try? ApplePhotosRecordFile(paths: paths).load().assets) ?? [:]
        guard !record.isEmpty else { return copies }
        var byCloud: [String: String] = [:]
        for (local, copy) in record {
            if let cloud = copy.cloud {
                byCloud[cloud] = local
            }
        }
        for asset in waiting {
            if let copy = record[asset.id] {
                copies.recorded[asset.id] = RecordedCopy(local: asset.id, paths: copy.paths)
            } else if let local = asset.cloud.flatMap({ byCloud[$0] }), let copy = record[local] {
                copies.recorded[asset.id] = RecordedCopy(local: local, paths: copy.paths)
            }
        }
        let unnamed = Set(waiting.map(\.id)).subtracting(copies.recorded.keys)
        guard readingBack, !unnamed.isEmpty else { return copies }
        let named = Set(copies.recorded.values.map(\.local)).union(assets.map(\.id))
        let elsewhere = record.filter { !named.contains($0.key) }.compactMapValues(\.cloud)
        guard !elsewhere.isEmpty else { return copies }
        for (recorded, local) in try await photos.localIDs(ofCopies: elsewhere) where unnamed.contains(local) {
            guard copies.recorded[local] == nil, let copy = record[recorded] else { continue }
            copies.recorded[local] = RecordedCopy(local: recorded, paths: copy.paths)
        }
        return copies
    }

    /// The copies the index links to the assets `ids` names, or to every asset for nil: `Copies.standing` and
    /// `.linked`.
    static func linkedCopies(of ids: Set<String>?, _ reader: some IndexQueries) throws -> Copies {
        let select = "SELECT c.local_id, c.photo, p.state FROM photo_copies c LEFT JOIN photos p ON p.id = c.photo"
        var copies = Copies()
        let read = { (row: SQLiteStatement) in
            let local = row.string(at: 0) ?? ""
            copies.linked.insert(local)
            guard let photo = row.optionalInt64(at: 1), let state = row.optionalInt(at: 2),
                  !PhotoRecord.State(rawValue: state).contains(.missing) else { return }
            copies.standing[local, default: []].append(photo)
        }
        guard let ids else {
            try reader.database.cached(select).forEachRow(read)
            return copies
        }
        let statement = try reader.database.cached(select + " WHERE c.local_id = ?")
        for id in ids {
            try statement.bind(id, at: 1)
            try statement.forEachRow(read)
        }
        return copies
    }

    /// The assets of `batch` whose copies stand in for them, with the copies' rows: those the index links, or those
    /// Apple Photos.json names, found by their paths (the files' own rows, there, not missing and no other asset's
    /// copy), each whose sidecar names the asset as the record does.
    func standing(
        _ batch: some Sequence<ApplePhotosAsset>, _ copies: Copies, locator: SidecarLocator,
    ) async throws -> [String: [Int64]] {
        var standing: [String: [Int64]] = [:]
        var checking: [(asset: String, copy: RecordedCopy)] = []
        for asset in batch {
            if let rows = copies.standing[asset.id] {
                standing[asset.id] = rows
            } else if let copy = copies.recorded[asset.id] {
                checking.append((asset.id, copy))
            }
        }
        guard !checking.isEmpty else { return standing }
        let candidates = checking
        let found = try await index.read { reader in
            try candidates.map { entry in try (entry, Self.copyRows(at: entry.copy.paths, of: entry.asset, reader)) }
        }
        let store = SidecarStore(locator: locator)
        var claimed = Set(standing.values.joined())
        for (entry, rows) in found {
            let named = rows.filter { row in
                !claimed.contains(row.id)
                    && store.summary(for: URL(fileURLWithPath: row.path))?.metadata.applePhotos?.id == entry.copy.local
            }
            guard !named.isEmpty else { continue }
            standing[entry.asset] = named.map(\.id)
            claimed.formUnion(named.map(\.id))
        }
        return standing
    }

    /// The files' own rows at `paths`, there and not missing, that no asset but `local`'s has as its copy.
    private static func copyRows(
        at paths: [String], of local: String, _ reader: some IndexQueries,
    ) throws -> [(id: Int64, path: String)] {
        let statement = try reader.database.cached("""
        SELECT p.id FROM photos p JOIN folders f ON f.id = p.folder
        WHERE f.path = ?1 AND p.name = ?2 AND p.version = '' AND p.state & \(PhotoRecord.State.missing.rawValue) = 0
          AND NOT EXISTS (SELECT 1 FROM photo_copies c WHERE c.photo = p.id AND c.local_id != ?3)
        """)
        var rows: [(id: Int64, path: String)] = []
        for path in paths {
            let place = path as NSString
            try statement.bind(place.deletingLastPathComponent, at: 1)
            try statement.bind(place.lastPathComponent, at: 2)
            try statement.bind(local, at: 3)
            if let id = try statement.first({ $0.int64(at: 0) }) {
                rows.append((id, path))
            }
        }
        return rows
    }

    /// Writes what `standing` says of the assets `evaluated` names: each standing asset's copies linked to it and
    /// listed
    /// in its albums kept, `albums`, its rows from Photos (`known`'s) taken out as a sweep takes them, their sidecars
    /// kept; the copies of the others listed in no album.
    func standIn(
        _ standing: [String: [Int64]], albums: [String: [String]], evaluated: Set<String>,
        known: [String: KnownAsset], _ outcome: inout Outcome,
    ) async throws {
        let settled = evaluated.union(standing.keys)
        guard !settled.isEmpty else { return }
        let copies = standing.map { (local: $0.key, photos: $0.value, albums: albums[$0.key] ?? []) }
        let changed = try await index.write { try $0.setApplePhotosCopies(copies, evaluated: settled) }
        outcome.copies += standing.count
        if !changed.isEmpty {
            live?.receive(.photosUpdated(changed))
        }
        try await sweep(standing.keys.flatMap { known[$0].map { Array($0.rows.values) } ?? [] }, &outcome)
    }

    /// The assets whose copies changed since their assets were last brought up to date: a copy taken out of the
    /// library, marked missing or found again.
    static func copiesChanged(_ reader: some IndexQueries) throws -> Set<String> {
        try Set(reader.database.cached("""
        SELECT DISTINCT c.local_id FROM photo_copies c LEFT JOIN photos p ON p.id = c.photo
        WHERE c.live != (p.id IS NOT NULL AND p.state & \(PhotoRecord.State.missing.rawValue) = 0)
        """).map { $0.string(at: 0) ?? "" })
    }

    /// When Apple Photos.json was last written; nil while there's none.
    var recordWritten: Date? {
        try? ApplePhotosRecordFile(paths: paths).url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    /// The assets with rows from Photos that Apple Photos.json names, by their local or cloud identifiers: copied since
    /// their rows were made, by Copy to Folder or an import, so their copies stand in once they're brought up to date.
    func copiesRecorded() async throws -> Set<String> {
        let record = (try? ApplePhotosRecordFile(paths: paths).load().assets) ?? [:]
        guard !record.isEmpty else { return [] }
        let clouds = Set(record.values.compactMap(\.cloud))
        return try await index.read { reader in
            var found = Set<String>()
            try reader.database.cached("SELECT DISTINCT local_id, cloud_id FROM photo_assets").forEachRow { row in
                let local = row.string(at: 0) ?? ""
                if record[local] != nil || row.string(at: 1).map(clouds.contains) == true {
                    found.insert(local)
                }
            }
            return found
        }
    }
}
