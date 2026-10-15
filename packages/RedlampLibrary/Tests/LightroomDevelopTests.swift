import Foundation
import Testing
@testable import RedlampLibrary

/// A Lightroom Classic catalog's Develop settings (EDT-23): each photo's and virtual copy's settings with its
/// rotation, its file's size, its snapshots and how many history steps it has, read in parts in the same
/// opening of the catalog as the rest, from its copy when Lightroom didn't close it.
struct LightroomDevelopTests {
    struct Catalog {
        let maker: LightroomCatalogMaker
        let first: Int64
        let second: Int64
        let third: Int64
        let copy: Int64
        let firstText: String
    }

    /// Three photos and a virtual copy: the first with settings, a rotation, a size, two snapshots and four
    /// history steps; the second with two rows of settings, the later one written last; the third with none;
    /// the copy with its own settings, rotation and history.
    static func catalog(in folder: URL) throws -> Catalog {
        let maker = try LightroomCatalogMaker(at: folder.appending(path: "Lightroom Catalog.lrcat"))
        let root = try maker.root("/Volumes/Photos/")
        let shoot = try maker.folder(root, "2024/")
        let first = try maker.photo(shoot, "A.CR3", orientation: "AB", size: (6000, 4000))
        let second = try maker.photo(shoot, "B.CR3", orientation: "BC", size: (4000, 6000))
        let third = try maker.photo(shoot, "C.JPG")
        let copy = try maker.photo(shoot, "A.CR3", master: first, copyName: "Copy 1", orientation: "CD")
        let firstText = LightroomSettingsText.text(["Exposure2012": "0.35"])
        try maker.develop(first, firstText, processVersion: "11.0", digest: "D1")
        try maker.develop(second, #"s = { ProcessVersion = "6.7" }"#, processVersion: "6.7")
        try maker.develop(second, #"s = { ProcessVersion = "11.0" }"#, processVersion: "11.0")
        try maker.develop(copy, LightroomSettingsText.text(["Exposure2012": "-0.5"]))
        try maker.snapshot(first, name: "Before", text: "s = { Exposure2012 = 0 }")
        try maker.snapshot(first, name: "After", text: firstText)
        try maker.history(first, steps: 4)
        try maker.history(copy, steps: 1)
        maker.close()
        return Catalog(maker: maker, first: first, second: second, third: third, copy: copy, firstText: firstText)
    }

    /// Each photo's and virtual copy's Develop settings in `url`, read in parts of `partSize`, the parts' sizes,
    /// and the notes.
    static func develop(
        _ url: URL, partSize: Int = 2,
    ) throws -> (records: [LightroomCatalog.Develop], parts: [Int], notes: [String]) {
        var notes: [String] = []
        let parts = try LightroomCatalog.opened(url) { reader in
            try reader.develop(partSize: partSize, notes: &notes) { $0 }
        }
        return (parts.flatMap(\.self), parts.map(\.count), notes)
    }

    @Test func `each photo's and virtual copy's settings, rotation, size, snapshots and history are read in parts`(
    ) throws {
        let folder = try TemporaryFolder()
        let catalog = try Self.catalog(in: folder.url)
        let (records, parts, notes) = try Self.develop(catalog.maker.url)
        #expect(parts == [2, 2])
        #expect(records.map(\.image) == [catalog.first, catalog.second, catalog.third, catalog.copy])
        #expect(notes.isEmpty, "\(notes)")

        let first = records[0]
        #expect(first.master == nil && first.orientation == "AB")
        #expect(first.fileWidth == 6000 && first.fileHeight == 4000)
        #expect(first.text == catalog.firstText && first.processVersion == "11.0" && first.digest == "D1")
        #expect(try first.settings()?.number("Exposure2012") == 0.35)
        #expect(try first.settings()?.text("CameraProfile") == "Adobe Standard")
        #expect(try first.settings()?["Look"]?.table?.text("Name") == "Adobe Color")
        #expect(first.snapshots.map(\.name) == ["Before", "After"])
        #expect(try first.snapshots.first?.settings()?.number("Exposure2012") == 0)
        #expect(first.snapshots.allSatisfy { $0.snapshotID != nil && $0.globalID != nil && $0.digest != nil })
        #expect(first.historySteps == 4)
        #expect(catalog.firstText.utf8.count > 3000, "settings the size a real catalog's are")

        let second = records[1]
        #expect(try second.settings()?.text("ProcessVersion") == "11.0", "the settings written last")
        #expect(second.orientation == "BC" && second.fileWidth == 4000 && second.snapshots.isEmpty)

        let third = records[2]
        #expect(third.text == nil && third.orientation == nil && third.fileWidth == nil && third.historySteps == 0)
        #expect(try third.settings() == nil)

        let copy = records[3]
        #expect(copy.master == catalog.first && copy.orientation == "CD" && copy.historySteps == 1)
        #expect(try copy.settings()?.number("Exposure2012") == -0.5)
    }

    @Test func `parts follow the catalog's order whatever their size`() throws {
        let folder = try TemporaryFolder()
        let catalog = try Self.catalog(in: folder.url)
        let order = [catalog.first, catalog.second, catalog.third, catalog.copy]
        for size in [1, 3, 500] {
            let (records, parts, _) = try Self.develop(catalog.maker.url, partSize: size)
            #expect(records.map(\.image) == order)
            #expect(parts.allSatisfy { $0 <= size } && parts.reduce(0, +) == 4)
        }
    }

    @Test func `a catalog lacking the develop tables and columns is still read, and its notes say what it lacked`(
    ) throws {
        let folder = try TemporaryFolder()
        let catalog = try Self.catalog(in: folder.url)
        let database = try SQLiteDatabase(path: catalog.maker.url.path)
        try database.execute("""
        DROP TABLE Adobe_libraryImageDevelopSnapshot; DROP TABLE Adobe_libraryImageDevelopHistoryStep;
        ALTER TABLE Adobe_images DROP COLUMN orientation; ALTER TABLE Adobe_images DROP COLUMN fileWidth;
        ALTER TABLE Adobe_imageDevelopSettings DROP COLUMN processVersion;
        ALTER TABLE Adobe_imageDevelopSettings DROP COLUMN digest
        """)
        let (records, _, notes) = try Self.develop(catalog.maker.url)
        #expect(records.count == 4)
        #expect(records[0].text == catalog.firstText, "the settings themselves are still read")
        #expect(records.allSatisfy {
            $0.orientation == nil && $0.fileWidth == nil && $0.fileHeight == nil && $0.processVersion == nil
                && $0.digest == nil && $0.snapshots.isEmpty && $0.historySteps == 0
        })
        #expect(notes.count == 6, "\(notes)")
        #expect(notes.contains { $0.contains("orientation") } && notes.contains { $0.contains("fileWidth") })
        #expect(notes.contains { $0.contains("Snapshot") } && notes.contains { $0.contains("HistoryStep") })

        try database.execute("DROP TABLE Adobe_imageDevelopSettings")
        let (bare, _, bareNotes) = try Self.develop(catalog.maker.url)
        #expect(bare.count == 4 && bare.allSatisfy { $0.text == nil })
        #expect(bareNotes.contains { $0.contains("no Develop settings") })
    }

    @Test func `a catalog Lightroom didn't close has its settings read from its copy, which goes once they're read`(
    ) throws {
        let folder = try TemporaryFolder()
        let catalog = try Self.catalog(in: folder.url)
        let crashed = folder.url.appending(path: "Crashed/Lightroom Catalog.lrcat")
        try LightroomCatalogTests.leaveLog(
            from: catalog.maker.url, at: crashed,
            changing: "UPDATE Adobe_imageDevelopSettings SET text = 's = { Exposure2012 = 1.5 }' "
                + "WHERE image = \(catalog.first)",
        )
        let before = try Data(contentsOf: crashed)
        var read: (path: String, copied: Bool)?
        var notes: [String] = []
        let parts = try LightroomCatalog.opened(crashed) { reader in
            read = (reader.database.path, reader.copied)
            return try reader.develop(notes: &notes) { $0 }
        }
        let opened = try #require(read)
        #expect(opened.copied && opened.path != crashed.path)
        #expect(!FileManager.default.fileExists(atPath: opened.path), "the copy is deleted once it's read")
        #expect(try parts.flatMap(\.self).first?.settings()?.number("Exposure2012") == 1.5, "the log's change")
        #expect(try Data(contentsOf: crashed) == before)
    }
}
