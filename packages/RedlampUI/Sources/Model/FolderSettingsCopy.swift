import Foundation

/// A copy of the settings that name folders, with their bookmarks, in Redlamp's own folder (ARC-17): the
/// working set, the import's destination and backup, the export presets and Export with Previous. When the
/// App Sandbox first starts, macOS moves the app's settings into its container, and a setting written
/// moments before can stay behind; the copy moves with Redlamp's folder, and the sandboxed app takes from it
/// the settings it lacks (`restoreMissing`). Written at launch, a moment after any of them changes, and as
/// the app quits.
@MainActor
public final class FolderSettingsCopy {
    /// The settings it copies.
    static let keys = [
        FolderLibrary.Key.roots, FolderLibrary.Key.open, ImportPreferences.settingsKey,
        ImportPreferences.destinationChosenKey, ImportPreferences.bookmarksKey, ExportPresetStore.Keys.presets,
        ExportPresetStore.Keys.previous, ExportPresetStore.Keys.previousPreset, ExportPresetStore.Keys.bookmarks,
    ]

    /// `~/Library/Application Support/Redlamp/Folders.plist`.
    public nonisolated static var standard: URL {
        URL.applicationSupportDirectory.appending(path: "Redlamp/Folders.plist")
    }

    let url: URL
    private let defaults: UserDefaults
    /// What the copy holds, as last written.
    private var written: NSDictionary?
    private var observation: (any NSObjectProtocol)?
    private var waiting: Task<Void, Never>?

    public init(url: URL = FolderSettingsCopy.standard, defaults: UserDefaults = .standard) {
        self.url = url
        self.defaults = defaults
    }

    isolated deinit {
        waiting?.cancel()
        if let observation {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    /// Writes the copy, and writes it again a moment after any of the settings changes.
    public func start() {
        write()
        guard observation == nil else { return }
        observation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
    }

    /// Writes the settings as they are now, unless the copy holds them already.
    public func write() {
        waiting?.cancel()
        waiting = nil
        var values: [String: Any] = [:]
        for key in Self.keys {
            values[key] = defaults.object(forKey: key)
        }
        let copy = NSDictionary(dictionary: values)
        guard written.map({ !$0.isEqual(to: values) }) ?? true,
              let data = try? PropertyListSerialization.data(fromPropertyList: copy, format: .binary, options: 0)
        else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: url, options: .atomic)) != nil {
            written = copy
        }
    }

    private func changed() {
        guard waiting == nil else { return }
        waiting = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    /// Sets in `defaults` each of the settings it lacks that the copy at `url` holds, before anything reads them,
    /// and returns their keys: what the App Sandbox's first launch does.
    @discardableResult
    public static func restoreMissing(from url: URL = standard, into defaults: UserDefaults = .standard) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let copy = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        var restored: [String] = []
        for key in keys where defaults.object(forKey: key) == nil {
            guard let value = copy[key] else { continue }
            defaults.set(value, forKey: key)
            restored.append(key)
        }
        return restored
    }
}
