import Foundation
import Testing
@testable import RedlampLibrary

/// The census of an import from Apple Photos (LIB-54) on the simulated library: what each kind of asset comes
/// to, what's left and why, and the fields each macOS gives.
struct ApplePhotosCensusTests {
    @Test func `the tree lists folders before their albums, with counts, and resolves titles, paths and IDs`(
    ) async throws {
        let tree = try await ApplePhotosTree(SamplePhotos.library().collections())
        #expect(tree.collections.map(\.id) == [
            "album-selects", "folder-trips", "album-lisbon", "album-porto", "smart-favourites", "shared-family",
        ])
        #expect(tree.children(of: "folder-trips").map(\.title) == ["Lisbon", "Porto"])
        #expect(tree["folder-trips"]?.estimatedCount == nil && tree["album-porto"]?.estimatedCount == 3)
        #expect(tree.path(of: "album-lisbon")?.text == "Trips/Lisbon")
        #expect(tree.resolve("porto")?.id == "album-porto")
        #expect(tree.resolve("Trips/Lisbon")?.id == "album-lisbon")
        #expect(tree.resolve("shared-family")?.kind == .sharedAlbum)
        #expect(tree.resolve("Nowhere") == nil)
        #expect(tree.standardChoice == ["album-selects", "album-lisbon", "album-porto"])
        #expect(tree.albums(in: ["folder-trips", "album-porto"]).map(\.id) == ["album-lisbon", "album-porto"])
    }

    @Test func `the standard choice takes every album, each photo once, and leaves videos, hidden photos and frames`(
    ) async throws {
        let census = try await ApplePhotosCensus.make(SamplePhotos.library())
        let report = census.report
        #expect(report.albums == ["album": 3])
        #expect(report.assets == 10, "the burst's frames come with its key photo")
        #expect(Set(census.taken.map(\.id)) == [
            SamplePhotos.tram, SamplePhotos.edited, SamplePhotos.live, SamplePhotos.pair, SamplePhotos.dng,
            SamplePhotos.burstKey, SamplePhotos.burstPick,
        ])
        #expect(census.left == [
            SamplePhotos.video: .video, SamplePhotos.hidden: .hidden, SamplePhotos.burstFrame: .burstFrame,
        ])
        #expect(report.photos == 7 && report.libraryPhotos == 8, "the edit's rendering is a photo of its own")
        #expect(report.files == 9, "the pair's two files and the edit's rendering")
        #expect(report.pairs == 1 && report.raws == 1 && report.dngs == 1)
        #expect(report.edited == 1 && report.editedWithoutRendering == 0)
        #expect(report.livePhotos == 1)
        #expect(report.bursts == 1 && report.burstFrames == 2 && report.burstFramesLeft == 1)
        #expect(report.videosLeft == 1 && report.hiddenLeft == 1 && report.hiddenIncluded == 0)
        #expect(report.inSeveralAlbums == 2, "the tram in Lisbon and Porto, the pair in Selects and Porto")
        #expect(report.favorites == 2 && report.sharedCopies == 0)
        #expect(report.withLocation == 2)
        #expect(report.types == ["public.heic": 2, "public.jpeg": 4, "com.adobe.raw-image": 1])
        #expect(report.pairRawTypes == ["public.camera-raw-image": 1])
        #expect(report.editTypes == ["public.jpeg → public.jpeg": 1])
        #expect(report.resources["pairedVideo+photo"] == 1 && report.resources["fullSizePhoto+other+photo"] == 1)
        #expect(report.leftInPhotos.contains("titles") && report.leftInPhotos.contains("people and pets"))
    }

    @Test func `hidden photos come when included, smart and shared albums when chosen, and imports are left`(
    ) async throws {
        let census = try await ApplePhotosCensus.make(
            SamplePhotos.library(), choosing: ["album-lisbon", "smart-favourites", "shared-family"],
            includesHidden: true, imported: [SamplePhotos.tram],
        )
        let report = census.report
        #expect(report.albums == ["album": 1, "smartAlbum": 1, "sharedAlbum": 1])
        #expect(census.taken.contains { $0.id == SamplePhotos.hidden } && report.hiddenIncluded == 1)
        #expect(census.left[SamplePhotos.tram] == .imported && report.alreadyImported == 1)
        #expect(report.sharedCopies == 1)
        let pair = try #require(census.taken.first { $0.id == SamplePhotos.pair })
        #expect(pair.albums == ["smart-favourites"], "only the chosen albums it's in")
        let tram = try await ApplePhotosCensus.make(SamplePhotos.library(), choosing: ["smart-favourites"])
            .taken.first { $0.id == SamplePhotos.tram }
        #expect(tram?.albums == ["smart-favourites"])
    }

    @Test func `macOS 27 gives ratings, captions and keywords; macOS 26 gives none of them and says so`(
    ) async throws {
        let later = try await ApplePhotosCensus.make(SamplePhotos.library(macOS: 27))
        #expect(later.report.fields.contains(.rating) && later.report.fromMacOS27.isEmpty)
        #expect(later.report.rated == 1 && later.report.captioned == 1 && later.report.withKeywords == 1)
        let tram = try #require(later.taken.first { $0.id == SamplePhotos.tram })
        #expect(tram.rating == 4 && tram.caption == "The tram climbing to Graça." && tram.keywords == [
            "Tram",
            "Lisbon",
        ])

        let now = try await ApplePhotosCensus.make(SamplePhotos.library(macOS: 26))
        #expect(now.report.fields == [.favorite, .date, .originalName, .albums, .location])
        #expect(now.report.fromMacOS27 == [.rating, .caption, .keywords])
        #expect(now.report.rated == 0 && now.report.captioned == 0 && now.report.withKeywords == 0)
        #expect(now.taken.allSatisfy { $0.rating == nil && $0.caption == nil && $0.keywords == nil })
        #expect(now.report.lines().contains { $0.contains("macOS 27 adds rating, caption, keywords") })
    }

    @Test func `a date unchanged in Photos is the time the file records, and a changed one is Photos' own`(
    ) async throws {
        let assets = try await SamplePhotos.library().assets(in: ["album-lisbon"])
        let tram = try #require(assets.first { $0.id == SamplePhotos.tram })
        #expect(tram.created == ISO8601DateFormatter().date(from: "2026-10-05T08:00:00Z"), "09:00 at +01:00")
        let edited = try #require(assets.first { $0.id == SamplePhotos.edited })
        #expect(edited.created == ISO8601DateFormatter().date(from: "2026-10-05T10:30:00Z"))
    }

    @Test func `the report names no album, photo or place, and reads back as it was written`() async throws {
        let census = try await ApplePhotosCensus.make(
            SamplePhotos.library(), choosing: ["folder-trips", "album-selects", "smart-favourites", "shared-family"],
        )
        let json = try census.report.json()
        let text = String(decoding: json, as: UTF8.self) + census.report.lines().joined(separator: "\n")
        for secret in ["Lisbon", "Porto", "Selects", "Family", "Favourites", "IMG_", "8A1F", "Graça", "38.71"] {
            #expect(!text.contains(secret), "the report names “\(secret)”")
        }
        #expect(try JSONDecoder().decode(ApplePhotosReport.self, from: json) == census.report)
    }

    @Test func `the census asks for nothing while access isn't given, and a limited library lists no albums`(
    ) async throws {
        let folder = try TemporaryFolder()
        for (access, grants) in [("notDetermined", "denied"), ("limited", "limited")] {
            let url = try SamplePhotos.manifest(
                in: folder.url, collections: [["id": "a", "title": "A", "kind": "album"]], assets: [],
                extra: ["access": access, "grants": grants],
            )
            let library = try SimulatedPhotosLibrary(manifest: url)
            await #expect(throws: ApplePhotosError.self) {
                try await ApplePhotosCensus.make(library)
            }
            #expect(await library.requestAccess() == ApplePhotosAccess(rawValue: grants))
        }
    }

    @Test func `a census of 10,000 assets takes under 2 s`() async throws {
        let folder = try TemporaryFolder()
        let assets = (0 ..< 10000).map { number -> [String: Any] in
            [
                "id": "asset-\(number)", "created": "2026-10-05T09:00:00Z", "favorite": number % 7 == 0,
                "albums": ["album-\(number % 20)"],
                "resources": [["kind": "photo", "name": String(format: "IMG_%05d.HEIC", number)]],
            ]
        }
        let url = try SamplePhotos.manifest(
            in: folder.url,
            collections: (0 ..< 20).map { ["id": "album-\($0)", "title": "Album \($0)", "kind": "album"] },
            assets: assets,
        )
        let library = try SimulatedPhotosLibrary(manifest: url)
        let clock = ContinuousClock()
        let started = clock.now
        let census = try await ApplePhotosCensus.make(library)
        let elapsed = clock.now - started
        #expect(census.report.photos == 10000)
        #expect(elapsed < .seconds(2), "\(elapsed)")
    }
}
