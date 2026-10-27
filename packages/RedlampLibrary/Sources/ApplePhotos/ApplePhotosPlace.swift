import CryptoKit
import Foundation

/// Where a photo left in Apple Photos is in the library (LIB-58, DEC-107): a folder per asset in Redlamp's cache,
/// `Apple Photos/System/<asset key>/<name>`, where its original lands once it's downloaded, so its address stays a
/// path the library and the editor know; its sidecars on this Mac, at `Sidecars/apple-photos/System/<asset key>/`,
/// the layout Redlamp's iCloud Drive container would use.
public enum ApplePhotosPlace {
    /// The library's name for the volume the Apple Photos root is on, and the folder its sidecars are in on this Mac.
    public static let volume = "apple-photos"
    /// The System Photo Library's folder below the cache and the sidecars: the only library PhotoKit reads.
    public static let library = "System"

    /// An asset's key: the first 16 bytes of SHA-256 over its cloud identifier's archival string, in hexadecimal, or
    /// over `local:` and its local identifier while it has none (iCloud Photos off, or not synced yet). Safe in a path,
    /// where cloud identifiers' colons and local identifiers' slashes aren't, and derived again from the identifier.
    public static func key(cloud: String?, local: String) -> String {
        let digest = SHA256.hash(data: Data((cloud ?? "local:" + local).utf8))
        var hex = [UInt8]()
        hex.reserveCapacity(32)
        for byte in digest.prefix(16) {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: hex, as: UTF8.self)
    }

    private static let digits = Array("0123456789abcdef".utf8)

    /// The Apple Photos root of the library at `paths`.
    public static func root(in paths: LibraryPaths) -> URL {
        paths.applePhotos.appending(path: library, directoryHint: .isDirectory)
    }

    /// A UUID derived from `text`, for the stacks Photos makes (an edit over its original, a burst's frames), so
    /// each is the same however often the index is made again.
    static func stackID(_ text: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(("stack:" + text).utf8)).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 0x0F) | 0x50, bytes[7],
            (bytes[8] & 0x3F) | 0x80, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
    }
}

/// A row of the Apple Photos root as `photo_assets` names it: its asset, which of the asset's files it is, and what of
/// the asset its images and fields were made from.
public struct ApplePhotosRow: Sendable, Hashable {
    public enum Resource: Int, Sendable, Hashable, CaseIterable {
        /// The original's photo: a RAW+JPEG pair's JPEG or HEIC, a ProRAW's DNG.
        case original = 0
        /// A RAW+JPEG pair's raw.
        case alternate = 1
        /// Photos' rendering of its edit.
        case edit = 2
    }

    public var photo: Int64
    public var local: String
    public var cloud: String?
    public var key: String
    public var resource: Resource
    /// When the picture it shows last changed (`ApplePhotosAsset.contentVersion`).
    public var contentVersion: Date
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var subtypes: Set<ApplePhotosAsset.Subtype>
    /// The asset's favourite as last read.
    public var isFavorite: Bool
    public var isHidden: Bool

    public init(
        photo: Int64, local: String, cloud: String?, key: String, resource: Resource, contentVersion: Date,
        pixelWidth: Int? = nil, pixelHeight: Int? = nil, subtypes: Set<ApplePhotosAsset.Subtype> = [],
        isFavorite: Bool = false, isHidden: Bool = false,
    ) {
        self.photo = photo
        self.local = local
        self.cloud = cloud
        self.key = key
        self.resource = resource
        self.contentVersion = contentVersion
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.subtypes = subtypes
        self.isFavorite = isFavorite
        self.isHidden = isHidden
    }

    static func bits(_ subtypes: Set<ApplePhotosAsset.Subtype>) -> Int {
        ApplePhotosAsset.Subtype.allCases.enumerated().reduce(0) { bits, entry in
            subtypes.contains(entry.element) ? bits | 1 << entry.offset : bits
        }
    }

    static func subtypes(_ bits: Int) -> Set<ApplePhotosAsset.Subtype> {
        Set(ApplePhotosAsset.Subtype.allCases.enumerated().compactMap { bits & 1 << $0.offset != 0 ? $0.element : nil })
    }
}

public extension LibraryPaths {
    /// Redlamp's cache of Apple Photos (LIB-58): for the standard library, in `~/Library/Caches/Redlamp`, which macOS
    /// may empty and Time Machine leaves out; for any other, in its folder.
    var applePhotos: URL {
        guard root.standardizedFileURL.path == LibraryPaths.standard.root.standardizedFileURL.path else {
            return root.appending(path: "Apple Photos", directoryHint: .isDirectory)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: "Redlamp/Apple Photos", directoryHint: .isDirectory)
    }
}

public extension LibraryIndex.Writer {
    /// The Apple Photos root's ID, made at `path` with its volume, its folder and its sidecars on this Mac when the
    /// index has none; one it has stays where it is.
    func applePhotosRoot(at path: String) throws -> Int64 {
        if let existing = try applePhotosRoot() {
            return existing.id
        }
        let volume = try upsertVolume(VolumeRecord(uuid: ApplePhotosPlace.volume, name: "Apple Photos"))
        let root = try upsertRoot(RootRecord(volume: volume, path: path, sidecars: .onThisMac, kind: .applePhotos))
        try upsertFolder(FolderRecord(root: root, path: path))
        try setSetting("1", for: LibrarySidecars.probedKey(root))
        try setSetting(ApplePhotosPlace.library, for: LibrarySidecars.pathKey(root))
        return root
    }

    /// Writes the rows' `photo_assets` and replaces their photos' albums with `albums`.
    func setApplePhotosRows(_ rows: [(row: ApplePhotosRow, albums: [String])]) throws {
        let asset = try database.cached("""
        INSERT OR REPLACE INTO photo_assets (photo, local_id, cloud_id, asset_key, resource, content_version, width,
          height, subtypes, favorite, hidden) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        let clear = try database.cached("DELETE FROM photo_albums WHERE photo = ?")
        let album = try database.cached("INSERT OR IGNORE INTO photo_albums (album, photo) VALUES (?, ?)")
        for (row, albums) in rows {
            try asset.bind(row.photo, at: 1)
            try asset.bind(row.local, at: 2)
            try asset.bind(row.cloud, at: 3)
            try asset.bind(row.key, at: 4)
            try asset.bind(row.resource.rawValue, at: 5)
            try asset.bind(row.contentVersion.timeIntervalSince1970, at: 6)
            try asset.bind(row.pixelWidth, at: 7)
            try asset.bind(row.pixelHeight, at: 8)
            try asset.bind(ApplePhotosRow.bits(row.subtypes), at: 9)
            try asset.bind(row.isFavorite ? 1 : 0, at: 10)
            try asset.bind(row.isHidden ? 1 : 0, at: 11)
            try asset.run()
            try clear.bind(row.photo, at: 1)
            try clear.run()
            for id in albums {
                try album.bind(id, at: 1)
                try album.bind(row.photo, at: 2)
                try album.run()
            }
        }
    }

    /// Takes out the photos `ids` of the Apple Photos root with what names their assets and albums, and the folders
    /// left with no photo; returns the rows removed. Their sidecars stay, so keeping an album that holds them again
    /// brings back everything Redlamp kept of them.
    func removeApplePhotos(_ ids: [Int64]) throws -> [Int64] {
        let folders = try database.cached("SELECT DISTINCT folder FROM photos WHERE id = ?")
        var emptied = Set<Int64>()
        for id in ids {
            try folders.bind(id, at: 1)
            try folders.forEachRow { emptied.insert($0.int64(at: 0)) }
        }
        let removed = try removePhotos(ids)
        let asset = try database.cached("DELETE FROM photo_assets WHERE photo = ?")
        let albums = try database.cached("DELETE FROM photo_albums WHERE photo = ?")
        for id in removed {
            for statement in [asset, albums] {
                try statement.bind(id, at: 1)
                try statement.run()
            }
        }
        let folder = try database.cached("""
        DELETE FROM folders WHERE id = ?1 AND NOT EXISTS (SELECT 1 FROM photos WHERE folder = ?1)
          AND root IN (SELECT id FROM roots WHERE kind = 1) AND parent IS NOT NULL
        """)
        for id in emptied {
            try folder.bind(id, at: 1)
            try folder.run()
        }
        return removed
    }
}

public extension IndexQueries {
    /// Every row of the Apple Photos root, as `photo_assets` names them.
    func applePhotosRows() throws -> [ApplePhotosRow] {
        try database.cached("""
        SELECT photo, local_id, cloud_id, asset_key, resource, content_version, width, height, subtypes, favorite,
          hidden FROM photo_assets ORDER BY photo
        """).map { row in
            ApplePhotosRow(
                photo: row.int64(at: 0), local: row.string(at: 1) ?? "", cloud: row.string(at: 2),
                key: row.string(at: 3) ?? "", resource: ApplePhotosRow.Resource(rawValue: row.int(at: 4)) ?? .original,
                contentVersion: Date(timeIntervalSince1970: row.double(at: 5)), pixelWidth: row.optionalInt(at: 6),
                pixelHeight: row.optionalInt(at: 7), subtypes: ApplePhotosRow.subtypes(row.int(at: 8)),
                isFavorite: row.int(at: 9) != 0, isHidden: row.int(at: 10) != 0,
            )
        }
    }

    /// How many photos of the Apple Photos root each album kept in place holds, by Photos' local identifier.
    func applePhotosAlbumCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        try database.cached("SELECT album, count(*) FROM photo_albums GROUP BY album").forEachRow { row in
            counts[row.string(at: 0) ?? ""] = row.int(at: 1)
        }
        return counts
    }
}
