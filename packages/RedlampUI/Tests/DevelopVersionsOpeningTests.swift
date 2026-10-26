import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Develop opening a version (LIB-48): the version chosen is known before its photo starts opening, so the thumbnail
/// and badges shown until its sidecar is read are the version's, the photo is built for the version's edit, which is
/// the first shown, and a rating given meanwhile is the version's. A file's own row opens as it always has.
@MainActor
struct DevelopVersionsOpeningTests {
    /// IMG_1.JPG, rated 1 with an edit of exposure 1, and its version, rated 4 with an edit of exposure -1 at process
    /// 16, beside IMG_2.JPG; their renders made, All Photographs shown, and Develop open on IMG_2.
    private struct Photos {
        let fixture: EditRenderFixture
        let model: EditorModel
        let url: URL
        let other: URL
        let version: UUID
        let reads = Gate()

        var own: PhotoAddress {
            PhotoAddress(url: url)
        }

        var copy: PhotoAddress {
            PhotoAddress(url: url, version: version)
        }

        /// The edits Develop's engine has been asked to render since `count` of them.
        func rendered(since count: Int) -> [Double] {
            fixture.editor.renders.dropFirst(count).map { $0.recipe[.exposure] }
        }

        /// The raw revision Develop's engine last expected IMG_1 to be built at.
        var expectedRevision: RawRevision? {
            fixture.editor.expected.withLock { expected in expected.last { $0.url == url }?.revision }
        }

        /// IMG_1's sidecar as it is on disk.
        var saved: Sidecar? {
            SidecarStore().load(for: url)
        }
    }

    private func photos(_ fixture: EditRenderFixture) async throws -> Photos {
        try fixture.photos(["IMG_1.JPG", "IMG_2.JPG"])
        let version = UUID()
        var older = EditRenderFixture.recipe(exposure: -1)
        older.processVersion = 16
        var sidecar = Sidecar(recipe: EditRenderFixture.recipe(exposure: 1), metadata: PhotoMetadata(rating: 1))
        sidecar.versions = [
            PhotoVersion(id: version, name: "Copy 1", recipe: older, metadata: PhotoMetadata(rating: 4)),
        ]
        let url = fixture.photo("IMG_1.JPG")
        try SidecarStore().save(sidecar, for: url)
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 3)
        fixture.renders.isRunning = true
        try await fixture.eventually { fixture.renders.statistics.rendered == 2 }
        try #require(fixture.renders.statistics.rendered == 2, "the file's edit and its version's rendered")
        let model = try #require(fixture.model)
        let other = fixture.photo("IMG_2.JPG")
        model.select(PhotoAddress(url: other))
        model.showModule(.develop)
        try await fixture.eventually { model.info?.url == other }
        try #require(model.info?.url == other)
        let photos = Photos(fixture: fixture, model: model, url: url, other: other, version: version)
        model.beforeReadingSidecar = { [reads = photos.reads] _ in await reads.pass() }
        return photos
    }

    @Test func `a version not decoded yet shows its own render and badges while it opens, then its own edit first`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        let renders = fixture.editor.renders.count
        photos.reads.hold()

        model.select(photos.copy)
        try await fixture.eventually { photos.reads.arrived > 0 && model.selectionThumbnail != nil }
        #expect(model.isLoading && model.info == nil, "its placeholder shows")
        #expect(
            EditRenderFixture.isRender(model.selectionThumbnail, exposure: -1),
            "the version's render, not its file's",
        )
        #expect(model.photoMetadata.rating == 4, "the version's rating")
        #expect(model.activeAddress == photos.copy)

        photos.reads.release()
        try await fixture.eventually { model.info?.url == photos.url && !photos.rendered(since: renders).isEmpty }
        #expect(model.openVersion == photos.version && model.value(.exposure) == -1)
        #expect(model.photoMetadata.rating == 4)
        let rendered = photos.rendered(since: renders)
        #expect(
            rendered.first == -1 && !rendered.contains(1),
            "the version's edit is the first rendered, its file's never",
        )
        #expect(photos.expectedRevision == .third, "the photo is built for the version's edit, at process 16")
    }

    @Test func `a decoded version shows its own thumbnail at once while its sidecar is read`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        for photo in [photos.own, photos.copy] {
            let item = try #require(fixture.item(photo))
            #expect(await model.thumbnailLoader.image(for: item) != nil)
        }
        fixture.editor.ready = [photos.url]
        model.openingPatience = .seconds(30)
        let renders = fixture.editor.renders.count
        photos.reads.hold()

        model.select(photos.copy)
        #expect(model.opening == photos.url)
        #expect(EditRenderFixture.isRender(model.selectionThumbnail, exposure: -1), "the version's, not its file's")
        try await fixture.eventually { photos.reads.arrived > 0 }
        photos.reads.release()
        try await fixture.eventually { model.info?.url == photos.url && !photos.rendered(since: renders).isEmpty }
        #expect(model.openVersion == photos.version && model.value(.exposure) == -1)
        let rendered = photos.rendered(since: renders)
        #expect(
            rendered.first == -1 && !rendered.contains(1),
            "the version's edit is the first rendered, its file's never",
        )
    }

    @Test func `the file's own row opens in its own edit, with its own render and badges until then`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        let renders = fixture.editor.renders.count
        photos.reads.hold()

        model.select(photos.own)
        try await fixture.eventually { photos.reads.arrived > 0 && model.selectionThumbnail != nil }
        #expect(EditRenderFixture.isRender(model.selectionThumbnail, exposure: 1), "the file's own render")
        #expect(model.photoMetadata.rating == 1 && model.activeAddress == photos.own)

        photos.reads.release()
        try await fixture.eventually { model.info?.url == photos.url && !photos.rendered(since: renders).isEmpty }
        #expect(model.openVersion == nil && model.value(.exposure) == 1 && model.photoMetadata.rating == 1)
        let rendered = photos.rendered(since: renders)
        #expect(rendered.first == 1 && !rendered.contains(-1))
        #expect(photos.expectedRevision == .fourth, "built for the file's own edit")
    }

    @Test func `a rating given while a version opens is the version's, its file's staying as it was`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        photos.reads.hold()

        model.select(photos.copy)
        try await fixture.eventually { photos.reads.arrived > 0 }
        model.cull(.rating(5))
        #expect(model.photoMetadata.rating == 5)
        #expect(fixture.item(photos.copy)?.metadata.rating == 5, "the version's row")
        #expect(fixture.item(photos.own)?.metadata.rating == 1, "not its file's")

        photos.reads.release()
        try await fixture.eventually { model.info?.url == photos.url }
        #expect(model.openVersion == photos.version && model.photoMetadata.rating == 5)
        #expect(fixture.item(photos.copy)?.metadata.rating == 5 && fixture.item(photos.own)?.metadata.rating == 1)
        try await fixture.eventually { photos.saved?.version(photos.version)?.metadata?.rating == 5 }
        #expect(photos.saved?.version(photos.version)?.metadata?.rating == 5)
        #expect(photos.saved?.metadata?.rating == 1, "the file's own metadata keeps its rating")
    }

    @Test func `another of the photo's edits chosen while it opens shows its render and opens in its place`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        photos.reads.hold()

        model.select(photos.own)
        try await fixture.eventually { photos.reads.arrived > 0 && model.selectionThumbnail != nil }
        #expect(EditRenderFixture.isRender(model.selectionThumbnail, exposure: 1))
        model.select(photos.copy)
        try await fixture.eventually { EditRenderFixture.isRender(model.selectionThumbnail, exposure: -1) }
        #expect(
            EditRenderFixture.isRender(model.selectionThumbnail, exposure: -1),
            "the version's render takes its place",
        )
        #expect(model.photoMetadata.rating == 4 && model.activeAddress == photos.copy)

        photos.reads.release()
        try await fixture.eventually { model.info?.url == photos.url }
        #expect(model.openVersion == photos.version && model.value(.exposure) == -1)
    }

    @Test func `back on the photo open before the next was read, the version chosen opens in place of its edit open`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        fixture.editor.ready = [photos.url, photos.other]
        model.select(photos.own)
        try await fixture.eventually { model.info?.url == photos.url }
        try #require(model.info?.url == photos.url && model.openVersion == nil)
        model.openingPatience = .seconds(30)
        photos.reads.hold()
        model.select(PhotoAddress(url: photos.other))
        try await fixture.eventually { photos.reads.arrived > 0 }
        try #require(model.opening == photos.other)

        model.select(photos.copy)
        #expect(model.opening == nil && model.info?.url == photos.url)
        #expect(model.openVersion == photos.version && model.value(.exposure) == -1, "the version chosen")
        #expect(model.activeAddress == photos.copy)
        photos.reads.release()
    }
}
