import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Library's panels on a version (LIB-48), a photo of its own: Edit Capture Time sets the active version's time, which
/// is its file's; the Photo panel shows the version's own badges; a version made in Develop comes into a folder's own
/// list under its ID in the index; and in a folder's own list using IDs of its own, the Keywording and Metadata panels
/// show and change the version's row, not its file's.
@MainActor
@Suite(.serialized)
struct LibraryPanelsVersionsTests {
    private let first = UUID()

    /// Small JPEGs A and B below Shoot, B taken at 2007-06-01 15:30 with the keyword Belém and a version, Copy 1,
    /// rated 1 with the keyword Alfama; returns B.
    private func shoot(in sandbox: SourcesSandbox) throws -> URL {
        try sandbox.photos(["Shoot/A.JPG"])
        let photo = sandbox.photo("Shoot/B.JPG")
        try LibraryPanelsTests.Folder.writeJPEG(photo, shade: 1, taken: "2007:06:01 15:30:00")
        var sidecar = Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(keywords: ["Belém"]))
        sidecar.versions = [PhotoVersion(
            id: first, name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 1, keywords: ["Alfama"]),
        )]
        try SidecarStore().saveOrRemove(sidecar, for: photo)
        return photo
    }

    /// Shoot shown from the library from the first, by the index's IDs, in Library with the panels following.
    private func showShoot(in sandbox: SourcesSandbox) async throws -> (EditorModel, URL) {
        let photo = try shoot(in: sandbox)
        let model = try await sandbox.open()
        model.library.open(sandbox.folder("Shoot"))
        try await sandbox.eventually {
            model.library.isShownFromLibrary && !model.library.isListing && model.library.count == 3
        }
        try #require(model.library.count == 3 && model.library.showsIndexIDs, "Shoot shown by the index's IDs")
        model.libraryPanels.follow()
        return (model, photo)
    }

    /// The index's IDs of `photo`'s own row and of its versions' rows, in their order.
    private func indexIDs(of photo: URL, in service: LibraryService) async throws -> (own: Int64, versions: [Int64]) {
        let index = try #require(service.core).index
        let rows = try await index.read { reader -> (Int64, [Int64])? in
            guard let file = try LibraryService.photo(at: photo, in: reader) else { return nil }
            return try (file.id, reader.versions(folder: file.folder, name: file.name).map(\.id))
        }
        let found = try #require(rows)
        return (found.0, found.1)
    }

    /// Until every change asked for is made, the lists hold it and the panels show it.
    private func written(_ panels: LibraryPanels, _ service: LibraryService) async throws {
        await panels.written()
        await service.settled()
        try await Task.sleep(for: .milliseconds(30))
        await panels.refreshed()
    }

    private func captured(_ panels: LibraryPanels) -> String? {
        panels.selection.fields.captured.map { CaptureTimeChange.describe(time: $0.lowerBound) }
    }

    private func keywords(_ panels: LibraryPanels) -> [String] {
        panels.selection.orderedKeywords.map(\.path.text)
    }

    @Test func `Edit Capture Time with a version active sets its file's time, which each of the file's rows shows`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let (model, photo) = try await showShoot(in: sandbox)
        let service = try #require(sandbox.service)
        let panels = model.libraryPanels
        let rows = try await indexIDs(of: photo, in: service)
        let (own, copy) = (PhotoAddress(url: photo), PhotoAddress(url: photo, version: first))
        try #require(rows.versions.count == 1)

        model.clickInGrid(copy)
        try await sandbox.eventually { panels.selection.ids == rows.versions }
        #expect(panels.selection.activeID == rows.versions[0], "the version's row active, not its file's")
        #expect(captured(panels) == "2007-06-01 15:30:00")
        #expect(model.canPerform(.editCaptureTime))
        let time = try #require(ISO8601DateFormatter().date(from: "2008-01-02T03:04:05Z"))
        #expect(panels.setCaptureTime(time))
        try await written(panels, service)
        #expect(captured(panels) == "2008-01-02 03:04:05", "the version shows its file's time")
        let sidecar = SidecarStore().load(for: photo)
        #expect((sidecar?.metadata?.captureShift ?? 0) != 0, "the file's own metadata shifted")
        #expect((sidecar?.version(first)?.metadata?.captureShift ?? 0) == 0, "never a version's")

        model.clickInGrid(own)
        try await sandbox.eventually { panels.selection.ids == [rows.own] }
        #expect(captured(panels) == "2008-01-02 03:04:05", "the file's own row shows it")

        model.clickInGrid(copy)
        try await sandbox.eventually { panels.selection.ids == rows.versions }
        #expect(model.perform(.undo))
        try await written(panels, service)
        #expect(captured(panels) == "2007-06-01 15:30:00", "Undo gives the file its time back")
        #expect((SidecarStore().load(for: photo)?.metadata?.captureShift ?? 0) == 0)
    }

    @Test func `the Photo panel shows the active version's own badges, not its file's`() async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let (model, photo) = try await showShoot(in: sandbox)
        let view = PhotoPanelView(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.titled], backing: .buffered,
            defer: true,
        )
        window.contentView = view
        defer { window.contentView = nil }
        let rating = try #require(Self.field("photo.rating", in: view))

        model.clickInGrid(PhotoAddress(url: photo, version: first))
        try await sandbox.eventually { rating.stringValue == "★" }
        #expect(rating.stringValue == "★", "Copy 1's rating")
        model.clickInGrid(PhotoAddress(url: photo))
        try await sandbox.eventually { rating.stringValue == "None" }
        #expect(rating.stringValue == "None", "B's own")
    }

    private static func field(_ identifier: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.accessibilityIdentifier() == identifier {
            return field
        }
        return view.subviews.lazy.compactMap { field(identifier, in: $0) }.first
    }

    @Test func `a version made in Develop comes into a folder's own list under its ID in the index, which the list keeps`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let (model, photo) = try await showShoot(in: sandbox)
        let service = try #require(sandbox.service)
        let listed = model.library.photoIDs
        model.clickInGrid(PhotoAddress(url: photo))
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }

        model.createVersion()
        let version = try #require(model.openVersion)
        let copy = PhotoAddress(url: photo, version: version)
        try await sandbox.eventually { model.library.index(of: copy) != nil }
        #expect(model.library.showsIndexIDs, "the list keeps the index's IDs")
        #expect(Array(model.library.photoIDs.prefix(listed.count)) == Array(listed), "its photos under their IDs")
        let rows = try await indexIDs(of: photo, in: service)
        #expect(rows.versions.count == 2 && rows.versions.last == model.library.photoID(of: copy))

        model.showModule(.library)
        let panels = model.libraryPanels
        model.clickInGrid(copy)
        try await sandbox.eventually { panels.selection.ids == [rows.versions[1]] }
        #expect(panels.selection.activeID == rows.versions[1])
    }

    @Test func `in a folder's own list using its own IDs, Keywording and Metadata show and change a version's row`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photo = try shoot(in: sandbox)
        let library = FolderLibrary()
        library.add([sandbox.root])
        library.open(sandbox.folder("Shoot"))
        let service = LibraryService(
            paths: LibraryPaths(root: sandbox.base.appending(path: "Library", directoryHint: .isDirectory)),
            sidecars: library.sidecars,
        ) { url, size in StoreThumbnailMaker.imageIO(url, nil, size) }
        sandbox.closes(service)
        library.attach(service)
        try await sandbox.eventually { !library.isListing && library.count == 3 }
        try await sandbox.eventually(seconds: 60) { library.isShownFromLibrary && !library.fromLibrary.adopting }
        await library.caughtUp()
        try #require(library.isShownFromLibrary && library.count == 3)
        try #require(!library.showsIndexIDs, "listed from the disk first, the list keeps IDs of its own")
        let model = EditorModel(engine: StubEngine(), library: library)
        model.showModule(.library)
        let panels = model.libraryPanels
        panels.follow()
        let rows = try await indexIDs(of: photo, in: service)
        let (own, copy) = (PhotoAddress(url: photo), PhotoAddress(url: photo, version: first))

        model.clickInGrid(copy)
        try await sandbox.eventually { panels.selection.ids == rows.versions }
        #expect(panels.selection.ids == rows.versions, "the version's row in the index, not its file's")
        #expect(panels.selection.activeID == rows.versions.first)
        #expect(keywords(panels) == ["Alfama"])
        #expect(panels.addKeywords("Tram"))
        #expect(panels.set(.title, to: "Up the hill"))
        try await written(panels, service)
        #expect(keywords(panels) == ["Alfama", "Tram"])
        #expect(panels.selection.fields[.title] == .same("Up the hill"))
        let sidecar = SidecarStore().load(for: photo)
        #expect(sidecar?.version(first)?.metadata?.keywords?.sorted() == ["Alfama", "Tram"])
        #expect(sidecar?.version(first)?.metadata?.title == "Up the hill")
        #expect(sidecar?.metadata?.keywords == ["Belém"] && sidecar?.metadata?.title == nil, "B's own as it was")

        model.clickInGrid(own)
        try await sandbox.eventually { panels.selection.ids == [rows.own] }
        #expect(keywords(panels) == ["Belém"])
        #expect(panels.selection.fields[.title] == SharedValue.none)
    }
}
