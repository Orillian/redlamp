import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

extension EditRenderFixture {
    /// Saves to the photo's sidecar its own edit of `exposure` and versions of these exposures, each under its ID, nil
    /// for one without an edit of its own; with `telling`, tells the library, as the editor's saves do.
    func edit(
        _ path: String, exposure: Double, versions: [(id: UUID, exposure: Double?)], telling: Bool = false,
    ) throws {
        var sidecar = Sidecar(recipe: Self.recipe(exposure: exposure))
        sidecar.versions = versions.enumerated().map { number, version in
            PhotoVersion(
                id: version.id, name: "Copy \(number + 1)",
                recipe: version.exposure.map(Self.recipe(exposure:)) ?? EditRecipe(),
            )
        }
        try SidecarStore().save(sidecar, for: photo(path))
        if telling {
            library.sidecarSaved(photo(path))
        }
    }

    /// Shows All Photographs, where each of a file's versions is a photo of its own, once it lists `count` photos.
    func showAllPhotographs(count: Int) async throws {
        try #require(model.librarySources.show(.allPhotographs))
        try await eventually(seconds: 20) { !self.model.librarySources.isListing && self.library.count == count }
        try #require(library.count == count, "the photos and their versions listed")
    }

    func item(_ photo: PhotoAddress) -> RedlampUI.LibraryItem? {
        library.index(of: photo).flatMap { library.items.row($0) }
    }

    /// The index's rows of `photos`, by photo.
    func rows(_ photos: [PhotoAddress]) async throws -> [PhotoAddress: Int64] {
        try await LibraryService.indexIDs(of: photos, in: #require(service.core?.index))
    }

    /// The edit of `photo`'s row, a file's own or one of its versions, whose render the index records as stored,
    /// standing for its sidecar as it is.
    func recordedEdit(_ photo: PhotoAddress) async throws -> EditDigest? {
        let index = try #require(service.core?.index)
        guard let id = try await rows([photo])[photo] else { return nil }
        return try await index.read { try $0.standingPhotoEdits(ofPhotos: [id], renderer: EditRenders.renderer)[id] }
    }

    func waitForRecord(_ photo: PhotoAddress, _ edit: EditDigest) async throws {
        for _ in 0 ..< 2000 where try await recordedEdit(photo) != edit {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(try await recordedEdit(photo) == edit, "the render of \(photo)'s edit is recorded under its row")
    }
}

/// Renders of versions (LIB-48): each of a file's versions a source shows is rendered with its own edit and recorded
/// under its own row; a file's photos with the same edit share one render; a change to a version's edit renders it
/// alone; and its cells, the loupe and Develop's placeholder show its own edit.
@MainActor
extension EditRendersTests {
    @Test func `a photo's versions with edits of their own are each rendered with theirs, recorded under their own rows`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        try fixture.photos(["IMG_1.JPG", "IMG_2.JPG"])
        let (first, second) = (UUID(), UUID())
        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(first, -1), (second, 0.5)])
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 4)
        let url = fixture.photo("IMG_1.JPG")
        let photos = [nil, first, second].map { PhotoAddress(url: url, version: $0) }
        let exposures = [1.0, -1, 0.5]
        let digests = try exposures.map(EditRenderFixture.digest(exposure:))

        fixture.renders.isRunning = true
        try await fixture.eventually { fixture.renders.statistics.rendered == 3 }
        #expect(fixture.renders.statistics.rendered == 3 && fixture.renders.statistics.failed == 0)
        #expect(fixture.engine.rendered.withLock { $0.map { $0.recipe[.exposure] } }.sorted() == exposures.sorted())
        #expect(fixture.engine.opened.withLock { $0 } == [url, url, url], "the file, once for each of its edits")
        let key = try #require(fixture.key("IMG_1.JPG"))
        #expect(fixture.store.edits(of: key) == Set(digests), "three renders of the one file")
        for (photo, (exposure, digest)) in zip(photos, zip(exposures, digests)) {
            let item = try #require(fixture.item(photo))
            #expect(fixture.renders.shownEdit(for: item) == digest)
            let thumbnail = await fixture.model.thumbnailLoader.image(for: item)
            #expect(EditRenderFixture.isRender(thumbnail, exposure: exposure), "each row's thumbnail shows its edit")
            try await fixture.waitForRecord(photo, digest)
        }
        let rows = try await fixture.rows(photos)
        #expect(rows.count == 3 && Set(rows.values).count == 3, "each recorded under a row of its own")
    }

    @Test func `a version with its file's edit shows the file's render, made once, as does one made from it later`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        try fixture.photos(["IMG_1.JPG"])
        let (copy, later) = (UUID(), UUID())
        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(copy, 1)])
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 2)
        let url = fixture.photo("IMG_1.JPG")
        let digest = try EditRenderFixture.digest(exposure: 1)
        let shows = { (photos: [PhotoAddress]) in
            photos.allSatisfy { fixture.item($0).flatMap(fixture.renders.shownEdit(for:)) == digest }
        }

        let photos = [nil, copy].map { PhotoAddress(url: url, version: $0) }
        fixture.renders.isRunning = true
        try await fixture.eventually { shows(photos) }
        #expect(shows(photos), "the file and its version show the render")
        #expect(fixture.renders.statistics.rendered == 1 && fixture.engine.rendered.withLock { $0.count } == 1)
        for photo in photos {
            try await fixture.waitForRecord(photo, digest)
        }
        let thumbnails = try await [
            fixture.model.thumbnailLoader.image(for: #require(fixture.item(photos[0]))),
            fixture.model.thumbnailLoader.image(for: #require(fixture.item(photos[1]))),
        ]
        #expect(EditRenderFixture.isRender(thumbnails[0], exposure: 1))
        #expect(thumbnails[0] === thumbnails[1], "one thumbnail for both")

        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(copy, 1), (later, 1)], telling: true)
        try await fixture.eventually { fixture.library.count == 3 }
        let all = photos + [PhotoAddress(url: url, version: later)]
        try await fixture.eventually { shows(all) }
        #expect(shows(all), "a version made later shows it at once")
        try await fixture.waitForRecord(all[2], digest)
        #expect(fixture.renders.statistics.rendered == 1, "rendered once still")
        #expect(try fixture.store.edits(of: #require(fixture.key("IMG_1.JPG"))) == [digest])
    }

    @Test func `a change to a version's edit renders that version alone, its old edit's render leaving the store`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        try fixture.photos(["IMG_1.JPG", "IMG_2.JPG"])
        let (first, second) = (UUID(), UUID())
        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(first, -1), (second, 0.5)])
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 4)
        let url = fixture.photo("IMG_1.JPG")
        let photos = [nil, first, second].map { PhotoAddress(url: url, version: $0) }
        let (own, old, new, other) = try (
            EditRenderFixture.digest(exposure: 1), EditRenderFixture.digest(exposure: -1),
            EditRenderFixture.digest(exposure: -0.5), EditRenderFixture.digest(exposure: 0.5),
        )
        fixture.renders.isRunning = true
        try await fixture.eventually { fixture.renders.statistics.rendered == 3 }
        try #require(fixture.renders.statistics.rendered == 3)

        fixture.engine.gate.hold()
        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(first, -0.5), (second, 0.5)], telling: true)
        try await fixture.eventually { fixture.engine.gate.arrived == 1 }
        #expect(fixture.engine.gate.arrived == 1 && fixture.engine.rendered
            .withLock { $0.last?.recipe[.exposure] } == -0.5)
        let changed = try #require(fixture.item(photos[1]))
        #expect(fixture.renders.shownEdit(for: changed) == nil && fixture.renders.renders(changed), "marked meanwhile")
        let unchanged = [photos[0], photos[2]]
        try await fixture.eventually {
            unchanged.allSatisfy { fixture.item($0).flatMap(fixture.renders.isRendered) == true }
        }
        #expect(fixture.item(photos[0]).flatMap(fixture.renders.shownEdit(for:)) == own, "the file keeps its render")
        #expect(fixture.item(photos[2]).flatMap(fixture.renders.shownEdit(for:)) == other, "so does the other version")
        let key = try #require(fixture.key("IMG_1.JPG"))
        try await fixture.eventually { !fixture.store.edits(of: key).contains(old) }
        #expect(fixture.store.edits(of: key) == [own, other], "the version's old edit's render leaves the store")

        fixture.engine.gate.release()
        try await fixture.eventually { fixture.item(photos[1]).flatMap(fixture.renders.shownEdit(for:)) == new }
        #expect(fixture.item(photos[1]).flatMap(fixture.renders.shownEdit(for:)) == new)
        #expect(fixture.renders.statistics.rendered == 4, "that version's edit alone rendered again")
        #expect(fixture.store.edits(of: key) == [own, new, other])
        for (photo, digest) in zip(photos, [own, new, other]) {
            try await fixture.waitForRecord(photo, digest)
        }
    }

    @Test func `a version's cell shows its embedded preview marked until its edit renders, an unedited version's unmarked`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        try fixture.photos(["IMG_1.JPG", "IMG_2.JPG"])
        let (edited, plain) = (UUID(), UUID())
        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(edited, -1), (plain, nil)])
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 4)
        let model = try #require(fixture.model)
        let grid = LibraryGridView(model: model)
        fixture.show(grid)
        let url = fixture.photo("IMG_1.JPG")
        let photos = [nil, edited, plain].map { PhotoAddress(url: url, version: $0) }
        let cell = { (photo: PhotoAddress) in grid.cells.values.first { $0.item?.address == photo } }
        try await fixture.eventually { photos.allSatisfy { cell($0)?.image != nil } }
        let (own, version, unedited) = try (
            #require(cell(photos[0])),
            #require(cell(photos[1])),
            #require(cell(photos[2])),
        )
        #expect(own.showsUneditedPreview && version.showsUneditedPreview, "embedded previews, marked")
        #expect(!unedited.showsUneditedPreview && unedited.shownEdit == nil, "an unedited version's, unmarked")

        fixture.renders.isRunning = true
        let (brighter, darker) = try (EditRenderFixture.digest(exposure: 1), EditRenderFixture.digest(exposure: -1))
        try await fixture.eventually { own.shownEdit == brighter && version.shownEdit == darker }
        #expect(version.shownEdit == darker && !version.showsUneditedPreview, "the version's own render, unmarked")
        #expect(EditRenderFixture.isRender(version.image, exposure: -1))
        #expect(own.shownEdit == brighter && EditRenderFixture.isRender(own.image, exposure: 1))
        #expect(!unedited.showsUneditedPreview && unedited.shownEdit == nil, "as the file's unedited photo would show")
        #expect(!EditRenderFixture.isRender(unedited.image, exposure: 1) && !EditRenderFixture.isRender(
            unedited.image, exposure: -1,
        ))
        #expect(fixture.renders.statistics.rendered == 2, "nothing rendered for the unedited version")
    }

    @Test func `the loupe shows the active version's own edit, and Develop the version it opens until its render lands`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        try fixture.photos(["IMG_1.JPG", "IMG_2.JPG"])
        let copy = UUID()
        try fixture.edit("IMG_1.JPG", exposure: 1, versions: [(copy, -1)])
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 3)
        fixture.renders.isRunning = true
        try await fixture.eventually { fixture.renders.statistics.rendered == 2 }
        let model = try #require(fixture.model)
        let url = fixture.photo("IMG_1.JPG")
        let version = PhotoAddress(url: url, version: copy)
        let (brighter, darker) = try (EditRenderFixture.digest(exposure: 1), EditRenderFixture.digest(exposure: -1))

        model.select(version)
        model.showLibrary(.loupe)
        let loupe = LibraryLoupeView(model: model)
        fixture.show(loupe)
        try await fixture.eventually { loupe.showsPreview && loupe.shownEdit == darker }
        #expect(loupe.shownEdit == darker && EditRenderFixture.isRender(loupe.image, exposure: -1), "the version's")
        model.select(PhotoAddress(url: url))
        try await fixture.eventually { loupe.showsPreview && loupe.shownEdit == brighter }
        #expect(loupe.shownEdit == brighter && EditRenderFixture.isRender(loupe.image, exposure: 1), "the file's own")

        model.select(version)
        try await fixture.eventually { loupe.showsPreview && loupe.shownEdit == darker }
        model.showModule(.develop)
        #expect(EditRenderFixture.isRender(model.selectionThumbnail, exposure: -1), "Develop shows the version's")
    }
}
