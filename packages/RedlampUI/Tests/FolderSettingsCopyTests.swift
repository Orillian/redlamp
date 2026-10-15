import Foundation
import Testing
@testable import RedlampUI

/// The copy of the settings that name folders in Redlamp's own folder (ARC-17), which the App Sandbox's first launch
/// takes what its settings lack from.
@MainActor
struct FolderSettingsCopyTests {
    private let suite = "folder-settings-copy-\(UUID().uuidString)"
    private let file = FileManager.default.temporaryDirectory
        .appending(path: "folder-settings-\(UUID().uuidString)/Redlamp/Folders.plist")

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suite)!
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent())
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func copied() throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func `the copy holds the settings that name folders, and no others`() throws {
        defer { cleanUp() }
        defaults.set(Data([1, 2]), forKey: "folders.roots")
        defaults.set("/Volumes/Photos/Trip", forKey: "folders.open")
        defaults.set(Data([3]), forKey: "import.bookmarks")
        defaults.set(true, forKey: "import.destinationChosen")
        defaults.set(Data([4]), forKey: "exportPrevious")
        defaults.set("dark", forKey: "theme")

        FolderSettingsCopy(url: file, defaults: defaults).write()
        let copy = try copied()
        #expect(Set(copy.keys) == [
            "folders.roots",
            "folders.open",
            "import.bookmarks",
            "import.destinationChosen",
            "exportPrevious",
        ])
        #expect(copy["folders.roots"] as? Data == Data([1, 2]) && copy["import.destinationChosen"] as? Bool == true)
    }

    @Test func `a change is copied a moment later`() async throws {
        defer { cleanUp() }
        let defaults = defaults
        let copy = FolderSettingsCopy(url: file, defaults: defaults)
        copy.start()
        #expect(try copied().isEmpty)
        defaults.set(Data([5]), forKey: "export.bookmarks")
        for _ in 0 ..< 60 where (try? copied()["export.bookmarks"]) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try copied()["export.bookmarks"] as? Data == Data([5]))
    }

    @Test func `the sandbox's first launch takes from the copy only what its settings lack`() throws {
        defer { cleanUp() }
        defaults.set(Data([1]), forKey: "folders.roots")
        defaults.set(Data([2]), forKey: "import.settings")
        FolderSettingsCopy(url: file, defaults: defaults).write()

        let lacking = "folder-settings-lacking-\(UUID().uuidString)"
        let moved = try #require(UserDefaults(suiteName: lacking))
        defer { UserDefaults().removePersistentDomain(forName: lacking) }
        moved.set(Data([9]), forKey: "import.settings")
        #expect(FolderSettingsCopy.restoreMissing(from: file, into: moved) == ["folders.roots"])
        #expect(moved.data(forKey: "folders.roots") == Data([1]))
        #expect(moved.data(forKey: "import.settings") == Data([9]), "a setting it has stays as it is")
        #expect(FolderSettingsCopy.restoreMissing(from: file.deletingLastPathComponent(), into: moved).isEmpty)
    }
}
