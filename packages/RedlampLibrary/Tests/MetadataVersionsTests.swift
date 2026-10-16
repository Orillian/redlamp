import Foundation
import RedlampDocument
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// The library's own changes to versions of photos' edits (LIB-48): ratings, flags, labels, keywords and their Undo
/// reach a version's own metadata in its file's sidecar, never the file's, with one write a sidecar for a file and its
/// versions; a capture time changed through a version is its file's, which the version shows.
struct MetadataVersionsTests {
    private static let copy = UUID(uuidString: "6F1C2A4E-8B1D-4C3A-9E57-1B2D3C4E5F60")!

    /// A photo whose sidecar gives it a rating of 2 and a version, Copy 1, rated 4, indexed.
    private static func library() async throws -> (sandbox: KeywordSandbox, file: Int64, version: Int64) {
        let sandbox = try await KeywordSandbox.make()
        try sandbox.shot("A.JPG", at: "2024:06:01 12:00:00", offset: "+01:00")
        let version = PhotoVersion(id: copy, name: "Copy 1", recipe: EditRecipe(), metadata: PhotoMetadata(rating: 4))
        try SidecarStore().save(
            Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 2), versions: [version]),
            for: sandbox.url("A.JPG"),
        )
        try await sandbox.indexAll()
        let file = try await sandbox.id("A.JPG")
        let row = try await sandbox.index.read { reader in
            try reader.photo(id: file).flatMap { try reader.versions(folder: $0.folder, name: $0.name).first?.id }
        }
        return try (sandbox, file, #require(row))
    }

    private static func rows(_ sandbox: KeywordSandbox, _ ids: [Int64]) async throws -> [PhotoRecord] {
        try await sandbox.index.read { reader in try ids.compactMap { try reader.photo(id: $0) } }
    }

    @Test func `a rating and a flag given to a version are its own, in its file's sidecar, and Undo takes them back`(
    ) async throws {
        let (sandbox, file, version) = try await Self.library()
        defer { sandbox.remove() }
        let metadata = LibraryMetadata(index: sandbox.index, paths: sandbox.paths)
        let outcome = try await metadata.apply(.set([.rating(5), .flag(.pick)], on: [version]))
        #expect(outcome.photos == 1 && outcome.written == 1)
        let sidecar = try #require(sandbox.sidecar("A.JPG"))
        #expect(sidecar.metadata?.rating == 2 && sidecar.metadata?.flag == nil)
        #expect(sidecar.version(Self.copy)?.metadata?.rating == 5 && sidecar.version(Self.copy)?.metadata?
            .flag == .pick)
        #expect(try await Self.rows(sandbox, [file, version]).map(\.rating) == [2, 5])

        try await metadata.undo()
        let undone = try #require(sandbox.sidecar("A.JPG"))
        #expect(undone.metadata?.rating == 2 && undone.version(Self.copy)?.metadata?.rating == 4)
        #expect(undone.version(Self.copy)?.metadata?.flag == nil)
        #expect(try await Self.rows(sandbox, [file, version]).map(\.rating) == [2, 4])
    }

    @Test func `a file and its version changed together are written once, each in its own edit`() async throws {
        let (sandbox, file, version) = try await Self.library()
        defer { sandbox.remove() }
        let metadata = LibraryMetadata(index: sandbox.index, paths: sandbox.paths)
        let outcome = try await metadata.apply(.set([.label(.red), .rating(3)], on: [file, version]))
        #expect(outcome.written == 2 && outcome.skipped.isEmpty)
        let sidecar = try #require(sandbox.sidecar("A.JPG"))
        #expect(sidecar.metadata?.label == .red && sidecar.metadata?.rating == 3)
        #expect(sidecar.version(Self.copy)?.metadata?.label == .red && sidecar.version(Self.copy)?.metadata?
            .rating == 3)
        #expect(try await Self.rows(sandbox, [file, version]).map(\.label) == [.red, .red])
    }

    @Test func `keywords added to a version are its own, and Undo takes them off`() async throws {
        let (sandbox, file, version) = try await Self.library()
        defer { sandbox.remove() }
        let keywords = sandbox.keywords()
        try await keywords.apply(.add([kw("Birds/Heron")], to: [version]))
        let sidecar = try #require(sandbox.sidecar("A.JPG"))
        #expect(sidecar.metadata?.keywords == nil && sidecar.version(Self.copy)?.metadata?.keywords == ["Birds/Heron"])
        let indexed = try await sandbox.index.read { reader in
            try (reader.keywords(forPhoto: file), reader.keywords(forPhoto: version))
        }
        #expect(indexed.0.isEmpty && indexed.1 == ["Birds/Heron"])

        try await keywords.undo()
        let undone = try #require(sandbox.sidecar("A.JPG"))
        #expect(undone.version(Self.copy)?.metadata?.keywords ?? [] == [] && undone.metadata?.keywords == nil)
        #expect(try await sandbox.index.read { try $0.keywords(forPhoto: version) }.isEmpty)
    }

    @Test func `a capture time shifted through a version is its file's, which the version shows`() async throws {
        let (sandbox, file, version) = try await Self.library()
        defer { sandbox.remove() }
        let before = try await Self.rows(sandbox, [file, version])
        let metadata = LibraryMetadata(index: sandbox.index, paths: sandbox.paths)
        try await metadata.apply(.shift([version], by: 3600))
        let sidecar = try #require(sandbox.sidecar("A.JPG"))
        #expect(sidecar.metadata?.captureShift == 3600 && sidecar.version(Self.copy)?.metadata?.captureShift == 0)
        let after = try await Self.rows(sandbox, [file, version])
        let shifted = before[0].captured.map { $0.addingTimeInterval(3600) }
        #expect(shifted != nil && after.map(\.captured) == [shifted, shifted])
    }
}
