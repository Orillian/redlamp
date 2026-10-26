import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Move to Trash on versions the library lists as photos of their own (LIB-48): a version selected without its file
/// leaves its file's sidecar, the file and its other versions staying, in the same step that takes the files selected
/// with it to the Trash, and Library's Undo puts it back under its ID with its metadata; in Develop with a version
/// open, that version goes, the photo's own edit opening in its place.
@MainActor
@Suite(.serialized)
struct MoveToTrashVersionsTests {
    private let first = UUID()
    private let second = UUID()

    /// Runs `body` on IMG_0001.JPG and IMG_0002.JPG below Shoot, the second with versions Copy 1, rated 1, and Copy 2,
    /// rated 3, shown in All Photographs with the versions' rows, in `module`; then removes what it left in the Trash
    /// and the sandbox.
    private func withShoot(
        in module: AppModule = .library, _ body: (SourcesSandbox, EditorModel, URL) async throws -> Void,
    ) async throws {
        let sandbox = SourcesSandbox()
        var service: LibraryService?
        do {
            try sandbox.photos(["Shoot/IMG_0001.JPG", "Shoot/IMG_0002.JPG"])
            let photo = sandbox.photo("Shoot/IMG_0002.JPG")
            var sidecar = Sidecar(recipe: EditRecipe())
            sidecar.versions = [
                PhotoVersion(id: first, name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 1)),
                PhotoVersion(id: second, name: "Copy 2", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 3)),
            ]
            try SidecarStore().saveOrRemove(sidecar, for: photo)
            let model = try await sandbox.open()
            service = sandbox.service
            #expect(model.librarySources.show(.allPhotographs))
            try await sandbox.eventually { !model.librarySources.isListing && model.library.count == 4 }
            model.showModule(module)
            try await body(sandbox, model, photo)
        } catch {
            await cleanUp(sandbox, service)
            throw error
        }
        await cleanUp(sandbox, service)
    }

    private func cleanUp(_ sandbox: SourcesSandbox, _ service: LibraryService?) async {
        for place in await service?.trashedPlaces() ?? [] {
            try? FileManager.default.removeItem(atPath: place)
        }
        sandbox.remove()
    }

    /// The versions of `photo` its sidecar holds on disk, in order.
    private func versions(of photo: URL) -> [UUID] {
        SidecarStore().load(for: photo)?.versions.map(\.id) ?? []
    }

    /// Selects the rows of `photos`, and only them.
    private func select(_ photos: [PhotoAddress], in model: EditorModel) throws {
        model.selectOnly(photos.first)
        for photo in photos.dropFirst() {
            try model.photoSelection.toggle(#require(model.library.photoID(of: photo)), in: model.library.photoList)
        }
        try #require(model.selectedCount == photos.count)
    }

    @Test func `a version selected alone leaves its sidecar, the file and its other versions staying, and Undo puts it back`(
    ) async throws {
        try await withShoot { sandbox, model, photo in
            model.select(sandbox.photo("Shoot/IMG_0001.JPG"))
            try select([PhotoAddress(url: photo, version: first)], in: model)
            #expect(model.canPerform(.moveToTrash))

            #expect(await model.trash(model.selectedIndexIDs()) == nil)
            #expect(model.undoNotice.text == "Removed version “Copy 1” of IMG_0002.JPG")
            await model.filesMade()
            #expect(FileManager.default.fileExists(atPath: photo.path), "the file stays")
            #expect(versions(of: photo) == [second], "its other version stays")
            try await sandbox.eventually { model.library.count == 3 }
            #expect(model.library.index(of: PhotoAddress(url: photo, version: first)) == nil)
            #expect(model.library.trashedCount == 0, "Recently Trashed lists files only")

            #expect(model.canPerform(.undo) && model.perform(.undo))
            await model.filesMade()
            #expect(versions(of: photo) == [first, second], "back under its ID, at its place")
            #expect(SidecarStore().load(for: photo)?.version(first)?.metadata?.rating == 1, "with its metadata")
            try await sandbox.eventually { model.library.count == 4 }

            #expect(model.canPerform(.redo) && model.perform(.redo))
            await model.filesMade()
            #expect(versions(of: photo) == [second])
        }
    }

    @Test func `a file and another file's version go in one step, the file to the Trash and the version from its sidecar, and Undo puts both back`(
    ) async throws {
        try await withShoot { sandbox, model, photo in
            let other = sandbox.photo("Shoot/IMG_0001.JPG")
            model.select(other)
            try select([PhotoAddress(url: other), PhotoAddress(url: photo, version: second)], in: model)

            #expect(await model.trash(model.selectedIndexIDs()) == nil)
            #expect(model.undoNotice.text
                == "Moved IMG_0001.JPG to the Trash and removed version “Copy 2” of IMG_0002.JPG")
            #expect(model.activity.events.contains { $0.text == "Removed version “Copy 2” of IMG_0002.JPG" })
            #expect(model.fileUndoTitles.last == "Move 1 Photo to the Trash and Remove 1 Version")
            await model.filesMade()
            #expect(!FileManager.default.fileExists(atPath: other.path))
            try await sandbox.eventually { versions(of: photo) == [first] }
            try await sandbox.eventually { model.library.count == 2 }

            #expect(model.perform(.undo))
            await model.filesMade()
            #expect(FileManager.default.fileExists(atPath: other.path))
            try await sandbox.eventually { versions(of: photo) == [first, second] }
            try await sandbox.eventually { model.library.count == 4 }
        }
    }

    @Test func `a file selected with its version goes to the Trash with all its versions`() async throws {
        try await withShoot { sandbox, model, photo in
            model.select(sandbox.photo("Shoot/IMG_0001.JPG"))
            try select([PhotoAddress(url: photo), PhotoAddress(url: photo, version: first)], in: model)

            #expect(await model.trash(model.selectedIndexIDs()) == nil)
            #expect(model.undoNotice.text == "Moved IMG_0002.JPG to the Trash")
            await model.filesMade()
            #expect(!FileManager.default.fileExists(atPath: photo.path))
            try await sandbox.eventually { model.library.count == 1 }

            #expect(model.perform(.undo))
            await model.filesMade()
            #expect(versions(of: photo) == [first, second], "its sidecar as it went")
            try await sandbox.eventually { model.library.count == 4 }
        }
    }

    @Test func `in Develop the version open goes, the photo's own edit opening in its place, and Undo puts it back`(
    ) async throws {
        try await withShoot(in: .develop) { sandbox, model, photo in
            let version = PhotoAddress(url: photo, version: first)
            model.select(version)
            try await sandbox.eventually { model.openPhoto == version }

            #expect(model.canPerform(.moveToTrash) && model.moveToTrash())
            try await sandbox.eventually { model.undoNotice.text == "Removed version “Copy 1” of IMG_0002.JPG" }
            await model.filesMade()
            #expect(model.openPhoto == PhotoAddress(url: photo), "its own edit open in its place")
            #expect(model.versions.map(\.id) == [second])
            #expect(FileManager.default.fileExists(atPath: photo.path))
            try await sandbox.eventually { versions(of: photo) == [second] }

            #expect(model.undoFiles())
            await model.filesMade()
            #expect(model.versions.map(\.id) == [first, second])
            try await sandbox.eventually { versions(of: photo) == [first, second] }
            #expect(SidecarStore().load(for: photo)?.version(first)?.metadata?.rating == 1)
        }
    }
}
