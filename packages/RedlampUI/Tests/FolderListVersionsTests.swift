import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Versions in a folder's own list (LIB-48), as they change: made, renamed and removed in Develop, each photo's
/// versions after it in a folder listed from the disk, and with their file when it's renamed or moved.
@MainActor
@Suite(.serialized)
struct FolderListVersionsTests {
    /// The IDs of the version rows the index has of `photo`'s file, in their order.
    private func indexedVersions(of photo: URL, in sandbox: SourcesSandbox) async throws -> [Int64] {
        let index = try #require(sandbox.service?.core).index
        return try await index.read { reader in
            guard let file = try LibraryService.photo(at: photo, in: reader) else { return [] }
            return try reader.versions(folder: file.folder, name: file.name).map(\.id)
        }
    }

    @Test func `a version made, renamed or removed in Develop comes, changes its name and goes in its folder's list`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG"])
        let photo = sandbox.photo("Shoot/B.JPG")
        let model = try await sandbox.open()
        model.library.open(sandbox.folder("Shoot"))
        try await sandbox.eventually {
            model.library.isShownFromLibrary && !model.library.isListing && model.library.count == 2
        }
        try #require(model.library.isShownFromLibrary && model.library.count == 2, "Shoot shown from the library")
        let own = PhotoAddress(url: photo)
        let ownID = try #require(model.library.photoID(of: own))
        model.clickInGrid(own)
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }

        model.createVersion()
        let version = try #require(model.openVersion)
        let copy = PhotoAddress(url: photo, version: version)
        try await sandbox.eventually { model.library.index(of: copy) != nil }
        #expect(model.activeAddress == copy, "the version open the active cell once its row comes")
        model.showModule(.library)
        #expect(model.library.count == 3)
        #expect([own, copy].map { model.library.index(of: $0) } == [1, 2], "the version after its file")
        #expect(model.library.items.row(2)?.title == "Copy 1, a version of B.JPG")
        let indexed = try await indexedVersions(of: photo, in: sandbox)
        #expect(indexed.count == 1 && indexed.first == model.library.photoID(of: copy), "by its ID in the index")
        #expect(model.library.photoID(of: own) == ownID, "its file's row as it was")

        model.showModule(.develop)
        model.renameVersion(version, to: "Black and white")
        try await sandbox.eventually { model.library.items.row(2)?.versionName == "Black and white" }
        #expect(model.library.items.row(2)?.title == "Black and white, a version of B.JPG")
        #expect(model.library.index(of: copy) == 2 && model.library.count == 3, "renamed where it was")

        model.removeVersion(version)
        try await sandbox.eventually { model.library.count == 2 }
        #expect(model.library.index(of: copy) == nil, "the version gone from the list")
        #expect(model.library.index(of: own) == 1 && model.library.photoID(of: own) == ownID, "its file's row stays")
        #expect(model.activeAddress == own && model.openVersion == nil, "the photo's own edit open in its place")
        #expect(model.library.items.allRows.map(\.title) == ["A.JPG", "B.JPG"])
        try await SourcesSandbox.eventually { try await indexedVersions(of: photo, in: sandbox).isEmpty }
    }
}
