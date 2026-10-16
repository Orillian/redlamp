import Foundation
import RedlampRecipes
import Synchronization

public extension LightroomCatalog {
    /// A photo's or virtual copy's Develop settings as the catalog keeps them, with what converting its edit
    /// needs of it (EDT-23): how Lightroom turns it, its file's size as the catalog records it, its snapshots,
    /// and how many steps its history has.
    struct Develop: Sendable, Hashable {
        /// Its image in the catalog (`Adobe_images.id_local`): a photo's ID or a virtual copy's.
        public var image: Int64
        /// The photo it's a virtual copy of; nil for a photo.
        public var master: Int64?
        /// How Lightroom turns and flips it (`Adobe_images.orientation`), in Lightroom's own code, as text.
        public var orientation: String?
        /// The file's width and height in pixels, as the catalog records them (`Adobe_images.fileWidth` and
        /// `fileHeight`).
        public var fileWidth: Int?
        public var fileHeight: Int?
        /// The settings, a Lua table as Lightroom writes it (`Adobe_imageDevelopSettings.text`:
        /// `s = { Exposure2012 = 0.35, … }`); nil when the catalog has none for it.
        public var text: String?
        /// The settings row's own `processVersion` and `digest`, as text.
        public var processVersion: String?
        public var digest: String?
        /// Whether Lightroom marks the settings as changed from its defaults (`hasDevelopAdjustmentsEx`, or
        /// `hasDevelopAdjustments` in older catalogs); nil when the catalog has neither.
        public var adjusted: Bool?
        public var snapshots: [Snapshot] = []
        /// The steps of its history in Develop (`Adobe_libraryImageDevelopHistoryStep`).
        public var historySteps = 0
    }

    /// A snapshot of a photo's or virtual copy's Develop settings (`Adobe_libraryImageDevelopSnapshot`).
    struct Snapshot: Sendable, Hashable {
        public var id: Int64
        /// Lightroom's own identifiers for it, where the catalog keeps them (`id_global`, `snapshotID`).
        public var globalID: String?
        public var snapshotID: String?
        public var name: String?
        /// Its settings, in the form `Develop.text` has them.
        public var text: String?
        public var digest: String?
    }
}

extension LightroomCatalog.Develop {
    /// The settings as a table; nil when the catalog has none for it.
    func settings() throws(LuaTableError) -> LuaTable? {
        guard let text else { return nil }
        return try LuaTable(parsing: text)
    }
}

extension LightroomCatalog.Snapshot {
    func settings() throws(LuaTableError) -> LuaTable? {
        guard let text else { return nil }
        return try LuaTable(parsing: text)
    }
}

extension LightroomCatalogReader {
    /// Photos whose settings are read and handed on together: about 2 MB of settings at 4 KB a photo.
    static let developPart = 500

    /// Every photo's and virtual copy's Develop settings, in the catalog's order, handed to `make` in parts of
    /// `partSize` on every core while the next parts are read, so only the parts being made are in memory: what
    /// `make` makes of each part is kept, in the catalog's order. What the catalog lacks goes in `notes`.
    func develop<Part: Sendable>(
        partSize: Int = developPart, notes: inout [String],
        _ make: @escaping @Sendable ([LightroomCatalog.Develop]) -> Part,
    ) throws -> [Part] {
        let images = try developImages(notes: &notes)
        let settings = try settingsRows(notes: &notes)
        let snapshots = try snapshotRows(notes: &notes)
        let history = try historyCounts(notes: &notes)
        let fetchSettings = try settingsStatement()
        let fetchSnapshot = try snapshotStatement()

        let made = MadeParts<Part>()
        let running = DispatchGroup()
        let slots = DispatchSemaphore(value: ProcessInfo.processInfo.activeProcessorCount + 2)
        defer { running.wait() }
        var part: [LightroomCatalog.Develop] = []
        var parts = 0
        func send() {
            slots.wait()
            let records = part
            let number = parts
            part = []
            parts += 1
            DispatchQueue.global(qos: .userInitiated).async(group: running) {
                made.add(make(records), at: number)
                slots.signal()
            }
        }
        for image in images {
            var develop = LightroomCatalog.Develop(
                image: image.id, master: image.master, orientation: image.orientation, fileWidth: image.width,
                fileHeight: image.height,
            )
            if let row = settings[image.id], let fetchSettings {
                try fetchSettings.bind(row, at: 1)
                if try fetchSettings.step() {
                    develop.text = fetchSettings.string(at: 0).flatMap(Self.settingsText)
                    develop.processVersion = fetchSettings.string(at: 1).flatMap(Self.text)
                    develop.digest = fetchSettings.string(at: 2).flatMap(Self.text)
                    develop.adjusted = fetchSettings.isNull(at: 3) ? nil : fetchSettings.double(at: 3) > 0
                }
                fetchSettings.reset()
            }
            if let rows = snapshots[image.id], let fetchSnapshot {
                develop.snapshots = try rows.compactMap { row in
                    try fetchSnapshot.bind(row, at: 1)
                    defer { fetchSnapshot.reset() }
                    guard try fetchSnapshot.step() else { return nil }
                    return LightroomCatalog.Snapshot(
                        id: row, globalID: fetchSnapshot.string(at: 0).flatMap(Self.text),
                        snapshotID: fetchSnapshot.string(at: 1).flatMap(Self.text),
                        name: fetchSnapshot.string(at: 2).flatMap(Self.text),
                        text: fetchSnapshot.string(at: 3).flatMap(Self.settingsText),
                        digest: fetchSnapshot.string(at: 4).flatMap(Self.text),
                    )
                }
            }
            develop.historySteps = history[image.id] ?? 0
            part.append(develop)
            if part.count >= partSize {
                send()
            }
        }
        if !part.isEmpty {
            send()
        }
        running.wait()
        return made.inOrder()
    }

    /// Settings' text, nil when it's only spaces; not trimmed, since it's kilobytes and the table reader skips them.
    private static func settingsText(_ text: String) -> String? {
        text.utf8.allSatisfy { $0 == 0x20 || (0x09 ... 0x0D).contains($0) } ? nil : text
    }

    private struct DevelopImage {
        let id: Int64
        let master: Int64?
        let orientation: String?
        let width: Int?
        let height: Int?
    }

    /// Each photo and virtual copy with a file, as `photos` reads them, and what `Adobe_images` holds for its
    /// edit.
    private func developImages(notes: inout [String]) throws -> [DevelopImage] {
        let images = try columns("Adobe_images")
        func image(_ column: String) -> String {
            images.contains(column.lowercased()) ? "i.\(column)" : "NULL"
        }
        if !images.contains("orientation") {
            notes.append("Adobe_images has no orientation: no rotations came from it")
        }
        let sized = images.isSuperset(of: ["filewidth", "fileheight"])
        if !sized {
            notes.append("Adobe_images has no fileWidth and fileHeight: no sizes came from it")
        }
        func pixels(_ value: Double?) -> Int? {
            value.flatMap { $0.isFinite && $0 >= 1 && $0 < 1e9 ? Int($0.rounded()) : nil }
        }
        return try database.prepare("""
        SELECT i.id_local, \(image("masterImage")), \(image("orientation")), \(sized ? "i.fileWidth" : "NULL"),
          \(sized ? "i.fileHeight" : "NULL")
        FROM Adobe_images i JOIN AgLibraryFile f ON f.id_local = i.rootFile ORDER BY i.id_local
        """).map { row in
            let id = row.int64(at: 0)
            let master = row.optionalInt64(at: 1).flatMap { $0 == id ? nil : $0 }
            return DevelopImage(
                id: id, master: master, orientation: row.string(at: 2).flatMap(Self.text),
                width: pixels(row.optionalDouble(at: 3)), height: pixels(row.optionalDouble(at: 4)),
            )
        }
    }

    /// The settings row of each image that has one: the last written, should a catalog hold several.
    private func settingsRows(notes: inout [String]) throws -> [Int64: Int64] {
        let columns = try columns("Adobe_imageDevelopSettings")
        guard columns.isSuperset(of: ["id_local", "image", "text"]) else {
            notes.append("the catalog has no Develop settings (Adobe_imageDevelopSettings.text): no edits came from it")
            return [:]
        }
        for (column, what) in [("processVersion", "process versions"), ("digest", "digests")]
            where !columns.contains(column.lowercased()) {
            notes
                .append("Adobe_imageDevelopSettings has no \(column): the settings' \(what) came from their text alone")
        }
        var rows: [Int64: Int64] = [:]
        try database.prepare("SELECT id_local, image FROM Adobe_imageDevelopSettings WHERE image IS NOT NULL")
            .forEachRow { row in
                let id = row.int64(at: 0)
                let image = row.int64(at: 1)
                if id > rows[image] ?? .min {
                    rows[image] = id
                }
            }
        return rows
    }

    private func settingsStatement() throws -> SQLiteStatement? {
        let columns = try columns("Adobe_imageDevelopSettings")
        guard columns.isSuperset(of: ["id_local", "image", "text"]) else { return nil }
        let processVersion = columns.contains("processversion") ? "processVersion" : "NULL"
        let digest = columns.contains("digest") ? "digest" : "NULL"
        let adjusted = columns.contains("hasdevelopadjustmentsex") ? "hasDevelopAdjustmentsEx"
            : columns.contains("hasdevelopadjustments") ? "hasDevelopAdjustments" : "NULL"
        return try database.prepare(
            "SELECT text, \(processVersion), \(digest), \(adjusted) FROM Adobe_imageDevelopSettings WHERE id_local = ?",
        )
    }

    /// Each image's snapshots, in the order they were made.
    private func snapshotRows(notes: inout [String]) throws -> [Int64: [Int64]] {
        guard try columns("Adobe_libraryImageDevelopSnapshot").isSuperset(of: ["id_local", "image"]) else {
            notes.append("the catalog has no Adobe_libraryImageDevelopSnapshot: no snapshots came from it")
            return [:]
        }
        var rows: [Int64: [Int64]] = [:]
        try database.prepare("""
        SELECT id_local, image FROM Adobe_libraryImageDevelopSnapshot WHERE image IS NOT NULL ORDER BY id_local
        """).forEachRow { row in
            rows[row.int64(at: 1), default: []].append(row.int64(at: 0))
        }
        return rows
    }

    private func snapshotStatement() throws -> SQLiteStatement? {
        let columns = try columns("Adobe_libraryImageDevelopSnapshot")
        guard columns.isSuperset(of: ["id_local", "image"]) else { return nil }
        let present = ["id_global", "snapshotID", "name", "text", "digest"].map {
            columns.contains($0.lowercased()) ? $0 : "NULL"
        }
        return try database.prepare(
            "SELECT \(present.joined(separator: ", ")) FROM Adobe_libraryImageDevelopSnapshot WHERE id_local = ?",
        )
    }

    /// How many history steps each image has: the steps themselves, each a whole set of settings, aren't read.
    private func historyCounts(notes: inout [String]) throws -> [Int64: Int] {
        guard try columns("Adobe_libraryImageDevelopHistoryStep").contains("image") else {
            notes.append("the catalog has no Adobe_libraryImageDevelopHistoryStep: no history steps were counted")
            return [:]
        }
        var counts: [Int64: Int] = [:]
        try database.prepare("""
        SELECT image, COUNT(*) FROM Adobe_libraryImageDevelopHistoryStep WHERE image IS NOT NULL GROUP BY image
        """).forEachRow { row in
            counts[row.int64(at: 0)] = row.int(at: 1)
        }
        return counts
    }
}

/// What each part's `make` made, from whichever thread made it.
private final class MadeParts<Part: Sendable>: Sendable {
    private let parts = Mutex<[Int: Part]>([:])

    func add(_ part: Part, at number: Int) {
        parts.withLock { $0[number] = part }
    }

    func inOrder() -> [Part] {
        parts.withLock { parts in parts.keys.sorted().compactMap { parts[$0] } }
    }
}
