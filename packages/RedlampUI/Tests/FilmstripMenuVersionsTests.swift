import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// The filmstrip's menu on a version's cell that isn't selected (LIB-48): Copy Settings, Copy Settings with Last
/// Choice, Paste Settings and Move to Trash act on the cell's version alone, as they act on a file's cell alone, the
/// photo selected staying as it is.
@MainActor
@Suite(.serialized)
struct FilmstripMenuVersionsTests {
    private let first = UUID()
    private let second = UUID()

    /// Runs `body` on A.JPG and B.JPG below Shoot, B's own edit as made and its versions Copy 1, Exposure +0.5, and
    /// Copy 2, Exposure −0.25, shown in All Photographs with the versions' rows; A is selected. Then removes what it
    /// left in the Trash and the sandbox.
    private func withShoot(_ body: (SourcesSandbox, EditorModel, URL) async throws -> Void) async throws {
        let sandbox = SourcesSandbox()
        var service: LibraryService?
        do {
            try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG"])
            let photo = sandbox.photo("Shoot/B.JPG")
            var sidecar = Sidecar(recipe: EditRecipe())
            sidecar.versions = [
                PhotoVersion(id: first, name: "Copy 1", recipe: Self.recipe(exposure: 0.5)),
                PhotoVersion(id: second, name: "Copy 2", recipe: Self.recipe(exposure: -0.25)),
            ]
            try SidecarStore().saveOrRemove(sidecar, for: photo)
            let model = try await sandbox.open()
            service = sandbox.service
            #expect(model.librarySources.show(.allPhotographs))
            try await sandbox.eventually { !model.librarySources.isListing && model.library.count == 4 }
            await sandbox.service?.settled()
            model.clickInGrid(PhotoAddress(url: sandbox.photo("Shoot/A.JPG")))
            try #require(model.selectedCount == 1 && model.selection == sandbox.photo("Shoot/A.JPG"))
            try await body(sandbox, model, photo)
        } catch {
            await cleanUp(sandbox, service)
            throw error
        }
        await cleanUp(sandbox, service)
    }

    private func cleanUp(_ sandbox: SourcesSandbox, _ service: LibraryService?) async {
        for place in await service?.trashedPlaces() ?? [] {
            try? FileManager.default.removeItem(atPath: place)
        }
        sandbox.remove()
    }

    private static func recipe(exposure: Double) -> EditRecipe {
        var recipe = EditRecipe()
        recipe[.exposure] = exposure
        return recipe
    }

    /// The edit `version` of `photo` holds on disk (nil: its own), as its Exposure.
    private func exposure(of photo: URL, _ version: UUID?) -> Double? {
        SidecarStore().load(for: photo)?[edit: version]?.recipe[.exposure]
    }

    /// Sends the action of the item titled `title` in the filmstrip's menu on `photo`'s cell, as AppKit does when it's
    /// chosen. `performActionForItem(at:)` sends nothing while `NSApp` is nil, as it is in a suite that hasn't made
    /// the app.
    private func choose(_ title: String, onCell photo: PhotoAddress, model: EditorModel) throws {
        let menu = try #require(FilmstripMenu.menu(for: photo, model: model))
        let item = try #require(menu.items.first { $0.title == title }, "\(title) in \(menu.items.map(\.title))")
        try NSApplication.shared.sendAction(#require(item.action), to: item.target, from: item)
    }

    /// A, selected and active, as it was before.
    private func aStaysSelected(_ sandbox: SourcesSandbox, _ model: EditorModel) -> Bool {
        let a = PhotoAddress(url: sandbox.photo("Shoot/A.JPG"))
        return model.selectedCount == 1 && model.activeAddress == a
            && model.library.photoID(of: a).map(model.photoSelection.contains) == true
    }

    @Test func `Copy Settings… shows the checklist of that version's settings`() async throws {
        try await withShoot { sandbox, model, photo in
            try choose(
                ShortcutAction.copySettings.title,
                onCell: PhotoAddress(url: photo, version: first),
                model: model,
            )
            try await sandbox.eventually { model.settingsChooser != nil }
            let chooser = try #require(model.settingsChooser, "the checklist")
            #expect(chooser.purpose == .copy && chooser.sourceURL == photo)
            #expect(chooser.source[.exposure] == 0.5, "Copy 1's edit, not B's own or Copy 2's")
            #expect(aStaysSelected(sandbox, model))
            model.settingsChooser = nil
        }
    }

    @Test func `Copy Settings with Last Choice copies that version's settings`() async throws {
        try await withShoot { sandbox, model, photo in
            #expect(!model.hasClipboard)
            try choose(
                ShortcutAction.copySettingsAgain.title, onCell: PhotoAddress(url: photo, version: second), model: model,
            )
            try await sandbox.eventually { model.hasClipboard }
            #expect(model.clipboard?.source[.exposure] == -0.25, "Copy 2's edit")
            #expect(model.clipboard?.sourceURL == photo)
            #expect(aStaysSelected(sandbox, model))
        }
    }

    @Test func `Paste Settings pastes onto that version alone`() async throws {
        try await withShoot { sandbox, model, photo in
            let (copy, other) = (PhotoAddress(url: photo, version: first), PhotoAddress(url: photo, version: second))
            try choose(ShortcutAction.copySettingsAgain.title, onCell: copy, model: model)
            try await sandbox.eventually { model.hasClipboard }
            try choose(ShortcutAction.pasteSettings.title, onCell: other, model: model)
            try await sandbox.eventually { exposure(of: photo, second) == 0.5 }
            await model.settingsSync.idle()
            #expect(exposure(of: photo, second) == 0.5, "Copy 2 given Copy 1's Exposure")
            #expect(
                exposure(of: photo, first) == 0.5 && exposure(of: photo, nil) == 0,
                "B's own edit and Copy 1 as they were",
            )
            #expect(SidecarStore().load(for: sandbox.photo("Shoot/A.JPG")) == nil, "A as it was")
            #expect(aStaysSelected(sandbox, model))
        }
    }

    @Test func `Move to Trash takes that version alone out of its sidecar, and Undo puts it back`() async throws {
        try await withShoot { sandbox, model, photo in
            let copy = PhotoAddress(url: photo, version: first)
            try choose(ShortcutAction.moveToTrash.title, onCell: copy, model: model)
            try await sandbox.eventually { SidecarStore().load(for: photo)?.versions.map(\.id) == [second] }
            await model.filesMade()
            #expect(FileManager.default.fileExists(atPath: photo.path), "the file stays")
            #expect(SidecarStore().load(for: photo)?.versions.map(\.id) == [second], "its other version stays")
            try await sandbox.eventually { model.library.count == 3 }
            #expect(model.library.index(of: copy) == nil && model.library.index(of: PhotoAddress(url: photo)) != nil)
            #expect(aStaysSelected(sandbox, model))

            #expect(model.perform(.undo))
            await model.filesMade()
            #expect(SidecarStore().load(for: photo)?.versions.map(\.id) == [first, second], "back at its place")
            try await sandbox.eventually { model.library.count == 4 }
            #expect(model.library.index(of: copy) != nil)
        }
    }
}
