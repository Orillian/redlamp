import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// A Lightroom Classic catalog's report and import at size (LIB-29): a catalog of 100,000 photos reported in
/// seconds and imported in parts with progress. The full size runs with `REDLAMP_LIGHTROOM_BENCH=1`
/// (`TEST_RUNNER_REDLAMP_LIGHTROOM_BENCH=1` through `xcodebuild`), `REDLAMP_LIGHTROOM_BENCH_PHOTOS` setting
/// how many; every run measures 5,000.
struct LightroomBenchTests {
    /// The library's photos as rows of an index, in folders of 1,000 on disk where their sidecars go, and a
    /// catalog of them: a third rated, a tenth picked and a twentieth rejected, a fifth labelled, three keywords
    /// each from a list of 2,000 in a hierarchy, a fifth in one of 50 collections in 5 sets, 10 smart
    /// collections, captions on a third, and XMP for every photo, Develop settings in it and a title in a fifth.
    struct Library {
        let photos: TemporaryFolder
        let library: TemporaryFolder
        let index: LibraryIndex
        let catalog: URL
        /// With `edits`, the size of each photo's Develop settings, in bytes.
        var settingsSizes: [Int] = []

        var paths: LibraryPaths {
            LibraryPaths(root: library.url)
        }
    }

    /// With `edits`, each photo has Develop settings as `settings` writes them, a rotation and a size, three
    /// history steps, a tenth two snapshots and a twentieth a virtual copy with settings of its own; the index
    /// has the files' EXIF orientations.
    static func library(photos count: Int, edits: Bool = false) async throws -> Library {
        let photos = try TemporaryFolder()
        let library = try TemporaryFolder()
        let index = try await LibraryIndex.open(at: library.url.appending(path: "Index.sqlite"))
        let root = LibraryIndexer.path(photos.url)
        let folders = (count + 999) / 1000
        for folder in 0 ..< folders {
            try FileManager.default.createDirectory(
                at: photos.url.appending(path: String(format: "Shoot %03d", folder)), withIntermediateDirectories: true,
            )
        }
        try await index.write { writer in
            let volume = try writer.upsertVolume(VolumeRecord(uuid: "BENCH-VOLUME", name: "Bench", kind: .ssd))
            let rootID = try writer.upsertRoot(RootRecord(volume: volume, path: root))
            let top = try writer.upsertFolder(FolderRecord(root: rootID, parent: nil, path: root))
            for folder in 0 ..< folders {
                let id = try writer.upsertFolder(FolderRecord(
                    root: rootID, parent: top, path: root + String(format: "/Shoot %03d", folder),
                ))
                let names = (folder * 1000 ..< min((folder + 1) * 1000, count))
                _ = try writer.upsertPhotos(names.map { number in
                    PhotoRecord(
                        folder: id, name: String(format: "IMG_%06d.CR3", number), size: 1000,
                        orientation: edits ? (number % 9 == 0 ? 6 : 1) : nil,
                    )
                })
            }
        }

        let maker = try LightroomCatalogMaker(at: library.url.appending(path: "Lightroom Catalog.lrcat"))
        var settingsSizes: [Int] = []
        try maker.transaction {
            let top = try maker.root(root + "/")
            var keywords: [Int64] = []
            var parents: [Int64] = []
            for group in 0 ..< 40 {
                let parent = try maker.keyword("Group \(group)", synonyms: group % 4 == 0 ? ["G\(group)"] : [])
                parents.append(parent)
                for child in 0 ..< 49 {
                    try keywords.append(maker.keyword(
                        "Keyword \(group)-\(child)",
                        parent: parent,
                        includeOnExport: child % 10 != 0,
                    ))
                }
            }
            var members: [[Int64]] = Array(repeating: [], count: 50)
            var folderIDs: [Int64] = []
            for folder in 0 ..< folders {
                try folderIDs.append(maker.folder(top, String(format: "Shoot %03d/", folder)))
            }
            for number in 0 ..< count {
                let turned = number % 9 == 0
                var size: (width: Int, height: Int)?
                if edits {
                    size = turned ? (width: 4000, height: 6000) : (width: 6000, height: 4000)
                }
                let photo = try maker.photo(
                    folderIDs[number / 1000], String(format: "IMG_%06d.CR3", number),
                    rating: number % 3 == 0 ? number % 5 + 1 : nil,
                    pick: number % 10 == 0 ? 1 : number % 20 == 1 ? -1 : 0,
                    label: number % 5 == 0 ? ["Red", "Yellow", "Green", "Blue", "Purple"][number / 5 % 5] : "",
                    orientation: edits ? (turned ? "BC" : "AB") : nil, size: size,
                )
                if edits {
                    try settingsSizes.append(Self.edit(photo, number, folder: folderIDs[number / 1000], in: maker))
                }
                for step in 0 ..< 3 {
                    try maker.tag(photo, keywords[(number * 7 + step * 131) % keywords.count])
                }
                if number % 5 == 0 {
                    members[number / 5 % 50].append(photo)
                }
                if number % 3 == 0 {
                    try maker.iptc(photo, caption: "Caption of photo \(number)")
                }
                try maker.xmp(photo, title: number % 5 == 0 ? "Title \(number)" : nil, settings: 150)
            }
            for set in 0 ..< 5 {
                let parent = try maker.collection("Set \(set)", kind: LightroomCatalogMaker.setKind)
                for collection in 0 ..< 10 {
                    try maker.collection(
                        "Collection \(set)-\(collection)",
                        parent: parent,
                        photos: members[set * 10 + collection],
                    )
                }
            }
            for rating in 0 ..< 10 {
                try maker.collection("Smart \(rating)", kind: LightroomCatalogMaker.smartKind, rules: """
                s = { { criteria = "rating", operation = ">=", value = \(rating % 5 + 1), value2 = 0, },
                      { criteria = "keywords", operation = "any", value = "Keyword \(rating)-1", value2 = "", },
                      combine = "intersect", }
                """)
            }
        }
        maker.close()
        return Library(photos: photos, library: library, index: index, catalog: maker.url, settingsSizes: settingsSizes)
    }

    /// Photo `number`'s edit in the catalog: its settings, three history steps, two snapshots on a tenth and a
    /// virtual copy on a twentieth. The size of its settings, in bytes.
    private static func edit(
        _ photo: Int64,
        _ number: Int,
        folder: Int64,
        in maker: LightroomCatalogMaker,
    ) throws -> Int {
        let text = settings(number)
        try maker.develop(photo, text)
        try maker.history(photo, steps: 3)
        if number % 10 == 4 {
            try maker.snapshot(photo, name: "Snapshot 1", text: text)
            try maker.snapshot(photo, name: "Snapshot 2", text: settings(number + 3))
        }
        if number % 20 == 7 {
            let copy = try maker.photo(
                folder, String(format: "IMG_%06d.CR3", number), master: photo, copyName: "Copy 1", orientation: "CD",
            )
            try maker.develop(copy, settings(number + 1))
        }
        return text.utf8.count
    }

    /// Develop settings for the bench's photo `number`, 3.5 to 5.5 KB as a real catalog's are: a third with the
    /// exposure changed, a tenth in Process 2012 and a fiftieth in Process 2010, a seventh with a camera-matching
    /// profile, half with a lens profile and Upright's solved transforms, a tenth with two to four masks of one to
    /// three components, and a twentieth with spots.
    static func settings(_ number: Int) -> String {
        var changes: [String: String] = [:]
        var fields: [String] = []
        if number % 3 == 0 {
            changes["Exposure2012"] = String(format: "%.2f", Double(number % 41 - 20) / 10)
        }
        if number % 10 == 1 {
            changes["ProcessVersion"] = #""6.7""#
        } else if number % 50 == 2 {
            changes["ProcessVersion"] = #""5.0""#
        }
        if number % 7 == 0 {
            changes["CameraProfile"] = #""Camera Standard""#
        }
        if number % 50 == 3 {
            changes["PerspectiveUpright"] = "\(number % 6)"
        }
        if number % 2 == 0 {
            fields += lens
        }
        if number % 10 == 0 {
            let corrections = (0 ..< 2 + number % 3).map { place in
                LightroomSettingsText.correction(
                    (0 ..< 1 + place % 3).map { component in
                        LightroomSettingsText.mask(
                            maskKinds[(number + place + component) % maskKinds.count],
                            "ZeroX = 0.5, ZeroY = 0.2, FullX = 0.5, FullY = 0.7, Feather = 0.5",
                        )
                    },
                    "LocalExposure2012 = \(Double(place) / 4), LocalContrast2012 = 10, LocalClarity2012 = 0",
                )
            }
            fields.append(LightroomSettingsText.masks(corrections))
        }
        if number % 20 == 5 {
            let spot = LightroomSettingsText.spot(
                "heal", masks: [LightroomSettingsText.mask("Mask/Ellipse", "X = 0.3, Y = 0.4, SizeX = 0.02")],
            )
            fields.append("RetouchAreas = { \(spot), \(spot) }")
        }
        return LightroomSettingsText.text(changes, fields)
    }

    private static let maskKinds = ["Mask/Gradient", "Mask/CircularGradient", "Mask/Paint", "Mask/Image"]

    private static let lens = [
        #"LensProfileName = "Adobe (Bench 24-70mm f/2.8)""#,
        #"LensProfileFilename = "Bench Camera (Bench 24-70mm f2.8) - RAW.lcp""#,
        #"LensProfileDigest = "0123456789ABCDEF0123456789ABCDEF""#, "LensProfileDistortionScale = 100",
        "LensProfileVignettingScale = 100", "LensProfileChromaticAberrationScale = 100",
        "LensProfileIsEmbedded = false", #"UprightDependentDigest = "FEDCBA9876543210FEDCBA9876543210""#,
    ] + (0 ..< 6).map { place in
        "UprightTransform_\(place) = \"{1.000000, 0.000000, 0.000000, 0.000000, 1.000000, 0.000000, "
            + "0.000000, 0.000000, 1.000000}\""
    }

    struct Measured {
        var read: Duration
        var plan: Duration
        var run: Duration
        var undo: Duration
        var parts: Int
        var progress: Int
    }

    static func measure(photos count: Int) async throws -> Measured {
        let library = try await Self.library(photos: count)
        defer { library.index.closeAndWait() }
        let clock = ContinuousClock()
        var started = clock.now
        let catalog = try LightroomCatalog.read(library.catalog)
        let read = clock.now - started
        started = clock.now
        let plan = try await LightroomPlan.make(catalog, index: library.index, paths: library.paths)
        let planned = clock.now - started
        #expect(plan.report.found == count && plan.report.notFound == 0)
        #expect(plan.report.fields.ratings == (count + 2) / 3)
        #expect(plan.report.smartMapped.count == 10 && plan.report.collections == 50)
        #expect(plan.report.keywords == 40 * 50)

        let progress = ProgressLog()
        let importer = LightroomImport(index: library.index, paths: library.paths)
        started = clock.now
        let outcome = try await importer.run(plan) { progress.add($0) }
        let ran = clock.now - started
        #expect(outcome.record.photos == count && outcome.skipped.isEmpty)
        #expect(progress.last?.done == count)
        started = clock.now
        try await importer.undo()
        let undone = clock.now - started
        let parts = (count + importer.partSize - 1) / importer.partSize
        print("LIGHTROOM-BENCH \(count) photos: read \(read), report \(planned), import \(ran) in \(parts) parts "
            + "(\(outcome.written) sidecars written, \(progress.count) progress reports), undo \(undone)")
        return Measured(read: read, plan: planned, run: ran, undo: undone, parts: parts, progress: progress.count)
    }

    @Test(.measuresSpeed)
    func `a catalog of 5,000 photos is reported in under a second and imported with progress`() async throws {
        let measured = try await Self.measure(photos: 5000)
        #expect(measured.read + measured.plan < .seconds(1))
        #expect(measured.progress >= measured.parts)
    }

    /// The census of a bench library's catalog of `count` photos with edits (EDT-23), paired with its index, timed.
    static func census(photos count: Int) async throws -> Duration {
        let library = try await Self.library(photos: count, edits: true)
        defer { library.index.closeAndWait() }
        let clock = ContinuousClock()
        let started = clock.now
        let census = try await LightroomCensus.make(library.catalog, index: library.index)
        let took = clock.now - started
        let copies = (count + 12) / 20
        #expect(census.photos == count && census.virtualCopies == copies && census.unreadable == 0)
        #expect(census.withSettings == count + copies && census.found == count + copies)
        #expect(census.historySteps == 3 * count && census.snapshots == 2 * ((count + 5) / 10))
        #expect(census.photosWithMasks == (count + 9) / 10)
        let sizes = library.settingsSizes
        let cores = ProcessInfo.processInfo.activeProcessorCount
        print("LIGHTROOM-CENSUS-BENCH \(count) photos and \(copies) virtual copies, their settings "
            + "\(sizes.reduce(0, +) / max(sizes.count, 1)) bytes on average (\(sizes.min() ?? 0) to "
            + "\(sizes.max() ?? 0)): census in \(took) on \(cores) cores; the report with edits has about 4.9 s "
            + "for 100,000 photos")
        return took
    }

    @Test(.measuresSpeed)
    func `the census of a catalog of 5,000 photos' edits takes under a second`() async throws {
        let took = try await Self.census(photos: 5000)
        #expect(took < .seconds(1))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH"] == "1"), .measuresSpeed)
    func `the census of a catalog of 100,000 photos' edits is within the report's budget`() async throws {
        let photos = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH_PHOTOS"].flatMap { Int($0) }
            ?? 100_000
        let took = try await Self.census(photos: photos)
        #expect(took < .milliseconds(4900 * photos / 100_000))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH"] == "1"), .measuresSpeed)
    func `a catalog of 100,000 photos is reported in seconds and imported in parts with progress`() async throws {
        let photos = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH_PHOTOS"].flatMap { Int($0) }
            ?? 100_000
        let measured = try await Self.measure(photos: photos)
        #expect(measured.read + measured.plan < .seconds(10))
        #expect(measured.parts == (photos + LightroomImport.standardPartSize - 1) / LightroomImport.standardPartSize)
    }
}
