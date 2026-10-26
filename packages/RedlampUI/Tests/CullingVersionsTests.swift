import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Culling versions the library lists as photos of their own (LIB-48): a change to a version shown in a source reaches
/// the version's row and its edit in the sidecar, never its file's, with Undo and Redo; one to the file's own row
/// reaches the file's edit; Develop's culling of the version open reaches the version's.
@MainActor
@Suite(.serialized)
struct CullingVersionsTests {
    private let version = UUID()

    /// Small JPEGs `names` below Shoot, the last with a version, Copy 1, rated 1; the library open and All Photographs
    /// shown, the version's row with the rest; with `large`, its rows read as they're asked for.
    private func open(_ names: [String], large: Bool = false) async throws -> (SourcesSandbox, EditorModel, URL) {
        let sandbox = SourcesSandbox()
        try sandbox.photos(names.map { "Shoot/\($0)" })
        let photo = sandbox.photo("Shoot/\(names[names.count - 1])")
        var sidecar = Sidecar(recipe: EditRecipe())
        sidecar.versions = [
            PhotoVersion(id: version, name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 1)),
        ]
        try SidecarStore().saveOrRemove(sidecar, for: photo)
        let model = try await sandbox.open()
        if large {
            model.library.largestRead = 4
            model.library.firstRead = 2
        }
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually { !model.librarySources.isListing && model.library.count == names.count + 1 }
        if !large {
            try #require(
                model.library.index(of: PhotoAddress(url: photo, version: version)) != nil,
                "the version listed",
            )
        }
        return (sandbox, model, photo)
    }

    private static func values(rating: Int = 0, flag: PhotoFlag? = nil) -> CullingValues {
        var metadata = PhotoMetadata(rating: rating)
        metadata.flag = flag
        return CullingValues(metadata)
    }

    /// `photo`'s own edit and its version, as the library addresses them.
    private func edits(of photo: URL) -> [PhotoAddress] {
        [PhotoAddress(url: photo), PhotoAddress(url: photo, version: version)]
    }

    /// The culling fields of `photo`'s own edit and of its version, as its sidecar holds them.
    private func sidecar(_ photo: URL) -> [CullingValues] {
        let sidecar = SidecarStore().load(for: photo)
        return [sidecar?.metadata, sidecar?.version(version)?.metadata].map { CullingValues($0 ?? PhotoMetadata()) }
    }

    /// The culling fields of the rows of `photo`'s own edit and of its version, as the index holds them.
    private func rows(_ photo: URL, _ sandbox: SourcesSandbox) async throws -> [CullingValues] {
        let core = try #require(sandbox.service?.core)
        let photos = edits(of: photo)
        let ids = await LibraryService.indexIDs(of: photos, in: core.index)
        try #require(ids.count == 2, "a row for the file and one for its version")
        return try await core.index.read { reader in
            try photos.map { photo in
                let row = try ids[photo].flatMap { try reader.photo(id: $0) }
                var metadata = PhotoMetadata(rating: row?.rating ?? 0)
                metadata.flag = row?.flag
                return CullingValues(metadata)
            }
        }
    }

    /// The culling fields of `photo`'s own edit and of its version, as their rows in the list show them.
    private func shown(_ photo: URL, in model: EditorModel) -> [CullingValues] {
        edits(of: photo).map { photo in
            CullingValues(model.library.index(of: photo).flatMap { model.library.items.row($0) }?.metadata
                ?? PhotoMetadata())
        }
    }

    private func settle(_ model: EditorModel, _ sandbox: SourcesSandbox) async throws {
        try await sandbox.eventually { !model.isWritingCulling }
        await sandbox.service?.settled()
    }

    @Test func `culling a version in All Photographs changes only its row and its edit, with Undo and Redo`(
    ) async throws {
        let (sandbox, model, photo) = try await open(["A.JPG", "B.JPG"])
        defer { sandbox.remove() }
        let copy = PhotoAddress(url: photo, version: version)
        model.select(copy)
        try #require(model.selectedIDs == [model.library.photoID(of: copy)], "the version selected alone")
        #expect(model.perform(.rating3))
        try await settle(model, sandbox)
        let rated = [Self.values(), Self.values(rating: 3)]
        #expect(sidecar(photo) == rated)
        #expect(try await rows(photo, sandbox) == rated)
        #expect(shown(photo, in: model) == rated)

        #expect(model.undoCulling())
        try await settle(model, sandbox)
        let before = [Self.values(), Self.values(rating: 1)]
        #expect(sidecar(photo) == before)
        #expect(try await rows(photo, sandbox) == before)
        #expect(shown(photo, in: model) == before)

        #expect(model.redoCulling())
        try await settle(model, sandbox)
        #expect(sidecar(photo) == rated)
        #expect(try await rows(photo, sandbox) == rated)
        #expect(shown(photo, in: model) == rated)
    }

    @Test func `culling the file's own row changes the file's edit, and a cell's flag reaches the version it shows`(
    ) async throws {
        let (sandbox, model, photo) = try await open(["A.JPG", "B.JPG"])
        defer { sandbox.remove() }
        model.select(photo)
        #expect(model.perform(.rating2))
        try await settle(model, sandbox)
        let rated = [Self.values(rating: 2), Self.values(rating: 1)]
        #expect(sidecar(photo) == rated)
        #expect(try await rows(photo, sandbox) == rated)

        model.cull(.flag(.pick), fromCell: PhotoAddress(url: photo, version: version))
        try await settle(model, sandbox)
        let flagged = [Self.values(rating: 2), Self.values(rating: 1, flag: .pick)]
        #expect(sidecar(photo) == flagged)
        #expect(try await rows(photo, sandbox) == flagged)
        #expect(shown(photo, in: model) == flagged)
    }

    @Test func `a large source's photos culled with their rows unread reach each version's own edit`() async throws {
        let (sandbox, model, photo) = try await open(["A.JPG", "B.JPG", "C.JPG", "D.JPG", "E.JPG"], large: true)
        defer { sandbox.remove() }
        model.select(sandbox.photo("Shoot/A.JPG"))
        model.selectAllPhotos()
        try #require(model.library.items.readsOnRequest && !model.hasReadSelection, "rows not read")
        #expect(model.perform(.flagReject))
        try await sandbox.eventually { model.cullingUndoCount == 1 }
        try await settle(model, sandbox)
        let rejected = [Self.values(flag: .reject), Self.values(rating: 1, flag: .reject)]
        #expect(sidecar(photo) == rejected)
        #expect(try await rows(photo, sandbox) == rejected)

        #expect(model.undoCulling())
        try await settle(model, sandbox)
        #expect(sidecar(photo) == [Self.values(), Self.values(rating: 1)])
        #expect(try await rows(photo, sandbox) == [Self.values(), Self.values(rating: 1)])
    }

    @Test func `Develop's culling of the version open changes the version's row and its edit`() async throws {
        let (sandbox, model, photo) = try await open(["A.JPG", "B.JPG"])
        defer { sandbox.remove() }
        model.select(PhotoAddress(url: photo, version: version))
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }
        try #require(model.openVersion == version, "the version open in Develop")
        #expect(model.perform(.rating4))
        let rated = [Self.values(), Self.values(rating: 4)]
        #expect(shown(photo, in: model) == rated)
        await model.saves.flush()
        #expect(sidecar(photo) == rated)
    }
}
