import AppKit
import Foundation
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// The albums imports from Apple Photos follow (LIB-55), on a simulated Photos library: their new photos offered by
/// the Library panel's From Apple Photos and imported by its Import, without asking once Settings › Library says so,
/// and nothing taken out of Redlamp when a photo leaves Photos.
@MainActor
@Suite(.serialized)
struct ApplePhotosFollowedAlbumsTests {
    @Test func `the followed albums' new photos show in the Library panel, and Import brings them with the last settings`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        defer {
            model.simulateApplePhotos(nil)
            model.applePhotosFollower.stop()
            ApplePhotosWindowController.current?.close()
        }
        let destination = sandbox.base.appending(path: "Pictures", directoryHint: .isDirectory)
        let library = await ImportActions.library(of: model)
        let first = try SimulatedPhotosLibrary(manifest: ApplePhotosWindowTests.manifest(in: sandbox))
        try await ApplePhotosImport(photos: first, library: library).run(ApplePhotosImport.Settings(
            collections: ["album-lisbon"],
            copying: ImportSettings(destination: destination, folders: NamingTemplate(parsing: "{album}")),
        ))
        _ = NSApplication.shared
        let panel = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 500), styleMask: [.titled], backing: .buffered,
            defer: false,
        )
        let list = LibraryOutlineView(model: model)
        panel.contentView = list
        defer { panel.contentView = nil }
        func offered() -> Int? {
            (0 ..< list.numberOfRows).lazy.compactMap { index -> Int? in
                guard case let .applePhotos(count) = (list.item(atRow: index) as? SidebarNode)?.kind else { return nil }
                return count
            }.first
        }

        model.simulateApplePhotos(first)
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 0 && offered() == nil, "nothing new: no From Apple Photos")

        let arrived = try SimulatedPhotosLibrary(manifest: ApplePhotosWindowTests.manifest(in: sandbox, extra: 2))
        model.simulateApplePhotos(arrived)
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 2)
        try await sandbox.eventually { offered() == 2 }
        arrived.simulateChange()
        try await Task.sleep(for: ApplePhotosFollower.settling + .milliseconds(100))
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 2, "counted again after Photos changed")

        let row = try #require((0 ..< list.numberOfRows).first { index in
            if case .applePhotos = (list.item(atRow: index) as? SidebarNode)?.kind {
                return true
            }
            return false
        })
        let cell = try #require(list.view(atColumn: 0, row: row, makeIfNecessary: true))
        try #require(ApplePhotosWindowTests.button("sources.apple-photos.import", in: cell)).performClick(nil)
        try await sandbox.eventually(seconds: 60) { ApplePhotosWindowController.current?.phase == "imported" }
        let window = try #require(ApplePhotosWindowController.current)
        #expect(window.outcome?.imported == 2 && window.problem == nil, "\(window.problem ?? "")")
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Lisbon/IMG_0010.JPG").path))
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Lisbon/IMG_0011.JPG").path))
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 0)
        try await sandbox.eventually { offered() == nil }

        // A photo that leaves Photos stays in Redlamp.
        let left = try SimulatedPhotosLibrary(manifest: ApplePhotosWindowTests.manifest(
            in: sandbox,
            extra: 2,
            dropping: ["asset-1"],
        ))
        model.simulateApplePhotos(left)
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 0)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Lisbon/IMG_0001.JPG").path))
    }

    @Test func `with Import new photos automatically on, they're imported without asking once Photos settles`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let delay = ApplePhotosFollower.automaticDelay
        ApplePhotosFollower.automaticDelay = .milliseconds(200)
        defer {
            ApplePhotosFollower.automaticDelay = delay
            ApplePhotosPreferences.shared.importsAutomatically = false
            model.simulateApplePhotos(nil)
            model.applePhotosFollower.stop()
        }
        let destination = sandbox.base.appending(path: "Pictures", directoryHint: .isDirectory)
        let library = await ImportActions.library(of: model)
        try await ApplePhotosImport(
            photos: SimulatedPhotosLibrary(manifest: ApplePhotosWindowTests.manifest(in: sandbox)), library: library,
        ).run(ApplePhotosImport.Settings(
            collections: ["album-porto"],
            copying: ImportSettings(destination: destination, folders: NamingTemplate(parsing: "{album}")),
        ))
        #expect(!ApplePhotosPreferences.shared.importsAutomatically, "off until it's turned on")

        let arrived = try SimulatedPhotosLibrary(manifest: ApplePhotosWindowTests.manifest(
            in: sandbox,
            extra: 2,
            into: "album-selects",
        ))
        model.simulateApplePhotos(arrived)
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 0, "Selects isn't followed")
        let followed = try SimulatedPhotosLibrary(manifest: ApplePhotosWindowTests.manifest(
            in: sandbox,
            extra: 1,
            into: "album-porto",
        ))
        model.simulateApplePhotos(followed)
        await model.applePhotosCounted()
        #expect(model.applePhotosNewPhotos == 1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.applePhotosNewPhotos == 1, "not imported while the setting is off")

        ApplePhotosPreferences.shared.importsAutomatically = true
        try await sandbox.eventually(seconds: 30) { model.applePhotosNewPhotos == 0 }
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "Porto/IMG_0010.JPG").path))
    }
}
