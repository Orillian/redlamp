import Foundation
import Synchronization
import Testing
@testable import RedlampLibrary

/// The cache of originals downloaded from iCloud (LIB-60) on the simulated library's iCloud: a download's progress, its
/// partial file and its rename; Cancel leaving nothing; one download for two asking; offline and a failure partway;
/// priorities and the next photo ahead; the budget, the least recently opened taken out first, never one held; Photos'
/// edit downloaded again once edited again; and the camera read from an original when it first arrives.
struct ApplePhotosOriginalsTests {
    /// The network as a test sets it.
    final class Network: ApplePhotosNetwork {
        private let state = Mutex((reachable: true, expensive: false))

        var isReachable: Bool {
            get { state.withLock(\.reachable) }
            set { state.withLock { $0.reachable = newValue } }
        }

        var isExpensive: Bool {
            get { state.withLock(\.expensive) }
            set { state.withLock { $0.expensive = newValue } }
        }
    }

    /// A library of photos only in iCloud, kept in place in a sandbox of its own, and its cache.
    struct Cloud {
        let sandbox: IndexSandbox
        let photos: SimulatedPhotosLibrary
        let cache: ApplePhotosOriginals
        let network: Network
        /// Each photo's row's URL, by its name.
        let urls: [String: URL]

        func remove() {
            sandbox.remove()
        }

        /// The files in `url`'s asset's folder, partial ones included.
        func folder(of url: URL) -> [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path))?.sorted() ?? []
        }
    }

    /// `files` (each name with its bytes, or a file to copy) as photos only in iCloud, in one album kept in place, with
    /// `network` the simulated iCloud's.
    static func cloud(
        _ files: [(name: String, bytes: Int, from: URL?)], network: [String: Any] = ["latency": 0, "rate": 4_000_000],
        failAfter: [String: Int] = [:], edited: Set<String> = [],
    ) async throws -> Cloud {
        let sandbox = try await IndexSandbox.make()
        let source = sandbox.directory.appending(path: "Source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var assets: [[String: Any]] = []
        for (number, file) in files.enumerated() {
            let url = source.appending(path: file.name)
            if let from = file.from {
                try FileManager.default.copyItem(at: from, to: url)
            } else {
                try Data((0 ..< file.bytes).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: url)
            }
            var resources: [[String: Any]] = [[
                "kind": "photo",
                "name": file.name,
                "file": "Source/\(file.name)",
                "inCloud": true,
            ]]
            if let bytes = failAfter[file.name] {
                resources[0]["failAfter"] = bytes
            }
            if edited.contains(file.name) {
                let render = "Render-\(file.name).jpeg"
                try Data(repeating: 7, count: 2048).write(to: source.appending(path: render))
                resources.append([
                    "kind": "fullSizePhoto",
                    "name": "FullSizeRender.jpeg",
                    "file": "Source/\(render)",
                    "inCloud": true,
                ])
            }
            assets.append([
                "id": "CLOUD-\(number)/L0/001", "created": "2026-10-0\(number % 9 + 1)T10:00:00Z",
                "albums": ["album-cloud"],
                "edited": edited.contains(file.name), "adjusted": "2026-10-20T10:00:00Z", "resources": resources,
            ])
        }
        let manifest = try SamplePhotos.manifest(
            in: sandbox.directory, collections: [["id": "album-cloud", "title": "Cloud", "kind": "album"]],
            assets: assets, extra: network,
        )
        let photos = try SimulatedPhotosLibrary(manifest: manifest)
        try await ApplePhotosIndexer(photos: photos, index: sandbox.index).keep(["album-cloud"])
        let urls = try await sandbox.index.read { reader in
            var urls: [String: URL] = [:]
            try reader.database.prepare("""
            SELECT f.path, p.name FROM photos p JOIN folders f ON f.id = p.folder JOIN photo_assets a ON a.photo = p.id
            """).forEachRow { row in
                let name = row.string(at: 1) ?? ""
                urls[name] = URL(fileURLWithPath: (row.string(at: 0) ?? "") + "/" + name, isDirectory: false)
            }
            return urls
        }
        let network = Network()
        let cache = ApplePhotosOriginals(
            index: sandbox.index, paths: LibraryPaths(root: sandbox.directory), photos: { photos }, network: network,
        )
        return Cloud(sandbox: sandbox, photos: photos, cache: cache, network: network, urls: urls)
    }

    static func eventually(within timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// The partial files seen as a download went.
    final class Partials: Sendable {
        let names = Mutex(Set<String>())
    }

    /// The progress `body` hears, in order.
    final class Heard: Sendable {
        private let heard = Mutex<[ApplePhotosOriginals.Progress]>([])

        var all: [ApplePhotosOriginals.Progress] {
            heard.withLock { $0 }
        }

        func hear(_ progress: ApplePhotosOriginals.Progress) {
            heard.withLock { $0.append(progress) }
        }
    }

    @Test func `an original downloads with its progress through a partial file to its row's address`() async throws {
        let cloud = try await Self.cloud([("IMG_0001.JPG", 400_000, nil)])
        defer { cloud.remove() }
        let url = try #require(cloud.urls["IMG_0001.JPG"])
        #expect(cloud.cache.owns(url))
        #expect(!cloud.cache.isLocal(url))
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let heard = Heard()
        let partials = Partials()
        let folder = url.deletingLastPathComponent().path
        let local = try await cloud.cache.local(url) { progress in
            heard.hear(progress)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            partials.names.withLock { $0.formUnion(names.filter { $0.hasSuffix(".download") }) }
        }
        #expect(local == url)
        #expect(try Data(contentsOf: url).count == 400_000)
        #expect(cloud.cache.isLocal(url))
        #expect(cloud.folder(of: url) == ["IMG_0001.JPG"], "the partial file was renamed")
        #expect(partials.names.withLock { $0.count } == 1, "it was written to a partial file beside it")
        let fractions = heard.all.map(\.fraction)
        #expect(fractions.count >= 2 && fractions == fractions.sorted() && fractions.last == 1)
        #expect(heard.all.last?.received == 400_000 && heard.all.last?.total == 400_000)
        #expect(await cloud.cache.usage().files == 1)

        // A second asking finds it in the cache, with nothing downloaded.
        let again = Heard()
        _ = try await cloud.cache.local(url) { again.hear($0) }
        #expect(again.all.isEmpty)
    }

    @Test func `the camera, lens and exposure are read into the row when the original first arrives`() async throws {
        let raw = FixtureTests.rawFolder.appending(path: "PXL_20201121_100251397.dng")
        guard FileManager.default.fileExists(atPath: raw.path) else { return }
        let cloud = try await Self.cloud([("PXL_0001.DNG", 0, raw)], network: [:])
        defer { cloud.remove() }
        let url = try #require(cloud.urls["PXL_0001.DNG"])
        let before = try await cloud.sandbox.index.read { reader in
            try reader.database.prepare("SELECT camera, iso FROM photos WHERE name = 'PXL_0001.DNG'")
                .first { ($0.optionalInt64(at: 0), $0.isNull(at: 1)) }
        }
        #expect(before?.0 == nil && before?.1 == true, "Photos doesn't give them")
        try await cloud.cache.local(url)
        let after = try await cloud.sandbox.index.read { reader in
            try reader.database.prepare("""
            SELECT c.name, p.iso FROM photos p JOIN cameras c ON c.id = p.camera WHERE p.name = 'PXL_0001.DNG'
            """).first { ($0.string(at: 0), $0.double(at: 1)) }
        }
        #expect(after?.0?.isEmpty == false)
        #expect((after?.1 ?? 0) > 0)
    }

    @Test func `Cancel leaves no partial file, and a download two ask for goes on until neither wants it`(
    ) async throws {
        let cloud = try await Self.cloud(
            [("IMG_0001.JPG", 400_000, nil)], network: ["latency": 100, "rate": 400_000],
        )
        defer { cloud.remove() }
        let url = try #require(cloud.urls["IMG_0001.JPG"])
        let cache = cloud.cache
        let first = Task { try await cache.local(url) }
        let second = Task { try await cache.local(url, priority: .export) }
        #expect(await Self.eventually { cache.status(of: url) != nil })
        #expect(cache.downloads.count == 1, "one download for both")

        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(cache.status(of: url) != nil, "the second still wants it")
        #expect(await Self.eventually {
            if case .downloading? = cache.status(of: url) {
                return true
            }
            return false
        })

        cache.cancel([url])
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await Self.eventually { cache.status(of: url) == nil })
        #expect(await Self.eventually { cloud.folder(of: url).isEmpty }, "nothing left behind")
        #expect(!cache.isLocal(url))

        // Download Again.
        try await cache.local(url)
        #expect(cache.isLocal(url))
        #expect(cloud.folder(of: url) == ["IMG_0001.JPG"])
    }

    @Test func `offline fails as offline, leaving nothing, and Try Again downloads once iCloud is back`() async throws {
        let cloud = try await Self.cloud([("IMG_0001.JPG", 200_000, nil)], network: ["offline": true])
        defer { cloud.remove() }
        let url = try #require(cloud.urls["IMG_0001.JPG"])
        let events = cloud.cache.events()
        await #expect(throws: ApplePhotosOriginals.Failure.offline) { try await cloud.cache.local(url) }
        #expect(cloud.folder(of: url).isEmpty)
        var told: [ApplePhotosOriginals.Event] = []
        for await event in events {
            told.append(event)
            if case .failed = event {
                break
            }
        }
        #expect(told.last == .failed(url, .offline))

        cloud.photos.network.offline = false
        try await cloud.cache.local(url)
        #expect(cloud.cache.isLocal(url))
    }

    @Test func `a download that goes offline or fails partway leaves nothing behind`() async throws {
        let cloud = try await Self.cloud(
            [("IMG_0001.JPG", 400_000, nil), ("IMG_0002.JPG", 400_000, nil)], network: ["rate": 800_000],
            failAfter: ["IMG_0002.JPG": 100_000],
        )
        defer { cloud.remove() }
        let (first, second) = try (#require(cloud.urls["IMG_0001.JPG"]), #require(cloud.urls["IMG_0002.JPG"]))
        let photos = cloud.photos
        let going = Task { try await cloud.cache.local(first) }
        #expect(await Self.eventually {
            if case let .downloading(progress)? = cloud.cache.status(of: first) {
                return progress.fraction > 0
            }
            return false
        })
        photos.network.offline = true
        await #expect(throws: ApplePhotosOriginals.Failure.offline) { try await going.value }
        #expect(cloud.folder(of: first).isEmpty)

        photos.network.offline = false
        await #expect(throws: ApplePhotosOriginals.Failure.self) { try await cloud.cache.local(second) }
        #expect(cloud.folder(of: second).isEmpty)
        #expect(!cloud.cache.isLocal(second))
    }

    @Test func `someone waiting starts at once, others wait for room, and the next photo ahead only on a cheap network`(
    ) async throws {
        let names = (1 ... 5).map { "IMG_000\($0).JPG" }
        let cloud = try await Self.cloud(
            names.map { (name: $0, bytes: 400_000, from: URL?.none) }, network: ["latency": 300, "rate": 400_000],
        )
        defer { cloud.remove() }
        let urls = try names.map { try #require(cloud.urls[$0]) }
        let cache = cloud.cache
        cache.request(Array(urls[0 ..< 3]), priority: .request)
        #expect(await Self.eventually { cache.downloads.count == 3 })
        #expect(await Self.eventually { cache.downloads.values.count { $0 != .queued } == 2 }, "two at a time")
        let opened = Task { try await cache.local(urls[3]) }
        #expect(await Self.eventually { cache.status(of: urls[3]).map { $0 != .queued } == true }, "it starts at once")
        #expect(cache.status(of: urls[2]) == .queued)

        cloud.network.isExpensive = true
        cache.request([urls[4]], priority: .ahead)
        try await Task.sleep(for: .milliseconds(100))
        #expect(cache.status(of: urls[4]) == nil, "nothing ahead on an expensive network")
        cloud.network.isExpensive = false
        cache.request([urls[4]], priority: .ahead)
        #expect(await Self.eventually { cache.status(of: urls[4]) != nil })

        cache.cancelAll()
        await #expect(throws: CancellationError.self) { try await opened.value }
        #expect(await Self.eventually { cache.downloads.isEmpty })
        for url in urls {
            #expect(await Self.eventually { cloud.folder(of: url).isEmpty })
        }
    }

    @Test func `the budget takes out the least recently opened first, never one held`() async throws {
        let names = (1 ... 4).map { "IMG_000\($0).JPG" }
        let cloud = try await Self.cloud(names.map { (name: $0, bytes: 100_000, from: URL?.none) })
        defer { cloud.remove() }
        let urls = try names.map { try #require(cloud.urls[$0]) }
        let cache = cloud.cache
        for url in urls[0 ..< 3] {
            try await cache.local(url)
            try await Task.sleep(for: .milliseconds(20))
        }
        let usage = await cache.usage()
        #expect(usage.files == 3 && usage.budget == ApplePhotosOriginals.defaultBudget)
        let each = usage.bytes / 3

        // The first, opened again, is the most recent; the second is held, as the photo open in Develop is.
        try await cache.local(urls[0])
        cache.hold(urls[1])
        try await cache.setBudget(each * 2 + each / 2)
        #expect(await cache.usage().files == 2)
        #expect(!cache.isLocal(urls[2]), "the least recently opened, not held, went")
        #expect(cache.isLocal(urls[0]) && cache.isLocal(urls[1]))
        #expect(!FileManager.default.fileExists(atPath: urls[2].deletingLastPathComponent().path), "with its folder")

        try await cache.local(urls[3])
        #expect(await Self.eventually { !cache.isLocal(urls[0]) }, "the oldest not held makes room for the newest")
        #expect(cache.isLocal(urls[1]) && cache.isLocal(urls[3]))

        // The budget is the library's: another cache of it reads it back.
        let photos = cloud.photos
        let again = ApplePhotosOriginals(
            index: cloud.sandbox.index, paths: LibraryPaths(root: cloud.sandbox.directory), photos: { photos },
            network: cloud.network,
        )
        #expect(await again.usage() == ApplePhotosOriginals.Usage(
            files: 2,
            bytes: each * 2,
            budget: each * 2 + each / 2,
        ))

        let emptied = await cache.empty()
        #expect(emptied.files == 1, "Empty Cache leaves the one held")
        #expect(cache.isLocal(urls[1]) && !cache.isLocal(urls[3]))
        cache.release(urls[1])
        #expect(await cache.empty().files == 1)
        #expect(await cache.usage().files == 0)
        let excluded = try cloud.sandbox.directory.appending(path: "Apple Photos", directoryHint: .isDirectory)
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        #expect(excluded == true)
    }

    @Test func `Photos' edit downloads again once it's edited again in Photos, an original never`() async throws {
        let cloud = try await Self.cloud([("IMG_0001.JPG", 50000, nil)], edited: ["IMG_0001.JPG"])
        defer { cloud.remove() }
        let original = try #require(cloud.urls["IMG_0001.JPG"])
        let edit = try #require(cloud.urls["IMG_0001 (Photos edit).jpeg"])
        try await cloud.cache.local(original)
        try await cloud.cache.local(edit)
        #expect(cloud.cache.isLocal(original) && cloud.cache.isLocal(edit))

        cloud.photos.update("CLOUD-0/L0/001") { asset in
            asset.adjusted = Date(timeIntervalSince1970: 1_800_000_000)
            asset.modified = asset.adjusted
        }
        try await ApplePhotosIndexer(photos: cloud.photos, index: cloud.sandbox.index).index()
        let heard = Heard()
        try await cloud.cache.local(edit) { heard.hear($0) }
        #expect(!heard.all.isEmpty, "Photos' new rendering was downloaded")
        let kept = Heard()
        try await cloud.cache.local(original) { kept.hear($0) }
        #expect(kept.all.isEmpty, "the original is the same")
    }

    @Test func `a row that isn't the Apple Photos root's isn't the cache's`() async throws {
        let cloud = try await Self.cloud([("IMG_0001.JPG", 1000, nil)])
        defer { cloud.remove() }
        let outside = URL(fileURLWithPath: "/Volumes/Test/Photos/A.JPG")
        #expect(!cloud.cache.owns(outside))
        await #expect(throws: ApplePhotosOriginals.Failure.notInPhotos) { try await cloud.cache.local(outside) }
        let stray = try #require(cloud.urls["IMG_0001.JPG"]).deletingLastPathComponent().appending(path: "B.JPG")
        await #expect(throws: ApplePhotosOriginals.Failure.notInPhotos) { try await cloud.cache.local(stray) }
    }
}
