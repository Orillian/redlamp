import Foundation
import RedlampDocument
import Synchronization
import Testing
@testable import RedlampLibrary

/// The indexer's thumbnails: read through the photo's volume below every read of the indexer's, then made
/// with the volume's place given back (LIB-53).
struct IndexerThumbnailTests {
    /// A volume whose first read waits until it's opened, recording the files read in the order they were.
    final class HeldFileSystem: LibraryFileSystem {
        private let gate = DispatchSemaphore(value: 0)
        private let state = Mutex<(open: Bool, reads: [String])>((false, []))

        var reads: [String] {
            state.withLock { $0.reads }
        }

        func open() {
            state.withLock { $0.open = true }
            gate.signal()
        }

        func contentsOfDirectory(at _: URL) throws -> [FileEntry] {
            []
        }

        func attributes(of url: URL) throws -> FileEntry {
            FileEntry(name: url.lastPathComponent)
        }

        func read(_ url: URL, range: Range<Int>) throws -> Data {
            let held = state.withLock { state -> Bool in
                state.reads.append(url.lastPathComponent)
                return !state.open
            }
            if held {
                gate.wait()
            }
            return Data(count: range.count)
        }

        func volume(of _: URL) throws -> VolumeInfo {
            VolumeInfo(uuid: "HELD", name: nil, isLocal: true, isInternal: false)
        }
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func `a thumbnail is read once the indexer's reads waiting on its volume are done, and only when needed`(
    ) async throws {
        let fileSystem = HeldFileSystem()
        let root = URL(fileURLWithPath: "/Volumes/Held", isDirectory: true)
        let io = try VolumeIO(volume: fileSystem.volume(of: root), fileSystem: fileSystem, probe: root, maximumWidth: 1)
        let made = Mutex<[String]>([])
        let queue = LibraryIndexer.ThumbnailQueue(
            thumbnails: LibraryIndexer.Thumbnails(isNeeded: { photo, _ in photo.lastPathComponent != "HAD.ARW" }) {
                photo, _, _ in made.withLock { $0.append(photo.lastPathComponent) }
            },
            scheduler: WorkScheduler(widths: .init(onScreen: 2, lookAhead: 2, background: 2), canRunBackground: {
                true
            }),
        )
        let first = Task { try await io.read(root.appending(path: "FIRST.ARW"), range: 0 ..< 16) }
        try await Self.waitUntil { fileSystem.reads.count == 1 }
        let names = (1 ... 4).map { "IMG_\($0).ARW" }
        let reads = names.map { name in Task { try await io.read(root.appending(path: name), range: 0 ..< 16) } }
        queue.add(["HAD.ARW", "THUMB.ARW"].map { name in
            LibraryIndexer.Thumbnail(
                url: root.appending(path: name), key: ContentKey(fileSize: 1_000_000, head: Data(name.utf8)),
                size: 1_000_000, file: nil, io: io,
            )
        })
        try await Self.waitUntil { io.waiting == names.count + 1 }
        #expect(io.waiting == names.count + 1)
        fileSystem.open()
        _ = try await first.value
        for read in reads {
            _ = try await read.value
        }
        try await Self.waitUntil { !made.withLock { $0 }.isEmpty }
        #expect(made.withLock { $0 } == ["THUMB.ARW"])
        let order = fileSystem.reads
        #expect(order.first == "FIRST.ARW" && Set(order.dropFirst().prefix(names.count)) == Set(names), "\(order)")
        // Its head, then the rest of a file that holds no preview, read whole.
        #expect(Array(order.dropFirst(names.count + 1)) == ["THUMB.ARW", "THUMB.ARW"], "\(order)")
    }

    /// Records each read's file and range.
    final class RangeRecordingFileSystem: LibraryFileSystem {
        let base = LocalFileSystem()
        private let recorded = Mutex<[(path: String, range: Range<Int>)]>([])

        var reads: [(path: String, range: Range<Int>)] {
            recorded.withLock { $0 }
        }

        func contentsOfDirectory(at url: URL) throws -> [FileEntry] {
            try base.contentsOfDirectory(at: url)
        }

        func attributes(of url: URL) throws -> FileEntry {
            try base.attributes(of: url)
        }

        func read(_ url: URL, range: Range<Int>) throws -> Data {
            recorded.withLock { $0.append((url.path, range)) }
            return try base.read(url, range: range)
        }

        func volume(of url: URL) throws -> VolumeInfo {
            try base.volume(of: url)
        }
    }

    @Test(.enabled(if: !FixtureTests.sources.isEmpty))
    func `a raw's thumbnail is read through the indexer's volume, its head and its preview, and stored`(
    ) async throws {
        let sandbox = try await IndexerSandbox.make(.init(photos: 40, seed: 32), raws: true)
        defer { sandbox.remove() }
        let folder = try TemporaryFolder()
        let store = PhotoStore(root: folder.url)
        defer { store.close() }
        let made = StoreTestCalls()
        let maker = StoreThumbnailMaker(store: store)
        let thumbnails = LibraryIndexer.Thumbnails(isNeeded: maker.needs) { photo, key, file in
            maker.make(photo, key: key, head: file)
            made.count.add(1, ordering: .relaxed)
        }
        let recording = RangeRecordingFileSystem()
        let indexer = LibraryIndexer(
            index: sandbox.index, fileSystem: recording,
            scheduler: WorkScheduler(widths: .init(onScreen: 4, lookAhead: 2, background: 4), canRunBackground: {
                true
            }),
            configuration: .testing(), thumbnails: thumbnails,
        )
        let run = await IndexerRun.collect(indexer.index([sandbox.root]))
        let photos = (0 ..< sandbox.manifest.totals.photos).map(sandbox.fixture.photo(at:))
        #expect(run.failures.isEmpty && run.summary?.photosInserted == photos.count)
        try await Self.waitUntil { made.count.load(ordering: .relaxed) >= photos.count }
        #expect(made.count.load(ordering: .relaxed) == photos.count)

        let reads = Dictionary(grouping: recording.reads, by: \.path)
        let rows = try await LibraryIndexerTests.rows(sandbox)
        let raws = photos.filter { $0.kind == .raw }
        #expect(!raws.isEmpty)
        for photo in raws {
            let url = sandbox.url(photo)
            let heads = reads[url.path, default: []].filter { $0.range == 0 ..< PhotoMetadataReader.headLength }
            #expect(heads.count == 2, "\(photo.path): \(reads[url.path, default: []].map(\.range))")
            // As ImageIO makes it from the file itself, which can't read every camera's raws.
            let key = try #require(rows[sandbox.path(photo.path)]?.contentKey.flatMap(ContentKey.init(data:)))
            let image = store.data(for: key, tier: .grid).flatMap(StoreImageEncoder.decode)
            let reference = StoreThumbnailMaker.imageIO(url, nil, PhotoStore.Tier.grid.pixelSize)
            let sizes = [image, reference].map { $0.map { "\($0.width)×\($0.height)" } ?? "none" }
            #expect(image?.width == reference?.width && image?.height == reference?.height, "\(url): \(sizes)")
        }
    }
}
