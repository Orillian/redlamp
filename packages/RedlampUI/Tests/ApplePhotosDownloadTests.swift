import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary
@_spi(Harness) @testable import RedlampUI

/// Originals of photos kept in Apple Photos downloaded from iCloud as the app needs them (LIB-60), on the simulated
/// library's iCloud: Develop's preview at once with the download's progress, then the photo opened; Cancel leaving it
/// on
/// its preview with Download Again; iCloud out of reach said with Try Again; export downloading its photos first and
/// naming those it couldn't get; and Download Originals on a selection.
@MainActor
@Suite(.serialized)
struct ApplePhotosDownloadTests {
    /// `count` small JPEGs as photos only in iCloud, in one album, with iCloud's `network`, and `failing` failing
    /// partway.
    static func cloud(
        _ sandbox: SourcesSandbox, count: Int, network: [String: Any], failing: Set<Int> = [],
    ) throws -> SimulatedPhotosLibrary {
        let folder = sandbox.base.appending(path: "Cloud", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var assets: [[String: Any]] = []
        for number in 1 ... count {
            let name = String(format: "IMG_%04d.JPG", number)
            try SourcesSandbox.jpeg(number: number).write(to: folder.appending(path: name))
            var resource: [String: Any] = ["kind": "photo", "name": name, "file": "Cloud/\(name)", "inCloud": true]
            if failing.contains(number) {
                resource["failAfter"] = 10
            }
            assets.append([
                "id": "asset-\(number)", "created": "2026-10-2\(number % 10)T10:00:00Z", "albums": ["album-a"],
                "resources": [resource],
            ])
        }
        var manifest: [String: Any] = [
            "format": SimulatedPhotosLibrary.format, "version": 1,
            "collections": [["id": "album-a", "title": "A", "kind": "album"]], "assets": assets,
        ]
        manifest.merge(network) { $1 }
        let url = sandbox.base.appending(path: "manifest.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        return try SimulatedPhotosLibrary(manifest: url)
    }

    /// `photos`' album kept in place in the sandbox's library, read in place of Photos, with All Photographs shown;
    /// its rows' URLs in their names' order.
    static func open(
        _ sandbox: SourcesSandbox, _ photos: SimulatedPhotosLibrary, rows: Int,
    ) async throws -> (EditorModel, [URL]) {
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        ApplePhotosSource.simulate(photos)
        let model = try await sandbox.open(photos: photos)
        let core = try #require(sandbox.service?.core)
        try await ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
            .keep(["album-a"])
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually(seconds: 20) { !model.librarySources.isListing && model.items.count == rows }
        try #require(model.items.count == rows, "All Photographs shows the photos kept in place")
        let urls = try await core.index.read { reader in
            try reader.database.prepare("""
            SELECT f.path, p.name FROM photos p JOIN folders f ON f.id = p.folder JOIN photo_assets a ON a.photo = p.id
              ORDER BY p.name
            """).map { URL(fileURLWithPath: ($0.string(at: 0) ?? "") + "/" + ($0.string(at: 1) ?? "")) }
        }
        return (model, urls)
    }

    @Test func `Develop on a photo not downloaded shows its preview at once with the download, then opens it`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try Self.cloud(sandbox, count: 2, network: ["latency": 400, "rate": 20000])
        let (model, urls) = try await Self.open(sandbox, photos, rows: 2)
        let url = urls[0]
        #expect(model.library.needsDownload(url))
        model.showModule(.develop)

        let asked = ContinuousClock.now
        model.select(url)
        let shown = ContinuousClock.now - asked
        #expect(model.download?.url == url && model.download?.isDownloading == true)
        #expect(model.download?.text == "Downloading from iCloud")
        #expect(model.info == nil, "its sliders are off until it opens")
        #expect(shown < .milliseconds(100), "the download shows at once: \(shown)")
        try await sandbox.eventually(seconds: 5) { model.selectionThumbnail != nil }
        let preview = ContinuousClock.now - asked
        #expect(preview < .milliseconds(400), "its preview shows before the original's first byte: \(preview)")
        print("LIB-60 budget: Develop showed the download \(shown) after the photo was chosen, its preview \(preview)")

        try await sandbox.eventually(seconds: 10) { model.info?.url == url }
        #expect(model.download == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!model.library.needsDownload(url))
        // The next photo in the filmstrip downloads ahead, on a network that isn't expensive.
        try await sandbox.eventually(seconds: 10) { FileManager.default.fileExists(atPath: urls[1].path) }
    }

    @Test func `Cancel leaves Develop on the preview with Download Again, and offline is said with Try Again`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try Self.cloud(sandbox, count: 1, network: ["latency": 5000])
        let (model, urls) = try await Self.open(sandbox, photos, rows: 1)
        let url = urls[0]
        model.showModule(.develop)
        model.select(url)
        try await sandbox.eventually(seconds: 5) {
            if case .downloading? = model.downloads.statuses[url] {
                return true
            }
            return false
        }
        #expect(model.downloads.statuses.count == 1, "the filmstrip counts it")

        model.cancelDownload()
        try await sandbox.eventually(seconds: 5) { model.download?.state == .cancelled }
        #expect(model.download?.text == "Not downloaded: this photo's original is only in iCloud")
        #expect(model.info == nil)
        try await sandbox.eventually(seconds: 5) { model.downloads.statuses.isEmpty }
        #expect(!FileManager.default.fileExists(atPath: url.path))

        photos.network = SimulatedPhotosLibrary.Network(offline: true)
        model.downloadAgain()
        try await sandbox.eventually(seconds: 5) { model.download?.state == .failed(.offline) }
        #expect(model.download?.text == "iCloud can't be reached: this photo's original isn't on this Mac")
        #expect(model.info == nil)

        photos.network = SimulatedPhotosLibrary.Network()
        model.downloadAgain()
        try await sandbox.eventually(seconds: 10) { model.info?.url == url }
        #expect(model.download == nil)
    }

    @Test func `export downloads its photos' originals first, a few ahead, and names those it couldn't get`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try Self.cloud(sandbox, count: 4, network: ["latency": 100], failing: [3])
        let (model, urls) = try await Self.open(sandbox, photos, rows: 4)
        model.makeWorkerEngine = { StubEngine() }
        let destination = sandbox.base.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var settings = ExportSettings()
        settings.revealInFinder = false
        settings.destinationFolder = destination
        let targets = try ExportNames(
            urls.map { ExportNames.Photo(url: $0) },
            settings: settings,
            reading: UnreadableFiles(),
        )
        .targets
        var report: BatchExport.Report?
        var counted: [BatchExport.Progress] = []
        model.batchExport.run(BatchExport.Job(targets: targets, settings: settings) { report = $0 })
        try await sandbox.eventually(seconds: 30) {
            if let downloads = model.batchExport.downloads, counted.last != downloads {
                counted.append(downloads)
            }
            return report != nil
        }
        let done = try #require(report)
        #expect(done.written.count == 3)
        #expect(done.failures.map(\.photo) == [urls[2]])
        #expect(done.failures.first?.reason.contains("stopped after 10 bytes") == true, "\(done.failures)")
        #expect(counted.first == BatchExport.Progress(done: 0, total: 4))
        #expect(model.batchExport.downloads == nil)
        #expect(urls.enumerated()
            .allSatisfy { $0.offset == 2 || FileManager.default.fileExists(atPath: $0.element.path) })

        // Beside the photo is Redlamp's cache: refused, with nothing downloaded for it.
        try FileManager.default.removeItem(at: urls[3])
        settings.destinationFolder = nil
        let beside = try ExportNames([ExportNames.Photo(url: urls[3])], settings: settings, reading: UnreadableFiles())
            .targets
        report = nil
        model.batchExport.run(BatchExport.Job(targets: beside, settings: settings) { report = $0 })
        try await sandbox.eventually(seconds: 30) { report != nil }
        #expect(report?.failures.first?.reason.hasPrefix("It's kept in Apple Photos") == true)
        #expect(!FileManager.default.fileExists(atPath: urls[3].path))
    }

    @Test func `Download Originals downloads the photos selected, the filmstrip counting them with Cancel All`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try Self.cloud(sandbox, count: 3, network: ["latency": 300])
        let (model, urls) = try await Self.open(sandbox, photos, rows: 3)
        model.select(urls[0])
        model.selectAllPhotos()
        try await sandbox.eventually(seconds: 5) { model.canPerform(.downloadOriginals) }
        #expect(model.perform(.downloadOriginals))
        try await sandbox.eventually(seconds: 5) { model.downloads.statuses.count == 3 }
        try await sandbox
            .eventually(seconds: 10) { urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }
        try await sandbox.eventually(seconds: 5) { model.downloads.statuses.isEmpty }
        #expect(!model.canPerform(.downloadOriginals), "nothing left to download")
    }
}
