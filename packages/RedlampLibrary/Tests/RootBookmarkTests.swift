import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// The library's roots, each kept with a security-scoped bookmark (ARC-17), which reaches it in the App Sandbox.
struct RootBookmarkTests {
    @Test func `roots indexed without a bookmark get one, but not a root taken out or one that's gone`() async throws {
        let (sandbox, indexer) = try await RootRemovalTests.library()
        defer { sandbox.remove() }
        let engine = QueryEngine(index: sandbox.index)
        try await engine.load()
        let roots = LibraryRoots(
            index: sandbox.index, indexer: indexer, live: LibraryLive(engine: engine, configuration: .init()),
        )
        #expect(try await sandbox.index.read { try $0.roots() }.allSatisfy { $0.bookmark == nil })
        let gone = "/Volumes/Gone \(UUID().uuidString)/Photos"
        try await sandbox.index.write { writer in
            let volume = try #require(try writer.roots().first?.volume)
            try writer.upsertRoot(RootRecord(volume: volume, path: gone))
        }
        try await roots.remove(sandbox.url("Home"), keeping: [sandbox.url("Trip")])

        let makes = FolderAccess.bookmark(for: sandbox.url("Trip")) != nil
        #expect(try await roots.bookmark() == (makes ? 1 : 0))
        let kept = try await sandbox.index.read { try $0.roots() }
        #expect((kept.first { $0.path.hasSuffix("/Trip") }?.bookmark != nil) == makes)
        #expect(kept.first { $0.path == gone }?.bookmark == nil)
        #expect(try await roots.bookmark() == 0, "each made once")
        await roots.swept()
    }
}
