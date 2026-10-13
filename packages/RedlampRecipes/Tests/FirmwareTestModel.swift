import Foundation
@testable import RedlampRecipes

/// The firmware model's folder for tests: `REDLAMP_FIRMWARE_MODEL`, or the default folder.
/// Tests that need it are skipped on a Mac without it.
enum FirmwareTestModel {
    static let folder = FirmwareFilmModel.environmentFolder ?? FirmwareFilmModel.defaultFolder
    static let vectorsURL = folder.appendingPathComponent("test_vectors.json")
    static let isAvailable = FirmwareFilmModel.isAvailable(at: folder)
        && FileManager.default.fileExists(atPath: vectorsURL.path)

    static func model() throws -> FirmwareFilmModel {
        try FirmwareFilmModel.shared(at: folder)
    }
}
