import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Versions in a folder's own list (LIB-48), as they change: made, renamed and removed in Develop, each photo's
/// versions after it in a folder listed from the disk, and with their file when it's renamed or moved.
@MainActor
@Suite(.serialized)
struct FolderListVersionsTests {
    private let first = UUID()
    private let second = UUID()

    @MainActor
    final class Diffs {
        var all: [LibraryDiff] = []
        var observation: LibraryObservation?
    }

    /// Small JPEGs A, B and Day 2/D below Shoot, B with versions Copy 1 and Copy 2 and D with one, Copy 1.
    private func shoot(in sandbox: SourcesSandbox) throws {
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG", "Shoot/Day 2/D.JPG"])
        try save(
            [(first, "Copy 1", 1), (second, "Copy 2", 2)], rating: 3, for: sandbox.photo("Shoot/B.JPG"),
        )
        try save([(UUID(), "Copy 1", 4)], rating: 0, for: sandbox.photo("Shoot/Day 2/D.JPG"))
    }

    /// Saves `photo`'s sidecar with its own rating and `versions`, each with its name and rating.
    private func save(_ versions: [(UUID, String, Int)], rating: Int, for photo: URL) throws {
        var sidecar = Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: rating))
        sidecar.versions = versions.map { id, name, rating in
            PhotoVersion(id: id, name: name, recipe: EditRecipe(), metadata: PhotoMetadata(rating: rating))
        }
        try SidecarStore().saveOrRemove(sidecar, for: photo)
    }

    /// What `library` shows, a row a line: each photo's path below Shoot, and a version's name after a colon.
    private func shown(_ library: FolderLibrary, in sandbox: SourcesSandbox) -> [String] {
        let shoot = sandbox.folder("Shoot").path + "/"
        return library.items.allRows.map { item in
            let path = String(item.url.path.dropFirst(shoot.count))
            return item.versionName.map { "\(path):\($0)" } ?? path
        }
    }

    @Test func `a folder listed from the disk shows each photo's versions after it, and follows the disk`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try shoot(in: sandbox)
        let photo = sandbox.photo("Shoot/B.JPG")
        let library = FolderLibrary()
        library.add([sandbox.root])
        let diffs = Diffs()
        diffs.observation = library.observe { diffs.all.append($0) }
        library.open(sandbox.folder("Shoot"))
        try await sandbox.eventually { !library.isListing && library.count == 6 }
        #expect(shown(library, in: sandbox) == [
            "A.JPG", "B.JPG", "B.JPG:Copy 1", "B.JPG:Copy 2", "Day 2/D.JPG", "Day 2/D.JPG:Copy 1",
        ])
        #expect(library.items.allRows.map(\.metadata.rating) == [0, 3, 1, 2, 0, 4], "each version's own badges")
        #expect(library.items.row(2)?.title == "Copy 1, a version of B.JPG")
        let (copy, other) = (PhotoAddress(url: photo, version: first), PhotoAddress(url: photo, version: second))
        #expect([copy, other].map { library.index(of: $0) } == [2, 3])
        let ids = try [copy, other].map { try #require(library.photoID(of: $0)) }

        diffs.all = []
        try sandbox.photos(["Shoot/C.JPG"], from: 3)
        library.changed([sandbox.folder("Shoot").path])
        try await sandbox.eventually { library.count == 7 }
        #expect(shown(library, in: sandbox) == [
            "A.JPG", "B.JPG", "B.JPG:Copy 1", "B.JPG:Copy 2", "C.JPG", "Day 2/D.JPG", "Day 2/D.JPG:Copy 1",
        ])
        #expect(diffs.all.allSatisfy { !$0.reset && $0.removed.isEmpty }, "a file added on disk leaves the versions")
        #expect([copy, other].map { library.photoID(of: $0) } == ids)

        try save([(second, "Black and white", 2), (UUID(), "Copy 3", 5)], rating: 3, for: photo)
        library.changed([sandbox.folder("Shoot").path])
        try await sandbox.eventually { shown(library, in: sandbox).contains("B.JPG:Copy 3") }
        #expect(shown(library, in: sandbox) == [
            "A.JPG", "B.JPG", "B.JPG:Black and white", "B.JPG:Copy 3", "C.JPG", "Day 2/D.JPG", "Day 2/D.JPG:Copy 1",
        ], "the versions its sidecar has now, in its order")
        #expect(library.photoID(of: other) == ids[1], "a version renamed keeps its row")
        #expect(library.index(of: copy) == nil)
        #expect(library.items.row(3)?.metadata.rating == 5)

        try FileManager.default.removeItem(at: sandbox.photo("Shoot/Day 2/D.JPG"))
        library.changed([sandbox.folder("Shoot/Day 2").path])
        try await sandbox.eventually { library.count == 5 }
        #expect(shown(library, in: sandbox) == ["A.JPG", "B.JPG", "B.JPG:Black and white", "B.JPG:Copy 3", "C.JPG"])
    }

    @Test func `a version made, renamed or removed in Develop comes, changes and goes in a folder listed from the disk`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG"])
        let photo = sandbox.photo("Shoot/B.JPG")
        let model = EditorModel(engine: StubEngine())
        model.open([sandbox.folder("Shoot")])
        try await sandbox.eventually { !model.library.isListing && model.library.count == 2 }
        #expect(!model.library.isShownFromLibrary)
        model.clickInGrid(PhotoAddress(url: photo))
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }

        model.createVersion()
        let version = try #require(model.openVersion)
        let copy = PhotoAddress(url: photo, version: version)
        try await sandbox.eventually { model.library.index(of: copy) != nil }
        #expect(shown(model.library, in: sandbox) == ["A.JPG", "B.JPG", "B.JPG:Copy 1"])
        #expect(model.activeAddress == copy, "the version open the active cell")

        model.renameVersion(version, to: "Black and white")
        try await sandbox.eventually { model.library.items.row(2)?.versionName == "Black and white" }
        #expect(shown(model.library, in: sandbox) == ["A.JPG", "B.JPG", "B.JPG:Black and white"])

        model.removeVersion(version)
        try await sandbox.eventually { model.library.count == 2 }
        #expect(shown(model.library, in: sandbox) == ["A.JPG", "B.JPG"])
        #expect(model.activeAddress == PhotoAddress(url: photo))
    }

    @Test func `a folder listed from the disk keeps its versions where they are as the library's list takes over`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try shoot(in: sandbox)
        let library = FolderLibrary()
        library.add([sandbox.root])
        let diffs = Diffs()
        diffs.observation = library.observe { diffs.all.append($0) }
        library.open(sandbox.folder("Shoot"))
        let service = LibraryService(
            paths: LibraryPaths(root: sandbox.base.appending(path: "Library", directoryHint: .isDirectory)),
            sidecars: library.sidecars,
        ) { url, size in StoreThumbnailMaker.imageIO(url, nil, size) }
        sandbox.closes(service)
        library.attach(service)
        try await sandbox.eventually { !library.isListing && library.count == 6 }
        #expect(!library.isShownFromLibrary, "listed from the disk while the library indexes it")
        let (listed, ids) = (library.items.allRows, library.photoIDs)
        diffs.all = []

        try await sandbox.eventually(seconds: 60) { library.isShownFromLibrary && !library.fromLibrary.adopting }
        await library.caughtUp()
        #expect(library.isShownFromLibrary)
        #expect(diffs.all.allSatisfy { !$0.reset && $0.removed.isEmpty && $0.inserted.isEmpty }, "no row moves")
        #expect(library.items.allRows.map(\.address) == listed.map(\.address))
        #expect(library.photoIDs == ids, "each photo, a version's too, under the ID it was listed with")
        #expect(library.items.allRows.map(\.title) == listed.map(\.title))
        #expect(library.items.allRows.map(\.metadata.rating) == listed.map(\.metadata.rating))
    }

    // MARK: - Renames and moves

    /// Shoot below the root, indexed and shown from the library in Library, with `photos` and B.JPG's versions Copy 1
    /// and Copy 2; and whether a photo was ever shown twice at once.
    private func showShoot(_ photos: [String], in sandbox: SourcesSandbox) async throws -> (EditorModel, Twice) {
        try sandbox.photos(photos.map { "Shoot/" + $0 })
        try save([(first, "Copy 1", 1), (second, "Copy 2", 2)], rating: 3, for: sandbox.photo("Shoot/B.JPG"))
        let model = try await sandbox.open()
        model.library.open(sandbox.folder("Shoot"))
        try await sandbox.eventually {
            model.library.isShownFromLibrary && !model.library.isListing && model.library.count == photos.count + 2
        }
        try #require(model.library.count == photos.count + 2)
        let twice = Twice()
        twice.observation = model.library.observe { [weak twice] _ in
            let shown = model.library.items.allRows.map(\.address)
            let repeated = Set(shown).count < shown.count || Set(model.library.photoIDs).count < shown.count
            twice?.seen = twice?.seen == true || repeated
        }
        return (model, twice)
    }

    /// Whether a photo was ever shown twice at once.
    @MainActor
    final class Twice {
        var seen = false
        var observation: LibraryObservation?
    }

    /// Holds the library's changes, and with them its batches, until the gate is released.
    private func hold(_ sandbox: SourcesSandbox) async throws -> (Gate, Task<Void, Never>) {
        let core = try #require(sandbox.service?.core)
        let gate = Gate()
        gate.hold()
        let turn = Task { await core.change { await gate.pass() } }
        try await sandbox.eventually { gate.arrived > 0 }
        try #require(gate.arrived > 0)
        return (gate, turn)
    }

    /// The IDs of B.JPG's own row and its versions' as `model` shows them at `photo`.
    private func ids(of photo: URL, in model: EditorModel) -> [Int64?] {
        [nil, first, second].map { model.library.photoID(of: PhotoAddress(url: photo, version: $0)) }
    }

    @Test func `a file renamed takes its versions with it at once, and Undo brings them back with it`() async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let (model, twice) = try await showShoot(["A.JPG", "B.JPG", "C.JPG"], in: sandbox)
        let (photo, renamed) = (sandbox.photo("Shoot/B.JPG"), sandbox.photo("Shoot/Z-1.JPG"))
        let before = shown(model.library, in: sandbox)
        #expect(before == ["A.JPG", "B.JPG", "B.JPG:Copy 1", "B.JPG:Copy 2", "C.JPG"])
        let rows = ids(of: photo, in: model)
        model.clickInGrid(PhotoAddress(url: photo, version: first))
        let sheet = try #require(model.renameSheet(presets: NamingPresetStore(url: nil)))
        await sheet.start()
        await sheet.namesFollow()
        sheet.setText("Z-{sequence}")

        var (gate, turn) = try await hold(sandbox)
        let renaming = Task { await model.rename(sheet) }
        let after = ["A.JPG", "C.JPG", "Z-1.JPG", "Z-1.JPG:Copy 1", "Z-1.JPG:Copy 2"]
        try await sandbox.eventually { shown(model.library, in: sandbox) == after }
        #expect(shown(model.library, in: sandbox) == after, "the versions with their file before its batch runs")
        #expect(ids(of: renamed, in: model) == rows, "each under its ID")
        #expect(model.activeAddress == PhotoAddress(url: renamed, version: first), "the version active goes with it")
        gate.release()
        await turn.value
        #expect(await renaming.value == nil)
        await model.filesMade()
        await model.library.caughtUp()
        #expect(shown(model.library, in: sandbox) == after && ids(of: renamed, in: model) == rows)

        (gate, turn) = try await hold(sandbox)
        #expect(model.perform(.undo))
        try await sandbox.eventually { shown(model.library, in: sandbox) == before }
        #expect(shown(model.library, in: sandbox) == before, "back with their file before Undo's batch runs")
        #expect(ids(of: photo, in: model) == rows)
        gate.release()
        await turn.value
        await model.filesMade()
        await model.library.caughtUp()
        #expect(shown(model.library, in: sandbox) == before && ids(of: photo, in: model) == rows)
        #expect(FileManager.default.fileExists(atPath: photo.path))
        #expect(!twice.seen, "no photo shown twice")
    }

    @Test func `a file moved takes its versions with it at once, within the folders shown or out of them, and Undo brings them back`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try FileManager.default.createDirectory(at: sandbox.folder("Other"), withIntermediateDirectories: true)
        let (model, twice) = try await showShoot(["A.JPG", "B.JPG", "Day 2/C.JPG"], in: sandbox)
        let (photo, moved) = (sandbox.photo("Shoot/B.JPG"), sandbox.photo("Shoot/Day 2/B.JPG"))
        let before = shown(model.library, in: sandbox)
        #expect(before == ["A.JPG", "B.JPG", "B.JPG:Copy 1", "B.JPG:Copy 2", "Day 2/C.JPG"])
        let rows = ids(of: photo, in: model)

        var (gate, turn) = try await hold(sandbox)
        let moving = Task { await model.movePhotos([photo], to: sandbox.folder("Shoot/Day 2")) }
        let after = ["A.JPG", "Day 2/B.JPG", "Day 2/B.JPG:Copy 1", "Day 2/B.JPG:Copy 2", "Day 2/C.JPG"]
        try await sandbox.eventually { shown(model.library, in: sandbox) == after }
        #expect(shown(model.library, in: sandbox) == after, "the versions with their file before its batch runs")
        #expect(ids(of: moved, in: model) == rows)
        gate.release()
        await turn.value
        #expect(await moving.value == nil)
        await model.filesMade()
        await model.library.caughtUp()
        #expect(shown(model.library, in: sandbox) == after && ids(of: moved, in: model) == rows)

        (gate, turn) = try await hold(sandbox)
        #expect(model.perform(.undo))
        try await sandbox.eventually { shown(model.library, in: sandbox) == before }
        #expect(shown(model.library, in: sandbox) == before, "back with their file before Undo's batch runs")
        gate.release()
        await turn.value
        await model.filesMade()
        await model.library.caughtUp()
        #expect(shown(model.library, in: sandbox) == before && ids(of: photo, in: model) == rows)

        (gate, turn) = try await hold(sandbox)
        let leaving = Task { await model.movePhotos([photo], to: sandbox.folder("Other")) }
        try await sandbox.eventually { shown(model.library, in: sandbox) == ["A.JPG", "Day 2/C.JPG"] }
        #expect(shown(model.library, in: sandbox) == ["A.JPG", "Day 2/C.JPG"], "out of the folders shown with it")
        gate.release()
        await turn.value
        #expect(await leaving.value == nil)
        await model.filesMade()
        await model.library.caughtUp()
        #expect(shown(model.library, in: sandbox) == ["A.JPG", "Day 2/C.JPG"])

        (gate, turn) = try await hold(sandbox)
        #expect(model.perform(.undo))
        try await sandbox.eventually { shown(model.library, in: sandbox) == before }
        #expect(shown(model.library, in: sandbox) == before, "Undo shows them again with their file at once")
        gate.release()
        await turn.value
        await model.filesMade()
        await model.library.caughtUp()
        #expect(shown(model.library, in: sandbox) == before)
        #expect(!twice.seen, "no photo shown twice")
    }

    /// The IDs of the version rows the index has of `photo`'s file, in their order.
    private func indexedVersions(of photo: URL, in sandbox: SourcesSandbox) async throws -> [Int64] {
        let index = try #require(sandbox.service?.core).index
        return try await index.read { reader in
            guard let file = try LibraryService.photo(at: photo, in: reader) else { return [] }
            return try reader.versions(folder: file.folder, name: file.name).map(\.id)
        }
    }

    @Test func `a version made, renamed or removed in Develop comes, changes its name and goes in its folder's list`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/A.JPG", "Shoot/B.JPG"])
        let photo = sandbox.photo("Shoot/B.JPG")
        let model = try await sandbox.open()
        model.library.open(sandbox.folder("Shoot"))
        try await sandbox.eventually {
            model.library.isShownFromLibrary && !model.library.isListing && model.library.count == 2
        }
        try #require(model.library.isShownFromLibrary && model.library.count == 2, "Shoot shown from the library")
        let own = PhotoAddress(url: photo)
        let ownID = try #require(model.library.photoID(of: own))
        model.clickInGrid(own)
        model.showModule(.develop)
        try await sandbox.eventually { model.info?.url == photo && model.opening == nil }

        model.createVersion()
        let version = try #require(model.openVersion)
        let copy = PhotoAddress(url: photo, version: version)
        try await sandbox.eventually { model.library.index(of: copy) != nil }
        #expect(model.activeAddress == copy, "the version open the active cell once its row comes")
        model.showModule(.library)
        #expect(model.library.count == 3)
        #expect([own, copy].map { model.library.index(of: $0) } == [1, 2], "the version after its file")
        #expect(model.library.items.row(2)?.title == "Copy 1, a version of B.JPG")
        let indexed = try await indexedVersions(of: photo, in: sandbox)
        #expect(indexed.count == 1 && indexed.first == model.library.photoID(of: copy), "by its ID in the index")
        #expect(model.library.photoID(of: own) == ownID, "its file's row as it was")

        model.showModule(.develop)
        model.renameVersion(version, to: "Black and white")
        try await sandbox.eventually { model.library.items.row(2)?.versionName == "Black and white" }
        #expect(model.library.items.row(2)?.title == "Black and white, a version of B.JPG")
        #expect(model.library.index(of: copy) == 2 && model.library.count == 3, "renamed where it was")

        model.removeVersion(version)
        try await sandbox.eventually { model.library.count == 2 }
        #expect(model.library.index(of: copy) == nil, "the version gone from the list")
        #expect(model.library.index(of: own) == 1 && model.library.photoID(of: own) == ownID, "its file's row stays")
        #expect(model.activeAddress == own && model.openVersion == nil, "the photo's own edit open in its place")
        #expect(model.library.items.allRows.map(\.title) == ["A.JPG", "B.JPG"])
        try await SourcesSandbox.eventually { try await indexedVersions(of: photo, in: sandbox).isEmpty }
    }
}
