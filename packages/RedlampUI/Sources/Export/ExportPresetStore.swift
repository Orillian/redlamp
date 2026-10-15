import Foundation
import Observation
import RedlampDocument

/// Export presets and the last export's settings, kept in user defaults, with a bookmark for each folder
/// they export to, which reaches it in the App Sandbox (ARC-17).
@MainActor @Observable
public final class ExportPresetStore {
    /// The settings of the last export, which Export with Previous repeats.
    public private(set) var previous: ExportSettings?
    /// The preset the last export started from, so the dialog can show its name.
    public private(set) var previousPresetID: UUID?
    public private(set) var userPresets: [ExportPreset]
    /// The bookmarks of the folders the presets and Export with Previous export to.
    @ObservationIgnored private(set) var bookmarks: FolderBookmarks

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        previous = defaults.data(forKey: Keys.previous).flatMap { try? JSONDecoder().decode(
            ExportSettings.self,
            from: $0,
        ) }
        previousPresetID = defaults.string(forKey: Keys.previousPreset).flatMap(UUID.init(uuidString:))
        userPresets = defaults.data(forKey: Keys.presets)
            .flatMap { try? JSONDecoder().decode([ExportPreset].self, from: $0) } ?? []
        bookmarks = defaults.data(forKey: Keys.bookmarks)
            .flatMap { try? JSONDecoder().decode(FolderBookmarks.self, from: $0) } ?? FolderBookmarks()
    }

    /// Built-ins first, then the user's presets in the order they were saved.
    public var presets: [ExportPreset] {
        ExportPreset.builtIns + userPresets
    }

    public func preset(_ id: UUID?) -> ExportPreset? {
        id.flatMap { id in presets.first { $0.id == id } }
    }

    /// What the dialog opens with: the last export, or the first built-in.
    public var initialSettings: ExportSettings {
        previous ?? ExportPreset.builtIns[0].settings
    }

    public var initialPresetID: UUID? {
        previous == nil ? ExportPreset.builtIns[0].id : preset(previousPresetID)?.id
    }

    /// An export just started with `settings`: its folder, chosen in the dialog's panel this session or kept
    /// from before, gets its bookmark while it's reachable.
    public func recordExport(_ settings: ExportSettings, presetID: UUID?) {
        previous = settings
        previousPresetID = presetID
        defaults.set(try? JSONEncoder().encode(settings), forKey: Keys.previous)
        defaults.set(presetID?.uuidString, forKey: Keys.previousPreset)
        remember(settings.destinationFolder)
    }

    /// Saves `settings` under `name`, replacing a preset of the user's with the same name.
    @discardableResult
    public func savePreset(named name: String, settings: ExportSettings) -> ExportPreset {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { remember(settings.destinationFolder) }
        if let index = userPresets
            .firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            userPresets[index].settings = settings
            save()
            return userPresets[index]
        }
        let preset = ExportPreset(name: name, settings: settings)
        userPresets.append(preset)
        save()
        return preset
    }

    public func updatePreset(_ id: UUID, settings: ExportSettings) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[index].settings = settings
        save()
        remember(settings.destinationFolder)
    }

    public func deletePreset(_ id: UUID) {
        userPresets.removeAll { $0.id == id }
        if previousPresetID == id {
            previousPresetID = nil
            defaults.removeObject(forKey: Keys.previousPreset)
        }
        save()
        keepBookmarks()
    }

    /// The folders the presets and Export with Previous export to.
    var folders: [String] {
        ([previous] + userPresets.map(\.settings)).compactMap { $0?.destinationFolder?.path }
    }

    /// Makes the bookmarks of the folders earlier versions exported to, which they didn't keep (ARC-17), at
    /// launch: off the main thread, as a folder may be on a disk that's slow to answer.
    public func bookmarkRemembered() async {
        let lacking = bookmarks.lacking(folders)
        guard !lacking.isEmpty else { return keepBookmarks() }
        let made = await Task.detached(priority: .utility) { FolderBookmarks.make(for: lacking) }.value
        keepBookmarks(adding: made)
    }

    private func remember(_ folder: URL?) {
        if let folder, bookmarks.remember(folder) {
            saveBookmarks()
        }
        keepBookmarks()
    }

    private func keepBookmarks(adding made: [String: Data] = [:]) {
        if bookmarks.keep(folders, adding: made) {
            saveBookmarks()
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(userPresets), forKey: Keys.presets)
    }

    private func saveBookmarks() {
        defaults.set(try? JSONEncoder().encode(bookmarks), forKey: Keys.bookmarks)
    }

    enum Keys {
        static let previous = "exportPrevious"
        static let previousPreset = "exportPreviousPreset"
        static let presets = "exportPresets"
        static let bookmarks = "export.bookmarks"
    }
}
