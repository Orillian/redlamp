import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// `source:` and the filter bar's Source column (LIB-62), on an index holding a folder's photos beside an album of the
/// simulated Photos library kept in place: All Photographs holding both, each side's photos found with the column store
/// as with SQL, counted by the column, and offered as the text and the palette complete what's typed.
struct ApplePhotosQueryTests {
    private static let folders = ["DSC_0001.NEF", "DSC_0002.JPG"]
    /// The raw and JPEG pair of the sample's album Selects.
    private static let photos = ["IMG_0004.JPG", "IMG_0004.NEF"]

    /// Two photos in a folder, and the album Selects kept in place.
    private static func library() async throws -> IndexSandbox {
        let sandbox = try await IndexSandbox.make()
        let folder = try #require(try await sandbox.addFolders(["Shoot"])["Shoot"])
        let taken = Date(timeIntervalSince1970: 1_750_000_000)
        try await sandbox.upsert(folders.enumerated().map { place, name in
            PhotoRecord(folder: folder, name: name, captured: taken.addingTimeInterval(Double(place)))
        })
        try await ApplePhotosIndexer(photos: SamplePhotos.library(), index: sandbox.index).keep(["album-selects"])
        return sandbox
    }

    /// The names of photos `ids`, in order of name.
    private static func names(
        _ ids: some Sequence<Int64> & Sendable,
        _ sandbox: IndexSandbox,
    ) async throws -> [String] {
        try await sandbox.index.read { reader in try ids.compactMap { try reader.photo(id: $0)?.name } }.sorted()
    }

    @Test func `source reads folders or photos, and writes itself back`() throws {
        let query = try LibraryQuery(parsing: "source:Photos")
        #expect(query == .filter(LibraryQuery.Filter(.source, .equal, [.source(.photos)])))
        #expect(query.description == "source:photos")
        #expect(try LibraryQuery(parsing: "-source:folders,photos").description == "-source:folders,photos")
    }

    @Test func `source finds each side's photos, with the column store as with SQL, and All Photographs holds both`(
    ) async throws {
        let sandbox = try await Self.library()
        defer { sandbox.remove() }
        let both = (Self.folders + Self.photos).sorted()
        let expected: [(String, [String])] = [
            ("source:photos", Self.photos),
            ("source:folders", Self.folders),
            ("-source:photos", Self.folders),
            ("source!=folders", Self.photos),
            ("source:folders,photos", both),
            ("source:photos -source:photos", []),
        ]
        let engine = QueryEngine(index: sandbox.index, timeZone: .gmt)
        var withSQL: [[Int64]] = []
        for (text, _) in expected {
            try await withSQL.append(engine.ids(text))
        }
        #expect(!engine.isLoaded, "the store isn't built yet, so SQL answers")
        try await engine.load()
        for ((text, found), sql) in zip(expected, withSQL) {
            let columns = try await engine.ids(text)
            #expect(try await Self.names(columns, sandbox) == found, "\(text)")
            #expect(columns == sql, "\(text)")
        }
        #expect(try await Self.names(engine.list(.allPhotographs, sort: QuerySort()).ids, sandbox) == both)
    }

    @Test func `the Source column counts each side, folders first, and filters by it`() async throws {
        let sandbox = try await Self.library()
        defer { sandbox.remove() }
        let engine = QueryEngine(index: sandbox.index, timeZone: .gmt)
        try await engine.load()
        #expect(FacetColumn.source.facet == nil && FacetColumn.source.field == .source)
        var counted: [FacetColumnCounts] = []
        let requests = try [
            FacetColumnRequest(.source, query: .all),
            FacetColumnRequest(.source, query: LibraryQuery(parsing: "source:photos")),
        ]
        for try await counts in engine.columns(requests, in: .allPhotographs) {
            counted.append(counts)
        }
        let all = try #require(counted.first { $0.index == 0 })
        #expect(all.total == 4 && all.values.map(\.name) == ["folders", "photos"])
        #expect(all.values.map(\.count) == [2, 2])
        #expect(all.values.map { $0.filter?.description } == ["source:folders", "source:photos"])
        let narrowed = try #require(counted.first { $0.index == 1 })
        #expect(narrowed.values.map(\.name) == ["photos"], "a side none of the photos is on isn't listed")

        var inFolder: [FacetColumnCounts] = []
        let folder = PhotoSource.folder(
            URL(fileURLWithPath: IndexSandbox.rootPath + "/Shoot"),
            includingSubfolders: false,
        )
        for try await counts in engine.columns([FacetColumnRequest(.source, query: .all)], in: folder) {
            inFolder.append(counts)
        }
        #expect(inFolder.first?.values.map(\.name) == ["folders"])
    }

    @Test func `the sources complete by their titles and words, each with the photos it finds`() async throws {
        let sandbox = try await Self.library()
        defer { sandbox.remove() }
        let engine = QueryEngine(index: sandbox.index, timeZone: .gmt)
        try await engine.load()
        let apple = await engine.completions("apple", field: nil)
        let photos = try #require(apple.first { $0.field == .source })
        #expect(photos.term == "source:photos" && photos.count == 2)
        let typed = await engine.completions("fold", field: .source)
        #expect(typed.map(\.term) == ["source:folders"] && typed.first?.count == 2)
        let values = await engine.values(of: .source)
        #expect(values.map(\.term) == ["source:folders", "source:photos"])
        #expect(values.map(\.count) == [2, 2])
        let album = await engine.values(of: .source, in: .applePhotos("album-selects"))
        #expect(album.map(\.count) == [0, 2])
    }
}
