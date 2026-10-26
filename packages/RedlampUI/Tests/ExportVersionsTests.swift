import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Export of versions the library lists as photos of their own (LIB-48): each is named from its own row, its name for
/// `{version}` and its own fields, and exported with its own edit (`BatchExportTests`).
@MainActor
@Suite(.serialized)
struct ExportVersionsTests {
    @Test func `a selection's versions are named with their own names and fields, the file's own edit with its own`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/IMG_0001.JPG"])
        let photo = sandbox.photo("Shoot/IMG_0001.JPG")
        let copy = UUID()
        var sidecar = Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2))
        sidecar.versions = [
            PhotoVersion(id: copy, name: "Black and white", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 5)),
        ]
        try SidecarStore().saveOrRemove(sidecar, for: photo)
        let model = try await sandbox.open()
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually { !model.librarySources.isListing && model.library.count == 2 }

        let read = ExportActions.reader(
            for: SelectedPhotos([PhotoAddress(url: photo), PhotoAddress(url: photo, version: copy)]), model: model,
        )
        let photos = await read()
        #expect(photos.map(\.address) == [PhotoAddress(url: photo), PhotoAddress(url: photo, version: copy)])
        #expect(photos.map(\.naming.url) == [photo, photo])
        #expect(photos.map(\.naming.fields.version) == [nil, "Black and white"])
        #expect(photos.map(\.naming.fields.rating) == [2, 5])
    }
}
