import CryptoKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// Albums of Apple Photos kept in place (LIB-58) on the simulated library: their photos as rows of the Apple Photos
/// root, a folder of Redlamp's cache per asset, made from Photos' fields with Redlamp's sidecars on this Mac standing
/// over them; the root in no folder view; photos leaving with their albums, their sidecars kept.
struct ApplePhotosIndexTests {
    /// A row of the Apple Photos root, and its folder's path.
    private struct Found {
        let record: PhotoRecord
        let folder: String
    }

    private static func found(_ sandbox: IndexSandbox) async throws -> [String: Found] {
        try await sandbox.index.read { reader in
            let ids = try reader.database.prepare("""
            SELECT p.id FROM photos p JOIN folders f ON f.id = p.folder JOIN roots r ON r.id = f.root WHERE r.kind = 1
            """).map { $0.int64(at: 0) }
            var found: [String: Found] = [:]
            for id in ids {
                let record = try #require(try reader.photo(id: id))
                found[record.name] = try Found(
                    record: record,
                    folder: #require(try reader.folder(id: record.folder)).path,
                )
            }
            return found
        }
    }

    private static func rootPath(_ sandbox: IndexSandbox) -> String {
        LibraryIndexer.path(ApplePhotosPlace.root(in: LibraryPaths(root: sandbox.directory)))
    }

    private static func sidecar(
        _ metadata: PhotoMetadata,
        for photo: URL,
        in sandbox: IndexSandbox,
    ) async throws -> URL {
        let locator = try await LibrarySidecars(index: sandbox.index).locator()
        try SidecarStore(locator: locator).save(Sidecar(recipe: EditRecipe(), metadata: metadata), for: photo)
        return locator.url(for: photo)
    }

    @Test func `albums kept in place list Photos' photos: a pair together, Photos' edits and bursts stacked, no video or hidden photo`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = try ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index)
        let outcome = try await indexer.keep(["album-lisbon", "album-selects"])
        #expect(outcome.assets == 6 && outcome.inserted.count == 8)
        #expect(outcome.videos == 1 && outcome.hidden == 1 && outcome.frames == 1)
        let found = try await Self.found(sandbox)
        #expect(Set(found.keys) == [
            "IMG_0001.HEIC", "IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg", "IMG_0003.HEIC", "IMG_0010.JPG",
            "IMG_0012.JPG", "IMG_0004.JPG", "IMG_0004.NEF",
        ])
        let tram = try #require(found["IMG_0001.HEIC"])
        #expect(tram.folder == Self.rootPath(sandbox) + "/" + ApplePhotosPlace.key(
            cloud: "cloud-0001",
            local: SamplePhotos.tram,
        ))
        #expect(tram.record.flag == .pick && found["IMG_0003.HEIC"]?.record.flag == nil)
        #expect(found["IMG_0004.JPG"]?.folder == found["IMG_0004.NEF"]?.folder)
        let edit = found["IMG_0002 (Photos edit).jpeg"]?.record.stack, original = found["IMG_0002.JPG"]?.record.stack
        #expect(edit?.id != nil && edit?.id == original?.id && edit?.top == true && original?.top == false)
        let key = found["IMG_0010.JPG"]?.record.stack, pick = found["IMG_0012.JPG"]?.record.stack
        #expect(key?.id != nil && key?.id == pick?.id && key?.top == true && pick?.top == false)
        let (counts, rows) = try await sandbox.index.read { try ($0.applePhotosAlbumCounts(), $0.applePhotosRows()) }
        #expect(counts == ["album-lisbon": 6, "album-selects": 2])
        #expect(rows.count == 8 && rows.filter { $0.resource == .edit }.count == 1)
        #expect(rows.first { $0.photo == tram.record.id }?.cloud == "cloud-0001")
    }

    @Test func `a photo kept in Photos has its sidecar on this Mac from before the first album kept makes the root`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let before = try await LibrarySidecars(index: sandbox.index).locator()
        try await ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index).keep(["album-selects"])
        let after = try await LibrarySidecars(index: sandbox.index).locator()
        let found = try await Self.found(sandbox)
        let kept = try #require(found.first)
        let photo = URL(fileURLWithPath: kept.value.folder + "/" + kept.key, isDirectory: false)
        #expect(after.url(for: photo) != SidecarLocator.besidePhoto(photo), "on this Mac once the root is made")
        #expect(before.url(for: photo) == after.url(for: photo), "and before, where an editor opened then writes it")
    }

    @Test func `the Apple Photos root is in no folder list, folder search or Folders' counts, its photos in every list`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        try await ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index).keep(["album-selects"])
        let (roots, every, names, counts, outside) = try await sandbox.index.read { reader in
            try (
                reader.roots().map(\.kind), reader.allRoots().map(\.kind), Array(reader.queryNames().folders.values),
                reader.photoCountsByFolder(), reader.foldersOutsideFolderRoots(),
            )
        }
        #expect(roots == [.folder] && Set(every) == [.folder, .applePhotos])
        #expect(!names.contains { $0.contains("Apple Photos") })
        #expect(outside.count == 2 && outside.isDisjoint(with: counts.keys))
        let engine = QueryEngine(index: sandbox.index)
        try await engine.load()
        #expect(try await engine.list(.allPhotographs, sort: QuerySort()).ids.count == 2)
        #expect(try await engine.list(.query(LibraryQuery(parsing: "Apple")), sort: QuerySort()).ids.isEmpty)
        #expect(try await engine.list(.query(LibraryQuery(parsing: "folder:System")), sort: QuerySort()).ids.isEmpty)
    }

    @Test func `a pass writes nothing for photos as they were, and a sidecar saved on this Mac stands over Photos' favourite`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = try ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index)
        try await indexer.keep(["album-selects"])
        let again = try await indexer.index()
        #expect(again.unchanged == 1 && again.inserted.isEmpty && again.updated.isEmpty)
        let jpeg = try #require(try await Self.found(sandbox)["IMG_0004.JPG"])
        let photo = URL(fileURLWithPath: jpeg.folder + "/IMG_0004.JPG")
        let sidecar = try await Self.sidecar(PhotoMetadata(rating: 4, flag: .reject), for: photo, in: sandbox)
        #expect(sidecar.path.hasPrefix(sandbox.directory.appending(path: "Sidecars/apple-photos/System").path))
        let after = try await indexer.index()
        #expect(after.updated.contains(jpeg.record.id))
        let row = try #require(try await Self.found(sandbox)["IMG_0004.JPG"]?.record)
        #expect(row.rating == 4 && row.flag == .reject && row.sidecarModified != nil)
        #expect(!FileManager.default.fileExists(atPath: jpeg.folder))
    }

    @Test func `photos that leave every album kept leave the library, their sidecars kept for when an album holds them again`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = try ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index)
        try await indexer.keep(["album-lisbon", "album-porto"])
        let edited = try #require(try await Self.found(sandbox)["IMG_0002.JPG"])
        let sidecar = try await Self.sidecar(
            PhotoMetadata(rating: 5), for: URL(fileURLWithPath: edited.folder + "/IMG_0002.JPG"), in: sandbox,
        )
        let left = try await indexer.stopKeeping(["album-lisbon"])
        #expect(left.removed.count == 5)
        #expect(try await Set(Self.found(sandbox).keys) == [
            "IMG_0001.HEIC",
            "IMG_0004.JPG",
            "IMG_0004.NEF",
            "IMG_0005.DNG",
        ])
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        try await indexer.keep(["album-lisbon"])
        #expect(try await Self.found(sandbox)["IMG_0002.JPG"]?.record.rating == 5)
    }

    @Test func `a folder that holds the Apple Photos root is indexed around it, its asset folders and originals left to it`(
    ) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "redlamp-photos-root-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let paths = LibraryPaths(root: folder.appending(path: "Library", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let index = try await LibraryIndex.open(at: paths.index)
        try await ApplePhotosIndexer(photos: SamplePhotos.library(), index: index).keep(["album-selects"])
        let key = try #require(try await index.read { try $0.applePhotosRows() }.first?.key)
        let asset = ApplePhotosPlace.root(in: paths).appending(path: key, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
        try Data("an original downloaded from iCloud".utf8).write(to: asset.appending(path: "IMG_0004.JPG"))
        for await _ in LibraryIndexer(index: index).index([folder]) {}
        let (roots, photos, applePhotos) = try await index.read { reader in
            try (
                Set(reader.database
                    .prepare("SELECT DISTINCT root FROM folders WHERE path LIKE '%/Apple Photos/System%'")
                    .map { $0.int64(at: 0) }),
                reader.photoCount(), reader.applePhotosRoot()?.id,
            )
        }
        await index.close()
        #expect(roots == Set([applePhotos].compactMap(\.self)) && photos == 2)
    }

    @Test func `an index of version 15 opens as the current one, its roots folders, with the tables for Apple Photos`(
    ) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "redlamp-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Index.sqlite")
        let old = try await LibraryIndex.open(at: url, migrations: Array(LibraryIndex.migrations.prefix(15)))
        try await old.write { writer in
            let volume = try writer.upsertVolume(VolumeRecord(uuid: "TEST-VOLUME"))
            try writer.database.execute("INSERT INTO roots (volume, path) VALUES (\(volume), '/Volumes/Test/Photos')")
        }
        await old.close()
        let index = try await LibraryIndex.open(at: url)
        let (version, kinds, assets, copies) = try await index.read { reader in
            try (
                reader.database.userVersion, reader.roots().map(\.kind),
                reader.database.prepare("SELECT count(*) FROM photo_assets").first { $0.int(at: 0) },
                reader.database.prepare("SELECT count(*) FROM photo_copies").first { $0.int(at: 0) },
            )
        }
        await index.close()
        #expect(version == LibraryIndex.schemaVersion && kinds == [.folder] && assets == 0 && copies == 0)
    }

    @Test func `an asset's key is the start of SHA-256 over its cloud identifier, or over its local one while it has none`() {
        func hex(_ text: String) -> String {
            SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        }
        #expect(ApplePhotosPlace.key(cloud: "cloud-0001", local: "A/L0/001") == hex("cloud-0001"))
        #expect(ApplePhotosPlace.key(cloud: "cloud-0001", local: "B/L0/001") == hex("cloud-0001"))
        #expect(ApplePhotosPlace.key(cloud: nil, local: "A/L0/001") == hex("local:A/L0/001"))
    }

    @Test func `the simulated library looks assets up by identifier, keeps a history of changes that expires, and gives images`(
    ) async throws {
        let library = try SamplePhotos.library()
        let found = try await library.assets(withIDs: [SamplePhotos.tram, "gone/L0/001"])
        #expect(found.map(\.id) == [SamplePhotos.tram] && found.first?.albums == [])
        let token = try #require(library.changeToken())
        library.recordChange(updated: [SamplePhotos.tram])
        let changes = try await library.changes(since: token)
        #expect(changes.updated == [SamplePhotos.tram] && changes.token != token)
        library.recordChange(deleted: [SamplePhotos.live], expiring: true)
        await #expect(throws: ApplePhotosError.expiredToken) { try await library.changes(since: token) }
        guard case let .image(image) = library.image(of: SamplePhotos.edited, version: .current, size: 64) else {
            Issue.record("the edited photo's image")
            return
        }
        #expect(max(image.width, image.height) == 64)
    }

    @Test func `thousands of assets are written a batch at a time, and a second pass leaves them as they were`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = ApplePhotosIndexer(photos: ApplePhotosFixture.generated(2500), index: sandbox.index)
        let outcome = try await indexer.keep(ApplePhotosFixture.albums.map(\.id))
        #expect(outcome.assets == 2500 && outcome.inserted.count == 2500 + 250 + 125)
        let again = try await indexer.index()
        #expect(again.unchanged == 2500 && again.inserted.isEmpty && again.updated.isEmpty && again.removed.isEmpty)
    }

    /// LIB-58's budget on the simulated library at 50,000 assets: the first 1,000 listed in 1 s, all indexed in
    /// 15 s. Skipped unless `REDLAMP_APPLE_PHOTOS_BENCH=1` (`TEST_RUNNER_REDLAMP_APPLE_PHOTOS_BENCH=1`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_APPLE_PHOTOS_BENCH"] == "1"))
    func `50,000 assets index within LIB-58's budget`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = ApplePhotosIndexer(photos: ApplePhotosFixture.generated(50000), index: sandbox.index)
        let outcome = try await indexer.keep(ApplePhotosFixture.albums.map(\.id))
        let again = try await indexer.index()
        print(
            "LIB-58 bench: 50,000 assets, \(outcome.inserted.count) rows; first batch in \(outcome.firstBatch ?? .zero),"
                + " all in \(outcome.elapsed); a pass with nothing changed in \(again.elapsed)",
        )
        #expect(outcome.assets == 50000)
        #expect(try #require(outcome.firstBatch) < .seconds(1))
        #expect(outcome.elapsed < .seconds(15))
    }
}

/// A simulated library of any size, with no files: a tenth of its assets RAW+JPEG pairs, a twentieth edited in Photos,
/// a third without a cloud identifier, a seventh favourites, across ten albums.
enum ApplePhotosFixture {
    static let albums = (0 ..< 10).map { ApplePhotosCollection(id: "album-\($0)", title: "Album \($0)", kind: .album) }

    static func generated(_ count: Int) -> SimulatedPhotosLibrary {
        let assets = (0 ..< count).map { number in
            let stem = String(format: "IMG_%05d", number)
            var resources = [ApplePhotosResource(
                kind: .photo, type: "public.heic", originalFilename: stem + ".HEIC", size: 2_400_000,
                pixelWidth: 4032, pixelHeight: 3024,
            )]
            if number % 10 == 0 {
                resources = [
                    ApplePhotosResource(kind: .photo, type: "public.jpeg", originalFilename: stem + ".JPG"),
                    ApplePhotosResource(
                        kind: .alternatePhoto,
                        type: "com.adobe.raw-image",
                        originalFilename: stem + ".DNG",
                    ),
                ]
            }
            let edited = number % 20 == 1
            if edited {
                resources.append(ApplePhotosResource(
                    kind: .fullSizePhoto, type: "public.jpeg", originalFilename: "FullSizeRender.jpeg",
                ))
            }
            let created = Date(timeIntervalSince1970: 1_700_000_000 + Double(number) * 60)
            return ApplePhotosAsset(
                id: String(format: "%08X-0000-4000-8000-%012X/L0/001", number, number),
                cloud: number % 3 == 0 ? nil : "cloud-\(number)", created: created, isFavorite: number % 7 == 0,
                hasAdjustments: edited, adjusted: edited ? created.addingTimeInterval(3600) : nil,
                albums: ["album-\(number % 10)"], resources: resources,
            )
        }
        return SimulatedPhotosLibrary(collections: albums, assets: assets)
    }
}
