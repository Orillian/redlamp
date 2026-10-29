import Foundation
import Synchronization
import Testing
@testable import RedlampLibrary

/// The census of a Photos library (LIB-57), run end to end on the simulated library of `census.json`: three photos on
/// this Mac and seven only in iCloud (one whose images Photos doesn't keep either), a RAW+JPEG pair, two edited in
/// Photos, a video and a hidden photo, in Photos' Library, with iCloud slowed so downloads can be cancelled partway.
struct PhotoKitCensusTests {
    static let manifest = SamplePhotos.folder.appending(path: "census.json")
    static let tram = "CE000001-0000-4000-8000-000000000001/L0/001"
    static let walk = "CE000002-0000-4000-8000-000000000002/L0/001"
    static let coast = "CE000003-0000-4000-8000-000000000003/L0/001"

    struct Network: ApplePhotosNetwork {
        var isReachable = true
        var isExpensive = false
    }

    /// Every photo sampled, the waits short.
    static var plan: PhotoKitCensus.Plan {
        var plan = PhotoKitCensus.Plan()
        plan.downloads = 3
        plan.cancels = 3
        plan.spares = 1
        plan.lanes = 2
        plan.timeout = .seconds(30)
        plan.preparing = .milliseconds(10)
        plan.watching = .milliseconds(100)
        plan.settling = .milliseconds(10)
        return plan
    }

    final class Said: Sendable {
        let lines = Mutex<[String]>([])
    }

    static func census(
        _ library: SimulatedPhotosLibrary, in folder: URL, network: Network = Network(), said: Said = Said(),
    ) -> PhotoKitCensus {
        PhotoKitCensus(photos: library, images: library, probe: library, network: network, folder: folder) { line in
            said.lines.withLock { $0.append(line) }
        }
    }

    /// The census's library, its iCloud slow enough that a download of one of its small files can be cancelled partway.
    static func library() throws -> SimulatedPhotosLibrary {
        let library = try SimulatedPhotosLibrary(manifest: manifest)
        library.network = .init(latency: .milliseconds(50), rate: 2000)
        return library
    }

    static func scratch() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "redlamp-census-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// What the report, its text and what the census said may never hold: the library's identifiers, files, albums,
    /// caption, keyword and place.
    static func secrets() throws -> [String] {
        let manifest = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
        )
        let assets = manifest["assets"] as? [[String: Any]] ?? []
        let collections = manifest["collections"] as? [[String: Any]] ?? []
        var secrets = assets.flatMap { asset in
            [asset["id"] as? String, asset["cloud"] as? String, asset["caption"] as? String].compactMap(\.self)
                + (asset["keywords"] as? [String] ?? [])
                + (asset["resources"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        }
        secrets += collections.compactMap { $0["title"] as? String }.filter { $0 != "Library" }
        secrets += collections.compactMap { $0["id"] as? String }
        return secrets + ["38.71", "9.133", "CE0000"]
    }

    static func expectNothingNamed(_ census: PhotoKitCensus, _ said: Said) throws {
        let written = try String(contentsOf: census.reportURL, encoding: .utf8)
            + String(contentsOf: census.textURL, encoding: .utf8) + said.lines.withLock { $0.joined(separator: "\n") }
        for secret in try secrets() {
            #expect(!written.contains(secret), "the census names “\(secret)”")
        }
    }

    @Test func `the census measures the simulated library end to end and names nothing in it`() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Self.library()
        let said = Said()
        let census = Self.census(library, in: folder, said: said)
        let report = try await census.run(.measure, plan: Self.plan)

        #expect(report.notes.isEmpty, "\(report.notes)")
        #expect(report.access == .authorized && report.ran["measure"] != nil)
        let shape = try #require(report.library)
        #expect(shape.assets == 12 && shape.photos == 10 && shape.videos == 1 && shape.hidden == 1)
        #expect(shape.edited == 2 && shape.editsRendered == 2 && shape.pairs == 1 && shape.live == 1)
        #expect(shape.screenshots == 1 && shape.collections == ["smartAlbum": 1, "album": 2, "folder": 1])
        #expect(Set(shape.milliseconds.keys) == ["collections", "assets", "listedIDs"])

        let index = try #require(report.index)
        #expect(index.assets == 10 && index.videos == 1 && index.hidden == 1, "\(index)")
        #expect(index.rows == 13, "ten photos, a pair's raw and two Photos edits")
        #expect(!index.unchangedWhole && index.firstBatchMilliseconds != nil)

        let sample = try #require(report.sample)
        #expect(sample.photos == 10 && sample.edited == 2)
        #expect(sample.originals == ["local": 3, "inCloud": 7] && sample.pairRaws == ["inCloud": 1])

        let images = try #require(report.images)
        let inCloud = try #require(images.current["inCloud"])
        #expect(inCloud.grid.asked == 7 && inCloud.grid.given == 6 && inCloud.grid.inCloud == 1)
        #expect(inCloud.preview.given == 6 && inCloud.largest.given == 6 && inCloud.largest.longEdge?.max == 64)
        #expect(images.current["local"]?.grid.given == 3)
        #expect(images.edited["original"]?.grid.given == 2 && images.edited["current"]?.largest.given == 2)
        #expect(images.screenfuls.isEmpty, "every photo was sampled, so none is left for a screenful")

        let exif = try #require(report.exif)
        #expect(exif.byOriginal["inCloud"]?.asked == 7 && exif.byOriginal["inCloud"]?.given == 0)
        #expect(exif.byOriginal["local"]?.given == 3 && exif.byOriginal["local"]?.fields["taken"] == 3)
        #expect(exif.byOriginal["local"]?.fields["gps"] == 1 && exif.byOriginal["local"]?.fields["camera"] == 3)
        #expect(exif.byOriginal["local"]?.fields["lens"] == nil, "the fixture's photos name their iPhone, no lens")

        let changes = try #require(report.changes)
        #expect(changes.sinceStart == ["inserted": 0, "updated": 0, "deleted": 0, "collections": 0])

        let downloads = try #require(report.downloads)
        #expect(downloads.asked == 4 && downloads.completed == 4, "three photos, one of them a pair")
        #expect(downloads.afterwards == ["inCloud": 4], "the simulated Photos keeps nothing it downloads")
        #expect(downloads.firstBytesMilliseconds.map { $0.min >= 50 } == true, "after iCloud's latency")
        #expect(downloads.megabytes != nil && downloads.freeBefore["available"] != nil)

        let cancels = try #require(report.cancels)
        #expect(cancels.asked == 3 && cancels.cancelled == 3, "\(cancels)")
        #expect(cancels.at == ["firstProgress": 1, "quarter": 1, "half": 1])
        #expect(cancels.ended == ["cancelled": 3] && cancels.grewAfterwards == 0)

        #expect(FileManager.default.fileExists(atPath: census.stateURL.path))
        #expect(!FileManager.default.fileExists(atPath: census.scratch.path), "the downloads are gone")
        let read = try PhotoKitCensusReport.read(Data(contentsOf: census.reportURL))
        #expect(try read.json() == report.json(), "the report reads back as it was written")
        #expect(report.lines().contains { $0.hasPrefix("Downloads from iCloud (LIB-60): 4 of 4") })
        try Self.expectNothingNamed(census, said)
    }

    @Test func `screenfuls ask for the grid's thumbnails on several lanes, prepared ahead or not`() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Self.library()
        var plan = Self.plan
        plan.sample = 0
        plan.edited = 0
        plan.screenful = 3
        plan.screenfuls = 2
        plan.cachedScreenfuls = 1
        let report = try await Self.census(library, in: folder).run(.measure, plan: plan)

        let screenfuls = try #require(report.images?.screenfuls)
        #expect(screenfuls.map(\.cached) == [false, true])
        #expect(screenfuls[0].count == 2 && screenfuls[0].given + screenfuls[0].inCloud == 6)
        #expect(screenfuls[1].count == 1 && screenfuls[1].given + screenfuls[1].inCloud == 3)
        #expect(screenfuls.allSatisfy { $0.lanes == 2 && $0.thumbnails == 3 && $0.milliseconds != nil })
        #expect(library.cachedImages["census"] == nil, "the caching window is let go")
        #expect(report.downloads?.asked == 0)
    }

    @Test func `a photo recovered from Recently Deleted is found again, by its identifier or its cloud identifier`()
        async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Self.library()
        let said = Said()
        let census = Self.census(library, in: folder, said: said)
        try await census.run(.measure, plan: Self.plan)
        let assets = try await library.assets(in: ["smart-census-library"])
        let tram = try #require(assets.first { $0.id == Self.tram })
        var walk = try #require(assets.first { $0.id == Self.walk })
        library.delete([Self.tram, Self.walk, Self.coast])
        library.insert(tram)
        walk.id = "CE0000FF-0000-4000-8000-0000000000FF/L0/001"
        library.insert(walk)

        let report = try await census.run(.recovered)
        let recovered = try #require(report.recovered)
        #expect(recovered.changeSets == 3 && recovered.changed["deleted"] == 3 && recovered.changed["inserted"] == 2)
        #expect(recovered.sameIdentifier == 1 && recovered.newIdentifier == 1 && recovered.notBack == 1)
        #expect(recovered.patterns == ["deleted, inserted": 1, "deleted": 2])
        #expect(recovered.readAs == ["deleted": 3], "read all at once, a photo deleted then given back reads deleted")
        let pass = try #require(recovered.index)
        #expect(!pass.whole && pass.missing >= 1, "\(pass)")
        #expect(report.library != nil, "the first step's part stays")
        try Self.expectNothingNamed(census, said)
    }

    @Test func `offline, a download of an original only in iCloud ends as iCloud out of reach`() async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Self.library()
        try await Self.census(library, in: folder).run(.measure, plan: Self.plan)
        library.network = .init(offline: true, latency: .milliseconds(50), rate: 2000)

        let report = try await Self.census(library, in: folder, network: Network(isReachable: false)).run(.offline)
        let offline = try #require(report.offline)
        #expect(!offline.reachable && offline.tried && offline.asOffline && offline.ended == "offline")
        #expect(offline.preview == "given", "Photos' local images are there offline")
    }

    @Test func `a week on, the census reads Photos' history since it measured, or says Photos no longer has it`()
        async throws {
        let folder = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Self.library()
        let census = Self.census(library, in: folder)
        try await census.run(.measure, plan: Self.plan)
        library.update(Self.coast) { $0.isFavorite = true }

        let report = try await census.run(.week)
        let week = try #require(report.week)
        #expect(!week.expired && week.changeSets == 1 && week.changed["updated"] == 1)
        #expect(week.downloaded == ["inCloud": 4] && week.cancelled == ["inCloud": 3])
        #expect(week.index.map { !$0.whole && $0.updated == 1 } == true, "\(String(describing: week.index))")
        #expect(!FileManager.default.fileExists(atPath: census.stateFolder.path), "what it kept is deleted")
        await #expect(throws: PhotoKitCensus.NotMeasured.self) { try await census.run(.recovered) }

        try await census.run(.measure, plan: Self.plan)
        library.expireHistory()
        let expired = try await census.run(.week)
        #expect(expired.week?.expired == true && expired.week?.index?.whole == true)
    }
}
