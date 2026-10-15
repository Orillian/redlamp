import Foundation
import RedlampDocument
import Synchronization

/// Folders taken out of the library (LIB-05, LIB-10), as Lightroom Classic's Remove takes a folder out of its
/// catalog: a root Folders no longer has leaves every list, count and search, then the index, with its folders
/// and photos, their keywords, collection memberships and text. Nothing on disk changes, and indexing the
/// folder again brings everything back from its photos and their sidecars: ratings, keywords, collections. A
/// root that can't be found isn't taken out: its photos stay, offline.
///
/// `remove` marks the root removed in one small transaction (`LibraryIndex.Writer.markRemoved`), keeping the
/// folders of the roots still followed, and the column store drops its photos at once; their keywords and
/// collection memberships go next, so the counts made from them follow; the rows go last, a batch at a time in
/// the indexer's turn (`LibraryIndexer.sweepRemovedRoots`). Every read of the store leaves out what's marked,
/// so a quit partway shows none of the root, and `resume` sweeps the rest at the next launch.
public final class LibraryRoots: Sendable {
    public let index: LibraryIndex
    public let indexer: LibraryIndexer
    public let live: LibraryLive
    private let state = Mutex(State())

    private struct State {
        /// The sweeps asked of the indexer, each in its turn, that haven't been followed yet.
        var runs: [AsyncStream<LibraryIndexerEvent>] = []
        /// Follows them, one after another, while there are any.
        var sweeping: Task<Void, Never>?
        var stopped = false
    }

    public init(index: LibraryIndex, indexer: LibraryIndexer, live: LibraryLive) {
        self.index = index
        self.indexer = indexer
        self.live = live
    }

    /// Takes the root at `root` out of the library, keeping the folders of `kept`, the roots still followed, and
    /// returns once the open lists leave its photos out and so do the counts of keywords and collections; its rows
    /// go behind (`swept`). Nil when the index has nothing of it to take out, or the photos stay in a root of
    /// `kept` that holds it.
    @discardableResult
    public func remove(_ root: URL, keeping kept: [URL]) async throws -> RootRemoval? {
        let (path, others) = (LibraryIndexer.path(root), kept.map(LibraryIndexer.path))
        guard let removal = try await index.write({ try $0.markRemoved(path, keeping: others) }) else { return nil }
        if removal.photos.isEmpty {
            try await live.engine.updateNames()
        } else {
            await live.remove(removal.photos)
            try await index.write { try $0.unlinkPhotos(removal.photos) }
        }
        sweep()
        return removal
    }

    /// Takes out the roots the index has that none of `followed` is, holds or is inside, but those at or inside a
    /// folder of `kept`: roots Folders lost while the library was off, or before a folder removed from Folders left
    /// the library. Returns what it took out.
    @discardableResult
    public func removeUnfollowed(_ followed: [URL], keeping kept: [URL]) async throws -> [RootRemoval] {
        let (others, spared) = (followed.map(LibraryIndexer.path), kept.map(LibraryIndexer.path))
        let roots = try await index.read { reader -> [String] in
            let removed = try reader.removedRoots()
            return try reader.roots().filter { removed[$0.id] == nil }.map(\.path)
        }
        let below = LibraryIndex.Writer.isBelow
        var removals: [RootRemoval] = []
        for root in roots where !others.contains(where: { $0 == root || below($0, root) || below(root, $0) })
            && !spared.contains(where: { $0 == root || below(root, $0) }) {
            if let removal = try await remove(URL(fileURLWithPath: root, isDirectory: true), keeping: followed) {
                removals.append(removal)
            }
        }
        return removals
    }

    /// Makes a security-scoped bookmark for each root the index has without one (ARC-17): roots added before
    /// bookmarks were kept, and those just indexed. The unsandboxed app makes one for any folder it can read, so the
    /// App Sandbox reaches the root later without asking; a sandboxed one only while the root's access is started,
    /// and a root that can't be found now gets one once it can. Returns how many were made. Reads the file system.
    @discardableResult
    public func bookmark() async throws -> Int {
        let lacking = try await index.read { reader in
            let removed = try reader.removedRoots()
            return try reader.roots().filter { $0.bookmark == nil && removed[$0.id] == nil }
        }
        let made = lacking.compactMap { root in
            FolderAccess.bookmark(for: URL(fileURLWithPath: root.path, isDirectory: true)).map { (root.id, $0) }
        }
        guard !made.isEmpty else { return 0 }
        try await index.write { writer in
            for (id, bookmark) in made {
                try writer.setBookmark(bookmark, ofRoot: id)
            }
        }
        return made.count
    }

    /// Sweeps what a removal a quit cut short left, after the indexer's runs asked for before: at launch.
    public func resume() async {
        if await (try? index.read { try !$0.removedRoots().isEmpty }) == true {
            sweep()
        }
    }

    /// Returns once the sweeps asked for so far are over.
    public func swept() async {
        await state.withLock { $0.sweeping }?.value
    }

    /// Stops sweeping after the batch under way, as the app quits: the marks stay, and the next `resume` sweeps
    /// the rest.
    public func stop() {
        let sweeping = state.withLock { state in
            state.stopped = true
            state.runs = []
            return state.sweeping
        }
        sweeping?.cancel()
    }

    /// Asks the indexer for a sweep in its turn, now, and follows it: the store reads the photos of each batch
    /// again, which keeps it reflecting the index's generation, and finds them gone.
    private func sweep() {
        state.withLock { state in
            guard !state.stopped else { return }
            state.runs.append(indexer.sweepRemovedRoots())
            guard state.sweeping == nil else { return }
            let engine = live.engine
            state.sweeping = Task.detached(priority: .utility) { [self] in
                while let events = nextRun() {
                    for await event in events {
                        if case let .photosRemoved(ids) = event {
                            try? await engine.update(photos: ids)
                        }
                    }
                }
            }
        }
    }

    /// The next sweep to follow; nil, ending the task following them, when there's none.
    private func nextRun() -> AsyncStream<LibraryIndexerEvent>? {
        state.withLock { state in
            guard !state.runs.isEmpty, !Task.isCancelled else {
                state.sweeping = nil
                return nil
            }
            return state.runs.removeFirst()
        }
    }
}
