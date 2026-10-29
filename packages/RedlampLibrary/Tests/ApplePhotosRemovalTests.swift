import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// Remove from Library on photos kept in Apple Photos (LIB-62), on the simulated library: every row of the photo's
/// asset leaves with what names it in Photos' tables, its sidecar kept and Photos unchanged; no pass brings it back,
/// whatever Photos changes, until Add Albums keeps an album holding it, and Undo puts it back as it was. Library
/// Health's Remove of a photo Photos no longer has takes its rows of Photos' tables too (LIB-58's review), and the
/// `.xmp` sync leaves photos kept in Photos alone.
struct ApplePhotosRemovalTests {
    /// The names of the rows the index has of asset `local`, in order.
    private static func names(of local: String, _ sandbox: IndexSandbox) async throws -> [String] {
        try await sandbox.index.read { reader in
            try reader.applePhotosRowIDs(ofAsset: local).compactMap { try reader.photo(id: $0)?.name }.sorted()
        }
    }

    /// The library's paths, beside its index, as the indexer has them.
    private static func paths(_ sandbox: IndexSandbox) -> LibraryPaths {
        LibraryPaths(root: sandbox.index.url.deletingLastPathComponent())
    }

    private static func rowIDs(of local: String, _ sandbox: IndexSandbox) async throws -> [Int64] {
        try await sandbox.index.read { try $0.applePhotosRowIDs(ofAsset: local) }
    }

    private static func removed(_ sandbox: IndexSandbox) async throws -> Set<String> {
        try await sandbox.index.read { try ApplePhotosIndexer.removed($0) }
    }

    @Test func `Remove from Library takes every row of a photo's asset out with what names it, and no pass brings it back`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index, paths: Self.paths(sandbox))
        try await indexer.keep(["album-lisbon"])
        let edited = try await Self.rowIDs(of: SamplePhotos.edited, sandbox)
        #expect(edited.count == 2)
        let locator = try await LibrarySidecars(index: sandbox.index, paths: Self.paths(sandbox)).locator()
        let original = try #require(try await sandbox.index.read { try $0.photosWithPaths([edited[0]]).first })
        guard let sidecar = locator.onThisMac(URL(fileURLWithPath: original.folder + "/" + original.photo.name)) else {
            Issue.record("a photo kept in Photos has its sidecars on this Mac")
            return
        }
        try FileManager.default.createDirectory(
            at: sidecar.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("kept".utf8).write(to: sidecar)

        let counted = try await sandbox.index.read { try $0.applePhotosAlbumCounts()["album-lisbon"] ?? 0 }
        let operations = FileOperations(index: sandbox.index, paths: Self.paths(sandbox))
        let batch = try await operations.planRemoval(ofApplePhotos: [edited[0]])
        #expect(batch.title == "Remove 1 photo from the library")
        #expect(try await operations.run(batch).isFinished)
        #expect(try await Self.names(of: SamplePhotos.edited, sandbox).isEmpty)
        let left = try await sandbox.index.read { reader in
            try (reader.applePhotosRows().map(\.local), reader.applePhotosPhotoIDs(in: "album-lisbon"))
        }
        #expect(!left.0.contains(SamplePhotos.edited))
        #expect(Set(left.1).isDisjoint(with: edited))
        let counts = try await sandbox.index.read { try $0.applePhotosAlbumCounts() }
        #expect(counts["album-lisbon"] == counted - 2, "--list counts neither row")
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try await Self.removed(sandbox) == [SamplePhotos.edited])

        _ = try await indexer.index()
        photos.update(SamplePhotos.edited) { $0.isFavorite.toggle() }
        let changes = try await indexer.update()
        #expect(!changes.whole)
        #expect(try await Self.names(of: SamplePhotos.edited, sandbox).isEmpty)
        #expect(try await !Self.names(of: SamplePhotos.tram, sandbox).isEmpty)
    }

    @Test func `Add Albums keeping an album holding a photo removed brings it back, and only that photo`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index, paths: Self.paths(sandbox))
        try await indexer.keep(["album-lisbon"])
        let operations = FileOperations(index: sandbox.index, paths: Self.paths(sandbox))
        let tram = try await Self.rowIDs(of: SamplePhotos.tram, sandbox)
        let live = try await Self.rowIDs(of: SamplePhotos.live, sandbox)
        #expect(try await operations.run(operations.planRemoval(ofApplePhotos: tram + live)).isFinished)
        #expect(try await Self.removed(sandbox) == [SamplePhotos.tram, SamplePhotos.live])

        try await indexer.keep(["album-porto"])
        #expect(try await Self.names(of: SamplePhotos.tram, sandbox) == ["IMG_0001.HEIC"])
        #expect(try await Self.names(of: SamplePhotos.live, sandbox).isEmpty)
        #expect(try await Self.removed(sandbox) == [SamplePhotos.live])
        let albums = try await sandbox.index.read { reader in
            try reader.applePhotosRowIDs(ofAsset: SamplePhotos.tram).flatMap(reader.applePhotosAlbums(ofPhoto:))
        }
        #expect(albums == ["album-lisbon", "album-porto"])
    }

    @Test func `Undo of Remove from Library puts the rows back as they were, with what names them, and Photos follows them`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index, paths: Self.paths(sandbox))
        try await indexer.keep(["album-lisbon"])
        let before = try await sandbox.index.read { reader in
            try reader.applePhotosRows().filter { $0.local == SamplePhotos.edited }
        }
        #expect(before.count == 2)
        let operations = FileOperations(index: sandbox.index, paths: Self.paths(sandbox))
        let removal = try await operations.run(operations.planRemoval(ofApplePhotos: [before[1].photo]))
        #expect(try await Self.names(of: SamplePhotos.edited, sandbox).isEmpty)

        #expect(try await operations.run(operations.planUndo(removal.batch)).isFinished)
        let after = try await sandbox.index.read { reader in
            try reader.applePhotosRows().filter { $0.local == SamplePhotos.edited }
        }
        #expect(after == before)
        let albums = try await sandbox.index.read { reader in
            try after.map { try reader.applePhotosAlbums(ofPhoto: $0.photo) }
        }
        #expect(albums == [["album-lisbon"], ["album-lisbon"]])
        #expect(try await Self.removed(sandbox).isEmpty)

        let pass = try await indexer.index()
        #expect(pass.inserted.isEmpty && pass.removed.isEmpty)
        #expect(try await Self.rowIDs(of: SamplePhotos.edited, sandbox) == before.map(\.photo))
    }

    @Test func `Library Health's Remove of a photo Photos no longer has takes its rows of Photos' tables, which Undo puts back`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index, paths: Self.paths(sandbox))
        try await indexer.keep(["album-lisbon"])
        photos.delete([SamplePhotos.live])
        let changes = try await indexer.update()
        let live = try await Self.rowIDs(of: SamplePhotos.live, sandbox)
        #expect(Set(changes.missing) == Set(live) && !live.isEmpty)

        let operations = FileOperations(index: sandbox.index, paths: Self.paths(sandbox))
        let removal = try await operations.run(operations.planRemoval(ofMissing: live))
        #expect(try await Self.rowIDs(of: SamplePhotos.live, sandbox).isEmpty)
        let albums = try await sandbox.index.read { reader in try live.flatMap(reader.applePhotosAlbums(ofPhoto:)) }
        #expect(albums.isEmpty)

        #expect(try await operations.run(operations.planUndo(removal.batch)).isFinished)
        #expect(try await Self.rowIDs(of: SamplePhotos.live, sandbox) == live)
    }

    @Test func `the .xmp sync leaves photos kept in Photos alone, writing nothing beside their originals`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index, paths: Self.paths(sandbox))
        try await indexer.keep(["album-lisbon"])
        let tram = try #require(try await Self.rowIDs(of: SamplePhotos.tram, sandbox).first)
        let report = try await LibraryXMP(index: sandbox.index, paths: Self.paths(sandbox)).sync([tram], writing: true)
        #expect(report.photos.isEmpty)
        let folder = try #require(try await sandbox.index.read { try $0.photosWithPaths([tram]).first?.folder })
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        #expect(!entries.contains { $0.lowercased().hasSuffix(".xmp") })
    }
}
