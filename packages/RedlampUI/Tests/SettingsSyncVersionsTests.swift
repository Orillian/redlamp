import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Sync Settings and Paste on versions the library lists as photos of their own (LIB-48): each edit of a file the
/// selection holds is changed in its own place in the file's sidecar, in one write of it, with a history session of its
/// own, and Undo puts each back; the edits of the photo open in Develop other than the one open are changed there, in
/// what it saves.
@MainActor
@Suite(.serialized)
struct SettingsSyncVersionsTests {
    private let first = UUID()
    private let second = UUID()

    /// Runs `body` in Develop on IMG_0001.JPG and IMG_0002.JPG below Shoot, the second with versions Copy 1, rated 1
    /// and edited as `copy`, and Copy 2, shown in All Photographs with the versions' rows; then removes the sandbox.
    private func withShoot(
        copy: EditRecipe = EditRecipe(), _ body: (SourcesSandbox, EditorModel, URL) async throws -> Void,
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["Shoot/IMG_0001.JPG", "Shoot/IMG_0002.JPG"])
        let photo = sandbox.photo("Shoot/IMG_0002.JPG")
        var sidecar = Sidecar(recipe: EditRecipe())
        sidecar.versions = [
            PhotoVersion(id: first, name: "Copy 1", recipe: copy, metadata: PhotoMetadata(rating: 1)),
            PhotoVersion(id: second, name: "Copy 2", recipe: EditRecipe()),
        ]
        try SidecarStore().saveOrRemove(sidecar, for: photo)
        let model = try await sandbox.open()
        #expect(model.librarySources.show(.allPhotographs))
        try await sandbox.eventually { !model.librarySources.isListing && model.library.count == 4 }
        model.showModule(.develop)
        model.copySelection = .default
        try await body(sandbox, model, photo)
        model.copySelection = .default
    }

    /// Selects the rows of `photos`, and only them.
    private func select(_ photos: [PhotoAddress], in model: EditorModel) throws {
        model.selectOnly(photos.first)
        for photo in photos.dropFirst() {
            try model.photoSelection.toggle(#require(model.library.photoID(of: photo)), in: model.library.photoList)
        }
        try #require(model.selectedCount == photos.count)
    }

    /// The exposure of each of `photo`'s edits on disk: its own, then Copy 1's and Copy 2's.
    private func exposures(of photo: URL) -> [Double?] {
        let sidecar = SidecarStore().load(for: photo)
        return [nil, first, second].map { sidecar?[edit: $0]?.recipe[.exposure] }
    }

    /// Counts the batch's writes of each photo's sidecar.
    private final class Writes {
        var count: [URL: Int] = [:]
    }

    private func counting(_ model: EditorModel) -> Writes {
        let writes = Writes()
        model.settingsSync.beforeWriting = { url in writes.count[url, default: 0] += 1 }
        return writes
    }

    @Test func `sync onto a file and its versions writes each edit once in one write of its sidecar, and Undo puts each back`(
    ) async throws {
        try await withShoot { sandbox, model, photo in
            let open = sandbox.photo("Shoot/IMG_0001.JPG")
            model.select(open)
            try await sandbox.eventually { model.openPhoto == PhotoAddress(url: open) }
            try select(
                [
                    PhotoAddress(url: open),
                    PhotoAddress(url: photo),
                    PhotoAddress(url: photo, version: first),
                    PhotoAddress(url: photo, version: second),
                ],
                in: model,
            )
            let writes = counting(model)
            model.setValue(.exposure, 1)

            model.syncSettings()
            await model.settingsSync.idle()
            #expect(writes.count == [photo: 1], "one write of the file's sidecar for its three edits")
            #expect(exposures(of: photo) == [1, 1, 1])
            let store = SidecarStore()
            for version in [nil, first, second] {
                let titles = store.loadHistory(for: photo, version: version).flatMap(\.steps).map(\.title)
                #expect(
                    titles == ["Opened", "Sync Settings"],
                    "a session of each edit's own: \(String(describing: version))",
                )
            }
            #expect(store.load(for: photo)?.version(first)?.metadata?.rating == 1, "its metadata stays")
            for version in [nil, first, second] {
                let row = try #require(model.library.index(of: PhotoAddress(url: photo, version: version)))
                #expect(model.library.items[row].hasEdits, "\(String(describing: version))'s row shows its edit")
            }

            #expect(model.canPerform(.undoSync))
            model.undoSync()
            await model.settingsSync.idle()
            #expect(writes.count == [photo: 2], "Undo puts the three back in one write too")
            #expect(exposures(of: photo) == [0, 0, 0])
            #expect(store.load(for: photo)?.versions.map(\.id) == [first, second])
        }
    }

    @Test func `paste onto a version alone changes only its edit`() async throws {
        try await withShoot { sandbox, model, photo in
            let open = sandbox.photo("Shoot/IMG_0001.JPG")
            model.select(open)
            try await sandbox.eventually { model.openPhoto == PhotoAddress(url: open) }
            model.setValue(.exposure, 2)
            model.copySettings()
            try select([PhotoAddress(url: open), PhotoAddress(url: photo, version: second)], in: model)

            model.pasteSettings()
            await model.settingsSync.idle()
            #expect(exposures(of: photo) == [0, 0, 2])
            let titles = SidecarStore().loadHistory(for: photo, version: second).flatMap(\.steps).map(\.title)
            #expect(titles == ["Opened", "Paste Settings"])
            #expect(
                SidecarStore().loadHistory(for: photo, version: nil).isEmpty,
                "the file's own edit has no new session",
            )
        }
    }

    @Test func `sync from the version open reaches the photo's other edits in Develop, saved with it, and Undo puts them back`(
    ) async throws {
        try await withShoot { sandbox, model, photo in
            let version = PhotoAddress(url: photo, version: first)
            model.select(version)
            try await sandbox.eventually { model.openPhoto == version }
            try select([version, PhotoAddress(url: photo), PhotoAddress(url: photo, version: second)], in: model)
            let writes = counting(model)
            model.setValue(.exposure, 1.5)

            model.syncSettings()
            await model.settingsSync.idle()
            #expect(model.openPhoto == version, "the version stays open")
            #expect(model.recipe[.exposure] == 1.5)
            model.saveNow()
            await model.saves.wait(for: photo)
            #expect(writes.count.isEmpty, "the editor saves the photo it has open")
            #expect(exposures(of: photo) == [1.5, 1.5, 1.5])
            let titles = SidecarStore().loadHistory(for: photo, version: second).flatMap(\.steps).map(\.title)
            #expect(titles == ["Opened", "Sync Settings"])

            model.undoSync()
            await model.settingsSync.idle()
            model.saveNow()
            await model.saves.wait(for: photo)
            #expect(exposures(of: photo) == [0, 1.5, 0], "the edit open keeps its own")
        }
    }

    @Test func `Copy Settings with a version active in Library copies the version's edit`() async throws {
        var edited = EditRecipe()
        edited[.exposure] = 0.7
        try await withShoot(copy: edited) { sandbox, model, photo in
            model.select(photo)
            try await sandbox.eventually { model.openPhoto == PhotoAddress(url: photo) }
            model.showModule(.library)
            model.selectOnly(PhotoAddress(url: photo, version: first))

            model.copySettings()
            try await sandbox.eventually { model.hasClipboard }
            #expect(model.clipboard?.source[.exposure] == 0.7, "Copy 1's edit, not the file's own open in the editor")
            #expect(model.openPhoto == PhotoAddress(url: photo))
        }
    }

    @Test func `Copy Settings from a version's menu reads its own edit from its sidecar`() async throws {
        var edited = EditRecipe()
        edited[.exposure] = -0.4
        try await withShoot(copy: edited) { sandbox, model, photo in
            let open = sandbox.photo("Shoot/IMG_0001.JPG")
            model.select(open)
            try await sandbox.eventually { model.openPhoto == PhotoAddress(url: open) }

            await model.copySettings(from: PhotoAddress(url: photo, version: first))
            #expect(model.clipboard?.source[.exposure] == -0.4)
            await model.copySettings(from: PhotoAddress(url: photo))
            #expect(model.clipboard?.source[.exposure] == 0, "the file's own edit")
        }
    }
}
