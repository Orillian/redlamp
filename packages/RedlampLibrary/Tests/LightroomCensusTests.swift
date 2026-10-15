import Foundation
import Testing
@testable import RedlampLibrary

/// The census of a Lightroom Classic catalog's edits (EDT-23): what its photos' and virtual copies' settings
/// use, counted so it can be shared, naming no photo, path, keyword or value.
struct LightroomCensusTests {
    typealias Lua = LightroomSettingsText

    /// A catalog of a wedding: seven photos and two virtual copies with every kind of thing the census counts,
    /// in a folder on disk, and the library's index of five of the photos with their files' EXIF orientations.
    struct Wedding {
        let photos: TemporaryFolder
        let library: TemporaryFolder
        let catalog: URL
        let index: LibraryIndex
    }

    static let ellipse = Lua.mask("Mask/Ellipse", "X = 0.3, Y = 0.4, SizeX = 0.02, SizeY = 0.02")
    static let paint = Lua.mask("Mask/Paint", #"Dabs = { "d 0.5 0.5" }"#)

    /// Process 11's masks (a gradient; a subject with a brush), and three spots.
    static func first() -> String {
        let gradient = Lua.correction(
            [Lua.mask("Mask/Gradient", "ZeroX = 0.5, ZeroY = 0.1, FullX = 0.5, FullY = 0.6")],
            #"LocalExposure2012 = 0.5, CorrectionName = "Jane's face""#,
        )
        let subject = Lua.correction(
            [Lua.mask("Mask/Image", "MaskSubType = 1"), Lua.mask("Mask/Paint", "Flow = 0.8, Radius = 0.05")],
            #"LocalExposure2012 = -0.4, CorrectionName = "Sky over the Smiths' house""#,
        )
        let heal = Lua.spot("heal", method: "gentle", masks: [ellipse])
        let clone = Lua.spot("clone", masks: [ellipse])
        return Lua.text(["Exposure2012": "0.35"], [
            Lua.masks([gradient, subject]), "RetouchAreas = { \(heal), \(heal), \(clone) }",
        ])
    }

    /// Upright's Auto, a camera-matching profile, a radial gradient with a brush inside it and a range mask,
    /// and a spot.
    static func second() -> String {
        let radial = Lua.mask("Mask/CircularGradient", #"Masks = { What = "Mask/Paint", MaskValue = 1 }"#)
        let range = Lua.mask("Mask/RangeMask", "CorrectionRangeMask = { Type = 2, LumMin = 0.2, LumMax = 0.8 }")
        let spot = Lua.spot("heal", method: "contentAware", masks: [paint, paint])
        let changes = ["PerspectiveUpright": "1", "CameraProfile": #""Camera Standard""#, "Look": "{}"]
        return Lua.text(changes, [
            Lua.masks([Lua.correction([radial, range], "LocalExposure2012 = 1.23")]), "RetouchAreas = { \(spot) }",
        ])
    }

    /// Process 2012, Upright's Guided, and Lightroom 10's masks: two gradients, one with a range mask, and a brush.
    static func third() -> String {
        let plain = Lua.correction([Lua.mask("Mask/Gradient")], "LocalExposure2012 = 0.3")
        let ranged = Lua.correction(
            [Lua.mask("Mask/Gradient")], "LocalExposure2012 = 0.3, CorrectionRangeMask = { Type = 1, LumMax = 0.5 }",
        )
        let brush = Lua.correction([paint, paint], "LocalExposure2012 = 0")
        return Lua.text(["ProcessVersion": #""6.7""#, "PerspectiveUpright": "5"], [
            "GradientBasedCorrections = { \(plain), \(ranged) }", "PaintBasedCorrections = { \(brush) }",
        ])
    }

    /// Process 2010, with its own sliders and spots, a radial gradient, and a profile and look of the
    /// photographer's own.
    static func fourth() -> String {
        let spots = """
        RetouchInfo = { "centerX = 0.5, centerY = 0.5, radius = 0.01, sourceState = sourceSetExplicitly, sourceX = 0.4, \
        sourceY = 0.5, spotType = heal", "centerX = 0.2, centerY = 0.7, radius = 0.02, \
        sourceState = sourceAutoComputed, sourceX = 0.1, sourceY = 0.7, spotType = clone" }
        """
        let radial = Lua.correction([Lua.mask("Mask/CircularGradient")], "LocalExposure2012 = 0.7")
        let changes = [
            "ProcessVersion": #""5.0""#, "CameraProfile": #""Smith Wedding Look""#,
            "Look": #"{ Name = "Client X Look", Amount = 1 }"#, "Exposure": "0", "Brightness": "50", "Contrast": "25",
        ]
        return Lua.text(changes, [spots, "CircularGradientBasedCorrections = { \(radial) }"])
    }

    /// Seventeen masks of four gradients each: more than an edit of Redlamp's holds.
    static func seventh() -> String {
        let crowded = (0 ..< 17).map { _ in
            Lua.correction(Array(repeating: Lua.mask("Mask/Gradient"), count: 4), "LocalExposure2012 = 0.25")
        }
        return Lua.text([:], [Lua.masks(crowded)])
    }

    static func wedding() async throws -> Wedding {
        let photos = try TemporaryFolder()
        let library = try TemporaryFolder()
        let root = LibraryIndexer.path(photos.url)
        let maker = try LightroomCatalogMaker(at: library.url.appending(path: "Lightroom Catalog.lrcat"))
        let folder = try maker.folder(maker.root(root + "/"), "2024/Client Smith/")
        func photo(_ number: Int, _ orientation: String?, size: (width: Int, height: Int)? = nil) throws -> Int64 {
            try maker.photo(
                folder, String(format: "Smith_Wedding_%04d.CR3", number), orientation: orientation, size: size,
            )
        }
        let first = try photo(1, "AB", size: (6000, 4000))
        try maker.develop(first, Self.first(), processVersion: "11.0")
        try maker.snapshot(first, name: "Before retouching", text: Lua.text())
        try maker.snapshot(first, name: "Smith album", text: Lua.text(["Exposure2012": "0.35"]))
        try maker.history(first, steps: 5)
        try maker.tag(first, maker.keyword("Jane Smith", type: "person"))
        let second = try photo(2, "BC", size: (4000, 6000))
        try maker.develop(second, Self.second())
        try maker.history(second, steps: 3)
        let third = try photo(3, "AB", size: (6000, 4000))
        try maker.develop(third, Self.third())
        try maker.develop(photo(4, "DA", size: (4000, 6000)), Self.fourth())
        try maker.develop(photo(5, nil), "s = { Exposure2012 = ")
        _ = try photo(6, "AB")
        try maker.develop(photo(7, nil), Self.seventh())
        let copy = try maker.photo(
            folder, "Smith_Wedding_0001.CR3", master: first, copyName: "Copy 1", orientation: "CD",
        )
        try maker.develop(copy, Lua.text(["Exposure2012": "-0.55"]))
        try maker.snapshot(copy, name: "Black and white", text: Lua.text())
        try maker.history(copy, steps: 1)
        let alternate = try maker.photo(
            folder, "Smith_Wedding_0003.CR3", master: third, copyName: "Smith Alternate", orientation: "AB",
        )
        try maker.develop(alternate, Lua.text(["ProcessVersion": #""6.7""#]))
        maker.close()

        let index = try await LibraryIndex.open(at: library.url.appending(path: "Index.sqlite"))
        try await index.write { writer in
            let volume = try writer.upsertVolume(VolumeRecord(uuid: "CENSUS-VOLUME", name: "Photos", kind: .ssd))
            let rootID = try writer.upsertRoot(RootRecord(volume: volume, path: root))
            let top = try writer.upsertFolder(FolderRecord(root: rootID, parent: nil, path: root))
            let shoot = try writer.upsertFolder(FolderRecord(
                root: rootID, parent: top, path: root + "/2024/Client Smith",
            ))
            _ = try writer.upsertPhotos([(1, 1), (2, 6), (3, 1), (4, 8), (5, nil)].map { number, orientation in
                PhotoRecord(
                    folder: shoot, name: String(format: "Smith_Wedding_%04d.CR3", number), size: 1000,
                    orientation: orientation,
                )
            })
        }
        return Wedding(photos: photos, library: library, catalog: maker.url, index: index)
    }

    @Test func `the census counts what every photo's and virtual copy's settings use`() async throws {
        let wedding = try await Self.wedding()
        defer { wedding.index.closeAndWait() }
        let census = try await LightroomCensus.make(wedding.catalog, index: wedding.index)

        #expect(census.version == "1300025")
        #expect(census.photos == 7 && census.virtualCopies == 2)
        #expect(census.withSettings == 8 && census.unreadable == 1 && census.adjusted == 8 && census.sizes == 4)
        #expect(census.processVersions == ["11.0": 4, "6.7": 2, "5.0": 1])

        let settings = Dictionary(uniqueKeysWithValues: census.settings.map { ($0.name, $0) })
        #expect(settings["Exposure2012"].map { [$0.carried, $0.changed] } == [7, 2])
        #expect(settings["PerspectiveUpright"].map { [$0.carried, $0.changed] } == [7, 2])
        #expect(settings["CameraProfile"].map { [$0.carried, $0.changed] } == [7, 2])
        #expect(settings["Brightness"].map { [$0.carried, $0.changed] } == [1, 1], "no two photos share a value")
        #expect(settings["MaskGroupBasedCorrections"].map { [$0.carried, $0.changed] } == [3, 3])
        #expect(settings["Temperature"].map { [$0.carried, $0.changed] } == [7, 0])
        #expect(census.settings.count == LightroomSettingsText.defaults.count + 9, "\(census.settings.map(\.name))")

        #expect(census.masks == 20 && census.photosWithMasks == 3)
        #expect(census.overMaskLimit == 1 && census.overComponentLimit == 1)
        #expect(Self.kinds(census.components) == [
            "Mask/CircularGradient": [1, 1], "Mask/Gradient": [69, 2], "Mask/Image, MaskSubType 1": [1, 1],
            "Mask/Paint": [1, 1], "Mask/Paint, inside Mask/CircularGradient": [1, 1],
            "Mask/RangeMask, range mask Type 2": [1, 1],
        ])
        let maskSettings = Dictionary(uniqueKeysWithValues: census.maskSettings.map { ($0.name, $0) })
        #expect(maskSettings["LocalExposure2012"].map { [$0.carried, $0.changed] } == [24, 7])
        #expect(maskSettings["CorrectionAmount"].map { [$0.carried, $0.changed] } == [24, 0])
        #expect(maskSettings["CorrectionName"].map { [$0.carried, $0.changed] } == [2, 2])
        #expect(maskSettings["CorrectionMasks"] == nil)
        #expect(Self.kinds(census.earlierMasks) == [
            "CircularGradientBasedCorrections": [1, 1], "GradientBasedCorrections": [1, 1],
            "GradientBasedCorrections, range mask Type 1": [1, 1], "PaintBasedCorrections": [1, 1],
        ])

        #expect(Self.kinds(census.spots) == [
            "clone, Mask/Ellipse": [1, 1], "heal, Method contentAware, Mask/Paint": [1, 1],
            "heal, Method gentle, Mask/Ellipse": [2, 1],
        ])
        #expect(Self.kinds(census.earlierSpots) == ["clone": [1, 1], "heal": [1, 1]])
        #expect(census.profiles == ["Adobe Standard": 5, "Camera Standard": 1, "other": 1])
        #expect(census.looks == ["Adobe Color": 5, "other": 1])
        #expect(census.upright == ["0": 5, "1": 1, "5": 1])
        #expect(census.snapshots == 3 && census.photosWithSnapshots == 2)
        #expect(census.historySteps == 9 && census.photosWithHistory == 3)

        #expect(census.paired && census.found == 7)
        #expect(census.rotations == [
            .init(code: "AB", photos: 4, orientations: ["1": 3]),
            .init(code: "BC", photos: 1, orientations: ["6": 1]),
            .init(code: "CD", photos: 1, orientations: ["1": 1]),
            .init(code: "DA", photos: 1, orientations: ["8": 1]),
            .init(code: "none", photos: 2, orientations: ["none": 1]),
        ])
        #expect(census.notes.isEmpty, "\(census.notes)")
    }

    @Test func `the census names no photo, path, keyword or value`() async throws {
        let wedding = try await Self.wedding()
        defer { wedding.index.closeAndWait() }
        let census = try await LightroomCensus.make(wedding.catalog, index: wedding.index)
        let lines = census.lines()
        print(lines.joined(separator: "\n"))
        let shared = try lines.joined(separator: "\n") + "\n" + String(decoding: census.json(), as: UTF8.self)
        for secret in [
            "Smith", "Wedding", "Client", "Jane", "Copy 1", "Alternate", "retouching", "album", "Black and white",
            "0.35", "0.55", "1.23", "Volumes", wedding.photos.url.lastPathComponent, wedding.library.url.path,
            "Lightroom Catalog.lrcat",
        ] {
            #expect(!shared.contains(secret), "the census names “\(secret)”")
        }
        #expect(lines.contains { $0.contains("Exposure2012: 7, 2 changed") })
        #expect(lines.contains { $0.contains("AB: 4 photos; 3 in the library, EXIF 1: 3") })
        #expect(lines.contains { $0.contains("Upright (PerspectiveUpright): 0 (Off): 5, 1 (Auto): 1, 5 (Guided): 1") })
    }

    @Test func `without the library's index the rotation codes are counted alone`() async throws {
        let wedding = try await Self.wedding()
        defer { wedding.index.closeAndWait() }
        let census = try await LightroomCensus.make(wedding.catalog)
        #expect(!census.paired && census.found == 0)
        #expect(census.rotations.map(\.code) == ["AB", "BC", "CD", "DA", "none"])
        #expect(census.rotations.map(\.photos) == [4, 1, 1, 1, 2] && census.rotations
            .allSatisfy(\.orientations.isEmpty))
        #expect(census.lines().contains { $0.contains("not paired with files") })
    }

    @Test func `a catalog lacking the develop tables is still counted, and the census says what it lacked`(
    ) async throws {
        let wedding = try await Self.wedding()
        defer { wedding.index.closeAndWait() }
        let database = try SQLiteDatabase(path: wedding.catalog.path)
        try database.execute("""
        DROP TABLE Adobe_imageDevelopSettings; DROP TABLE Adobe_libraryImageDevelopSnapshot;
        ALTER TABLE Adobe_images DROP COLUMN orientation
        """)
        let census = try await LightroomCensus.make(wedding.catalog, index: wedding.index)
        #expect(census.photos == 7 && census.virtualCopies == 2 && census.withSettings == 0 && census.adjusted == 0)
        #expect(census.settings.isEmpty && census.processVersions.isEmpty && census.snapshots == 0)
        #expect(census.historySteps == 9, "the history is still there")
        #expect(census.rotations == [.init(code: "none", photos: 9, orientations: ["1": 4, "6": 1, "8": 1, "none": 1])])
        #expect(census.notes.count == 3, "\(census.notes)")
    }

    @Test func `the census of a catalog Lightroom didn't close is read from its copy, and says so`() async throws {
        let wedding = try await Self.wedding()
        defer { wedding.index.closeAndWait() }
        let crashed = wedding.library.url.appending(path: "Crashed/Lightroom Catalog.lrcat")
        try LightroomCatalogTests.leaveLog(
            from: wedding.catalog, at: crashed, changing: "UPDATE Adobe_images SET orientation = 'BA'",
        )
        let census = try await LightroomCensus.make(crashed)
        #expect(census.rotations.map(\.code) == ["BA"] && census.photos == 7)
        #expect(census.notes == [LightroomCatalogReader.copiedNote])
    }

    @Test func `only Adobe's profiles, camera-matching ones and the forms of kinds and codes are named`() {
        typealias Names = LightroomCensusNames
        #expect([
            "Adobe Color",
            "Adobe Standard",
            "Artistic 01",
            "B&W 12",
            "Vintage 07",
            "ACR 4.4",
            "Embedded",
            "Camera Standard",
            "Camera PROVIA/Standard",
            "Camera ACROS+R FILTER",
        ]
        .allSatisfy { Names.profile($0) == $0 })
        #expect(["Smith Wedding", "Adobe Smith", "Artistic Smith", "B&W 123", "Camera <script>", ""].map(Names.profile)
            == ["other", "other", "other", "other", "other", "none"])
        #expect(Names.kind("Mask/Gradient") == "Mask/Gradient" && Names.kind("Jane's face") == "other")
        #expect(Names.kind(String(repeating: "a", count: 41)) == "other" && Names.kind(nil) == "none")
        #expect(Names.processVersion("11.0") == "11.0" && Names.processVersion("Smith") == "other")
        #expect(Names.rotation("AB") == "AB" && Names.rotation("A B") == "other" && Names.rotation(nil) == "none")
        #expect(Names.setting("Exposure2012") == "Exposure2012" && Names.setting("Jane Smith") == "other")
        #expect(Names.upright("3") == "3" && Names.upright("Full") == "other")
        #expect(Names.earlierSpot("centerX = 0.5, spotType = clone") == "clone" && Names.earlierSpot("x = 1") == "none")
    }

    /// Kinds as `[count, photos]`, by name.
    static func kinds(_ kinds: [LightroomCensus.Kind]) -> [String: [Int]] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0.name, [$0.count, $0.photos]) })
    }
}
