import Foundation
import Photos
import Synchronization
import UniformTypeIdentifiers

/// The System Photo Library through PhotoKit (LIB-54), only ever read (DEC-106): its albums, folders, smart
/// and shared albums, their assets with their fields and files, each file written by
/// `PHAssetResourceManager`, downloaded from iCloud where it's only there, and Photos' changes as
/// `PHPhotoLibraryChangeObserver` hears of them.
public final class PhotoKitLibrary: ApplePhotosLibrary {
    public init() {}

    public var fields: Set<ApplePhotosField> {
        var fields = Set(ApplePhotosField.everywhere)
        if #available(macOS 27, iOS 27, *), Self.hasMacOS27Fields {
            fields.formUnion(ApplePhotosField.fromMacOS27)
        }
        return fields
    }

    // MARK: - Access

    public func access() -> ApplePhotosAccess {
        Self.access(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAccess() async -> ApplePhotosAccess {
        await Self.access(PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    static func access(_ status: PHAuthorizationStatus) -> ApplePhotosAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .limited: .limited
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    private func requireAccess() throws {
        let access = access()
        guard access.canRead else { throw ApplePhotosError.noAccess(access) }
    }

    // MARK: - Collections

    public func collections() async throws -> [ApplePhotosCollection] {
        try requireAccess()
        var found: [ApplePhotosCollection] = []
        func walk(_ result: PHFetchResult<PHCollection>, parent: String?) {
            result.enumerateObjects { collection, _, _ in
                if let list = collection as? PHCollectionList {
                    found.append(ApplePhotosCollection(
                        id: list.localIdentifier, title: list.localizedTitle ?? "", kind: .folder, parent: parent,
                    ))
                    walk(PHCollection.fetchCollections(in: list, options: nil), parent: list.localIdentifier)
                } else if let album = collection as? PHAssetCollection, Self.isListed(album) {
                    found.append(Self.collection(album, parent: parent))
                }
            }
        }
        walk(PHCollectionList.fetchTopLevelUserCollections(with: nil), parent: nil)
        var listed = Set(found.map(\.id))
        for (type, subtype) in [
            (PHAssetCollectionType.smartAlbum, PHAssetCollectionSubtype.any),
            (.album, .albumCloudShared),
        ] {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: subtype, options: nil)
                .enumerateObjects { album, _, _ in
                    if Self.isListed(album), listed.insert(album.localIdentifier).inserted {
                        found.append(Self.collection(album, parent: nil))
                    }
                }
        }
        return found
    }

    /// Hidden photos come with an option, not as an album; Recently Deleted is never listed.
    private static func isListed(_ album: PHAssetCollection) -> Bool {
        album.assetCollectionSubtype != .smartAlbumAllHidden
    }

    private static func collection(_ album: PHAssetCollection, parent: String?) -> ApplePhotosCollection {
        let kind: ApplePhotosCollection.Kind = switch album.assetCollectionType {
        case .smartAlbum: .smartAlbum
        case .album where album.assetCollectionSubtype == .albumCloudShared: .sharedAlbum
        default: .album
        }
        let count = album.estimatedAssetCount
        return ApplePhotosCollection(
            id: album.localIdentifier, title: album.localizedTitle ?? "", kind: kind, parent: parent,
            estimatedCount: count == NSNotFound ? nil : count,
        )
    }

    // MARK: - Assets

    public func assets(in ids: [String]) async throws -> [ApplePhotosAsset] {
        try requireAccess()
        let albums = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: ids, options: nil)
        var found: [String: PHAsset] = [:]
        var order: [String] = []
        var albumsOf: [String: [String]] = [:]
        albums.enumerateObjects { album, _, _ in
            PHAsset.fetchAssets(in: album, options: Self.fetchOptions(allBursts: false))
                .enumerateObjects { asset, _, _ in
                    let id = asset.localIdentifier
                    if found.updateValue(asset, forKey: id) == nil {
                        order.append(id)
                    }
                    albumsOf[id, default: []].append(album.localIdentifier)
                }
        }
        for id in order {
            guard let key = found[id], key.representsBurst, let burst = key.burstIdentifier else { continue }
            PHAsset.fetchAssets(withBurstIdentifier: burst, options: Self.fetchOptions(allBursts: true))
                .enumerateObjects { frame, _, _ in
                    let frameID = frame.localIdentifier
                    guard found[frameID] == nil else { return }
                    found[frameID] = frame
                    order.append(frameID)
                    albumsOf[frameID] = albumsOf[id]
                }
        }
        let clouds = cloudIdentifiers(order)
        return order.compactMap { id in
            found[id].map { Self.asset($0, cloud: clouds[id], albums: albumsOf[id] ?? []) }
        }
    }

    private static func fetchOptions(allBursts: Bool) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = allBursts
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        #if compiler(>=6.4)
            if #available(macOS 27, iOS 27, *) {
                options.prefetchAssetExtendedMetadata = true
            }
        #endif
        return options
    }

    /// The assets' cloud identifiers, by local identifier, for those that have one.
    private func cloudIdentifiers(_ ids: [String]) -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        var clouds: [String: String] = [:]
        for (id, result) in PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: ids) {
            if case let .success(cloud) = result {
                clouds[id] = cloud.stringValue
            }
        }
        return clouds
    }

    private static func asset(_ asset: PHAsset, cloud: String?, albums: [String]) -> ApplePhotosAsset {
        let mediaType: ApplePhotosAsset.MediaType = switch asset.mediaType {
        case .image: .image
        case .video: .video
        case .audio: .audio
        default: .unknown
        }
        var subtypes = Set<ApplePhotosAsset.Subtype>()
        for (subtype, mine) in [
            (PHAssetMediaSubtype.photoLive, ApplePhotosAsset.Subtype.live), (.photoHDR, .hdr),
            (.photoPanorama, .panorama), (.photoDepthEffect, .depthEffect), (.photoScreenshot, .screenshot),
            (.spatialMedia, .spatial),
        ] where asset.mediaSubtypes.contains(subtype) {
            subtypes.insert(mine)
        }
        let source: ApplePhotosAsset.Source = switch asset.sourceType {
        case .typeCloudShared: .cloudShared
        case .typeiTunesSynced: .synced
        default: .library
        }
        var found = ApplePhotosAsset(
            id: asset.localIdentifier, cloud: cloud, created: asset.creationDate,
            location: asset.location.map {
                ApplePhotosAsset.Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            isFavorite: asset.isFavorite, isHidden: asset.isHidden, mediaType: mediaType, subtypes: subtypes,
            burst: asset.burstIdentifier.map { burst in
                ApplePhotosAsset.Burst(
                    id: burst, isKey: asset.representsBurst, isUserPick: asset.burstSelectionTypes.contains(.userPick),
                )
            },
            source: source, hasAdjustments: asset.hasAdjustments, albums: albums,
            resources: PHAssetResource.assetResources(for: asset).map(resource),
        )
        if #available(macOS 27, iOS 27, *) {
            readMacOS27Fields(of: asset, into: &found)
        }
        return found
    }

    /// Whether this build's SDK has PhotoKit's macOS 27 fields.
    private static var hasMacOS27Fields: Bool {
        #if compiler(>=6.4)
            true
        #else
            false
        #endif
    }

    /// The rating, caption and keywords macOS 27 gives (`PHAsset.rating`, `PHAsset.extendedMetadata`).
    @available(macOS 27, iOS 27, *)
    private static func readMacOS27Fields(of asset: PHAsset, into found: inout ApplePhotosAsset) {
        // Built only with an SDK that has them: Xcode 26's (macOS 26.5) doesn't.
        #if compiler(>=6.4)
            found.rating = switch asset.rating {
            case .one: 1
            case .two: 2
            case .three: 3
            case .four: 4
            case .five: 5
            default: 0
            }
            if let metadata = asset.extendedMetadata {
                found.caption = metadata.caption
                found.keywords = Array(metadata.keywords)
            } else {
                found.keywords = []
            }
        #endif
    }

    private static func resource(_ resource: PHAssetResource) -> ApplePhotosResource {
        let kind: ApplePhotosResource.Kind = switch resource.type {
        case .photo: .photo
        case .alternatePhoto: .alternatePhoto
        case .fullSizePhoto: .fullSizePhoto
        case .pairedVideo: .pairedVideo
        default: .other
        }
        return ApplePhotosResource(
            kind: kind, type: resource.contentType.identifier, originalFilename: resource.originalFilename,
        )
    }

    // MARK: - Files

    /// Written through `requestData`, chunk by chunk, so Stop cancels a download from iCloud:
    /// `writeData(for:toFile:options:)` gives nothing to cancel it by.
    public func write(
        _ resource: ApplePhotosResource, of asset: String, to url: URL,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        try requireAccess()
        guard let found = PHAsset.fetchAssets(
            withLocalIdentifiers: [asset],
            options: Self.fetchOptions(allBursts: true),
        )
        .firstObject
        else { throw ApplePhotosError.notFound(asset) }
        let resources = PHAssetResource.assetResources(for: found)
        guard let source = resources.first(where: {
            Self.resource($0).kind == resource.kind && $0.originalFilename == resource.originalFilename
        }) ?? resources.first(where: { Self.resource($0).kind == resource.kind })
        else { throw ApplePhotosError.unavailable(resource.originalFilename, "Photos has no such file for it") }
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url)
        else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { fraction in progress(fraction) }
        let failure = Mutex<(any Error)?>(nil)
        let request = Mutex<PHAssetResourceDataRequestID?>(nil)
        let cancelled = Cancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let id = PHAssetResourceManager.default().requestData(for: source, options: options) { data in
                    do {
                        try handle.write(contentsOf: data)
                    } catch {
                        failure.withLock { $0 = $0 ?? error }
                    }
                } completionHandler: { error in
                    try? handle.close()
                    if let error = error ?? failure.withLock({ $0 }) {
                        continuation.resume(throwing: cancelled.isSet ? CancellationError() : error)
                    } else {
                        continuation.resume()
                    }
                }
                request.withLock { $0 = id }
            }
        } onCancel: {
            cancelled.set()
            if let id = request.withLock({ $0 }) {
                PHAssetResourceManager.default().cancelDataRequest(id)
            }
        }
    }

    // MARK: - Changes

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let observer = ChangeObserver(continuation)
        PHPhotoLibrary.shared().register(observer)
        continuation.onTermination = { _ in PHPhotoLibrary.shared().unregisterChangeObserver(observer) }
        return stream
    }

    private final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
        let continuation: AsyncStream<Void>.Continuation

        init(_ continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }

        func photoLibraryDidChange(_: PHChange) {
            continuation.yield()
        }
    }
}
