import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// Favourites followed from Photos (LIB-65), scripted on the simulated library: a favourite is a pick when its photo is
/// added, the row's own, so the grid shows it; the pick follows Photos' favourite as it changes; and a flag set or
/// cleared in Redlamp through the library's culling stays as it is through Photos' changes, until the favourite comes
/// to agree with it, its Undo giving the pick back to the favourite. Nothing is written to Photos.
struct ApplePhotosFavoritesTests {
    /// The rows of the Apple Photos root, by name.
    private static func rows(_ sandbox: IndexSandbox) async throws -> [String: PhotoRecord] {
        try await sandbox.index.read { reader in
            let ids = try reader.database.prepare("""
            SELECT p.id FROM photos p JOIN folders f ON f.id = p.folder JOIN roots r ON r.id = f.root WHERE r.kind = 1
            """).map { $0.int64(at: 0) }
            return try Dictionary(ids.compactMap { try reader.photo(id: $0) }.map { ($0.name, $0) }) { first, _ in
                first
            }
        }
    }

    /// The flags of the rows `names` names, in that order.
    private static func flags(_ names: [String], _ sandbox: IndexSandbox) async throws -> [PhotoFlag?] {
        let rows = try await rows(sandbox)
        return names.map { rows[$0]?.flag }
    }

    @Test func `a favourite is a pick when its photo is added, the row's own, and the pick follows Photos' favourite`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        let tram = try #require(try await Self.rows(sandbox)["IMG_0001.HEIC"])
        #expect(tram.flag == .pick && tram.sidecarModified == nil)
        #expect(!tram.otherFields.contains(.flag), "the pick is the row's own, so the grid shows it")
        let edited = ["IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg"]
        #expect(try await Self.flags(edited, sandbox) == [nil, nil])

        library.update(SamplePhotos.tram) { $0.isFavorite = false }
        library.update(SamplePhotos.edited) { $0.isFavorite = true }
        let changed = try await indexer.update()
        #expect(!changed.whole && changed.assets == 2)
        #expect(try await Self.flags(["IMG_0001.HEIC"] + edited, sandbox) == [nil, .pick, .pick])
        let favorites = try await sandbox.index.read { try $0.applePhotosRows() }.filter(\.isFavorite).map(\.local)
        #expect(Set(favorites) == [SamplePhotos.edited], "the favourite as last read")
    }

    @Test func `a pick cleared or set in Redlamp stays through Photos' changes, until the favourite comes to agree with it`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        let names = ["IMG_0001.HEIC", "IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg"]
        let rows = try await Self.rows(sandbox)
        let tram = try #require(rows["IMG_0001.HEIC"]?.id)
        let edited = try #require(rows["IMG_0002.JPG"]?.id)
        let metadata = LibraryMetadata(index: sandbox.index)
        try await metadata.apply(.set([.flag(nil)], on: [tram]))
        try await metadata.apply(.set([.flag(.pick)], on: [edited]))
        #expect(try await Self.flags(names, sandbox) == [nil, .pick, nil])

        // Photos changes something else of both, so their rows are written again.
        let taken = Date(timeIntervalSince1970: 1_600_000_000)
        library.update(SamplePhotos.tram) { $0.created = taken }
        library.update(SamplePhotos.edited) { $0.created = taken }
        let changed = try await indexer.update()
        #expect(changed.updated.contains(tram) && changed.updated.contains(edited))
        #expect(try await Self.rows(sandbox)["IMG_0001.HEIC"]?.captured == taken)
        #expect(try await Self.flags(names, sandbox) == [nil, .pick, nil])

        // Again with the albums compared whole, Photos' history since the token gone.
        let porto = ApplePhotosAsset.Location(latitude: 41.1496, longitude: -8.611)
        library.update(SamplePhotos.tram) { $0.location = porto }
        library.update(SamplePhotos.edited) { $0.location = porto }
        library.expireHistory()
        let whole = try await indexer.update()
        #expect(whole.whole && whole.updated.contains(tram) && whole.updated.contains(edited))
        #expect(try await Self.flags(names, sandbox) == [nil, .pick, nil])

        // The favourites move to agree with Redlamp's flags, then away again: the pick set in Redlamp, which its
        // sidecar holds, stays; the one cleared follows the favourite once the two agreed, as Photos' edit's row does.
        library.update(SamplePhotos.tram) { $0.isFavorite = false }
        library.update(SamplePhotos.edited) { $0.isFavorite = true }
        _ = try await indexer.update()
        #expect(try await Self.flags(names, sandbox) == [nil, .pick, .pick])
        library.update(SamplePhotos.tram) { $0.isFavorite = true }
        library.update(SamplePhotos.edited) { $0.isFavorite = false }
        _ = try await indexer.update()
        #expect(try await Self.flags(names, sandbox) == [.pick, .pick, nil])
    }

    @Test func `a reject set in Redlamp stands over the favourite, and its Undo gives the pick back to Photos' favourite`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-selects"])
        let pair = ["IMG_0004.JPG", "IMG_0004.NEF"]
        #expect(try await Self.flags(pair, sandbox) == [.pick, .pick], "a RAW+JPEG pair's two rows")
        let jpeg = try #require(try await Self.rows(sandbox)["IMG_0004.JPG"]?.id)
        let metadata = LibraryMetadata(index: sandbox.index)
        try await metadata.apply(.set([.flag(.reject)], on: [jpeg]))
        library.update(SamplePhotos.pair) { $0.created = Date(timeIntervalSince1970: 1_600_000_000) }
        _ = try await indexer.update()
        #expect(try await Self.flags(pair, sandbox) == [.reject, .pick])

        try await metadata.undo()
        #expect(try await Self.flags(pair, sandbox) == [.pick, .pick], "Undo shows the favourite's pick again")
        library.update(SamplePhotos.pair) { $0.isFavorite = false }
        _ = try await indexer.update()
        #expect(try await Self.flags(pair, sandbox) == [nil, nil], "the pick follows the favourite again")
    }
}
