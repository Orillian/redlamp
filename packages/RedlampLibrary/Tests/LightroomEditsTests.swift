import Foundation
import RedlampDocument
import RedlampEngineAPI
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
}
