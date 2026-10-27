import AppKit
import Foundation
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Library Health's Missing check in the app (DEC-59): a photo whose file goes outside Redlamp leaves every list for
/// the
/// check, which says where it was and when it went; from it Locate… relinks the photo to a file with its content and
/// Remove from Library takes it out, each on Library's Undo; and what would write to its file is off there.
@MainActor
@Suite(.serialized)
struct MissingPhotosTests {
    @Test func `a missing photo's mark says so, where it was and when it went, and what can be done`() {
        let since = Date(timeIntervalSince1970: 1_760_000_000)
        let finding = HealthFinding(photo: 1, check: .missing, reason: .missing(from: "/Photos/Shoot", since: since))
        let mark = HealthMark(finding)
        #expect(mark.word == "Missing" && mark.proposal == .none && !mark.isFramed)
        #expect(mark.sentence.hasPrefix("gone from /Photos/Shoot since 20"))
        #expect(mark.sentence.hasSuffix(": Locate… finds it again, and Remove from Library takes it out"))
        #expect(LibrarySource.health(.missing).title == "Missing Photos")
    }

    @Test func `a photo deleted in the Finder leaves every list for the Missing check, where Remove takes it out, with Undo`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG", "Shoot/C.JPG"])
        let model = try await sandbox.open()
        let sources = model.librarySources
        try await sandbox.counts { $0.count(of: .allPhotographs) == 3 }
        try FileManager.default.removeItem(at: sandbox.photo("Shoot/B.JPG"))
        try await sandbox.counts { $0.count(of: .health(.missing)) == 1 && $0.count(of: .allPhotographs) == 2 }
        #expect(sources.count(of: .health(.missing)) == 1 && sources.count(of: .allPhotographs) == 2)

        model.showFolder(sandbox.folder("Shoot"))
        try await sandbox.eventually { model.items.count == 2 }
        #expect(Set(model.items.map(\.name)) == ["A.JPG", "C.JPG"], "the folder without it")

        #expect(sources.show(.health(.missing)))
        try await sandbox
            .eventually { !sources.isListing && model.items.count == 1 && model.healthProposals.marked == 1 }
        #expect(model.items.map(\.name) == ["B.JPG"])
        let shown = try #require(model.items.first?.url)
        let mark = try #require(model.healthProposals.mark(for: shown))
        #expect(mark.word == "Missing")
        #expect(mark.sentence.hasPrefix("gone from \(LibraryService.path(sandbox.folder("Shoot"))) since "))
        model.select(shown)
        #expect(model.canPerform(.locateMissingPhoto) && model.canPerform(.removeMissingPhotos))
        #expect(!model.canPerform(.keepAnyway) && !model.canPerform(.acceptHealthProposals))
        #expect(!model.canPerform(.rating3) && !model.canPerform(.editTool) && !model.canPerform(.showInFinder))
        #expect(!model.perform(.rating3), "culling leaves its sidecar alone")

        #expect(model.perform(.removeMissingPhotos))
        await model.healthChangesMade()
        try await sandbox.counts { $0.count(of: .health(.missing)) == nil }
        #expect(model.healthUndoCount == 1)
        #expect(model.perform(.undo))
        await model.healthChangesMade()
        try await sandbox.counts { $0.count(of: .health(.missing)) == 1 }
        #expect(sources.count(of: .allPhotographs) == 2, "back as missing, still out of the other lists")
    }

    @Test func `Locate… relinks a missing photo to the file chosen, with the others found beside it, and ⌘Z takes it back`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            sandbox.remove()
            EditorModel.answerLocate(with: nil)
        }
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG", "Shoot/C.JPG"])
        let model = try await sandbox.open()
        let sources = model.librarySources
        try await sandbox.counts { $0.count(of: .allPhotographs) == 3 }
        let core = try #require(sandbox.service?.core)
        let path = LibraryService.path(sandbox.photo("Shoot/A.JPG"))
        let id = try #require(await core.index.read { try $0.photo(path: path) }?.id)
        // Copies elsewhere in the library, as from a backup, then the originals deleted.
        try FileManager.default.createDirectory(at: sandbox.folder("Found"), withIntermediateDirectories: true)
        for name in ["A.JPG", "B.JPG"] {
            try FileManager.default.copyItem(at: sandbox.photo("Shoot/" + name), to: sandbox.photo("Found/" + name))
            try FileManager.default.removeItem(at: sandbox.photo("Shoot/" + name))
        }
        try await sandbox.counts { $0.count(of: .health(.missing)) == 2 && $0.count(of: .allPhotographs) == 3 }

        #expect(sources.show(.health(.missing)))
        try await sandbox
            .eventually { !sources.isListing && model.items.count == 2 && model.healthProposals.marked == 2 }
        let shown = try #require(model.items.first { $0.name == "A.JPG" }?.url)
        model.select(shown)
        EditorModel.answerLocate(with: sandbox.photo("Found/A.JPG"), relinkingOthers: true)
        #expect(model.perform(.locateMissingPhoto))
        try await sandbox.eventually { model.healthUndoCount == 1 }
        await model.healthChangesMade()
        try await sandbox.counts { $0.count(of: .health(.missing)) == nil && $0.count(of: .allPhotographs) == 3 }
        let found = LibraryService.path(sandbox.photo("Found/A.JPG"))
        #expect(try await core.index.read { try $0.photo(path: found) }?.id == id, "the photo's own row, relinked")

        #expect(model.perform(.undo))
        await model.healthChangesMade()
        try await sandbox.counts { $0.count(of: .health(.missing)) == 2 && $0.count(of: .allPhotographs) == 3 }
        #expect(try await core.index.read { try $0.photo(id: id) }?.state == [.missing], "missing again where it was")
    }

    @Test func `a folder's missing photos are each a cell of their own, so Locate… relinks the one selected`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer {
            sandbox.remove()
            EditorModel.answerLocate(with: nil)
        }
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG", "Shoot/C.JPG"])
        let model = try await sandbox.open()
        let sources = model.librarySources
        try await sandbox.counts { $0.count(of: .allPhotographs) == 3 }
        // Copies of B and C elsewhere in the library, then the three originals deleted.
        try FileManager.default.createDirectory(at: sandbox.folder("Found"), withIntermediateDirectories: true)
        for name in ["B.JPG", "C.JPG"] {
            try FileManager.default.copyItem(at: sandbox.photo("Shoot/" + name), to: sandbox.photo("Found/" + name))
        }
        for name in ["A.JPG", "B.JPG", "C.JPG"] {
            try FileManager.default.removeItem(at: sandbox.photo("Shoot/" + name))
        }
        try await sandbox.counts { $0.count(of: .health(.missing)) == 3 && $0.count(of: .allPhotographs) == 2 }

        let stacks = model.gridStacks
        #expect(sources.show(.health(.missing)))
        try await sandbox.eventually {
            !sources.isListing && model.items.count == 3 && model.healthProposals.marked == 3
                && stacks.stackingsMade > 0 && stacks.isIdle
        }
        #expect(model.items.count == 3 && stacks.stackingsMade > 0 && stacks.isIdle, "the photos listed and stacked")
        #expect(stacks.list == nil, "no stack of the photos the index has no names for")
        let shown = try #require(model.items.first { $0.name == "B.JPG" }?.url)
        model.select(shown)
        // Closed stacks cover the selection on the next main-actor turn.
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.selection == shown && model.selectedCount == 1, "B alone, active")

        EditorModel.answerLocate(with: sandbox.photo("Found/B.JPG"), relinkingOthers: true)
        #expect(model.perform(.locateMissingPhoto))
        try await sandbox.eventually { model.healthUndoCount == 1 }
        await model.healthChangesMade()
        try await sandbox.counts { $0.count(of: .health(.missing)) == 1 && $0.count(of: .allPhotographs) == 2 }
        #expect(model.healthUndoCount == 1, "B relinked to its copy")
        #expect(
            sources.count(of: .health(.missing)) == 1 && sources.count(of: .allPhotographs) == 2,
            "C relinked beside it, A still missing",
        )
    }

    @Test func `a photo deleted in Apple Photos is listed by the Missing check with Remove and no Locate…`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/A.JPG"])
        let model = try await sandbox.open()
        let sources = model.librarySources
        let core = try #require(sandbox.service?.core)
        let photos = SimulatedPhotosLibrary(
            collections: [ApplePhotosCollection(id: "album-trip", title: "Trip", kind: .album)],
            assets: [ApplePhotosAsset(
                id: "8A1F0001-0000-4000-8000-000000000001/L0/001", cloud: "cloud-0001",
                created: Date(timeIntervalSince1970: 1_760_000_000), albums: ["album-trip"],
                resources: [ApplePhotosResource(kind: .photo, type: "public.jpeg", originalFilename: "IMG_0001.JPG")],
            )],
        )
        let indexer = ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live)
        try await indexer.keep(["album-trip"])
        try await sandbox.counts { $0.count(of: .allPhotographs) == 2 }
        photos.delete(["8A1F0001-0000-4000-8000-000000000001/L0/001"])
        #expect(try await indexer.update().missing.count == 1)
        try await sandbox.counts { $0.count(of: .health(.missing)) == 1 && $0.count(of: .allPhotographs) == 1 }

        #expect(sources.show(.health(.missing)))
        try await sandbox
            .eventually { !sources.isListing && model.items.count == 1 && model.healthProposals.marked == 1 }
        let shown = try #require(model.items.first?.url)
        let mark = try #require(model.healthProposals.mark(for: shown))
        #expect(mark.word == "Missing" && mark.sentence.hasPrefix("no longer in Apple Photos since "))
        #expect(mark.sentence.hasSuffix(": Remove from Library takes it out, and Photos isn't changed"))
        model.select(shown)
        #expect(!model.canPerform(.locateMissingPhoto) && model.canPerform(.removeMissingPhotos))
        #expect(model.perform(.removeMissingPhotos))
        await model.healthChangesMade()
        try await sandbox.counts { $0.count(of: .health(.missing)) == nil }
    }
}
