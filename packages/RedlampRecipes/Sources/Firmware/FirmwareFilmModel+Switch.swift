import Foundation

/// The prototype's switch, off by default: Settings' Prototype tab in the app, an environment
/// variable for the CLI and tests.
public extension FirmwareFilmModel {
    /// A folder, or `1` for `defaultFolder`.
    static let environmentKey = "REDLAMP_FIRMWARE_MODEL"
    /// Whether the app uses the model.
    static let enabledKey = "app.redlamp.firmwareFilmModel"
    /// The folder the app reads it from, when not `defaultFolder`.
    static let folderKey = "app.redlamp.firmwareFilmModelFolder"

    static var defaultFolder: URL {
        URL.homeDirectory.appendingPathComponent("src/redlamp-fujix100v/model")
    }

    /// The folder `REDLAMP_FIRMWARE_MODEL` names, if it's set.
    static var environmentFolder: URL? {
        guard let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty else { return nil }
        return value == "1" ? defaultFolder : URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }

    /// The folder the app's settings name, when the switch is on.
    static func settingsFolder(_ defaults: UserDefaults = .standard) -> URL? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        guard let path = defaults.string(forKey: folderKey), !path.isEmpty else { return defaultFolder }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// The model in `folder`, read once per process.
    static func shared(at folder: URL) throws -> FirmwareFilmModel {
        try Cache.shared.model(at: folder.standardizedFileURL)
    }
}

/// The third of the inner key's three salt pieces (`FirmwareKeySaltA`).
enum FirmwareKeySaltC {
    static let bytes: [UInt8] = [0x6A, 0x0F, 0xC8, 0x53, 0xB2, 0x19, 0xE5, 0x47, 0x8D]
}

private final class Cache: @unchecked Sendable {
    static let shared = Cache()
    private let lock = NSLock()
    private var models: [URL: FirmwareFilmModel] = [:]

    func model(at folder: URL) throws -> FirmwareFilmModel {
        lock.lock()
        defer { lock.unlock() }
        if let model = models[folder] {
            return model
        }
        let model = try FirmwareFilmModel(folder: folder)
        models[folder] = model
        return model
    }
}
