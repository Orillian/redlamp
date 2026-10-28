import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary
@_spi(Harness) @testable import RedlampUI

/// Copy to Folder… for photos kept in Apple Photos (LIB-63) in the app, on the simulated library: Photo › Copy to
/// Folder… with a photo kept in Photos selected opens the Copy to Folder window, which copies it with its edit to To's
/// folder, the copy standing in for it in All Photographs, and Undo Copy gives the photo back; an album's Copy to
/// Folder… copies those of its photos not copied already into a folder of its title; dropped on a folder, photos kept
/// in Photos open it copying straight into that folder, Import's destination left as it was.
@MainActor
@Suite(.serialized)
struct ApplePhotosCopyWindowTests {
    /// Two photos only in iCloud, kept in place and shown in All Photographs, the app's Photos indexer following them,
    /// and Copy to Folder's To keeping its own settings.
    static func open(_ sandbox: SourcesSandbox) async throws -> (EditorModel, [URL]) {
        let photos = try ApplePhotosDownloadTests.cloud(sandbox, count: 2, network: [:])
        let (model, urls) = try await ApplePhotosDownloadTests.open(sandbox, photos, rows: 2)
        let service = try #require(sandbox.service)
        service.followApplePhotos(photos)
        try await sandbox.eventually { service.applePhotosIndexer != nil }
        ApplePhotosCopyWindowController.preferences = ApplePhotosWindowTests.preferences()
        return (model, urls)
    }

    static func close() {
        ApplePhotosCopyWindowController.current?.close()
        ApplePhotosCopyWindowController.preferences = .shared
        ApplePhotosSource.simulate(nil)
    }

    static func window(_ sandbox: SourcesSandbox) async throws -> ApplePhotosCopyWindowController {
        try await sandbox.eventually { ApplePhotosCopyWindowController.current?.phase == "choosing" }
        return try #require(ApplePhotosCopyWindowController.current, "the Copy to Folder window")
    }

    /// The photos the grid lists, by path.
    static func listed(_ model: EditorModel) -> Set<String> {
        Set(model.items.map { LibraryService.path($0.url) })
    }

    static func paths(_ urls: [URL]) -> Set<String> {
        Set(urls.map(LibraryService.path))
    }

    /// Empties what `window`'s Undo Copy put in the Trash.
    static func emptyTrash(of window: ApplePhotosCopyWindowController) {
        for file in window.model.undone?.rollbacks.flatMap(\.trashed) ?? [] {
            try? FileManager.default.removeItem(atPath: file.to)
        }
    }

    private static var edited: EditRecipe {
        var recipe = EditRecipe()
        recipe[.exposure] = 0.5
        return recipe
    }

    @Test func `Copy to Folder copies a photo kept in Photos with its edit to stand in for it, and Undo Copy gives it back`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            Self.close()
            sandbox.remove()
        }
        let (model, urls) = try await Self.open(sandbox)
        let core = try #require(sandbox.service?.core)
        let locator = try await LibrarySidecars(index: core.index, paths: core.paths).locator()
        try SidecarStore(locator: locator).save(Sidecar(recipe: Self.edited), for: urls[0])

        model.select(urls[0])
        #expect(model.selectionKeptInApplePhotos)
        #expect(model.copyToFolder())
        let window = try await Self.window(sandbox)
        #expect(window.assets == ["asset-1"] && window.report?.photos == 1)
        #expect(window.heading == "1 photo kept in Apple Photos")

        let copies = sandbox.base.appending(path: "Copies", directoryHint: .isDirectory)
        window.prepare(destination: copies, folders: "", names: "{name}")
        window.press(named: "copy")
        try await sandbox.eventually { window.phase == "copied" }
        #expect(window.outcome?.imported == 1 && window.outcome?.state == .finished)
        let copy = copies.appending(path: "IMG_0001.JPG")
        #expect(FileManager.default.fileExists(atPath: copy.path))
        let carried = try #require(SidecarStore().load(for: copy))
        #expect(carried.recipe == Self.edited, "the photo's edit, carried")
        #expect(carried.metadata?.applePhotos?.id == "asset-1")
        try await sandbox.eventually { Self.listed(model) == Self.paths([copy, urls[1]]) }
        #expect(
            model.items.first { LibraryService.path($0.url) == LibraryService.path(copy) }?.hasEdits == true,
            "All Photographs lists the copy in the photo's place, with its edit",
        )

        window.press(named: "undo")
        try await sandbox.eventually { window.phase == "undone" }
        Self.emptyTrash(of: window)
        #expect(!FileManager.default.fileExists(atPath: copy.path), "the copy is in the Trash")
        #expect(
            SidecarStore(locator: locator).load(for: urls[0])?.recipe == Self.edited,
            "the photo's own edit stays",
        )
        try await sandbox.eventually { Self.listed(model) == Self.paths(urls) }
        #expect(
            model.items.first { LibraryService.path($0.url) == LibraryService.path(urls[0]) }?.hasEdits == true,
            "the photo kept in Photos is back in All Photographs, with its edit",
        )
    }

    @Test func `an album's Copy to Folder copies its photos not copied already into a folder of its title`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            Self.close()
            sandbox.remove()
        }
        let (model, urls) = try await Self.open(sandbox)
        let copies = sandbox.base.appending(path: "Copies", directoryHint: .isDirectory)
        model.select(urls[0])
        #expect(model.copyToFolder())
        let first = try await Self.window(sandbox)
        first.prepare(destination: copies, folders: "", names: "{name}")
        first.press(named: "copy")
        try await sandbox.eventually { first.phase == "copied" }
        first.press(named: "done")
        let tram = copies.appending(path: "IMG_0001.JPG")
        try await sandbox.eventually { Self.listed(model) == Self.paths([tram, urls[1]]) }

        #expect(model.copyApplePhotosAlbum("album-a"))
        let window = try await Self.window(sandbox)
        #expect(window.assets == ["asset-2"], "the photo whose copy stands in isn't copied again")
        #expect(window.heading == "“A”: 1 photo kept in Apple Photos")
        window.prepare(destination: copies, folders: "{album}", names: "{name}")
        window.press(named: "copy")
        try await sandbox.eventually { window.phase == "copied" }
        #expect(window.outcome?.imported == 1)
        let second = copies.appending(path: "A/IMG_0002.JPG")
        #expect(FileManager.default.fileExists(atPath: second.path), "{album} gives the album's title")
        try await sandbox.eventually { Self.listed(model) == Self.paths([tram, second]) }

        window.press(named: "undo")
        try await sandbox.eventually { window.phase == "undone" }
        Self.emptyTrash(of: window)
        try await sandbox.eventually { Self.listed(model) == Self.paths([tram, urls[1]]) }
    }

    @Test func `photos kept in Photos dropped on a folder open Copy to Folder copying straight into it`() async throws {
        let sandbox = SourcesSandbox()
        defer {
            Self.close()
            sandbox.remove()
        }
        let (model, urls) = try await Self.open(sandbox)
        let picked = sandbox.folder("Picked")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let imports = ApplePhotosCopyWindowController.preferences.settings

        let dragged = DraggedPhotos(photo: PhotoAddress(url: urls[1]), fromLibrary: true)
        let drop = try #require(model.photoDrop(
            dragged,
            onFolder: picked,
            isMissing: false,
            operations: [.move, .copy],
        ))
        #expect(drop.operation == .copy, "photos kept in Photos aren't moved")
        drop.perform()
        let window = try await Self.window(sandbox)
        #expect(window.assets == ["asset-2"] && window.destination.path == LibraryService.path(picked))
        window.press(named: "copy")
        try await sandbox.eventually { window.phase == "copied" }
        #expect(window.outcome?.imported == 1)
        #expect(FileManager.default.fileExists(atPath: picked.appending(path: "IMG_0002.JPG").path))
        #expect(ApplePhotosCopyWindowController.preferences.settings == imports, "Import's own settings as they were")
    }
}
