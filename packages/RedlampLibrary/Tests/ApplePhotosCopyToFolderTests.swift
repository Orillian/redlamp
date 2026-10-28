import Foundation
import RedlampDocument
import RedlampEngineAPI
import Synchronization
import Testing
@testable import RedlampLibrary

/// Copy to Folder over photos kept in Apple Photos (LIB-63) on the simulated library, through the card import into a
/// library with an index: each copy carrying its photo's sidecar from this Mac (its edit, versions, history and
/// metadata, its collections included), Redlamp's fields standing over Photos' and no album made a collection or
/// followed; an original only in iCloud downloaded through Redlamp's cache, counted in the progress and let go of once
/// copied; a capture time as the library showed it; Undo Import taking the copies back, leaving what Redlamp keeps of
/// the photos in place as it was; and an album's copy standing in for each of its photos not copied already, which its
/// Undo gives back.
struct ApplePhotosCopyToFolderTests {
    /// A library keeping albums of the sample in place, with its cache of originals and an import that copies with it.
    struct Kept {
        let sandbox: ImportSandbox
        let photos: SimulatedPhotosLibrary
        let indexer: ApplePhotosIndexer
        let cache: ApplePhotosOriginals
        let importing: ApplePhotosImport

        func remove() {
            sandbox.remove()
        }

        /// The rows of the Apple Photos root, by name.
        func rows() async throws -> [String: PhotoRecord] {
            try await sandbox.index.read { reader in
                let ids = try reader.database.prepare("""
                SELECT p.id FROM photos p JOIN folders f ON f.id = p.folder JOIN roots r ON r.id = f.root
                WHERE r.kind = 1 AND p.version = ''
                """).map { $0.int64(at: 0) }
                return try Dictionary(ids.compactMap { try reader.photo(id: $0) }.map { ($0.name, $0) }) { first, _ in
                    first
                }
            }
        }

        /// The row `name`'s address in the Apple Photos root.
        func url(of name: String) async throws -> URL {
            let record = try #require(try await rows()[name], "\(name)")
            let folder = try await sandbox.index.read { try #require(try $0.folder(id: record.folder)).path }
            return URL(fileURLWithPath: folder + "/" + name, isDirectory: false)
        }

        /// Saves `sidecar` as the row `name`'s, on this Mac, then indexes the albums again so the row shows it.
        @discardableResult
        func save(_ sidecar: Sidecar, for name: String) async throws -> URL {
            let photo = try await url(of: name)
            let locator = try await LibrarySidecars(index: sandbox.index, paths: sandbox.paths).locator()
            try SidecarStore(locator: locator).save(sidecar, for: photo)
            try await indexer.index()
            return try #require(locator.onThisMac(photo))
        }

        func settings(_ ids: [String], naming albums: [String]? = nil) throws -> ApplePhotosImport.Settings {
            try .copyToFolder(ids, naming: albums, to: sandbox.settings(folders: "{album}", backup: false))
        }

        func copy(_ name: String) throws -> Sidecar {
            try #require(SidecarStore().load(for: sandbox.destination.appending(path: name)), "\(name)")
        }
    }

    static func kept(_ albums: [String]) async throws -> Kept {
        let sandbox = try await ImportSandbox.make()
        let photos = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: photos, index: sandbox.index, paths: sandbox.paths)
        try await indexer.keep(albums)
        let cache = ApplePhotosOriginals(index: sandbox.index, paths: sandbox.paths, photos: { photos })
        let importing = ApplePhotosImport(
            photos: photos, library: sandbox.library, originals: cache, indexer: indexer,
        )
        return Kept(sandbox: sandbox, photos: photos, indexer: indexer, cache: cache, importing: importing)
    }

    private static var exposure: EditRecipe {
        var recipe = EditRecipe()
        recipe[.exposure] = 0.5
        return recipe
    }

    private static func emptyTrash(of undone: ApplePhotosImport.Undone) {
        for file in undone.rollbacks.flatMap(\.trashed) {
            try? FileManager.default.removeItem(atPath: file.to)
        }
    }

    @Test func `each copy carries its photo's edit, versions, history and metadata, Redlamp's fields over Photos'`(
    ) async throws {
        let kept = try await Self.kept(["album-lisbon"])
        defer { kept.remove() }
        var black = EditRecipe()
        black[.saturation] = -100
        var metadata = PhotoMetadata()
        metadata.rating = 2
        metadata.keywords = ["Trams"]
        metadata.title = "Graça"
        metadata.collections = ["Picks"]
        var sidecar = Sidecar(
            recipe: Self.exposure, metadata: metadata,
            versions: [PhotoVersion(name: "Black and White", recipe: black)],
            session: HistorySession(steps: [
                HistoryStep(action: .open, title: "Opened", recipe: EditRecipe()),
                HistoryStep(action: .adjustment(.exposure), title: "Exposure", recipe: Self.exposure),
            ]),
        )
        sidecar.modified = Date(timeIntervalSince1970: 1_790_000_000)
        let original = try await kept.save(sidecar, for: "IMG_0001.HEIC")
        let shown = try #require(try await kept.rows()["IMG_0001.HEIC"])
        #expect(shown.rating == 2 && shown.flag == .pick && shown.edited, "the row shows the sidecar over Photos")

        let ids = [SamplePhotos.tram, SamplePhotos.edited]
        let outcome = try await kept.importing.run(kept.settings(ids))
        #expect(outcome.state == .finished && outcome.stagingFailures.isEmpty && outcome.imported == 2)
        let photos = Set(ImportSandbox.files(in: kept.sandbox.destination).keys.filter { !$0.contains(".redlamp") })
        #expect(photos == ["Lisbon/IMG_0001.HEIC", "Lisbon/IMG_0002.JPG", "Lisbon/IMG_0002 (Photos edit).jpeg"])

        let tram = try kept.copy("Lisbon/IMG_0001.HEIC")
        #expect(tram.recipe == Self.exposure && tram.versions.map(\.name) == ["Black and White"])
        #expect(tram.versions.first?.recipe == black)
        let history = SidecarStore().loadHistory(for: kept.sandbox.destination.appending(path: "Lisbon/IMG_0001.HEIC"))
        #expect(history.map(\.steps.count) == [2], "the photo's history, carried")
        let copied = try #require(tram.metadata)
        #expect(copied.rating == 2 && copied.flag == .pick, "the rating Redlamp gave, the favourite's pick")
        #expect(copied.keywords == ["Trams"] && copied.title == "Graça")
        #expect(copied.caption == "The tram climbing to Graça.", "Photos' caption, where Redlamp has none")
        #expect(copied.collections == ["Picks"], "Redlamp's collections, and no album made one")
        #expect(copied.applePhotos == ApplePhotosOrigin(id: SamplePhotos.tram, cloud: "cloud-0001"))

        let plain = try #require(try kept.copy("Lisbon/IMG_0002.JPG").metadata)
        #expect(plain.collections.isEmpty && plain.flag == nil && plain.applePhotos?.version == .original)
        #expect(try kept.copy("Lisbon/IMG_0002 (Photos edit).jpeg").metadata?.applePhotos?.version == .edited)

        let record = try kept.importing.record.load()
        #expect(Set(record.assets.keys) == Set(ids) && record.assets.values.allSatisfy { $0.importID == outcome.id })
        #expect(record.followed.isEmpty && record.imports.map(\.settings.photos) == [ids])
        #expect(record.imports.first?.albums.isEmpty == true, "a selection's copy names no album")
        let collections = try await LibraryMetadata(index: kept.sandbox.index, paths: kept.sandbox.paths)
            .collections.list()
        #expect(try collections[#require(CollectionPath("Trips/Lisbon"))] == nil)
        #expect(FileManager.default.fileExists(atPath: original.path), "the photo's own sidecar stays")
        #expect(!FileManager.default.fileExists(atPath: ApplePhotosStager.root(for: kept.sandbox.destination).path))
    }

    @Test func `an original only in iCloud downloads through the cache, counted, and leaves it once copied`(
    ) async throws {
        let kept = try await Self.kept(["album-lisbon"])
        defer { kept.remove() }
        let live = try await kept.url(of: "IMG_0003.HEIC")
        #expect(!kept.cache.isLocal(live))
        let events = kept.cache.events()
        let arrived = Mutex<[URL]>([])
        let listening = Task {
            for await event in events {
                if case let .arrived(url) = event {
                    arrived.withLock { $0.append(url) }
                }
            }
        }
        defer { listening.cancel() }
        let downloading = Mutex(0)
        let outcome = try await kept.importing.run(kept.settings([SamplePhotos.live])) { progress in
            if progress.stage == .staging {
                downloading.withLock { $0 = max($0, progress.downloading) }
            }
        }
        #expect(outcome.state == .finished && outcome.imported == 1)
        #expect(downloading.withLock { $0 } == 1, "the download counted in the staging's progress")
        #expect(arrived.withLock { $0 } == [live], "downloaded by the cache")
        let source = SamplePhotos.folder.appending(path: "files/IMG_0003.HEIC")
        let copy = kept.sandbox.destination.appending(path: "Lisbon/IMG_0003.HEIC")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: source))
        #expect(!FileManager.default.fileExists(atPath: live.path) && !kept.cache.isLocal(live))
        #expect(await kept.cache.usage().files == 0, "nothing shows the photo now its copy stands in")
    }

    @Test func `a copy keeps the capture time the library showed, and an original Redlamp edited stays on top`(
    ) async throws {
        let kept = try await Self.kept(["album-lisbon"])
        defer { kept.remove() }
        var metadata = PhotoMetadata()
        metadata.captureShift = 60
        try await kept.save(Sidecar(recipe: Self.exposure, metadata: metadata), for: "IMG_0002.JPG")
        let outcome = try await kept.importing.run(kept.settings([SamplePhotos.edited]))
        #expect(outcome.state == .finished && outcome.imported == 1)
        let original = try #require(try kept.copy("Lisbon/IMG_0002.JPG").metadata)
        let edit = try #require(try kept.copy("Lisbon/IMG_0002 (Photos edit).jpeg").metadata)
        #expect(original.captureShift == 5460, "Photos' date, and the minute Redlamp moved it")
        #expect(edit.captureShift == 5400, "Photos' date")
        #expect(original.stack?.id != nil && original.stack?.id == edit.stack?.id)
        #expect(original.stack?.top == true && edit.stack?.top == false, "the original, edited in Redlamp, on top")
    }

    @Test func `an album's copy names the album first, and what an album import follows keeps its own settings`(
    ) async throws {
        let kept = try await Self.kept(["album-lisbon"])
        defer { kept.remove() }
        let followed = try ApplePhotosImport.Settings(
            collections: ["shared-family"],
            copying: kept.sandbox.settings(folders: "Followed/{album}", backup: false),
        )
        try await kept.importing.run(followed)
        let outcome = try await kept.importing.run(kept.settings([SamplePhotos.tram], naming: ["album-porto"]))
        #expect(outcome.imported == 1)
        #expect(FileManager.default.fileExists(
            atPath: kept.sandbox.destination.appending(path: "Porto/IMG_0001.HEIC").path,
        ), "{album} is the album named first")
        let record = try kept.importing.record.load()
        #expect(record.imports.last?.albums.map(\.id) == ["album-porto"])
        #expect(record.followed.map(\.id) == ["shared-family"])
        #expect(try kept.importing.lastImport()?.settings == followed)
        let news = try #require(try await kept.importing.followedNews())
        #expect(news.settings.photos == nil && news.settings.copying == followed.copying)
    }

    @Test func `Undo Import takes the copies back and leaves what Redlamp keeps of the photos in place`(
    ) async throws {
        let kept = try await Self.kept(["album-lisbon"])
        defer { kept.remove() }
        let original = try await kept.save(Sidecar(recipe: Self.exposure), for: "IMG_0001.HEIC")
        let before = try Data(contentsOf: original.appending(path: SidecarStore.editFile))
        let outcome = try await kept.importing.run(kept.settings([SamplePhotos.tram]))
        #expect(outcome.imported == 1)
        let undone = try await kept.importing.undo()
        defer { Self.emptyTrash(of: undone) }
        #expect(undone.record.id == outcome.id && undone.rollbacks.map(\.state) == [.rolledBack])
        #expect(ImportSandbox.files(in: kept.sandbox.destination).isEmpty, "the copy and its sidecar")
        #expect(try kept.importing.record.load().assets.isEmpty)
        #expect(try Data(contentsOf: original.appending(path: SidecarStore.editFile)) == before)
        #expect(try await kept.rows()["IMG_0001.HEIC"]?.edited == true)
    }

    @Test func `an album's copy stands in for each of its photos not copied already, and Undo gives each back with its own`(
    ) async throws {
        let kept = try await Self.kept(["album-lisbon"])
        defer { kept.remove() }
        try await kept.save(Sidecar(recipe: Self.exposure, metadata: PhotoMetadata(rating: 4)), for: "IMG_0002.JPG")
        let tram = try await kept.importing.run(kept.settings([SamplePhotos.tram]))
        #expect(tram.imported == 1)
        let album = try await kept.sandbox.index.read { try $0.applePhotosAssets(inAlbum: "album-lisbon") }
        #expect(album.count == 4, "the photo whose copy stands in isn't copied again")
        #expect(Set(album) == [SamplePhotos.edited, SamplePhotos.live, SamplePhotos.burstKey, SamplePhotos.burstPick])

        let outcome = try await kept.importing.run(kept.settings(album, naming: ["album-lisbon"]))
        #expect(outcome.state == .finished && outcome.stagingFailures.isEmpty && outcome.imported == 4)
        #expect(try await kept.rows().isEmpty, "no photo from Photos once their copies stand in")
        #expect(try await ApplePhotosCopiesTests.listed(in: "album-lisbon", kept.sandbox) == [
            "Lisbon/IMG_0001.HEIC", "Lisbon/IMG_0002.JPG", "Lisbon/IMG_0002 (Photos edit).jpeg",
            "Lisbon/IMG_0003.HEIC", "Lisbon/IMG_0010.JPG", "Lisbon/IMG_0012.JPG",
        ])
        let copy = try #require(try await kept.sandbox.rows(below: kept.sandbox.destination)["Lisbon/IMG_0002.JPG"])
        #expect(copy.rating == 4 && copy.edited, "the copy has the photo's edit")

        let undone = try await kept.importing.undo()
        defer { Self.emptyTrash(of: undone) }
        #expect(undone.record.id == outcome.id && undone.rollbacks.map(\.state) == [.rolledBack])
        let back = try await kept.rows()
        #expect(Set(back.keys) == [
            "IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg", "IMG_0003.HEIC", "IMG_0010.JPG", "IMG_0012.JPG",
        ], "the album's photos from Photos back, and the one copied before still its copy")
        #expect(back["IMG_0002.JPG"]?.rating == 4 && back["IMG_0002.JPG"]?.edited == true, "back with its own edit")
        #expect(try await ApplePhotosCopiesTests.listed(in: "album-lisbon", kept.sandbox) == [
            "Lisbon/IMG_0001.HEIC", "IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg", "IMG_0003.HEIC", "IMG_0010.JPG",
            "IMG_0012.JPG",
        ])
        #expect(try Set(kept.importing.record.load().assets.keys) == [SamplePhotos.tram])
    }
}
