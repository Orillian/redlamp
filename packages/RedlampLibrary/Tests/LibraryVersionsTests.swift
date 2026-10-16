import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// What acts on files with versions of photos' edits present (LIB-48): duplicates, Library Health and the XMP sync take
/// the files' own rows, a version standing for its file, and never take a version's metadata for the file's.
struct LibraryVersionsTests {
    private static func version(rating: Int = 0) -> VersionSummary {
        VersionSummary(
            id: UUID(), name: "Copy", created: Date(timeIntervalSince1970: 1_700_000_000), hasEdits: true,
            metadata: PhotoMetadata(rating: rating),
        )
    }

    @Test func `duplicates are found among files, never a version with its own file`() async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let folder = try #require(try await sandbox.addFolders(["Shoot"])["Shoot"])
        let key = Data(repeating: 9, count: 16)
        let files = try await sandbox.upsert([
            PhotoRecord(folder: folder, name: "X.ARW", size: 100, contentKey: key),
            PhotoRecord(folder: folder, name: "X copy.ARW", size: 100, contentKey: key),
            PhotoRecord(folder: folder, name: "Y.ARW", size: 200, contentKey: Data(repeating: 3, count: 16)),
        ])
        try await sandbox.index.write { writer in
            for file in [files[0], files[2]] {
                try writer.setVersions([Self.version(), Self.version()], ofPhoto: file)
            }
        }
        let (groups, names) = try await sandbox.index.read { reader in
            try (reader.groupContentKeys().candidates().groups.map(\.photos), reader.photoNames(inFolder: folder))
        }
        #expect(groups == [[files[0], files[1]]])
        #expect(names.sorted() == ["X copy.ARW", "X.ARW", "Y.ARW"])
    }

    @Test func `Library Health lists each file once, and pairs files, whichever of its rows is asked about`(
    ) async throws {
        let sandbox = try await IndexSandbox.make()
        defer { sandbox.remove() }
        let folder = try #require(try await sandbox.addFolders(["Shoot"])["Shoot"])
        let files = try await sandbox.upsert([
            PhotoRecord(folder: folder, name: "A.ARW", kind: .raw), PhotoRecord(
                folder: folder,
                name: "A.JPG",
                kind: .jpeg,
            ),
            PhotoRecord(folder: folder, name: "B.ARW", kind: .raw),
        ])
        let gone = Date(timeIntervalSince1970: 1_700_000_000)
        let versions = try await sandbox.index.write { writer in
            let raw = try writer.setVersions([Self.version(rating: 3)], ofPhoto: files[0]).inserted
            let other = try writer.setVersions([Self.version()], ofPhoto: files[2]).inserted
            try writer.database
                .execute("UPDATE photos SET state = \(PhotoRecord.State.unreadable.rawValue) WHERE id = \(files[2])")
            try writer.carryFile(of: files[2])
            try writer.markMissing([(files[1], folder)], at: gone)
            return raw + other
        }
        let found = try await sandbox.index.read { reader in
            try (
                reader.unreadablePhotoIDs(), reader.unreadablePhotoIDs(among: versions),
                reader.missingPhotos(inFolder: folder).map(\.id), reader.pairPhotos(of: nil).map(\.id).sorted(),
                reader.pairPhotos(of: [versions[0]]).map(\.id),
            )
        }
        #expect(found.0 == [files[2]] && found.1.isEmpty, "a version shares its file's state, and isn't listed")
        #expect(found.2 == [files[1]])
        #expect(found.3 == files.sorted() && found.4 == [files[0]])

        let missing = try await HealthChecker(index: sandbox.index, paths: LibraryPaths(root: sandbox.directory))
            .missing(store: nil)
        #expect(missing.findings.map(\.photo) == [files[1]])
    }

    @Test func `the XMP sync writes the file's own metadata, given a version's row, and never a version's`(
    ) async throws {
        let sandbox = try await XMPSandbox.make()
        defer { sandbox.remove() }
        let photo = try sandbox.photo("A.ARW")
        let version = PhotoVersion(name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 5))
        try SidecarStore().save(
            Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2), versions: [version]), for: photo,
        )
        try await sandbox.indexAll()
        let file = try await sandbox.row("A.ARW")
        let versionRow = try #require(try await sandbox.index.read {
            try $0.versions(folder: file.folder, name: file.name).first
        })
        let report = try await sandbox.xmp.sync([versionRow.id], writing: true)
        #expect(report.photos.count == 1)
        let written = ["A.xmp", "A.ARW.xmp"].filter(sandbox.exists)
        #expect(written.count == 1, "\(written)")
        let xmp = try written.first.map(sandbox.text) ?? ""
        #expect(xmp.contains("xmp:Rating=\"2\"") && !xmp.contains("xmp:Rating=\"5\""), "\(xmp)")
        #expect(SidecarStore().load(for: photo)?.versions.map(\.metadata?.rating) == [5])
    }
}
