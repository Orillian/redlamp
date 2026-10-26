import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Keywords dropped and painted on a version's cell, and a version put in a collection (LIB-48, LIB-21, LIB-23): each
/// reaches the version's own row and its edit's metadata in the sidecar, never its file's, in a library source and in a
/// folder's own list using IDs of its own, and Undo takes it back; that list's stacks and groups take the version as
/// itself (LIB-28, LIB-41).
@MainActor
@Suite(.serialized)
struct TaggingVersionsTests {
    private let first = UUID()

    /// Where the photos are shown: All Photographs, or the folder's own list, listed from the disk before the library
    /// indexed it.
    enum Shown: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case source = "All Photographs"
        case ownList = "a folder's own list"

        var testDescription: String {
            rawValue
        }
    }

    /// A.JPG and B.JPG, B with a version, Copy 1, keyworded Alfama, shown as `shown` says in Library's grid with the
    /// panels following; returns B.
    private func open(_ sandbox: DragSandbox, _ shown: Shown) async throws -> URL {
        var sidecar = Sidecar(recipe: EditRecipe())
        sidecar.versions = [PhotoVersion(
            id: first, name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(keywords: ["Alfama"]),
        )]
        try await sandbox.open(photos: ["A.JPG", "B.JPG"], sidecars: ["B.JPG": sidecar], listedFirst: shown == .ownList)
        let model = try #require(sandbox.model)
        if shown == .source {
            #expect(model.librarySources.show(.allPhotographs))
            try await sandbox.eventually {
                sandbox.layOut()
                return !model.librarySources.isListing && sandbox.grid.cells.count == 3
            }
            try #require(model.items.count == 3 && model.library.showsIndexIDs, "All Photographs shown")
        }
        let photo = sandbox.photo("B.JPG")
        try #require(model.library.index(of: PhotoAddress(url: photo, version: first)) != nil, "the version listed")
        model.libraryPanels.follow()
        try await sandbox.eventually { model.libraryPanels.keywordList != nil }
        return photo
    }

    /// The index's rows of `photo`'s own edit and of its version, in that order.
    private func rows(of photo: URL, _ sandbox: DragSandbox) async throws -> [Int64] {
        let index = try #require(sandbox.service.core).index
        let edits = [PhotoAddress(url: photo), PhotoAddress(url: photo, version: first)]
        let ids = await LibraryService.indexIDs(of: edits, in: index)
        return try edits.map { try #require(ids[$0], "a row for the file and one for its version") }
    }

    /// The keywords of `photo`'s own edit and of its version, each sorted, as their rows in the index have them and as
    /// its sidecar holds them.
    private func keywords(
        of photo: URL,
        _ sandbox: DragSandbox,
    ) async throws -> (rows: [[String]], sidecar: [[String]]) {
        let rows = try await rows(of: photo, sandbox)
        let indexed = try await #require(sandbox.service.core).index.read { reader in
            try rows.map { try reader.keywords(forPhoto: $0).sorted() }
        }
        let sidecar = SidecarStore().load(for: photo)
        let saved = [sidecar?.metadata?.keywords, sidecar?.version(first)?.metadata?.keywords]
        return (indexed, saved.map { ($0 ?? []).sorted() })
    }

    /// The collections of `photo`'s own edit and of its version, as their rows in the index have them and as its
    /// sidecar holds them.
    private func collections(of photo: URL, _ sandbox: DragSandbox) async throws
        -> (rows: [[String]], sidecar: [[String]]) {
        let rows = try await rows(of: photo, sandbox)
        let indexed = try await #require(sandbox.service.core).index.read { reader in
            try rows.map { try reader.collections(ofPhoto: $0).map(\.text) }
        }
        let sidecar = SidecarStore().load(for: photo)
        return (indexed, [sidecar?.metadata?.collections ?? [], sidecar?.version(first)?.metadata?.collections ?? []])
    }

    /// Waits for `photo`'s own edit and its version to have the keywords `expected` says, its own first, in their rows
    /// and in its sidecar; then expects them to.
    private func expectKeywords(
        _ expected: [[String]], of photo: URL, _ sandbox: DragSandbox,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        try await SourcesSandbox.eventually { try await keywords(of: photo, sandbox) == (expected, expected) }
        let found = try await keywords(of: photo, sandbox)
        #expect(found.rows == expected, "the index's rows", sourceLocation: sourceLocation)
        #expect(found.sidecar == expected, "the sidecar's edits", sourceLocation: sourceLocation)
    }

    /// `expectKeywords` for the collections `photo`'s own edit and its version are in.
    private func expectCollections(
        _ expected: [[String]], of photo: URL, _ sandbox: DragSandbox,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        try await SourcesSandbox.eventually { try await collections(of: photo, sandbox) == (expected, expected) }
        let found = try await collections(of: photo, sandbox)
        #expect(found.rows == expected, "the index's rows", sourceLocation: sourceLocation)
        #expect(found.sidecar == expected, "the sidecar's edits", sourceLocation: sourceLocation)
    }

    // MARK: - Keywords on a version's cell

    @Test(arguments: Shown.allCases)
    func `a keyword dropped on a version's cell tags the version alone, its row and its edit, and Undo takes it off`(
        _ shown: Shown,
    ) async throws {
        let sandbox = DragSandbox()
        defer { sandbox.close() }
        let photo = try await open(sandbox, shown)
        let model = try #require(sandbox.model)
        let panels = model.libraryPanels
        let copy = PhotoAddress(url: photo, version: first)
        #expect(panels.create("Tram"))
        try await sandbox.panelsWritten()
        try await sandbox.eventually { sandbox.view("keywordList.name.Tram") != nil }
        sandbox.layOut()
        let label = try #require(sandbox.view("keywordList.name.Tram") as? KeywordDragLabel)
        let changes = panels.undoCount

        try sandbox.drag(label, to: sandbox.cell(copy), release: false)
        let outlined = sandbox.grid.cells.values.filter(\.isDropTarget).compactMap { $0.item?.address }
        #expect(outlined == [copy], "the version's cell alone")
        try label.mouseUp(with: sandbox.mouse(.leftMouseUp, at: sandbox.cell(copy)))
        try await sandbox.eventually { panels.undoCount > changes }
        try await sandbox.panelsWritten()
        #expect(panels.undoCount == changes + 1, "one change")
        try await expectKeywords([[], ["Alfama", "Tram"]], of: photo, sandbox)

        #expect(model.perform(.undo))
        try await sandbox.panelsWritten()
        try await expectKeywords([[], ["Alfama"]], of: photo, sandbox)
    }

    @Test(arguments: Shown.allCases)
    func `a keyword painted on a version's cell tags the version alone, its row and its edit, and Undo takes it off`(
        _ shown: Shown,
    ) async throws {
        let sandbox = DragSandbox()
        defer { sandbox.close() }
        let photo = try await open(sandbox, shown)
        let model = try #require(sandbox.model)
        let panels = model.libraryPanels
        let copy = PhotoAddress(url: photo, version: first)
        let painter = model.keywordPainter
        #expect(painter.setOn(true))
        painter.text = "Tram"
        let changes = panels.undoCount

        try sandbox.click(copy)
        #expect(painter.lastStroke == 1, "the stroke reached the version's cell alone")
        try await sandbox.eventually { panels.undoCount > changes }
        try await sandbox.panelsWritten()
        try await expectKeywords([[], ["Alfama", "Tram"]], of: photo, sandbox)

        #expect(model.perform(.undo))
        try await sandbox.panelsWritten()
        try await expectKeywords([[], ["Alfama"]], of: photo, sandbox)
    }

    // MARK: - A version in a collection

    @Test(arguments: Shown.allCases)
    func `Add to Collection with a version selected puts the version's row in it, not its file's, and Undo takes it out`(
        _ shown: Shown,
    ) async throws {
        let sandbox = DragSandbox()
        defer { sandbox.close() }
        let photo = try await open(sandbox, shown)
        let model = try #require(sandbox.model)
        let sources = model.librarySources
        let copy = PhotoAddress(url: photo, version: first)
        let picks = try #require(CollectionPath("Picks"))
        #expect(sources.create(.collection, named: "Picks"))
        try await sandbox.made { $0.collections[picks] != nil }

        try sandbox.click(copy)
        try await sandbox.eventually { model.activeAddress == copy }
        #expect(model.activeAddress == copy, "the version selected alone")
        #expect(sources.add(to: picks))
        try await sandbox.made { $0.count(of: .collection(picks)) == 1 }
        try await expectCollections([[], ["Picks"]], of: photo, sandbox)

        #expect(model.perform(.undo))
        try await sandbox.made { $0.count(of: .collection(picks)) == 0 }
        try await expectCollections([[], []], of: photo, sandbox)
    }

    @Test(arguments: Shown.allCases)
    func `B on the target collection and a drag onto a collection put a version in it as itself, each with Undo`(
        _ shown: Shown,
    ) async throws {
        let sandbox = DragSandbox()
        defer { sandbox.close() }
        let photo = try await open(sandbox, shown)
        let model = try #require(sandbox.model)
        let sources = model.librarySources
        let copy = PhotoAddress(url: photo, version: first)
        let picks = try #require(CollectionPath("Picks"))
        let selects = try #require(CollectionPath("Selects"))
        #expect(sources.create(.collection, named: "Picks", target: true))
        #expect(sources.create(.collection, named: "Selects"))
        try await sandbox.made { $0.collections.count == 2 && $0.target == picks }

        try sandbox.click(copy)
        try await sandbox.eventually { model.activeAddress == copy }
        #expect(model.perform(.toggleMark))
        try await sandbox.made { $0.count(of: .collection(picks)) == 1 }
        try await expectCollections([[], ["Picks"]], of: photo, sandbox)
        #expect(model.perform(.undo))
        try await sandbox.made { $0.count(of: .collection(picks)) == 0 }
        try await expectCollections([[], []], of: photo, sandbox)

        let row = SourceRow.identifier(of: .collection(selects))
        try await sandbox.eventually { sandbox.view(row) != nil }
        sandbox.layOut()
        let list = try #require(sandbox.first(CollectionOutlineView.self))
        try sandbox.press(copy)
        let location = try sandbox.middle(of: row)
        try sandbox.drag(from: sandbox.cell(copy), to: location, release: false)
        #expect(list.photoDropRow != nil, "the collection takes it")
        try sandbox.release(at: location)
        try await sandbox.made { $0.count(of: .collection(selects)) == 1 }
        try await expectCollections([[], ["Selects"]], of: photo, sandbox)
        #expect(model.perform(.undo))
        try await sandbox.made { $0.count(of: .collection(selects)) == 0 }
        try await expectCollections([[], []], of: photo, sandbox)
    }

    // MARK: - Stacks and groups in a folder's own list

    @Test func `in a folder's own list a version is in its file's pair, grouped as itself and stacked by hand as itself`(
    ) async throws {
        let sandbox = DragSandbox()
        defer { sandbox.close() }
        let photo = try await open(sandbox, .ownList)
        let model = try #require(sandbox.model)
        let a = PhotoAddress(url: sandbox.photo("A.JPG"))
        let copy = PhotoAddress(url: photo, version: first)
        let ids = try [a, PhotoAddress(url: photo), copy].map { try #require(model.library.photoID(of: $0)) }

        try await sandbox.eventually { model.gridStacks.list?.stacks.pair(containing: ids[2]) != nil }
        let pair = model.gridStacks.list?.stacks.pair(containing: ids[2])
        #expect(pair.map { Set($0.photos) } == Set([ids[1], ids[2]]), "the version in its file's pair")
        #expect(pair?.top == ids[1], "the file on top")

        model.setGroupKey(.folder)
        try await sandbox.eventually { model.gridGroups.list?.groups.key == .folder }
        let grouped = model.gridGroups.list?.groups.flatMap(\.photos) ?? []
        #expect(Set(grouped) == Set(ids), "every photo in its group, the version as itself")
        model.setGroupKey(.ungrouped)
        try await sandbox.eventually { model.gridGroups.list == nil }

        try sandbox.click(a)
        try sandbox.click(copy, modifiers: .command)
        #expect(model.perform(.stackPhotos))
        try await sandbox.panelsWritten()
        let sidecar = SidecarStore().load(for: photo)
        #expect(sidecar?.version(first)?.metadata?.stack != nil, "the version's own edit stacked, with its file's")
        #expect(sidecar?.metadata?.stack != nil)
    }
}
