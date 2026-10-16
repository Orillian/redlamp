import CoreGraphics
import Foundation
import RedlampDocument
import RedlampEngineAPI
import Synchronization
import Testing
@testable import RedlampLibrary

/// The Lightroom import's writes on a simulated 2.5-inch USB disk (LIB-53): the file operations a bench import
/// makes on the photos' disk, traced and replayed through `DiskReplay`, per photo and projected to 100,000 photos.
/// `REDLAMP_LIGHTROOM_DISK_PHOTOS` sets how many photos (2,000 by default). Serialised, since `FileTrace` follows
/// one trace at a time.
@Suite(.serialized)
struct LightroomDiskBenchTests {
    /// The operations `body` makes under `root`.
    static func traced(under root: URL, _ body: () async throws -> Void) async throws -> [FileTrace.Operation] {
        let roots = [root.path, LibraryIndexer.path(root), root.resolvingSymlinksInPath().path]
        FileTrace.start()
        do {
            try await body()
        } catch {
            FileTrace.stop()
            throw error
        }
        return FileTrace.stop().filter { operation in roots.contains { operation.path.hasPrefix($0 + "/") } }
    }

    /// The same operations, each photo's kept together and in order, the photos taken one folder at a time.
    static func folderByFolder(_ operations: [FileTrace.Operation]) -> [FileTrace.Operation] {
        let folders = operations.map { DiskReplay.folder(of: $0) }
        var first: [String: Int] = [:]
        for (place, folder) in folders.enumerated() where first[folder] == nil {
            first[folder] = place
        }
        return operations.indices.sorted { first[folders[$0]]! != first[folders[$1]]!
            ? first[folders[$0]]! < first[folders[$1]]! : $0 < $1
        }.map { operations[$0] }
    }

    static func describe(_ report: DiskReplay.Report, photos: Int) -> String {
        let kinds = report.operations.sorted { $0.key < $1.key }
            .map { "\($0.key.rawValue) \(String(format: "%.1f", Double($0.value) / Double(photos)))" }
            .joined(separator: ", ")
        let projected = report.duration.seconds * 100_000 / Double(photos)
        return "\(String(format: "%.1f", Double(report.total) / Double(photos))) operations a photo (\(kinds)), "
            + "\(String(format: "%.1f", Double(report.reachedDisk) / Double(photos))) reaching the disk, "
            + "\(report.folderMoves) moves between folders; \(String(format: "%.1f", report.duration.seconds)) s, "
            + "\(String(format: "%.1f", projected / 3600)) h at 100,000 photos"
    }

    @Test func `a trace follows only while it's on`() {
        FileTrace.note(.stat, path: "/before")
        FileTrace.start()
        FileTrace.note(.read, path: "/during", bytes: 3)
        let followed = FileTrace.stop()
        FileTrace.note(.stat, path: "/after")
        #expect(followed.contains(FileTrace.Operation(kind: .read, path: "/during", bytes: 3)))
        #expect(!followed.contains { $0.path == "/before" || $0.path == "/after" })
    }

    @Test(.measuresSpeed)
    func `the import's writes on a simulated 2.5-inch disk, operation by operation`() async throws {
        let count = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_DISK_PHOTOS"].flatMap { Int($0) } ?? 2000
        let library = try await LightroomBenchTests.library(photos: count, perFolder: 200)
        defer { library.index.closeAndWait() }
        let catalog = try LightroomCatalog.read(library.catalog)
        let plan = try await LightroomPlan.make(catalog, index: library.index, paths: library.paths)
        let importer = LightroomImport(index: library.index, paths: library.paths)
        var outcome: LightroomImport.Outcome?
        let operations = try await Self.traced(under: library.photos.url) {
            outcome = try await importer.run(plan)
        }
        #expect(outcome?.record.photos == count && outcome?.skipped.isEmpty == true)
        let disk = DiskReplay(profile: .usb25)
        let asRun = disk.replay(operations)
        let ordered = disk.replay(Self.folderByFolder(operations))
        #expect(asRun.operations[.create, default: 0] >= count)
        #expect(ordered.duration <= asRun.duration)
        print("LIGHTROOM-DISK-BENCH \(count) photos in folders of 200 on a simulated 2.5-inch disk (usb-2.5): "
            + "as run, \(Self.describe(asRun, photos: count)); one folder at a time, "
            + "\(Self.describe(ordered, photos: count))")
    }

    /// The size of the embedded preview the app's thumbnail reads of `raw`: the smallest reaching 384 pixels.
    static func previewLength(of raw: URL) async throws -> Int {
        let data = try Data(contentsOf: raw)
        var bytes = PreviewBytes(head: data, size: data.count) { range in data.subdata(in: range) }
        return try await EmbeddedPreviews.best(in: &bytes, reaching: 384)?.length ?? data.count
    }

    /// `operations` without one of each of `taken`.
    static func removing(
        _ taken: [FileTrace.Operation],
        from operations: [FileTrace.Operation],
    ) -> [FileTrace.Operation] {
        var left = Dictionary(taken.map { ($0, 1) }, uniquingKeysWith: +)
        return operations.filter { operation in
            guard let count = left[operation], count > 0 else { return true }
            left[operation] = count - 1
            return false
        }
    }

    @Test(.measuresSpeed)
    func `indexing a catalog's folders on a simulated 2.5-inch disk, thumbnails and all`() async throws {
        let count = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_DISK_INDEXED"].flatMap { Int($0) } ?? 600
        let raws = try FileManager.default.contentsOfDirectory(
            at: FixtureTests.rawFolder,
            includingPropertiesForKeys: nil,
        )
        .filter { ["arw", "cr3", "dng", "nef", "raf"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!raws.isEmpty, "the CC0 raws in tests/fixtures/raw")
        var previews: [String: Int] = [:]
        for raw in raws {
            previews[raw.pathExtension.uppercased()] = try await Self.previewLength(of: raw)
        }
        let photos = try TemporaryFolder()
        let library = try TemporaryFolder()
        for number in 0 ..< count {
            let raw = raws[number % raws.count]
            let folder = photos.url.appending(path: String(format: "Shoot %03d", number / 200))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: String(format: "IMG_%06d.", number) + raw.pathExtension.uppercased())
            if clonefile(raw.path, file.path, 0) != 0 {
                try FileManager.default.copyItem(at: raw, to: file)
            }
            // A size of its own, so its content key, and its thumbnail, are its own: after the end, where
            // decoders don't look.
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(String(number).utf8))
            try handle.close()
        }
        let index = try await LibraryIndex.open(at: library.url.appending(path: "Index.sqlite"))
        defer { index.closeAndWait() }
        let store = PhotoStore(root: library.url.appending(path: "Store"))
        defer { store.close() }
        let thumbnails = Mutex<[FileTrace.Operation]>([])
        let sizes = previews
        let image: StoreThumbnailMaker.ImageSource = { photo, _, _ in
            let read = FileTrace.Operation(kind: .read, path: photo.path, bytes: sizes[photo.pathExtension] ?? 0)
            FileTrace.note(read.kind, path: read.path, bytes: read.bytes)
            thumbnails.withLock { $0.append(read) }
            let context = CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            )
            return context?.makeImage()
        }
        let width = CoreCounts.performance
        let indexer = LibraryIndexer(
            index: index,
            fileSystem: SimulatedFileSystem(profile: VolumeProfile(name: "external", isInternal: false)),
            scheduler: WorkScheduler(
                widths: WorkScheduler.Widths(onScreen: width, lookAhead: width, background: width),
                canRunBackground: { true },
            ),
            thumbnails: StoreThumbnailMaker(store: store, image: image).thumbnails,
        )
        let operations = try await Self.traced(under: photos.url) {
            for await _ in indexer.index([photos.url]) {}
            let deadline = ContinuousClock.now + .seconds(60)
            while thumbnails.withLock({ $0.count }) < count, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let made = thumbnails.withLock { $0 }
        #expect(made.count == count)
        let disk = DiskReplay(profile: .usb25)
        let asRun = disk.replay(operations)
        let reads = disk.replay(Self.removing(made, from: operations))
        let afterwards = disk.replay(made)
        let read = previews.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value / 1000) KB" }.joined(separator: ", ")
        print(
            "LIGHTROOM-DISK-INDEX-BENCH \(count) raws (\(raws.count) files, previews read: \(read)) in folders of 200 "
                + "on a simulated 2.5-inch disk (usb-2.5), as an external disk's two readers read them: as run, "
                + "\(Self.describe(asRun, photos: count)); the indexing's own reads, which the import waits for, "
                +
                "\(Self.describe(reads, photos: count)); thumbnails made afterwards, \(Self.describe(afterwards, photos: count))",
        )
    }
}
