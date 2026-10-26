import AppKit
import Foundation
import RedlampDocument
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Versions in Compare (C) and Survey (N) (LIB-48): a version is a photo of its own beside its file, as Lightroom
/// Classic compares a virtual copy with its master. Each is shown with its own edit, name, rating, flag and label;
/// the select and the candidate, their swap and steps, culling and Survey's × reach each by its address.
@MainActor
struct CompareVersionsTests {
    /// IMG_1.JPG, rated 1 with an edit of exposure 1, and its versions Copy 1, rated 4 and picked with an edit of
    /// exposure -1, and Copy 2, rated 2 with an edit of exposure 0.5, between IMG_0.JPG and IMG_2.JPG; their renders
    /// made and All Photographs shown in Library.
    @MainActor private struct Photos {
        let fixture: EditRenderFixture
        let model: EditorModel
        let own: PhotoAddress
        let first: PhotoAddress
        let second: PhotoAddress
        /// The photo after IMG_1's versions in the source.
        let after: PhotoAddress

        func metadata(_ photo: PhotoAddress) -> PhotoMetadata? {
            fixture.item(photo)?.metadata
        }

        /// The metadata of `photo`'s edit in IMG_1's sidecar as it is on disk.
        func saved(_ photo: PhotoAddress) -> PhotoMetadata? {
            SidecarStore().load(for: own.url)?[edit: photo.version]?.metadata
        }
    }

    private func photos(_ fixture: EditRenderFixture) async throws -> Photos {
        try fixture.photos(capturedInOrder: ["IMG_0.JPG", "IMG_1.JPG", "IMG_2.JPG"])
        let (first, second) = (UUID(), UUID())
        var sidecar = Sidecar(recipe: EditRenderFixture.recipe(exposure: 1), metadata: PhotoMetadata(rating: 1))
        sidecar.versions = [
            PhotoVersion(
                id: first, name: "Copy 1", recipe: EditRenderFixture.recipe(exposure: -1),
                metadata: PhotoMetadata(rating: 4, flag: .pick),
            ),
            PhotoVersion(
                id: second, name: "Copy 2", recipe: EditRenderFixture.recipe(exposure: 0.5),
                metadata: PhotoMetadata(rating: 2),
            ),
        ]
        let url = fixture.photo("IMG_1.JPG")
        try SidecarStore().save(sidecar, for: url)
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 5)
        fixture.renders.isRunning = true
        try await fixture.eventually { fixture.renders.statistics.rendered == 3 }
        try #require(fixture.renders.statistics.rendered == 3, "the file's edit and each version's")
        let edits = [nil, first, second].map { PhotoAddress(url: url, version: $0) }
        let rows = try edits.map { try #require(fixture.library.index(of: $0)) }
        try #require(rows == [1, 2, 3], "a photo, the file's own row, its versions, then a photo")
        return try Photos(
            fixture: fixture, model: #require(fixture.model), own: edits[0], first: edits[1], second: edits[2],
            after: #require(fixture.library.items.row(4)).address,
        )
    }

    /// Compare's view in a window, its images from a grid's.
    private func compareView(_ photos: Photos) -> LibraryCompareView {
        let view = LibraryCompareView(model: photos.model, images: LibraryGridView(model: photos.model).thumbnails)
        photos.fixture.show(view)
        return view
    }

    private func surveyView(_ photos: Photos) -> LibrarySurveyView {
        let view = LibrarySurveyView(model: photos.model, images: LibraryGridView(model: photos.model).thumbnails)
        photos.fixture.show(view)
        return view
    }

    @Test func `C compares a version with its file, each with its own edit, name and badges`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        model.click(photos.own)
        model.click(photos.first, toggling: true)
        #expect(model.perform(.compareView) && model.libraryView == .compare)
        let compare = model.libraryCompare
        #expect(compare.select == photos.first && compare.candidate == photos.own, "the active version, then its file")
        #expect(model.activeAddress == photos.first && model.selectedCount == 2)

        let view = compareView(photos)
        let (select, candidate) = try (#require(view.halves[.select]), #require(view.halves[.candidate]))
        try await fixture.eventually { [select, candidate].allSatisfy { $0.photo.shownEdit != nil } }
        #expect(select.photo.address == photos.first && candidate.photo.address == photos.own)
        #expect(EditRenderFixture.isRender(select.photo.image, exposure: -1), "the version's own edit")
        #expect(EditRenderFixture.isRender(candidate.photo.image, exposure: 1), "its file's")
        #expect(select.photo.isActive && !candidate.photo.isActive)
        #expect(select.item?.title == "Copy 1, a version of IMG_1.JPG" && candidate.item?.title == "IMG_1.JPG")
        #expect(select.photo.accessibilityLabel() == "Copy 1, a version of IMG_1.JPG")
        #expect(select.badges.metadata?.rating == 4 && select.badges.metadata?.flag == .pick)
        #expect(candidate.badges.metadata?.rating == 1 && candidate.badges.metadata?.flag == nil)
    }

    @Test func `two versions of one file are compared, swapped, stepped through and made the select by address`()
        async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        let compare = model.libraryCompare
        model.click(photos.first)
        model.click(photos.second, toggling: true)
        #expect(model.perform(.compareView))
        #expect(compare.select == photos.second && compare.candidate == photos.first)
        let view = compareView(photos)
        try await fixture.eventually { view.halves.values.allSatisfy { $0.photo.shownEdit != nil } }
        #expect(EditRenderFixture.isRender(view.halves[.select]?.photo.image, exposure: 0.5))
        #expect(EditRenderFixture.isRender(view.halves[.candidate]?.photo.image, exposure: -1))

        #expect(model.perform(.swapCompared))
        #expect(compare.select == photos.first && compare.candidate == photos.second)
        #expect(compare.activeSide == .candidate && model.activeAddress == photos.second, "the active photo stays so")
        model.activateCompared(.select)
        #expect(model.activeAddress == photos.first)
        #expect(model.perform(.nextPhoto) && compare.candidate == photos.after, "→: the photo after the candidate")
        #expect(model.perform(.previousPhoto) && compare.candidate == photos.second)
        #expect(model.perform(.previousPhoto) && compare.candidate == photos.own, "←: past the select, to its file")
        #expect(model.activeAddress == photos.first, "the select stays active")
        #expect(model.perform(.makeSelect))
        #expect(compare.select == photos.own && compare.candidate == photos.first, "the photo after it the candidate")
        #expect(model.activeAddress == photos.own && compare.activeSide == .select)
        let selected = Set(model.selectedIDs)
        #expect(selected == Set([photos.own, photos.first].compactMap(model.library.photoID(of:))))
    }

    @Test func `a version chosen in the filmstrip takes the active photo's place in Compare`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        let compare = model.libraryCompare
        model.click(photos.own)
        #expect(model.perform(.compareView) && compare.select == photos.own && compare.candidate == photos.first)

        model.click(photos.second)
        model.keepCompareInStep()
        #expect(compare.select == photos.second, "the version, not its file again")
        #expect(compare.candidate == photos.first && model.activeAddress == photos.second)
    }

    @Test func `culling keys in Compare reach the active version alone, then its file alone`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        model.click(photos.own)
        model.click(photos.first, toggling: true)
        #expect(model.perform(.compareView) && model.activeAddress == photos.first)

        #expect(model.canPerform(.rating5) && model.perform(.rating5))
        #expect(photos.metadata(photos.first)?.rating == 5 && photos.metadata(photos.own)?.rating == 1)
        model.activateCompared(.candidate)
        #expect(model.activeAddress == photos.own)
        #expect(model.perform(.flagReject))
        #expect(photos.metadata(photos.own)?.flag == .reject && photos.metadata(photos.first)?.flag == .pick)
        try await fixture.eventually { !model.isWritingCulling && photos.saved(photos.own)?.flag == .reject }
        #expect(photos.saved(photos.own)?.rating == 1 && photos.saved(photos.own)?.flag == .reject, "the file's own")
        #expect(photos.saved(photos.first)?.rating == 5 && photos.saved(photos.first)?.flag == .pick, "the version's")
        #expect(photos.saved(photos.second)?.rating == 2, "the other version untouched")
    }

    @Test func `N surveys a file and its versions, each its own, and × takes a version out alone`() async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let model = photos.model
        model.click(photos.own)
        model.click(photos.second, extending: true)
        #expect(model.perform(.surveyView))
        #expect(model.surveyPhotos == [photos.own, photos.first, photos.second])
        #expect(model.surveyActivePhoto == photos.second)

        let view = surveyView(photos)
        try await fixture.eventually { view.photos.count == 3 }
        #expect(view.photos == [photos.own, photos.first, photos.second])
        let cells = try [photos.own, photos.first, photos.second].map { try #require(view.cell(showing: $0)) }
        try await fixture.eventually { cells.allSatisfy { $0.photo.shownEdit != nil } }
        for (cell, (exposure, rating)) in zip(cells, [(1.0, 1), (-1, 4), (0.5, 2)]) {
            #expect(EditRenderFixture.isRender(cell.photo.image, exposure: exposure), "each its own edit")
            #expect(cell.badges.metadata?.rating == rating, "and its own rating")
        }
        #expect(cells.map { $0.photo.accessibilityIdentifier() } == [
            "survey.IMG_1.JPG", "survey.IMG_1.JPG:Copy 1", "survey.IMG_1.JPG:Copy 2",
        ])
        #expect(cells[1].remove.accessibilityIdentifier() == "survey.remove.IMG_1.JPG:Copy 1")
        #expect(cells[1].remove.toolTip == "Remove Copy 1, a version of IMG_1.JPG from the Survey")
        #expect(cells.map(\.photo.isActive) == [false, false, true])

        #expect(model.perform(.previousPhoto) && model.surveyActivePhoto == photos.first, "← to the version before")
        model.activateSurveyed(photos.own)
        #expect(model.activeAddress == photos.own && model.selectedCount == 3, "a click, the selection kept")
        #expect(model.removeFromSurvey(photos.first))
        #expect(model.surveyPhotos == [photos.own, photos.second] && model.activeAddress == photos.own)
        #expect(model.library.photoID(of: photos.first).map(model.photoSelection.contains) == false)
        #expect(model.removeFromSurvey(photos.own))
        #expect(
            model.surveyPhotos == [photos.second] && model.activeAddress == photos.second,
            "the next becomes active",
        )
        #expect(!model.removeFromSurvey(photos.second), "the last photo stays")
    }
}
