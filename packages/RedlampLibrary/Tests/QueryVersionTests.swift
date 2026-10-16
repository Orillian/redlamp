import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// Copy Status (LIB-48): `version:yes` and `version:no` tell versions of photos' edits from the files' own photos, as
/// Lightroom Classic's Copy Status tells virtual copies from their master photos, alike in the column store and in SQL.
struct QueryVersionTests {
    @Test func `version:yes finds the versions and version:no the files' own photos, in the store and in SQL`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let folder = try #require(try await sandbox.addFolders(["Shoot"])["Shoot"])
        let files = try await sandbox.upsert([
            PhotoRecord(folder: folder, name: "A.ARW", rating: 2), PhotoRecord(folder: folder, name: "B.ARW"),
        ])
        let versions = try await sandbox.index.write { writer in
            try writer.setVersions([Self.version(rating: 5), Self.version(rating: 1)], ofPhoto: files[0]).inserted
        }
        let engine = QueryEngine(index: sandbox.index)
        try await engine.load()
        let today = QueryCalendar.days(2025, 12, 31)
        for (text, expected) in [
            ("version:yes", versions), ("version:no", files), ("-version:yes", files),
            ("version:yes rating>=3", [versions[0]]), ("version:no OR rating:1", files + [versions[1]]),
        ] {
            let query = try LibraryQuery(parsing: text)
            #expect(try LibraryQuery(parsing: query.description) == query)
            let store = try await Set(engine.ids(text))
            let sql = try await sandbox.index.read { reader in
                var ids: [Int64] = []
                try reader.run(
                    QuerySQL(query.searchable, sort: QuerySort(), today: today), cancellation: QueryCancellation(),
                ) { ids.append($0) }
                return Set(ids)
            }
            #expect(store == Set(expected), "\(text) with the column store")
            #expect(sql == Set(expected), "\(text) with SQL")
        }
        #expect(throws: (any Error).self) { try LibraryQuery(parsing: "version:maybe") }
    }

    private static func version(rating: Int) -> VersionSummary {
        VersionSummary(
            id: UUID(), name: "Copy", created: Date(timeIntervalSince1970: 1_700_000_000), hasEdits: true,
            metadata: PhotoMetadata(rating: rating),
        )
    }
}
