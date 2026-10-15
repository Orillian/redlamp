import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampDocument

/// Versions in the sidecar (EDT-09): another edit of the photo, with its own metadata, snapshots and history,
/// kept beside the photo's own edit so builds from before versions show the photo as it was.
struct SidecarVersionTests {
    /// Files keep whole seconds.
    private static let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func temporaryImage() throws -> (URL, () -> Void) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory.appending(path: "IMG_0001.ARW"), { try? FileManager.default.removeItem(at: directory) })
    }

    private func subjectMask(_ png: Data) -> MaskLayer {
        MaskLayer(name: "Subject", components: [MaskComponent(shape: .ai(AIMask(
            kind: .subject, provider: "test", revision: 1, analysisHash: "0", center: ImagePoint(x: 0.5, y: 0.5),
            bitmap: MaskBitmap(png: png, width: 4, height: 2), createdAt: Self.date,
        )))])
    }

    private func recipe(exposure: Double, masks: [MaskLayer] = []) -> EditRecipe {
        var recipe = EditRecipe()
        recipe[.exposure] = exposure
        recipe.masks = masks
        return recipe
    }

    private func version(
        _ name: String = "Copy 1", id: UUID = UUID(), exposure: Double = 1, metadata: PhotoMetadata? = nil,
        snapshots: [Snapshot] = [],
    ) -> PhotoVersion {
        PhotoVersion(
            id: id, name: name, created: Self.date, recipe: recipe(exposure: exposure), metadata: metadata,
            snapshots: snapshots,
        )
    }

    private func session(
        started: Date = Date(timeIntervalSince1970: 1000), exposure: Double = 0.5, version: UUID? = nil,
    ) -> HistorySession {
        HistorySession(started: started, steps: [
            HistoryStep(action: .open, title: "Opened", recipe: EditRecipe()),
            HistoryStep(action: .adjustment(.exposure), title: "Exposure", recipe: recipe(exposure: exposure)),
        ], versionID: version)
    }

    private func historyFiles(_ store: SidecarStore, _ image: URL) -> [String] {
        let directory = store.url(for: image).appending(path: SidecarStore.historyDirectory)
        return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func editJSON(_ store: SidecarStore, _ image: URL) throws -> [String: JSONValue] {
        let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: store.editURL(for: image)))
        return try #require(written.objectValue)
    }

    // MARK: - Saving and reading

    @Test func `a version is saved with its edit, metadata, snapshots and bitmaps, and reads back`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let edited = Data("version subject".utf8)
        let snapped = Data("version snapshot".utf8)
        var copy = version(metadata: PhotoMetadata(rating: 5, flag: .pick, keywords: ["Harbour"]))
        copy.recipe.masks = [subjectMask(edited)]
        copy.snapshots = [Snapshot(name: "Before", created: Self.date, recipe: recipe(exposure: 0, masks: [
            subjectMask(snapped),
        ]))]
        try store.save(Sidecar(recipe: recipe(exposure: 0.5), versions: [copy], modified: Self.date), for: image)

        let loaded = try #require(store.load(for: image))
        #expect(loaded.recipe[.exposure] == 0.5)
        #expect(loaded.versions == [copy])
        #expect(loaded.versions.first?.recipe.maskBitmaps.first?.png == edited)
        #expect(loaded.versions.first?.snapshots.first?.recipe.maskBitmaps.first?.png == snapped)
        #expect(store.protection(for: image) == nil)

        var changed = loaded
        changed.versions[0].recipe[.contrast] = 20
        try store.save(changed, for: image)
        for png in [edited, snapped] {
            #expect(FileManager.default.fileExists(atPath: store.bitmapURL(MaskBitmap.hash(png), for: image).path))
        }
        changed.versions = []
        try store.save(changed, for: image)
        for png in [edited, snapped] {
            #expect(!FileManager.default.fileExists(atPath: store.bitmapURL(MaskBitmap.hash(png), for: image).path))
        }
    }

    @Test func `a sidecar without versions is written as before them`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        try store.save(Sidecar(recipe: recipe(exposure: 0.5), metadata: PhotoMetadata(rating: 2)), for: image)
        #expect(try Set(editJSON(store, image).keys) == ["format", "recipe", "snapshots", "metadata", "modified"])
    }

    @Test func `a version keeps a sidecar whose own edit is back to defaults, and removing it removes the sidecar`(
    ) throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let pristine = PhotoVersion(name: "Copy 1", recipe: EditRecipe())
        #expect(!Sidecar(recipe: EditRecipe(), versions: [pristine]).isPristine)

        try store.saveOrRemove(Sidecar(recipe: EditRecipe(), versions: [pristine]), for: image)
        #expect(store.load(for: image)?.versions.map(\.id) == [pristine.id])
        try store.saveOrRemove(Sidecar(recipe: EditRecipe()), for: image)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: image).path))
    }

    @Test func `fields a newer build added to a version are kept`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        try store.save(Sidecar(recipe: EditRecipe(), versions: [version()]), for: image)
        var edit = try editJSON(store, image)
        var versions = try #require(edit["versions"]?.arrayValue)
        var first = try #require(versions[0].objectValue)
        first["pinned"] = .bool(true)
        versions[0] = .object(first)
        edit["versions"] = .array(versions)
        try JSONEncoder().encode(JSONValue.object(edit)).write(to: store.editURL(for: image))
        #expect(store.protection(for: image) == nil)

        var sidecar = try #require(store.load(for: image))
        sidecar.versions[0].recipe[.contrast] = 10
        try store.save(sidecar, for: image)
        let saved = try editJSON(store, image)["versions"]?.arrayValue?.first
        #expect(saved?["pinned"] == .bool(true))
    }

    @Test func `a version with a newer process version makes the sidecar read only`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let json = #"{"format":"app.redlamp.edit","recipe":{"version":3,"processVersion":1},"versions":[{"#
            + #""id":"8E2B4F1A-3C5D-4E6F-9A7B-0C1D2E3F4A5B","name":"Copy 1","created":"2026-10-15T18:05:00Z","#
            + #""recipe":{"version":3,"processVersion":99}}]}"#
        try Data(json.utf8).write(to: store.url(for: image))
        #expect(store.protection(for: image) == .writtenByNewerVersion)
        #expect(throws: SidecarStoreError.writtenByNewerVersion(store.url(for: image))) {
            try store.save(Sidecar(recipe: EditRecipe()), for: image)
        }
    }

    /// A build from before versions takes `versions` for a top-level key it doesn't know, and keeps such keys by
    /// the rules this build keeps them by; read here under a name this build doesn't know, it stands for that.
    @Test func `a build from before versions keeps them, and the bitmaps only they use`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let png = Data("only the version".utf8)
        var copy = version()
        copy.recipe.masks = [subjectMask(png)]
        var sidecar = Sidecar(recipe: recipe(exposure: 0.5), versions: [copy])
        sidecar.unsavedSessions = [session(version: copy.id)]
        try store.save(sidecar, for: image)
        let unknown = "versionsOfALaterBuild"
        var edit = try editJSON(store, image)
        let versions = try #require(edit["versions"])
        edit["versions"] = nil
        edit[unknown] = versions
        try JSONEncoder().encode(JSONValue.object(edit)).write(to: store.editURL(for: image))

        #expect(store.protection(for: image) == nil)
        var older = try #require(store.load(for: image))
        older.recipe[.contrast] = 10
        try store.save(older, for: image)
        #expect(try editJSON(store, image)[unknown] == versions)
        #expect(FileManager.default.fileExists(atPath: store.bitmapURL(MaskBitmap.hash(png), for: image).path))

        let file = store.url(for: image).appending(path: "history/\(sidecar.unsavedSessions[0].id.uuidString).json")
        let written = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        #expect(written["version"] == .number(2), "a reader of format 1 skips it")
    }

    // MARK: - Addressing a version

    @Test func `an edit is read and written by its version`() {
        let copy = version(exposure: 1, metadata: PhotoMetadata(rating: 4))
        var sidecar = Sidecar(recipe: recipe(exposure: 0.5), metadata: PhotoMetadata(rating: 1), versions: [copy])
        #expect(sidecar[edit: nil]?.recipe[.exposure] == 0.5)
        #expect(sidecar[edit: copy.id]?.metadata?.rating == 4)
        #expect(sidecar[edit: UUID()] == nil)

        sidecar[edit: copy.id]?.recipe[.exposure] = 2
        sidecar[edit: nil]?.metadata = PhotoMetadata(rating: 3)
        sidecar[edit: UUID()] = PhotoEdit(recipe: EditRecipe())
        #expect(sidecar.versions.first?.recipe[.exposure] == 2)
        #expect(sidecar.versions.first?.name == "Copy 1")
        #expect(sidecar.metadata?.rating == 3 && sidecar.recipe[.exposure] == 0.5)
        #expect(sidecar.versions.count == 1)
    }

    @Test func `a new version takes its source's edit and metadata, but not what's the file's`() throws {
        var sidecar = Sidecar(recipe: recipe(exposure: 0.5), metadata: PhotoMetadata(
            rating: 3, flag: .pick, label: .red, originalName: "DSC_0001.NEF", keywords: ["Harbour"], mark: true,
            title: "Dawn", collections: ["Selects"], stack: PhotoStack(id: UUID(), top: true), captureShift: 60,
            captureOffset: 3600,
        ))
        sidecar.snapshots = [Snapshot(name: "Before", recipe: EditRecipe())]
        let added = sidecar.addVersion(of: nil, created: Self.date)
        let first = try #require(added)
        #expect(first.name == "Copy 1" && first.created == Self.date && first.snapshots.isEmpty)
        #expect(first.recipe == sidecar.recipe)
        #expect(first.metadata == PhotoMetadata(
            rating: 3, flag: .pick, label: .red, keywords: ["Harbour"], title: "Dawn", collections: ["Selects"],
        ))

        sidecar.versions[0].recipe[.exposure] = 1
        let addedAgain = sidecar.addVersion(of: first.id)
        let second = try #require(addedAgain)
        #expect(second.name == "Copy 2" && second.recipe[.exposure] == 1)
        let unknown = sidecar.addVersion(of: UUID())
        #expect(unknown == nil)
        #expect(sidecar.versions.map(\.name) == ["Copy 1", "Copy 2"])
    }

    @Test func `new versions are named after the highest copy's number`() {
        var sidecar = Sidecar(recipe: EditRecipe())
        #expect(sidecar.nextVersionName == "Copy 1")
        sidecar.versions = [version("Copy 2"), version("Lightroom Classic"), version("Copy seven")]
        #expect(sidecar.nextVersionName == "Copy 3")
    }

    @Test func `the summary lists the versions as the library shows them`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let edited = version(metadata: PhotoMetadata(rating: 5))
        let plain = PhotoVersion(name: "Copy 2", created: Self.date, recipe: EditRecipe())
        try store.save(Sidecar(recipe: EditRecipe(), versions: [edited, plain]), for: image)
        let summary = try #require(store.summary(for: image))
        #expect(!summary.hasEdits)
        #expect(summary.versions == [
            VersionSummary(
                id: edited.id, name: "Copy 1", created: Self.date, hasEdits: true, metadata: PhotoMetadata(rating: 5),
            ),
            VersionSummary(id: plain.id, name: "Copy 2", created: Self.date, hasEdits: false),
        ])
    }

    // MARK: - Conflicting copies

    @Test func `conflicting copies keep every version, each merged as the photo's edit is`() {
        let shared = UUID()
        let older = Sidecar(
            recipe: recipe(exposure: 0.5),
            versions: [version("Copy 1", id: shared, exposure: 1), version("Only older", exposure: 2)],
            modified: Date(timeIntervalSince1970: 1000),
        )
        var newerVersion = version("Renamed", id: shared, exposure: 1.5, metadata: PhotoMetadata(rating: 4))
        newerVersion.snapshots = [Snapshot(name: "Mine", recipe: EditRecipe())]
        let newer = Sidecar(
            recipe: recipe(exposure: 0.5), versions: [version("Only newer", exposure: 3), newerVersion],
            modified: Date(timeIntervalSince1970: 2000),
        )

        let merged = SidecarStore.merge(older, [newer])
        #expect(merged.versions.map(\.name) == ["Only newer", "Renamed", "Only older"])
        let both = merged.versions[1]
        #expect(both.id == shared && both.recipe[.exposure] == 1.5 && both.metadata?.rating == 4)
        #expect(both.snapshots.map(\.name).first == "Mine")
        #expect(both.snapshots.last?.recipe[.exposure] == 1)
        #expect(both.snapshots.last?.name.hasPrefix("Edit from another Mac") == true)
        #expect(merged.snapshots.isEmpty, "the photo's own edit is the same in both")
        #expect(SidecarStore.merge(newer, [newer]) == newer)
    }

    @Test func `a save over another writer's keeps the versions each side added, changed or kept`() {
        let kept = version("Kept", exposure: 1)
        let theyRemove = version("They remove", exposure: 2)
        let weRemove = version("We remove", exposure: 3)
        let base = Sidecar(
            recipe: recipe(exposure: 0.5), versions: [kept, theyRemove, weRemove],
            modified: Date(timeIntervalSince1970: 1000),
        )

        var ours = base
        ours.modified = Date(timeIntervalSince1970: 3000)
        ours.versions = [kept, theyRemove, version("We add", exposure: 4)]
        ours.versions[0].recipe[.contrast] = 10
        var theirs = base
        theirs.modified = Date(timeIntervalSince1970: 2000)
        theirs.versions = [kept, weRemove, version("They add", exposure: 5)]
        theirs.versions[0].name = "Renamed"

        let merged = SidecarStore.merge(ours, theirs, base: base, opened: base)
        #expect(merged.versions.map(\.name) == ["Renamed", "We add", "They add"])
        #expect(merged.versions[0].recipe[.contrast] == 10)

        var changedHere = ours
        changedHere.versions[1].recipe[.contrast] = 20
        #expect(
            SidecarStore.merge(changedHere, theirs, base: base, opened: base).versions.map(\.name)
                .contains("They remove"),
            "changed here since they removed it",
        )
        var changedThere = theirs
        changedThere.versions[1].recipe[.contrast] = 30
        #expect(
            SidecarStore.merge(ours, changedThere, base: base, opened: base).versions.map(\.name)
                .contains("We remove"),
            "changed there since it was removed here",
        )
    }

    @Test func `a version both sides changed goes to the newer, the other kept as its snapshot`() {
        let copy = version(exposure: 1)
        let base = Sidecar(recipe: EditRecipe(), versions: [copy], modified: Date(timeIntervalSince1970: 1000))
        var ours = base
        ours.modified = Date(timeIntervalSince1970: 3000)
        ours.versions[0].recipe[.exposure] = 2
        var theirs = base
        theirs.modified = Date(timeIntervalSince1970: 2000)
        theirs.versions[0].recipe[.exposure] = 3
        theirs.versions[0].metadata = PhotoMetadata(rating: 2)

        let merged = SidecarStore.merge(ours, theirs, base: base, opened: base)
        #expect(merged.versions.count == 1)
        #expect(merged.versions[0].recipe[.exposure] == 2)
        #expect(merged.versions[0].snapshots.map { $0.recipe[.exposure] } == [3])
        #expect(merged.versions[0].metadata?.rating == 2, "only they rated it")
    }

    // MARK: - History

    @Test func `a version's sessions are its own, written in format 2`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let copy = version()
        let own = session(started: Date(timeIntervalSince1970: 1000))
        var sidecar = Sidecar(recipe: recipe(exposure: 0.5), versions: [copy], session: own)
        let versionSession = session(started: Date(timeIntervalSince1970: 2000), exposure: 1, version: copy.id)
        sidecar.unsavedSessions = [versionSession]
        try store.save(sidecar, for: image)

        #expect(store.loadHistory(for: image).map(\.id) == [versionSession.id, own.id])
        #expect(store.loadHistory(for: image, version: nil) == [own])
        #expect(store.loadHistory(for: image, version: copy.id) == [versionSession])
        let directory = store.url(for: image).appending(path: SidecarStore.historyDirectory)
        let ownFile = try JSONDecoder().decode(
            JSONValue.self, from: Data(contentsOf: directory.appending(path: "\(own.id.uuidString).json")),
        )
        #expect(ownFile["version"] == .number(1) && ownFile["versionID"] == nil)
        let versionFile = try JSONDecoder().decode(
            JSONValue.self, from: Data(contentsOf: directory.appending(path: "\(versionSession.id.uuidString).json")),
        )
        #expect(versionFile["version"] == .number(2))
        #expect(versionFile["versionID"] == .string(copy.id.uuidString))
    }

    @Test func `each edit keeps its own most recent sessions`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let copy = version()
        let versionSession = session(started: Date(timeIntervalSince1970: 500), version: copy.id)
        var first = Sidecar(recipe: EditRecipe(), versions: [copy], session: versionSession)
        first.modified = Self.date
        try store.save(first, for: image)
        for number in 0 ..< SidecarStore.keptSessions + 2 {
            let own = session(started: Date(timeIntervalSince1970: 1000 + Double(number) * 60))
            try store.save(Sidecar(recipe: EditRecipe(), versions: [copy], session: own), for: image)
        }
        #expect(store.loadHistory(for: image, version: nil).count == SidecarStore.keptSessions)
        #expect(store.loadHistory(for: image, version: copy.id) == [versionSession])
    }

    @Test func `clearing a version's history leaves the photo's, and removing a version removes its sessions`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let copy = version()
        let own = session(started: Date(timeIntervalSince1970: 1000))
        let earlier = session(started: Date(timeIntervalSince1970: 2000), version: copy.id)
        var sidecar = Sidecar(recipe: recipe(exposure: 0.5), versions: [copy], session: own)
        sidecar.unsavedSessions = [earlier]
        try store.save(sidecar, for: image)

        let open = session(started: Date(timeIntervalSince1970: 3000), exposure: 2, version: copy.id)
        var cleared = Sidecar(recipe: recipe(exposure: 0.5), versions: [copy], session: open)
        cleared.clearsHistory = true
        try store.save(cleared, for: image)
        #expect(store.loadHistory(for: image, version: copy.id) == [open])
        #expect(store.loadHistory(for: image, version: nil) == [own])

        try store.save(Sidecar(recipe: recipe(exposure: 0.5), session: own), for: image)
        #expect(store.loadHistory(for: image).map(\.id) == [own.id])
        #expect(historyFiles(store, image) == ["\(own.id.uuidString).json"])
    }

    @Test func `a version's sessions don't keep a sidecar whose last version is removed`() throws {
        let (image, cleanup) = try temporaryImage()
        defer { cleanup() }
        let store = SidecarStore()
        let copy = version()
        try store.save(
            Sidecar(recipe: EditRecipe(), versions: [copy], session: session(version: copy.id)), for: image,
        )
        try store.saveOrRemove(Sidecar(recipe: EditRecipe()), for: image)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: image).path))
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(object) = self else { return nil }
        return object
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(items) = self else { return nil }
        return items
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}
