import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

struct ExportNamesTests {
    private static func photo(_ name: String, in folder: String = "/Photos", minute: Int = 0) -> ExportNames.Photo {
        ExportNames.Photo(
            url: URL(fileURLWithPath: folder).appending(path: name),
            fields: NamingJobTests.photo(name, in: folder, minute: minute),
        )
    }

    private static func names(_ photos: [ExportNames.Photo], _ settings: ExportSettings) throws -> [String] {
        try ExportNames(photos, settings: settings, reading: ImageIOFiles()).targets.map(\.url.path)
    }

    /// An earlier export of `name` in `folder`, as Redlamp writes one.
    private static func earlierExport(_ name: String, in folder: URL) throws {
        try ImageExporter.write(
            PhotoMetadataReaderTests.image(width: 8, height: 8), to: folder.appending(path: name),
            settings: ExportSettings(), reading: ImageIOFiles(),
        )
    }

    @Test func `the standard template names each photo as one photo's export always has`() throws {
        let photos = [Self.photo("IMG_0001.ARW"), Self.photo("IMG_0002.NEF")]
        #expect(try Self.names(photos, ExportSettings()) == [
            "/Photos/IMG_0001-redlamp.jpg", "/Photos/IMG_0002-redlamp.jpg",
        ])
        var settings = ExportSettings()
        settings.setFormat(.tiff)
        settings.destinationFolder = URL(fileURLWithPath: "/Exports")
        settings.naming = .custom("Harbour: dusk/2")
        #expect(try Self.names([photos[0]], settings) == ["/Exports/Harbour- dusk-2.tif"])
    }

    @Test func `sequences number the batch in its order from their start, and the total counts it`() throws {
        var settings = ExportSettings()
        settings.naming = ExportNaming(
            template: "{text:shoot}-{sequence:3} of {total}", texts: ["shoot": "Harbour"], sequenceStart: 7,
        )
        let photos = [Self.photo("B.ARW", minute: 5), Self.photo("A.ARW", minute: 1), Self.photo("C.ARW")]
        #expect(try Self.names(photos, settings) == [
            "/Photos/Harbour-007 of 3.jpg", "/Photos/Harbour-008 of 3.jpg", "/Photos/Harbour-009 of 3.jpg",
        ])
    }

    @Test func `a raw's export and its JPEG's are two files`() throws {
        let photos = [Self.photo("IMG_0001.ARW"), Self.photo("IMG_0001.JPG")]
        #expect(try Self.names(photos, ExportSettings()) == [
            "/Photos/IMG_0001-redlamp.jpg", "/Photos/IMG_0001-redlamp-2.jpg",
        ])
    }

    @Test func `photos given one name are numbered in the order they were taken`() throws {
        var settings = ExportSettings()
        settings.naming = .custom("Harbour")
        settings.destinationFolder = URL(fileURLWithPath: "/Exports")
        let photos = [
            Self.photo("C.ARW", minute: 9), Self.photo("A.ARW", in: "/Photos/Day 1", minute: 1),
            Self.photo("B.ARW", minute: 4),
        ]
        #expect(try Self.names(photos, settings) == [
            "/Exports/Harbour-3.jpg", "/Exports/Harbour.jpg", "/Exports/Harbour-2.jpg",
        ])
    }

    @Test(arguments: ExistingFilePolicy.allCases)
    func `an earlier export is replaced, numbered, skipped or asked about, as the rule says`(
        policy: ExistingFilePolicy,
    ) throws {
        let folder = try TemporaryFolder()
        try Self.earlierExport("IMG_0001-redlamp.jpg", in: folder.url)
        try Self.earlierExport("IMG_0001-redlamp-2.jpg", in: folder.url)
        var settings = ExportSettings()
        settings.existingFiles = policy
        let photos = ["IMG_0001.ARW", "IMG_0002.ARW"].map { Self.photo($0, in: folder.url.path) }
        let names = try ExportNames(photos, settings: settings, reading: ImageIOFiles())
        let first = names.targets[0]
        switch policy {
        case .ask: #expect(first.existing == .asked && names.asked == 1)
        case .overwrite: #expect(first.existing == .replaced)
        case .skip: #expect(first.existing == .skipped && names.written.count == 1)
        case .addNumber:
            #expect(first.url.lastPathComponent == "IMG_0001-redlamp-3.jpg" && first.existing == .none)
        }
        #expect(names.targets[1].url.lastPathComponent == "IMG_0002-redlamp.jpg")
        #expect(names.targets[1].existing == .none)
    }

    @Test(arguments: ExistingFilePolicy.allCases)
    func `a photo is never replaced, whatever the rule, and a number keeps clear of the batch's names`(
        policy: ExistingFilePolicy,
    ) throws {
        let folder = try TemporaryFolder()
        try Data("raw".utf8).write(to: folder.url.appending(path: "IMG_0001.ARW"))
        try Data("raw".utf8).write(to: folder.url.appending(path: "IMG_0001.jpg"))
        var settings = ExportSettings()
        settings.existingFiles = policy
        settings.naming = ExportNaming(template: "{name}")
        let photos = [
            Self.photo("IMG_0001.ARW", in: folder.url.path),
            Self.photo("IMG_0001-2.ARW", in: folder.url.path),
        ]
        let names = try ExportNames(photos, settings: settings, reading: ImageIOFiles())
        #expect(names.targets.map(\.url.lastPathComponent) == ["IMG_0001-3.jpg", "IMG_0001-2.jpg"])
        #expect(names.targets.allSatisfy { $0.existing == .none })
    }

    @Test func `the answer to Ask applies to every earlier export the batch would replace`() throws {
        let folder = try TemporaryFolder()
        for name in ["A-redlamp.jpg", "B-redlamp.jpg"] {
            try Self.earlierExport(name, in: folder.url)
        }
        let photos = ["A.ARW", "B.ARW", "C.ARW"].map { Self.photo($0, in: folder.url.path) }
        let names = try ExportNames(photos, settings: ExportSettings(), reading: ImageIOFiles())
        #expect(names.asked == 2)
        #expect(names.answering(.overwrite).map(\.existing) == [.replaced, .replaced, .none])
        #expect(names.answering(.skip).map(\.existing) == [.skipped, .skipped, .none])
        #expect(names.answering(.addNumber).map(\.url.lastPathComponent) == [
            "A-redlamp-2.jpg", "B-redlamp-2.jpg", "C-redlamp.jpg",
        ])
    }

    @Test func `named counters carry on, and a template that doesn't read throws`() throws {
        var settings = ExportSettings()
        settings.naming = ExportNaming(template: "Trip-{counter:trip:3}")
        let names = try ExportNames(
            [Self.photo("A.ARW"), Self.photo("B.ARW")], settings: settings, counters: NamingCounters(["trip": 41]),
            reading: ImageIOFiles(),
        )
        #expect(names.targets.map(\.url.lastPathComponent) == ["Trip-042.jpg", "Trip-043.jpg"])
        #expect(names.counters["trip"] == 43)
        settings.naming = ExportNaming(template: "{nothing}")
        #expect(throws: NamingTemplateError.self) {
            try ExportNames([Self.photo("A.ARW")], settings: settings, reading: ImageIOFiles())
        }
    }
}
