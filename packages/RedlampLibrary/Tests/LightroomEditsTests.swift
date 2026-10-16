import Foundation
import RedlampDocument
import RedlampEngineAPI
import Synchronization
import Testing
@testable import RedlampLibrary

/// A Lightroom Classic catalog's photo edits (EDT-23): the report's Edits section before anything is written,
/// worked out from the catalog's Develop settings and the library's photos.
struct LightroomEditsTests {
    struct Library {
        let sandbox: KeywordSandbox
        let folder: TemporaryFolder
        let catalog: URL
        /// The catalog's images, by the photos' names.
        let images: [String: Int64]

        func plan() async throws -> LightroomPlan {
            try await LightroomPlan.make(LightroomCatalog.read(catalog), index: sandbox.index, paths: sandbox.paths)
        }

        func importer(editor: LightroomEditor? = nil) -> LightroomImport {
            LightroomImport(index: sandbox.index, paths: sandbox.paths, editor: editor)
        }

        /// Whether the index shows the photo at `path` as edited.
        func edited(_ path: String) async throws -> Bool {
            let id = try await sandbox.id(path)
            return try #require(try await sandbox.index.read { try $0.photo(id: id) }).edited
        }

        func remove() {
            sandbox.remove()
        }
    }

    static func library() async throws -> Library {
        let sandbox = try await KeywordSandbox.make()
        for name in [
            "2024/June/IMG_0001.CR3", "2024/June/IMG_0001.JPG", "2024/June/IMG_0002.CR3", "2024/July/IMG_0003.JPG",
            "2024/July/IMG_0004.JPG", "2024/July/IMG_0006.CR3",
        ] {
            try sandbox.photo(name)
        }
        let xmp = sandbox.url("2024/June/IMG_0002.xmp")
        try Data(#"<x:xmpmeta xmlns:x="adobe:ns:meta/"></x:xmpmeta>"#.utf8).write(to: xmp)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)],
            ofItemAtPath: xmp.path,
        )
        try sandbox.sidecar("2024/July/IMG_0004.JPG", PhotoMetadata(rating: 3))
        try await sandbox.indexAll()
        let folder = try TemporaryFolder()
        let maker = try LightroomCatalogMaker(at: folder.url.appending(path: "Lightroom Catalog.lrcat"))
        let top = try maker.root(sandbox.root.path + "/")
        let june = try maker.folder(top, "2024/June/")
        let july = try maker.folder(top, "2024/July/")
        let size = (width: 6000, height: 4000)
        let first = try maker.photo(june, "IMG_0001.CR3", sidecars: "JPG", size: size)
        let second = try maker.photo(june, "IMG_0002.CR3", size: size)
        let third = try maker.photo(july, "IMG_0003.JPG")
        let fourth = try maker.photo(july, "IMG_0004.JPG")
        let sixth = try maker.photo(july, "IMG_0006.CR3", size: size)
        let copy = try maker.photo(june, "IMG_0001.CR3", master: first, copyName: "Copy 1")
        try maker.develop(first, LightroomSettingsText.text(["Exposure2012": "0.5"]), digest: "D1")
        try maker.snapshot(first, name: "Brighter", text: LightroomSettingsText.text(["Exposure2012": "1.5"]))
        try maker.history(first, steps: 3)
        try maker.develop(
            second,
            LightroomSettingsText.text(["Exposure2012": "0.25"], ["LensBlur = { Active = true }"]),
        )
        try maker.edited(third)
        try maker.develop(fourth, LightroomSettingsText.text(["Exposure2012": "1"]))
        try maker.develop(sixth, LightroomSettingsText.text(["ProcessVersion": "\"5.7\"", "Brightness": "60"]))
        try maker.develop(copy, LightroomSettingsText.text(["Exposure2012": "-1"]))
        maker.close()
        return Library(
            sandbox: sandbox, folder: folder, catalog: maker.url,
            images: ["IMG_0001.CR3": first, "IMG_0002.CR3": second, "IMG_0006.CR3": sixth],
        )
    }

    @Test func `the report's Edits section says what each photo's edit becomes, before anything is written`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let plan = try await library.plan()
        let edits = plan.report.edits
        #expect(edits.photos == 3, "IMG_0001, IMG_0002 and IMG_0006; IMG_0004 is Redlamp's")
        #expect(edits.full + edits.approximated + edits.leftOut == 3 && edits.leftOut >= 2)
        #expect(edits.processes["Process 2010"] == 1 && edits.processes["Process 2012"] == 2)
        #expect(edits.snapshots == 1 && edits.historySteps == 3 && edits.pairs == 1)
        #expect(edits.kept == 1 && edits.keptPaths.first?.hasSuffix("2024/July/IMG_0004.JPG") == true)
        #expect(edits.unreadable == 1, "IMG_0003 is marked edited without settings")
        #expect(edits.virtualCopies == 1)
        #expect(edits.newerXMP == 1, "IMG_0002's .xmp changed after the catalog was written")
        let lensBlur = try #require(edits.reasons.first { $0.settings.contains("LensBlur") })
        #expect(lensBlur.why.contains("OTH-03") && lensBlur.photos == 1)
        #expect(lensBlur.paths.first?.hasSuffix("2024/June/IMG_0002.CR3") == true)
        #expect(edits.reasons.contains { $0.why.contains("EDT-31") && $0.photos == 1 })
        #expect(plan.report.left.contains { $0.what == "virtual copies" && $0.why.contains("0.3.4") })
        #expect(plan.report.left.contains { $0.what.hasPrefix("steps of the edited photos' histories") })
        #expect(plan.report.lines().contains("  edits, for the photos found:"))
        let json = try JSONDecoder().decode(LightroomReport.self, from: plan.report.json())
        #expect(json.edits == edits)

        let raw = try await library.sandbox.id("2024/June/IMG_0001.CR3")
        let jpeg = try await library.sandbox.id("2024/June/IMG_0001.JPG")
        #expect(plan.edits.count == 3 && plan.edits[jpeg] == nil, "the raw takes the pair's edit")
        let made = try #require(plan.edits[raw]).made()
        #expect(made.recipe[.exposure] == 0.5)
        #expect(made.recipe.provenance?.source == .lightroomCatalog)
        #expect(made.recipe.provenance?.photo == library.images["IMG_0001.CR3"])
        #expect(made.recipe.provenance?.digest == "D1" && made.recipe.provenance?.path == library.catalog.path)
        #expect(made.snapshots.map(\.name) == ["Brighter"] && made.snapshots.first?.recipe[.exposure] == 1.5)
    }

    @Test func `the import writes each photo's edit and snapshots with its fields, and Undo takes them back`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let importer = library.importer()
        let plan = try await library.plan()
        try library.sandbox.sidecar("2024/June/IMG_0002.CR3", PhotoMetadata(rating: 2))
        let outcome = try await importer.run(plan)
        #expect(outcome.record.batches.map(\.journal) == [.metadata])
        #expect(outcome.written == 3, "IMG_0001, IMG_0006 and IMG_0002, which kept its sidecar as it was")
        let raw = try #require(library.sandbox.sidecar("2024/June/IMG_0001.CR3"))
        #expect(raw.recipe[.exposure] == 0.5 && raw.recipe.provenance?.digest == "D1")
        #expect(raw.snapshots.map(\.name) == ["Brighter"] && raw.snapshots.first?.recipe[.exposure] == 1.5)
        #expect(try await library.edited("2024/June/IMG_0001.CR3"))
        #expect(try await library.edited("2024/July/IMG_0006.CR3"))
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.JPG") == nil, "the raw takes the pair's edit")
        let meanwhile = try #require(library.sandbox.sidecar("2024/June/IMG_0002.CR3"))
        #expect(meanwhile.recipe[.exposure] == 0.35 && meanwhile.recipe.provenance == nil, "edited since the plan")
        #expect(library.sandbox.sidecar("2024/July/IMG_0004.JPG")?.recipe.provenance == nil, "Redlamp's edit stays")

        try await importer.undo()
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.CR3") == nil, "nothing is left in it")
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3") == nil)
        #expect(try await !library.edited("2024/June/IMG_0001.CR3"))
        #expect(library.sandbox.sidecar("2024/June/IMG_0002.CR3")?.recipe[.exposure] == 0.35)
    }

    @Test func `Undo keeps an imported edit changed since, and takes off only the snapshots the import added`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let importer = library.importer()
        try await importer.run(library.plan())
        let store = SidecarStore()
        var changed = try #require(library.sandbox.sidecar("2024/June/IMG_0001.CR3"))
        changed.recipe[.contrast] = 20
        changed.snapshots.append(Snapshot(name: "Mine", recipe: changed.recipe))
        try store.save(changed, for: library.sandbox.url("2024/June/IMG_0001.CR3"))

        try await importer.undo()
        let kept = try #require(library.sandbox.sidecar("2024/June/IMG_0001.CR3"))
        #expect(kept.recipe[.contrast] == 20 && kept.recipe[.exposure] == 0.5, "edited since: the edit stays")
        #expect(kept.snapshots.map(\.name) == ["Mine"])
    }

    @Test func `the photo open in the editor takes its edit there, and Undo Import takes it back there`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let open = LibraryIndexer.path(library.sandbox.url("2024/July/IMG_0006.CR3"))
        let calls = Mutex<[(recipe: EditRecipe, over: EditRecipe?, adding: [Snapshot], removing: Set<UUID>)]>([])
        let isOpen = Mutex(true)
        let editor = LightroomEditor(open: { open }) { path, recipe, over, adding, removing in
            guard path == open, isOpen.withLock({ $0 }) else { return .notOpen }
            calls.withLock { $0.append((recipe, over, adding, removing)) }
            return .changed(EditRecipe(), [], recipe)
        }
        let importer = library.importer(editor: editor)
        let outcome = try await importer.run(library.plan())
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3") == nil, "the editor saves it")
        let made = try #require(calls.withLock { $0.first })
        #expect(made.recipe.provenance?.photo == library.images["IMG_0006.CR3"] && made.over == nil)
        #expect(outcome.record.inEditor?.count == 1 && outcome.record.photos == 3)
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.CR3")?.recipe[.exposure] == 0.5)

        try await importer.undo()
        let undone = try #require(calls.withLock { $0.last })
        #expect(calls.withLock { $0.count } == 2 && undone.recipe == EditRecipe() && undone.over == made.recipe)

        isOpen.withLock { $0 = false }
        let closed = try await importer.run(library.plan())
        #expect(closed.record.inEditor == nil && closed.record.batches.count == 2, "closed meanwhile: its own batch")
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3")?.recipe.provenance != nil)
        try await importer.undo()
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3") == nil)
    }

    @Test func `EXIF's orientations are a mirror then clockwise quarter turns, and the size is the stored one`() {
        let turns = (1 ... 8).map { LightroomEditReading.orientation(exif: $0) }
        #expect(turns.map(\.quarterTurns) == [0, 0, 2, 2, 3, 1, 1, 3])
        #expect(turns.map(\.mirrored) == [false, true, false, true, true, false, true, false])
        var row = PhotoRecord(id: 1, folder: 1, name: "IMG_0001.CR3", size: 1, modified: Date())
        (row.width, row.height, row.orientation) = (4000, 6000, 6)
        var develop = LightroomCatalog.Develop(image: 1)
        (develop.fileWidth, develop.fileHeight) = (6000, 4000)
        let context = LightroomEditReading.context(row, develop, slotLooks: [:])
        #expect(context.size == PixelSize(width: 6000, height: 4000), "the index holds the size once oriented")
        #expect(context.catalogSize == PixelSize(width: 6000, height: 4000))
        #expect(context.cameraOrientation == ImageOrientation(quarterTurns: 1) && context.isRaw)
    }

    @Test func `the rotation most photos held the same way have is no turn, and another is a turn made in Lightroom`(
    ) async throws {
        func target(_ id: Int64, exif: Int) -> LightroomEditReading.Target {
            var row = PhotoRecord(id: id, folder: 1, name: "IMG_\(id).CR3", size: 1, modified: Date())
            row.orientation = exif
            return LightroomEditReading.Target(row: row, pairs: 0)
        }
        let exif: [Int64: Int] = [1: 1, 2: 1, 3: 1, 4: 6, 5: 6, 6: 6]
        let codes: [Int64: String] = [1: "AB", 2: "AB", 3: "DA", 4: "DA", 5: "DA", 6: "AB"]
        let targets = exif.mapValues { _ in 0 }.reduce(into: [Int64: LightroomEditReading.Target]()) { found, entry in
            found[entry.key] = target(entry.key, exif: exif[entry.key] ?? 1)
        }
        let unturned = LightroomEditReading.unturnedCodes(codes, targets: targets)
        #expect(unturned == [1: "AB", 6: "DA"], "whichever frame Lightroom's codes use")
        let given = (1 ... 6).map { (id: Int64) in
            var develop = LightroomCatalog.Develop(image: id)
            develop.orientation = codes[id]
            return LightroomEditReading.context(targets[id]!.row, develop, slotLooks: [:], unturned: unturned)
                .orientationCode
        }
        #expect(given == [nil, nil, "DA", nil, nil, "AB"], "only the turned photos keep their codes, to be reported")

        let sandbox = try await KeywordSandbox.make()
        defer { sandbox.remove() }
        let names = (1 ... 6).map { "Turns/IMG_000\($0).CR3" }
        for name in names {
            try sandbox.photo(name)
        }
        try await sandbox.indexAll()
        for (place, name) in names.enumerated() {
            let id = try await sandbox.id(name)
            try await sandbox.index.write { writer in
                var row = try #require(try writer.photo(id: id))
                row.orientation = exif[Int64(place + 1)]
                try writer.upsertPhotos([row])
            }
        }
        let folder = try TemporaryFolder()
        let maker = try LightroomCatalogMaker(at: folder.url.appending(path: "Turns.lrcat"))
        let turns = try maker.folder(maker.root(sandbox.root.path + "/"), "Turns/")
        for (place, name) in names.enumerated() {
            let image = try maker.photo(
                turns, (name as NSString).lastPathComponent, orientation: codes[Int64(place + 1)],
                size: (width: 6000, height: 4000),
            )
            try maker.develop(image, LightroomSettingsText.text(["Exposure2012": "0.5"]))
        }
        maker.close()
        let plan = try await LightroomPlan.make(
            LightroomCatalog.read(maker.url),
            index: sandbox.index,
            paths: sandbox.paths,
        )
        #expect(plan.report.edits.photos == 6 && plan.report.edits.turned == 2)
        let checked = plan.report.edits.reasons.first { $0.settings.contains("orientation") }
        #expect(checked?.photos == 2)
        #expect(plan.report.lines().contains { $0.contains("photos turned in Lightroom: 2, which come across as") })
        #expect(plan.edits.values.filter { $0.photo.recipe.provenance?.leftOut.contains("orientation") == true }
            .count == 2)
    }
}
