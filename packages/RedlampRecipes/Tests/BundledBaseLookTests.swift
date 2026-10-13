import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// The Base Looks Redlamp ships: compressed in the bundle, listed by an index of their
/// details, and each table read the first time its look is used.
struct BundledBaseLookTests {
    @Test func `the bundled looks ship compressed, and the index lists each one`() {
        let bundle = BuiltInBaseLooks.bundle
        let plain = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("base-") || $0.lastPathComponent.hasPrefix("stock-") }
        #expect(plain.isEmpty)
        #expect((bundle.urls(forResourcesWithExtension: "lzfse", subdirectory: nil) ?? []).isEmpty)
        let files = bundle.urls(forResourcesWithExtension: "lzma", subdirectory: nil) ?? []
        #expect(!files.isEmpty)
        #expect(files.count == BuiltInBaseLooks.resources.count)
    }

    @Test func `every bundled look's details match its file, and its table decodes to its hash`() throws {
        let files = BuiltInBaseLooks.bundle.urls(forResourcesWithExtension: "lzma", subdirectory: nil) ?? []
        let decoded = try files.map(BuiltInBaseLooks.decode)
        let listed = BuiltInBaseLooks.read()
        #expect(!listed.isEmpty)
        #expect(Set(decoded) == Set(listed))
        for package in listed {
            let table = try #require(try package.definition().table)
            #expect(table.contentHash == package.table?.sha256)
        }
    }

    @Test func `listing the bundled looks reads no table, and using a look reads only its own, keeping no text`(
    ) throws {
        let looks = BuiltInBaseLooks.read()
        #expect(looks.contains { $0.table != nil })
        _ = looks.map(\.reference)
        _ = BuiltInBaseLooks.newest(looks)
        _ = Set(looks)
        #expect(looks.allSatisfy { ($0.table?.reads ?? 0) == 0 })

        let look = try #require(looks.first { $0.table != nil })
        let definition = try look.definition()
        #expect(definition.table?.contentHash == look.table?.sha256)
        #expect(looks.count(where: { ($0.table?.reads ?? 0) > 0 }) == 1)

        // The text isn't kept once its table is decoded.
        _ = try look.definition()
        #expect(look.table?.reads == 2)
    }

    @Test func `installing a look writes it compressed and lists it in the folder's index`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "bundled-looks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = try BaseLookPackage(
            id: "redlamp/test", name: "Test", slot: "test",
            table: LookTable(size: 3) { SIMD3($0.x * 0.9, $0.y, $0.z) },
        )
        try BuiltInBaseLooks.install(package, as: "base-test", in: folder)
        let file = folder.appending(path: "base-test.look.lzma")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try BuiltInBaseLooks.decode(file) == package)
        #expect(BuiltInBaseLooks.installed("base-test", in: folder) == package)
        #expect(BuiltInBaseLooks.read(from: folder) == [package])
    }

    @Test func `a file that isn't a bundled look, or whose table is cut short, isn't read`() throws {
        let other = try (Data("{}".utf8) as NSData).compressed(using: .lzma) as Data
        #expect(throws: BundledLookFile.ReadError.notALook) { try BundledLookFile.decode(other) }

        let package = try BaseLookPackage(id: "redlamp/test", name: "Test", table: LookTable(size: 3) { $0 })
        let whole = try (BundledLookFile.encode(package) as NSData).decompressed(using: .lzma) as Data
        let cut = try (whole.dropLast(2) as NSData).compressed(using: .lzma) as Data
        #expect(throws: BundledLookFile.ReadError.badTable) { try BundledLookFile.decode(cut) }
    }
}
