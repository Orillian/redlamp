import AppKit
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@testable import RedlampUI

/// Batch export (EDT-16): photos that aren't open rendered in an engine of the batch's own, one at a time, each
/// with its edit as it was when Export was clicked.
@MainActor
struct BatchExportTests {
    private struct Fixture {
        let model: EditorModel
        let worker: StubEngine
        let folder: URL
        let photos: [URL]

        func cleanup() {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// An editor with `count` photos in a folder, each with an edit of its own Exposure (0.1, 0.2…), and an engine
    /// for the batch.
    private func fixture(_ count: Int = 3) throws -> Fixture {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var photos: [URL] = []
        for number in 1 ... count {
            let photo = folder.appending(path: String(format: "IMG_%04d.ARW", number))
            try Data("raw".utf8).write(to: photo)
            var recipe = EditRecipe()
            recipe[.exposure] = Double(number) / 10
            try SidecarStore().save(Sidecar(recipe: recipe), for: photo)
            photos.append(photo)
        }
        let model = EditorModel(engine: StubEngine())
        let worker = StubEngine()
        model.makeWorkerEngine = { worker }
        return Fixture(model: model, worker: worker, folder: folder, photos: photos)
    }

    private func targets(
        _ fixture: Fixture,
        settings: ExportSettings = ExportSettings(),
    ) throws -> [ExportNames.Target] {
        try ExportNames(
            fixture.photos.map { ExportNames.Photo(url: $0) },
            settings: settings,
            reading: UnreadableFiles(),
        )
        .targets
    }

    /// Runs `targets` and returns the report once the batch is done.
    private func export(
        _ fixture: Fixture, _ targets: [ExportNames.Target], open: (url: URL, recipe: EditRecipe)? = nil,
        while running: () async throws -> Void = {},
    ) async throws -> BatchExport.Report {
        var report: BatchExport.Report?
        var settings = ExportSettings()
        settings.revealInFinder = false
        fixture.model.batchExport.run(BatchExport.Job(targets: targets, settings: settings, open: open) { report = $0 })
        try await running()
        let deadline = ContinuousClock.now + .seconds(30)
        while report == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return try #require(report)
    }

    @Test func `every photo exports with its own edit, one at a time, each let go before the next opens`() async throws {
        let fixture = try fixture()
        defer { fixture.cleanup() }
        let targets = try targets(fixture)
        let report = try await export(fixture, targets)

        #expect(report.written == targets.map(\.url))
        #expect(report.failures.isEmpty)
        #expect(targets.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        #expect(targets.map(\.url.lastPathComponent) == [
            "IMG_0001-redlamp.jpg",
            "IMG_0002-redlamp.jpg",
            "IMG_0003-redlamp.jpg",
        ])
        #expect(fixture.worker.opened.withLock { $0 } == fixture.photos)
        #expect(fixture.worker.stills.map { $0.recipe[.exposure] } == [0.1, 0.2, 0.3])
        #expect(fixture.worker.stills.allSatisfy { $0.purpose == .export })
        #expect(fixture.worker.releases.withLock { $0 } == 3)
        #expect(fixture.model.batchExport.progress == nil)
        #expect(fixture.model.batchExport.summary == "Exported 3 photos")
    }

    @Test func `each photo is built at its own edit's raw revision before it opens`() async throws {
        let fixture = try fixture(2)
        defer { fixture.cleanup() }
        var older = EditRecipe()
        older.processVersion = 14
        try SidecarStore().save(Sidecar(recipe: older), for: fixture.photos[0])
        let report = try await export(fixture, targets(fixture))
        #expect(report.written.count == 2)
        let expected = fixture.worker.expected.withLock { $0 }
        #expect(expected.map(\.url) == fixture.photos)
        #expect(expected.map(\.revision) == [.first, .current])
    }

    @Test func `the open photo exports as it was on screen when Export was clicked, not as it's changed after`(
    ) async throws {
        let fixture = try fixture(2)
        defer { fixture.cleanup() }
        var onScreen = EditRecipe()
        onScreen[.exposure] = 0.7
        let report = try await export(fixture, targets(fixture), open: (fixture.photos[0], onScreen)) {
            onScreen[.exposure] = 1.5
        }
        #expect(report.written.count == 2)
        #expect(fixture.worker.stills.map { $0.recipe[.exposure] } == [0.7, 0.2])
    }

    @Test func `a photo of the batch opens only once its edit is taken, so an edit made then isn't in its file`(
    ) async throws {
        let fixture = try fixture(2)
        defer { fixture.cleanup() }
        let gate = Gate()
        gate.hold()
        fixture.model.batchExport.saved = { _ in await gate.pass() }
        let report = try await export(fixture, targets(fixture)) {
            fixture.model.select(fixture.photos[1])
            try await Task.sleep(for: .milliseconds(200))
            #expect(fixture.model.info == nil, "it opened before the batch took its edit")
            gate.release()
            for _ in 0 ..< 400 where fixture.model.info == nil {
                try await Task.sleep(for: .milliseconds(5))
            }
            fixture.model.beginEdit(.exposure)
            fixture.model.setSliderValue(.exposure, 2)
            fixture.model.endEdit()
            fixture.model.saveNow()
        }
        #expect(report.written.count == 2)
        #expect(fixture.worker.stills.map { $0.recipe[.exposure] } == [0.1, 0.2])
    }

    @Test func `Cancel finishes the photo under way, keeps what's written and leaves the rest`() async throws {
        let fixture = try fixture()
        defer { fixture.cleanup() }
        let targets = try targets(fixture)
        let gate = Gate()
        gate.hold()
        fixture.model.batchExport.beforeExporting = { url in
            if url == fixture.photos[1] {
                await gate.pass()
            }
        }
        let report = try await export(fixture, targets) {
            for _ in 0 ..< 400 where gate.arrived == 0 {
                try await Task.sleep(for: .milliseconds(5))
            }
            fixture.model.batchExport.cancel()
            gate.release()
        }
        #expect(report.written == Array(targets.prefix(2).map(\.url)))
        #expect(report.cancelled == 1)
        #expect(!FileManager.default.fileExists(atPath: targets[2].url.path))
        #expect(fixture.model.batchExport.summary == "Export cancelled: 2 of 3 photos exported")
    }

    @Test func `a photo that fails is named with why, and the rest go on`() async throws {
        let fixture = try fixture()
        defer { fixture.cleanup() }
        let targets = try targets(fixture)
        try FileManager.default.removeItem(at: fixture.photos[1])
        let report = try await export(fixture, targets)
        #expect(report.written == [targets[0].url, targets[2].url])
        #expect(report.failures.map(\.photo) == [fixture.photos[1]])
        #expect(report.failures.first?.reason.contains("isn't there any more") == true)
        #expect(fixture.model.batchExport.summary == "Exported 2 of 3 photos")
        #expect(ExportActions.failureList(report.failures).hasPrefix("IMG_0002.ARW: It isn't there any more"))
    }

    @Test func `photos to skip aren't opened, and a file that doesn't open fails alone`() async throws {
        let fixture = try fixture()
        defer { fixture.cleanup() }
        var targets = try targets(fixture)
        targets[0].existing = .skipped
        fixture.worker.openError = EngineError.noImageOpen
        let report = try await export(fixture, targets)
        #expect(report.skipped == 1)
        #expect(report.failures.count == 2)
        #expect(fixture.worker.opened.withLock { $0 } == Array(fixture.photos.dropFirst()))
    }
}
