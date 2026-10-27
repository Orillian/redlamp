import AppKit
import Foundation
import ImageIO
import RedlampDesign
import RedlampDocument
import Testing
import UniformTypeIdentifiers
@testable import RedlampLibrary
@_spi(Harness) @testable import RedlampUI

/// Photos left in Apple Photos seen without their originals (LIB-59), on the simulated library: the grid's, the
/// filmstrip's and the loupe's images made from Photos' own and kept in the store, each picture asked of Photos once;
/// Photos' edit shown as Photos shows it; a photo whose images are only in iCloud marked with the cloud; and the rows
/// on and near the screen cached in Photos as the grid scrolls. Nothing is downloaded.
@MainActor
@Suite(.serialized)
struct ApplePhotosThumbnailsTests {
    /// A simulated Photos library of `count` photos in one album, made in memory: the second edited in Photos, the
    /// third
    /// a RAW+JPEG pair, the fourth with its images only in iCloud. Its pictures are red for Photos' current version and
    /// blue for the original, each made `taking` long.
    static func photos(_ count: Int, taking: Duration = .zero) -> SimulatedPhotosLibrary {
        let assets = (1 ... count).map { number in
            var resources = [ApplePhotosResource(
                kind: .photo, type: "public.jpeg", originalFilename: String(format: "IMG_%04d.JPG", number),
            )]
            if number == 2 {
                resources.append(ApplePhotosResource(
                    kind: .fullSizePhoto, type: "public.jpeg", originalFilename: "FullSizeRender.jpeg",
                ))
            } else if number == 3 {
                resources.append(ApplePhotosResource(
                    kind: .alternatePhoto, type: "com.adobe.raw-image", originalFilename: "IMG_0003.DNG",
                ))
            }
            let created = Date(timeIntervalSince1970: 1_790_000_000 + Double(number) * 60)
            return ApplePhotosAsset(
                id: "asset-\(number)", created: created, hasAdjustments: number == 2,
                adjusted: number == 2 ? created.addingTimeInterval(600) : nil, albums: ["album-a"],
                resources: resources,
            )
        }
        let seconds = Double(taking.components.seconds) + Double(taking.components.attoseconds) / 1e18
        return SimulatedPhotosLibrary(
            collections: [ApplePhotosCollection(id: "album-a", title: "A", kind: .album)], assets: assets,
        ) { asset, version, size in
            if seconds > 0 {
                Thread.sleep(forTimeInterval: seconds)
            }
            guard asset.id != "asset-4" else { return .inCloud }
            return picture(version, size: size).map(ApplePhotosImage.image) ?? .unavailable
        }
    }

    /// Red for Photos' current version, blue for the original, at most 64 pixels wide.
    nonisolated static func picture(_ version: ApplePhotosImageVersion, size: Int) -> CGImage? {
        let (width, height) = (min(size, 64), min(size, 48))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ) else { return nil }
        let current = version == .current
        context.setFillColor(red: current ? 0.9 : 0.1, green: 0.1, blue: current ? 0.1 : 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// Whether `image` is more red than blue: a picture of Photos' current version.
    private static func isRed(_ image: CGImage) -> Bool {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn && pixel[0] > pixel[2]
    }

    /// The picture a row of `photos(_:)` shows, by its name.
    private static func picture(of name: String) -> ApplePhotosPicture {
        switch name {
        case "IMG_0002.JPG": ApplePhotosPicture(asset: "asset-2", version: .original)
        case "IMG_0002 (Photos edit).jpeg": ApplePhotosPicture(asset: "asset-2", version: .current)
        default: ApplePhotosPicture(asset: "asset-\(Int(name.dropFirst(4).prefix(4)) ?? 0)", version: .current)
        }
    }

    /// `photos`' album kept in place in the sandbox's library, with All Photographs shown, in a grid of `size` when
    /// `grid`.
    static func open(
        _ sandbox: SourcesSandbox, _ photos: SimulatedPhotosLibrary, rows: Int, grid: CGSize? = nil,
    ) async throws -> (EditorModel, LibraryGridView?, NSWindow?) {
        let model = try await sandbox.open(photos: photos)
        let core = try #require(sandbox.service?.core)
        try await ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
            .keep(["album-a"])
        model.showLibrary(.grid)
        var shown: (LibraryGridView, NSWindow)?
        if let grid {
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: grid), styleMask: [.borderless], backing: .buffered,
                defer: false,
            )
            let view = LibraryGridView(model: model)
            view.frame = window.contentLayoutRect
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            shown = (view, window)
        }
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually(seconds: 20) { !model.librarySources.isListing && model.items.count == rows }
        try #require(model.items.count == rows, "All Photographs shows the photos kept in place")
        return (model, shown?.0, shown?.1)
    }

    /// Whether every cell of `grid` shows its thumbnail or the cloud mark.
    private static func settled(_ grid: LibraryGridView) -> Bool {
        !grid.cells.isEmpty && grid.cells.values.allSatisfy { $0.item == nil || $0.image != nil || $0.showsCloud }
    }

    @Test func `photos left in Apple Photos show Photos' thumbnails, asked once and kept, Photos' edit as Photos shows it`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos(6)
        let (model, shown, window) = try await Self.open(
            sandbox,
            photos,
            rows: 8,
            grid: CGSize(width: 900, height: 700),
        )
        let grid = try #require(shown)
        defer { window?.contentView = nil }
        try await sandbox.eventually { Self.settled(grid) }
        let cells = Dictionary(grid.cells.values.compactMap { cell in cell.item.map { ($0.name, cell) } }) { a, _ in a }
        #expect(cells["IMG_0001.JPG"] != nil && cells["IMG_0002 (Photos edit).jpeg"] != nil)
        for (name, cell) in cells where name != "IMG_0004.JPG" {
            let image = try #require(cell.image, "\(name) shows Photos' thumbnail")
            #expect(!cell.showsCloud)
            #expect(Self.isRed(image) == (name != "IMG_0002.JPG"), "\(name) shows \(Self.picture(of: name).version)")
        }
        let cloud = try #require(cells["IMG_0004.JPG"])
        #expect(cloud.image == nil && cloud.showsCloud, "a photo whose images are only in iCloud has the cloud mark")
        let asked = photos.askedImages
        for name in cells.keys where name != "IMG_0004.JPG" {
            #expect(asked[Self.picture(of: name)] == 1, "\(name)'s picture asked for once")
        }

        // Another grid reads them from the store: Photos isn't asked again.
        let again = LibraryGridView(model: model)
        again.frame = try #require(window).contentLayoutRect
        window?.contentView = again
        again.layoutSubtreeIfNeeded()
        try await sandbox.eventually { Self.settled(again) && again.cells.count == grid.cells.count }
        #expect(again.cells.values.allSatisfy { $0.item?.name == "IMG_0004.JPG" || $0.image != nil })
        let local = { (pictures: [ApplePhotosPicture: Int]) in pictures.filter { $0.key.asset != "asset-4" } }
        #expect(local(photos.askedImages) == local(asked), "the store's thumbnails")

        let core = try #require(sandbox.service?.core)
        let root = ApplePhotosPlace.root(in: core.paths)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        #expect(files?.isEmpty ?? true, "nothing downloaded")
    }

    @Test func `the filmstrip's thumbnail and the loupe's preview of a photo left in Apple Photos are Photos' own`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos(6)
        let (model, _, _) = try await Self.open(sandbox, photos, rows: 8)
        let rows = model.library.items.allRows
        let edit = try #require(rows.first { $0.name == "IMG_0002 (Photos edit).jpeg" })
        let thumbnail = try #require(await model.thumbnailLoader.image(for: edit))
        #expect(Self.isRed(thumbnail))
        let preview = await withCheckedContinuation { continuation in
            model.previews.request(edit) { continuation.resume(returning: $0) }
        }
        #expect(try Self.isRed(#require(preview)))
        #expect(
            photos.askedImages[ApplePhotosPicture(asset: "asset-2", version: .current)] == 2,
            "its grid tier and preview",
        )

        let cloud = try #require(rows.first { $0.name == "IMG_0004.JPG" })
        #expect(await model.thumbnailLoader.image(for: cloud) == nil)
        #expect(model.thumbnailLoader.isInCloud(cloud), "the filmstrip marks it with the cloud")
        let none = await withCheckedContinuation { continuation in
            model.previews.request(cloud) { continuation.resume(returning: $0) }
        }
        #expect(none == nil)
    }

    @Test func `the rows on and near the screen are cached in Photos as the grid scrolls, and those far from it let go`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos(300, taking: .milliseconds(15))
        let (_, shown, window) = try await Self.open(sandbox, photos, rows: 302, grid: CGSize(width: 480, height: 320))
        let grid = try #require(shown)
        defer { window?.contentView = nil }
        func cached() -> Set<Int> {
            Set(photos.cachedImages.values.joined().compactMap { Int($0.asset.dropFirst("asset-".count)) })
        }
        try await sandbox.eventually { !cached().isEmpty }
        let first = cached()
        #expect(!first.isEmpty && first.allSatisfy { $0 <= 100 }, "the first screens' photos: \(first.sorted())")
        LibraryGridViews.scroll(grid, to: 1)
        try await sandbox.eventually { cached().contains { $0 > 250 } }
        let last = cached()
        #expect(last.allSatisfy { $0 > 200 }, "the window followed the grid: \(last.sorted())")
        try await sandbox.eventually { Self.settled(grid) }
        let local = photos.askedImages.filter { $0.key.asset != "asset-4" }
        #expect(local.values.allSatisfy { $0 == 1 }, "each picture asked for once")
    }

    // MARK: - At 50,000

    /// Photos' own images for measuring: the CC0 raws' previews as JPEGs at 512 and 2048 pixels, which a request
    /// decodes at its size, as Photos decodes its derivatives.
    private static func derivatives() -> [(small: Data, large: Data)] {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "tests/fixtures/raw")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        func jpeg(_ image: CGImage) -> Data? {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary,
            )
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }
        return names.filter { !$0.hasSuffix(".redlamp") && !$0.hasPrefix(".") }.sorted().compactMap { name in
            guard let source = CGImageSourceCreateWithURL(folder.appending(path: name) as CFURL, nil),
                  let large = Self.thumbnail(source, 2048), let largeData = jpeg(large),
                  let small = CGImageSourceCreateWithData(largeData as CFData, nil)
                  .flatMap({ Self.thumbnail($0, 512) }),
                  let smallData = jpeg(small)
            else { return nil }
            return (smallData, largeData)
        }
    }

    private nonisolated static func thumbnail(_ source: CGImageSource, _ size: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    /// 50,000 assets across ten albums, as LIB-58 measures them: a tenth RAW+JPEG pairs, a twentieth edited in Photos,
    /// a third without a cloud identifier; their pictures `derivatives`' in turn.
    private static func generated(_ count: Int, derivatives: [(small: Data, large: Data)]) -> SimulatedPhotosLibrary {
        let albums = (0 ..< 10).map { ApplePhotosCollection(id: "album-\($0)", title: "Album \($0)", kind: .album) }
        let assets = (0 ..< count).map { number in
            let stem = String(format: "IMG_%05d", number)
            var resources = [ApplePhotosResource(
                kind: .photo, type: "public.heic", originalFilename: stem + ".HEIC", pixelWidth: 4032,
                pixelHeight: 3024,
            )]
            if number % 10 == 0 {
                resources = [
                    ApplePhotosResource(kind: .photo, type: "public.jpeg", originalFilename: stem + ".JPG"),
                    ApplePhotosResource(
                        kind: .alternatePhoto,
                        type: "com.adobe.raw-image",
                        originalFilename: stem + ".DNG",
                    ),
                ]
            }
            let edited = number % 20 == 1
            if edited {
                resources.append(ApplePhotosResource(
                    kind: .fullSizePhoto, type: "public.jpeg", originalFilename: "FullSizeRender.jpeg",
                ))
            }
            let created = Date(timeIntervalSince1970: 1_700_000_000 + Double(number) * 60)
            return ApplePhotosAsset(
                id: String(format: "%08X-0000-4000-8000-%012X/L0/001", number, number),
                cloud: number % 3 == 0 ? nil : "cloud-\(number)", created: created, hasAdjustments: edited,
                adjusted: edited ? created.addingTimeInterval(3600) : nil, albums: ["album-\(number % 10)"],
                resources: resources,
            )
        }
        return SimulatedPhotosLibrary(collections: albums, assets: assets) { asset, _, size in
            let number = Int(asset.id.prefix(8), radix: 16) ?? 0
            let derivative = derivatives[number % derivatives.count]
            guard let source = CGImageSourceCreateWithData(
                (size <= 512 ? derivative.small : derivative.large) as CFData, nil,
            ), let image = thumbnail(source, size) else { return .unavailable }
            return .image(image)
        }
    }

    /// The memory the process takes, as Activity Monitor shows it, in megabytes.
    private static var footprint: Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Whether every cell of `grid` on screen shows its photo's thumbnail.
    private static func shown(_ grid: LibraryGridView) -> Bool {
        !grid.cells.isEmpty && grid.cells.values.allSatisfy { !$0.root.isHidden && $0.image != nil }
    }

    /// How long until `grid`, scrolled to each of `places`, shows every thumbnail on screen, in milliseconds.
    private static func screenfuls(_ grid: LibraryGridView, at places: [Double]) async throws -> [Double] {
        var times: [Double] = []
        for place in places {
            let started = ContinuousClock.now
            LibraryGridViews.scroll(grid, to: place)
            let deadline = started + .seconds(10)
            while !shown(grid), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(1))
            }
            let elapsed = ContinuousClock.now - started
            times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        return times
    }

    private static func percentile(_ values: [Double], _ share: Double) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))]
    }

    /// LIB-59's budgets on the simulated library at 50,000 assets, Photos' images the CC0 raws' previews: the grid
    /// scrolled at three rows a frame through all of them with the main thread's p99 under 8.3 ms; a screenful the
    /// store
    /// hasn't, from Photos, at p95 under 250 ms; one the store has within a frame; the grid tier about 22 KB a
    /// thumbnail;
    /// the memory within the library's 250 MB; nothing downloaded. Skipped unless `REDLAMP_APPLE_PHOTOS_BENCH=1`
    /// (`TEST_RUNNER_REDLAMP_APPLE_PHOTOS_BENCH=1`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_APPLE_PHOTOS_BENCH"] == "1"))
    func `50,000 photos left in Apple Photos scroll within LIB-59's budgets`() async throws {
        let derivatives = Self.derivatives()
        try #require(!derivatives.isEmpty, "the CC0 raws in tests/fixtures/raw")
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.generated(50000, derivatives: derivatives)
        let model = try await sandbox.open(photos: photos)
        let core = try #require(sandbox.service?.core)
        let kept = try await ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
            .keep((0 ..< 10).map { "album-\($0)" })
        let rows = kept.inserted.count
        let before = Self.footprint
        model.showLibrary(.grid)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered,
            defer: false,
        )
        defer { window.contentView = nil }
        let grid = LibraryGridView(model: model)
        grid.frame = window.contentLayoutRect
        window.contentView = grid
        grid.layoutSubtreeIfNeeded()
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually(seconds: 60) { !model.librarySources.isListing && model.items.count == rows }
        try #require(model.items.count == rows, "All Photographs shows the \(rows) photos kept in place")

        // A screenful the store hasn't, from Photos' images, at twenty places through the grid.
        let places = (0 ..< 20).map { (Double($0) + 0.5) / 20 }
        let fromPhotos = try await Self.screenfuls(grid, at: places)

        // The main thread while the grid scrolls through every photo at three rows a frame, at 120 frames a second.
        let row = try #require(LibraryGridViews.position(of: grid)?.row)
        let steps = Int((1 / max(row * 3, 1e-6)).rounded(.up))
        LibraryGridViews.scroll(grid, to: 0)
        let monitor = MainThreadMonitor()
        monitor.start()
        let scrolling = ContinuousClock.now
        for step in 1 ... steps {
            LibraryGridViews.scroll(grid, to: min(Double(step) / Double(steps), 1))
            try await Task.sleep(for: .microseconds(8333))
        }
        let scrolled = ContinuousClock.now - scrolling
        monitor.stop()
        let turns = try #require(monitor.summary())

        // A screenful the store has, in a grid that has none in memory.
        let fresh = LibraryGridView(model: model)
        fresh.frame = window.contentLayoutRect
        window.contentView = fresh
        fresh.layoutSubtreeIfNeeded()
        let fromStore = try await Self.screenfuls(fresh, at: places)
        let after = Self.footprint

        let statistics = core.store.statistics()
        let perThumbnail = statistics.records > 0 ? Double(statistics.gridBytes) / Double(statistics.records) : 0
        let asked = photos.askedImages
        let root = ApplePhotosPlace.root(in: core.paths)
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        print(String(
            format: "LIB-59 bench: %d rows of 50,000 assets, %d derivatives; a screenful from Photos p50 %.0f ms, p95 %.0f ms, "
                + "max %.0f ms; from the store p50 %.1f ms, p95 %.1f ms; scrolling %d steps in %.1f s, main thread p50 %.2f ms, "
                + "p95 %.2f ms, p99 %.2f ms, max %.1f ms, %d of %d turns over 8.3 ms; %d grid thumbnails, %.1f KB each, so %.2f GB "
                + "for every row; %d pictures asked of Photos, at most %d times each; memory %.0f MB before the grid, %.0f MB "
                + "after; %d files in the Photos root",
            rows, derivatives.count, Self.percentile(fromPhotos, 0.5), Self.percentile(fromPhotos, 0.95),
            fromPhotos.max() ?? 0,
            Self.percentile(fromStore, 0.5), Self.percentile(fromStore, 0.95), steps,
            Double(scrolled.components.seconds) + Double(scrolled.components.attoseconds) / 1e18, turns.p50, turns.p95,
            turns.p99, turns.max, turns.overFrame, turns.iterations, statistics.records, perThumbnail / 1024,
            perThumbnail * Double(rows) / 1e9, asked.count, asked.values.max() ?? 0, before, after, files?.count ?? 0,
        ))
        #expect(turns.p99 < 8.3)
        #expect(Self.percentile(fromPhotos, 0.95) < 250)
        #expect(Self.percentile(fromStore, 0.95) < 16.7)
        #expect(asked.values.allSatisfy { $0 == 1 }, "each picture asked of Photos once")
        #expect(files?.isEmpty ?? true, "nothing downloaded")
    }
}
