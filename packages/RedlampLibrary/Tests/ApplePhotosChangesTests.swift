import Foundation
import RedlampDocument
import RedlampEngineAPI
import Synchronization
import Testing
@testable import RedlampLibrary

/// Following Photos' changes to the albums kept in place (LIB-61), scripted on the simulated library: what changed
/// since the token read alone, each kind of change reaching the rows, photos Photos no longer has kept as missing,
/// assets keyed again, and the albums compared whole when the token or the albums no longer serve.
struct ApplePhotosChangesTests {
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

    private static func folder(_ record: PhotoRecord, _ sandbox: IndexSandbox) async throws -> String {
        try await sandbox.index.read { try #require(try $0.folder(id: record.folder)).path }
    }

    private static func rootPath(_ sandbox: IndexSandbox) -> String {
        LibraryIndexer.path(ApplePhotosPlace.root(in: LibraryPaths(root: sandbox.directory)))
    }

    private static func save(
        _ sidecar: Sidecar,
        for record: PhotoRecord,
        in sandbox: IndexSandbox,
    ) async throws -> URL {
        let photo = try await URL(fileURLWithPath: folder(record, sandbox) + "/" + record.name)
        let locator = try await LibrarySidecars(index: sandbox.index).locator()
        try SidecarStore(locator: locator).save(sidecar, for: photo)
        return locator.url(for: photo)
    }

    private static var edited: EditRecipe {
        var recipe = EditRecipe()
        recipe[.exposure] = 0.5
        return recipe
    }

    private static func photo(_ number: Int, cloud: String? = nil, albums: [String]) -> ApplePhotosAsset {
        ApplePhotosAsset(
            id: String(format: "8A1F%04d-0000-4000-8000-%012d/L0/001", number, number), cloud: cloud,
            created: Date(timeIntervalSince1970: 1_750_000_000 + Double(number)), albums: albums,
            resources: [ApplePhotosResource(kind: .photo, type: "public.heic", originalFilename: "IMG_\(number).HEIC")],
        )
    }

    @Test func `with Photos unchanged an update reads only its history since the token, and fetches no album`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try CountingPhotos(SamplePhotos.library())
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep(["album-lisbon", "album-selects"])
        let read = photos.albumsRead
        let outcome = try await indexer.update()
        #expect(!outcome.whole && outcome.assets == 0 && outcome.unchanged == 0)
        #expect(outcome.inserted.isEmpty && outcome.updated.isEmpty && outcome.removed.isEmpty && outcome.missing
            .isEmpty)
        #expect(photos.albumsRead == read, "no album was fetched")
        let following = try await sandbox.index.read { try ApplePhotosIndexer.following($0) }
        #expect(following?.token == photos.changeToken())
        #expect(Set(following?.albums ?? []) == ["album-lisbon", "album-selects"])
    }

    @Test func `a photo added to an album kept is listed at the next update, and one added to another album isn't`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let photos = CountingPhotos(library)
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep(["album-selects"])
        library.insert(Self.photo(50, cloud: "cloud-0050", albums: ["album-selects"]))
        library.insert(Self.photo(51, albums: ["album-porto"]))
        let read = photos.albumsRead
        let outcome = try await indexer.update()
        #expect(!outcome.whole && outcome.inserted.count == 1 && outcome.assets == 1)
        #expect(photos.albumsRead == read + 1, "only the album that changed is read, for its photos' identifiers")
        let rows = try await Self.rows(sandbox)
        #expect(rows["IMG_50.HEIC"] != nil && rows["IMG_51.HEIC"] == nil)
        let counts = try await sandbox.index.read { try $0.applePhotosAlbumCounts() }
        #expect(counts == ["album-selects": 3])
    }

    @Test func `a photo put in an album kept joins its list, and one taken out of every album kept leaves it`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-selects"])
        let pair = try #require(try await Self.rows(sandbox)["IMG_0004.JPG"])
        let sidecar = try await Self.save(
            Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2)),
            for: pair,
            in: sandbox,
        )
        library.setAlbums(
            of: SamplePhotos.tram,
            to: ["album-lisbon", "album-porto", "smart-favourites", "album-selects"],
        )
        library.setAlbums(of: SamplePhotos.pair, to: ["album-porto", "smart-favourites"])
        let outcome = try await indexer.update()
        #expect(!outcome.whole && outcome.inserted.count == 1 && outcome.removed.count == 2 && outcome.missing.isEmpty)
        #expect(try await Set(Self.rows(sandbox).keys) == ["IMG_0001.HEIC"])
        #expect(FileManager.default.fileExists(atPath: sidecar.path), "the sidecar stays for when an album holds it")
    }

    @Test func `a changed favourite, date or place reaches the rows, and a new edit in Photos the edit's images`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        let before = try await Self.rows(sandbox)
        let taken = Date(timeIntervalSince1970: 1_600_000_000)
        library.update(SamplePhotos.tram) { tram in
            tram.isFavorite = false
            tram.created = taken
            tram.location = ApplePhotosAsset.Location(latitude: 41.1496, longitude: -8.611)
        }
        let again = Date(timeIntervalSince1970: 1_800_000_000)
        library.update(SamplePhotos.edited) { edited in
            edited.adjusted = again
            edited.modified = again
        }
        let outcome = try await indexer.update()
        let after = try await Self.rows(sandbox)
        let tram = try #require(after["IMG_0001.HEIC"])
        #expect(tram.flag == nil && tram.captured == taken && tram.latitude == 41.1496 && tram.longitude == -8.611)
        let edit = try #require(after["IMG_0002 (Photos edit).jpeg"])
        #expect(edit.modified == again && edit.modified != before["IMG_0002 (Photos edit).jpeg"]?.modified)
        #expect(
            after["IMG_0002.JPG"]?.modified == before["IMG_0002.JPG"]?.modified,
            "the original's picture is as it was",
        )
        #expect(outcome.updated.contains(tram.id) && outcome.updated.contains(edit.id))
        #expect(outcome.unchanged == 0 && outcome.assets == 2)
    }

    @Test func `an edit in Photos after Redlamp's adds Photos' edit, and its revert keeps it as missing when Redlamp edited it`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        let tram = try #require(try await Self.rows(sandbox)["IMG_0001.HEIC"])
        _ = try await Self.save(Sidecar(recipe: Self.edited), for: tram, in: sandbox)
        library.update(SamplePhotos.tram) { tram in
            tram.hasAdjustments = true
            tram.adjusted = Date(timeIntervalSince1970: 1_800_000_000)
            tram.resources.append(ApplePhotosResource(
                kind: .fullSizePhoto, type: "public.jpeg", originalFilename: "FullSizeRender.jpeg",
            ))
        }
        let edited = try await indexer.update()
        var rows = try await Self.rows(sandbox)
        let edit = try #require(rows["IMG_0001 (Photos edit).jpeg"])
        #expect(edited.inserted == [edit.id])
        #expect(rows["IMG_0001.HEIC"]?.edited == true && rows["IMG_0001.HEIC"]?.stack?.top == true)
        #expect(edit.stack?.id == rows["IMG_0001.HEIC"]?.stack?.id && edit.stack?.top == false)

        let kept = try await Self.save(Sidecar(recipe: Self.edited), for: edit, in: sandbox)
        _ = try await indexer.index()
        library.update(SamplePhotos.tram) { tram in
            tram.hasAdjustments = false
            tram.adjusted = Date(timeIntervalSince1970: 1_800_000_600)
            tram.resources.removeAll { $0.kind == .fullSizePhoto }
        }
        let reverted = try await indexer.update()
        rows = try await Self.rows(sandbox)
        #expect(reverted.missing == [edit.id] && reverted.removed.isEmpty)
        #expect(rows["IMG_0001 (Photos edit).jpeg"]?.state.contains(.missing) == true)
        #expect(rows["IMG_0001.HEIC"]?.state.contains(.missing) == false)
        #expect(FileManager.default.fileExists(atPath: kept.path))
        let compared = try await indexer.index()
        #expect(compared.missing.isEmpty && compared.removed.isEmpty, "a row kept as missing stays as it is")
        #expect(try await Self.rows(sandbox)["IMG_0001 (Photos edit).jpeg"]?.state.contains(.missing) == true)
    }

    @Test func `a photo deleted in Photos is kept as missing with its sidecar, and Library Health offers Remove alone`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-selects", "album-lisbon"])
        let jpeg = try #require(try await Self.rows(sandbox)["IMG_0004.JPG"])
        let sidecar = try await Self.save(
            Sidecar(recipe: Self.edited, metadata: PhotoMetadata(rating: 4)),
            for: jpeg,
            in: sandbox,
        )
        _ = try await indexer.index()
        library.delete([SamplePhotos.pair])
        let outcome = try await indexer.update()
        let rows = try await Self.rows(sandbox)
        let raw = try #require(rows["IMG_0004.NEF"])
        #expect(!outcome.whole && Set(outcome.missing) == [jpeg.id, raw.id] && outcome.removed.isEmpty)
        #expect(rows["IMG_0004.JPG"]?.state.contains(.missing) == true && rows["IMG_0004.JPG"]?.rating == 4)
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        let counts = try await sandbox.index.read { try $0.applePhotosAlbumCounts() }
        #expect(counts["album-selects"] == nil)

        let engine = QueryEngine(index: sandbox.index)
        try await engine.load()
        #expect(try await !Set(engine.list(.allPhotographs)).contains(jpeg.id))
        let operations = FileOperations(index: sandbox.index, paths: LibraryPaths(root: sandbox.directory))
        let health = LibraryHealth(operations: operations, engine: engine)
        let found = try await health.findings(.missing)
        #expect(Set(found.photos) == [jpeg.id, raw.id])
        #expect(found.findings.allSatisfy {
            if case .notInPhotos = $0.reason {
                true
            } else {
                false
            }
        })
        #expect(found.findings.first?.reason.description.hasPrefix("no longer in Apple Photos since ") == true)
        let located = try await health.locate(jpeg.id, at: sandbox.directory.appending(path: "IMG_0004.JPG"))
        #expect(located.problem == .inApplePhotos)
        _ = try await health.run(health.planRemoval([jpeg.id, raw.id], in: found))
        #expect(try await Self.rows(sandbox).isEmpty == false)
        #expect(try await Self.rows(sandbox)["IMG_0004.JPG"] == nil)
    }

    @Test func `a photo Photos gives back returns with what Redlamp kept of it`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-selects"])
        let jpeg = try #require(try await Self.rows(sandbox)["IMG_0004.JPG"])
        _ = try await Self.save(
            Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 4)),
            for: jpeg,
            in: sandbox,
        )
        let pair = try #require(try await library.assets(withIDs: [SamplePhotos.pair], in: ["album-selects"]).first)
        library.delete([SamplePhotos.pair])
        #expect(try await indexer.update().missing.count == 2)
        library.insert(pair)
        let back = try await indexer.update()
        let rows = try await Self.rows(sandbox)
        #expect(back.missing.isEmpty && back.inserted.isEmpty && back.updated.count == 2)
        #expect(rows["IMG_0004.JPG"]?.id == jpeg.id && rows["IMG_0004.JPG"]?.state.contains(.missing) == false)
        #expect(rows["IMG_0004.JPG"]?.rating == 4)
    }

    @Test func `an asset that gains a cloud identifier is keyed again: its sidecars, folder and rows move, keeping their IDs`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        let live = try #require(try await Self.rows(sandbox)["IMG_0003.HEIC"])
        let old = ApplePhotosPlace.key(cloud: nil, local: SamplePhotos.live)
        #expect(try await Self.folder(live, sandbox) == Self.rootPath(sandbox) + "/" + old)
        let sidecar = try await Self.save(
            Sidecar(recipe: Self.edited, metadata: PhotoMetadata(rating: 3)),
            for: live,
            in: sandbox,
        )
        let original = URL(fileURLWithPath: Self.rootPath(sandbox) + "/" + old + "/IMG_0003.HEIC")
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("an original downloaded from iCloud".utf8).write(to: original)
        _ = try await indexer.update()
        library.update(SamplePhotos.live) { $0.cloud = "cloud-0003" }
        let outcome = try await indexer.update()
        let key = ApplePhotosPlace.key(cloud: "cloud-0003", local: SamplePhotos.live)
        let moved = try #require(try await Self.rows(sandbox)["IMG_0003.HEIC"])
        #expect(outcome.rekeyed == 1 && moved.id == live.id && moved.rating == 3 && moved.edited)
        #expect(try await Self.folder(moved, sandbox) == Self.rootPath(sandbox) + "/" + key)
        let assets = try await sandbox.index.read { try $0.applePhotosRows() }.filter { $0.photo == live.id }
        #expect(assets.map(\.key) == [key] && assets.map(\.cloud) == ["cloud-0003"])
        let locator = try await LibrarySidecars(index: sandbox.index).locator()
        let there = locator.url(for: URL(fileURLWithPath: Self.rootPath(sandbox) + "/" + key + "/IMG_0003.HEIC"))
        #expect(FileManager.default.fileExists(atPath: there.path) && !FileManager.default
            .fileExists(atPath: sidecar.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: Self.rootPath(sandbox) + "/" + key + "/IMG_0003.HEIC"))
        #expect(!FileManager.default.fileExists(atPath: indexer.rekeyJournal.path))
        #expect(try await indexer.update().rekeyed == 0)
    }

    @Test func `a re-key a quit cut short is finished by the next pass`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        let live = try #require(try await Self.rows(sandbox)["IMG_0003.HEIC"])
        let sidecar = try await Self.save(
            Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 3)),
            for: live,
            in: sandbox,
        )
        let (old, key) = (
            ApplePhotosPlace.key(cloud: nil, local: SamplePhotos.live),
            ApplePhotosPlace.key(cloud: "cloud-0003", local: SamplePhotos.live),
        )
        let move = ApplePhotosRekey(local: SamplePhotos.live, cloud: "cloud-0003", from: old, to: key)
        try JSONEncoder().encode([move]).write(to: indexer.rekeyJournal)
        let folder = sidecar.deletingLastPathComponent()
        try FileManager.default.moveItem(at: folder, to: folder.deletingLastPathComponent().appending(path: key))
        library.update(SamplePhotos.live) { $0.cloud = "cloud-0003" }
        let outcome = try await indexer.update()
        let moved = try #require(try await Self.rows(sandbox)["IMG_0003.HEIC"])
        #expect(outcome.whole && moved.id == live.id && moved.rating == 3)
        #expect(try await Self.folder(moved, sandbox) == Self.rootPath(sandbox) + "/" + key)
        #expect(!FileManager.default.fileExists(atPath: indexer.rekeyJournal.path))
    }

    @Test func `an expired token compares the albums kept whole`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        library.expireHistory()
        let outcome = try await indexer.update()
        #expect(outcome.whole && outcome.unchanged == outcome.assets && outcome.assets == 5)
        #expect(try await !indexer.update().whole, "the token the comparison kept serves again")
    }

    @Test func `rows written in an earlier format are compared whole once`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let indexer = try ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index)
        try await indexer.keep(["album-lisbon"])
        try await sandbox.index.write { writer in
            var earlier = try #require(try ApplePhotosIndexer.following(writer))
            earlier.format = nil
            try ApplePhotosIndexer.setFollowing(earlier, writer)
        }
        #expect(try await indexer.update().whole)
        #expect(try await !indexer.update().whole)
    }

    @Test func `an album deleted in Photos is compared whole: its photos still in Photos leave, their sidecars kept`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-porto", "album-selects"])
        library.removeCollection("album-porto")
        let outcome = try await indexer.update()
        #expect(outcome.whole && outcome.missing.isEmpty && outcome.removed.count == 2)
        #expect(try await Set(Self.rows(sandbox).keys) == ["IMG_0004.JPG", "IMG_0004.NEF"])
    }

    @Test func `another System Photo Library keeps the photos as missing, found again by their keys when kept again`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        try await ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index).keep(["album-selects"])
        let jpeg = try #require(try await Self.rows(sandbox)["IMG_0004.JPG"])
        _ = try await Self.save(
            Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 5)),
            for: jpeg,
            in: sandbox,
        )
        var pair = try #require(try await SamplePhotos.library().assets(withIDs: [SamplePhotos.pair]).first)
        pair.id = "9B2E0004-0000-4000-8000-000000000004/L0/001"
        pair.albums = ["album-picks"]
        let other = SimulatedPhotosLibrary(
            collections: [ApplePhotosCollection(id: "album-picks", title: "Picks", kind: .album)], assets: [pair],
        )
        let indexer = ApplePhotosIndexer(photos: other, index: sandbox.index)
        let switched = try await indexer.update()
        #expect(switched.whole && switched.missing.count == 2 && switched.removed.isEmpty)
        let kept = try await indexer.keep(["album-picks"])
        let rows = try await Self.rows(sandbox)
        #expect(kept.missing.isEmpty && kept.removed.isEmpty && rows.count == 2)
        #expect(rows["IMG_0004.JPG"]?.id == jpeg.id && rows["IMG_0004.JPG"]?.state.contains(.missing) == false)
        #expect(rows["IMG_0004.JPG"]?.rating == 5)
        let assets = try await sandbox.index.read { try $0.applePhotosRows() }
        #expect(Set(assets.map(\.local)) == [pair.id])
    }

    @Test func `following Photos lists a change a moment after Photos tells of it`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        try await indexer.keep(["album-selects"])
        let following = Task { await indexer.follow(settling: .milliseconds(50)) }
        defer { following.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        library.insert(Self.photo(52, cloud: "cloud-0052", albums: ["album-selects"]))
        let started = ContinuousClock.now
        while try await Self.rows(sandbox)["IMG_52.HEIC"] == nil, ContinuousClock.now - started < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try await Self.rows(sandbox)["IMG_52.HEIC"] != nil)
    }

    /// LIB-61's budgets on the simulated library at 50,000 assets: a launch with Photos unchanged applies its changes
    /// in under 200 ms, fetching no album; a change in Photos is in the lists within 2 s of its notice. Skipped unless
    /// `REDLAMP_APPLE_PHOTOS_BENCH=1` (`TEST_RUNNER_REDLAMP_APPLE_PHOTOS_BENCH=1`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_APPLE_PHOTOS_BENCH"] == "1"))
    func `with 50,000 assets, Photos' changes are followed within LIB-61's budget`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = ApplePhotosFixture.generated(50000)
        let photos = CountingPhotos(library)
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index)
        try await indexer.keep(ApplePhotosFixture.albums.map(\.id))
        let read = photos.albumsRead
        let unchanged = try await indexer.update()
        #expect(!unchanged.whole && photos.albumsRead == read && unchanged.elapsed < .milliseconds(200))

        let rows = try await sandbox.index.read { try $0.applePhotosRows() }
        let first = try #require(rows.first)
        let following = Task {
            await indexer.follow(settling: .milliseconds(250))
        }
        defer { following.cancel() }
        try await Task.sleep(for: .milliseconds(300))
        let told = ContinuousClock.now
        library.insert(Self.photo(60, cloud: "cloud-0060", albums: ["album-3"]))
        library.update(first.local) { $0.isFavorite.toggle() }
        try library.delete([#require(rows.last).local])
        try library.setAlbums(of: #require(rows.dropFirst(5).first).local, to: ["album-1", "album-2"])
        func arrived() async throws -> Bool {
            let inserted = try await Self.rows(sandbox)["IMG_60.HEIC"] != nil
            let missing = try await sandbox.index.read { try $0.photoCount(withState: .missing) }
            return inserted && missing > 0
        }
        while try await !arrived(), ContinuousClock.now - told < .seconds(10) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let listed = ContinuousClock.now - told
        print(
            "LIB-61 bench: 50,000 assets; an update with Photos unchanged in \(unchanged.elapsed); a change listed"
                + " \(listed) after its notice, settling 250 ms included",
        )
        #expect(listed < .seconds(2))
    }
}

/// A Photos library that counts the albums it's asked for whole, or for their photos' identifiers.
final class CountingPhotos: ApplePhotosLibrary {
    let base: any ApplePhotosLibrary
    private let reads = Mutex(0)

    init(_ base: any ApplePhotosLibrary) {
        self.base = base
    }

    var albumsRead: Int {
        reads.withLock(\.self)
    }

    var fields: Set<ApplePhotosField> {
        base.fields
    }

    func access() -> ApplePhotosAccess {
        base.access()
    }

    func requestAccess() async -> ApplePhotosAccess {
        await base.requestAccess()
    }

    func collections() async throws -> [ApplePhotosCollection] {
        try await base.collections()
    }

    func assets(in ids: [String]) async throws -> [ApplePhotosAsset] {
        reads.withLock { $0 += ids.count }
        return try await base.assets(in: ids)
    }

    func listedIDs(in ids: [String]) async throws -> [String: Set<String>] {
        reads.withLock { $0 += ids.count }
        return try await base.listedIDs(in: ids)
    }

    func write(
        _ resource: ApplePhotosResource, of asset: String, to url: URL, progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        try await base.write(resource, of: asset, to: url, progress: progress)
    }

    func changes() -> AsyncStream<Void> {
        base.changes()
    }

    func assets(withIDs ids: [String]) async throws -> [ApplePhotosAsset] {
        try await base.assets(withIDs: ids)
    }

    func assets(withIDs ids: [String], in albums: [String]) async throws -> [ApplePhotosAsset] {
        try await base.assets(withIDs: ids, in: albums)
    }

    func changeToken() -> Data? {
        base.changeToken()
    }

    func changes(since token: Data) async throws -> ApplePhotosChanges {
        try await base.changes(since: token)
    }
}
