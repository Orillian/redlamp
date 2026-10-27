import Foundation
import RedlampDocument

/// An asset keyed again (LIB-61): its key came from its local identifier, as it had no cloud identifier when its rows
/// were made (iCloud Photos off, or not synced yet), and now it has one. Its folder of sidecars on this Mac and its
/// folder in Redlamp's cache move to the new key, then the index's folder and rows, which keep their IDs. Re-keys are
/// journaled in the library's folder before the first file moves until the index has them, as Move Edits journals its
/// moves (LIB-11), so the next pass after a quit finishes them.
struct ApplePhotosRekey: Codable, Hashable {
    var local: String
    var cloud: String
    var from: String
    var to: String
}

extension ApplePhotosIndexer {
    /// The re-keys under way.
    var rekeyJournal: URL {
        paths.root.appending(path: "Apple Photos Keys.json")
    }

    /// Keys again the assets of `assets` that gained a cloud identifier since their rows were made, `known` following.
    /// An asset whose new key another asset's folder has keeps its key, with its cloud identifier recorded.
    func rekey(
        _ assets: [ApplePhotosAsset], root: RootRecord, locator: SidecarLocator, known: inout [String: KnownAsset],
        _ outcome: inout Outcome,
    ) async throws {
        var moves: [ApplePhotosRekey] = []
        for asset in assets {
            guard let cloud = asset.cloud, let existing = known[asset.id], existing.cloud != cloud else { continue }
            let key = ApplePhotosPlace.key(cloud: cloud, local: asset.id)
            if key != existing.key {
                moves.append(ApplePhotosRekey(local: asset.id, cloud: cloud, from: existing.key, to: key))
            }
        }
        guard !moves.isEmpty else { return }
        try JSONEncoder().encode(moves).write(to: rekeyJournal, options: .atomic)
        outcome.rekeyed += try await finish(moves, root: root, locator: locator, known: &known)
    }

    /// Finishes the re-keys a quit cut short, before a pass writes any row.
    func finishRekeying(root: RootRecord, locator: SidecarLocator, known: inout [String: KnownAsset]) async throws {
        guard let data = try? Data(contentsOf: rekeyJournal),
              let moves = try? JSONDecoder().decode([ApplePhotosRekey].self, from: data)
        else { return }
        _ = try await finish(moves, root: root, locator: locator, known: &known)
    }

    /// Moves each asset's files, then its rows, to its new key, and lets the journal go; returns how many moved.
    private func finish(
        _ moves: [ApplePhotosRekey], root: RootRecord, locator: SidecarLocator, known: inout [String: KnownAsset],
    ) async throws -> Int {
        for move in moves {
            if let from = Self.sidecarFolder(of: move.from, root: root.path, locator: locator),
               let to = Self.sidecarFolder(of: move.to, root: root.path, locator: locator) {
                try Self.moveSidecars(from: from, to: to)
            }
            Self.moveCache(
                from: URL(fileURLWithPath: root.path + "/" + move.from, isDirectory: true),
                to: URL(fileURLWithPath: root.path + "/" + move.to, isDirectory: true),
            )
        }
        let keyed = try await index.write { writer -> [String: ApplePhotosRekey] in
            var keyed: [String: ApplePhotosRekey] = [:]
            for move in moves {
                let (from, to) = (root.path + "/" + move.from, root.path + "/" + move.to)
                guard let folder = try writer.folder(path: from) else { continue }
                guard try writer.folder(path: to) == nil else {
                    try writer.setApplePhotosKey(move.from, cloud: move.cloud, ofAsset: move.local)
                    continue
                }
                try writer.moveFolder(folder.id, to: to, parent: folder.parent)
                try writer.setApplePhotosKey(move.to, cloud: move.cloud, ofAsset: move.local)
                keyed[move.local] = move
            }
            return keyed
        }
        for move in moves {
            known[move.local]?.cloud = move.cloud
            guard keyed[move.local] != nil else { continue }
            known[move.local]?.key = move.to
            known[move.local]?.folder = root.path + "/" + move.to
        }
        try? FileManager.default.removeItem(at: rekeyJournal)
        return keyed.count
    }

    /// Moves the sidecars in `from` to `to`, each under file coordination as Move Edits moves them, then takes out
    /// `from` once nothing is left in it. A sidecar in both with different contents stays in `from`.
    private static func moveSidecars(from: URL, to: URL) throws {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: from.path) else { return }
        let sidecars = names.filter { !$0.hasPrefix(".") }
        if !sidecars.isEmpty {
            try manager.createDirectory(at: to, withIntermediateDirectories: true)
        }
        for name in sidecars {
            _ = try SidecarMover.coordinatedMove(from.appending(path: name), to: to.appending(path: name))
        }
        if (try? manager.contentsOfDirectory(atPath: from.path))?.allSatisfy({ $0.hasPrefix(".") }) == true {
            try? manager.removeItem(at: from)
        }
    }

    /// Moves the asset's folder in Redlamp's cache, where its originals land, to `to`: what can't move is let go, as
    /// anything in the cache may be.
    private static func moveCache(from: URL, to: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: from.path) else { return }
        if (try? manager.moveItem(at: from, to: to)) == nil {
            try? manager.removeItem(at: from)
        }
    }
}
