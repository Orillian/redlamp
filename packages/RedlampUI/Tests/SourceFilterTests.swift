import Foundation
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// Where photos are kept, in the filter bar and the palette (LIB-62): the Source column beside Folder and its rows'
/// titles, the completion and the palette's term for `source:`, and the smart collection editor's name for it.
@MainActor
struct SourceFilterTests {
    @Test func `the Source column follows Folder, and its rows are Folders and Apple Photos`() throws {
        #expect(FacetColumn.source.title == "Source")
        let menu = FacetColumn.allCases.map(\.title)
        #expect(menu.firstIndex(of: "Source") == menu.firstIndex(of: "Folder").map { $0 + 1 })
        let counts = FacetColumnCounts(index: 0, column: .source, total: 5, values: [
            FacetValue(name: "folders", count: 3, filter: .filter(.init(.source, .equal, [.source(.folders)]))),
            FacetValue(name: "photos", count: 2, filter: .filter(.init(.source, .equal, [.source(.photos)]))),
        ])
        let rows = FilterColumnRow.rows(counts, folder: nil)
        #expect(rows.map(\.title) == ["Folders", "Apple Photos"] && rows.map(\.count) == [3, 2])
        let chosen = try FilterColumnRow.choice(in: QueryRules(parsing: "source:photos rating>=3"), column: .source)
        #expect(rows.map { $0.isChosen(by: chosen, in: .source) } == [false, true])
    }

    @Test func `source completes as Folders or Apple Photos, a term the palette lists with its photos`() {
        let completion = FilterCompletion(QueryCompletion(field: .source, value: "photos", count: 2))
        #expect(completion.title == "Apple Photos" && completion.text == "source:photos ")
        #expect(completion.detail == "Source · 2")
        let items = PaletteCatalog.libraryItems(
            names: [QueryCompletion(field: .source, value: "folders", count: 3)], photos: nil,
        )
        #expect(items.map(\.title) == ["Folders"] && items.first?.context == "source:folders · 3 photos")
        #expect(SmartRules.title(of: LibraryQuery.Field.source) == "Source")
        #expect(SmartRules.fields.contains(.filter(.source)))
    }
}
