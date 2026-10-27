import CoreGraphics
import Foundation
import Synchronization
import Testing
@testable import RedlampLibrary

/// Staging an import from Apple Photos (LIB-54): each asset's files written into its own folder in the
/// hidden staging folder at the destination, whole files kept so a stopped import takes up where it was, and
/// the card import's planner naming them by `{album}`.
struct ApplePhotosStagingTests {
    /// A library whose writes of the files `holds` names wait until they're cancelled.
    final class HoldingLibrary: ApplePhotosLibrary {
        let base: SimulatedPhotosLibrary
        let holds: Set<String>
        let writes = Mutex<[String]>([])

        init(_ base: SimulatedPhotosLibrary, holding holds: Set<String> = []) {
            self.base = base
            self.holds = holds
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
            try await base.assets(in: ids)
        }

        func write(
            _ resource: ApplePhotosResource, of asset: String, to url: URL,
            progress: @escaping @Sendable (Double) -> Void,
        ) async throws {
            writes.withLock { $0.append(resource.originalFilename) }
            if holds.contains(resource.originalFilename) {
                try Data("partly".utf8).write(to: url)
                try await Task.sleep(for: .seconds(60))
            }
            try await base.write(resource, of: asset, to: url, progress: progress)
        }

        func changes() -> AsyncStream<Void> {
            base.changes()
        }

        func assets(withIDs ids: [String]) async throws -> [ApplePhotosAsset] {
            try await base.assets(withIDs: ids)
        }

        func changeToken() -> Data? {
            base.changeToken()
        }

        func changes(since token: Data) async throws -> ApplePhotosChanges {
            try await base.changes(since: token)
        }

        func image(of asset: String, version: ApplePhotosImageVersion, size: Int) async throws -> CGImage? {
            try await base.image(of: asset, version: version, size: size)
        }
    }

    private static func assets(_ ids: [String]) async throws -> [ApplePhotosAsset] {
        let all = try await SamplePhotos.library().assets(in: ["album-selects", "album-lisbon", "album-porto"])
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private static func listing(_ folder: URL) -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    @Test func `each asset's files go in a folder of its own, a pair under one name and an edit beside its original`(
    ) async throws {
        try #require(SamplePhotos.hasRaws, "the CC0 raws in tests/fixtures/raw")
        let folder = try TemporaryFolder()
        let assets = try await Self.assets([SamplePhotos.pair, SamplePhotos.edited, SamplePhotos.live])
        let stager = try ApplePhotosStager(library: SamplePhotos.library(), destination: folder.url, id: UUID())
        #expect(stager.folder.path.hasPrefix(folder.url.path + "/.Redlamp Photos Import/"))
        let reports = Mutex<[ApplePhotosStager.Progress]>([])
        let outcome = await stager.stage(assets) { progress in reports.withLock { $0.append(progress) } }
        #expect(outcome.failures.isEmpty && !outcome.stopped)
        #expect(outcome.staged.map(\.asset) == [SamplePhotos.pair, SamplePhotos.edited, SamplePhotos.live])
        let pair = try #require(outcome.staged.first)
        #expect(pair.folder.lastPathComponent == "8A1F0004-0000-4000-8000-000000000004-L0-001")
        #expect(Self.listing(pair.folder) == ["IMG_0004.JPG", "IMG_0004.NEF"])
        let edited = outcome.staged[1]
        #expect(Self.listing(edited.folder) == ["IMG_0002 (Photos edit).jpeg", "IMG_0002.JPG"])
        #expect(edited.edit == "IMG_0002 (Photos edit).jpeg" && edited.originals == ["IMG_0002.JPG"])
        #expect(Self.listing(outcome.staged[2].folder) == ["IMG_0003.HEIC"], "a Live Photo's still, not its video")
        let rendering = try Data(contentsOf: edited.folder.appending(path: "IMG_0002 (Photos edit).jpeg"))
        #expect(try rendering == Data(contentsOf: SamplePhotos.folder.appending(path: "files/FullSizeRender.jpeg")))
        let dated = try edited.folder.appending(path: "IMG_0002.JPG")
            .resourceValues(forKeys: [.contentModificationDateKey])
        #expect(dated.contentModificationDate == assets[1].created, "dated as Photos has it")

        let last = try #require(reports.withLock { $0 }.max { $0.done < $1.done })
        #expect(last.done == 3 && last.assets == 3 && last.downloading == 0)
        #expect(last.bytes == last.written && (last.bytes ?? 0) > 40_000_000)
        #expect(reports.withLock { $0 }.contains { $0.downloading == 1 }, "the Live Photo comes from iCloud")
    }

    @Test func `a file staged already is kept, and a stopped import leaves no part of a file`() async throws {
        let folder = try TemporaryFolder()
        let id = UUID()
        let assets = try await Self.assets([SamplePhotos.tram, SamplePhotos.edited])
        let holding = try HoldingLibrary(SamplePhotos.library(), holding: ["FullSizeRender.jpeg"])
        let stager = ApplePhotosStager(library: holding, destination: folder.url, id: id)
        let tram = stager.folder.appending(path: "8A1F0001-0000-4000-8000-000000000001-L0-001/IMG_0001.HEIC")
        let task = Task { await stager.stage(assets) }
        while !holding.writes.withLock({ $0.contains("FullSizeRender.jpeg") })
            || !FileManager.default.fileExists(atPath: tram.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        let stopped = await task.value
        #expect(stopped.stopped && stopped.staged.map(\.asset) == [SamplePhotos.tram])
        let staged = Self.listing(stager.folder)
        #expect(!staged.contains { $0.hasSuffix(".partial") }, "\(staged)")
        #expect(staged.contains("8A1F0002-0000-4000-8000-000000000002-L0-001/IMG_0002.JPG"))

        try Data("kept".utf8).write(to: tram)
        let again = HoldingLibrary(holding.base)
        let resumed = await ApplePhotosStager(library: again, destination: folder.url, id: id).stage(assets)
        #expect(!resumed.stopped && resumed.failures.isEmpty && resumed.staged.count == 2)
        #expect(again.writes.withLock { $0 } == ["FullSizeRender.jpeg"], "only what wasn't whole")
        #expect(try Data(contentsOf: tram) == Data("kept".utf8))

        stager.remove()
        #expect(!FileManager.default.fileExists(atPath: ApplePhotosStager.root(for: folder.url).path))
    }

    @Test func `an asset whose file Photos can't give fails alone`() async throws {
        let folder = try TemporaryFolder()
        var missing = ApplePhotosAsset(id: "gone", created: Date())
        missing.resources = [ApplePhotosResource(kind: .photo, type: "public.jpeg", originalFilename: "GONE.JPG")]
        let assets = try await Self.assets([SamplePhotos.tram]) + [missing]
        let stager = try ApplePhotosStager(library: SamplePhotos.library(), destination: folder.url, id: UUID())
        let outcome = await stager.stage(assets)
        #expect(outcome.staged.map(\.asset) == [SamplePhotos.tram])
        #expect(outcome.failures["gone"]?.contains("GONE.JPG") == true && !outcome.stopped)
    }

    @Test func `the planner names a staged photo's folders by its album, a level left out without one`(
    ) async throws {
        let sandbox = try await ImportSandbox.make()
        defer { sandbox.remove() }
        let assets = try await Self.assets([SamplePhotos.tram, SamplePhotos.burstKey])
        let stager = try ApplePhotosStager(
            library: SamplePhotos.library(),
            destination: sandbox.destination,
            id: UUID(),
        )
        let outcome = await stager.stage(assets)
        let source = try ImportSource.at(stager.folder)
        #expect(source.kind == .folder)
        let session = ImportSession(sources: [source], library: sandbox.library, makesPreviews: false)
        _ = await session.browsed()
        let tram = try #require(session.id(named: "IMG_0001.HEIC"))
        session.album([tram], "Lisbon")
        let plan = try await session.plan(sandbox.settings(folders: "{album}/{date:yyyy}", backup: false))
        #expect(Set(plan.items.map { $0.copies[0].path }) == ["Lisbon/2026/IMG_0001.HEIC", "2026/IMG_0010.JPG"])
        #expect(outcome.staged.count == 2)
    }
}
