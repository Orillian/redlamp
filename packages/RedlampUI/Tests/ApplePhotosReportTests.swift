import Foundation
import Testing
@testable import RedlampLibrary
@_spi(Harness) @testable import RedlampUI

/// Report a Bug on a photo kept in Apple Photos (LIB-62), on the simulated library: This photo's disk is Apple Photos
/// with where its original is, while Develop waits for it too, and the report names none of the photo's Photos
/// identifiers, nor the albums and Photos' folders kept.
@MainActor
@Suite(.serialized)
struct ApplePhotosReportTests {
    /// IMG_4312.JPG only in iCloud, in the album Lisbon of the folder Trips, its download's first byte five seconds
    /// away.
    static func library(_ sandbox: SourcesSandbox) throws -> SimulatedPhotosLibrary {
        let folder = sandbox.base.appending(path: "Cloud", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SourcesSandbox.jpeg(number: 1).write(to: folder.appending(path: "IMG_4312.JPG"))
        let manifest: [String: Any] = [
            "format": SimulatedPhotosLibrary.format, "version": 1, "latency": 5000,
            "collections": [
                ["id": "folder-trips", "title": "Trips", "kind": "folder"],
                ["id": "album-lisbon", "title": "Lisbon", "kind": "album", "parent": "folder-trips"],
            ],
            "assets": [[
                "id": "9F983DBA-EC35-42B8-8773-B597CF782EDD/L0/001",
                "cloud": "9F983DBA-EC35-42B8-8773-B597CF782EDD:001:AYx3Lq0b8NnS1oE",
                "created": "2026-10-21T10:00:00Z", "albums": ["album-lisbon"],
                "resources": [[
                    "kind": "photo", "name": "IMG_4312.JPG", "file": "Cloud/IMG_4312.JPG", "inCloud": true,
                    "width": 4032, "height": 3024,
                ]],
            ]],
        ]
        let url = sandbox.base.appending(path: "manifest.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        return try SimulatedPhotosLibrary(manifest: url)
    }

    /// The folder Trips kept in place, read in place of Photos, and Develop on its photo, waiting for its original;
    /// the photo's address and its row.
    static func waiting(_ sandbox: SourcesSandbox, _ photos: SimulatedPhotosLibrary) async throws
        -> (EditorModel, URL, ApplePhotosRow) {
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        ApplePhotosSource.simulate(photos)
        let model = try await sandbox.open(photos: photos)
        let core = try #require(sandbox.service?.core)
        try await ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
            .keep(["folder-trips"])
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually(seconds: 20) { !model.librarySources.isListing && model.items.count == 1 }
        try await sandbox.counts { $0.applePhotos["album-lisbon"] != nil }
        let url = try #require(model.items.first?.url)
        let id = try #require(model.library.photoID(of: url))
        let row = try #require(try await core.index.read { try $0.applePhotosRow(ofPhoto: id) })
        model.showModule(.develop)
        model.select(url)
        try await sandbox.eventually(seconds: 5) {
            if case .downloading? = model.downloads.statuses[url] {
                return true
            }
            return false
        }
        return (model, url, row)
    }

    @Test func `This photo says Apple Photos and where its original is, from downloading to open on this Mac`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try Self.library(sandbox)
        let (model, url, row) = try await Self.waiting(sandbox, photos)
        #expect(model.info == nil, "Develop shows its preview while it downloads")

        var context = FeedbackContext.capture(from: model)
        await context.readApplePhotos(from: model)
        #expect(context.photo?.volume == "Apple Photos, downloading")
        #expect(context.photo?.fileName == "IMG_4312.JPG" && context.photo?.format == "JPG")
        #expect(context.photo?.size == "4032 × 3024 (12.2 MP)", "its size as Photos gives it")
        #expect(context.photo?.camera == nil && context.edit == nil, "nothing read from an original not yet here")
        #expect(context.messages.contains("Downloading from iCloud"))
        #expect(Set(context.identifiers) == Set([row.key, row.local, row.cloud].compactMap(\.self)))
        #expect(context.albums == ["Lisbon"] && context.albumFolders == ["Trips"])

        model.cancelDownload()
        try await sandbox.eventually(seconds: 5) { model.download?.state == .cancelled }
        try await sandbox.eventually(seconds: 5) { model.downloads.statuses.isEmpty }
        let cancelled = FeedbackContext.capture(from: model)
        #expect(cancelled.photo?.volume == "Apple Photos, in iCloud only")
        #expect(cancelled.messages.contains("Not downloaded: this photo's original is only in iCloud"))

        photos.network = SimulatedPhotosLibrary.Network()
        model.downloadAgain()
        try await sandbox.eventually(seconds: 10) { model.info?.url == url }
        let open = FeedbackContext.capture(from: model)
        #expect(open.photo?.volume == "Apple Photos, on this Mac")
        #expect(open.photo?.format.hasPrefix("JPG (") == true, "read from the original once it's open")
        #expect(open.identifiers == [row.key], "the rest read from the index as the report is made")
    }

    @Test func `the report names none of the photo's Photos identifiers, nor the albums and Photos' folders kept`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try Self.library(sandbox)
        let (model, url, row) = try await Self.waiting(sandbox, photos)
        var context = FeedbackContext.capture(from: model)
        await context.readApplePhotos(from: model)
        let alias = try #require(context.photo?.alias)
        let sidecar = model.library.sidecars.locator.url(for: url)

        let log = [
            "10:02:11 error library: Photos no longer has \(row.local) (\(row.cloud ?? ""))",
            "10:02:12 error library: Couldn’t read “\(url.path)” or “\(sidecar.path)”",
            "10:02:13 notice library: Removed “Lisbon” from the library, and “Trips”",
        ]
        var report = FeedbackReport()
        report.kind = .bug
        report.body = "It stays on Downloading from iCloud."
        let body = report.issueBody(context: context, system: FeedbackReportTests.system, log: log)
        let data = try #require(try report.diagnostics(context: context, system: FeedbackReportTests.system, log: log))
        let diagnostics = String(decoding: data, as: UTF8.self)
        for text in [body, diagnostics] {
            for named in [row.local, row.key, "9F983DBA", "Lisbon", "Trips", "IMG_4312", "Apple Photos/System"] {
                #expect(!text.contains(named), "\(named)")
            }
        }
        #expect(body.contains("| Disk | Apple Photos, downloading |"))
        #expect(body.contains("Photos no longer has … (…)"))
        #expect(body.contains("Couldn’t read “…/\(alias)” or “…/\(alias).redlamp”"))
        #expect(body.contains("Removed “an album” from the library, and “a folder”"))
    }
}
