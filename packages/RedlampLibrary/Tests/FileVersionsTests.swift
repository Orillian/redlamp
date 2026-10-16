import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// File operations on photos with versions of their edits (LIB-48): each file moved, copied, trashed, put back or taken
/// out of the library once, whichever of its rows is given, its versions' rows going with it and coming back with
/// Undo under their IDs, with their own fields and keywords.
struct FileVersionsTests {
    private static func sandbox() async throws -> FileSandbox {
        let simulated = SimulatedFileSystem(profile: .ssd)
        let sandbox = try await FileSandbox.make([
            .init("Shoot/IMG_0001.ARW", captured: FileSandbox.date(0), sidecar: true),
            .init("Shoot/IMG_0002.ARW", captured: FileSandbox.date(1), sidecar: true),
            .init("Shoot/Day 2/IMG_0003.ARW", captured: FileSandbox.date(2), sidecar: true),
        ], fileSystem: simulated)
        simulated.useTrash(sandbox.folder.url.appending(path: "Trash", directoryHint: .isDirectory))
        return sandbox
    }

    /// Gives the photo at `path` two versions, as the indexer writes a sidecar's.
    private static func versions(of path: String, in sandbox: FileSandbox) async throws -> (Int64, [Int64]) {
        let file = try #require(try await sandbox.rows()[path])
        let summaries = [(5, ["Birds"]), (1, [])].map { rating, keywords in
            VersionSummary(
                id: UUID(), name: "Copy", created: FileSandbox.date(), hasEdits: true,
                metadata: PhotoMetadata(rating: rating, keywords: keywords),
            )
        }
        let versions = try await sandbox.index.write { try $0.setVersions(summaries, ofPhoto: file).inserted }
        return (file, versions)
    }

    /// The rows of `ids` the index has: each one's place, rating, version and keywords.
    private static func rows(_ ids: [Int64], _ sandbox: FileSandbox) async throws -> [String] {
        let rootPath = sandbox.rootPath
        return try await sandbox.index.read { reader in
            try ids.compactMap { id in
                guard let row = try reader.photo(id: id), let folder = try reader.folder(id: row.folder) else {
                    return nil
                }
                let place = (folder.path + "/" + row.name).dropFirst(rootPath.count + 1)
                return try "\(id) \(place) \(row.rating) \(row.version != nil) \(reader.keywords(forPhoto: id))"
            }
        }
    }

    @Test func `a version's row moves its file once, with its versions`() async throws {
        let sandbox = try await Self.sandbox()
        defer { sandbox.remove() }
        let (file, versions) = try await Self.versions(of: "Shoot/IMG_0001.ARW", in: sandbox)
        let operations = sandbox.operations()
        let batch = try await operations.planMove(photos: [versions[1], file], to: sandbox.url("Shoot/Day 2"))
        #expect(batch.title == "Move 1 photo to Day 2")
        #expect(try await operations.run(batch).isFinished)
        let rows = try await Self.rows([file] + versions, sandbox)
        #expect(rows.allSatisfy { $0.contains(" Shoot/Day 2/IMG_0001.ARW ") }, "\(rows)")
        #expect(sandbox.files().keys.contains("Shoot/Day 2/IMG_0001.ARW"))
    }

    @Test func `the Trash takes a file with its versions, and Undo and Put Back bring their rows back under their IDs`(
    ) async throws {
        let sandbox = try await Self.sandbox()
        defer { sandbox.remove() }
        let (file, versions) = try await Self.versions(of: "Shoot/IMG_0002.ARW", in: sandbox)
        let before = try await Self.rows([file] + versions, sandbox)
        let operations = sandbox.operations()
        let trash = try await operations.planTrash(photos: [versions[0], file])
        #expect(trash.title == "Move 1 photo to the Trash" && trash.photoCount == 1)
        #expect(try await operations.run(trash).isFinished)
        #expect(try await Self.rows([file] + versions, sandbox).isEmpty)

        #expect(try await operations.undo().isFinished)
        #expect(try await Self.rows([file] + versions, sandbox) == before)

        let again = try await operations.planTrash(photos: [versions[1]])
        #expect(try await operations.run(again).isFinished)
        #expect(try await Self.rows([file] + versions, sandbox).isEmpty)
        let putBack = try await operations.planPutBack(batch: again.id)
        #expect(putBack.title == "Put back 1 photo")
        #expect(try await operations.run(putBack).isFinished)
        #expect(try await Self.rows([file] + versions, sandbox) == before)
    }

    @Test func `a copy gets rows of its own for its file's versions`() async throws {
        let sandbox = try await Self.sandbox()
        defer { sandbox.remove() }
        let (file, versions) = try await Self.versions(of: "Shoot/IMG_0001.ARW", in: sandbox)
        let before = try await Self.rows([file] + versions, sandbox)
        let operations = sandbox.operations()
        let copy = try await operations.planCopy(photos: [versions[0]], to: sandbox.url("Shoot/Day 2"))
        #expect(copy.photoCount == 1)
        #expect(try await operations.run(copy).isFinished)
        #expect(try await Self.rows([file] + versions, sandbox) == before, "the original's rows are as they were")
        let day2 = sandbox.rootPath + "/Shoot/Day 2"
        let copied = try await sandbox.index.read { reader -> (PhotoRecord?, [PhotoRecord], [PhotoRecord]) in
            let folder = try reader.folder(path: day2)?.id ?? 0
            let original = try reader.photo(id: file)
            return try (
                reader.photo(folder: folder, name: "IMG_0001.ARW"),
                reader.versions(folder: folder, name: "IMG_0001.ARW"),
                original.map { try reader.versions(folder: $0.folder, name: $0.name) } ?? [],
            )
        }
        let (own, theirs, originals) = copied
        #expect(own != nil && theirs.count == 2)
        #expect(theirs.map(\.version) == originals.map(\.version) && theirs.map(\.rating) == [5, 1])
        #expect(Set(theirs.map(\.id)).isDisjoint(with: versions) && !theirs.contains { $0.id == own?.id })
    }

    @Test func `taking a missing file out of the library takes its versions, and Undo brings them back`(
    ) async throws {
        let sandbox = try await Self.sandbox()
        defer { sandbox.remove() }
        let (file, versions) = try await Self.versions(of: "Shoot/IMG_0001.ARW", in: sandbox)
        let folder = try #require(try await sandbox.index.read { try $0.photo(id: file)?.folder })
        _ = try await sandbox.index.write { try $0.markMissing([(file, folder)], at: FileSandbox.date(9)) }
        let before = try await Self.rows([file] + versions, sandbox)
        let operations = sandbox.operations()
        let removal = try await operations.planRemoval(ofMissing: [versions[1]])
        #expect(removal.title == "Remove 1 missing photo" && removal.steps.count == 1)
        #expect(try await operations.run(removal).isFinished)
        #expect(try await Self.rows([file] + versions, sandbox).isEmpty)
        #expect(try await operations.undo().isFinished)
        #expect(try await Self.rows([file] + versions, sandbox) == before)
    }
}
