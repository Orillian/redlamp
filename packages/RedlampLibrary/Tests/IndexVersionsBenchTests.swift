import Foundation
import Testing
@testable import RedlampLibrary

/// Schema version 15 (LIB-48) makes `photos` again so versions of a photo's edit can have rows beside its file's: the
/// time it takes, the index's size and its log's at two million photos, or `REDLAMP_VERSIONS_BENCH_PHOTOS`, in an index
/// of version 14 configured as the app's, one photo in seven with a sidecar, a title and a caption. Skipped unless
/// `REDLAMP_VERSIONS_BENCH=1` (`TEST_RUNNER_REDLAMP_VERSIONS_BENCH=1` through xcodebuild).
struct IndexVersionsBenchTests {
    private static let photoCount = ProcessInfo.processInfo.environment["REDLAMP_VERSIONS_BENCH_PHOTOS"]
        .flatMap(Int.init) ?? 2_000_000

    private static func report(_ line: String) {
        print("VERSIONS-BENCH \(line)")
    }

    private static func megabytes(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) / 1_000_000
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_VERSIONS_BENCH"] == "1"))
    func `two million photos: the photos table made again for versions, keeping every row's ID`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "redlamp-versions-bench-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Index.sqlite")
        let database = try SQLiteDatabase(path: url.path)
        _ = try database.prepare("PRAGMA journal_mode = WAL").first { $0.string(at: 0) }
        try database.execute("""
        PRAGMA synchronous = NORMAL; PRAGMA mmap_size = \(1 << 30); PRAGMA temp_store = MEMORY;
        PRAGMA cache_size = -\(16 * 1024);
        """)
        try QueryFunctions.register(on: database)
        try LibraryIndex.migrate(database, with: Array(LibraryIndex.migrations.prefix(14)))

        let filling = ContinuousClock.now
        try database.transaction(.immediate) {
            let fill = try database.prepare("""
            WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < ?1)
            INSERT INTO photos (id, folder, name, kind, size, modified, file_id, content_key, captured,
              captured_offset, camera, lens, iso, aperture, shutter, focal, width, height, orientation, rating, flag,
              label, sidecar_modified, title, caption, indexed, widest_aperture, focal35)
            SELECT i + 1, i / 200 + 1, printf('DSC_%07d.ARW', i), 1, 25000000 + i % 5000000, 1.7e9 + i, i + 1000000,
              randomblob(16), 1.6e9 + i * 7, 3600, i % 12 + 1, i % 20 + 1, 100 << (i % 6), 2.8, 0.004, 35, 6000,
              4000, 1, i % 6, i % 3, i % 6, CASE WHEN i % 7 = 0 THEN 1.7e9 + i END,
              CASE WHEN i % 7 = 0 THEN 'Title ' || i END, CASE WHEN i % 7 = 0 THEN 'A caption for photo ' || i END,
              1, 2.8, 52
            FROM n
            """)
            try fill.bind(Self.photoCount, at: 1)
            try fill.run()
        }
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        Self.report(String(
            format: "filled %ld photos at version 14 in %.1f s; the index %ld MB",
            Self.photoCount, (ContinuousClock.now - filling) / .seconds(1), Self.megabytes(url),
        ))
        let before = try database.prepare("SELECT count(*), sum(id), sum(rating) FROM photos")
            .first { [$0.int64(at: 0), $0.int64(at: 1), $0.int64(at: 2)] }

        let migrating = ContinuousClock.now
        try LibraryIndex.migrate(database, with: LibraryIndex.migrations)
        let migration = ContinuousClock.now - migrating
        let log = Self.megabytes(URL(fileURLWithPath: url.path + "-wal"))
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        Self.report(String(
            format: "schema version 15: %.2f s for %ld photos; the index %ld MB after, its log %ld MB before the checkpoint",
            migration / .seconds(1), Self.photoCount, Self.megabytes(url), log,
        ))

        let after = try database.prepare("SELECT count(*), sum(id), sum(rating) FROM photos")
            .first { [$0.int64(at: 0), $0.int64(at: 1), $0.int64(at: 2)] }
        #expect(after == before)
        #expect(try database.userVersion == LibraryIndex.schemaVersion)
        let checking = ContinuousClock.now
        let check = try database.prepare("PRAGMA quick_check").first { $0.string(at: 0) }
        #expect(check == "ok")
        Self.report(String(format: "quick_check after: %.2f s", (ContinuousClock.now - checking) / .seconds(1)))

        // What a migration that kept the table would cost at most: the old unique index dropped and the new one made,
        // its schema otherwise changed in place.
        let indexes = try database
            .prepare("SELECT count(*) FROM sqlite_schema WHERE type = 'index' AND tbl_name = 'photos'")
            .first { $0.int(at: 0) } ?? 0
        let dropping = ContinuousClock.now
        try database.transaction(.immediate) { try database.execute("DROP INDEX photos_place") }
        let dropped = ContinuousClock.now - dropping
        let making = ContinuousClock.now
        try database.transaction(.immediate) { try database.execute(LibraryIndex.schemaVersion15Index) }
        Self.report(String(
            format: "the unique index alone: dropped in %.2f s, made in %.2f s; the table has %ld indexes",
            dropped / .seconds(1), (ContinuousClock.now - making) / .seconds(1), indexes,
        ))
    }
}
