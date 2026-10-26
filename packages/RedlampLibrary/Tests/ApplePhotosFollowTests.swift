import Foundation
import Testing
@testable import RedlampLibrary

/// The albums an import from Apple Photos follows (LIB-55): their new photos are the assets the record doesn't
/// name, counted with the last import's settings, and counted within 100 ms for albums of 10,000 photos.
struct ApplePhotosFollowTests {
    @Test func `the followed albums' new photos are those the record doesn't name, with the last import's settings`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let folder = sandbox.folder.url.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["IMG_0002.JPG", "IMG_0010.JPG"] {
            try FileManager.default.copyItem(
                at: SamplePhotos.folder.appending(path: "files/\(name)"), to: folder.appending(path: name),
            )
        }
        let collections: [[String: Any]] = [
            ["id": "album-a", "title": "A", "kind": "album"], ["id": "album-b", "title": "B", "kind": "album"],
        ]
        func asset(_ number: Int, _ name: String, albums: [String]) -> [String: Any] {
            ["id": "asset-\(number)", "created": "2026-10-0\(number)T10:00:00Z", "albums": albums, "resources": [
                ["kind": "photo", "name": name, "file": "Photos/\(name)"],
            ]]
        }
        let first = try SamplePhotos.manifest(
            in: sandbox.folder.url, collections: collections, assets: [asset(1, "IMG_0002.JPG", albums: ["album-a"])],
        )
        let importing = try ApplePhotosImport(photos: SimulatedPhotosLibrary(manifest: first), library: sandbox.library)
        #expect(try await importing.followedNews() == nil, "nothing followed yet")
        let settings = try ApplePhotosImport.Settings(
            collections: ["album-a"], copying: sandbox.settings(folders: "{album}", backup: false),
        )
        try await importing.run(settings)
        let caughtUp = try #require(try await importing.followedNews())
        #expect(caughtUp.settings.collections == ["album-a"] && caughtUp.settings.copying == settings.copying)
        #expect(caughtUp.census.report.photos == 0 && caughtUp.census.report.alreadyImported == 1)

        let arrived = try SamplePhotos.manifest(in: sandbox.folder.url, collections: collections, assets: [
            asset(1, "IMG_0002.JPG", albums: ["album-a"]), asset(2, "IMG_0010.JPG", albums: ["album-a", "album-b"]),
            asset(3, "IMG_0010.JPG", albums: ["album-b"]),
        ])
        let later = try ApplePhotosImport(photos: SimulatedPhotosLibrary(manifest: arrived), library: sandbox.library)
        let news = try #require(try await later.followedNews())
        #expect(news.census.report.photos == 1, "the new photo in A; B isn't followed")
        let outcome = try await later.run(news.settings, census: news.census)
        #expect(outcome.imported == 1 && outcome.state == .finished)
        #expect(try await later.followedNews()?.census.report.photos == 0)
        #expect(ImportSandbox.files(in: sandbox.destination).keys.filter { !$0.contains(".redlamp") }.sorted()
            == ["A/IMG_0002.JPG", "A/IMG_0010.JPG"])
    }

    @Test func `followed albums of 10,000 photos are counted within 100 ms`() async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let assets: [[String: Any]] = (0 ..< 10000).map { number in
            [
                "id": "asset-\(number)", "created": "2026-10-01T10:00:00Z", "favorite": number % 7 == 0,
                "albums": [number % 2 == 0 ? "album-a" : "album-b"],
                "resources": [["kind": "photo", "name": String(format: "IMG_%05d.HEIC", number)]],
            ]
        }
        let manifest = try SamplePhotos.manifest(in: sandbox.folder.url, collections: [
            ["id": "folder", "title": "Trips", "kind": "folder"],
            ["id": "album-a", "title": "A", "kind": "album", "parent": "folder"],
            ["id": "album-b", "title": "B", "kind": "album"],
        ], assets: assets)
        let importing = try ApplePhotosImport(
            photos: SimulatedPhotosLibrary(manifest: manifest),
            library: sandbox.library,
        )
        let settings = try ApplePhotosImport.Settings(
            collections: ["folder", "album-b"],
            copying: sandbox.settings(backup: false),
        )
        let imported = Dictionary(uniqueKeysWithValues: (0 ..< 3000).map { number in
            ("asset-\(number)", ApplePhotosRecord.Asset(paths: ["/Pictures/IMG_\(number).HEIC"]))
        })
        try importing.record.change { record in
            record.keep(ApplePhotosRecord.Import(
                id: UUID(), date: Date(), albums: [], settings: settings, state: .finished, photos: imported.count,
            ))
            record.follow([
                ApplePhotosRecord.Album(id: "album-a", title: "A", kind: .album, path: "Trips/A"),
                ApplePhotosRecord.Album(id: "album-b", title: "B", kind: .album, path: "B"),
            ])
            record.assets = imported
        }
        var fastest = Duration.seconds(60)
        for _ in 0 ..< 3 {
            let started = ContinuousClock.now
            let news = try #require(try await importing.followedNews())
            fastest = min(fastest, ContinuousClock.now - started)
            #expect(news.census.report.photos == 7000)
        }
        #expect(fastest < .milliseconds(100), "\(fastest)")
    }
}
