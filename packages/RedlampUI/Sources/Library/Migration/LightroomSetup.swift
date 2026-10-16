import Foundation
import RedlampLibrary
import RedlampRecipes
import Synchronization

/// What File › Import from Lightroom Classic… finds of Lightroom Classic on this Mac before anything comes across
/// (EDT-34): the catalog Lightroom last used, the presets in Camera Raw's Settings folder, and the Adobe camera and
/// lens profiles Redlamp reads where they are (TON-51, LNS-16, DEC-85). Finding lists folders and reads Lightroom's
/// preferences and the Settings folder's XMP files, which hold presets and profiles alike: no catalog is opened, and
/// the other camera and lens profiles are counted by their files' names.
@_spi(Harness) public struct LightroomSetup: Sendable, Equatable {
    /// Where finding looks: this Mac's folders, or a test home's in their place.
    public struct Locations: Sendable, Equatable {
        /// The photographer's home: Lightroom's preferences, Pictures and their own Camera Raw folder.
        public var home: URL
        /// Camera Raw's own folder, which Lightroom Classic and Photoshop's Camera Raw install.
        public var cameraRaw: URL
        /// Redlamp's Lens Profiles folder.
        public var lensProfiles: URL
        /// The files and folders chosen with Choose Camera Profiles….
        public var chosenCameraProfiles: [URL]

        public init(home: URL, cameraRaw: URL, lensProfiles: URL, chosenCameraProfiles: [URL] = []) {
            self.home = home
            self.cameraRaw = cameraRaw
            self.lensProfiles = lensProfiles
            self.chosenCameraProfiles = chosenCameraProfiles
        }

        /// This Mac's, where `CameraProfileLibrary` and `LCPProfileLibrary` read them.
        static func standard(chosenCameraProfiles: [URL]) -> Locations {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            return Locations(
                home: FileManager.default.homeDirectoryForCurrentUser,
                cameraRaw: URL(fileURLWithPath: "/Library/Application Support/Adobe/CameraRaw", isDirectory: true),
                lensProfiles: support.appending(path: "Redlamp/Lens Profiles", directoryHint: .isDirectory),
                chosenCameraProfiles: chosenCameraProfiles,
            )
        }

        /// The photographer's Camera Raw folder: their presets and profiles in `Settings`, their camera profiles in
        /// `CameraProfiles` and their lens profiles in `LensProfiles`.
        public var userCameraRaw: URL {
            home.appending(path: "Library/Application Support/Adobe/CameraRaw", directoryHint: .isDirectory)
        }

        /// Where Lightroom Classic keeps the photographer's presets, and the profiles they add.
        public var settings: URL {
            userCameraRaw.appending(path: "Settings", directoryHint: .isDirectory)
        }

        /// Where Lightroom Classic makes its first catalog.
        public var pictures: URL {
            home.appending(path: "Pictures/Lightroom", directoryHint: .isDirectory)
        }
    }

    /// A catalog, as its folder lists it: nothing is read from inside it.
    public struct Catalog: Sendable, Equatable {
        public enum Source: Sendable, Equatable {
            /// The one Lightroom Classic's preferences say it opened last.
            case lastUsed
            /// The newest in Pictures › Lightroom.
            case pictures
            /// Chosen with Choose….
            case chosen
        }

        public var url: URL
        public var source: Source
        /// In bytes.
        public var size: Int?
        public var modified: Date?
        /// Lightroom Classic has it open: its lock file is beside it.
        public var isOpenInLightroom: Bool

        static func at(_ url: URL, source: Source) -> Catalog {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return Catalog(
                url: url, source: source, size: values?.fileSize, modified: values?.contentModificationDate,
                isOpenInLightroom: FileManager.default.fileExists(atPath: LightroomCatalog.lockURL(of: url).path),
            )
        }
    }

    /// A folder a part's files were found in, and how many.
    public struct Place: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// Camera Raw's own folder, which Lightroom Classic and Camera Raw install.
            case cameraRaw
            /// The photographer's Camera Raw folder.
            case userCameraRaw
            /// The files and folders chosen with Choose Camera Profiles….
            case chosen
            /// Redlamp's Lens Profiles folder.
            case redlamp
        }

        public var kind: Kind
        /// Nil for the files chosen, which can be anywhere.
        public var folder: URL?
        public var count: Int
        /// False where the folder is there but can't be listed, as in the App Sandbox until it's chosen.
        public var isReadable = true
    }

    public var catalog: Catalog?
    /// Camera Raw's Settings folder, and the presets in it, each a file EDT-11's import takes, in the order
    /// `RecipeLibrary.presets(in:)` lists a folder's.
    public var presetsFolder: URL
    public var presets: [URL]
    /// The groups Lightroom Classic shows the presets in, those in none counting as one, as its User Presets.
    public var presetGroups = 0
    public var presetsReadable = true
    /// Where camera profiles are, Camera Raw's first; only places holding some, or that can't be read.
    public var cameraProfiles: [Place]
    public var lensProfiles: [Place]

    public var cameraProfileCount: Int {
        cameraProfiles.reduce(0) { $0 + $1.count }
    }

    public var lensProfileCount: Int {
        lensProfiles.reduce(0) { $0 + $1.count }
    }

    /// Looks in `locations`, off the main thread: Camera Raw's folders hold thousands of profiles.
    public static func find(_ locations: Locations) -> LightroomSetup {
        let settings = settings(in: locations.settings)
        let cameraRaw = locations.cameraRaw
        let installedProfiles = [
            files(in: cameraRaw.appending(path: "CameraProfiles", directoryHint: .isDirectory), extensions: ["dcp"]),
            files(in: cameraRaw.appending(path: "Settings/Adobe/Profiles", directoryHint: .isDirectory), extensions: [
                "xmp",
            ]),
        ]
        let ownProfiles = files(
            in: locations.userCameraRaw.appending(path: "CameraProfiles", directoryHint: .isDirectory),
            extensions: ["dcp"],
        )
        let chosen = locations.chosenCameraProfiles.map { files(in: $0, extensions: ["dcp", "xmp"]) }
        let cameraProfiles = [
            Place(
                kind: .cameraRaw, folder: cameraRaw, count: installedProfiles.reduce(0) { $0 + $1.urls.count },
                isReadable: installedProfiles.allSatisfy(\.readable),
            ),
            Place(
                kind: .userCameraRaw, folder: locations.userCameraRaw,
                count: ownProfiles.urls.count + settings.profiles,
                isReadable: ownProfiles.readable && settings.readable,
            ),
            Place(kind: .chosen, count: chosen.reduce(0) { $0 + $1.urls.count }),
        ]
        let lensFolders: [(Place.Kind, URL)] = [
            (.cameraRaw, cameraRaw.appending(path: "LensProfiles/1.0", directoryHint: .isDirectory)),
            (.userCameraRaw, locations.userCameraRaw.appending(path: "LensProfiles", directoryHint: .isDirectory)),
            (.redlamp, locations.lensProfiles),
        ]
        let lensProfiles = lensFolders.map { kind, folder in
            let found = files(in: folder, extensions: ["lcp"])
            return Place(kind: kind, folder: folder, count: found.urls.count, isReadable: found.readable)
        }
        return LightroomSetup(
            catalog: lastUsedCatalog(home: locations.home) ?? newestCatalog(in: locations.pictures),
            presetsFolder: locations.settings, presets: settings.presets, presetGroups: settings.groups,
            presetsReadable: settings.readable,
            cameraProfiles: cameraProfiles.filter { $0.count > 0 || !$0.isReadable },
            lensProfiles: lensProfiles.filter { $0.count > 0 || !$0.isReadable },
        )
    }

    // MARK: - The catalog

    /// The first catalog Lightroom's preferences name that's on this Mac: a catalog made on Windows, or on a disk
    /// that isn't connected, isn't.
    static func lastUsedCatalog(home: URL) -> Catalog? {
        for file in LightroomPreferences.files(home: home) {
            for path in LightroomPreferences.catalogs(in: file) where path.lowercased().hasSuffix(".lrcat") {
                var isFolder: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue {
                    return .at(URL(fileURLWithPath: path), source: .lastUsed)
                }
            }
        }
        return nil
    }

    /// The catalog in `folder` that changed last; its subfolders, Backups among them, aren't looked in.
    static func newestCatalog(in folder: URL) -> Catalog? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
        )) ?? []
        let catalogs = entries.compactMap { url -> (url: URL, modified: Date)? in
            guard url.pathExtension.lowercased() == "lrcat", let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }
        return catalogs.max { $0.modified < $1.modified }.map { .at($0.url, source: .pictures) }
    }

    // MARK: - Folders

    private enum SettingsFile: Equatable {
        case other, profile
        /// A preset, in the group its `crs:Group` names; nil for one in none.
        case preset(group: String?)
    }

    /// The Settings folder's XMP files: the presets, by path, the groups they're in, and how many files are
    /// profiles, which `CameraProfileLibrary` reads there too. Each file is read whole, on every core, as EDT-11's
    /// import reads it.
    static func settings(in folder: URL) -> (presets: [URL], groups: Int, profiles: Int, readable: Bool) {
        let listed = files(in: folder, extensions: ["xmp"])
        let urls = listed.urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let kinds = Mutex([SettingsFile](repeating: .other, count: urls.count))
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let kind = kind(of: urls[index])
            kinds.withLock { $0[index] = kind }
        }
        let found = kinds.withLock { $0 }
        let groups = found.compactMap { kind -> String? in
            guard case let .preset(group) = kind else { return nil }
            return group ?? ""
        }
        return (
            zip(urls, found).compactMap { url, kind in
                guard case .preset = kind else { return nil }
                return url
            },
            Set(groups).count, found.count(where: { $0 == .profile }), listed.readable,
        )
    }

    private static func kind(of url: URL) -> SettingsFile {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= RecipeValidator.maximumFileSize, let data = try? Data(contentsOf: url)
        else { return .other }
        if LightroomPreset.isPreset(data) {
            return .preset(group: group(in: data))
        }
        let head = data.prefix(64 << 10)
        let look = ["crs:PresetType=\"Look\"", "<crs:PresetType>Look</crs:PresetType>"]
        return look.contains { head.range(of: Data($0.utf8)) != nil } ? .profile : .other
    }

    /// The group a preset's `crs:Group` names, the first of its languages: Lightroom Classic writes it as an
    /// `rdf:Alt`, which XMP keeps in an element of its own.
    static func group(in data: Data) -> String? {
        guard let start = data.range(of: Data("<crs:Group>".utf8)),
              let end = data.range(of: Data("</crs:Group>".utf8), in: start.upperBound ..< data.endIndex),
              let item = data.range(of: Data("<rdf:li".utf8), in: start.upperBound ..< end.lowerBound),
              let open = data[item.upperBound ..< end.lowerBound].firstIndex(of: UInt8(ascii: ">")),
              let close = data.range(of: Data("</rdf:li>".utf8), in: open + 1 ..< end.lowerBound)
        else { return nil }
        let name = String(decoding: data[open + 1 ..< close.lowerBound], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The files with one of `extensions` in `url` and its subfolders, or `url` itself when it's such a file;
    /// none, and not readable, where the folder is there but can't be listed.
    static func files(in url: URL, extensions: Set<String>) -> (urls: [URL], readable: Bool) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return ([], true) }
        guard isFolder.boolValue else {
            return (extensions.contains(url.pathExtension.lowercased()) ? [url] : [], true)
        }
        guard (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil else { return ([], false) }
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [], options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true },
        )
        var urls: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            if extensions.contains(file.pathExtension.lowercased()) {
                urls.append(file)
            }
        }
        return (urls, true)
    }
}

/// Lightroom Classic's preferences, read for the catalogs they name: the startup preferences, which Lightroom reads
/// first and which override the main ones for its catalogs, and the main preferences. The startup file is a Lua table
/// (`.agprefs`); the main one a property list. In both, `libraryToLoad20` is the catalog Lightroom opens at launch and
/// `recentLibraries20` a Lua table, in a string, of those it opened, newest first.
enum LightroomPreferences {
    /// Lightroom Classic's, then Lightroom 6's, each startup file before its main preferences.
    static func files(home: URL) -> [URL] {
        let folder = home.appending(
            path: "Library/Application Support/Adobe/Lightroom/Preferences",
            directoryHint: .isDirectory,
        )
        let main = home.appending(path: "Library/Preferences", directoryHint: .isDirectory)
        return [
            folder.appending(path: "Lightroom Classic CC 7 Startup Preferences.agprefs"),
            main.appending(path: "com.adobe.LightroomClassicCC7.plist"),
            folder.appending(path: "Lightroom 6 Startup Preferences.agprefs"),
            main.appending(path: "com.adobe.Lightroom6.plist"),
        ]
    }

    /// The catalogs a preferences file names, the one Lightroom opens at launch first, each once.
    static func catalogs(in url: URL) -> [String] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 << 20,
              let data = try? Data(contentsOf: url)
        else { return [] }
        guard url.pathExtension.lowercased() == "plist" else { return catalogs(agprefs: data) }
        guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }
        let recent: [String] = switch values["recentLibraries20"] {
        case let text as String: strings(in: Array(text.utf8))
        case let list as [Any]: list.compactMap { $0 as? String }
        default: []
        }
        return unique([values["libraryToLoad20"] as? String] + recent)
    }

    /// The catalogs a startup preferences file names.
    static func catalogs(agprefs data: Data) -> [String] {
        let bytes = Array(data)
        let recent = value(of: "recentLibraries20", in: bytes).map { strings(in: Array($0.utf8)) } ?? []
        return unique([value(of: "libraryToLoad20", in: bytes)] + recent)
    }

    private static func unique(_ paths: [String?]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard let path, !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
    }

    /// The string `key = "…"` sets, the first time it's set.
    static func value(of key: String, in bytes: [UInt8]) -> String? {
        let name = Array(key.utf8)
        var start = 0
        while start + name.count <= bytes.count {
            guard let found = firstIndex(of: name, in: bytes, from: start) else { return nil }
            start = found + name.count
            let joined = found > 0 && isNamePart(bytes[found - 1]) || start < bytes.count && isNamePart(bytes[start])
            guard !joined else { continue }
            var index = skipSpaces(bytes, from: start)
            guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else { continue }
            index = skipSpaces(bytes, from: index + 1)
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'")
            else { continue }
            return string(in: bytes, at: index)?.value
        }
        return nil
    }

    /// Every quoted string in a Lua table's text, in order.
    static func strings(in bytes: [UInt8]) -> [String] {
        var strings: [String] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\"") || bytes[index] == UInt8(ascii: "'"),
               let read = string(in: bytes, at: index) {
                strings.append(read.value)
                index = read.end
            } else {
                index += 1
            }
        }
        return strings
    }

    /// The Lua string whose opening quote is at `start`, its escapes read as Lua 5.1 reads them, and the index after
    /// its closing quote; nil where it doesn't end on its line.
    static func string(in bytes: [UInt8], at start: Int) -> (value: String, end: Int)? {
        let quote = bytes[start]
        var value: [UInt8] = []
        var index = start + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote {
                return (String(decoding: value, as: UTF8.self), index + 1)
            }
            guard byte != UInt8(ascii: "\n") else { return nil }
            guard byte == UInt8(ascii: "\\"), index + 1 < bytes.count else {
                value.append(byte)
                index += 1
                continue
            }
            index += 1
            let escape = bytes[index]
            switch escape {
            case UInt8(ascii: "n"), UInt8(ascii: "\n"): value.append(10)
            case UInt8(ascii: "\r"):
                value.append(10)
                if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "\n") {
                    index += 1
                }
            case UInt8(ascii: "t"): value.append(9)
            case UInt8(ascii: "r"): value.append(13)
            case UInt8(ascii: "a"): value.append(7)
            case UInt8(ascii: "b"): value.append(8)
            case UInt8(ascii: "f"): value.append(12)
            case UInt8(ascii: "v"): value.append(11)
            case UInt8(ascii: "0") ... UInt8(ascii: "9"):
                var number = 0
                var digits = 0
                while digits < 3, index < bytes.count,
                      (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(bytes[index]) {
                    number = number * 10 + Int(bytes[index] - UInt8(ascii: "0"))
                    digits += 1
                    index += 1
                }
                value.append(UInt8(truncatingIfNeeded: number))
                continue
            default: value.append(escape)
            }
            index += 1
        }
        return nil
    }

    private static func firstIndex(of needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard let first = needle.first, needle.count <= bytes.count else { return nil }
        var index = start
        while index + needle.count <= bytes.count {
            if bytes[index] == first, bytes[index ..< index + needle.count].elementsEqual(needle) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func skipSpaces(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, [UInt8(ascii: " "), UInt8(ascii: "\t")].contains(bytes[index]) {
            index += 1
        }
        return index
    }

    private static func isNamePart(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_") || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
            || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte | 0x20)
    }
}
