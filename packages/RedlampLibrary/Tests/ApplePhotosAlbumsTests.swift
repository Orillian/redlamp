import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// Albums of Apple Photos kept in place as the library lists them (LIB-62), on the simulated library: the part of
/// Photos' tree kept, which each pass records for the Apple Photos section; an album's photos as a source, with their
/// versions and without those Photos no longer has, counted as they're listed; albums leaving the library, a folder
/// kept giving way to what else it holds when one of its albums leaves; and with limited access, the photos chosen for
/// Redlamp as one album.
struct ApplePhotosAlbumsTests {
    /// The IDs of the collections the index has as kept, in Photos' order.
    private static func kept(_ sandbox: IndexSandbox) async throws -> [String] {
        try await sandbox.index.read { try $0.applePhotosKeptTree().collections.map(\.id) }
    }

    /// The names of the photos `source` lists, in order of name.
    private static func names(_ source: PhotoSource, _ sandbox: IndexSandbox) async throws -> [String] {
        let engine = QueryEngine(index: sandbox.index)
        try await engine.load()
        let ids = try await engine.list(source, sort: QuerySort()).ids
        return try await sandbox.index.read { reader in try ids.compactMap { try reader.photo(id: $0)?.name } }.sorted()
    }

    @Test func `each pass records the part of Photos' tree kept: an album under its folder, a folder with its albums`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        #expect(try await Self.kept(sandbox) == ["folder-trips", "album-lisbon"])
        try await indexer.keep(["smart-favourites"])
        #expect(try await Self.kept(sandbox) == ["folder-trips", "album-lisbon", "smart-favourites"])
        try await indexer.stopKeeping(["album-lisbon", "smart-favourites"])
        #expect(try await Self.kept(sandbox).isEmpty)

        try await indexer.keep(["folder-trips"])
        #expect(try await Self.kept(sandbox) == ["folder-trips", "album-lisbon", "album-porto"])
        photos.add(ApplePhotosCollection(id: "album-porto", title: "Porto 2026", kind: .album, parent: "folder-trips"))
        let renamed = try await indexer.update()
        #expect(!renamed.whole)
        let tree = try await sandbox.index.read { try $0.applePhotosKeptTree() }
        #expect(tree["album-porto"]?.title == "Porto 2026" && tree["folder-trips"]?.title == "Trips")
        photos.add(ApplePhotosCollection(id: "album-braga", title: "Braga", kind: .album, parent: "folder-trips"))
        _ = try await indexer.update()
        #expect(try await Self.kept(sandbox) == ["folder-trips", "album-lisbon", "album-porto", "album-braga"])
    }

    @Test func `an index whose last pass recorded no tree lists the albums as chosen, until a pass reads Photos' tree`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try CountingPhotos(SamplePhotos.library())
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        try await sandbox.index.write { writer in
            var following = try #require(try ApplePhotosIndexer.following(writer))
            following.tree = nil
            try ApplePhotosIndexer.setFollowing(following, writer)
        }
        #expect(try await Self.kept(sandbox) == ["album-lisbon"])
        let read = photos.albumsRead
        let caught = try await indexer.update()
        #expect(!caught.whole && photos.albumsRead == read, "no album was fetched")
        #expect(try await Self.kept(sandbox) == ["folder-trips", "album-lisbon"])
    }

    @Test func `an album's photos are Photos' with their versions, not those Photos no longer has, and a folder's its albums'`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep(["folder-trips", "album-selects"])
        let lisbon = [
            "IMG_0001.HEIC", "IMG_0002 (Photos edit).jpeg", "IMG_0002.JPG", "IMG_0003.HEIC", "IMG_0010.JPG",
            "IMG_0012.JPG",
        ]
        let porto = ["IMG_0001.HEIC", "IMG_0004.JPG", "IMG_0004.NEF", "IMG_0005.DNG"]
        #expect(try await Self.names(.applePhotos("album-lisbon"), sandbox) == lisbon)
        #expect(try await Self.names(.applePhotos("album-porto"), sandbox) == porto)
        #expect(try await Self.names(.applePhotos("folder-trips"), sandbox) == Set(lisbon + porto).sorted())
        #expect(try await Self.names(.applePhotos("album-selects"), sandbox) == ["IMG_0004.JPG", "IMG_0004.NEF"])

        try await sandbox.index.write { writer in
            let tram = try #require(try writer.database.prepare(
                "SELECT id FROM photos WHERE name = 'IMG_0001.HEIC' AND version = ''",
            ).map { $0.int64(at: 0) }.first)
            let version = VersionSummary(id: UUID(), name: "Black and White", created: Date(), hasEdits: true)
            try writer.setVersions([version], ofPhoto: tram)
        }
        photos.delete([SamplePhotos.live])
        _ = try await indexer.update()
        let listed = try await Self.names(.applePhotos("album-lisbon"), sandbox)
        #expect(listed == ["IMG_0001.HEIC"] + lisbon.filter { $0 != "IMG_0003.HEIC" })
        let counts = try await sandbox.index.read { try $0.applePhotosAlbumCounts() }
        let trips = try await Self.names(.applePhotos("folder-trips"), sandbox)
        #expect(counts == ["album-lisbon": listed.count, "album-porto": porto.count + 1, "album-selects": 2])
        #expect(trips.count == 9 && trips.filter { $0 == "IMG_0001.HEIC" }.count == 2)
    }

    @Test func `an album leaving a folder kept leaves the folder's other albums kept, and a folder leaving takes what's in it`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = try ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index)
        try await indexer.keep(["folder-trips", "album-selects"])
        let left = try await indexer.stopKeeping(["album-lisbon"])
        #expect(try await indexer.albums().map(\.id) == ["album-selects", "album-porto"])
        #expect(try await Self.kept(sandbox) == ["album-selects", "folder-trips", "album-porto"])
        #expect(left.removed.count == 5)
        #expect(try await Self.names(.allPhotographs, sandbox) == [
            "IMG_0001.HEIC", "IMG_0004.JPG", "IMG_0004.NEF", "IMG_0005.DNG",
        ])

        try await indexer.keep(["album-lisbon"])
        try await indexer.stopKeeping(["folder-trips"])
        #expect(try await indexer.albums().map(\.id) == ["album-selects"])
        #expect(try await Self.kept(sandbox) == ["album-selects"])
    }

    @Test func `with limited access the photos chosen for Redlamp are one album, kept and followed as an album is`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        photos.limit(to: [SamplePhotos.tram, SamplePhotos.pair, SamplePhotos.video])
        let chosen = ApplePhotosCollection.chosenForRedlamp
        let listed = try await photos.collections()
        #expect(listed.map(\.id) == [chosen.id] && listed.first?.title == "Photos Chosen for Redlamp")
        #expect(listed.first?.estimatedCount == 3)
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep([chosen.id])
        #expect(try await Self.kept(sandbox) == [chosen.id])
        #expect(try await Self.names(.applePhotos(chosen.id), sandbox) == [
            "IMG_0001.HEIC", "IMG_0004.JPG", "IMG_0004.NEF",
        ])

        let (passes, passed) = AsyncStream.makeStream(of: ApplePhotosIndexer.Outcome.self)
        let following = Task { await indexer.follow(settling: .zero, passed: { passed.yield($0) }) }
        defer { following.cancel() }
        var heard = passes.makeAsyncIterator()
        _ = await heard.next()
        photos.limit(to: [SamplePhotos.tram, SamplePhotos.dng])
        let changed = try #require(await heard.next())
        #expect(!changed.whole && changed.missing.isEmpty, "other photos chosen, though Photos' history tells nothing")
        #expect(try await Self.names(.applePhotos(chosen.id), sandbox) == ["IMG_0001.HEIC", "IMG_0005.DNG"])
    }

    @Test func `once access is limited, photos of the albums kept before leave the lists, none kept as missing`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        let chosen = ApplePhotosCollection.chosenForRedlamp.id
        let porto = ["IMG_0001.HEIC", "IMG_0004.JPG", "IMG_0004.NEF", "IMG_0005.DNG"]
        try await indexer.keep(["album-porto"])
        #expect(try await Self.names(.applePhotos("album-porto"), sandbox) == porto)

        photos.limit(to: [SamplePhotos.tram])
        let limited = try await indexer.update()
        #expect(limited.whole && limited.missing.isEmpty && limited.removed.count == 4)
        #expect(try await Self.names(.allPhotographs, sandbox).isEmpty)
        try await indexer.keep([chosen])
        #expect(try await Self.kept(sandbox) == [chosen])
        #expect(try await Self.names(.applePhotos(chosen), sandbox) == ["IMG_0001.HEIC"])

        photos.limit(to: nil)
        try await indexer.index()
        #expect(try await Self.names(.applePhotos("album-porto"), sandbox) == porto, "back with full access")
        #expect(try await Self.names(.applePhotos(chosen), sandbox).isEmpty)
    }
}
