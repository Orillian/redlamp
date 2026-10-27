import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// A Photos library read from a manifest of collections and assets over files in folders (LIB-54), for the
/// tests, the harness, the CLI's tests and the regression suite, none of which can be given access to Photos.
///
/// The manifest is JSON: `{"format": "app.redlamp.simulated-photos", "version": 1, "macOS": 27, "access":
/// "authorized", "grants": "authorized", "collections": […], "assets": […]}`. `macOS` says which fields its
/// PhotoKit gives (26 by default: ratings, captions and keywords come from 27); `access` is where access
/// stands, and `grants` what asking gives while it's `notDetermined`, both `authorized` by default. A collection is
/// `{"id", "title", "kind": "album" | "smartAlbum" | "sharedAlbum" | "folder", "parent"}`. An asset is
/// `{"id", "cloud", "created", "location": {"latitude", "longitude"}, "favorite", "hidden", "mediaType",
/// "subtypes", "burst": {"id", "key", "userPick"}, "source", "edited", "adjusted", "modified", "rating", "caption",
/// "keywords", "albums": [collection IDs], "imagesInCloud", "resources": [{"kind", "type", "name", "file",
/// "inCloud"}]}`, every key but `id` optional. A resource's `file` is a path from the manifest's folder; `inCloud`
/// makes writing it report a download. An asset without `created` was taken when its first original file records,
/// in the zone it records or this Mac's: a date unchanged in Photos. Its images (`ApplePhotosImages`, LIB-59) are
/// made from its files, but for one `imagesInCloud`, whose Photos keeps none on this Mac.
///
/// Changes made in Photos are scripted (LIB-61): `insert`, `update`, `setAlbums`, `delete`, `add`, `removeCollection`,
/// each kept in a history of changes whose tokens `expireHistory` makes expire, and told to those listening.
public final class SimulatedPhotosLibrary: ApplePhotosLibrary {
    public static let format = "app.redlamp.simulated-photos"

    struct Manifest: Decodable {
        struct Collection: Decodable {
            var id: String
            var title: String
            var kind: ApplePhotosCollection.Kind
            var parent: String?
        }

        struct Resource: Decodable {
            var kind: ApplePhotosResource.Kind
            var type: String?
            var name: String
            var file: String?
            var inCloud: Bool?
        }

        struct Burst: Decodable {
            var id: String
            var key: Bool?
            var userPick: Bool?
        }

        struct Asset: Decodable {
            var id: String
            var cloud: String?
            var created: Date?
            var location: ApplePhotosAsset.Location?
            var favorite: Bool?
            var hidden: Bool?
            var mediaType: ApplePhotosAsset.MediaType?
            var subtypes: [ApplePhotosAsset.Subtype]?
            var burst: Burst?
            var source: ApplePhotosAsset.Source?
            var edited: Bool?
            var adjusted: Date?
            var modified: Date?
            var imagesInCloud: Bool?
            var rating: Int?
            var caption: String?
            var keywords: [String]?
            var albums: [String]?
            var resources: [Resource]?
        }

        var format: String
        var version: Int
        var macOS: Int?
        var access: ApplePhotosAccess?
        var grants: ApplePhotosAccess?
        var collections: [Collection]
        var assets: [Asset]
    }

    /// Where the manifest is, its files' paths from its folder; nil for a library made in memory.
    public let manifest: URL?
    public let fields: Set<ApplePhotosField>
    private let state: Mutex<State>
    /// Names the library in its change tokens.
    private let identity = UUID().uuidString
    /// The images of a library made in memory, which has no files.
    private let given: (@Sendable (ApplePhotosAsset, ApplePhotosImageVersion, Int) -> ApplePhotosImage)?

    /// A file of an asset's, and whether it's only in iCloud.
    private typealias File = (url: URL, inCloud: Bool)

    private struct State {
        var access: ApplePhotosAccess
        var granted: ApplePhotosAccess
        var tree: [ApplePhotosCollection]
        var assets: [ApplePhotosAsset]
        /// Each asset's resources' files, by asset ID and resource name.
        var files: [String: [String: File]]
        /// The assets whose Photos keeps no image on this Mac.
        var imagesInCloud: Set<String>
        var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
        /// The changes recorded, as Photos' persistent history keeps them: a token is how many there were.
        var history: [ApplePhotosChanges] = []
        /// The tokens below it have expired.
        var kept = 0
        /// Each asset's place in `assets`, by ID, made again once an asset comes or goes.
        var places: [String: Int]?
        /// How often each picture was asked for, and what each caching window holds (LIB-59).
        var asked: [ApplePhotosPicture: Int] = [:]
        var cached: [String: Set<ApplePhotosPicture>] = [:]

        mutating func asset(_ id: String) -> ApplePhotosAsset? {
            if places == nil {
                places = Dictionary(assets.enumerated().map { ($1.id, $0) }) { first, _ in first }
            }
            return places?[id].map { assets[$0] }
        }
    }

    /// A library of `assets` in `collections`, with no files, as PhotoKit on `macOS` gives them: for measuring the
    /// index at scale, and with `images` the store's images of its photos.
    public init(
        collections: [ApplePhotosCollection], assets: [ApplePhotosAsset], macOS: Int = 26,
        images: (@Sendable (ApplePhotosAsset, ApplePhotosImageVersion, Int) -> ApplePhotosImage)? = nil,
    ) {
        manifest = nil
        given = images
        fields = Set(ApplePhotosField.everywhere + (macOS >= 27 ? ApplePhotosField.fromMacOS27 : []))
        state = Mutex(State(
            access: .authorized, granted: .authorized, tree: collections, assets: assets, files: [:],
            imagesInCloud: [],
        ))
    }

    /// The library `manifest` describes; `macOS` stands in for the manifest's own, for a test of what each
    /// version gives.
    public init(manifest: URL, macOS: Int? = nil) throws {
        let data: Data
        do {
            data = try Data(contentsOf: manifest)
        } catch {
            throw ApplePhotosError.unreadableManifest("\(manifest.path): \(error.localizedDescription)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read: Manifest
        do {
            read = try decoder.decode(Manifest.self, from: data)
        } catch {
            throw ApplePhotosError.unreadableManifest("\(manifest.path): \(error)")
        }
        guard read.format == Self.format else {
            throw ApplePhotosError.unreadableManifest("\(manifest.path) isn't a simulated Photos library")
        }
        self.manifest = manifest
        given = nil
        let version = macOS ?? read.macOS ?? 26
        fields = Set(ApplePhotosField.everywhere + (version >= 27 ? ApplePhotosField.fromMacOS27 : []))
        let folder = manifest.deletingLastPathComponent()
        let tree = read.collections.map { collection in
            ApplePhotosCollection(
                id: collection.id, title: collection.title, kind: collection.kind, parent: collection.parent,
            )
        }
        var files: [String: [String: File]] = [:]
        let assets = read.assets.map { entry in
            var resources: [ApplePhotosResource] = []
            for resource in entry.resources ?? [] {
                let url = resource.file.map { folder.appending(path: $0).standardizedFileURL }
                let size = url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init)
                resources.append(ApplePhotosResource(
                    kind: resource.kind, type: resource.type ?? Self.type(of: resource.name),
                    originalFilename: resource.name, size: size,
                ))
                if let url {
                    files[entry.id, default: [:]][resource.name] = (url, resource.inCloud ?? false)
                }
            }
            let given = { (field: ApplePhotosField) in version >= 27 && ApplePhotosField.fromMacOS27.contains(field) }
            var asset = ApplePhotosAsset(
                id: entry.id, cloud: entry.cloud, created: entry.created, location: entry.location,
                isFavorite: entry.favorite ?? false, isHidden: entry.hidden ?? false,
                mediaType: entry.mediaType ?? .image, subtypes: Set(entry.subtypes ?? []),
                burst: entry.burst.map {
                    ApplePhotosAsset.Burst(id: $0.id, isKey: $0.key ?? false, isUserPick: $0.userPick ?? false)
                },
                source: entry.source ?? .library, hasAdjustments: entry.edited ?? false, adjusted: entry.adjusted,
                modified: entry.modified ?? entry.adjusted, rating: given(.rating) ? entry.rating ?? 0 : nil,
                caption: given(.caption) ? entry.caption : nil,
                keywords: given(.keywords) ? entry.keywords ?? [] : nil, albums: entry.albums ?? [],
                resources: resources,
            )
            if asset.created == nil {
                let original = asset.resource(.alternatePhoto) ?? asset.resource(.photo)
                asset.created = original.flatMap { files[entry.id]?[$0.originalFilename]?.url }
                    .flatMap(Self.recordedInstant)
            }
            return asset
        }
        state = Mutex(State(
            access: read.access ?? .authorized, granted: read.grants ?? .authorized, tree: tree, assets: assets,
            files: files, imagesInCloud: Set(read.assets.filter { $0.imagesInCloud == true }.map(\.id)),
        ))
    }

    public func access() -> ApplePhotosAccess {
        state.withLock(\.access)
    }

    public func requestAccess() async -> ApplePhotosAccess {
        state.withLock { state in
            if state.access == .notDetermined {
                state.access = state.granted
            }
            return state.access
        }
    }

    public func collections() async throws -> [ApplePhotosCollection] {
        try requireAlbums()
        let (tree, assets) = state.withLock { ($0.tree, $0.assets) }
        var counts: [String: Int] = [:]
        for asset in assets {
            for album in asset.albums {
                counts[album, default: 0] += 1
            }
        }
        return tree.map { collection in
            var counted = collection
            counted.estimatedCount = collection.kind == .folder ? nil : counts[collection.id] ?? 0
            return counted
        }
    }

    public func assets(in ids: [String]) async throws -> [ApplePhotosAsset] {
        try requireAlbums()
        let assets = state.withLock(\.assets)
        let chosen = Set(ids)
        var found: [ApplePhotosAsset] = []
        var bursts = Set<String>()
        for asset in assets where asset.albums.contains(where: chosen.contains) {
            var asset = asset
            asset.albums = asset.albums.filter(chosen.contains)
            if let burst = asset.burst {
                bursts.insert(burst.id)
            }
            found.append(asset)
        }
        let albumsOfBursts = Dictionary(grouping: found.filter { $0.burst?.isKey == true }) { $0.burst?.id ?? "" }
            .mapValues { $0.flatMap(\.albums) }
        let present = Set(found.map(\.id))
        for asset in assets where !present.contains(asset.id) {
            guard let burst = asset.burst, bursts.contains(burst.id) else { continue }
            var frame = asset
            frame.albums = albumsOfBursts[burst.id] ?? []
            found.append(frame)
        }
        return found
    }

    public func write(
        _ resource: ApplePhotosResource, of asset: String, to url: URL,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws {
        try requireAlbums()
        guard let file = state.withLock({ $0.files[asset]?[resource.originalFilename] }) else {
            throw ApplePhotosError.unavailable(resource.originalFilename, "the manifest names no file for it")
        }
        if file.inCloud {
            for step in 1 ... 4 {
                try Task.checkCancellation()
                progress(Double(step) / 4)
                await Task.yield()
            }
        }
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
        }
        do {
            try FileManager.default.copyItem(at: file.url, to: url)
        } catch {
            throw ApplePhotosError.unavailable(resource.originalFilename, error.localizedDescription)
        }
    }

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let id = UUID()
        state.withLock { $0.observers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.observers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Tells those listening that Photos changed, as PhotoKit's change observer does.
    public func simulateChange() {
        for observer in state.withLock({ Array($0.observers.values) }) {
            observer.yield()
        }
    }

    public func assets(withIDs ids: [String]) async throws -> [ApplePhotosAsset] {
        try await assets(withIDs: ids, in: [])
    }

    /// A burst's frames are in the albums its key photo is in, as `assets(in:)` gives them.
    public func assets(withIDs ids: [String], in albums: [String]) async throws -> [ApplePhotosAsset] {
        try requireAlbums()
        let assets = state.withLock(\.assets)
        let (wanted, kept) = (Set(ids), Set(albums))
        let keys = Dictionary(assets.compactMap { asset in
            asset.burst.flatMap { $0.isKey ? ($0.id, asset.albums) : nil }
        }) { first, _ in first }
        return assets.filter { wanted.contains($0.id) }.map { asset in
            var found = asset
            let holding = asset.burst.flatMap { $0.isKey ? nil : keys[$0.id] } ?? asset.albums
            found.albums = holding.filter(kept.contains)
            return found
        }
    }

    /// How many changes there were, after this library's name: another library's tokens have expired here, as another
    /// System Photo Library's do in PhotoKit.
    public func changeToken() -> Data? {
        token(state.withLock(\.history.count))
    }

    private func token(_ count: Int) -> Data {
        Data("\(identity) \(count)".utf8)
    }

    public func changes(since token: Data) async throws -> ApplePhotosChanges {
        try requireAlbums()
        let parts = String(decoding: token, as: UTF8.self).split(separator: " ")
        return try state.withLock { state in
            guard parts.count == 2, parts[0] == identity, let since = Int(parts[1]), since >= state.kept,
                  since <= state.history.count
            else { throw ApplePhotosError.expiredToken }
            var changes = ApplePhotosChanges(token: self.token(state.history.count))
            for change in state.history[since...] {
                changes.inserted.formUnion(change.inserted)
                changes.updated.formUnion(change.updated)
                changes.deleted.formUnion(change.deleted)
                changes.collections.formUnion(change.collections)
            }
            return changes
        }
    }

    /// Records a change in Photos' history, by local identifier, and tells those listening; `expiring` forgets the
    /// history before it, so the tokens given before expire.
    public func recordChange(
        inserted: Set<String> = [], updated: Set<String> = [], deleted: Set<String> = [],
        collections: Set<String> = [], expiring: Bool = false,
    ) {
        state.withLock { state in
            state.history.append(ApplePhotosChanges(
                inserted: inserted, updated: updated, deleted: deleted, collections: collections, token: Data(),
            ))
            if expiring {
                state.kept = state.history.count
            }
        }
        simulateChange()
    }

    // MARK: - Changes made in Photos (LIB-61)

    /// Adds `asset` to Photos in the collections its `albums` name, `files` its resources' files by name, as a photo
    /// imported into Photos or saved to an album: recorded as the asset inserted and those collections changed.
    public func insert(_ asset: ApplePhotosAsset, files: [String: URL] = [:]) {
        state.withLock { state in
            state.assets.removeAll { $0.id == asset.id }
            state.assets.append(asset)
            state.places = nil
            state.files[asset.id] = files.isEmpty ? nil : files.mapValues { ($0, false) }
        }
        recordChange(inserted: [asset.id], collections: Set(asset.albums))
    }

    /// Changes asset `id` as `change` says, as editing it in Photos does: its fields, an edit (`hasAdjustments`,
    /// `adjusted` and a `fullSizePhoto` resource) or its revert, a cloud identifier once iCloud Photos has it.
    /// Recorded as the asset updated; the albums it's in are `setAlbums(of:to:)`'s.
    public func update(_ id: String, _ change: (inout ApplePhotosAsset) -> Void) {
        state.withLock { state in
            guard let at = state.assets.firstIndex(where: { $0.id == id }) else { return }
            let albums = state.assets[at].albums
            change(&state.assets[at])
            state.assets[at].albums = albums
        }
        recordChange(updated: [id])
    }

    /// Puts asset `id` in the collections `albums` names, as adding it to an album or taking it out does: recorded as
    /// the collections it joined or left changed, the asset itself not.
    public func setAlbums(of id: String, to albums: [String]) {
        let changed = state.withLock { state -> Set<String> in
            guard let at = state.assets.firstIndex(where: { $0.id == id }) else { return [] }
            let before = Set(state.assets[at].albums)
            state.assets[at].albums = albums
            return before.symmetricDifference(albums)
        }
        recordChange(collections: changed)
    }

    /// Deletes the assets `ids` from Photos: recorded as deleted, with the collections they were in.
    public func delete(_ ids: [String]) {
        let wanted = Set(ids)
        let albums = state.withLock { state -> Set<String> in
            let leaving = state.assets.filter { wanted.contains($0.id) }
            state.assets.removeAll { wanted.contains($0.id) }
            state.places = nil
            return Set(leaving.flatMap(\.albums))
        }
        recordChange(deleted: wanted, collections: albums)
    }

    /// Adds `collection` to Photos, or replaces the one with its ID, as making an album or renaming one does.
    public func add(_ collection: ApplePhotosCollection) {
        state.withLock { state in
            if let at = state.tree.firstIndex(where: { $0.id == collection.id }) {
                state.tree[at] = collection
            } else {
                state.tree.append(collection)
            }
        }
        recordChange(collections: Set([collection.id] + [collection.parent].compactMap(\.self)))
    }

    /// Deletes collection `id` from Photos, the photos in it staying in Photos, as deleting an album does.
    public func removeCollection(_ id: String) {
        let parent = state.withLock { state -> String? in
            let parent = state.tree.first { $0.id == id }?.parent
            state.tree.removeAll { $0.id == id }
            for at in state.assets.indices {
                state.assets[at].albums.removeAll { $0 == id }
            }
            return parent
        }
        recordChange(collections: Set([id] + [parent].compactMap(\.self)))
    }

    /// Forgets the history so far, as Photos does after a while: the tokens given before it expire.
    public func expireHistory() {
        recordChange(expiring: true)
    }

    /// Reading albums needs full access: PhotoKit gives a limited app none.
    private func requireAlbums() throws {
        let access = access()
        guard access == .authorized else { throw ApplePhotosError.noAccess(access) }
    }

    /// The instant a file records it was taken, in the zone it records or this Mac's.
    private static func recordedInstant(_ url: URL) -> Date? {
        guard let metadata = PhotoMetadataReader.read(url: url), let captured = metadata.captured else { return nil }
        let offset = metadata.capturedOffset ?? TimeZone.current.secondsFromGMT(for: captured)
        return captured.addingTimeInterval(-Double(offset))
    }

    private static func type(of name: String) -> String {
        switch NamingJob.split(name).ext.lowercased() {
        case "heic", "heif": "public.heic"
        case "jpg", "jpeg", "jpe": "public.jpeg"
        case "png": "public.png"
        case "tif", "tiff": "public.tiff"
        case "dng": "com.adobe.raw-image"
        case "mov": "com.apple.quicktime-movie"
        case "mp4": "public.mpeg-4"
        case let ext where NamingJob.isRaw(ext): "public.camera-raw-image"
        default: "public.data"
        }
    }
}

extension SimulatedPhotosLibrary: ApplePhotosImages {
    /// Made from the file of the picture asked for, Photos' edit's for the current one, as Photos makes its own; none
    /// for an asset `imagesInCloud`. A library made in memory gives the images it was given.
    public func image(of asset: String, version: ApplePhotosImageVersion, size: Int) -> ApplePhotosImage {
        let (found, files, inCloud) = state.withLock { state in
            state.asked[ApplePhotosPicture(asset: asset, version: version), default: 0] += 1
            return (state.asset(asset), state.files[asset], state.imagesInCloud.contains(asset))
        }
        guard access() == .authorized, let found else { return .unavailable }
        if let given {
            return given(found, version, size)
        }
        guard !inCloud else { return .inCloud }
        let resource = version == .current ? found.edit ?? found.resource(.photo) : found.resource(.photo)
        guard let resource, let url = files?[resource.originalFilename]?.url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max(size, 1),
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return .unavailable }
        return .image(image)
    }

    public func cache(_ pictures: Set<ApplePhotosPicture>, size _: Int, window: String) {
        state.withLock { $0.cached[window] = pictures.isEmpty ? nil : pictures }
    }

    /// How many times each picture was asked for, for the tests.
    public var askedImages: [ApplePhotosPicture: Int] {
        state.withLock(\.asked)
    }

    /// What each caching window holds, for the tests.
    public var cachedImages: [String: Set<ApplePhotosPicture>] {
        state.withLock(\.cached)
    }
}
