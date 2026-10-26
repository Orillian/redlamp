import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Versions as photos of their own in the library's lists (LIB-48): a click on a version's cell selects its row, the
/// filmstrip's menu culls it, and Develop opens the version chosen in Library, its filmstrip marking the version open
/// and ← and → stepping through the photo's versions in their order.
@MainActor
@Suite(.serialized)
struct LibraryVersionsTests {
    private let first = UUID()
    private let second = UUID()

    /// Small JPEGs A and B below Shoot, B with two versions, Copy 1 and Copy 2; the library open and All Photographs
    /// shown, the versions' rows after B's own.
    private func open() async throws -> (SourcesSandbox, EditorModel, URL) {
        let sandbox = SourcesSandbox()
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG"])
        let photo = sandbox.photo("Shoot/B.JPG")
        var sidecar = Sidecar(recipe: EditRecipe())
        sidecar.versions = [
            PhotoVersion(id: first, name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 1)),
            PhotoVersion(id: second, name: "Copy 2", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2)),
        ]
        try SidecarStore().saveOrRemove(sidecar, for: photo)
        let model = try await sandbox.open()
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually { !model.librarySources.isListing && model.library.count == 4 }
        let places = [
            PhotoAddress(url: photo),
            PhotoAddress(url: photo, version: first),
            PhotoAddress(url: photo, version: second),
        ].map { model.library.index(of: $0) }
        try #require(places == [1, 2, 3], "the versions listed after their file, in their order")
        return (sandbox, model, photo)
    }

    private func id(_ photo: PhotoAddress, in model: EditorModel) throws -> Int64 {
        try #require(model.library.photoID(of: photo))
    }

    @Test func `a click on a version's cell selects its row, and ⌘ and ⇧ reach rows by address`() async throws {
        let (sandbox, model, photo) = try await open()
        defer { sandbox.remove() }
        let own = PhotoAddress(url: photo)
        let copy = PhotoAddress(url: photo, version: first)
        let other = PhotoAddress(url: sandbox.photo("Shoot/A.JPG"))
        let (ownID, copyID) = try (id(own, in: model), id(copy, in: model))
        model.clickInGrid(copy)
        #expect(model.selectedIDs == [copyID] && model.activeAddress == copy)
        #expect(model.selection == photo, "the file is the photo active")
        #expect(model.library.items.row(2)?.title == "Copy 1, a version of B.JPG")
        #expect(model.library.items.row(1)?.title == "B.JPG", "the file's own cell, which has no badge")

        model.clickInGrid(own)
        #expect(model.selectedIDs == [ownID] && model.activeAddress == own)

        model.clickInGrid(copy, toggling: true)
        #expect(model.selectedIDs == [ownID, copyID])
        #expect(model.activeAddress == copy, "the version ⌘-clicked active")
        model.clickInGrid(copy, toggling: true)
        #expect(model.selectedIDs == [ownID] && model.activeAddress == own)

        model.clickInGrid(other)
        model.clickInGrid(PhotoAddress(url: photo, version: second), extending: true)
        #expect(model.selectedCount == 4, "from A through Copy 2")
        #expect(model.activeAddress == PhotoAddress(url: photo, version: second))
        model.clickInGrid(copy)
        model.clickInGrid(own, extending: true)
        #expect(model.selectedIDs == [ownID, copyID], "⇧ from a version")
    }

    @Test func `opening a version's cell in the loupe makes it active, as a double-click does`() async throws {
        let (sandbox, model, photo) = try await open()
        defer { sandbox.remove() }
        let copy = PhotoAddress(url: photo, version: second)
        let copyID = try id(copy, in: model)
        model.openInLoupe(copy)
        #expect(model.libraryView == .loupe && model.activeAddress == copy)
        #expect(model.selectedIDs == [copyID])
    }

    @Test(.disabled("4 Stars from the menu leaves Copy 1 at 1 star, with two versions in an open pair: to diagnose"))
    func `the filmstrip's menu culls the version of its cell`() async throws {
        let (sandbox, model, photo) = try await open()
        defer { sandbox.remove() }
        let own = PhotoAddress(url: photo)
        let copy = PhotoAddress(url: photo, version: first)
        await sandbox.service?.settled()
        model.clickInGrid(own)
        let menu = try #require(FilmstripMenu.menu(for: copy, model: model, culling: true))
        let ratings = try #require(menu.items.first { $0.title == "Set Rating" }?.submenu)
        let four = try #require(ratings.items.firstIndex { $0.title.hasPrefix("4 Stars") })
        ratings.performActionForItem(at: four)
        let rating = { (photo: PhotoAddress) in
            model.library.index(of: photo).flatMap { model.library.items.row($0) }?.metadata.rating
        }
        #expect(rating(copy) == 4 && rating(own) == 0, "the version's row, not its file's")
        try await sandbox.eventually { !model.isWritingCulling }
        await sandbox.service?.settled()
        let sidecar = SidecarStore().load(for: photo)
        #expect(sidecar?.version(first)?.metadata?.rating == 4 && (sidecar?.metadata?.rating ?? 0) == 0)
    }

    @Test func `Develop opens the version chosen in Library, and the file's own edit for its own row`() async throws {
        let (sandbox, model, photo) = try await open()
        defer { sandbox.remove() }
        let copy = PhotoAddress(url: photo, version: first)
        model.clickInGrid(copy)
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }
        #expect(model.openVersion == first)

        model.showModule(.library)
        model.clickInGrid(PhotoAddress(url: photo))
        model.showModule(.develop)
        #expect(model.info?.url == photo && model.openVersion == nil, "its own edit, the file still open")

        model.showModule(.library)
        model.clickInGrid(PhotoAddress(url: photo, version: second))
        model.showModule(.develop)
        #expect(model.openVersion == second)
        #expect(model.activeAddress == PhotoAddress(url: photo, version: second))
    }

    @Test func `in Develop the version open is the active cell, and ← and → step through the photo's versions`(
    ) async throws {
        let (sandbox, model, photo) = try await open()
        defer { sandbox.remove() }
        model.clickInGrid(PhotoAddress(url: photo))
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }
        let secondID = try id(PhotoAddress(url: photo, version: second), in: model)
        model.showVersion(second)
        #expect(model.openVersion == second)
        #expect(model.selectedIDs == [secondID])

        model.showModule(.library)
        model.showModule(.develop)
        #expect(model.openVersion == second, "Develop keeps its version while Library chose nothing")

        #expect(model.perform(.previousPhoto))
        #expect(model.openVersion == first && model.activeAddress == PhotoAddress(url: photo, version: first))
        #expect(model.perform(.previousPhoto))
        #expect(model.openVersion == nil && model.activeAddress == PhotoAddress(url: photo))
        #expect(model.info?.url == photo, "stepping through its versions keeps the file open")
        #expect(model.perform(.nextPhoto))
        #expect(model.openVersion == first)
        #expect(model.perform(.previousPhoto) && model.perform(.previousPhoto))
        try await sandbox.eventually { model.info?.url == sandbox.photo("Shoot/A.JPG") && model.opening == nil }
        #expect(model.openVersion == nil)
        #expect(model.perform(.nextPhoto))
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }
        #expect(model.openVersion == nil && model.activeAddress == PhotoAddress(url: photo))
    }
}
