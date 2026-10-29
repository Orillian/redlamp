import AppKit
import Foundation
import RedlampDocument
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// The file operations on photos kept in Apple Photos (LIB-62), on a simulated Photos library: Rename Photos… and Move
/// to Folder… refused with the reason, nothing changed; Show in Finder opening Photos; a photo's menus offering Remove
/// from Library… with Move to Trash dimmed and Show in Photos; and Move to Trash saying why, Remove from Library then
/// taking the photo out of the library, Photos' changes not bringing it back, until Undo puts it back.
@MainActor
@Suite(.serialized)
struct ApplePhotosFileOperationsTests {
    private static let reason = "This photo is in Apple Photos. Redlamp doesn't move, rename or delete photos in Photos."

    /// Whether the activity log says `text` since `logged` events.
    private static func says(_ text: String, _ model: EditorModel, since logged: Int) -> Bool {
        model.activity.events.dropFirst(logged).contains { $0.kind == .error && $0.text == text }
    }

    @Test func `Rename Photos… and Move to Folder… refuse a photo kept in Photos with the reason, changing nothing`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try ApplePhotosDownloadTests.cloud(sandbox, count: 2, network: [:])
        let (model, urls) = try await ApplePhotosDownloadTests.open(sandbox, photos, rows: 2)
        model.select(urls[0])
        let logged = model.activity.events.count
        #expect(model.renamePhotos())
        #expect(Self.says("“IMG_0001.JPG” can't be renamed: \(Self.reason)", model, since: logged))
        #expect(model.moveToFolder())
        #expect(Self.says("“IMG_0001.JPG” can't be moved: \(Self.reason)", model, since: logged))
        #expect(!model.isModalDialogOpen, "no sheet or panel opened")
        #expect(Set(model.items.map(\.name)) == ["IMG_0001.JPG", "IMG_0002.JPG"])
    }

    @Test func `Show in Finder opens Photos for a photo kept in Photos, and its menus offer Remove from Library…`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            sandbox.remove()
        }
        let photos = try ApplePhotosDownloadTests.cloud(sandbox, count: 2, network: [:])
        let (model, urls) = try await ApplePhotosDownloadTests.open(sandbox, photos, rows: 2)
        let opening = ApplePhotosActions.openPhotos
        var opened = 0
        ApplePhotosActions.openPhotos = { opened += 1 }
        defer { ApplePhotosActions.openPhotos = opening }
        model.showInFinder(urls[1])
        #expect(opened == 1)

        model.select(urls[0])
        let menu = try #require(FilmstripMenu.menu(for: urls[0], model: model))
        let titles = menu.items.map(\.title)
        #expect(titles.contains("Remove from Library…"))
        #expect(!titles.contains(ShortcutAction.renamePhotos.title) && !titles
            .contains(ShortcutAction.moveToFolder.title))
        #expect(menu.item(withTitle: ShortcutAction.moveToTrash.title)?.isEnabled == false)
        let grid = LibraryGridMenu.menu(for: PhotoAddress(url: urls[0]), model: model)
        #expect(grid.items.contains { $0.title == "Show in Photos" })
        #expect(!grid.items.contains { $0.title == ShortcutAction.showInFinder.title })
    }

    @Test func `Move to Trash says why, and Remove from Library takes the photo out until Undo puts it back`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            ApplePhotosSource.simulate(nil)
            ApplePhotosRemoval.answer = nil
            sandbox.remove()
        }
        let photos = try ApplePhotosDownloadTests.cloud(sandbox, count: 2, network: [:])
        let (model, urls) = try await ApplePhotosDownloadTests.open(sandbox, photos, rows: 2)
        let core = try #require(sandbox.service?.core)
        let indexer = ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
        model.select(urls[0])
        let logged = model.activity.events.count
        ApplePhotosRemoval.answer = true
        #expect(model.moveToTrash())
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 1 }
        await model.healthSteps.made()
        #expect(Self.says(
            "“IMG_0001.JPG” can't be moved to the Trash: \(Self.reason) Remove from Library takes it out of Redlamp's "
                + "lists and leaves Photos as it is.",
            model, since: logged,
        ))
        #expect(model.items.map(\.name) == ["IMG_0002.JPG"])
        #expect(try await core.index.read { try $0.applePhotosRows().map(\.local) } == ["asset-2"])
        #expect(try await photos.assets(withIDs: ["asset-1"]).count == 1, "Photos still has it")

        photos.update("asset-1") { $0.isFavorite.toggle() }
        _ = try await indexer.update()
        #expect(try await core.index.read { try $0.applePhotosRows().map(\.local) } == ["asset-2"])

        #expect(model.perform(.undo))
        await model.healthSteps.made()
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 2 }
        #expect(try await core.index.read { try $0.applePhotosRows().map(\.local) } == ["asset-1", "asset-2"])
    }
}
