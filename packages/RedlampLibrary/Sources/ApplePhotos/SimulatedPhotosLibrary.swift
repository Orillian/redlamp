import Foundation
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
/// "subtypes", "burst": {"id", "key", "userPick"}, "source", "edited", "rating", "caption", "keywords",
/// "albums": [collection IDs], "resources": [{"kind", "type", "name", "file", "inCloud"}]}`, every key but
/// `id` optional. A resource's `file` is a path from the manifest's folder; `inCloud` makes writing it report
/// a download. An asset without `created` was taken when its first original file records, in the zone it
/// records or this Mac's: a date unchanged in Photos.
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

    /// Where the manifest is; its files' paths are from its folder.
    public let manifest: URL
    public let fields: Set<ApplePhotosField>
    private let tree: [ApplePhotosCollection]
    private let assets: [ApplePhotosAsset]
    /// Each asset's resources' files, by asset ID and resource name, and whether each is only in iCloud.
    private let files: [String: [String: (url: URL, inCloud: Bool)]]
    private let state: Mutex<State>

    private struct State {
        var access: ApplePhotosAccess
        var granted: ApplePhotosAccess
        var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
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
        let version = macOS ?? read.macOS ?? 26
        fields = Set(ApplePhotosField.everywhere + (version >= 27 ? ApplePhotosField.fromMacOS27 : []))
        let folder = manifest.deletingLastPathComponent()
        var counts: [String: Int] = [:]
        for asset in read.assets {
            for album in asset.albums ?? [] {
                counts[album, default: 0] += 1
            }
        }
        tree = read.collections.map { collection in
            ApplePhotosCollection(
                id: collection.id, title: collection.title, kind: collection.kind, parent: collection.parent,
                estimatedCount: collection.kind == .folder ? nil : counts[collection.id] ?? 0,
            )
        }
        var files: [String: [String: (url: URL, inCloud: Bool)]] = [:]
        assets = read.assets.map { entry in
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
                source: entry.source ?? .library, hasAdjustments: entry.edited ?? false,
                rating: given(.rating) ? entry.rating ?? 0 : nil, caption: given(.caption) ? entry.caption : nil,
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
        self.files = files
        state = Mutex(State(access: read.access ?? .authorized, granted: read.grants ?? .authorized))
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
        return tree
    }

    public func assets(in ids: [String]) async throws -> [ApplePhotosAsset] {
        try requireAlbums()
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
        guard let file = files[asset]?[resource.originalFilename] else {
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
