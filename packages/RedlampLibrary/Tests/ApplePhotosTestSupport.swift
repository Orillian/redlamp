import Foundation
import Testing
@testable import RedlampLibrary

/// The sample Photos library in `tests/fixtures/apple-photos`: an album, a folder of two albums, a smart album
/// and a shared album, over favourites, a RAW+JPEG pair, a ProRAW DNG, a photo edited in Photos with its date
/// changed, a Live Photo only in iCloud, a burst, a video, a hidden photo and a shared album's reduced copy.
enum SamplePhotos {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "tests/fixtures/apple-photos")
    static let manifest = folder.appending(path: "manifest.json")

    /// The photos' local identifiers, by their files' names.
    static let edited = "8A1F0002-0000-4000-8000-000000000002/L0/001"
    static let tram = "8A1F0001-0000-4000-8000-000000000001/L0/001"
    static let live = "8A1F0003-0000-4000-8000-000000000003/L0/001"
    static let pair = "8A1F0004-0000-4000-8000-000000000004/L0/001"
    static let dng = "8A1F0005-0000-4000-8000-000000000005/L0/001"
    static let burstKey = "8A1F0010-0000-4000-8000-000000000010/L0/001"
    static let burstFrame = "8A1F0011-0000-4000-8000-000000000011/L0/001"
    static let burstPick = "8A1F0012-0000-4000-8000-000000000012/L0/001"
    static let video = "8A1F0020-0000-4000-8000-000000000020/L0/001"
    static let hidden = "8A1F0030-0000-4000-8000-000000000030/L0/001"
    static let shared = "8A1F0040-0000-4000-8000-000000000040/L0/001"

    static func library(macOS: Int? = nil) throws -> SimulatedPhotosLibrary {
        try SimulatedPhotosLibrary(manifest: manifest, macOS: macOS)
    }

    /// Whether the CC0 raws the pair and the DNG point at are there.
    static var hasRaws: Bool {
        FileManager.default.fileExists(atPath: FixtureTests.rawFolder.appending(path: "DSC_0750.NEF").path)
            && FileManager.default.fileExists(atPath: FixtureTests.rawFolder.appending(path: "IMG_1361.DNG").path)
    }

    /// A manifest of its own in `folder`, with `assets` over the sample's files.
    static func manifest(
        in folder: URL, collections: [[String: Any]], assets: [[String: Any]], extra: [String: Any] = [:],
    ) throws -> URL {
        var object: [String: Any] = [
            "format": SimulatedPhotosLibrary.format, "version": 1, "collections": collections, "assets": assets,
        ]
        object.merge(extra) { $1 }
        let url = folder.appending(path: "manifest.json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        return url
    }
}
