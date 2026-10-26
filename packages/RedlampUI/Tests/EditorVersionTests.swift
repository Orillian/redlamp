import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import Testing
@testable import RedlampUI

/// Versions in Develop (EDT-09): Create Version makes another edit of the photo open, which opens in place of the
/// one it was made from, with its own history, snapshots and metadata, saved in the photo's one sidecar.
@MainActor
struct EditorVersionTests {
    @MainActor private struct Editor {
        let model = EditorModel(engine: StubEngine())
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        var photo: URL {
            folder.appending(path: "IMG_0001.ARW")
        }

        var other: URL {
            folder.appending(path: "IMG_0002.ARW")
        }

        /// The photo's sidecar as it is on disk.
        var saved: Sidecar? {
            SidecarStore().load(for: photo)
        }
    }

    private func openEditor() async throws -> (Editor, () -> Void) {
        let editor = Editor()
        try FileManager.default.createDirectory(at: editor.folder, withIntermediateDirectories: true)
        try await open(editor.photo, in: editor.model)
        return (editor, { try? FileManager.default.removeItem(at: editor.folder) })
    }

    private func open(_ url: URL, in model: EditorModel) async throws {
        model.select(url)
        try await eventually { model.info?.url == url }
        try #require(model.info?.url == url)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func `Create Version copies the edit open and opens the copy in its place`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.setValue(.exposure, 0.5)
        model.createSnapshot()
        model.createVersion()

        let version = try #require(model.versions.first)
        #expect(model.versions.map(\.name) == ["Copy 1"])
        #expect(model.openVersion == version.id && model.openEditName == "Copy 1")
        #expect(model.value(.exposure) == 0.5)
        #expect(model.snapshots.isEmpty, "a version starts without snapshots")
        #expect(model.history.map(\.title) == ["Created from Original"])

        model.setValue(.exposure, 1)
        model.saveNow()
        try await eventually { editor.saved?.versions.first?.recipe[.exposure] == 1 }
        let saved = try #require(editor.saved)
        #expect(saved.recipe[.exposure] == 0.5 && saved.snapshots.count == 1)
        #expect(saved.versions.map(\.id) == [version.id] && saved.versions.first?.recipe[.exposure] == 1)

        model.createVersion()
        #expect(model.versions.map(\.name) == ["Copy 1", "Copy 2"])
        #expect(model.value(.exposure) == 1, "made from the version open")
        #expect(model.history.first?.title == "Created from Copy 1")
    }

    @Test func `each edit has its own snapshots and history`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.setValue(.exposure, 0.5)
        model.createVersion()
        let version = try #require(model.openVersion)
        model.setValue(.contrast, 20)
        model.createSnapshot()
        #expect(model.snapshots.count == 1)

        model.showVersion(nil)
        #expect(model.openVersion == nil && model.value(.contrast) == 0 && model.value(.exposure) == 0.5)
        #expect(model.snapshots.isEmpty)
        model.showVersion(version)
        #expect(model.value(.contrast) == 20 && model.snapshots.count == 1)

        try await eventually { SidecarStore().loadHistory(for: editor.photo, version: version).count == 1 }
        let sessions = SidecarStore().loadHistory(for: editor.photo)
        #expect(sessions.contains { $0.versionID == version && $0.steps.last?.recipe[.contrast] == 20 })
        #expect(sessions.contains { $0.versionID == nil && $0.steps.last?.recipe[.exposure] == 0.5 })

        try await open(editor.other, in: model)
        try await open(editor.photo, in: model)
        try await eventually { !model.earlierSessions.isEmpty }
        #expect(model.earlierSessions.allSatisfy { $0.versionID == nil })
        model.showVersion(version)
        try await eventually { !model.earlierSessions.isEmpty }
        #expect(model.earlierSessions.allSatisfy { $0.versionID == version })
    }

    @Test func `Clear History in a version clears the version's sessions and leaves the photo's own`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.setValue(.exposure, 0.5)
        model.createVersion()
        let version = try #require(model.openVersion)
        model.setValue(.contrast, 20)
        model.saveNow()
        try await eventually { !SidecarStore().loadHistory(for: editor.photo, version: version).isEmpty }
        #expect(SidecarStore().loadHistory(for: editor.photo, version: nil).count == 1)

        model.clearHistory()
        try await eventually { SidecarStore().loadHistory(for: editor.photo, version: version).isEmpty }
        #expect(SidecarStore().loadHistory(for: editor.photo, version: version).isEmpty)
        #expect(SidecarStore().loadHistory(for: editor.photo, version: nil).count == 1)
        #expect(editor.saved?.versions.first?.recipe[.contrast] == 20)
    }

    @Test func `a version survives leaving the photo and opening it again`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.createVersion()
        let version = try #require(model.openVersion)
        model.setTreatment(.blackAndWhite)
        try await open(editor.other, in: model)
        try await eventually { editor.saved?.versions.first?.recipe.treatment == .blackAndWhite }

        try await open(editor.photo, in: model)
        #expect(model.versions.map(\.id) == [version] && model.openVersion == nil)
        #expect(model.treatment == .color)
        model.showVersion(version)
        #expect(model.treatment == .blackAndWhite)

        try await open(editor.other, in: model)
        model.select(PhotoAddress(url: editor.photo, version: version))
        try await eventually { model.info?.url == editor.photo }
        #expect(model.openVersion == version && model.treatment == .blackAndWhite)
    }

    @Test func `a version is renamed and removed, its history with it`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.setValue(.exposure, 0.5)
        model.createVersion()
        let version = try #require(model.openVersion)
        model.setValue(.exposure, 1)
        model.renameVersion(version, to: "  Black and white  ")
        #expect(model.versions.map(\.name) == ["Black and white"])
        try await eventually { editor.saved?.versions.first?.name == "Black and white" }
        try await eventually { !SidecarStore().loadHistory(for: editor.photo, version: version).isEmpty }

        model.removeVersion(version)
        #expect(model.versions.isEmpty && model.openVersion == nil && model.value(.exposure) == 0.5)
        try await eventually { editor.saved?.versions.isEmpty == true }
        try await eventually { SidecarStore().loadHistory(for: editor.photo, version: version).isEmpty }
        #expect(editor.saved?.recipe[.exposure] == 0.5)
    }

    @Test func `a version's rating is its own, and the photo's row keeps the photo's`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.cull(.rating(2))
        model.createVersion()
        #expect(model.photoMetadata.rating == 2, "a version takes the metadata of the edit it was made from")
        model.cull(.rating(5))
        #expect(model.photoMetadata.rating == 5)
        try await eventually { editor.saved?.versions.first?.metadata?.rating == 5 }
        #expect(editor.saved?.metadata?.rating == 2)
        model.showVersion(nil)
        #expect(model.photoMetadata.rating == 2)
    }

    @Test func `settings copied from a version paste onto another photo`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.createVersion()
        model.setValue(.exposure, 0.75)
        model.copySettings()
        model.pasteSettings(onto: editor.other)
        try await eventually { SidecarStore().load(for: editor.other)?.recipe[.exposure] == 0.75 }
        #expect(SidecarStore().load(for: editor.other)?.recipe[.exposure] == 0.75)
        #expect(editor.saved?.recipe[.exposure] == 0, "the photo's own edit is as it was")
    }

    @Test func `a version's export is named with the version's name, and the photo's own edit's without one`(
    ) async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.createVersion()
        let version = try #require(model.openVersion)
        model.renameVersion(version, to: "Black and white")
        let named = ExportActions.reader(
            for: SelectedPhotos([PhotoAddress(url: editor.photo, version: version)]), model: model,
        )
        #expect(await named().map(\.fields.version) == ["Black and white"])

        model.showVersion(nil)
        let own = ExportActions.reader(for: SelectedPhotos([PhotoAddress(url: editor.photo)]), model: model)
        #expect(await own().map(\.fields.version) == [nil])
    }

    @Test func `a version's export carries its own rating, label and fields, and the photo's where it holds none`() {
        let photo = ExportMetadata.Fields(
            title: "The photo", caption: "Its caption", creators: ["Pedro"], copyright: "© Pedro",
            keywords: ["Lisbon", "Places"], keywordPaths: [["Places", "Lisbon"]], rating: 2, label: "Red",
        )
        let metadata = PhotoMetadata(rating: 5, label: .green, keywords: ["Places/Porto"], title: "The version")
        let fields = EditorModel.versionFields(
            metadata,
            over: photo,
            keywords: KeywordDefinitions(),
            labels: .lightroom,
        )
        #expect(fields.rating == 5 && fields.label == "Green" && fields.title == "The version")
        #expect(fields.caption == "Its caption" && fields.creators == ["Pedro"] && fields.copyright == "© Pedro")
        #expect(fields.keywordPaths == [["Places", "Porto"]] && !fields.keywords.contains("Lisbon"))

        let unrated = EditorModel.versionFields(
            PhotoMetadata(), over: photo, keywords: KeywordDefinitions(), labels: .lightroom,
        )
        #expect(unrated.rating == nil && unrated.label == nil && unrated.keywordPaths == photo.keywordPaths)
    }

    @Test func `Paste from Previous pastes the edit open before, a version's or the photo's own`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.copySelection = .default
        model.createVersion()
        let version = try #require(model.openVersion)
        model.setValue(.exposure, 1)
        try await open(editor.other, in: model)
        model.pasteFromPrevious()
        try await eventually { model.value(.exposure) == 1 }
        #expect(model.value(.exposure) == 1, "the version open on the photo left")

        try await open(editor.photo, in: model)
        model.showVersion(version)
        model.showVersion(nil)
        #expect(model.value(.exposure) == 0)
        model.pasteFromPrevious()
        try await eventually { model.value(.exposure) == 1 }
        #expect(model.openVersion == nil && model.value(.exposure) == 1, "the version open before the photo's own")
    }

    @Test func `an import from Lightroom Classic leaves the photo open as it is while one of its versions is open`(
    ) async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        var imported = EditRecipe()
        imported[.exposure] = 0.7
        let path = editor.photo.standardizedFileURL.path
        model.createVersion()
        #expect(await model.lightroomEditor.change(path, imported, nil, [], []) == .left)
        #expect(model.value(.exposure) == 0)

        model.showVersion(nil)
        #expect(await model.lightroomEditor.change(path, imported, nil, [], []) != .left)
        #expect(model.value(.exposure) == 0.7)
    }

    @Test func `another writer's removal of the version open opens the photo's own edit`() async throws {
        let (editor, cleanup) = try await openEditor()
        defer { cleanup() }
        let model = editor.model
        model.setValue(.exposure, 0.5)
        model.createVersion()
        model.saveNow()
        try await eventually { editor.saved?.versions.count == 1 }
        var theirs = try #require(editor.saved)
        theirs.versions = []
        #expect(model.showOtherWriters(theirs))
        #expect(model.openVersion == nil && model.versions.isEmpty && model.value(.exposure) == 0.5)
    }
}
