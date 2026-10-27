import Foundation
import RedlampDocument
import Testing

/// `redlamp library photos` (LIB-54), run as a person runs it, on the simulated Photos library in
/// `tests/fixtures/apple-photos`: its albums, the census, the import and its Undo.
struct PhotosCommandTests {
    private final class Bundled {}

    /// The tool, built beside this test bundle.
    private static let redlamp = Bundle(for: Bundled.self).bundleURL.deletingLastPathComponent()
        .appending(path: "redlamp")
    private static let manifest = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "tests/fixtures/apple-photos/manifest.json")

    private struct Run {
        var status: Int32
        var output: String
        var errors: String

        func json() throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        }
    }

    /// `redlamp library photos` with `arguments`, on the sample's manifest unless it's `manifest`.
    private static func run(_ arguments: [String], in scratch: URL, manifest: URL? = nil) async throws -> Run {
        try #require(FileManager.default.isExecutableFile(atPath: redlamp.path), "redlamp isn't built beside the tests")
        let name = UUID().uuidString
        let output = scratch.appending(path: "\(name).out"), errors = scratch.appending(path: "\(name).err")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let process = Process()
        process.executableURL = redlamp
        process.arguments = ["library", "photos", "--simulated", (manifest ?? Self.manifest).path] + arguments
        process.standardOutput = try FileHandle(forWritingTo: output)
        process.standardError = try FileHandle(forWritingTo: errors)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return try Run(
            status: process.terminationStatus, output: String(contentsOf: output, encoding: .utf8),
            errors: String(contentsOf: errors, encoding: .utf8),
        )
    }

    private static func scratch() throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "redlamp-photos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    @Test func `--albums lists the tree, each folder's albums below it, with counts and IDs`() async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let text = try await Self.run(["--albums"], in: scratch)
        #expect(text.status == 0, "\(text.errors)")
        #expect(text.output.contains("Trips (folder)  folder-trips\n  Lisbon (album, 6)  album-lisbon\n"))
        #expect(text.output.contains("Family (shared album, reduced copies, 1)  shared-family"))
        let json = try await Self.run(["--albums", "--json"], in: scratch)
        let albums = try #require(try JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [[String: Any]])
        #expect(albums.map { $0["id"] as? String } == [
            "album-selects", "folder-trips", "album-lisbon", "album-porto", "smart-favourites", "shared-family",
        ])
        #expect(albums[3]["parent"] as? String == "folder-trips" && albums[3]["estimatedCount"] as? Int == 3)
    }

    @Test func `--census reports the albums named, naming none of them, and writes nothing`() async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let index = scratch.appending(path: "Library/Index.sqlite")
        let run = try await Self.run(
            ["--census", "--album", "Trips/Lisbon", "--album", "shared-family", "--index", index.path, "--json"],
            in: scratch,
        )
        #expect(run.status == 0, "\(run.errors)")
        let census = try run.json()
        #expect(census["albums"] as? [String: Int] == ["album": 1, "sharedAlbum": 1])
        #expect(census["photos"] as? Int == 6 && census["videosLeft"] as? Int == 1 && census["hiddenLeft"] as? Int == 1)
        #expect(census["sharedCopies"] as? Int == 1 && census["edited"] as? Int == 1)
        #expect(census["fromMacOS27"] as? [String] == [])
        for secret in ["Lisbon", "Family", "IMG_", "8A1F"] {
            #expect(!run.output.contains(secret), "the census names “\(secret)”")
        }
        #expect(!FileManager.default.fileExists(atPath: index.deletingLastPathComponent().path), "nothing written")
        let text = try await Self.run(["--census", "--index", index.path], in: scratch)
        #expect(text.status == 0 && text.output.contains("From 3 albums: 10 assets"), "\(text.output)")
    }

    @Test func `--apply imports an album with its fields, and --undo takes it back`() async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let index = scratch.appending(path: "Library/Index.sqlite")
        let pictures = scratch.appending(path: "Pictures")
        let applied = try await Self.run(
            [
                "--apply",
                "--album",
                "Lisbon",
                "--destination",
                pictures.path,
                "--folders",
                "{album}",
                "--index",
                index.path,
                "--json",
            ],
            in: scratch,
        )
        #expect(applied.status == 0, "\(applied.errors)")
        let imported = try #require(try applied.json()["import"] as? [String: Any])
        #expect(imported["state"] as? String == "finished" && imported["imported"] as? Int == 5)
        #expect(imported["photos"] as? Int == 6 && imported["placesOnlyInPhotos"] as? Int == 1)
        let tram = pictures.appending(path: "Lisbon/IMG_0001.HEIC")
        let metadata = try #require(SidecarStore().load(for: tram)?.metadata)
        #expect(metadata.flag == .pick && metadata.collections == ["Trips/Lisbon"])
        #expect(metadata.applePhotos?.id == "8A1F0001-0000-4000-8000-000000000001/L0/001")
        #expect(FileManager.default.fileExists(atPath: scratch.appending(path: "Library/Apple Photos.json").path))

        let again = try await Self.run(["--census", "--album", "Lisbon", "--index", index.path, "--json"], in: scratch)
        #expect(try again.json()["alreadyImported"] as? Int == 5)

        let undone = try await Self.run(["--undo", "--index", index.path, "--json"], in: scratch)
        #expect(undone.status == 0, "\(undone.errors)")
        let trashed = try #require(try undone.json()["trashed"] as? [String])
        defer {
            for file in trashed {
                try? FileManager.default.removeItem(atPath: file)
            }
        }
        #expect(trashed.contains { $0.hasSuffix("IMG_0001.HEIC") })
        #expect(!FileManager.default.fileExists(atPath: tram.path))
        let nothing = try await Self.run(["--undo", "--index", index.path], in: scratch)
        #expect(nothing.status == 1 && nothing.errors.contains("no import from Apple Photos to undo"))
    }

    @Test func `--keep keeps an album in place without copying a file, and --list lists it with its photos`(
    ) async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let index = scratch.appending(path: "Library/Index.sqlite")
        let kept = try await Self.run(
            ["--keep", "--album", "Trips/Lisbon", "--index", index.path, "--json"],
            in: scratch,
        )
        #expect(kept.status == 0, "\(kept.errors)")
        let report = try kept.json()
        #expect(report["albums"] as? [String] == ["album-lisbon"] && report["photos"] as? Int == 5)
        #expect(report["inserted"] as? Int == 6 && report["videos"] as? Int == 1 && report["hidden"] as? Int == 1)
        let cache = scratch.appending(path: "Library/Apple Photos/System")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: cache.path)) == nil)
        let again = try await Self.run(["--keep", "--index", index.path], in: scratch)
        #expect(
            again.status == 0 && again.output.contains("0 rows added, 0 written again, 0 taken out"),
            "\(again.output)",
        )
        let listed = try await Self.run(["--list", "--index", index.path], in: scratch)
        #expect(listed.status == 0 && listed.output == "Lisbon (album, 6 photos)  album-lisbon\n", "\(listed.output)")
    }

    @Test func `--originals reports the cache of originals downloaded from iCloud, and --evict empties it`(
    ) async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let index = scratch.appending(path: "Library/Index.sqlite")
        let kept = try await Self.run(["--keep", "--album", "Trips/Lisbon", "--index", index.path], in: scratch)
        #expect(kept.status == 0, "\(kept.errors)")
        let folder = scratch.appending(path: "Library/Apple Photos/System/0123456789abcdef0123456789abcdef")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 50000).write(to: folder.appending(path: "IMG_0001.HEIC"))

        let report = try await Self.run(["--originals", "--index", index.path, "--json"], in: scratch).json()
        #expect(report["files"] as? Int == 1 && (report["bytes"] as? Int ?? 0) >= 50000)
        #expect(report["budget"] as? Int == 20_000_000_000)
        let evicted = try await Self.run(["--evict", "--index", index.path], in: scratch)
        #expect(
            evicted.status == 0 && evicted.output.hasPrefix("Took 1 originals out of the cache"),
            "\(evicted.output)",
        )
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        let empty = try await Self.run(["--originals", "--index", index.path], in: scratch)
        #expect(empty.output.hasPrefix("Originals downloaded from iCloud: 0, "), "\(empty.output)")
        #expect(empty.output.contains("of a budget of 20 GB"), "\(empty.output)")
    }

    @Test func `a missing destination, an album Photos hasn't and access refused are each said`() async throws {
        let scratch = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let index = scratch.appending(path: "Library/Index.sqlite").path
        let noDestination = try await Self.run(["--apply", "--index", index], in: scratch)
        #expect(noDestination.status == 1 && noDestination.errors.contains("--apply needs --destination"))
        let nowhere = try await Self.run(["--census", "--album", "Nowhere", "--index", index], in: scratch)
        #expect(nowhere.status == 1 && nowhere.errors.contains("Photos has no album Nowhere"))
        let both = try await Self.run(["--census", "--apply"], in: scratch)
        #expect(both.status == 1 && both.errors.contains("photos takes one of"))

        let refused = scratch.appending(path: "refused.json")
        try JSONSerialization.data(withJSONObject: [
            "format": "app.redlamp.simulated-photos", "version": 1, "access": "notDetermined", "grants": "denied",
            "collections": [], "assets": [],
        ]).write(to: refused)
        let denied = try await Self.run(["--albums"], in: scratch, manifest: refused)
        #expect(denied.status == 1 && denied.errors.contains("Privacy & Security › Photos"), "\(denied.errors)")
    }
}
