import AppKit
import Photos
import RedlampLibrary
import Synchronization

/// Photos' own images of its pictures through one `PHCachingImageManager` (LIB-59), never downloading: each asked at
/// the size the store keeps, from the scheduler's lanes, which wait for it, with the pictures of the rows the grid and
/// the filmstrip show and a margin either side prepared ahead. On the Mac `requestImage` gives an `NSImage`, which is
/// why this is the app's and not the library's. Compile-checked only: what Photos keeps on this Mac under Optimize Mac
/// Storage, and how fast it answers, is the census's to measure.
final class PhotoKitImages: ApplePhotosImages {
    static let shared = PhotoKitImages()

    private let manager = PHCachingImageManager()
    /// A request's options, by version. The caching manager matches a request to what it prepared by its size, its
    /// content mode and these; they're never changed once made.
    private nonisolated(unsafe) let options: [ApplePhotosImageVersion: PHImageRequestOptions]
    /// What each window holds.
    private let windows = Mutex<[String: Set<Cached>]>([:])

    /// A picture being prepared, at its size.
    private struct Cached: Hashable {
        let picture: ApplePhotosPicture
        let size: Int
    }

    /// What a request answered, read once it returns: a synchronous request answers before.
    private final class Answer: Sendable {
        let image = Mutex(ApplePhotosImage.unavailable)
    }

    init() {
        var options: [ApplePhotosImageVersion: PHImageRequestOptions] = [:]
        for version in [ApplePhotosImageVersion.current, .original] {
            let request = PHImageRequestOptions()
            request.isNetworkAccessAllowed = false
            request.isSynchronous = true
            request.deliveryMode = .highQualityFormat
            request.resizeMode = .fast
            request.version = version == .current ? .current : .original
            options[version] = request
        }
        self.options = options
    }

    /// At about `size` pixels on its long side, or larger: the store fits it to its tier.
    func image(of asset: String, version: ApplePhotosImageVersion, size: Int) -> ApplePhotosImage {
        guard Self.canRead, let found = Self.assets([asset]).first else { return .unavailable }
        let answer = Answer()
        manager.requestImage(
            for: found, targetSize: Self.target(size), contentMode: .aspectFit, options: options[version],
        ) { image, info in
            if let image = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                answer.image.withLock { $0 = .image(image) }
            } else if info?[PHImageResultIsInCloudKey] as? Bool == true {
                answer.image.withLock { $0 = .inCloud }
            }
        }
        return answer.image.withLock { $0 }
    }

    /// Prepares what the windows together hold that they didn't, and stops preparing what none holds now: a picture
    /// two windows show stays prepared while either does.
    func cache(_ pictures: Set<ApplePhotosPicture>, size: Int, window: String) {
        let (starting, stopping) = windows.withLock { windows -> (Set<Cached>, Set<Cached>) in
            let before = windows.values.reduce(into: Set<Cached>()) { $0.formUnion($1) }
            windows[window] = pictures.isEmpty ? nil : Set(pictures.map { Cached(picture: $0, size: size) })
            let after = windows.values.reduce(into: Set<Cached>()) { $0.formUnion($1) }
            return (after.subtracting(before), before.subtracting(after))
        }
        guard Self.canRead else { return }
        for (group, cached) in Dictionary(
            grouping: stopping,
            by: { Group(size: $0.size, version: $0.picture.version) },
        ) {
            manager.stopCachingImages(
                for: Self.assets(cached.map(\.picture.asset)), targetSize: Self.target(group.size),
                contentMode: .aspectFit, options: options[group.version],
            )
        }
        for (group, cached) in Dictionary(
            grouping: starting,
            by: { Group(size: $0.size, version: $0.picture.version) },
        ) {
            manager.startCachingImages(
                for: Self.assets(cached.map(\.picture.asset)), targetSize: Self.target(group.size),
                contentMode: .aspectFit, options: options[group.version],
            )
        }
    }

    private struct Group: Hashable {
        let size: Int
        let version: ApplePhotosImageVersion
    }

    private static var canRead: Bool {
        [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func target(_ size: Int) -> CGSize {
        CGSize(width: size, height: size)
    }

    /// The assets `ids` names, those Photos no longer has left out: burst frames and hidden photos included, as the
    /// library reads them.
    private static func assets(_ ids: [String]) -> [PHAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        let found = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        return found.objects(at: IndexSet(integersIn: 0 ..< found.count))
    }
}
