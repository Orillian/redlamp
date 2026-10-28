import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// Copies beside albums kept in place (LIB-64) on the simulated library: photos LIB-54's import copied into the
/// library's folders stand in for their assets once an album holding them is kept in place, matched by their local
/// identifiers, or by their cloud identifiers as Photos gives them now or reads back what 0.3.4 recorded; a copy made
/// while its album is kept stands in once its assets are brought up to date, and a copy that goes gives its asset
/// its photo from Photos back.
struct ApplePhotosCopiesTests {
    /// album-lisbon's photos, as LIB-54's import copies them with `{album}` folders.
    private static let lisbon: Set = [
        "Lisbon/IMG_0001.HEIC", "Lisbon/IMG_0002.JPG", "Lisbon/IMG_0002 (Photos edit).jpeg", "Lisbon/IMG_0003.HEIC",
        "Lisbon/IMG_0010.JPG", "Lisbon/IMG_0012.JPG",
    ]
    private static let lisbonAssets = [
        SamplePhotos.tram, SamplePhotos.edited, SamplePhotos.live, SamplePhotos.burstKey, SamplePhotos.burstPick,
    ]

    /// Copies `albums` from `library` into the sandbox's folders, as 0.3.4's import from Apple Photos does.
    @discardableResult
    private static func copy(
        _ albums: [String], from library: SimulatedPhotosLibrary, into sandbox: ImportSandbox,
    ) async throws -> ApplePhotosImport {
        let importing = ApplePhotosImport(photos: library, library: sandbox.library)
        let outcome = try await importing.run(ApplePhotosImport.Settings(
            collections: albums, copying: sandbox.settings(folders: "{album}", backup: false),
        ))
        #expect(outcome.state == .finished)
        return importing
    }

    /// The names of the Apple Photos root's rows: the photos made from Photos.
    private static func fromPhotos(_ sandbox: ImportSandbox) async throws -> Set<String> {
        try await sandbox.index.read { reader in
            try Set(reader.database.prepare("""
            SELECT p.name FROM photos p JOIN folders f ON f.id = p.folder JOIN roots r ON r.id = f.root WHERE r.kind = 1
            """).map { $0.string(at: 0) ?? "" })
        }
    }

    /// What album `id` lists, not missing: a copy by its path in the sandbox's folders, a photo from Photos by its
    /// name.
    private static func listed(in id: String, _ sandbox: ImportSandbox) async throws -> Set<String> {
        let folders = LibraryIndexer.path(sandbox.destination) + "/"
        return try await sandbox.index.read { reader in
            let statement = try reader.database.prepare("""
            SELECT f.path, p.name FROM photo_albums al JOIN photos p ON p.id = al.photo
            JOIN folders f ON f.id = p.folder WHERE al.album = ? AND p.state & \(PhotoRecord.State.missing.rawValue) = 0
            """)
            try statement.bind(id, at: 1)
            return try Set(statement.map { row in
                let folder = (row.string(at: 0) ?? "") + "/"
                let name = row.string(at: 1) ?? ""
                return folder.hasPrefix(folders) ? String(folder.dropFirst(folders.count)) + name : name
            })
        }
    }

    /// Records the copies of asset `local` as another Mac's would be: in Apple Photos.json and their sidecars, under
    /// the
    /// local identifier `other` with the cloud identifier `cloud`.
    private static func recorded(_ local: String, as other: String, cloud: String, in sandbox: ImportSandbox) throws {
        let paths = try ApplePhotosRecordFile(paths: sandbox.paths).change { record in
            let removed = record.assets.removeValue(forKey: local)
            var asset = try #require(removed)
            asset.cloud = cloud
            record.assets[other] = asset
            return asset.paths
        }
        for path in paths {
            let photo = URL(fileURLWithPath: path)
            var sidecar = try #require(SidecarStore().load(for: photo))
            let version = sidecar.metadata?.applePhotos?.version ?? .original
            sidecar.metadata?.applePhotos = ApplePhotosOrigin(id: other, cloud: cloud, version: version)
            try SidecarStore().save(sidecar, for: photo)
        }
    }

    @Test func `photos 0.3.4 copied stand in for theirs once their album is kept in place, and none is made from Photos`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        try await Self.copy(["album-lisbon"], from: library, into: sandbox)
        let copies = try await Set(sandbox.rows(below: sandbox.destination).keys)
        #expect(copies == Self.lisbon)

        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index, paths: sandbox.paths)
        let outcome = try await indexer.keep(["album-lisbon", "album-selects"])
        #expect(outcome.assets == 6 && outcome.copies == 5 && outcome.inserted.count == 2)
        #expect(try await Self.fromPhotos(sandbox) == ["IMG_0004.JPG", "IMG_0004.NEF"], "the pair was never copied")
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon)
        #expect(try await Self.listed(in: "album-selects", sandbox) == ["IMG_0004.JPG", "IMG_0004.NEF"])
        let counts = try await sandbox.index.read { try $0.applePhotosAlbumCounts() }
        #expect(counts == ["album-lisbon": 6, "album-selects": 2])
        #expect(try await Set(sandbox.rows(below: sandbox.destination).keys) == copies, "the copies are as they were")

        let again = try await indexer.index()
        #expect(again.copies == 5 && again.inserted.isEmpty && again.updated.isEmpty && again.removed.isEmpty)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon)
    }

    @Test func `a copy recorded on another Mac stands in by its cloud identifier, as Photos gives it or reads back 0.3.4's`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        try await Self.copy(["album-lisbon"], from: library, into: sandbox)
        let tram = "0E0D0001-0000-4000-8000-000000000001/L0/001", edited = "0E0D0002-0000-4000-8000-000000000002/L0/001"
        try Self.recorded(SamplePhotos.tram, as: tram, cloud: "cloud-0001", in: sandbox)
        try Self.recorded(SamplePhotos.edited, as: edited, cloud: "string-0002", in: sandbox)

        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index, paths: sandbox.paths)
        let outcome = try await indexer.keep(["album-lisbon"])
        #expect(outcome.copies == 5 && outcome.inserted.isEmpty)
        #expect(try await Self.fromPhotos(sandbox).isEmpty)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon)

        let later = try await indexer.update()
        #expect(later.assets == 0 && later.inserted.isEmpty, "linked, they're found again without reading back")
    }

    @Test func `a copy made while its album is kept stands in once noticed, and Undo gives back the photo from Photos`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index, paths: sandbox.paths)
        try await indexer.keep(["album-lisbon"])
        let root = LibraryIndexer.path(ApplePhotosPlace.root(in: sandbox.paths))
        let key = ApplePhotosPlace.key(cloud: "cloud-0001", local: SamplePhotos.tram)
        let tram = URL(fileURLWithPath: root + "/" + key + "/IMG_0001.HEIC")
        let locator = try await LibrarySidecars(index: sandbox.index, paths: sandbox.paths).locator()
        try SidecarStore(locator: locator)
            .save(Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 5)), for: tram)

        let importing = try await Self.copy(["album-lisbon"], from: library, into: sandbox)
        let copied = try await indexer.update()
        #expect(copied.copies == 5 && copied.removed.count == 6, "Apple Photos.json changed since the last pass")
        #expect(try await Self.fromPhotos(sandbox).isEmpty)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon)
        #expect(FileManager.default.fileExists(atPath: locator.url(for: tram).path), "its rating is kept on this Mac")

        let undone = try await importing.undo()
        defer {
            for file in undone.rollbacks.flatMap(\.trashed) {
                try? FileManager.default.removeItem(atPath: file.to)
            }
        }
        #expect(undone.rollbacks.map(\.state) == [.rolledBack])
        let back = try await indexer.refresh(Self.lisbonAssets)
        #expect(back.copies == 0 && back.inserted.count == 6)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == [
            "IMG_0001.HEIC", "IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg", "IMG_0003.HEIC", "IMG_0010.JPG",
            "IMG_0012.JPG",
        ])
        let rating = try await sandbox.index.read { reader in
            try reader.folder(path: root + "/" + key).flatMap { try reader.photo(folder: $0.id, name: "IMG_0001.HEIC") }
        }?.rating
        #expect(rating == 5)
        let links = try await sandbox.index.read { reader in
            try reader.database.prepare("SELECT count(*) FROM photo_copies").first { $0.int(at: 0) }
        }
        #expect(links == 0, "the copies taken out are let go once their assets have their photos back")
        #expect(try await !indexer.update().whole)
    }

    @Test func `a copy that goes missing gives its asset its photo from Photos back, and one found or renamed stands in`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        try await Self.copy(["album-lisbon"], from: library, into: sandbox)
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index, paths: sandbox.paths)
        try await indexer.keep(["album-lisbon"])
        let copy = try #require(try await sandbox.rows(below: sandbox.destination)["Lisbon/IMG_0001.HEIC"])

        try await sandbox.index.write { _ = try $0.markMissing([(copy.id, copy.folder)], at: Date()) }
        let missing = try await indexer.update()
        #expect(missing.assets == 1 && missing.copies == 0 && missing.inserted.count == 1)
        #expect(try await Self.fromPhotos(sandbox) == ["IMG_0001.HEIC"])
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon
            .subtracting(["Lisbon/IMG_0001.HEIC"]).union(["IMG_0001.HEIC"]))

        try await sandbox.index.write { _ = try $0.markFound([copy.id]) }
        let found = try await indexer.update()
        #expect(found.copies == 1 && found.removed.count == 1)
        #expect(try await Self.fromPhotos(sandbox).isEmpty)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon)

        try await sandbox.index.write { _ = try $0.movePhotos([(copy.id, copy.folder, "Tram.HEIC")]) }
        let renamed = try await indexer.index()
        #expect(renamed.copies == 5 && renamed.inserted.isEmpty)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon
            .subtracting(["Lisbon/IMG_0001.HEIC"]).union(["Lisbon/Tram.HEIC"]))
    }

    @Test func `a copy follows its asset's albums in Photos, and stays a photo of its folder once Photos deletes it`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let library = try SamplePhotos.library()
        try await Self.copy(["album-lisbon"], from: library, into: sandbox)
        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index, paths: sandbox.paths)
        try await indexer.keep(["album-lisbon", "album-porto"])
        #expect(try await Self.listed(in: "album-porto", sandbox) == [
            "Lisbon/IMG_0001.HEIC", "IMG_0004.JPG", "IMG_0004.NEF", "IMG_0005.DNG",
        ])

        library.setAlbums(of: SamplePhotos.dng, to: [])
        let left = try await indexer.update()
        #expect(left.assets == 0 && left.removed.count == 1, "the album's copy isn't read again for it")

        library.setAlbums(of: SamplePhotos.tram, to: ["album-porto", "smart-favourites"])
        let moved = try await indexer.update()
        #expect(moved.copies == 1 && moved.inserted.isEmpty)
        #expect(try await Self.listed(in: "album-lisbon", sandbox) == Self.lisbon.subtracting(["Lisbon/IMG_0001.HEIC"]))
        #expect(try await Self.listed(in: "album-porto", sandbox) == [
            "Lisbon/IMG_0001.HEIC", "IMG_0004.JPG", "IMG_0004.NEF",
        ])

        library.delete([SamplePhotos.tram])
        let deleted = try await indexer.update()
        #expect(deleted.copies == 0 && deleted.missing.isEmpty && deleted.inserted.isEmpty)
        #expect(try await Self.listed(in: "album-porto", sandbox) == ["IMG_0004.JPG", "IMG_0004.NEF"])
        let copy = try await sandbox.rows(below: sandbox.destination)["Lisbon/IMG_0001.HEIC"]
        #expect(copy != nil && copy?.state.contains(.missing) == false, "the copy is the folder's still")
    }

    /// The first keep after 0.3.4's import, at scale: 50,000 assets, 10,000 of them copied into the library's folders,
    /// each copy's sidecar read once, within LIB-58's budget (the first 1,000 listed in 1 s, all indexed in 15 s).
    /// Skipped unless `REDLAMP_APPLE_PHOTOS_BENCH=1` (`TEST_RUNNER_REDLAMP_APPLE_PHOTOS_BENCH=1`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_APPLE_PHOTOS_BENCH"] == "1"))
    func `50,000 assets, 10,000 of them copied, are kept within LIB-58's budget`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let library = ApplePhotosFixture.generated(50000)
        let copied = try await library.assets(in: ApplePhotosFixture.albums.map(\.id)).prefix(10000)
        let folder = LibraryIndexer.path(sandbox.directory.appending(path: "Copies", directoryHint: .isDirectory))
        let (volume, albums) = (sandbox.volume, ApplePhotosFixture.albums.map(\.id))
        let photos = copied.map { asset in
            let name = asset.originals.first?.originalFilename ?? ""
            return (asset: asset, path: folder + "/" + (asset.albums.first ?? "") + "/" + name)
        }
        try await sandbox.index.write { writer in
            let root = try writer.upsertRoot(RootRecord(volume: volume, path: folder))
            try writer.upsertFolder(FolderRecord(root: root, path: folder))
            var folders: [String: Int64] = [:]
            for album in albums {
                folders[album] = try writer.upsertFolder(FolderRecord(root: root, path: folder + "/" + album))
            }
            try writer.upsertPhotos(photos.map { copy in
                let name = (copy.path as NSString).lastPathComponent
                return PhotoRecord(
                    folder: folders[copy.asset.albums.first ?? ""] ?? 0, name: name,
                    kind: PhotoRecord.Kind(pathExtension: (name as NSString).pathExtension),
                )
            })
        }
        for album in albums {
            try FileManager.default.createDirectory(atPath: folder + "/" + album, withIntermediateDirectories: true)
        }
        for copy in photos {
            let origin = ApplePhotosOrigin(id: copy.asset.id, cloud: copy.asset.cloud)
            try SidecarStore().save(
                Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(applePhotos: origin)),
                for: URL(fileURLWithPath: copy.path),
            )
        }
        try ApplePhotosRecordFile(paths: LibraryPaths(root: sandbox.directory)).change { record in
            for copy in photos {
                record.assets[copy.asset.id] = ApplePhotosRecord.Asset(cloud: copy.asset.cloud, paths: [copy.path])
            }
        }

        let indexer = ApplePhotosIndexer(photos: library, index: sandbox.index)
        let outcome = try await indexer.keep(albums)
        let again = try await indexer.index()
        print(
            "LIB-64 bench: 50,000 assets, 10,000 copied; \(outcome.copies) copies standing in, "
                + "\(outcome.inserted.count) rows from Photos; first batch in \(outcome.firstBatch ?? .zero), "
                + "all in \(outcome.elapsed); a pass with nothing changed in \(again.elapsed)",
        )
        #expect(outcome.assets == 50000 && outcome.copies == 10000 && again.copies == 10000)
        #expect(try #require(outcome.firstBatch) < .seconds(1))
        #expect(outcome.elapsed < .seconds(15))
    }
}
