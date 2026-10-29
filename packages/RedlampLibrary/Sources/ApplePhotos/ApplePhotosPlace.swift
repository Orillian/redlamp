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

    /// Gives the rows of the asset with local identifier `local` the key `key` and the cloud identifier `cloud`
    /// (LIB-61).
    func setApplePhotosKey(_ key: String, cloud: String, ofAsset local: String) throws {
        let statement = try database.cached("UPDATE photo_assets SET asset_key = ?, cloud_id = ? WHERE local_id = ?")
        try statement.bind(key, at: 1)
        try statement.bind(cloud, at: 2)
        try statement.bind(local, at: 3)
        try statement.run()
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

    /// Links the copies `standing` names to their assets (LIB-64), by local identifier, each listed in its asset's
    /// albums kept, and settles the other copies linked to the assets `evaluated` names: those taken out let go, the
    /// rest kept, in no album, with whether they're there and not missing. Returns the copies whose albums changed.
    func setApplePhotosCopies(
        _ standing: [(local: String, photos: [Int64], albums: [String])], evaluated: Set<String>,
    ) throws -> [Int64] {
        let linked = try database.cached("SELECT photo FROM photo_copies WHERE local_id = ? AND photo IS NOT NULL")
        let unlink = try database.cached("DELETE FROM photo_copies WHERE local_id = ?")
        let link = try database.cached("""
        INSERT OR REPLACE INTO photo_copies (photo, local_id, live) VALUES (?1, ?2,
          EXISTS (SELECT 1 FROM photos WHERE id = ?1 AND state & \(PhotoRecord.State.missing.rawValue) = 0))
        """)
        let held = try database.cached("SELECT album FROM photo_albums WHERE photo = ?")
        let clear = try database.cached("DELETE FROM photo_albums WHERE photo = ?")
        let album = try database.cached("INSERT OR IGNORE INTO photo_albums (album, photo) VALUES (?, ?)")
        var wanted: [String: (photos: Set<Int64>, albums: Set<String>)] = [:]
        for copy in standing {
            wanted[copy.local] = (Set(copy.photos), Set(copy.albums))
        }
        var changed: [Int64] = []
        for local in evaluated.union(wanted.keys) {
            try linked.bind(local, at: 1)
            let before = try Set(linked.map { $0.int64(at: 0) })
            try unlink.bind(local, at: 1)
            try unlink.run()
            let now = wanted[local]
            for photo in before.union(now?.photos ?? []).sorted() {
                let albums = now?.photos.contains(photo) == true ? now?.albums ?? [] : []
                try held.bind(photo, at: 1)
                if try Set(held.map { $0.string(at: 0) ?? "" }) != albums {
                    try clear.bind(photo, at: 1)
                    try clear.run()
                    for id in albums {
                        try album.bind(id, at: 1)
                        try album.bind(photo, at: 2)
                        try album.run()
                    }
                    changed.append(photo)
                }
                try link.bind(photo, at: 1)
                try link.bind(local, at: 2)
                try link.run()
            }
        }
        return changed
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

    /// How many photos the library lists of each album kept in place, by Photos' local identifier, as the album's list
    /// shows them (LIB-62): its photos, the copies standing in for theirs (LIB-64) and their versions (LIB-48), not
    /// those kept as missing (LIB-61).
    func applePhotosAlbumCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        try database.cached("""
        SELECT al.album, count(*) FROM photo_albums al JOIN photos p ON p.id = al.photo
          JOIN photos v ON v.folder = p.folder AND v.name = p.name
        WHERE v.state & \(PhotoRecord.State.missing.rawValue) = 0 GROUP BY al.album
        """).forEachRow { row in
            counts[row.string(at: 0) ?? ""] = row.int(at: 1)
        }
        return counts
    }

    /// The part of Photos' tree kept in place, as the last pass found it (LIB-62): each collection kept, everything
    /// inside a folder kept, and the folders above them, in Photos' order and titled as Photos had them; before a pass
    /// has found it, the collections kept as they were chosen.
    func applePhotosKeptTree() throws -> ApplePhotosTree {
        try ApplePhotosTree(ApplePhotosIndexer.following(self)?.tree ?? ApplePhotosIndexer.chosen(self))
    }

    /// The photos the library has of album `id`, kept in place, or of every album kept in folder `id` (LIB-62): its
    /// photos from Photos and the copies standing in for theirs (LIB-64), each with its versions (LIB-48), those kept
    /// as missing among them, as a folder's are; in the order of their IDs.
    func applePhotosPhotoIDs(in id: String) throws -> [Int64] {
        let tree = try applePhotosKeptTree()
        let albums = tree[id]?.kind == .folder ? tree.albums(in: [id]).map(\.id) : [id]
        let statement = try database.cached("""
        SELECT v.id FROM photo_albums al JOIN photos p ON p.id = al.photo
          JOIN photos v ON v.folder = p.folder AND v.name = p.name WHERE al.album = ?
        """)
        var photos = Set<Int64>()
        for album in albums {
            try statement.bind(album, at: 1)
            try statement.forEachRow { photos.insert($0.int64(at: 0)) }
        }
        return photos.sorted()
    }

    /// Every photo the library keeps in Apple Photos (LIB-62): those under its root, each with its versions and those
    /// kept as missing among them, but not the copies standing in for theirs, which are in folders (LIB-64); in the
    /// order of their IDs.
    func applePhotosPhotoIDs() throws -> [Int64] {
        var photos: [Int64] = []
        try database.cached("""
        SELECT id FROM photos WHERE folder IN (SELECT id FROM folders
          WHERE root IN (SELECT id FROM roots WHERE kind = \(RootRecord.Kind.applePhotos.rawValue))) ORDER BY id
        """).forEachRow { photos.append($0.int64(at: 0)) }
        return photos
    }
}
