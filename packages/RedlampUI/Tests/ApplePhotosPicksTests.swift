import Foundation
import RedlampDocument
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Favourites followed from Photos in Library (LIB-65), on a simulated Photos library: All Photographs shows a
/// favourite as a pick before the photo has a sidecar; Unflag clears it, and Photos' changes leave it so while a photo
/// Photos favourites becomes a pick; Undo gives the pick back to the favourite, which it then follows again.
@MainActor
@Suite(.serialized)
struct ApplePhotosPicksTests {
    /// Three photos in one album, the first and the third favourites.
    private static func photos() -> SimulatedPhotosLibrary {
        let assets = (1 ... 3).map { number in
            ApplePhotosAsset(
                id: "asset-\(number)", created: Date(timeIntervalSince1970: 1_790_000_000 + Double(number) * 60),
                isFavorite: number != 2, albums: ["album-a"], resources: [ApplePhotosResource(
                    kind: .photo, type: "public.jpeg", originalFilename: String(format: "IMG_%04d.JPG", number),
                )],
            )
        }
        return SimulatedPhotosLibrary(
            collections: [ApplePhotosCollection(id: "album-a", title: "A", kind: .album)], assets: assets,
        )
    }

    /// The flag each photo listed shows, by name, as its cell's badge shows it.
    private static func flags(_ model: EditorModel) -> [String: PhotoFlag?] {
        Dictionary(model.items.map { ($0.name, $0.metadata.flag) }) { first, _ in first }
    }

    @Test func `a favourite shows as a pick, Unflag clears it through Photos' changes, and Undo gives it to the favourite`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        let photos = Self.photos()
        let model = try await sandbox.open(photos: photos)
        let core = try #require(sandbox.service?.core)
        let indexer = ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
        try await indexer.keep(["album-a"])
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 3 }
        #expect(Self.flags(model) == ["IMG_0001.JPG": .pick, "IMG_0002.JPG": nil, "IMG_0003.JPG": .pick])

        let first = try #require(model.items.first { $0.name == "IMG_0001.JPG" }?.url)
        try await sandbox.cull(.unflag, [first])
        #expect(Self.flags(model) == ["IMG_0001.JPG": nil, "IMG_0002.JPG": nil, "IMG_0003.JPG": .pick])
        photos.update("asset-1") { $0.created = Date(timeIntervalSince1970: 1_800_000_000) }
        photos.update("asset-2") { $0.isFavorite = true }
        let changed = try await indexer.update()
        #expect(changed.updated.count == 2)
        try await sandbox.eventually { Self.flags(model)["IMG_0002.JPG"] == .pick }
        #expect(Self.flags(model) == ["IMG_0001.JPG": nil, "IMG_0002.JPG": .pick, "IMG_0003.JPG": .pick])

        #expect(model.undoCulling())
        try await sandbox.eventually { !model.isWritingCulling }
        await sandbox.service?.settled()
        #expect(Self.flags(model)["IMG_0001.JPG"] == .pick)
        // Culling keeps its change shown over the lists' updates for this long after it's written.
        try await Task.sleep(for: CullingOverlay.kept + .milliseconds(100))
        photos.update("asset-1") { $0.isFavorite = false }
        _ = try await indexer.update()
        try await sandbox.eventually { Self.flags(model)["IMG_0001.JPG"] == .some(nil) }
        #expect(Self.flags(model) == ["IMG_0001.JPG": nil, "IMG_0002.JPG": .pick, "IMG_0003.JPG": .pick])
    }
}
