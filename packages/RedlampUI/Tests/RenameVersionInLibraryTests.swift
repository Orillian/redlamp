import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// A version renamed from Library (LIB-48), as Lightroom Classic renames a virtual copy: in the Metadata panel's Copy
/// Name, shown while the active photo is a version, and from Photo › Versions › Rename Version…, under EDT-09's rules
/// for a version's name; through the editor when Develop has the photo open, else in its sidecar; one step on
/// Library's Undo, the version's row, its tooltip and its accessibility name following.
@MainActor
@Suite(.serialized)
struct RenameVersionInLibraryTests {
    private let first = UUID()
    private let second = UUID()

    /// How a rename is asked for.
    enum Asking: CaseIterable {
        case panel, menu
    }

    /// Small JPEGs A and B below Shoot, B with two versions, Copy 1 and Copy 2; the library open and All Photographs
    /// shown, the versions' rows after B's own; the Metadata panel in a window, over which sheets show.
    @MainActor
    private final class Library {
        let sandbox: SourcesSandbox
        let model: EditorModel
        let photo: URL
        let panel: MetadataPanelView
        let window: NSWindow

        init(_ versions: [UUID]) async throws {
            let sandbox = SourcesSandbox()
            try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG"])
            let photo = sandbox.photo("Shoot/B.JPG")
            var sidecar = Sidecar(recipe: EditRecipe())
            sidecar.versions = zip(versions, ["Copy 1", "Copy 2"]).map { id, name in
                PhotoVersion(id: id, name: name, recipe: EditRecipe())
            }
            try SidecarStore().saveOrRemove(sidecar, for: photo)
            let model = try await sandbox.open()
            #expect(model.librarySources.show(.allPhotographs))
            try await sandbox.eventually { !model.librarySources.isListing && model.library.count == 4 }
            // `EditorWindowController.frontWindow` asks `NSApp`, which is nil until something makes it.
            _ = NSApplication.shared
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.titled], backing: .buffered,
                defer: false,
            )
            let panel = MetadataPanelView(model: model, panels: model.libraryPanels)
            panel.frame = CGRect(x: 0, y: 0, width: 320, height: 560)
            window.contentView?.addSubview(panel)
            window.orderFront(nil)
            EditorWindowController.harnessWindow = window
            (self.sandbox, self.model, self.photo, self.panel, self.window) = (sandbox, model, photo, panel, window)
        }

        func remove() {
            EditorWindowController.harnessWindow = nil
            window.orderOut(nil)
            sandbox.remove()
        }

        func version(_ id: UUID) -> PhotoAddress {
            PhotoAddress(url: photo, version: id)
        }

        /// The library's item of `photo`.
        func item(_ photo: PhotoAddress) -> RedlampUI.LibraryItem? {
            model.library.index(of: photo).flatMap { model.library.items.row($0) }
        }

        /// The name of version `id` in B's sidecar on disk.
        func saved(_ id: UUID) -> String? {
            SidecarStore().load(for: photo)?.version(id)?.name
        }

        /// Opens B in Develop in version `id`, then shows Library again, Develop keeping it open.
        func openInDevelop(_ id: UUID) async throws {
            model.clickInGrid(version(id))
            model.showModule(.develop)
            let model = model
            let photo = photo
            try await sandbox.eventually { model.info?.url == photo && model.opening == nil }
            try #require(model.info?.url == photo && model.openVersion == id, "B open in Develop in the version")
            model.showModule(.library)
        }

        /// Asks for `typed` as the name of the active version, as `asking` does it.
        func rename(to typed: String, by asking: Asking) async throws {
            switch asking {
            case .panel:
                let (panel, model) = (panel, model)
                try await sandbox.eventually { panel.copyNameVersion == model.activeAddress }
                try #require(panel.copyNameVersion == model.activeAddress, "Copy Name shows the active version")
                let field = panel.copyName
                field.stringValue = typed
                panel.controlTextDidEndEditing(Notification(
                    name: NSControl.textDidEndEditingNotification,
                    object: field,
                ))
            case .menu:
                #expect(MenuBarState.shown(by: model, for: []).canRenameVersion, "Rename Version… is enabled")
                model.chooseVersionName()
                let sheet = { EditorWindowController.frontWindow?.attachedSheet }
                try await sandbox.eventually { sheet() != nil }
                let content = try #require(sheet()?.contentView, "Rename Version… shows its sheet")
                let field = try #require(Self.find(NSTextField.self, in: content) {
                    $0.accessibilityIdentifier() == "versions.rename.name"
                })
                let active = try #require(model.activeAddress)
                #expect(model.versionName(of: active) == field.stringValue, "the sheet starts from the version's name")
                field.stringValue = typed
                try #require(Self.find(NSButton.self, in: content) { $0.title == "Rename" }).performClick(nil)
                try await sandbox.eventually { sheet() == nil && !model.isModalDialogOpen }
            }
        }

        /// The renames asked for written, and the index caught up with them.
        func written() async throws {
            await model.versionNameSteps.written()
            await sandbox.service?.settled()
        }

        static func find<View: NSView>(_: View.Type, in view: NSView, where test: (View) -> Bool) -> View? {
            if let found = view as? View, test(found) {
                return found
            }
            for subview in view.subviews {
                if let found = find(View.self, in: subview, where: test) {
                    return found
                }
            }
            return nil
        }
    }

    @Test func `Copy Name shows the active photo's name when it's a version, and isn't there for a file's own`(
    ) async throws {
        let library = try await Library([first, second])
        defer { library.remove() }
        let (model, panel) = (library.model, library.panel)
        model.clickInGrid(library.version(second))
        try await library.sandbox.eventually { panel.copyName.stringValue == "Copy 2" }
        #expect(panel.copyNameRow?.isHidden == false && panel.copyName.stringValue == "Copy 2")
        #expect(MenuBarState.shown(by: model, for: []).canRenameVersion)

        model.clickInGrid(PhotoAddress(url: library.photo))
        try await library.sandbox.eventually { panel.copyNameRow?.isHidden == true }
        #expect(panel.copyNameRow?.isHidden == true, "no Copy Name for B's own row")
        #expect(!MenuBarState.shown(by: model, for: []).canRenameVersion, "no version to rename")
        model.clickInGrid(PhotoAddress(url: library.sandbox.photo("Shoot/A.JPG")))
        try await library.sandbox.eventually { model.activeAddress?.url.lastPathComponent == "A.JPG" }
        #expect(panel.copyNameRow?.isHidden == true)
    }

    @Test(arguments: Asking.allCases)
    func `a version not open in Develop is renamed in its sidecar, and Undo and Redo are one step each`(
        by asking: Asking,
    ) async throws {
        let library = try await Library([first, second])
        defer { library.remove() }
        let model = library.model
        let copy = library.version(first)
        model.clickInGrid(copy)
        #expect(model.info == nil, "Library doesn't open the photo")
        try await library.rename(to: "  Contrast ", by: asking)
        #expect(model.versionName(of: copy) == "Contrast", "without the spaces at its ends, shown at once")
        try await library.written()
        #expect(library.saved(first) == "Contrast" && library.saved(second) == "Copy 2")
        try await library.sandbox.eventually { library.item(copy)?.versionName == "Contrast" }
        #expect(library.item(copy)?.title == "Contrast, a version of B.JPG")
        #expect(library.item(copy)?.accessibilityName == "B.JPG:Contrast")
        #expect(library.item(library.version(second))?.versionName == "Copy 2", "B's other version as it was")
        #expect(model.versionNameSteps.asked.isEmpty, "the row has the name")
        let field = library.panel.copyName
        try await library.sandbox.eventually { field.stringValue == "Contrast" }
        #expect(field.stringValue == "Contrast")

        #expect(model.libraryUndoKind == .versionNames && model.perform(.undo))
        try await library.written()
        #expect(library.saved(first) == "Copy 1")
        try await library.sandbox.eventually { library.item(copy)?.versionName == "Copy 1" }
        #expect(library.item(copy)?.title == "Copy 1, a version of B.JPG")
        #expect(model.libraryUndoKind == nil, "the rename was one step")

        #expect(model.libraryRedoKind == .versionNames && model.perform(.redo))
        try await library.written()
        #expect(library.saved(first) == "Contrast")
        try await library.sandbox.eventually { library.item(copy)?.versionName == "Contrast" }
        #expect(model.libraryRedoKind == nil)
    }

    @Test(arguments: Asking.allCases)
    func `a version whose photo Develop has open is renamed through the editor`(by asking: Asking) async throws {
        let library = try await Library([first, second])
        defer { library.remove() }
        let model = library.model
        let copy = library.version(second)
        try await library.openInDevelop(first)
        model.clickInGrid(copy)
        #expect(model.info?.url == library.photo, "Develop keeps the photo open behind Library")
        try await library.rename(to: "Portrait", by: asking)
        try await library.written()
        #expect(model.versions.map(\.name) == ["Copy 1", "Portrait"], "the editor's versions")
        #expect(model.openVersion == first, "Develop's version open as it was")
        try await library.sandbox.eventually { library.saved(second) == "Portrait" }
        try await library.sandbox.eventually { library.item(copy)?.versionName == "Portrait" }
        #expect(library.item(copy)?.accessibilityName == "B.JPG:Portrait")

        #expect(model.perform(.undo))
        try await library.written()
        #expect(model.versions.map(\.name) == ["Copy 1", "Copy 2"])
        try await library.sandbox.eventually { library.saved(second) == "Copy 2" }
        try await library.sandbox.eventually { library.item(copy)?.versionName == "Copy 2" }
        #expect(model.perform(.redo))
        try await library.written()
        #expect(model.versions.map(\.name) == ["Copy 1", "Portrait"])
        try await library.sandbox.eventually { library.saved(second) == "Portrait" }
    }

    @Test(arguments: Asking.allCases)
    func `a name EDT-09 refuses changes nothing and leaves no step`(by asking: Asking) async throws {
        let library = try await Library([first, second])
        defer { library.remove() }
        let model = library.model
        let copy = library.version(first)
        model.clickInGrid(copy)
        for refused in ["", "   ", "Copy 1"] {
            try await library.rename(to: refused, by: asking)
            #expect(model.libraryUndoKind == nil, "“\(refused)” went on Undo")
            #expect(model.versionName(of: copy) == "Copy 1")
            if asking == .panel {
                #expect(library.panel.copyName.stringValue == "Copy 1", "the field given the name back")
            }
        }
        try await library.written()
        #expect(library.saved(first) == "Copy 1" && library.item(copy)?.versionName == "Copy 1")
    }

    @Test func `in Develop Rename Version… renames the version open, as it did`() async throws {
        let library = try await Library([first, second])
        defer { library.remove() }
        let model = library.model
        try await library.openInDevelop(second)
        model.showModule(.develop)
        #expect(MenuBarState.shown(by: model, for: []).canRenameVersion)
        model.renameVersion(second, to: "Wide")
        #expect(model.versions.map(\.name) == ["Copy 1", "Wide"])
        #expect(model.libraryUndoKind != .versionNames, "Develop's rename isn't Library's step")
        try await library.sandbox.eventually { library.saved(second) == "Wide" }
        model.showVersion(nil)
        #expect(!MenuBarState.shown(by: model, for: []).canRenameVersion, "the photo's own edit open")
    }
}
