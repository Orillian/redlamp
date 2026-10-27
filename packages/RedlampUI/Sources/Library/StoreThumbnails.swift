import CoreGraphics
import Foundation
import ImageIO
import RedlampEngineAPI
import RedlampLibrary

/// The filmstrip's thumbnails of the library's photos (LIB-09): from the store's grid tier, made
/// for it first when it hasn't one yet, as the indexer makes them. A raw's comes from LibRaw's
/// smallest embedded preview big enough for the grid (`thumbnail`, the engine's), anything else's
/// from ImageIO. An edited photo's, once its edit is rendered, is that render's (`EditRenders`).
/// A photo left in Apple Photos has no file to make them from: its thumbnail and preview are made
/// from Photos' own images (`photos`, LIB-59).
public struct StoreThumbnails: Sendable {
    public let store: PhotoStore
    public let maker: StoreThumbnailMaker
    /// Makes the store's images of photos left in Apple Photos; nil where the library keeps none.
    public let photos: ApplePhotosThumbnailMaker?

    /// `thumbnail` is the engine's `decodeThumbnail(for:maxPixelSize:)`.
    public init(
        store: PhotoStore, thumbnail: @escaping @Sendable (URL, Int) -> CGImage?,
        photos: ApplePhotosThumbnailMaker? = nil,
    ) {
        self.store = store
        maker = StoreThumbnailMaker(store: store, image: Self.source(thumbnail))
        self.photos = photos
    }

    /// Whether `photo` is left in Apple Photos, so its images come from Photos rather than its file.
    public func isInApplePhotos(_ photo: URL) -> Bool {
        photos?.owns(photo) == true
    }

    /// A photo left in Apple Photos (LIB-59): its `tier`, at most `pixelSize` on its long edge, from the store's record
    /// of the row as it is (`size` bytes, its content version `modified`), made there from Photos' image first when the
    /// store has none. Nil when it can't be had, and whether that's because Photos keeps none on this Mac without
    /// iCloud. It blocks: only ever off the main thread.
    public func fromPhotos(
        _ photo: URL, key: ContentKey, tier: PhotoStore.Tier, size: Int64, modified: Date, pixelSize: Int,
    ) -> (image: CGImage?, inCloud: Bool) {
        if let data = store.data(for: key, tier: tier, size: size, modified: modified) {
            return (Self.decode(data, pixelSize: pixelSize), false)
        }
        guard let photos else { return (nil, false) }
        switch photos.make(photo, key: key, tier: tier, size: size, modified: modified) {
        case .stored:
            return (
                store.data(for: key, tier: tier, size: size, modified: modified)
                    .flatMap { Self.decode($0, pixelSize: pixelSize) },
                false,
            )
        case .inCloud:
            return (nil, true)
        case .unavailable:
            return (nil, false)
        }
    }

    /// The image the store keeps of a photo: the engine's thumbnail for raws and focus stacks, which
    /// ImageIO can't read the way LibRaw does, ImageIO's for the rest.
    static func source(_ thumbnail: @escaping @Sendable (URL, Int) -> CGImage?) -> StoreThumbnailMaker.ImageSource {
        { photo, bytes, maxPixelSize in
            if SupportedFormats.isRaw(photo) || SupportedFormats.isStack(photo) {
                return thumbnail(photo, maxPixelSize)
            }
            return StoreThumbnailMaker.imageIO(photo, bytes, maxPixelSize)
        }
    }

    /// The photo's thumbnail at most `pixelSize` on its long edge, from the store's record of the
    /// file as it is (`size` bytes, modified at `modified`), made first when the store has none;
    /// nil when it can't be made. It blocks: only ever off the main thread.
    public func image(for photo: URL, key: ContentKey, size: Int64, modified: Date, pixelSize: Int) -> CGImage? {
        if let data = store.data(for: key, tier: .grid, size: size, modified: modified) {
            return Self.decode(data, pixelSize: pixelSize)
        }
        if isInApplePhotos(photo) {
            return fromPhotos(photo, key: key, tier: .grid, size: size, modified: modified, pixelSize: pixelSize).image
        }
        guard maker.make(photo, key: key, head: Data()),
              let data = store.data(for: key, tier: .grid, size: size, modified: modified)
        else { return nil }
        return Self.decode(data, pixelSize: pixelSize)
    }

    /// The photo's `tier` showing `edit`, at most `pixelSize` on its long edge, from the store's render of
    /// it (LIB-17) for the file as it is (`size` bytes, modified at `modified`); nil when the store has
    /// none. It blocks: only ever off the main thread.
    public func image(
        for key: ContentKey, tier: PhotoStore.Tier, edit: EditDigest, size: Int64, modified: Date, pixelSize: Int,
    ) -> CGImage? {
        store.data(for: key, tier: tier, edit: edit, size: size, modified: modified)
            .flatMap { Self.decode($0, pixelSize: pixelSize) }
    }

    /// A stored image decoded now, at most `pixelSize` on its long edge, as `StoreImageEncoder.decode`
    /// decodes: as a thumbnail, which ImageIO decodes on every thread at once.
    static func decode(_ data: Data, pixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
