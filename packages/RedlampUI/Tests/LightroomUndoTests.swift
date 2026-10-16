import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// ⌘Z for an import from Lightroom Classic (LIB-29): an import that ends goes on Undo as a change of its own, taken
/// back in turn with the changes made since through the import's own Undo, by its window when it's open and by itself
/// when it's closed; Undo Import takes it off Undo, and Redo doesn't make it again.
@MainActor
@Suite(.serialized)
struct LightroomUndoTests {
    /// The sandbox's root with A.jpg, and Other/Day/B.jpg outside the library, in a catalog of both; the editor
    /// shows the root in Library.
    private func opened(_ sandbox: SourcesSandbox) async throws -> (EditorModel, URL, other: URL) {
        try sandbox.photos(["A.jpg"])
        let other = sandbox.base.appending(path: "Other", directoryHint: .isDirectory)
        try sandbox.photos(["Day/B.jpg"], under: other, from: 1)
        let catalog = sandbox.base.appending(path: "Catalog/Lightroom Catalog.lrcat")
        try LightroomWindowTests.catalog(root: sandbox.root, other: other, at: catalog)
        let model = try await sandbox.open()
        model.open([sandbox.root])
        try await sandbox.eventually { model.library.count == 1 }
        return (model, catalog, other)
    }

    /// Imports `catalog` from its window, and returns the window once the import is done.
    private func imported(_ catalog: URL, into model: EditorModel, _ sandbox: SourcesSandbox) async throws
        -> LightroomWindowController {
        LightroomWindowController.show(editor: model)
        let window = try #require(LightroomWindowController.current)
        window.choose(catalog: catalog)
        try await sandbox.eventually { window.isReported }
        window.model.startImport()
        try await sandbox.eventually(seconds: 90) { window.isImported }
        try #require(window.problem == nil, "\(window.problem ?? "")")
        return window
    }

    private func metadata(_ url: URL) -> PhotoMetadata? {
        SidecarStore().load(for: url)?.metadata
    }

    private func removeOther(_ other: URL, from model: EditorModel) async {
        if let root = model.library.root(containing: other) {
            await model.library.remove(root)?.value
        }
    }

    @Test func `the import gives the photo open its versions, and takes back only those still as it gave them`(
    ) async throws {
        let model = EditorModel(engine: StubEngine())
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "IMG_0001.ARW")
        model.select(photo)
        try await SourcesSandbox.eventually { model.info?.url == photo }
        let path = try #require(await model.lightroomEditor.open())
        let versions = try #require(model.lightroomEditor.versions)
        let copy = PhotoVersion(name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 4))
        let other = PhotoVersion(name: "Copy 2", recipe: EditRecipe())

        let made = await versions(path, [copy, other], [])
        #expect(made == .changed([], [copy, other]))
        #expect(model.versions.map(\.name) == ["Copy 1", "Copy 2"], "Develop lists them")
        try await SourcesSandbox.eventually { SidecarStore().load(for: photo)?.versions.count == 2 }

        var changed = other
        changed.name = "Copy 2 as imported"
        #expect(await versions(path, [], [copy, changed]) == .changed([copy, other], [other]))
        #expect(model.versions.map(\.name) == ["Copy 2"], "one that isn't as it was given stays")
        try await SourcesSandbox.eventually { SidecarStore().load(for: photo)?.versions.map(\.name) == ["Copy 2"] }
        #expect(await versions("/Elsewhere/B.jpg", [copy], []) == .notOpen)
    }

    @Test func `⌘Z takes an import back after the changes made since, through its window`() async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let (model, catalog, other) = try await opened(sandbox)
        let window = try await imported(catalog, into: model, sandbox)
        defer { window.close() }
        #expect(model.libraryUndoKind == .lightroom && model.canPerform(.undo))
        #expect(model.lightroomSteps.undo.first?.title == "Import from Lightroom Classic of 2 photos")
        #expect(metadata(sandbox.photo("A.jpg"))?.rating == 4)

        try await sandbox.cull(.flagReject, [sandbox.photo("A.jpg")])
        #expect(model.libraryUndoKind == .culling, "the flag, made after the import, goes first")
        #expect(model.perform(.undo))
        try await sandbox.eventually { !model.isWritingCulling && metadata(sandbox.photo("A.jpg"))?.flag == .pick }
        #expect(metadata(sandbox.photo("A.jpg"))?.flag == .pick, "Lightroom's pick, as the import left it")

        #expect(model.libraryUndoKind == .lightroom && model.perform(.undo))
        try await sandbox.eventually(seconds: 60) { window.isUndone }
        #expect(window.problem == nil, "\(window.problem ?? "")")
        #expect(metadata(sandbox.photo("A.jpg"))?.isEmpty ?? true)
        #expect(metadata(other.appending(path: "Day/B.jpg"))?.isEmpty ?? true)
        #expect(model.lightroomSteps.undo.isEmpty && model.libraryUndoKind == nil)
        #expect(model.libraryRedoKind == .culling, "⇧⌘Z makes the flag again, not the import")
        #expect(model.activity.events.contains { $0.text == "Undo Import from Lightroom Classic of 2 photos" })
        await removeOther(other, from: model)
    }

    @Test func `with its window closed ⌘Z takes the import back itself, and Undo Import takes it off Undo`()
        async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let (model, catalog, other) = try await opened(sandbox)
        let window = try await imported(catalog, into: model, sandbox)
        window.close()
        #expect(LightroomWindowController.current == nil)
        #expect(model.perform(.undo))
        try await sandbox.eventually(seconds: 60) { metadata(sandbox.photo("A.jpg"))?.isEmpty ?? true }
        #expect(metadata(sandbox.photo("A.jpg"))?.isEmpty ?? true)
        try await sandbox.eventually {
            model.activity.events.contains { $0.text == "Undo the import from Lightroom Classic of 2 photos" }
        }
        #expect(!model.canPerform(.undo) && !model.canPerform(.redo))

        let again = try await imported(catalog, into: model, sandbox)
        defer { again.close() }
        #expect(model.libraryUndoKind == .lightroom)
        try await sandbox.eventually { again.button("lightroom.undo")?.enabled == true }
        again.model.undo()
        try await sandbox.eventually(seconds: 60) { again.isUndone }
        #expect(model.lightroomSteps.undo.isEmpty && !model.canPerform(.undo), "Undo Import took it off Undo")
        #expect(metadata(sandbox.photo("A.jpg"))?.isEmpty ?? true)
        await removeOther(other, from: model)
    }
}
