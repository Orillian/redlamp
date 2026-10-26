import Foundation
import RedlampDocument
import Synchronization

/// What the library keeps of its imports from Apple Photos (LIB-54), in `Apple Photos.json` in its folder:
/// each import with its albums and settings, the albums followed for their new photos (LIB-55), and each
/// asset imported, by its local identifier, with the paths of its photos. The assets can be rebuilt from the
/// photos' sidecars (`applePhotos`), which name them.
public struct ApplePhotosRecord: Sendable, Hashable, Codable {
    public static let format = "app.redlamp.apple-photos"
    public static let version = 1
    public static let fileName = "Apple Photos.json"

    /// A collection an import took, as it was then.
    public struct Album: Sendable, Hashable, Codable, Identifiable {
        public var id: String
        public var title: String
        public var kind: ApplePhotosCollection.Kind
        /// Its collection's path in the library: `Trips/Lisbon`.
        public var path: String

        public init(id: String, title: String, kind: ApplePhotosCollection.Kind, path: String) {
            self.id = id
            self.title = title
            self.kind = kind
            self.path = path
        }
    }

    public struct Import: Sendable, Hashable, Codable, Identifiable {
        public enum State: String, Sendable, Hashable, Codable {
            /// Its files are being written to its staging folder, or it was cut short there.
            case staging
            /// Copying, or cut short while it copied.
            case copying
            /// Stopped: its staging folder is kept, so the next import of its albums takes up where it was.
            case stopped
            case finished
            case undone
        }

        /// Its staging folder's name.
        public var id: UUID
        public var date: Date
        public var albums: [Album]
        public var settings: ApplePhotosImport.Settings
        /// The card import's plans that copied it, in the order they ran, by their journal IDs.
        public var plans: [UUID] = []
        public var state: State
        /// Assets imported.
        public var photos = 0
    }

    /// An asset imported, and where its photos are.
    public struct Asset: Sendable, Hashable, Codable {
        public var cloud: String?
        /// Its photos' paths: the original's, then its edit's.
        public var paths: [String]
        /// The import that brought it; nil for one found in the sidecars.
        public var importID: UUID?

        public init(cloud: String? = nil, paths: [String], importID: UUID? = nil) {
            self.cloud = cloud
            self.paths = paths
            self.importID = importID
        }
    }

    public var imports: [Import] = []
    /// The albums followed, for the new photos that arrive in them.
    public var followed: [Album] = []
    /// By local identifier.
    public var assets: [String: Asset] = [:]

    public init(imports: [Import] = [], followed: [Album] = [], assets: [String: Asset] = [:]) {
        self.imports = imports
        self.followed = followed
        self.assets = assets
    }

    /// The newest import not taken back.
    public var lastImport: Import? {
        imports.last { $0.state != .undone }
    }

    public func importing(_ id: UUID) -> Import? {
        imports.first { $0.id == id }
    }

    mutating func keep(_ entry: Import) {
        if let place = imports.firstIndex(where: { $0.id == entry.id }) {
            imports[place] = entry
        } else {
            imports.append(entry)
        }
    }

    /// Follows `albums`, those followed already keeping their places and taking their new titles.
    mutating func follow(_ albums: [Album]) {
        for album in albums {
            if let place = followed.firstIndex(where: { $0.id == album.id }) {
                followed[place] = album
            } else {
                followed.append(album)
            }
        }
    }

    /// The assets the sidecars of `photos` name, with those photos' paths, originals first.
    public static func assets(
        inSidecarsOf photos: [URL], locator: SidecarLocator = .besidePhotos,
    ) -> [String: Asset] {
        let store = SidecarStore(locator: locator)
        var found: [String: (asset: Asset, edits: [String])] = [:]
        for photo in photos {
            guard let origin = store.load(for: photo)?.metadata?.applePhotos else { continue }
            var entry = found[origin.id] ?? (Asset(cloud: origin.cloud, paths: []), [])
            entry.asset.cloud = entry.asset.cloud ?? origin.cloud
            if origin.version == .edited {
                entry.edits.append(photo.path)
            } else {
                entry.asset.paths.append(photo.path)
            }
            found[origin.id] = entry
        }
        return found.mapValues { entry in
            var asset = entry.asset
            asset.paths = asset.paths.sorted() + entry.edits.sorted()
            return asset
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, version, imports, followed, assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imports = try container.decodeIfPresent([Import].self, forKey: .imports) ?? []
        followed = try container.decodeIfPresent([Album].self, forKey: .followed) ?? []
        assets = try container.decodeIfPresent([String: Asset].self, forKey: .assets) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.format, forKey: .format)
        try container.encode(Self.version, forKey: .version)
        try container.encode(imports, forKey: .imports)
        try container.encode(followed, forKey: .followed)
        try container.encode(assets, forKey: .assets)
    }
}

/// `Apple Photos.json` in a library's folder, read and written whole, one change at a time.
public struct ApplePhotosRecordFile: Sendable {
    public let url: URL
    private static let lock = Mutex(())

    public init(paths: LibraryPaths) {
        url = paths.root.appending(path: ApplePhotosRecord.fileName)
    }

    /// The record; an empty one when there's no file.
    public func load() throws -> ApplePhotosRecord {
        try Self.lock.withLock { _ in try read() }
    }

    /// Changes the record in one step, written whole in place of the file.
    @discardableResult
    public func change<T>(_ body: (inout ApplePhotosRecord) throws -> T) throws -> T {
        try Self.lock.withLock { _ in
            var record = try read()
            let result = try body(&record)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try encoder.encode(record).write(to: url, options: .atomic)
            return result
        }
    }

    /// Takes the assets the sidecars of `photos` name into the record, those it has already kept as they
    /// are: how a record that was lost is rebuilt.
    @discardableResult
    public func rebuild(fromSidecarsOf photos: [URL], locator: SidecarLocator = .besidePhotos) throws -> Int {
        let found = ApplePhotosRecord.assets(inSidecarsOf: photos, locator: locator)
        return try change { record in
            var added = 0
            for (id, asset) in found where record.assets[id] == nil {
                record.assets[id] = asset
                added += 1
            }
            return added
        }
    }

    private func read() throws -> ApplePhotosRecord {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ApplePhotosRecord()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ApplePhotosRecord.self, from: data)
    }
}
