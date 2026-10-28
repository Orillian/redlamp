import Foundation

/// Whether Redlamp may read Photos, as PhotoKit says (`PHAuthorizationStatus` for read and write, which
/// reading needs).
public enum ApplePhotosAccess: String, Sendable, Hashable, Codable {
    case notDetermined, denied, restricted
    /// Only the photos the person chose: on the Mac, no albums.
    case limited
    case authorized

    public var canRead: Bool {
        self == .limited || self == .authorized
    }
}

/// An album, a smart album, a shared album or a folder in Photos, as the import window's tree shows it.
public struct ApplePhotosCollection: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case album, smartAlbum, sharedAlbum, folder
    }

    /// PhotoKit's local identifier.
    public var id: String
    public var title: String
    public var kind: Kind
    /// The folder it's in; nil at the top.
    public var parent: String?
    /// Photos' own estimate of the assets it holds; nil when Photos doesn't say, and for a folder.
    public var estimatedCount: Int?

    public init(id: String, title: String, kind: Kind, parent: String? = nil, estimatedCount: Int? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.parent = parent
        self.estimatedCount = estimatedCount
    }
}

/// What PhotoKit can tell of an asset, beyond its files: macOS 26 gives the first five, macOS 27 the rest.
public enum ApplePhotosField: String, Sendable, Hashable, Codable, CaseIterable {
    case favorite, date, originalName, albums, location
    case rating, caption, keywords

    /// The fields PhotoKit gives from macOS 27 only (`PHAsset.rating` and `extendedMetadata`).
    public static let fromMacOS27: [ApplePhotosField] = [.rating, .caption, .keywords]
    /// The fields every macOS Redlamp runs on gives.
    public static let everywhere: [ApplePhotosField] = [.favorite, .date, .originalName, .albums, .location]
}

/// One of an asset's files in Photos (`PHAssetResource`).
public struct ApplePhotosResource: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        /// The original: a RAW+JPEG pair's JPEG, a ProRAW's DNG.
        case photo
        /// A RAW+JPEG pair's raw.
        case alternatePhoto
        /// Photos' rendering of its edit.
        case fullSizePhoto
        /// A Live Photo's video.
        case pairedVideo
        /// Anything else: a video's file, edit data, a base for adjustments.
        case other
    }

    public var kind: Kind
    /// Its uniform type identifier: `public.heic`, `com.adobe.raw-image`.
    public var type: String
    public var originalFilename: String
    /// In bytes, when the library says.
    public var size: Int64?
    /// Its size in pixels, when the library says.
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(
        kind: Kind, type: String, originalFilename: String, size: Int64? = nil, pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
    ) {
        self.kind = kind
        self.type = type
        self.originalFilename = originalFilename
        self.size = size
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// A photo or video in Photos (`PHAsset`), with what an import takes from it.
public struct ApplePhotosAsset: Sendable, Hashable, Identifiable {
    public enum MediaType: String, Sendable, Hashable, Codable {
        case image, video, audio, unknown
    }

    public enum Subtype: String, Sendable, Hashable, Codable, CaseIterable {
        case live, hdr, panorama, depthEffect, screenshot, spatial
    }

    public enum Source: String, Sendable, Hashable, Codable {
        /// The person's own library.
        case library
        /// A shared album's: a copy reduced in size, not the original.
        case cloudShared
        /// Synced from a computer by the Finder.
        case synced
    }

    /// Its place in a burst.
    public struct Burst: Sendable, Hashable, Codable {
        public var id: String
        /// The photo Photos shows for the burst.
        public var isKey: Bool
        /// A frame the photographer picked.
        public var isUserPick: Bool

        public init(id: String, isKey: Bool = false, isUserPick: Bool = false) {
            self.id = id
            self.isKey = isKey
            self.isUserPick = isUserPick
        }
    }

    public struct Location: Sendable, Hashable, Codable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// PhotoKit's local identifier: this Mac's name for it.
    public var id: String
    /// Its `PHCloudIdentifier`, the same on every device on one iCloud Photos library; nil without one.
    public var cloud: String?
    /// When it was taken, as Photos has it: a date changed in Photos included.
    public var created: Date?
    public var location: Location?
    public var isFavorite: Bool
    public var isHidden: Bool
    public var mediaType: MediaType
    public var subtypes: Set<Subtype>
    public var burst: Burst?
    public var source: Source
    /// Edited in Photos.
    public var hasAdjustments: Bool
    /// When it was last edited or reverted in Photos (`adjustmentTimestamp`); nil for one never edited.
    public var adjusted: Date?
    /// When its picture or its fields last changed in Photos (`modificationDate`).
    public var modified: Date?
    /// From macOS 27: 0 to 5 stars, nil when PhotoKit doesn't say.
    public var rating: Int?
    public var caption: String?
    public var keywords: [String]?
    /// The chosen collections it's in, by ID.
    public var albums: [String]
    public var resources: [ApplePhotosResource]

    public init(
        id: String, cloud: String? = nil, created: Date? = nil, location: Location? = nil, isFavorite: Bool = false,
        isHidden: Bool = false, mediaType: MediaType = .image, subtypes: Set<Subtype> = [], burst: Burst? = nil,
        source: Source = .library, hasAdjustments: Bool = false, adjusted: Date? = nil, modified: Date? = nil,
        rating: Int? = nil, caption: String? = nil, keywords: [String]? = nil, albums: [String] = [],
        resources: [ApplePhotosResource] = [],
    ) {
        self.id = id
        self.cloud = cloud
        self.created = created
        self.location = location
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.mediaType = mediaType
        self.subtypes = subtypes
        self.burst = burst
        self.source = source
        self.hasAdjustments = hasAdjustments
        self.adjusted = adjusted
        self.modified = modified
        self.rating = rating
        self.caption = caption
        self.keywords = keywords
        self.albums = albums
        self.resources = resources
    }

    public func resource(_ kind: ApplePhotosResource.Kind) -> ApplePhotosResource? {
        resources.first { $0.kind == kind }
    }

    /// The original's files: its photo, and a RAW+JPEG pair's raw.
    public var originals: [ApplePhotosResource] {
        [resource(.photo), resource(.alternatePhoto)].compactMap(\.self)
    }

    /// Photos' rendering of its edit, when it has one.
    public var edit: ApplePhotosResource? {
        hasAdjustments ? resource(.fullSizePhoto) : nil
    }

    /// A RAW+JPEG pair: a raw beside its JPEG or HEIC.
    public var isPair: Bool {
        resource(.photo) != nil && resource(.alternatePhoto).map { ApplePhotosNames.isRaw($0) } == true
    }

    /// Its original is a raw alone: a camera's, or ProRAW's DNG.
    public var isRaw: Bool {
        !isPair && resource(.photo).map(ApplePhotosNames.isRaw) == true
    }

    /// When its picture as Photos shows it last changed (LIB-58): its last edit or revert in Photos, or when it was
    /// taken for one never edited. A favourite, an album or a caption leaves it as it is, so its images aren't made
    /// again for those.
    public var contentVersion: Date {
        adjusted ?? (hasAdjustments ? modified : nil) ?? created ?? Date(timeIntervalSince1970: 0)
    }

    /// Whether the library lists it once its album is kept in place (LIB-58): a photo with an original, not hidden in
    /// Photos, and of a burst its key photo or a frame picked.
    public var isListed: Bool {
        mediaType == .image && !isHidden && burst.map { $0.isKey || $0.isUserPick } != false
            && resource(.photo) != nil
    }
}

/// What changed in Photos since a change token (`PHPersistentChange`), by local identifier, and the token after it.
public struct ApplePhotosChanges: Sendable, Hashable {
    public var inserted: Set<String>
    public var updated: Set<String>
    public var deleted: Set<String>
    /// Albums, smart albums and folders added, changed or removed.
    public var collections: Set<String>
    public var token: Data

    public init(
        inserted: Set<String> = [], updated: Set<String> = [], deleted: Set<String> = [],
        collections: Set<String> = [], token: Data,
    ) {
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
        self.collections = collections
        self.token = token
    }

    /// Nothing changed.
    public var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && deleted.isEmpty && collections.isEmpty
    }
}

/// Which of an asset's pictures an image shows (`PHImageRequestOptionsVersion`).
public enum ApplePhotosImageVersion: String, Sendable, Hashable, Codable {
    /// As Photos shows it, its edit included.
    case current
    /// The original, without Photos' edit.
    case original
}

/// Why reading Photos failed.
public enum ApplePhotosError: Error, Sendable, Hashable, CustomStringConvertible {
    /// Redlamp may not read Photos.
    case noAccess(ApplePhotosAccess)
    /// An asset or collection Photos no longer has, by its local identifier.
    case notFound(String)
    /// An asset's file Photos couldn't give: gone, or its download failed.
    case unavailable(String, String)
    /// An asset's file only in iCloud, which can't be reached (LIB-60).
    case offline(String)
    /// A simulated library's manifest that can't be read.
    case unreadableManifest(String)
    /// Photos no longer has the changes since the token: what's chosen is compared whole instead.
    case expiredToken

    public var description: String {
        switch self {
        case .noAccess(.notDetermined): "Redlamp hasn't been allowed to read Photos yet"
        case .noAccess(.limited): "Redlamp may read only the photos chosen for it, and no albums"
        case .noAccess: "Redlamp isn't allowed to read Photos: System Settings › Privacy & Security › Photos allows it"
        case let .notFound(id): "Photos no longer has \(id)"
        case let .unavailable(name, message): "Photos couldn't give \(name): \(message)"
        case let .offline(name): "iCloud can't be reached, and \(name) is only there"
        case let .unreadableManifest(message): "the simulated library's manifest can't be read: \(message)"
        case .expiredToken: "Photos no longer has its changes since Redlamp last read them"
        }
    }
}

/// What an import from Apple Photos needs from Photos (LIB-54): whether Redlamp may read it, its albums,
/// folders, smart and shared albums, the assets of those chosen with their fields and files, each file
/// written to disk, and notice of changes (LIB-55). PhotoKit gives an app a photo's data, never a path,
/// and Photos is only ever read (DEC-106). `PhotoKitLibrary` is Photos itself; `SimulatedPhotosLibrary`
/// stands in for it where nothing can be given access to Photos.
public protocol ApplePhotosLibrary: Sendable {
    func access() -> ApplePhotosAccess
    /// Asks the person, the first time, and returns what they chose.
    func requestAccess() async -> ApplePhotosAccess
    /// The fields of assets this Mac's PhotoKit gives.
    var fields: Set<ApplePhotosField> { get }
    /// Every album, smart album, shared album and folder, each folder before what's in it.
    func collections() async throws -> [ApplePhotosCollection]
    /// The assets of the collections `ids` names (albums, smart albums and shared albums), each once with the
    /// chosen collections it's in: hidden ones included, and every frame of a burst.
    func assets(in ids: [String]) async throws -> [ApplePhotosAsset]
    /// Writes `asset`'s `resource` to `url`, where nothing is, downloading it from iCloud where it's only
    /// there; `progress` hears of the download, from 0 to 1. Cancelling the task stops it, leaving whatever
    /// was written at `url` for the caller to remove. Throws `ApplePhotosError.offline` when iCloud can't be reached.
    func write(
        _ resource: ApplePhotosResource, of asset: String, to url: URL,
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws
    /// A notice each time Photos changes, until the stream is let go.
    func changes() -> AsyncStream<Void>
    /// The assets `ids` names by local identifier, as `assets(in:)` gives them but with no albums, those Photos no
    /// longer has left out (LIB-58).
    func assets(withIDs ids: [String]) async throws -> [ApplePhotosAsset]
    /// The assets `ids` names, as `assets(withIDs:)` gives them, each with those of the collections `albums` names
    /// that hold it, as `assets(in:)` gives them (LIB-61).
    func assets(withIDs ids: [String], in albums: [String]) async throws -> [ApplePhotosAsset]
    /// The photos the library lists of each of the collections `ids` names (`ApplePhotosAsset.isListed`), by local
    /// identifier, without their fields or files: what following an album needs to see which joined it or left it
    /// (LIB-61).
    func listedIDs(in ids: [String]) async throws -> [String: Set<String>]
    /// Photos' change token now, archived, for `changes(since:)` across launches; nil where Photos gives none.
    func changeToken() -> Data?
    /// What changed since `token`; throws `ApplePhotosError.expiredToken` once Photos no longer has the history.
    func changes(since token: Data) async throws -> ApplePhotosChanges
    /// This Mac's local identifiers of the assets copies were made from (LIB-64), by the local identifier each copy
    /// recorded, given with the cloud identifier it recorded: that identifier where Photos has it, and otherwise the
    /// asset the cloud identifier names, read back as Photos reads one recorded on another Mac or by an earlier
    /// Redlamp,
    /// whose `stringValue` 0.3.4 recorded. Those Photos can't find are left out. Photos maps cloud identifiers in one
    /// batch, at a cost Apple calls high, so only those it doesn't have by their own identifier are read back.
    func localIDs(ofCopies copies: [String: String]) async throws -> [String: String]
}

public extension ApplePhotosLibrary {
    /// Made from `assets(in:)`, an album at a time.
    func listedIDs(in ids: [String]) async throws -> [String: Set<String>] {
        var listed: [String: Set<String>] = [:]
        for id in ids {
            listed[id] = try await Set(assets(in: [id]).filter(\.isListed).map(\.id))
        }
        return listed
    }

    /// Made from `assets(withIDs:)`, and `assets(in:)` an album at a time.
    func assets(withIDs ids: [String], in albums: [String]) async throws -> [ApplePhotosAsset] {
        var holding: [String: [String]] = [:]
        for album in albums {
            for asset in try await assets(in: [album]) {
                holding[asset.id, default: []].append(album)
            }
        }
        return try await assets(withIDs: ids).map { asset in
            var found = asset
            found.albums = holding[asset.id] ?? []
            return found
        }
    }

    /// Made from `assets(withIDs:)`: those Photos has by the identifier recorded, none read back.
    func localIDs(ofCopies copies: [String: String]) async throws -> [String: String] {
        try await Dictionary(assets(withIDs: Array(copies.keys)).map { ($0.id, $0.id) }) { first, _ in first }
    }
}

/// The collection tree as an import uses it: folders' albums, each album's path in Redlamp's collection
/// list, and a collection found by its title, path or ID.
public struct ApplePhotosTree: Sendable, Hashable {
    /// Each folder before what's in it, in Photos' order.
    public let collections: [ApplePhotosCollection]
    private let byID: [String: ApplePhotosCollection]

    public init(_ collections: [ApplePhotosCollection]) {
        self.collections = collections
        byID = Dictionary(collections.map { ($0.id, $0) }) { first, _ in first }
    }

    public subscript(id: String) -> ApplePhotosCollection? {
        byID[id]
    }

    /// What's directly in the folder `id`, or at the top for nil.
    public func children(of id: String?) -> [ApplePhotosCollection] {
        collections.filter { $0.parent == id }
    }

    /// The albums, smart and shared albums `chosen` names, those in a folder it names included, each once in
    /// the tree's order.
    public func albums(in chosen: some Sequence<String>) -> [ApplePhotosCollection] {
        let chosen = Set(chosen)
        return collections.filter { collection in
            guard collection.kind != .folder else { return false }
            var place: String? = collection.id
            while let id = place {
                if chosen.contains(id) {
                    return true
                }
                place = byID[id]?.parent
            }
            return false
        }
    }

    /// The albums an import takes when none are chosen: every album, in folders or not; no smart album, and
    /// no shared album, whose photos are reduced copies.
    public var standardChoice: [String] {
        collections.filter { $0.kind == .album }.map(\.id)
    }

    /// The titles from the top down to collection `id`.
    public func titles(of id: String) -> [String] {
        var titles: [String] = []
        var place: String? = id
        while let id = place, let collection = byID[id] {
            titles.insert(collection.title, at: 0)
            place = collection.parent
        }
        return titles
    }

    /// The collection's path in Redlamp's collection list: Photos' folders as sets, the album a collection.
    public func path(of id: String) -> CollectionPath? {
        CollectionPath(names: titles(of: id))
    }

    /// The collection `text` names: its ID, its path of titles (`Trips/Lisbon`), or its title, ignoring
    /// case, the first in the tree when several share it.
    public func resolve(_ text: String) -> ApplePhotosCollection? {
        if let found = byID[text] {
            return found
        }
        if let path = CollectionPath(text), path.names.count > 1,
           let found = collections.first(where: { self.path(of: $0.id) == path }) {
            return found
        }
        return collections.first { $0.title.caseInsensitiveCompare(text) == .orderedSame }
    }
}

/// How an import names the files it writes from Photos.
enum ApplePhotosNames {
    static func isRaw(_ resource: ApplePhotosResource) -> Bool {
        NamingJob.isRaw(NamingJob.split(resource.originalFilename).ext) || resource.type == "com.adobe.raw-image"
    }

    /// `name` safe in a folder: no slash or colon, not hidden, not empty.
    static func safe(_ name: String) -> String {
        var safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while safe.hasPrefix(".") {
            safe.removeFirst()
        }
        return safe.isEmpty ? "Photo" : safe
    }

    /// The folder an asset's files are staged in: its local identifier, made safe.
    static func folder(of asset: String) -> String {
        safe(asset)
    }

    /// The names an asset's original files get: Photos' own, a RAW+JPEG pair's raw given its photo's stem so
    /// the two stay a pair.
    static func originals(of asset: ApplePhotosAsset) -> [(resource: ApplePhotosResource, name: String)] {
        guard let photo = asset.resource(.photo) else { return [] }
        let name = safe(photo.originalFilename)
        var named = [(photo, name)]
        if let raw = asset.resource(.alternatePhoto) {
            let ext = NamingJob.split(safe(raw.originalFilename)).ext
            named.append((raw, NamingJob.split(name).base + (ext.isEmpty ? "" : "." + ext)))
        }
        return named
    }

    /// The name Photos' rendering of an edit gets: `<name> (Photos edit).<ext>`, after the original's photo,
    /// with the rendering's own extension.
    static func edit(of asset: ApplePhotosAsset) -> (resource: ApplePhotosResource, name: String)? {
        guard let edit = asset.edit, let photo = asset.resource(.photo) else { return nil }
        let base = NamingJob.split(safe(photo.originalFilename)).base
        var ext = NamingJob.split(safe(edit.originalFilename)).ext
        if ext.isEmpty {
            ext = edit.type == "public.heic" ? "heic" : "jpeg"
        }
        return (edit, "\(base) (Photos edit).\(ext)")
    }
}
