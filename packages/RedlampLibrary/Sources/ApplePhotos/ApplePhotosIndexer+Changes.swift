import Foundation
import RedlampDocument

/// Following Photos' changes (LIB-61): Photos' persistent change history, read from the token the last pass kept, at
/// launch and a moment after each change Photos tells of while Redlamp runs.
public extension ApplePhotosIndexer {
    /// Brings the albums kept in place up to date with what changed in Photos since the last pass, from the change
    /// token it kept: only the assets and albums Photos says changed are read, and with nothing changed no album is
    /// fetched. The albums are compared whole instead (`index()`) when there's no token, when Photos no longer has its
    /// history since the token, when the collections kept no longer hold the albums they did (an album deleted, one
    /// added to or taken out of a folder kept, or another System Photo Library), when a quit cut a re-key short, and
    /// once after the format rows are written in changes (`rowFormat`). One pass runs at a time.
    @discardableResult
    func update() async throws -> Outcome {
        try await enqueue { [self] in try await changesPass() }
    }

    /// Brings the rows of the assets `ids` names up to date, as a change in Photos to them would: once Copy to Folder's
    /// copies stand in for them, and once Undo Import has taken those copies back (LIB-63). Nothing is read while no
    /// album is kept in place.
    @discardableResult
    func refresh(_ ids: Set<String>) async throws -> Outcome {
        try await enqueue { [self] in
            var outcome = Outcome()
            outcome.whole = false
            let albums = try await index.read { try Self.following($0)?.albums }
            if let albums, !ids.isEmpty {
                try await apply(ids, albums: albums, &outcome)
            }
            return outcome
        }
    }

    /// Follows Photos while Redlamp runs: `update()` at once, for what changed since the last pass, then again
    /// `settling` after each change Photos tells of, until the task is cancelled. It reads nothing while no album is
    /// kept in place or Redlamp may not read Photos: albums kept later start it again. `failed` hears of a pass that
    /// couldn't run; the next change tries again.
    func follow(
        settling: Duration = .milliseconds(250), failed: @escaping @Sendable (any Error) -> Void = { _ in },
    ) async {
        guard photos.access() == .authorized, await (try? albums())?.isEmpty == false else { return }
        let notices = photos.changes()
        await updating(failed)
        for await _ in notices {
            try? await Task.sleep(for: settling)
            guard !Task.isCancelled else { return }
            await updating(failed)
        }
    }
}

extension ApplePhotosIndexer {
    private func updating(_ failed: @Sendable (any Error) -> Void) async {
        do {
            _ = try await update()
        } catch {
            if !(error is CancellationError) {
                failed(error)
            }
        }
    }

    private func changesPass() async throws -> Outcome {
        let started = ContinuousClock.now
        let (chosen, following) = try await index.read { try (Self.chosen($0), Self.following($0)) }
        guard !chosen.isEmpty, let following, let token = following.token, following.format == Self.rowFormat,
              !FileManager.default.fileExists(atPath: rekeyJournal.path)
        else { return try await pass() }
        let changes: ApplePhotosChanges
        do {
            changes = try await photos.changes(since: token)
        } catch ApplePhotosError.expiredToken {
            return try await pass()
        }
        var outcome = Outcome()
        outcome.whole = false
        var touched = changes.inserted.union(changes.updated).union(changes.deleted)
        if !changes.collections.isEmpty {
            let tree = try await ApplePhotosTree(photos.collections())
            guard Set(tree.albums(in: chosen.map(\.id)).map(\.id)) == Set(following.albums) else {
                return try await pass()
            }
            try await retitle(chosen, in: tree)
            let changed = changes.collections.intersection(following.albums)
            if !changed.isEmpty {
                try await touched.formUnion(joinedOrLeft(Array(changed)))
            }
        }
        if !touched.isEmpty {
            try await apply(touched, albums: following.albums, &outcome)
        }
        if changes.token != token {
            let next = Following(token: changes.token, albums: following.albums, format: Self.rowFormat)
            try await index.write { try Self.setFollowing(next, $0) }
        }
        outcome.elapsed = ContinuousClock.now - started
        return outcome
    }

    /// The collections kept with their titles and folders as Photos has them now, for the lists that name them.
    private func retitle(_ chosen: [ApplePhotosCollection], in tree: ApplePhotosTree) async throws {
        let now = chosen.map { kept in
            tree[kept.id].map { found in
                var renamed = kept
                renamed.title = found.title
                renamed.parent = found.parent
                return renamed
            } ?? kept
        }
        guard now != chosen else { return }
        try await index.write { try Self.setChosen(now, $0) }
    }

    /// The photos that joined or left the albums `changed` names since the index listed them.
    private func joinedOrLeft(_ changed: [String]) async throws -> Set<String> {
        let held = try await photos.listedIDs(in: changed)
        let listed = try await index.read { try Self.listed(in: changed, $0) }
        var touched = Set<String>()
        for album in changed {
            touched.formUnion((held[album] ?? []).symmetricDifference(listed[album] ?? []))
        }
        return touched
    }

    /// The photos the index lists in each of the albums `ids` names, by local identifier: not those marked missing.
    private static func listed(in ids: [String], _ reader: some IndexQueries) throws -> [String: Set<String>] {
        let statement = try reader.database.cached("""
        SELECT a.local_id FROM photo_albums al JOIN photo_assets a ON a.photo = al.photo
        JOIN photos p ON p.id = al.photo WHERE al.album = ? AND p.state & \(PhotoRecord.State.missing.rawValue) = 0
        """)
        var listed: [String: Set<String>] = [:]
        for id in ids {
            try statement.bind(id, at: 1)
            listed[id] = try Set(statement.map { $0.string(at: 0) ?? "" })
        }
        return listed
    }

    /// Brings the rows of the assets `touched` names up to date with Photos in the albums kept, `albums`: those the
    /// library lists written, those that left every album kept taken out, and those Photos no longer has kept as
    /// missing.
    private func apply(_ touched: Set<String>, albums: [String], _ outcome: inout Outcome) async throws {
        let fetched = try await photos.assets(withIDs: Array(touched), in: albums)
        let found = Set(fetched.map(\.id))
        let assets = Self.kept(fetched.filter { !$0.albums.isEmpty }, &outcome)
        let rootPath = LibraryIndexer.path(ApplePhotosPlace.root(in: paths))
        let making = !assets.isEmpty
        let known = try await index.write { writer -> (root: RootRecord, assets: [String: KnownAsset])? in
            if making {
                _ = try writer.applePhotosRoot(at: rootPath)
            }
            guard let root = try writer.applePhotosRoot() else { return nil }
            return try (root, Self.knownAssets(writer, ids: touched))
        }
        guard var known else { return }
        let locator = try await LibrarySidecars(index: index, paths: paths).locator()
        try await finishRekeying(root: known.root, locator: locator, known: &known.assets)
        try await rekey(assets, root: known.root, locator: locator, known: &known.assets, &outcome)
        let keys = Set(assets.map { known.assets[$0.id]?.key ?? ApplePhotosPlace.key(cloud: $0.cloud, local: $0.id) })
        let withSidecars = Self.keysWithSidecars(root: known.root.path, locator: locator, keys: keys)
        for start in stride(from: 0, to: assets.count, by: Self.batchSize) {
            try Task.checkCancellation()
            try await write(
                assets[start ..< min(start + Self.batchSize, assets.count)], root: known.root, known: known.assets,
                locator: locator, sidecars: withSidecars, into: &outcome,
            )
        }
        outcome.assets = assets.count
        let kept = Set(assets.map(\.id))
        var swept: [Int64] = []
        var gone: [KnownAsset] = []
        for (local, asset) in Self.left(known.assets.filter { !kept.contains($0.key) }, outcome) {
            if found.contains(local) {
                swept += asset.rows.values
            } else if !asset.isMissing {
                gone.append(asset)
            }
        }
        try await sweep(swept, &outcome)
        try await markMissing(gone, &outcome)
    }
}
