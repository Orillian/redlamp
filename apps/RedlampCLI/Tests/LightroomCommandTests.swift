import CoreGraphics
import Foundation
import ImageIO
import RedlampDocument
@_spi(Harness) import RedlampEngineAPI
import SQLite3
import Testing

/// `redlamp library lightroom` (EDT-23), run as a person runs it on a Lightroom Classic catalog made for the test,
/// never one Lightroom made: its census, the rotation codes paired with the EXIF orientations of the files a
/// library has indexed, naming none of the photos; and its import, raws naming the synthetic Adobe profiles of a
/// Camera Raw folder made for the test (EDT-33).
struct LightroomCommandTests {
    private final class Bundled {}

    /// The tool, built beside this test bundle.
    private static let redlamp = Bundle(for: Bundled.self).bundleURL.deletingLastPathComponent()
        .appending(path: "redlamp")

    private struct Run {
        var status: Int32
        var output: String
        var errors: String
    }

    /// `redlamp library` with `arguments`, its home `home` where it's given.
    private static func run(_ arguments: [String], in scratch: URL, home: URL? = nil) async throws -> Run {
        try #require(FileManager.default.isExecutableFile(atPath: redlamp.path), "redlamp isn't built beside the tests")
        let name = UUID().uuidString
        let output = scratch.appending(path: "\(name).out"), errors = scratch.appending(path: "\(name).err")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let process = Process()
        process.executableURL = redlamp
        process.arguments = ["library"] + arguments
        if let home {
            process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path]) {
                $1
            }
        }
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

    /// A JPEG of 8 by 8 pixels whose EXIF orientation is `orientation`, from `camera` where it's given.
    private static func jpeg(at url: URL, orientation: Int, camera: (make: String, model: String)? = nil) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if let camera {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFMake: camera.make, kCGImagePropertyTIFFModel: camera.model,
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }

    /// A catalog of `photos` in the root folder `root`, each with Lightroom's rotation code and its settings, with
    /// the tables and columns the census reads.
    private static func catalog(at url: URL, root: String, photos: [(name: String, code: String, settings: String)])
        throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        func text(_ value: String) -> String {
            "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
        }
        var sql = """
        CREATE TABLE Adobe_variablesTable (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, name, value);
        CREATE TABLE AgLibraryRootFolder (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
          absolutePath UNIQUE NOT NULL DEFAULT '', name NOT NULL DEFAULT '', relativePathFromCatalog);
        CREATE TABLE AgLibraryFolder (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
          pathFromRoot NOT NULL DEFAULT '', rootFolder INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE AgLibraryFile (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
          baseName NOT NULL DEFAULT '', extension NOT NULL DEFAULT '', folder INTEGER NOT NULL DEFAULT 0,
          idx_filename NOT NULL DEFAULT '', sidecarExtensions);
        CREATE TABLE Adobe_images (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL, colorLabels NOT NULL
          DEFAULT '', copyName, fileHeight, fileWidth, masterImage INTEGER, orientation, pick NOT NULL DEFAULT 0,
          rating, rootFile INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE Adobe_imageDevelopSettings (id_local INTEGER PRIMARY KEY, digest, hasDevelopAdjustments,
          image INTEGER, processVersion, text);
        CREATE TABLE Adobe_libraryImageDevelopSnapshot (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
          image INTEGER, name, snapshotID, text);
        CREATE TABLE Adobe_libraryImageDevelopHistoryStep (id_local INTEGER PRIMARY KEY, id_global UNIQUE NOT NULL,
          image INTEGER, name, text);
        INSERT INTO Adobe_variablesTable VALUES (1, 'v', 'Adobe_DBVersion', '1300025');
        INSERT INTO AgLibraryRootFolder VALUES (2, 'r', \(text(root)), 'Photos', NULL);
        INSERT INTO AgLibraryFolder VALUES (3, 'f', '', 2);

        """
        for (place, photo) in photos.enumerated() {
            let file = 10 + place * 3, image = file + 1
            let stem = (photo.name as NSString).deletingPathExtension, ext = (photo.name as NSString).pathExtension
            sql += """
            INSERT INTO AgLibraryFile VALUES (\(file), 'file\(file)', \(text(stem)), \(text(ext)), 3,
              \(text(photo.name)), NULL);
            INSERT INTO Adobe_images VALUES (\(image), 'image\(image)', '', NULL, 6000, 4000, NULL,
              \(text(photo.code)), 0, NULL, \(file));
            INSERT INTO Adobe_imageDevelopSettings VALUES (\(image + 1), 'digest', 1, \(image), '11.0',
              \(text(photo.settings)));
            INSERT INTO Adobe_libraryImageDevelopHistoryStep VALUES (\(image + 1), 'step\(image)', \(image), 'Import',
              \(text(photo.settings)));

            """
        }
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(database) }
        try #require(
            sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK,
            "\(String(cString: sqlite3_errmsg(database)))",
        )
    }

    @Test func `the census counts a catalog's edits and pairs its rotations with the library's files, naming none`(
    ) async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "redlamp-census-\(UUID().uuidString)")
        let photos = scratch.appending(path: "Smith Wedding")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try Self.jpeg(at: photos.appending(path: "Smith_0001.jpg"), orientation: 1)
        try Self.jpeg(at: photos.appending(path: "Smith_0002.jpg"), orientation: 6)
        let index = scratch.appending(path: "Library/Index.sqlite")
        try FileManager.default.createDirectory(
            at: index.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let indexed = try await Self.run(["index", photos.path, "--index", index.path], in: scratch)
        #expect(indexed.status == 0, "\(indexed.errors)")

        let catalog = scratch.appending(path: "Lightroom/Lightroom Catalog.lrcat")
        try Self.catalog(at: catalog, root: photos.standardizedFileURL.path + "/", photos: [
            (
                "Smith_0001.jpg",
                "AB",
                #"s = { ProcessVersion = "11.0", Exposure2012 = 0.4567, CameraProfile = "Smith" }"#,
            ),
            (
                "Smith_0002.jpg",
                "BC",
                #"s = { ProcessVersion = "11.0", Exposure2012 = 0, CameraProfile = "Adobe Standard" }"#,
            ),
        ])
        let json = try await Self.run(
            ["lightroom", catalog.path, "--census", "--index", index.path, "--json"],
            in: scratch,
        )
        #expect(json.status == 0, "\(json.errors)")
        let census = try #require(try JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [String: Any])
        #expect(census["photos"] as? Int == 2 && census["found"] as? Int == 2 && census["paired"] as? Bool == true)
        #expect(census["processVersions"] as? [String: Int] == ["11.0": 2])
        #expect(census["profiles"] as? [String: Int] == ["Adobe Standard": 1, "other": 1])
        #expect(census["historySteps"] as? Int == 2)
        let rotations = try #require(census["rotations"] as? [[String: Any]])
        #expect(rotations.map { $0["code"] as? String } == ["AB", "BC"])
        #expect(rotations.map { $0["orientations"] as? [String: Int] } == [["1": 1], ["6": 1]])

        let text = try await Self.run(["lightroom", catalog.path, "--census", "--index", index.path], in: scratch)
        #expect(text.status == 0, "\(text.errors)")
        #expect(text.output.contains("    AB: 1 photo; 1 in the library, EXIF 1: 1"))
        #expect(text.output.contains("    BC: 1 photo; 1 in the library, EXIF 6: 1"))
        #expect(text.output.contains("    Exposure2012: 2, 2 changed"), "two values, neither shared")
        for secret in ["Smith", scratch.path, "0.4567", "Lightroom Catalog.lrcat"] {
            #expect(!text.output.contains(secret) && !json.output.contains(secret), "the census names “\(secret)”")
        }
    }

    @Test func `an import names the Adobe profile Camera Raw's folder holds for a raw's camera, else Redlamp's look`(
    ) async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "redlamp-profiles-\(UUID().uuidString)")
        let photos = scratch.appending(path: "Shoot")
        let home = scratch.appending(path: "Home")
        let profiles = home.appending(path: "Library/Application Support/Adobe/CameraRaw/CameraProfiles")
        let index = scratch.appending(path: "Library/Index.sqlite")
        for folder in [photos, profiles, index.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        // Cameras no Adobe profile installed on this Mac is for, as JPEGs named as raws, which ImageIO reads.
        try SyntheticCameraProfiles.dcp(
            name: "Adobe Standard", camera: "Redlamp Testcam One",
            colorMatrices: [[0.6722, -0.0635, -0.0963, -0.4287, 1.2460, 0.2028, -0.0908, 0.2162, 0.5668]],
            illuminants: [21],
        ).write(to: profiles.appending(path: "Testcam One.dcp"))
        let own = photos.appending(path: "TC1_0001.DNG"), standIn = photos.appending(path: "TC2_0001.DNG")
        try Self.jpeg(at: own, orientation: 1, camera: ("Redlamp", "Testcam One"))
        try Self.jpeg(at: standIn, orientation: 1, camera: ("Redlamp", "Testcam Two"))
        let catalog = scratch.appending(path: "Lightroom/Lightroom Catalog.lrcat")
        let settings = #"s = { ProcessVersion = "11.0", Exposure2012 = 0.5, CameraProfile = "Adobe Standard" }"#
        try Self.catalog(at: catalog, root: photos.standardizedFileURL.path + "/", photos: [
            ("TC1_0001.DNG", "AB", settings), ("TC2_0001.DNG", "AB", settings),
        ])

        let applied = try await Self.run(
            ["lightroom", catalog.path, "--index", index.path, "--apply", "--json"], in: scratch, home: home,
        )
        #expect(applied.status == 0, "\(applied.errors)")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(applied.output.utf8)) as? [String: Any])
        let edits = try #require((json["report"] as? [String: Any])?["edits"] as? [String: Any])
        #expect(edits["photos"] as? Int == 2 && edits["ownProfiles"] as? Int == 1)
        #expect(edits["standIns"] as? [String: Int] == ["Adobe Standard": 1])
        let ownLook = try #require(SidecarStore().load(for: own)).recipe.baseLook
        #expect(ownLook.isAdobeProfile && ownLook.name == "Adobe Standard")
        let standInLook = try #require(SidecarStore().load(for: standIn)).recipe
        #expect(!standInLook.baseLook.isAdobeProfile && standInLook[.exposure] == 0.5)
    }

    @Test func `an import brings a virtual copy across as a version of its photo, and --undo takes it back`(
    ) async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "redlamp-copies-\(UUID().uuidString)")
        let photos = scratch.appending(path: "Shoot")
        let index = scratch.appending(path: "Library/Index.sqlite")
        for folder in [photos, index.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let photo = photos.appending(path: "Shoot_0001.jpg")
        try Self.jpeg(at: photo, orientation: 1)
        let catalog = scratch.appending(path: "Lightroom/Lightroom Catalog.lrcat")
        try Self.catalog(at: catalog, root: photos.standardizedFileURL.path + "/", photos: [
            ("Shoot_0001.jpg", "AB", #"s = { ProcessVersion = "11.0", Exposure2012 = 0.5 }"#),
        ])
        var database: OpaquePointer?
        try #require(sqlite3_open(catalog.path, &database) == SQLITE_OK)
        let copied = sqlite3_exec(database, """
        INSERT INTO Adobe_images VALUES (100, 'copy', '', 'Black and white', 6000, 4000, 11, 'AB', 0, 4, 10);
        INSERT INTO Adobe_imageDevelopSettings VALUES (101, 'digest', 1, 100, '11.0',
          's = { ProcessVersion = "11.0", Exposure2012 = -0.5 }');
        """, nil, nil, nil)
        sqlite3_close(database)
        try #require(copied == SQLITE_OK)

        let applied = try await Self.run(["lightroom", catalog.path, "--index", index.path, "--apply"], in: scratch)
        #expect(applied.status == 0, "\(applied.errors)")
        #expect(applied.output.contains("virtual copies: 1, which come across as versions of their photos"))
        #expect(!applied.output.contains("    virtual copies (1)"), "not among what stays behind")
        let sidecar = try #require(SidecarStore().load(for: photo))
        #expect(sidecar.recipe[.exposure] == 0.5)
        let version = try #require(sidecar.versions.first)
        #expect(version.name == "Black and white" && version.recipe[.exposure] == -0.5)
        #expect(version.metadata?.rating == 4 && version.recipe.provenance?.photo == 100)

        let undone = try await Self.run(["lightroom", "--undo", "--index", index.path], in: scratch)
        #expect(undone.status == 0, "\(undone.errors)")
        #expect(SidecarStore().load(for: photo) == nil, "the edit and the version are taken back")
    }

    @Test func `the census takes no --apply or --undo, and an --index that isn't there is refused`() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "redlamp-census-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let catalog = scratch.appending(path: "Lightroom Catalog.lrcat")
        try Self.catalog(at: catalog, root: scratch.path + "/", photos: [("A.jpg", "AB", "s = {}")])
        for other in ["--apply", "--undo"] {
            let refused = try await Self.run(["lightroom", catalog.path, "--census", other], in: scratch)
            #expect(refused.status == 1 && refused.errors.contains("--census only counts"), "\(other)")
        }
        let missing = scratch.appending(path: "None/Index.sqlite")
        let unindexed = try await Self.run(
            ["lightroom", catalog.path, "--census", "--index", missing.path], in: scratch,
        )
        #expect(unindexed.status == 1 && unindexed.errors.contains("no index at"))
        #expect(!FileManager.default.fileExists(atPath: missing.path), "no index is made")
    }
}
