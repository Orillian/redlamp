import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes
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
        let copy = try maker.photo(
            june, "IMG_0001.CR3", rating: 4, pick: 1, label: "Green", master: first, copyName: "Copy 1",
        )
        let unnamed = try maker.photo(june, "IMG_0001.CR3", master: first, copyName: "")
        try maker.tag(copy, maker.keyword("Mono"))
        try maker.collection("Selects", photos: [copy])
        try maker.iptc(copy, caption: "Darker")
        try maker.xmp(copy, title: "The copy's title")
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
        try maker.develop(copy, LightroomSettingsText.text(["Exposure2012": "-1"]), digest: "D2")
        try maker.snapshot(copy, name: "Darkest", text: LightroomSettingsText.text(["Exposure2012": "-2"]))
        try maker.develop(unnamed, LightroomSettingsText.text(["Exposure2012": "0.75"]))
        maker.close()
        return Library(
            sandbox: sandbox, folder: folder, catalog: maker.url,
            images: [
                "IMG_0001.CR3": first, "IMG_0002.CR3": second, "IMG_0004.JPG": fourth, "IMG_0006.CR3": sixth,
                "Copy 1": copy, "unnamed": unnamed,
            ],
        )
    }

    @Test func `the report's Edits section says what each photo's edit becomes, before anything is written`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let plan = try await library.plan()
        let edits = plan.report.edits
        #expect(edits.photos == 4, "IMG_0001, IMG_0002, IMG_0006, and IMG_0004, which Redlamp has edited")
        #expect(edits.full + edits.approximated + edits.leftOut == 4 && edits.leftOut >= 2)
        #expect(edits.processes["Process 2010"] == 1 && edits.processes["Process 2012"] == 3)
        #expect(edits.snapshots == 2 && edits.historySteps == 3 && edits.pairs == 1, "IMG_0001's and its copy's")
        #expect(edits.kept == 1 && edits.keptPaths.first?.hasSuffix("2024/July/IMG_0004.JPG") == true)
        #expect(edits.unreadable == 1, "IMG_0003 is marked edited without settings")
        #expect(edits.virtualCopies == 2 && edits.copiesInCollections == 1 && edits.alreadyThere == 0)
        #expect(edits.newerXMP == 1, "IMG_0002's .xmp changed after the catalog was written")
        let lensBlur = try #require(edits.reasons.first { $0.settings.contains("LensBlur") })
        #expect(lensBlur.why.contains("OTH-03") && lensBlur.photos == 1)
        #expect(lensBlur.paths.first?.hasSuffix("2024/June/IMG_0002.CR3") == true)
        #expect(edits.reasons.contains { $0.why.contains("EDT-31") && $0.photos == 1 })
        #expect(!plan.report.left.contains { $0.what == "virtual copies" }, "they come across")
        #expect(plan.report.left.contains { $0.what.hasPrefix("steps of the edited photos' histories") })
        let lines = plan.report.lines()
        #expect(lines.contains("  edits, for the photos found:"))
        #expect(lines.contains { $0.contains("virtual copies: 2, which come across as versions of their photos") })
        #expect(lines.contains { $0.contains("edited already: 1, which keep their edit") && $0.contains("Lightroom") })
        let json = try JSONDecoder().decode(LightroomReport.self, from: plan.report.json())
        #expect(json.edits == edits)

        let raw = try await library.sandbox.id("2024/June/IMG_0001.CR3")
        let jpeg = try await library.sandbox.id("2024/June/IMG_0001.JPG")
        #expect(plan.edits.count == 4 && plan.edits[jpeg] == nil, "the raw takes the pair's edit")
        let made = try #require(plan.edits[raw]).made()
        #expect(made.recipe[.exposure] == 0.5)
        #expect(made.recipe.provenance?.source == .lightroomCatalog)
        #expect(made.recipe.provenance?.photo == library.images["IMG_0001.CR3"])
        #expect(made.recipe.provenance?.digest == "D1" && made.recipe.provenance?.path == library.catalog.path)
        #expect(made.snapshots.map(\.name) == ["Brighter"] && made.snapshots.first?.recipe[.exposure] == 1.5)

        let copies = try #require(plan.copies[raw])
        #expect(copies.map(\.image) == [library.images["Copy 1"], library.images["unnamed"]])
        #expect(copies.map(\.name) == ["Copy 1", ""] && plan.copies[jpeg] == nil)
        let version = copies[0].version()
        #expect(version.name == "Copy 1" && version.recipe[.exposure] == -1)
        #expect(version.recipe.provenance?.photo == library.images["Copy 1"] && version.recipe.provenance?
            .digest == "D2")
        #expect(version.snapshots.map(\.name) == ["Darkest"] && version.snapshots.first?.recipe[.exposure] == -2)
        let own = try #require(version.metadata)
        #expect(own.rating == 4 && own.flag == .pick && own.label == .green, "the copy's own fields")
        #expect(own.keywords == ["Mono"] && own.collections == ["Selects"])
        #expect(own.title == "The copy's title" && own.caption == "Darker")
        #expect(copies[1].version().metadata == nil && copies[1].version().recipe[.exposure] == 0.75)
    }

    @Test func `the import writes each photo's edit and snapshots with its fields, and Undo takes them back`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let importer = library.importer()
        let plan = try await library.plan()
        try library.sandbox.sidecar("2024/June/IMG_0002.CR3", PhotoMetadata(rating: 2))
        let outcome = try await importer.run(plan)
        #expect(outcome.record.batches.map(\.journal) == [.keywords, .metadata], "Mono, the copy's alone, is kept")
        #expect(outcome.written == 4, "IMG_0001, IMG_0006, and IMG_0002 and IMG_0004, which keep their edits")
        let raw = try #require(library.sandbox.sidecar("2024/June/IMG_0001.CR3"))
        #expect(raw.recipe[.exposure] == 0.5 && raw.recipe.provenance?.digest == "D1")
        #expect(raw.snapshots.map(\.name) == ["Brighter"] && raw.snapshots.first?.recipe[.exposure] == 1.5)
        #expect(raw.versions.map(\.name) == ["Copy 1", "Copy 2"], "an unnamed copy named as Create Version would")
        #expect(raw.versions.map { $0.recipe[.exposure] } == [-1, 0.75])
        #expect(raw.versions.first?.snapshots.map(\.name) == ["Darkest"] && raw.versions.first?.metadata?.rating == 4)
        #expect(raw.metadata?.rating ?? 0 == 0, "the photo keeps its own fields")
        #expect(try await library.edited("2024/June/IMG_0001.CR3"))
        #expect(try await library.edited("2024/July/IMG_0006.CR3"))
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.JPG") == nil, "the raw takes the pair's edit")
        let meanwhile = try #require(library.sandbox.sidecar("2024/June/IMG_0002.CR3"))
        #expect(meanwhile.recipe[.exposure] == 0.35 && meanwhile.recipe.provenance == nil, "edited since the plan")
        #expect(meanwhile.versions.map(\.name) == [LightroomImport.versionName])
        #expect(meanwhile.versions.first?.recipe[.exposure] == 0.25 && meanwhile.versions.first?.metadata?.rating == 2)
        let kept = try #require(library.sandbox.sidecar("2024/July/IMG_0004.JPG"))
        #expect(kept.recipe.provenance == nil && kept.recipe[.exposure] == 0.35, "Redlamp's edit stays")
        let lightroom = try #require(kept.versions.first)
        #expect(kept.versions.count == 1 && lightroom.name == "Lightroom Classic" && lightroom.recipe[.exposure] == 1)
        #expect(lightroom.recipe.provenance?.photo == library.images["IMG_0004.JPG"])
        #expect(lightroom.metadata == PhotoMetadata(rating: 3), "the photo's metadata, as a new virtual copy takes it")

        try await importer.undo()
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.CR3") == nil, "nothing is left in it")
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3") == nil)
        #expect(try await !library.edited("2024/June/IMG_0001.CR3"))
        #expect(library.sandbox.sidecar("2024/June/IMG_0002.CR3")?.recipe[.exposure] == 0.35)
        #expect(library.sandbox.sidecar("2024/June/IMG_0002.CR3")?.versions.isEmpty == true)
        let undone = try #require(library.sandbox.sidecar("2024/July/IMG_0004.JPG"))
        #expect(undone.recipe[.exposure] == 0.35 && undone.versions.isEmpty && undone.metadata?.rating == 3)
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
        #expect(kept.versions.isEmpty, "the versions it added, as it left them, go")
    }

    @Test func `Undo takes off only the versions the import added, keeping one changed since and the photo's own`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let path = "2024/July/IMG_0004.JPG"
        let store = SidecarStore()
        var before = try #require(library.sandbox.sidecar(path))
        let added = before.addVersion(of: nil, named: "Mine")
        let mine = try #require(added)
        try store.save(before, for: library.sandbox.url(path))
        try await library.sandbox.indexAll()
        before = try #require(library.sandbox.sidecar(path))
        let importer = library.importer()
        try await importer.run(library.plan())
        var imported = try #require(library.sandbox.sidecar(path))
        #expect(imported.versions.map(\.name) == ["Mine", "Lightroom Classic"], "after those it has")
        #expect(imported.versions.first == before.versions.first, "the photo's own version is left as it was")

        try await importer.undo()
        #expect(library.sandbox.sidecar(path)?.versions.map(\.id) == [mine.id])

        try await importer.run(library.plan())
        imported = try #require(library.sandbox.sidecar(path))
        imported.versions[1].name = "Lightroom, renamed"
        try store.save(imported, for: library.sandbox.url(path))
        try await importer.undo()
        let kept = try #require(library.sandbox.sidecar(path))
        #expect(kept.versions.map(\.name) == ["Mine", "Lightroom, renamed"], "changed since: the version stays")
        #expect(kept.recipe[.exposure] == 0.35)
    }

    @Test func `an edit brought from the catalog before is left as it is, and the report counts it as already there`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let importer = library.importer()
        try await importer.run(library.plan())
        let names = ["2024/June/IMG_0001.CR3", "2024/June/IMG_0002.CR3", "2024/July/IMG_0004.JPG"]
        let first = names.map { library.sandbox.sidecar($0) }
        let again = try await library.plan()
        let edits = again.report.edits
        #expect(edits.alreadyThere == 6, "IMG_0001's edit and its two copies, IMG_0002's, IMG_0004's and IMG_0006's")
        #expect(edits.photos == 0 && edits.virtualCopies == 0 && edits.kept == 0 && again.copies.isEmpty)
        #expect(again.report.lines().contains { $0.contains("edits brought from this catalog before: 6") })
        try await importer.run(again)
        #expect(names.map { library.sandbox.sidecar($0)?.versions } == first.map { $0?.versions })
        #expect(names.map { library.sandbox.sidecar($0)?.recipe } == first.map { $0?.recipe })
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
        #expect(outcome.record.inEditor?.count == 1 && outcome.record.photos == 4)
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.CR3")?.recipe[.exposure] == 0.5)

        try await importer.undo()
        let undone = try #require(calls.withLock { $0.last })
        #expect(calls.withLock { $0.count } == 2 && undone.recipe == EditRecipe() && undone.over == made.recipe)

        isOpen.withLock { $0 = false }
        let closed = try await importer.run(library.plan())
        #expect(closed.record.inEditor == nil, "closed meanwhile")
        #expect(closed.record.batches.map(\.journal) == [.keywords, .metadata, .metadata], "its own batch")
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3")?.recipe.provenance != nil)
        try await importer.undo()
        #expect(library.sandbox.sidecar("2024/July/IMG_0006.CR3") == nil)
    }

    @Test func `the photo open in an editor with versions takes them there, and Undo Import takes them back there`(
    ) async throws {
        let library = try await Self.library()
        defer { library.remove() }
        let open = LibraryIndexer.path(library.sandbox.url("2024/June/IMG_0001.CR3"))
        let given = Mutex<[(adding: [PhotoVersion], removing: [PhotoVersion])]>([])
        let held = Mutex<[PhotoVersion]>([])
        let editor = LightroomEditor(open: { open }) { path, recipe, _, _, _ in
            path == open ? .changed(EditRecipe(), [], recipe) : .notOpen
        } versions: { path, adding, removing in
            guard path == open else { return .notOpen }
            given.withLock { $0.append((adding, removing)) }
            return held.withLock { versions in
                let had = versions
                versions = versions.filter { !removing.contains($0) } + adding
                return .changed(had, versions)
            }
        }
        let importer = library.importer(editor: editor)
        let outcome = try await importer.run(library.plan())
        let added = try #require(given.withLock { $0.first?.adding })
        #expect(added.map(\.name) == ["Copy 1", "Copy 2"] && added.first?.metadata?.rating == 4)
        #expect(library.sandbox.sidecar("2024/June/IMG_0001.CR3") == nil, "the editor saves them")
        #expect(outcome.record.inEditor?.first?.after["versions"]?.arrayValue?.count == 2)

        try await importer.undo()
        #expect(given.withLock { $0.last?.removing.map(\.name) } == ["Copy 1", "Copy 2"])
        #expect(held.withLock { $0.isEmpty })

        let edited = LibraryIndexer.path(library.sandbox.url("2024/July/IMG_0004.JPG"))
        let photographers = LightroomEditor(open: { edited }) { _, _, _, _, _ in .left } versions: { path, adding, _ in
            guard path == edited else { return .notOpen }
            given.withLock { $0.append((adding, [])) }
            return .changed([], adding)
        }
        try await library.importer(editor: photographers).run(library.plan())
        let lightroom = try #require(given.withLock { $0.last?.adding.first })
        #expect(lightroom.name == "Lightroom Classic" && lightroom.recipe[.exposure] == 1)
        #expect(lightroom.metadata == PhotoMetadata(rating: 3), "the photo's, read from its sidecar")
        #expect(library.sandbox.sidecar("2024/July/IMG_0004.JPG")?.versions.isEmpty == true)
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

    @Test func `a raw names the photographer's Adobe profile where its camera's list has it, each camera asked once`(
    ) async throws {
        let sandbox = try await KeywordSandbox.make()
        defer { sandbox.remove() }
        let names = ["IMG_0001.CR3", "IMG_0002.CR3", "DSC_0001.NEF", "IMG_0003.JPG"]
        for name in names {
            try sandbox.photo("Shoot/\(name)")
        }
        try await sandbox.indexAll()
        var ids: [String: Int64] = [:]
        for name in names {
            ids[name] = try await sandbox.id("Shoot/\(name)")
        }
        try await sandbox.index.write { [ids] writer in
            let r5 = try writer.cameraID(for: "Canon EOS R5", make: "Canon", model: "Canon EOS R5")
            let z8 = try writer.cameraID(for: "Nikon Z 8", make: "Nikon", model: "NIKON Z 8")
            let iphone = try writer.cameraID(for: "Apple iPhone 15 Pro", make: "Apple", model: "iPhone 15 Pro")
            for (name, camera) in [
                ("IMG_0001.CR3", r5), ("IMG_0002.CR3", r5), ("DSC_0001.NEF", z8), ("IMG_0003.JPG", iphone),
            ] {
                let update = try writer.database.cached("UPDATE photos SET camera = ? WHERE id = ?")
                try update.bind(camera, at: 1)
                try update.bind(ids[name], at: 2)
                try update.run()
            }
        }
        let folder = try TemporaryFolder()
        let maker = try LightroomCatalogMaker(at: folder.url.appending(path: "Lightroom Catalog.lrcat"))
        let shoot = try maker.folder(maker.root(sandbox.root.path + "/"), "Shoot/")
        for name in names {
            let image = try maker.photo(shoot, name, size: (width: 6000, height: 4000))
            try maker.develop(image, LightroomSettingsText.text([
                "CameraProfile": "\"Adobe Standard\"", "Look": "{}", "Exposure2012": "0.5",
            ]))
        }
        maker.close()
        let standard = CameraProfileLook(
            reference: BaseLookReference(
                id: BaseLookReference.adobeIDPrefix + "0123456789abcdef",
                name: "Adobe Standard",
            ),
            group: .adobeRaw, summary: "Adobe Standard, for the test",
        )
        let asked = Mutex<[String]>([])
        let plan = try await LightroomPlan.make(
            LightroomCatalog.read(maker.url), index: sandbox.index, paths: sandbox.paths,
            adobeProfiles: { make, model in
                asked.withLock { $0.append("\(make) \(model)") }
                return make == "Canon" ? [standard] : []
            },
        )

        #expect(asked.withLock { $0 }.sorted() == ["Canon Canon EOS R5", "Nikon NIKON Z 8"], "a JPEG's isn't asked")
        let edits = plan.report.edits
        #expect(edits.photos == 4 && edits.ownProfiles == 2 && edits.standIns == ["Adobe Standard": 1])
        let lines = plan.report.lines()
        #expect(lines
            .contains("      raws in the Adobe profile Lightroom used, the photographer's own copy on this Mac: 2"))
        #expect(lines.contains(
            "      raws whose Adobe profile isn't on this Mac, Redlamp's look standing in: 1 (Adobe Standard 1)",
        ))
        #expect(try JSONDecoder().decode(LightroomReport.self, from: plan.report.json()).edits == edits)

        let outcome = try await LightroomImport(index: sandbox.index, paths: sandbox.paths).run(plan)
        #expect(outcome.written == 4)
        for name in ["IMG_0001.CR3", "IMG_0002.CR3"] {
            #expect(sandbox.sidecar("Shoot/\(name)")?.recipe.baseLook == standard.reference, "\(name)")
        }
        let standIn = try #require(sandbox.sidecar("Shoot/DSC_0001.NEF")).recipe
        #expect(standIn.baseLook.name == AdobeProfileStandIn.look(forProfileNamed: "Adobe Standard").name)
        #expect(!standIn.baseLook.isAdobeProfile && standIn[.exposure] == 0.5)
        #expect(sandbox.sidecar("Shoot/IMG_0003.JPG")?.recipe.baseLook.isAdobeProfile == false)
    }

    @Test func `a Fujifilm simulation takes the look filling its slot on this Mac, else Redlamp's film look`(
    ) async throws {
        let sandbox = try await KeywordSandbox.make()
        defer { sandbox.remove() }
        let profiles = [("DSCF0001.RAF", "Camera CLASSIC CHROME"), ("DSCF0002.RAF", "Camera Velvia/Vivid")]
        for (name, _) in profiles {
            try sandbox.photo("Shoot/\(name)")
        }
        try await sandbox.indexAll()
        let folder = try TemporaryFolder()
        let maker = try LightroomCatalogMaker(at: folder.url.appending(path: "Lightroom Catalog.lrcat"))
        let shoot = try maker.folder(maker.root(sandbox.root.path + "/"), "Shoot/")
        for (name, profile) in profiles {
            let image = try maker.photo(shoot, name, size: (width: 6240, height: 4160))
            try maker.develop(image, LightroomSettingsText.text([
                "CameraProfile": "\"\(profile)\"", "Look": "{}", "Exposure2012": "0.5",
            ]))
        }
        maker.close()
        let lut = BaseLookReference(id: BaseLookReference.makerIDPrefix + "chrome", name: "Classic Chrome LUT")
        let plan = try await LightroomPlan.make(
            LightroomCatalog.read(maker.url), index: sandbox.index, paths: sandbox.paths, slotLooks: [.chrome: lut],
        )

        let chrome = try #require(try await plan.edits[sandbox.id("Shoot/DSCF0001.RAF")]).photo.recipe
        let velvia = try #require(try await plan.edits[sandbox.id("Shoot/DSCF0002.RAF")]).photo.recipe
        #expect(chrome.baseLook == lut)
        #expect(velvia.baseLook == FilmSlot.vividSlide.baseLook)
        for recipe in [chrome, velvia] {
            #expect(recipe.provenance?.approximated.contains("CameraProfile") == true)
        }
        let outcome = try await LightroomImport(index: sandbox.index, paths: sandbox.paths).run(plan)
        #expect(outcome.written == 2)
        #expect(sandbox.sidecar("Shoot/DSCF0001.RAF")?.recipe.baseLook == lut)
        #expect(sandbox.sidecar("Shoot/DSCF0002.RAF")?.recipe.baseLook == FilmSlot.vividSlide.baseLook)
    }
}
