import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// The rows of photos' versions follow the sidecars the library writes (LIB-48), whose dates it records so the indexer
/// doesn't read them again: a catalog's virtual copies come across with rows of their own and Undo Import takes them
/// off, a batch a forced quit stopped leaves them as it leaves its sidecars, and a version another writer added,
/// renamed or removed before the library wrote the sidecar gets, changes or loses its row.
struct MetadataVersionRowsTests {
    /// The rows of the versions of the file whose row is `photo`.
    private static func versions(of photo: Int64, in index: LibraryIndex) async throws -> [PhotoRecord] {
        try await index.read { reader in
            try reader.photo(id: photo).map { try reader.versions(folder: $0.folder, name: $0.name) } ?? []
        }
    }

    /// A query engine loaded from `index`, and the live lists that keep it in step with the library's changes.
    private static func live(_ index: LibraryIndex) async throws -> (QueryEngine, LibraryLive) {
        let engine = QueryEngine(index: index)
        try await engine.load()
        return (engine, LibraryLive(engine: engine, configuration: .init(latency: .milliseconds(10))))
    }

    @Test func `a catalog's virtual copy gets a row with its own fields, found by version:yes, and Undo Import removes it`(
    ) async throws {
        let library = try await LightroomEditsTests.library()
        defer { library.remove() }
        let index = library.sandbox.index
        let (engine, live) = try await Self.live(index)
        let importer = LightroomImport(index: index, paths: library.sandbox.paths, live: live)
        try await importer.run(library.plan())
        await live.settle()

        let raw = try await library.sandbox.id("2024/June/IMG_0001.CR3")
        let copies = try await Self.versions(of: raw, in: index)
        #expect(copies.map(\.versionName) == ["Copy 1", "Copy 2"])
        let copy = try #require(copies.first)
        #expect(copy.rating == 4 && copy.flag == .pick && copy.label == .green && copy.edited)
        #expect(copy.title == "The copy's title" && copy.caption == "Darker")
        let organised = try await index.read { reader in
            try (reader.keywords(forPhoto: copy.id), reader.collectionPlaces(ofPhoto: copy.id).compactMap(\.path))
        }
        #expect(organised.0 == ["Mono"] && organised.1 == ["Selects"])
        let lightroom = try await Self.versions(of: library.sandbox.id("2024/July/IMG_0004.JPG"), in: index)
        #expect(lightroom.map(\.versionName) == ["Lightroom Classic"] && lightroom.first?.rating == 3)
        let found = try await Set(engine.ids("version:yes"))
        #expect(found == Set((copies + lightroom).map(\.id)), "the open lists heard of the versions' rows")

        try await importer.undo()
        await live.settle()
        #expect(try await Self.versions(of: raw, in: index).isEmpty)
        #expect(try await Self.versions(of: library.sandbox.id("2024/July/IMG_0004.JPG"), in: index).isEmpty)
        #expect(try await index.read { reader in try found.compactMap { try reader.photo(id: $0) } }.isEmpty)
        #expect(try await engine.ids("version:yes").isEmpty)
    }

    @Test func `versions a batch brings that a forced quit stopped have rows as its sidecars do, finished or rolled back`(
    ) async throws {
        let sandbox = try await KeywordSandbox.make()
        defer { sandbox.remove() }
        let names = (0 ..< 40).map { String(format: "P%02d.JPG", $0) }
        for name in names {
            try sandbox.photo(name)
        }
        try await sandbox.indexAll()
        let ids = try await sandbox.ids(names)
        func copies() async throws -> [[String?]] {
            try await sandbox.index.read { reader in
                try ids.compactMap { try reader.photo(id: $0) }.map { file in
                    try reader.versions(folder: file.folder, name: file.name).map(\.versionName)
                }
            }
        }

        for choice in [FileRecovery.finish, .rollBack] {
            let killed = LibraryMetadata(index: sandbox.index, paths: sandbox.paths)
            killed.interruption.withLock { $0 = 15 }
            let plan = try await Self.copies(of: ids, killed)
            await #expect(throws: LibraryMetadata.ForcedQuit.self) { try await killed.run(plan) }
            let stopped = try await copies()
            #expect((15 ..< 40).contains(stopped.count { $0 == ["Copy 1"] }), "\(choice): the sidecars written")
            #expect(stopped.allSatisfy { $0.isEmpty || $0 == ["Copy 1"] })

            let launch = LibraryMetadata(index: sandbox.index, paths: sandbox.paths)
            #expect(try await launch.recover(choice).map(\.state) == [choice == .finish ? .finished : .rolledBack])
            let expected: [String?] = choice == .finish ? ["Copy 1"] : []
            #expect(try await copies() == Array(repeating: expected, count: ids.count), "\(choice)")
            #expect(names.allSatisfy { (sandbox.sidecar($0)?.versions.count ?? 0) == expected.count })
            if choice == .finish {
                try await launch.undo()
                #expect(try await copies().allSatisfy(\.isEmpty))
            }
        }
    }

    @Test func `a version added, renamed or removed in a sidecar before the library writes it gets, changes or loses its row`(
    ) async throws {
        let sandbox = try await KeywordSandbox.make()
        defer { sandbox.remove() }
        let photo = try sandbox.photo("A.JPG")
        let copy = PhotoVersion(id: UUID(), name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 4))
        try SidecarStore().save(Sidecar(recipe: EditRecipe(), versions: [copy]), for: photo)
        try await sandbox.indexAll()
        let file = try await sandbox.id("A.JPG")
        let before = try await Self.versions(of: file, in: sandbox.index)
        let (engine, live) = try await Self.live(sandbox.index)
        let metadata = LibraryMetadata(index: sandbox.index, paths: sandbox.paths, live: live)

        var sidecar = try #require(sandbox.sidecar("A.JPG"))
        sidecar.versions[0].name = "Heron"
        sidecar.versions.append(PhotoVersion(
            id: UUID(), name: "Copy 2", recipe: EditRecipe(), metadata: PhotoMetadata(flag: .reject),
        ))
        try SidecarStore().save(sidecar, for: photo)
        try await metadata.apply(.set([.rating(5)], on: [file]))
        await live.settle()
        let after = try await Self.versions(of: file, in: sandbox.index)
        #expect(after.map(\.versionName) == ["Heron", "Copy 2"])
        #expect(after.first?.id == before.first?.id && after.first?.rating == 4, "a version renamed keeps its row")
        #expect(after.last?.flag == .reject)
        #expect(try await Set(engine.ids("version:yes")) == Set(after.map(\.id)))

        sidecar = try #require(sandbox.sidecar("A.JPG"))
        sidecar.versions.removeAll { $0.id == copy.id }
        try SidecarStore().save(sidecar, for: photo)
        try await metadata.apply(.set([.rating(1)], on: [file]))
        await live.settle()
        #expect(try await Self.versions(of: file, in: sandbox.index).map(\.id) == [after[1].id])
        #expect(try await engine.ids("version:yes") == [after[1].id])
        #expect(try await sandbox.index.read { try $0.photo(id: after[0].id) } == nil)
    }

    /// A batch giving each of `ids` a version, Copy 1, as a catalog import brings a virtual copy.
    private static func copies(of ids: [Int64], _ metadata: LibraryMetadata) async throws -> MetadataPlan {
        var batch = MetadataBatch(kind: .metadata, title: "Import")
        batch.photos = try await metadata.photos(
            ids, edits: Dictionary(uniqueKeysWithValues: ids.map { ($0, [:]) }), edit: [:], keepingUnchanged: true,
        )
        for place in batch.photos.indices {
            let version = PhotoVersion(
                id: UUID(), name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 3),
            )
            batch.photos[place].develop = MetadataBatch.Develop(
                recipe: nil, snapshots: [], versions: [JSONValue(sidecar: version)].compactMap(\.self),
            )
        }
        return MetadataPlan(batch: batch)
    }
}
