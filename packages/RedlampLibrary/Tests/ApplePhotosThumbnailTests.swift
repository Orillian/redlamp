import Foundation
import Testing
@testable import RedlampLibrary

/// Thumbnails and previews of photos left in Apple Photos (LIB-59) on the simulated library: made from Photos' own
/// images, never from a file, into the store under each row's store key and content version; Photos' edit's row
/// showing Photos' current version and its original the original; a picture two rows show asked for once; nothing
/// stored where Photos keeps no image without iCloud; and the rows on and near the screen cached in Photos.
struct ApplePhotosThumbnailTests {
    /// A row of the Apple Photos root as the store keeps its images.
    private struct Row {
        let url: URL
        let key: ContentKey
        let size: Int64
        let modified: Date
        let asset: String
        let resource: ApplePhotosRow.Resource
    }

    /// The rows of the Apple Photos root, by name.
    private static func rows(_ sandbox: IndexSandbox) async throws -> [String: Row] {
        try await sandbox.index.read { reader in
            var rows: [String: Row] = [:]
            try reader.database.prepare("""
            SELECT f.path, p.name, p.content_key, p.size, p.modified, a.asset_key, a.resource FROM photos p
              JOIN folders f ON f.id = p.folder JOIN photo_assets a ON a.photo = p.id
            """).forEachRow { row in
                let name = row.string(at: 1) ?? ""
                guard let key = row.data(at: 2).flatMap(ContentKey.init(data:)) else { return }
                rows[name] = Row(
                    url: URL(fileURLWithPath: (row.string(at: 0) ?? "") + "/" + name), key: key, size: row.int64(at: 3),
                    modified: Date(timeIntervalSince1970: row.double(at: 4)), asset: row.string(at: 5) ?? "",
                    resource: ApplePhotosRow.Resource(rawValue: row.int(at: 6)) ?? .original,
                )
            }
            return rows
        }
    }

    /// `albums` of `photos` kept in place in `sandbox`, and the maker of their images, with a store of its own.
    private static func kept(
        _ albums: [String], of photos: SimulatedPhotosLibrary, in sandbox: IndexSandbox,
    ) async throws -> ApplePhotosThumbnailMaker {
        try await ApplePhotosIndexer(photos: photos, index: sandbox.index).keep(albums)
        return ApplePhotosThumbnailMaker(
            store: PhotoStore(root: sandbox.directory.appending(path: "Store", directoryHint: .isDirectory)),
            index: sandbox.index, paths: LibraryPaths(root: sandbox.directory), images: photos,
        )
    }

    private static func make(_ row: Row, _ tier: PhotoStore.Tier, with maker: ApplePhotosThumbnailMaker)
        -> ApplePhotosThumbnailMaker.Made {
        maker.make(row.url, key: row.key, tier: tier, size: row.size, modified: row.modified)
    }

    @Test func `each row's store key comes from its asset's key and its file, and stands as its content key`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        _ = try await Self.kept(["album-lisbon", "album-selects"], of: photos, in: sandbox)
        let rows = try await Self.rows(sandbox)
        #expect(rows.count == 8)
        for row in rows.values {
            #expect(row.key == ApplePhotosPlace.storeKey(asset: row.asset, resource: row.resource))
        }
        #expect(Set(rows.values.map(\.key)).count == 8, "a pair's two rows and an edit's have keys of their own")

        // Rows written before LIB-59 had no content key: the next pass gives them theirs.
        try await sandbox.index.write { writer in
            try writer.database
                .execute("UPDATE photos SET content_key = NULL WHERE id IN (SELECT photo FROM photo_assets)")
            try writer.database.execute(
                "UPDATE folders SET indexed_signature = 0 WHERE root IN (SELECT id FROM roots WHERE kind = 1)",
            )
        }
        #expect(try await Self.rows(sandbox).isEmpty)
        let again = try await ApplePhotosIndexer(photos: photos, index: sandbox.index).index()
        #expect(again.unchanged == 0 && again.inserted.isEmpty)
        #expect(try await Self.rows(sandbox).mapValues(\.key) == rows.mapValues(\.key))
    }

    @Test func `Photos' edit's row shows Photos' current version and its original the original, a photo never edited the current`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        _ = try await Self.kept(["album-lisbon", "album-selects"], of: SamplePhotos.library(), in: sandbox)
        let rows = try await Self.rows(sandbox)
        func pictures(_ name: String) async throws -> [ContentKey: ApplePhotosPicture] {
            let path = try LibraryIndexer.path(#require(rows[name]).url)
            let found = try await sandbox.index.read { try $0.applePhotosStoreRows(ofAssetAt: path) }
            return Dictionary(found.map { ($0.key, $0.picture) }) { first, _ in first }
        }
        let edited = try await pictures("IMG_0002.JPG")
        let original = try #require(rows["IMG_0002.JPG"]), edit = try #require(rows["IMG_0002 (Photos edit).jpeg"])
        #expect(edited.count == 2)
        #expect(edited[original.key] == ApplePhotosPicture(asset: SamplePhotos.edited, version: .original))
        #expect(edited[edit.key] == ApplePhotosPicture(asset: SamplePhotos.edited, version: .current))
        let tram = try await pictures("IMG_0001.HEIC")
        #expect(Array(tram.values) == [ApplePhotosPicture(asset: SamplePhotos.tram, version: .current)])
        let pair = try await pictures("IMG_0004.NEF")
        #expect(pair.count == 2 && Set(pair.values) == [ApplePhotosPicture(
            asset: SamplePhotos.pair,
            version: .current,
        )])
        let outside = try await sandbox.index
            .read { try $0.applePhotosStoreRows(ofAssetAt: "/Volumes/Test/Photos/A.JPG") }
        #expect(outside.isEmpty)
    }

    @Test func `a row's images are asked of Photos once and kept in the store, a pair's two rows from one request`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let maker = try await Self.kept(["album-selects", "album-lisbon"], of: photos, in: sandbox)
        let rows = try await Self.rows(sandbox)
        let jpeg = try #require(rows["IMG_0004.JPG"]), raw = try #require(rows["IMG_0004.NEF"])
        let pair = ApplePhotosPicture(asset: SamplePhotos.pair, version: .current)

        #expect(Self.make(jpeg, .grid, with: maker) == .stored)
        #expect(photos.askedImages == [pair: 1])
        #expect(maker.store.contains(raw.key, tier: .grid, size: raw.size, modified: raw.modified))
        #expect(Self.make(raw, .grid, with: maker) == .stored)
        #expect(Self.make(jpeg, .grid, with: maker) == .stored)
        #expect(photos.askedImages == [pair: 1], "the raw's came with the JPEG's, and the store keeps both")
        let data = try #require(maker.store.data(for: jpeg.key, tier: .grid, size: jpeg.size, modified: jpeg.modified))
        let thumbnail = try #require(StoreImageEncoder.decode(data))
        #expect(max(thumbnail.width, thumbnail.height) <= PhotoStore.Tier.grid.pixelSize)
        #expect(!FileManager.default.fileExists(atPath: jpeg.url.path), "nothing downloaded")

        #expect(Self.make(jpeg, .preview, with: maker) == .stored)
        #expect(photos.askedImages == [pair: 2], "the preview's a request of its own")

        // Photos' edit and its original are two pictures, asked for once each.
        let edit = try #require(rows["IMG_0002 (Photos edit).jpeg"]), original = try #require(rows["IMG_0002.JPG"])
        #expect(Self.make(edit, .grid, with: maker) == .stored && Self.make(original, .grid, with: maker) == .stored)
        #expect(photos.askedImages[ApplePhotosPicture(asset: SamplePhotos.edited, version: .current)] == 1)
        #expect(photos.askedImages[ApplePhotosPicture(asset: SamplePhotos.edited, version: .original)] == 1)

        // A new content version, an edit made in Photos, is asked for again.
        let later = edit.modified.addingTimeInterval(60)
        #expect(!maker.store.contains(edit.key, tier: .grid, size: edit.size, modified: later))
        #expect(maker.make(edit.url, key: edit.key, tier: .grid, size: edit.size, modified: later) == .stored)
        #expect(photos.askedImages[ApplePhotosPicture(asset: SamplePhotos.edited, version: .current)] == 2)
    }

    @Test func `a photo Photos keeps no image of without iCloud is in the cloud, nothing stored, and a file is left to its own`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let folder = try TemporaryFolder()
        try FileManager.default.copyItem(
            at: SamplePhotos.folder.appending(path: "files/IMG_0010.JPG"),
            to: folder.url.appending(path: "IMG_0010.JPG"),
        )
        let manifest = try SamplePhotos.manifest(
            in: folder.url, collections: [["id": "album-a", "title": "A", "kind": "album"]], assets: [
                ["id": "asset-1", "created": "2026-10-01T10:00:00Z", "albums": ["album-a"], "resources": [
                    ["kind": "photo", "name": "IMG_0010.JPG", "file": "IMG_0010.JPG"],
                ]],
                [
                    "id": "asset-2",
                    "created": "2026-10-02T10:00:00Z",
                    "albums": ["album-a"],
                    "imagesInCloud": true,
                    "resources": [["kind": "photo", "name": "IMG_0011.JPG", "file": "IMG_0010.JPG", "inCloud": true]],
                ],
            ],
        )
        let photos = try SimulatedPhotosLibrary(manifest: manifest)
        let maker = try await Self.kept(["album-a"], of: photos, in: sandbox)
        let rows = try await Self.rows(sandbox)
        let local = try #require(rows["IMG_0010.JPG"]), cloud = try #require(rows["IMG_0011.JPG"])
        #expect(Self.make(local, .grid, with: maker) == .stored)
        #expect(Self.make(cloud, .grid, with: maker) == .inCloud)
        #expect(Self.make(cloud, .preview, with: maker) == .inCloud)
        #expect(!maker.store.contains(cloud.key, tier: .grid) && !maker.store.contains(cloud.key, tier: .preview))
        #expect(photos.askedImages[ApplePhotosPicture(asset: "asset-2", version: .current)] == 2)

        let file = URL(fileURLWithPath: IndexSandbox.rootPath + "/IMG_0010.JPG")
        #expect(!maker.owns(file) && maker.owns(local.url))
        #expect(maker
            .make(file, key: local.key, tier: .preview, size: local.size, modified: local.modified) == .unavailable)
    }

    @Test func `the rows on and near the screen are cached in Photos but those the store has, and the window let go`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let photos = try SamplePhotos.library()
        let maker = try await Self.kept(["album-lisbon", "album-selects"], of: photos, in: sandbox)
        let rows = try await Self.rows(sandbox)
        let shown = ["IMG_0001.HEIC", "IMG_0002.JPG", "IMG_0002 (Photos edit).jpeg", "IMG_0004.JPG", "IMG_0004.NEF"]
            .compactMap { rows[$0] }
        let window = shown.map { (url: $0.url, key: $0.key, size: $0.size, modified: $0.modified) }
        #expect(Self.make(shown[0], .grid, with: maker) == .stored)
        maker.cache(
            window + [(URL(fileURLWithPath: "/Volumes/Test/Photos/A.JPG"), shown[0].key, 0, Date())],
            tier: .grid,
            window: "grid",
        )
        #expect(photos.cachedImages["grid"] == [
            ApplePhotosPicture(asset: SamplePhotos.edited, version: .original),
            ApplePhotosPicture(asset: SamplePhotos.edited, version: .current),
            ApplePhotosPicture(asset: SamplePhotos.pair, version: .current),
        ])
        #expect(photos.askedImages.values.reduce(0, +) == 1, "caching asks for no image")
        maker.cache([], tier: .grid, window: "grid")
        #expect(photos.cachedImages["grid"] == nil)
    }
}
