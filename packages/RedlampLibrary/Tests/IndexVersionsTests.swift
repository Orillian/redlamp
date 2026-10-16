import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// Versions of photos in the index (LIB-48): each version in a photo's sidecar is a row beside its file's, with the
/// version's own organising fields, keywords and collections and the file's own fields, and goes where its file goes.
struct IndexVersionsTests {
    private static let copy = UUID(uuidString: "6F1C2A4E-8B1D-4C3A-9E57-1B2D3C4E5F60")!
    private static let lightroom = UUID(uuidString: "0A0B0C0D-1111-2222-3333-444455556666")!

    /// A sidecar with the photo's own edit and metadata, and two versions: Copy 1, edited, rated, keyworded and in a
    /// collection, and Lightroom Classic, with a custom label.
    private static func sidecar() -> Sidecar {
        var edited = EditRecipe()
        edited[.exposure] = 0.5
        return Sidecar(
            recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2, keywords: ["Places/Lisbon"], captureShift: 3600),
            versions: [
                PhotoVersion(
                    id: copy, name: "Copy 1", recipe: edited,
                    metadata: PhotoMetadata(
                        rating: 5, flag: .pick, label: .red, keywords: ["Birds/Heron"], mark: true, title: "Heron",
                        caption: "At dawn", creator: "Ana", collections: ["Portfolio"],
                    ),
                ),
                PhotoVersion(
                    id: lightroom, name: "Lightroom Classic", recipe: EditRecipe(),
                    metadata: PhotoMetadata(customLabel: "Hero", customLabelColor: .orange),
                ),
            ],
            modified: Date(timeIntervalSinceNow: -3600),
        )
    }

    @discardableResult
    private static func index(_ sandbox: XMPSandbox, into index: LibraryIndex? = nil) async -> IndexerRun {
        let indexer = LibraryIndexer(index: index ?? sandbox.index, configuration: .testing())
        let run = await IndexerRun.collect(indexer.index([sandbox.root]))
        #expect(run.failures.isEmpty, "\(run.failures)")
        return run
    }

    private static func versions(of file: PhotoRecord, in index: LibraryIndex) async throws -> [PhotoRecord] {
        try await index.read { try $0.versions(folder: file.folder, name: file.name) }
    }

    @Test func `a sidecar's versions are rows beside the photo's, each with its own fields and the file's`(
    ) async throws {
        let sandbox = try await XMPSandbox.make()
        defer { sandbox.remove() }
        try SidecarStore().save(Self.sidecar(), for: sandbox.photo("A.ARW"))
        try sandbox.photo("B.ARW")
        let run = await Self.index(sandbox)

        let file = try await sandbox.row("A.ARW")
        let rows = try await Self.versions(of: file, in: sandbox.index)
        #expect(file.version == nil && file.rating == 2 && !file.edited)
        #expect(rows.map(\.version) == [Self.copy, Self.lightroom])
        #expect(try await Set(run.inserted) == Set([file.id, sandbox.id("B.ARW")] + rows.map(\.id)))
        let (copy, lightroom) = (rows[0], rows[1])
        #expect(copy.rating == 5 && copy.flag == .pick && copy.label == .red && copy.marked && copy.edited)
        #expect(copy.title == "Heron" && copy.caption == "At dawn" && copy.creator == "Ana")
        #expect(lightroom.rating == 0 && lightroom.customLabel == "Hero" && lightroom.customLabelColor == .orange)
        #expect(!lightroom.edited && !lightroom.marked)
        for row in rows {
            #expect(row.folder == file.folder && row.name == file.name && row.kind == file.kind)
            #expect(row.size == file.size && row.modified == file.modified && row.fileID == file.fileID)
            #expect(row.contentKey == file.contentKey && row.sidecarModified == file.sidecarModified)
            #expect(row.captured == file.captured && row.otherFields.isEmpty)
        }
        let organised = try await sandbox.index.read { reader in
            try [file, copy, lightroom].map { row in
                try (reader.keywords(forPhoto: row.id), reader.collectionPlaces(ofPhoto: row.id).compactMap(\.path))
            }
        }
        #expect(organised.map(\.0) == [["Places/Lisbon"], ["Birds/Heron"], []])
        #expect(organised.map(\.1) == [[], ["Portfolio"], []])
    }

    @Test func `a version taken out of the sidecar takes its row, and one changed or added is written`() async throws {
        let sandbox = try await XMPSandbox.make()
        defer { sandbox.remove() }
        let photo = try sandbox.photo("A.ARW")
        try SidecarStore().save(Self.sidecar(), for: photo)
        await Self.index(sandbox)
        let file = try await sandbox.row("A.ARW")
        let before = try await Self.versions(of: file, in: sandbox.index)

        var sidecar = try #require(SidecarStore().load(for: photo))
        let added = UUID()
        sidecar.versions.removeAll { $0.id == Self.lightroom }
        sidecar.versions[0].name = "Heron, warm"
        sidecar.versions[0].metadata?.rating = 3
        sidecar.versions[0].metadata?.keywords = []
        sidecar.versions.append(PhotoVersion(
            id: added, name: "Copy 2", recipe: EditRecipe(), metadata: PhotoMetadata(flag: .reject),
        ))
        try SidecarStore().save(sidecar, for: photo)
        let run = await Self.index(sandbox)

        let after = try await Self.versions(of: file, in: sandbox.index)
        #expect(after.map(\.version) == [Self.copy, added])
        #expect(after[0].id == before[0].id && after[0].rating == 3 && after[1].flag == .reject)
        #expect(run.inserted == [after[1].id])
        #expect(run.removed == [before[1].id])
        #expect(run.updated.contains(after[0].id))
        let left = try await sandbox.index.read { reader in
            try (reader.photo(id: before[1].id), reader.keywords(forPhoto: before[0].id))
        }
        #expect(left.0 == nil && left.1.isEmpty)

        // The sidecar gone, the photo has no versions.
        try FileManager.default.removeItem(at: SidecarStore().url(for: photo))
        let cleared = await Self.index(sandbox)
        #expect(try await Self.versions(of: file, in: sandbox.index).isEmpty)
        #expect(Set(cleared.removed) == Set(after.map(\.id)))
    }

    @Test func `an index rebuilt from the sidecars gets the photos' versions back`() async throws {
        let sandbox = try await XMPSandbox.make()
        defer { sandbox.remove() }
        try SidecarStore().save(Self.sidecar(), for: sandbox.photo("A.ARW"))
        await Self.index(sandbox)
        let rebuilt = try await LibraryIndex.open(at: sandbox.library.url.appending(path: "Rebuilt.sqlite"), readers: 2)
        defer { rebuilt.closeAndWait() }
        await Self.index(sandbox, into: rebuilt)

        let path = LibraryIndexer.path(sandbox.url("A.ARW"))
        func shown(_ index: LibraryIndex) async throws -> [PhotoRecord] {
            try await index.read { reader in
                guard let file = try reader.photo(path: path) else { return [] }
                return try ([file] + reader.versions(folder: file.folder, name: file.name)).map { row in
                    var row = row
                    row.id = 0
                    row.folder = 0
                    return row
                }
            }
        }
        let rows = try await shown(rebuilt)
        #expect(rows.map(\.version) == [nil, Self.copy, Self.lightroom])
        #expect(try await rows == shown(sandbox.index))
    }

    @Test func `lookups by place give the file's own row, and moves, renames and parking take its versions along`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let folders = try await sandbox.addFolders(["A", "B"])
        let (a, b) = try (#require(folders["A"]), #require(folders["B"]))
        let key = Data(repeating: 7, count: 16)
        let files = try await sandbox.upsert([
            PhotoRecord(folder: a, name: "X.ARW", size: 10, fileID: 1, contentKey: key),
            PhotoRecord(folder: a, name: "Y.ARW", size: 20, fileID: 2),
        ])
        let (x, y) = (files[0], files[1])
        let (xv, yv) = try await sandbox.index.write { writer in
            try (
                writer.setVersions([Self.summary(Self.copy, rating: 4), Self.summary(Self.lightroom)], ofPhoto: x)
                    .inserted,
                writer.setVersions([Self.summary(Self.copy)], ofPhoto: y).inserted,
            )
        }
        let found = try await sandbox.index.read { reader in
            try (
                reader.photo(folder: a, name: "X.ARW")?.id, reader.photo(path: IndexSandbox.rootPath + "/A/X.ARW")?.id,
                reader.photos(inFolder: a).map(\.id), reader.versions(inFolder: a).map(\.id),
                reader.photos(fileID: 1, volume: sandbox.volume).map(\.id), reader.photos(contentKey: key).map(\.id),
                reader.fileRows(of: xv + [y] + yv), reader.photo(id: xv[0]),
            )
        }
        #expect(found.0 == x && found.1 == x && found.2 == [x, y] && found.3 == xv + yv)
        #expect(found.4 == [x] && found.5 == [x] && found.6 == [x, y])
        #expect(found.7?.size == 10 && found.7?.fileID == 1 && found.7?.contentKey == key && found.7?.rating == 4)

        // Renamed by a version's row: the file's.
        let renamed = try await sandbox.index.write { try $0.movePhotos([(xv[1], a, "Z.ARW")]) }
        #expect(Set(renamed) == Set([x, xv[0]]))
        #expect(try await Self.place(of: x, sandbox) == Place(folder: a, name: "Z.ARW", versions: xv))

        // X and Y swap names: each waits under a name no file has, with its versions.
        let stale = try await sandbox.index.write { try $0.placePhotos([(x, a, "Y.ARW"), (y, a, "Z.ARW")]) }
        #expect(stale.isEmpty)
        #expect(try await Self.place(of: x, sandbox) == Place(folder: a, name: "Y.ARW", versions: xv))
        #expect(try await Self.place(of: y, sandbox) == Place(folder: a, name: "Z.ARW", versions: yv))

        // Moved to another folder onto a row of a file that's gone, whose versions go with it.
        let gone = try await sandbox.upsert([PhotoRecord(folder: b, name: "Y.ARW")])[0]
        let goneVersions = try await sandbox.index.write { writer in
            try writer.setVersions([Self.summary(Self.copy)], ofPhoto: gone).inserted
        }
        let removed = try await sandbox.index.write { try $0.placePhotos([(x, b, "Y.ARW")]) }
        #expect(removed == [gone])
        #expect(try await Self.place(of: x, sandbox) == Place(folder: b, name: "Y.ARW", versions: xv))
        #expect(try await sandbox.index.read { try $0.photo(id: goneVersions[0]) } == nil)
    }

    @Test func `missing and found, relinks, file fields and removal take in a photo's versions`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let folders = try await sandbox.addFolders(["A", "B"])
        let (a, b) = try (#require(folders["A"]), #require(folders["B"]))
        let files = try await sandbox.upsert([
            PhotoRecord(folder: a, name: "X.ARW", size: 10), PhotoRecord(folder: b, name: "Y.ARW", size: 20),
        ])
        let (x, y) = (files[0], files[1])
        let (xv, yv) = try await sandbox.index.write { writer in
            try (
                writer.setVersions([Self.summary(Self.copy), Self.summary(Self.lightroom)], ofPhoto: x).inserted,
                writer.setVersions([Self.summary(Self.copy)], ofPhoto: y).inserted,
            )
        }
        let gone = Date(timeIntervalSince1970: 1_700_000_000)
        let marked = try await sandbox.index.write { try $0.markMissing([(x, a)], at: gone) }
        #expect(Set(marked) == Set([x] + xv) && marked.count == 3)
        let missing = try await Self.rows([x] + xv, sandbox)
        #expect(missing.allSatisfy { $0.state.contains(.missing) && $0.missingSince == gone })
        let found = try await sandbox.index.write { try $0.markFound([x]) }
        #expect(Set(found) == Set([x] + xv))
        #expect(try await Self.rows([x] + xv, sandbox).allSatisfy { !$0.state.contains(.missing) })

        // A file's identifier and its sidecar's date are the file's, on every row of it.
        let saved = Date(timeIntervalSince1970: 1_700_000_100)
        try await sandbox.index.write { writer in
            try writer.setFileID(77, forPhoto: xv[0])
            try writer.setSidecarModified(saved, forPhoto: xv[1])
        }
        #expect(try await Self.rows([x] + xv, sandbox).allSatisfy { $0.fileID == 77 && $0.sidecarModified == saved })

        // A version's row removed alone; the file's own takes its versions.
        #expect(try await sandbox.index.write { try $0.deletePhotos([yv[0]]) } == 1)
        #expect(try await Self.rows([y], sandbox).count == 1)

        // Relinked by a version's row onto Y's place: X's rows go there with the file's fields, and Y's row goes.
        _ = try await sandbox.index.write { try $0.markMissing([(x, a)], at: gone) }
        let replaced = try await sandbox.index.write { writer in
            try writer.relinkPhoto(xv[0], toFolder: b, name: "Y.ARW", fileID: 9, size: 30, modified: saved)
        }
        #expect(replaced == [y])
        let relinked = try await Self.rows([x] + xv, sandbox)
        #expect(relinked.allSatisfy { $0.folder == b && $0.name == "Y.ARW" && $0.fileID == 9 && $0.size == 30 })
        #expect(relinked.allSatisfy { !$0.state.contains(.missing) && $0.missingSince == nil })
        #expect(relinked.map(\.version) == [nil, Self.copy, Self.lightroom])

        #expect(try await sandbox.index.write { try $0.deletePhotos([x]) } == 3)
        #expect(try await Self.rows([x] + xv, sandbox).isEmpty)
    }

    @Test func `an index at version 14 is made again with every row's ID and values, its text and indexes kept`(
    ) async throws {
        let folder = try TemporaryFolder()
        defer { withExtendedLifetime(folder) {} }
        let url = folder.url.appending(path: "Index.sqlite")
        let old = try await LibraryIndex.open(at: url, migrations: Array(LibraryIndex.migrations.prefix(14)))
        try await old.write { writer in
            let volume = try writer.upsertVolume(VolumeRecord(uuid: "V", name: "V", kind: .ssd))
            let root = try writer.upsertRoot(RootRecord(volume: volume, path: "/Photos"))
            let folder = try writer.upsertFolder(FolderRecord(root: root, parent: nil, path: "/Photos"))
            try writer.database.execute("""
            INSERT INTO photos (id, folder, name, kind, size, modified, file_id, content_key, captured, rating, flag,
              label, marked, edited, title, caption, creator, city, stack, stack_top, stack_position, custom_label,
              custom_label_color, focal35, other_fields)
            VALUES (7, \(folder), 'A.ARW', 1, 100, 1.7e9, 11, x'00112233445566778899aabbccddeeff', 1.6e9, 3, 1, 2, 1,
              1, 'Heron', 'At dawn', 'Ana', 'Lisbon', 'S', 1, 2, NULL, NULL, 52.5, 3),
              (12, \(folder), 'B.ARW', 1, 200, 1.71e9, NULL, NULL, NULL, 0, 0, 0, 0, 0, NULL, NULL, NULL, NULL, NULL,
              0, NULL, 'Hero', 'orange', NULL, 0);
            UPDATE photos SET state = 1, missing_since = 1.69e9 WHERE id = 12;
            """)
            try writer.setKeywords(["Birds/Heron"], forPhoto: 7)
            try writer.setCollections(["Portfolio"], forPhoto: 12)
            try writer.writeText(adding: [12], replacing: [])
        }
        let columns = try await old.read { reader in
            try reader.database.prepare("SELECT name FROM pragma_table_info('photos') ORDER BY cid")
                .map { $0.string(at: 0) ?? "" }
        }
        let before = try await Self.contents(of: old, columns: columns)
        await old.close()

        let migrated = try await LibraryIndex.open(at: url)
        let after = try await Self.contents(of: migrated, columns: columns)
        #expect(after.version == LibraryIndex.schemaVersion)
        #expect(after.rows == before.rows && after.rows.count == 2)
        #expect(after.text == before.text && after.text == [[7], [12], [7, 12]], "\(before.text)")
        #expect(after.organised == before.organised)
        #expect(after.indexes == (before.indexes.filter { !$0.hasPrefix("sqlite_autoindex") } + ["photos_place"])
            .sorted())
        let checked = try await migrated.read { reader in
            try (
                reader.database.prepare("PRAGMA integrity_check").first { $0.string(at: 0) },
                reader.database.prepare("SELECT DISTINCT version FROM photos").map { $0.string(at: 0) },
                reader.database.prepare("SELECT name FROM pragma_table_info('photos') ORDER BY cid")
                    .map { $0.string(at: 0) ?? "" },
            )
        }
        #expect(checked.0 == "ok" && checked.1 == [""] && checked.2 == columns + ["version"])
        await migrated.close()

        // Set back to 14 with the column, it only makes sure of the unique index.
        try SQLiteDatabase(path: url.path).setUserVersion(14)
        let again = try await LibraryIndex.open(at: url)
        defer { again.closeAndWait() }
        let reopened = try await Self.contents(of: again, columns: columns)
        #expect(reopened.version == LibraryIndex.schemaVersion && reopened.rows == before.rows)
    }

    private static func summary(_ id: UUID, rating: Int = 0) -> VersionSummary {
        VersionSummary(
            id: id, name: "Copy", created: Date(timeIntervalSince1970: 1_700_000_000), hasEdits: rating > 0,
            metadata: PhotoMetadata(rating: rating),
        )
    }

    private struct Place: Equatable {
        var folder: Int64
        var name: String
        var versions: [Int64]
    }

    private static func place(of file: Int64, _ sandbox: IndexSandbox) async throws -> Place? {
        try await sandbox.index.read { reader in
            guard let row = try reader.photo(id: file) else { return nil }
            return try Place(
                folder: row.folder, name: row.name,
                versions: reader.versions(folder: row.folder, name: row.name).map(\.id),
            )
        }
    }

    private static func rows(_ ids: [Int64], _ sandbox: IndexSandbox) async throws -> [PhotoRecord] {
        try await sandbox.index.read { reader in try ids.compactMap { try reader.photo(id: $0) } }
    }

    private struct Contents: Equatable {
        var version: Int
        /// Each row's values of `columns`, as SQLite quotes them, by ID.
        var rows: [[String]]
        /// The rows the text index finds for a title, a name and part of every name.
        var text: [[Int64]]
        var organised: [[String]]
        var indexes: [String]
    }

    private static func contents(of index: LibraryIndex, columns: [String]) async throws -> Contents {
        try await index.read { reader in
            let database = reader.database
            let values = "SELECT " + columns.map { "quote(\"\($0)\")" }.joined(separator: ", ")
                + " FROM photos ORDER BY id"
            let rows = try database.prepare(values).map { row in
                columns.indices.map { row.string(at: Int32($0)) ?? "" }
            }
            let text = try ["heron", "\"b.arw\"", "arw"].map { term in
                try database.prepare("SELECT rowid FROM photo_text WHERE photo_text MATCH '\(term)' ORDER BY rowid")
                    .map { $0.int64(at: 0) }
            }
            let organised = try [7, 12].map { photo in
                try reader.keywords(forPhoto: Int64(photo))
                    + reader.collectionPlaces(ofPhoto: Int64(photo)).compactMap(\.path)
            }
            let indexes = try database.prepare("""
            SELECT name FROM sqlite_schema WHERE type = 'index' AND tbl_name = 'photos' ORDER BY name
            """).map { $0.string(at: 0) ?? "" }
            return try Contents(
                version: database.userVersion, rows: rows, text: text, organised: organised, indexes: indexes,
            )
        }
    }
}

private extension IndexerRun {
    var updated: [Int64] {
        events.flatMap { event -> [Int64] in
            guard case let .photosUpdated(ids) = event else { return [] }
            return ids
        }
    }

    var removed: [Int64] {
        events.flatMap { event -> [Int64] in
            guard case let .photosRemoved(ids) = event else { return [] }
            return ids
        }
    }
}
