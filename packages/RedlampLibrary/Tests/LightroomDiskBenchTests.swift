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

    /// Hours at 100,000 photos for `seconds` at `photos`.
    static func hours(_ seconds: Double, photos: Int) -> String {
        String(format: "%.2f h", seconds * 100_000 / Double(photos) / 3600)
    }

    /// The volumes the index bench's indexer reads through: one that answers at once, whose order of operations
    /// is the SSD's, and the 2.5-inch disk itself in real time, whose one head makes what waits for it wait; the
    /// last in Low Power Mode until the photos' folders are indexed, the import's root read first.
    static let indexedVolumes = ["external", VolumeProfile.usb25.name, lowPower]
    static let lowPower = VolumeProfile.usb25.name + " in Low Power Mode, read first"

    @Test(.measuresSpeed, arguments: indexedVolumes)
    func `indexing a catalog's folders on a simulated 2.5-inch disk, thumbnails and all`(
        volume: String,
    ) async throws {
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
        // The indexer reads what each thumbnail is made from through the volume, and the decode finds it in memory.
        let made = Atomic(0)
        let image: StoreThumbnailMaker.ImageSource = { _, _, _ in
            made.add(1, ordering: .relaxed)
            let context = CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            )
            return context?.makeImage()
        }
        let name = String(volume.prefix { $0 != " " })
        let profile = try #require(name == "external"
            ? VolumeProfile(name: "external", isInternal: false) : VolumeProfile.named(name))
        let relaxed = Atomic(volume != Self.lowPower)
        let width = CoreCounts.performance
        let maker = StoreThumbnailMaker(store: store, image: image)
        let indexer = LibraryIndexer(
            index: index,
            fileSystem: SimulatedFileSystem(profile: profile),
            scheduler: WorkScheduler(
                widths: WorkScheduler.Widths(onScreen: width, lookAhead: width, background: width),
                canRunBackground: { relaxed.load(ordering: .relaxed) },
            ),
            thumbnails: maker.thumbnails,
        )
        if volume == Self.lowPower {
            indexer.readFirst([photos.url])
        }
        let folders = (count + 199) / 200
        let start = ContinuousClock.now
        var indexed = Duration.zero
        let operations = try await Self.traced(under: photos.url) {
            var done = 0
            for await event in indexer.index([photos.url]) {
                guard case let .folderIndexed(folder) = event, folder.inserted > 0 else { continue }
                done += 1
                if done == folders {
                    indexed = ContinuousClock.now - start
                    relaxed.store(true, ordering: .relaxed)
                }
            }
            let deadline = ContinuousClock.now + .seconds(600)
            while made.load(ordering: .relaxed) < count, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let finished = ContinuousClock.now - start
        #expect(made.load(ordering: .relaxed) == count && indexed > .zero)
        let isThumbnail = { (operation: FileTrace.Operation) in operation.purpose == FileTrace.thumbnail }
        let last = try #require(operations.lastIndex { !isThumbnail($0) })
        let disk = DiskReplay(profile: .usb25)
        let asRun = disk.replay(operations)
        let untilImport = disk.replay(Array(operations[...last]))
        let reads = disk.replay(operations.filter { !isThumbnail($0) })
        let afterwards = disk.replay(operations.filter(isThumbnail))
        let read = previews.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value / 1000) KB" }.joined(separator: ", ")
        let io = indexer.volumes.all.first
        let real = profile.maxInFlight == nil ? "" : "; on the simulated disk itself, the photos' folders indexed in "
            + "\(String(format: "%.1f", indexed.seconds)) s (\(Self.hours(indexed.seconds, photos: count))) and "
            + "thumbnails made by \(String(format: "%.1f", finished.seconds)) s "
            + "(\(Self.hours(finished.seconds, photos: count)))"
        print(
            "LIGHTROOM-DISK-INDEX-BENCH \(count) raws (\(raws.count) files, previews read: \(read)) in folders of 200 "
                + "on a simulated 2.5-inch disk (usb-2.5), read through a volume simulated as \(volume) "
                + "(\(io.map { "\($0.width) readers at the end" } ?? "no readers")): as run, "
                + "\(Self.describe(asRun, photos: count)); until the import could start (the replay up to the "
                + "indexing's last operation), \(String(format: "%.1f", untilImport.duration.seconds)) s, "
                + "\(Self.hours(untilImport.duration.seconds, photos: count)) at 100,000 photos; the indexing's own "
                + "operations, which the import waits for, \(Self.describe(reads, photos: count)); thumbnails "
                + "made afterwards, \(Self.describe(afterwards, photos: count))\(real)",
        )
    }
}
