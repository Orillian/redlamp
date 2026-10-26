import AppKit
import Foundation
import ImageIO
import RedlampDocument
import RedlampLibrary
import Testing
import UniformTypeIdentifiers
@_spi(Harness) @testable import RedlampUI

extension EditRenderFixture {
    /// Small JPEGs at `paths` below the root, each its own colour, captured a second apart in their order: the
    /// library's sources list photos by capture time, a file's versions after it.
    func photos(capturedInOrder paths: [String]) throws {
        for (number, path) in paths.enumerated() {
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            ))
            let colour = Self.colour(number)
            context.setFillColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil,
            ))
            let time = String(format: "2026:10:01 12:00:%02d", number)
            let properties = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: time]]
            try CGImageDestinationAddImage(destination, #require(context.makeImage()), properties as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try (data as Data).write(to: photo(path))
        }
    }
}

/// Thumbnails read ahead of versions (LIB-48): the grid's and the filmstrip's reading ahead, and held arrow keys' in
/// the loupe, ask for each row's own edit, as the cells shown do, so a version with an edit of its own is read ahead
/// with it while its file's is, and one with its file's edit shares the file's thumbnail.
@MainActor
struct ThumbnailReadAheadVersionsTests {
    /// Seven photos, the fourth, IMG_4.JPG, edited, with a version of its own edit and a version of its file's,
    /// their renders made and All Photographs shown: three photos, IMG_4 and its versions, then three photos.
    @MainActor private struct Photos {
        let fixture: EditRenderFixture
        let model: EditorModel
        /// IMG_4's own row, its version with an edit of its own, and its version with the file's edit, in rows one
        /// after another from `row`.
        let own: RedlampUI.LibraryItem
        let edited: RedlampUI.LibraryItem
        let shared: RedlampUI.LibraryItem
        let row: Int

        var versions: [RedlampUI.LibraryItem] {
            [own, edited, shared]
        }

        /// The photo `offset` rows after IMG_4's own.
        func item(after offset: Int) throws -> RedlampUI.LibraryItem {
            try #require(fixture.library.items.row(row + offset))
        }
    }

    private func photos(_ fixture: EditRenderFixture) async throws -> Photos {
        try fixture.photos(capturedInOrder: (1 ... 7).map { "IMG_\($0).JPG" })
        let (edited, shared) = (UUID(), UUID())
        try fixture.edit("IMG_4.JPG", exposure: 1, versions: [(edited, -1), (shared, 1)])
        try await fixture.open(running: false)
        try await fixture.showAllPhotographs(count: 9)
        fixture.renders.isRunning = true
        try await fixture.eventually { fixture.renders.statistics.rendered == 2 }
        try #require(fixture.renders.statistics.rendered == 2, "the file's edit, which a version shares, and the other")
        let url = fixture.photo("IMG_4.JPG")
        let addresses = [nil, edited, shared].map { PhotoAddress(url: url, version: $0) }
        let rows = try addresses.map { try #require(fixture.library.index(of: $0)) }
        try #require(rows == [rows[0], rows[0] + 1, rows[0] + 2], "the file's own row, then its versions")
        try #require(rows[0] >= 3 && rows[2] + 3 < fixture.library.count, "three photos on either side")
        let items = try addresses.map { try #require(fixture.item($0)) }
        return try Photos(
            fixture: fixture, model: #require(fixture.model), own: items[0], edited: items[1], shared: items[2],
            row: rows[0],
        )
    }

    @Test func `the grid reads ahead a version's own edit while its file's is read, and shares the file's otherwise`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let grid = LibraryGridView(model: photos.model)
        fixture.show(grid)
        let cells = try (photos.row ..< photos.row + 3).map { try #require(grid.item(ofRow: $0)) }
        try #require(cells == [cells[0], cells[0] + 1, cells[0] + 2], "a cell for each, the stack open")
        // A load still on its way when the thumbnails are forgotten is dropped, with any read ahead that joins it.
        try await fixture.eventually {
            grid.cells.values.allSatisfy { cell in
                cell.image != nil && cell.item.map { cell.shownEdit == grid.thumbnails.edit(for: $0) } == true
            }
        }
        let edge = grid.edge
        grid.thumbnails.removeAll()

        grid.prefetch(around: cells[2] + 1 ..< cells[2] + 4)
        let cached = { (item: RedlampUI.LibraryItem) in grid.thumbnails.cached(item, edge: edge) }
        try await fixture.eventually { photos.versions.allSatisfy { cached($0) != nil } }
        #expect(EditRenderFixture.isRender(cached(photos.own), exposure: 1))
        #expect(EditRenderFixture.isRender(cached(photos.edited), exposure: -1), "the version's own edit")
        #expect(cached(photos.shared) === cached(photos.own), "the version with its file's edit shares its image")
    }

    @Test func `the filmstrip reads ahead a version's own edit while its file's is read, and shares the file's otherwise`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let loader = photos.model.thumbnailLoader
        let strip = FilmstripStripView(model: photos.model)
        strip.frame = CGRect(x: 0, y: 0, width: 300, height: FilmstripStripView.height)
        fixture.show(strip)
        let count = strip.collectionView.numberOfItems(inSection: 0)
        let paths = try (photos.row ..< photos.row + 3).map { row in
            try IndexPath(item: #require((0 ..< count).first { strip.row(ofItem: $0) == row }), section: 0)
        }
        loader.removeAll()

        strip.collectionView(strip.collectionView, prefetchItemsAt: paths)
        try await fixture.eventually { photos.versions.allSatisfy(loader.hasThumbnail) }
        #expect(EditRenderFixture.isRender(loader.cached(photos.own), exposure: 1))
        #expect(EditRenderFixture.isRender(loader.cached(photos.edited), exposure: -1), "the version's own edit")
        #expect(
            loader.cached(photos.shared) === loader.cached(photos.own),
            "the version with its file's edit shares it",
        )
    }

    @Test func `a held arrow key in the loupe steps from a photo onto its version and reads ahead from there`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let (model, loader) = (photos.model, photos.model.thumbnailLoader)
        let (next, far) = try (photos.item(after: 3), photos.item(after: 5))
        model.select(photos.own.id)
        model.showLibrary(.loupe)
        let prefetch = NavigationPrefetch(model: model)
        defer { withExtendedLifetime(prefetch) {} }
        try await fixture.eventually { [photos.edited, photos.shared, next].allSatisfy(loader.hasThumbnail) }
        try #require(!loader.hasThumbnail(far), "five cells on, past what's read around the photo")
        loader.removeAll()

        model.selectNext()
        #expect(model.activeAddress == photos.edited.id)
        try await fixture.eventually { loader.hasThumbnail(far) }
        #expect(loader.hasThumbnail(far), "the photos ahead of the version are read")
        #expect(EditRenderFixture.isRender(loader.cached(photos.edited), exposure: -1), "the version's own edit")
    }

    @Test func `a held arrow key in the loupe steps back onto a version and reads its file's other rows ahead`(
    ) async throws {
        let fixture = EditRenderFixture()
        defer { fixture.cleanUp() }
        let photos = try await photos(fixture)
        let (model, loader) = (photos.model, photos.model.thumbnailLoader)
        try model.select(photos.item(after: 3).id)
        model.showLibrary(.loupe)
        let prefetch = NavigationPrefetch(model: model)
        defer { withExtendedLifetime(prefetch) {} }
        try await fixture.eventually { photos.versions.allSatisfy(loader.hasThumbnail) }
        loader.removeAll()

        model.selectPrevious()
        #expect(model.activeAddress == photos.shared.id)
        try await fixture.eventually { photos.versions.allSatisfy(loader.hasThumbnail) }
        #expect(
            EditRenderFixture.isRender(loader.cached(photos.edited), exposure: -1),
            "the version before, its own edit",
        )
        #expect(loader.cached(photos.shared) === loader.cached(photos.own), "the version reached shares its file's")
    }
}
