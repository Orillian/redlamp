import Foundation
import Synchronization

/// Makes the store's thumbnails and previews of photos left in Apple Photos from Photos' own images (LIB-59), never
/// from a file: a row's tier is asked of Photos at the tier's size without the network and stored under the row's store
/// key with its size and content version, as a file's are kept by its size and date, so Photos is asked once and the
/// grid reads the store after. The rows of an asset that show one picture, a RAW+JPEG pair's, are stored from one
/// request, a row asked for while another's request is under way waiting for its answer. A photo whose original is only
/// in iCloud has its images for as long as Photos keeps them on this Mac.
public struct ApplePhotosThumbnailMaker: Sendable {
    public enum Made: Sendable, Hashable {
        /// The store has it.
        case stored
        /// Photos has none on this Mac without iCloud.
        case inCloud
        /// The photo isn't a row of the Apple Photos root, or Photos couldn't give its picture.
        case unavailable
    }

    /// The pictures kept for caching, at most: the rows on and near the screen, read again as it scrolls.
    static let resolvedLimit = 4096

    public let store: PhotoStore
    public let index: LibraryIndex
    public let images: any ApplePhotosImages
    public let encoder: StoreImageEncoder
    /// The Apple Photos root's path, with a slash at its end: its rows are below it.
    private let below: String
    private let resolved = Resolved()
    private let asking = Asking()

    /// The pictures of rows read from the index for caching, by store key.
    private final class Resolved: Sendable {
        let pictures = Mutex<[ContentKey: ApplePhotosPicture]>([:])
    }

    /// The requests to Photos under way, by picture and tier, each with the rows that wait for its answer.
    private final class Asking: Sendable {
        struct Key: Hashable {
            let picture: ApplePhotosPicture
            let tier: PhotoStore.Tier
        }

        let requests = Mutex<[Key: Request]>([:])
    }

    /// A request to Photos under way: what it came to, once it's answered.
    private final class Request: Sendable {
        private let answered = DispatchSemaphore(value: 0)
        private let made = Mutex<Made>(.unavailable)

        func finish(_ outcome: Made) {
            made.withLock { $0 = outcome }
            answered.signal()
        }

        /// Waits for the answer, and passes it on to the next row waiting.
        func wait() -> Made {
            answered.wait()
            defer { answered.signal() }
            return made.withLock { $0 }
        }
    }

    public init(
        store: PhotoStore, index: LibraryIndex, paths: LibraryPaths, images: any ApplePhotosImages,
        encoder: StoreImageEncoder = StoreImageEncoder(),
    ) {
        self.store = store
        self.index = index
        self.images = images
        self.encoder = encoder
        below = LibraryIndexer.path(ApplePhotosPlace.root(in: paths)) + "/"
    }

    /// Whether `photo` is a row of the Apple Photos root, whose images come from Photos.
    public func owns(_ photo: URL) -> Bool {
        photo.path.hasPrefix(below)
    }

    /// Makes `photo`'s `tier` from Photos and stores it for the row as it is (`size` bytes, its content version
    /// `modified`), and for the other rows of its asset that show the same picture, unless the store has it. It
    /// blocks: only ever off the main thread.
    @discardableResult
    public func make(_ photo: URL, key: ContentKey, tier: PhotoStore.Tier, size: Int64, modified: Date) -> Made {
        if store.contains(key, tier: tier, size: size, modified: modified) {
            return .stored
        }
        guard owns(photo), let rows = try? index.readAndWait({ reader in
            try reader.applePhotosStoreRows(ofAssetAt: LibraryIndexer.path(photo))
        }), let picture = rows.first(where: { $0.key == key })?.picture
        else { return .unavailable }
        let request = Asking.Key(picture: picture, tier: tier)
        let (underWay, leads) = asking.requests.withLock { requests in
            if let underWay = requests[request] {
                return (underWay, false)
            }
            let leading = Request()
            requests[request] = leading
            return (leading, true)
        }
        guard leads else {
            let made = underWay.wait()
            return made == .stored && !store.contains(key, tier: tier, size: size, modified: modified)
                ? make(photo, key: key, tier: tier, size: size, modified: modified) : made
        }
        // A request that ended since the store was looked at stored what this would ask for.
        let made = store.contains(key, tier: tier, size: size, modified: modified)
            ? .stored : ask(picture, tier: tier, storing: rows, as: key, size: size, modified: modified)
        asking.requests.withLock { $0[request] = nil }
        underWay.finish(made)
        return made
    }

    /// Asks Photos for `picture` at `tier`'s size, and stores it for the row `key` names as it is and for the other
    /// rows of `rows` that show it.
    private func ask(
        _ picture: ApplePhotosPicture, tier: PhotoStore.Tier, storing rows: [ApplePhotosStoreRow], as key: ContentKey,
        size: Int64, modified: Date,
    ) -> Made {
        switch images.image(of: picture.asset, version: picture.version, size: tier.pixelSize) {
        case .inCloud:
            return .inCloud
        case .unavailable:
            return .unavailable
        case let .image(image):
            guard let payload = encoder.encode(image, for: tier),
                  store.store(payload, for: key, tier: tier, size: size, modified: modified)
            else { return .unavailable }
            for row in rows where row.picture == picture && row.key != key
                && !store.contains(row.key, tier: tier, size: row.size, modified: row.modified) {
                store.store(payload, for: row.key, tier: tier, size: row.size, modified: row.modified)
            }
            return .stored
        }
    }

    /// Has Photos prepare the pictures of `photos`, the rows a grid or a filmstrip shows and a margin either side, at
    /// `tier`'s size for the requests their cells make, in `window` in place of what it held: only those the store
    /// lacks, so Photos isn't asked again for what it gave. It blocks: only ever off the main thread.
    public func cache(
        _ photos: [(url: URL, key: ContentKey, size: Int64, modified: Date)], tier: PhotoStore.Tier, window: String,
    ) {
        let wanted = photos.filter {
            owns($0.url) && !store.contains($0.key, tier: tier, size: $0.size, modified: $0.modified)
        }
        var pictures = Set<ApplePhotosPicture>()
        var unknown: [(url: URL, key: ContentKey)] = []
        resolved.pictures.withLock { known in
            for photo in wanted {
                if let picture = known[photo.key] {
                    pictures.insert(picture)
                } else {
                    unknown.append((photo.url, photo.key))
                }
            }
        }
        if !unknown.isEmpty, let found = try? index.readAndWait({ reader in
            try unknown.map { try reader.applePhotosStoreRows(ofAssetAt: LibraryIndexer.path($0.url)) }
        }) {
            resolved.pictures.withLock { known in
                if known.count > Self.resolvedLimit {
                    known = [:]
                }
                for row in found.joined() {
                    known[row.key] = row.picture
                }
            }
            for (photo, rows) in zip(unknown, found) {
                if let picture = rows.first(where: { $0.key == photo.key })?.picture {
                    pictures.insert(picture)
                }
            }
        }
        images.cache(pictures, size: tier.pixelSize, window: window)
    }
}
