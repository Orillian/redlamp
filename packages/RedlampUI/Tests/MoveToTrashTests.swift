import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Move to Trash (LIB-46): the photo being edited, or the photos selected, to the Trash as one of the library's
/// batches, each with its raw or JPEG pair, its sidecars and other apps' `.xmp`, in Library and Develop; the photo
/// after them becoming active, the one before it at the end, and none with none left; Library's Undo putting them back
/// selected as they were, and Recently Trashed's Put Back too; and ⌫ left to Remove from Collection in a collection and
/// in Marked, and to the masks and spots in Develop's Masking and Healing tools, ⌘⌫ to Put Back in Recently Trashed.
///
/// The Trash is the real one: the photos are made in the scratch folder, and what a test leaves in the Trash is removed
/// with it.
@MainActor
@Suite(.serialized)
struct MoveToTrashTests {
    /// Shoot's photos in the order Folders lists them: IMG_0001's raw and JPEG pair, the JPEG with a sidecar and the
    /// pair with another app's `.xmp`, then IMG_0002 to IMG_0004.
    private static let names = ["IMG_0001.DNG", "IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG", "IMG_0004.JPG"]

    private static let delete = KeyCombo(.delete)
    private static let commandDelete = KeyCombo(.delete, command: true)

    private func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// Runs `body` on Shoot, shown from the library in `module`, then removes what it left in the Trash and the
    /// sandbox, whether `body` threw or not.
    private func withShoot(
        in module: AppModule = .library, _ body: (SourcesSandbox, EditorModel, LibraryService) async throws -> Void,
    ) async throws {
        let sandbox = SourcesSandbox()
        var service: LibraryService?
        do {
            for (number, name) in Self.names.enumerated() {
                try RenameTests.RenameFolder.write(sandbox.photo("Shoot/\(name)"), shade: number, second: number)
            }
            try SidecarStore().save(
                Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2)),
                for: sandbox.photo("Shoot/IMG_0001.JPG"),
            )
            try Data("xmp of IMG_0001".utf8).write(to: sandbox.photo("Shoot/IMG_0001.xmp"))
            let model = try await sandbox.open()
            service = sandbox.service
            let shoot = sandbox.folder("Shoot")
            model.showFolder(shoot)
            try await sandbox.eventually {
                model.folder == shoot && !model.library.isListing && model.items.count == Self.names.count
            }
            try #require(model.items.map(\.name) == Self.names)
            model.showModule(module)
            try await body(sandbox, model, #require(service))
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

    @Test func `the selection goes to the Trash with its pair and sidecars, the photo after it becoming active, and Undo, Redo and Put Back follow`(
    ) async throws {
        try await withShoot { sandbox, model, service in
            let shoot = sandbox.folder("Shoot")
            let photo = { (name: String) in sandbox.photo("Shoot/\(name)") }
            let before = files(in: shoot)
            #expect(before.contains("IMG_0001.JPG.redlamp") && before.contains("IMG_0001.xmp"))
            model.select(photo("IMG_0001.JPG"))
            model.click(photo("IMG_0003.JPG"), toggling: true)
            #expect(model.canPerform(.moveToTrash))

            #expect(await model.trash(model.selectedIndexIDs()) == nil)
            #expect(model.undoNotice.text == "Moved 3 Photos to the Trash")
            #expect(model.activity.events.contains { $0.text == "Move 3 Photos to the Trash" })
            await model.filesMade()
            #expect(files(in: shoot) == ["IMG_0002.JPG", "IMG_0004.JPG"], "the pair, its sidecar and its .xmp went too")
            #expect(model.items.map(\.name) == ["IMG_0002.JPG", "IMG_0004.JPG"])
            #expect(model.selection == photo("IMG_0004.JPG") && model.selectedPhotos == [photo("IMG_0004.JPG")])
            try await sandbox.eventually { model.library.trashedCount == 3 }
            #expect(model.library.trashedCount == 3, "Recently Trashed lists the three photos")
            #expect(await service.trashedPlaces().count == 5)

            #expect(model.canPerform(.undo) && model.perform(.undo))
            await model.filesMade()
            #expect(files(in: shoot) == before)
            #expect(model.items.map(\.name) == Self.names)
            #expect(Set(model.selectedPhotos) == [photo("IMG_0001.JPG"), photo("IMG_0003.JPG")])
            #expect(model.selection == photo("IMG_0003.JPG"), "they come back selected as they were")
            #expect(SidecarStore().load(for: photo("IMG_0001.JPG"))?.metadata?.rating == 2, "its sidecar as it went")

            #expect(model.canPerform(.redo) && model.perform(.redo))
            await model.filesMade()
            #expect(files(in: shoot) == ["IMG_0002.JPG", "IMG_0004.JPG"])

            model.showRecentlyTrashed()
            try await sandbox.eventually { model.library.showsRecentlyTrashed && model.items.count == 3 }
            #expect(!model.canPerform(.moveToTrash), "off in Recently Trashed")
            model.selectAllPhotos()
            #expect(model.perform(.putBack))
            try await sandbox.eventually { model.items.isEmpty && model.library.trashedCount == 0 }
            #expect(files(in: shoot) == before, "Put Back puts them where they were")
        }
    }

    @Test func `in Develop the photo being edited goes, the next one opening, the one before it at the end, and none with none left`(
    ) async throws {
        try await withShoot(in: .develop) { sandbox, model, _ in
            let photo = { (name: String) in sandbox.photo("Shoot/\(name)") }
            @MainActor func open(_ name: String) async throws {
                model.select(photo(name))
                try await sandbox.eventually { model.info?.url == photo(name) }
                try #require(model.info?.url == photo(name))
            }
            @MainActor func gone(_ name: String) -> Bool {
                !FileManager.default.fileExists(atPath: photo(name).path)
            }

            try await open("IMG_0002.JPG")
            #expect(model.perform(.moveToTrash))
            try await sandbox.eventually { gone("IMG_0002.JPG") }
            await model.filesMade()
            #expect(model.selection == photo("IMG_0003.JPG"), "the photo after it")
            try await sandbox.eventually { model.info?.url == photo("IMG_0003.JPG") }
            #expect(model.info?.url == photo("IMG_0003.JPG"), "opens in Develop")

            try await open("IMG_0004.JPG")
            #expect(model.perform(.moveToTrash))
            try await sandbox.eventually { gone("IMG_0004.JPG") }
            await model.filesMade()
            #expect(model.selection == photo("IMG_0003.JPG"), "at the end, the photo before it")

            model.selectAllPhotos()
            #expect(model.selectedCount == 3)
            #expect(model.perform(.moveToTrash))
            try await sandbox.eventually { model.items.isEmpty }
            await model.filesMade()
            #expect(model.selection == nil && model.info == nil && model.selectedCount == 0, "no photo is open")
            #expect(!model.canPerform(.moveToTrash))

            #expect(model.perform(.undo))
            await model.filesMade()
            #expect(model.items.count == 3)
            #expect(model.selection == photo("IMG_0003.JPG") && model.selectedCount == 3, "selected as they were")
            try await sandbox.eventually { model.info?.url == photo("IMG_0003.JPG") }
            #expect(model.info?.url == photo("IMG_0003.JPG"), "open in Develop again")
        }
    }

    @Test func `a photo's menu moves it alone when it isn't selected, and a photo the library doesn't have is said`(
    ) async throws {
        try await withShoot { sandbox, model, _ in
            let photo = { (name: String) in sandbox.photo("Shoot/\(name)") }
            model.select(photo("IMG_0002.JPG"))
            #expect(model.moveToTrash(PhotoAddress(url: photo("IMG_0004.JPG"))))
            try await sandbox.eventually { !FileManager.default.fileExists(atPath: photo("IMG_0004.JPG").path) }
            await model.filesMade()
            #expect(model.selection == photo("IMG_0002.JPG"), "the photo selected stays")
            #expect(model.items.map(\.name) == Array(Self.names.prefix(4)))

            let menu = try #require(FilmstripMenu.menu(for: photo("IMG_0003.JPG"), model: model))
            let item = try #require(menu.items.first { $0.title == ShortcutAction.moveToTrash.title })
            #expect(item.keyEquivalent == "\u{7F}" && item.keyEquivalentModifierMask == .command)
            let grid = LibraryGridMenu.menu(for: PhotoAddress(url: photo("IMG_0002.JPG")), model: model)
            #expect(grid.items.contains { $0.title == ShortcutAction.moveToTrash.title })

            #expect(await model.trash([]) == "The library hasn't read these photos yet")
        }
    }

    @Test func `in a collection Move to Trash takes the photo out of it, the next one active, and Undo puts it back in`(
    ) async throws {
        try await withShoot { sandbox, model, _ in
            let photo = { (name: String) in sandbox.photo("Shoot/\(name)") }
            let sources = model.librarySources
            let selects = try #require(CollectionPath("Selects"))
            model.select(photo("IMG_0002.JPG"))
            model.click(photo("IMG_0003.JPG"), toggling: true)
            model.click(photo("IMG_0004.JPG"), toggling: true)
            #expect(sources.create(.collection, named: "Selects", adding: true))
            await model.libraryPanels.written()
            try await sandbox.counts { $0.count(of: .collection(selects)) == 3 }
            #expect(sources.show(.collection(selects)))
            try await sandbox.eventually { !sources.isListing && model.items.count == 3 }
            #expect(model.items.map(\.name) == ["IMG_0002.JPG", "IMG_0003.JPG", "IMG_0004.JPG"])

            model.select(photo("IMG_0003.JPG"))
            #expect(await model.trash(model.selectedIndexIDs()) == nil)
            await model.filesMade()
            try await sandbox.eventually { model.items.count == 2 }
            #expect(model.items.map(\.name) == ["IMG_0002.JPG", "IMG_0004.JPG"])
            #expect(model.selection == photo("IMG_0004.JPG"), "the photo after it")

            #expect(model.perform(.undo))
            await model.filesMade()
            try await sandbox.eventually { model.items.count == 3 }
            #expect(
                model.items.map(\.name) == ["IMG_0002.JPG", "IMG_0003.JPG", "IMG_0004.JPG"],
                "back in the collection",
            )
            #expect(model.selection == photo("IMG_0003.JPG"), "selected as it was")
        }
    }

    @Test func `⌫ takes photos out of a collection, the mark off in Marked, and is the masks' and spots' in their tools`(
    ) async throws {
        try await withShoot { sandbox, model, service in
            let photo = { (name: String) in sandbox.photo("Shoot/\(name)") }
            let sources = model.librarySources
            model.select(photo("IMG_0002.JPG"))
            #expect(model.action(forKey: Self.delete)?.action == .moveToTrash, "in a folder, Move to Trash's")
            #expect(model.action(forKey: Self.commandDelete)?.action == .moveToTrash)

            // A collection: Remove from Collection's, the photo staying where it is.
            let selects = try #require(CollectionPath("Selects"))
            #expect(sources.create(.collection, named: "Selects", adding: true))
            await model.libraryPanels.written()
            try await sandbox.counts { $0.count(of: .collection(selects)) == 1 }
            #expect(sources.show(.collection(selects)))
            try await sandbox.eventually { !sources.isListing && model.items.count == 1 }
            model.select(photo("IMG_0002.JPG"))
            let inCollection = try #require(model.action(forKey: Self.delete))
            #expect(inCollection.action == .removeFromCollection)
            #expect(model.perform(inCollection.action))
            try await sandbox.eventually { model.items.isEmpty }
            #expect(model.items.isEmpty && FileManager.default.fileExists(atPath: photo("IMG_0002.JPG").path))

            // Marked: the mark comes off, the photo staying where it is.
            model.showFolder(sandbox.folder("Shoot"))
            try await sandbox.eventually { model.folder != nil && model.items.count == Self.names.count }
            try await sandbox.cull(.toggleMark, [photo("IMG_0003.JPG")])
            try await sandbox.counts { $0.count(of: .marked) == 1 }
            #expect(sources.show(.marked))
            try await sandbox.eventually { !sources.isListing && model.items.count == 1 }
            model.select(photo("IMG_0003.JPG"))
            #expect(model.canPerform(.removeFromCollection))
            let inMarked = try #require(model.action(forKey: Self.delete))
            #expect(inMarked.action == .removeFromCollection)
            #expect(model.perform(inMarked.action))
            try await sandbox.eventually { !model.isWritingCulling }
            await service.settled()
            #expect(SidecarStore().load(for: photo("IMG_0003.JPG"))?.metadata?.mark != true, "unmarked")
            #expect(FileManager.default.fileExists(atPath: photo("IMG_0003.JPG").path))

            // Develop: the Masking and Healing tools' whether or not a mask or spot is selected.
            model.showFolder(sandbox.folder("Shoot"))
            try await sandbox.eventually { model.folder != nil && model.items.count == Self.names.count }
            model.showModule(.develop)
            model.select(photo("IMG_0004.JPG"))
            try await sandbox.eventually { model.info?.url == photo("IMG_0004.JPG") }
            for tool in [EditTool.masking, .heal] {
                model.activeTool = tool
                #expect(model.action(forKey: Self.delete)?.action == .deleteMask, "\(tool)")
                #expect(!model.perform(.deleteMask), "nothing selected: the photo stays")
            }
            model.activeTool = .edit
            #expect(model.action(forKey: Self.delete)?.action == .moveToTrash)
            #expect(FileManager.default.fileExists(atPath: photo("IMG_0004.JPG").path))

            // Recently Trashed: ⌘⌫ is Put Back's, and its item carries the key there.
            model.showModule(.library)
            #expect(await model.trash(model.selectedIndexIDs()) == nil)
            await model.filesMade()
            let menuBar = MenuBarState(model: model)
            #expect(menuBar.shown.claimed.isEmpty)
            model.showRecentlyTrashed()
            try await sandbox.eventually { model.library.showsRecentlyTrashed && model.items.count == 1 }
            #expect(model.action(forKey: Self.commandDelete)?.action == .putBack)
            #expect(MenuBarState.shown(by: model, for: [.putBack, .moveToTrash]).claimed == [.putBack])
        }
    }

    @Test func `a held key moves one batch to the Trash, its repeats taken in its place`() throws {
        _ = NSApplication.shared
        let model = EditorModel(engine: StubEngine())
        func press(repeated: Bool) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: repeated, keyCode: 51,
            ))
        }
        #expect(model.action(forKey: Self.commandDelete)?.action == .moveToTrash)
        #expect(try MenuBarKeys.prepare(for: press(repeated: true), model: model), "a repeat is taken")
        #expect(try !MenuBarKeys.prepare(for: press(repeated: false), model: model), "a press reaches the menu bar")
    }
}
