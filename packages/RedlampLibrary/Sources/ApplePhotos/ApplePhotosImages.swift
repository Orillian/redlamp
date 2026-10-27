import CoreGraphics
import CryptoKit
import Foundation

/// What Photos gave of a picture without the network (LIB-59).
public enum ApplePhotosImage: Sendable {
    case image(CGImage)
    /// Photos keeps none on this Mac: it would need iCloud.
    case inCloud
    /// Photos has no such asset, or couldn't make its picture.
    case unavailable
}

/// One of an asset's pictures as Photos makes its images: the asset, by its local identifier, with Photos' edit or
/// without.
public struct ApplePhotosPicture: Sendable, Hashable {
    public var asset: String
    public var version: ApplePhotosImageVersion

    public init(asset: String, version: ApplePhotosImageVersion) {
        self.asset = asset
        self.version = version
    }
}

/// Photos' own images of its pictures at a size, never downloading (LIB-59): what the store's thumbnails and previews
/// of photos left in Photos are made from. PhotoKit's are `PHCachingImageManager`'s, on the app's side, since
/// `requestImage` gives an `NSImage` on the Mac; a simulated library's are made from its files.
public protocol ApplePhotosImages: Sendable {
    /// The picture at about `size` pixels on its long side, from what Photos keeps on this Mac. It blocks: only ever
    /// off the main thread.
    func image(of asset: String, version: ApplePhotosImageVersion, size: Int) -> ApplePhotosImage
    /// Has Photos prepare `pictures` at `size` for the requests to come, in place of what `window` held: the rows a
    /// grid or a filmstrip shows and a margin either side, as it scrolls. An empty set lets the window go.
    func cache(_ pictures: Set<ApplePhotosPicture>, size: Int, window: String)
}

/// A row of the Apple Photos root as the store keeps its images: its store key, its size and its content version, as
/// any photo's file's are kept, and the picture they're asked of Photos as.
public struct ApplePhotosStoreRow: Sendable, Hashable {
    public var key: ContentKey
    public var size: Int64
    public var modified: Date
    public var picture: ApplePhotosPicture
}

public extension IndexQueries {
    /// The rows of the asset whose row is at `path` in the Apple Photos root, each with the picture its images show:
    /// Photos' edit's is the current version; the originals' is the original once the asset is edited in Photos, and
    /// while it isn't the current version, the same picture, which Photos keeps images of. Empty for a path that isn't
    /// such a row.
    func applePhotosStoreRows(ofAssetAt path: String) throws -> [ApplePhotosStoreRow] {
        guard let slash = path.lastIndex(of: "/") else { return [] }
        let statement = try database.cached("""
        SELECT a.local_id, a.resource, p.content_key, p.size, p.modified FROM photos s JOIN folders f ON f.id = s.folder
          JOIN photo_assets sa ON sa.photo = s.id JOIN photo_assets a ON a.local_id = sa.local_id
          JOIN photos p ON p.id = a.photo
          WHERE f.path = ? AND s.name = ? AND s.version = '' AND p.content_key IS NOT NULL
        """)
        try statement.bind(String(path[..<slash]), at: 1)
        try statement.bind(String(path[path.index(after: slash)...]), at: 2)
        var rows: [(resource: ApplePhotosRow.Resource, row: ApplePhotosStoreRow)] = []
        try statement.forEachRow { row in
            guard let key = row.data(at: 2).flatMap(ContentKey.init(data:)) else { return }
            rows.append((ApplePhotosRow.Resource(rawValue: row.int(at: 1)) ?? .original, ApplePhotosStoreRow(
                key: key, size: row.int64(at: 3), modified: Date(timeIntervalSince1970: row.double(at: 4)),
                picture: ApplePhotosPicture(asset: row.string(at: 0) ?? "", version: .current),
            )))
        }
        let edited = rows.contains { $0.resource == .edit }
        return rows.map { found in
            var row = found.row
            row.picture.version = edited && found.resource != .edit ? .original : .current
            return row
        }
    }
}

public extension ApplePhotosPlace {
    /// The key the store keeps a row's thumbnail and preview by, which stands as its content key (LIB-59): the first
    /// 16 bytes of SHA-256 over its asset's key and which of the asset's files the row is. It needs none of the file's
    /// bytes, which are rarely on this Mac, and stays the same once its original is downloaded, so the store's images
    /// and renders of the row outlive the original's eviction.
    static func storeKey(asset key: String, resource: ApplePhotosRow.Resource) -> ContentKey {
        let digest = SHA256.hash(data: Data("store:\(key):\(resource.rawValue)".utf8))
        return ContentKey(data: Data(digest.prefix(16)))!
    }
}
