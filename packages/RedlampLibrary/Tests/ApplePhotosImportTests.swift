import Foundation
import RedlampDocument
import Synchronization
import Testing
@testable import RedlampLibrary

/// An import from Apple Photos (LIB-54) on the simulated library, through the card import into a library with
/// an index: each photo copied once with Photos' fields in its sidecar, its albums as collections, edits and
/// bursts stacked, the record kept, a stopped import taken up again, and Undo Import.
struct ApplePhotosImportTests {
    private static func settings(_ sandbox: ImportSandbox, collections: [String]? = nil) throws
        -> ApplePhotosImport.Settings {
        try ApplePhotosImport.Settings(
            collections: collections, copying: sandbox.settings(folders: "{album}", backup: false),
        )
    }

    private static func sidecar(_ sandbox: ImportSandbox, _ path: String) throws -> PhotoMetadata {
        try #require(SidecarStore().load(for: sandbox.destination.appending(path: path))?.metadata, "\(path)")
    }

    private static func emptyTrash(of undone: ApplePhotosImport.Undone) {
        for file in undone.rollbacks.flatMap(\.trashed) {
            try? FileManager.default.removeItem(atPath: file.to)
        }
    }

    @Test func `each photo is copied once, with Photos' fields, its albums and its stack in its sidecar`(
    ) async throws {
        try #require(SamplePhotos.hasRaws, "the CC0 raws in tests/fixtures/raw")
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let importing = try ApplePhotosImport(photos: SamplePhotos.library(), library: sandbox.library)
        let stages = Mutex<[ApplePhotosImport.Stage]>([])
        let outcome = try await importing.run(Self.settings(sandbox)) { progress in
            stages.withLock {
                if $0.last != progress.stage {
                    $0.append(progress.stage)
                }
            }
        }
        #expect(stages.withLock { $0 } == [.census, .staging, .copying, .finishing])
        #expect(outcome.state == .finished && outcome.stagingFailures.isEmpty)
        #expect(outcome.imported == 7 && outcome.copy?.verified == 8, "the edit's rendering is a photo of its own")
        #expect(outcome.placesOnlyInPhotos == 1, "the Live Photo's file holds no GPS")
        let photos = Set(ImportSandbox.files(in: sandbox.destination).keys.filter { !$0.contains(".redlamp") })
        #expect(photos == [
            "Lisbon/IMG_0001.HEIC", "Lisbon/IMG_0002.JPG", "Lisbon/IMG_0002 (Photos edit).jpeg",
            "Lisbon/IMG_0003.HEIC", "Lisbon/IMG_0010.JPG", "Lisbon/IMG_0012.JPG", "Selects/IMG_0004.JPG",
            "Selects/IMG_0004.NEF", "Porto/IMG_0005.DNG",
        ])
        #expect(!FileManager.default.fileExists(atPath: ApplePhotosStager.root(for: sandbox.destination).path))

        let tram = try Self.sidecar(sandbox, "Lisbon/IMG_0001.HEIC")
        #expect(tram.flag == .pick && tram.rating == 4 && tram.caption == "The tram climbing to Graça.")
        #expect(tram.keywords == ["Tram", "Lisbon"] && tram.collections == ["Trips/Lisbon", "Trips/Porto"])
        #expect(tram.applePhotos == ApplePhotosOrigin(id: SamplePhotos.tram, cloud: "cloud-0001"))
        #expect(tram.stack == nil && tram.captureShift == 0 && tram.captureOffset == nil)

        let original = try Self.sidecar(sandbox, "Lisbon/IMG_0002.JPG")
        let edit = try Self.sidecar(sandbox, "Lisbon/IMG_0002 (Photos edit).jpeg")
        #expect(original.applePhotos?.version == .original && edit.applePhotos?.version == .edited)
        #expect(original.stack?.id != nil && original.stack?.id == edit.stack?.id)
        #expect(original.stack?.top == false && edit.stack?.top == true, "the edit shown, as Photos shows it")
        #expect(original.captureShift == 5400 && edit.captureShift == 5400, "the date changed in Photos")
        #expect(original.captureOffset == nil && original.flag == nil)

        for half in ["Selects/IMG_0004.JPG", "Selects/IMG_0004.NEF"] {
            let pair = try Self.sidecar(sandbox, half)
            #expect(pair.flag == .pick && pair.collections == ["Selects", "Trips/Porto"], "\(half)")
            #expect(pair.applePhotos?.id == SamplePhotos.pair && pair.captureShift == 0, "\(half)")
        }
        let key = try Self.sidecar(sandbox, "Lisbon/IMG_0010.JPG")
        let pick = try Self.sidecar(sandbox, "Lisbon/IMG_0012.JPG")
        #expect(key.stack?.id == pick.stack?.id && key.stack?.top == true && pick.stack?.top == false)
        #expect(pick.collections == ["Trips/Lisbon"])

        let collections = try await LibraryMetadata(index: sandbox.index, paths: sandbox.paths).collections.list()
        #expect(try collections[#require(CollectionPath("Trips"))]?.kind == .set)
        #expect(try collections[#require(CollectionPath("Trips/Lisbon"))]?.photos == 6)
        #expect(try collections[#require(CollectionPath("Selects"))]?.kind == .collection)

        let record = try importing.record.load()
        #expect(record.assets.count == 7 && record.imports.map(\.state) == [.finished])
        #expect(record.followed.map(\.path) == ["Selects", "Trips/Lisbon", "Trips/Porto"])
        #expect(try importing.followedAlbums().map(\.id) == ["album-selects", "album-lisbon", "album-porto"])
        let edited = try #require(record.assets[SamplePhotos.edited])
        #expect(edited.paths.map { ($0 as NSString).lastPathComponent } == [
            "IMG_0002.JPG",
            "IMG_0002 (Photos edit).jpeg",
        ])
        #expect(FileManager.default.fileExists(atPath: sandbox.paths.root.appending(path: "Apple Photos.json").path))
    }

    @Test func `a later import skips what the record names, and brings a shared album's copy when it's chosen`(
    ) async throws {
        try #require(SamplePhotos.hasRaws, "the CC0 raws in tests/fixtures/raw")
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let importing = try ApplePhotosImport(photos: SamplePhotos.library(), library: sandbox.library)
        try await importing.run(Self.settings(sandbox))
        let again = try await importing.census(Self.settings(sandbox))
        #expect(again.report.photos == 0 && again.report.alreadyImported == 7)
        let shared = try Self.settings(sandbox, collections: ["folder-trips", "shared-family"])
        let outcome = try await importing.run(shared)
        #expect(outcome.report.photos == 1 && outcome.report.sharedCopies == 1 && outcome.imported == 1)
        #expect(try Self.sidecar(sandbox, "Family/IMG_0040.JPG").collections == ["Family"])
        #expect(try importing.record.load().assets.count == 8)
    }

    @Test func `a stopped import keeps what it staged and takes up where it was`() async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let settings = try Self.settings(sandbox, collections: ["album-lisbon"])
        let holding = try ApplePhotosStagingTests.HoldingLibrary(
            SamplePhotos.library(),
            holding: ["FullSizeRender.jpeg"],
        )
        let importing = ApplePhotosImport(photos: holding, library: sandbox.library)
        let running = Task { try await importing.run(settings) }
        while !holding.writes.withLock({ $0.contains("FullSizeRender.jpeg") }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        importing.stop()
        let stopped = try await running.value
        #expect(stopped.state == .stopped && stopped.copy == nil)
        #expect(try importing.record.load().imports.map(\.state) == [.stopped])
        let staging = ApplePhotosStager(library: holding, destination: sandbox.destination, id: stopped.id).folder
        #expect(FileManager.default.fileExists(atPath: staging.path))

        let resumed = try await ApplePhotosImport(photos: holding.base, library: sandbox.library).run(settings)
        #expect(resumed.id == stopped.id && resumed.state == .finished && resumed.imported == 5)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(try importing.record.load().imports.map(\.state) == [.finished])
    }

    @Test func `Undo Import takes the copies back, and the record forgets the import and the albums only it followed`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let importing = try ApplePhotosImport(photos: SamplePhotos.library(), library: sandbox.library)
        let outcome = try await importing.run(Self.settings(sandbox, collections: ["album-lisbon"]))
        #expect(outcome.imported == 5)
        let undone = try await importing.undo()
        defer { Self.emptyTrash(of: undone) }
        #expect(undone.record.id == outcome.id && undone.record.state == .undone)
        #expect(undone.rollbacks.map(\.state) == [.rolledBack] && undone.rollbacks[0].rolledBack.count == 6)
        #expect(ImportSandbox.files(in: sandbox.destination).isEmpty, "the photos and their sidecars")
        let record = try importing.record.load()
        #expect(record.assets.isEmpty && record.followed.isEmpty && record.lastImport == nil)
        await #expect(throws: ApplePhotosImportError.nothingToUndo) { try await importing.undo() }
        #expect(try await importing.census(Self.settings(sandbox, collections: ["album-lisbon"])).report.photos == 5)
    }

    @Test func `the record's assets are rebuilt from the photos' sidecars`() async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let importing = try ApplePhotosImport(photos: SamplePhotos.library(), library: sandbox.library)
        try await importing.run(Self.settings(sandbox, collections: ["album-lisbon"]))
        let kept = try importing.record.load().assets
        try FileManager.default.removeItem(at: importing.record.url)
        let photos = ImportSandbox.files(in: sandbox.destination).keys.filter { !$0.contains(".redlamp") }
            .map { sandbox.destination.appending(path: $0) }
        #expect(try importing.record.rebuild(fromSidecarsOf: photos) == 5)
        let rebuilt = try importing.record.load().assets
        #expect(Set(rebuilt.keys) == Set(kept.keys))
        #expect(rebuilt[SamplePhotos.edited]?.paths.map { ($0 as NSString).lastPathComponent }
            == ["IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg"])
        #expect(rebuilt.values.allSatisfy { $0.importID == nil })
    }

    @Test func `a date is shifted only where Photos' differs from the file's, in the file's zone or the one given`() {
        let lisbon = TimeZone(identifier: "Europe/Lisbon") ?? .current
        let wallClock = cameraTime()
        let recorded = CaptureMetadata(captured: wallClock, capturedOffset: 3600)
        let same = wallClock.addingTimeInterval(-3600)
        #expect(ApplePhotosCopy.captureTime(given: same, recorded: recorded) == (0, nil))
        #expect(ApplePhotosCopy.captureTime(given: same.addingTimeInterval(0.4), recorded: recorded) == (0, nil))
        #expect(ApplePhotosCopy.captureTime(given: same.addingTimeInterval(-7200), recorded: recorded) == (-7200, nil))
        let unzoned = CaptureMetadata(captured: wallClock)
        #expect(ApplePhotosCopy.captureTime(given: same, recorded: unzoned, zone: lisbon) == (0, nil), "summer time")
        #expect(ApplePhotosCopy.captureTime(given: same.addingTimeInterval(60), recorded: unzoned, zone: lisbon)
            == (60, 3600))
        #expect(ApplePhotosCopy.captureTime(given: same, recorded: nil) == (0, nil))
        #expect(ApplePhotosCopy.captureTime(given: nil, recorded: recorded) == (0, nil))
    }
}
