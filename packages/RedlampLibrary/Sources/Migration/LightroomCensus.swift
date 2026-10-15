import Foundation
import RedlampEngineAPI

/// What a Lightroom Classic catalog's edits use, counted over every photo and virtual copy (EDT-23), so that a
/// photographer can share what their catalog holds: it names setting names, the kinds of masks and spots with
/// their subtypes, Adobe's profiles and the camera-matching ones, process versions and Lightroom's rotation
/// codes, and no photo, path, keyword or value. The catalog is read as `LightroomCatalog` reads it, never written.
///
/// A setting's value counts as changed when it isn't the value most of the photos carrying the setting have,
/// which in a catalog of any size is Lightroom's default. A setting whose values all differ, as masks' do, has
/// no such value, and every photo carrying it counts as changed.
public struct LightroomCensus: Sendable, Hashable, Codable {
    /// A setting: the photos and virtual copies carrying it (for a mask's own setting, the masks), and of those
    /// the ones whose value isn't the one most of them have.
    public struct Setting: Sendable, Hashable, Codable {
        public var name: String
        public var carried: Int
        public var changed: Int
    }

    /// A kind of thing photos hold several of: how many there are, and the photos and virtual copies with any.
    public struct Kind: Sendable, Hashable, Codable {
        public var name: String
        public var count: Int
        public var photos: Int
    }

    /// One of Lightroom's rotation codes: the photos and virtual copies with it, and of those whose files the
    /// library has, how many have each EXIF orientation, 1 to 8, or `none` where the index holds none.
    public struct Rotation: Sendable, Hashable, Codable {
        public var code: String
        public var photos: Int
        public var orientations: [String: Int]
    }

    /// The catalog's version, as Lightroom numbers it.
    public var version: String?
    /// The catalog's photos, virtual copies aside.
    public var photos = 0
    public var virtualCopies = 0
    /// The photos and virtual copies with Develop settings, and of those the ones whose settings couldn't be read.
    public var withSettings = 0
    public var unreadable = 0
    /// The photos and virtual copies Lightroom marks as adjusted (`hasDevelopAdjustments`).
    public var adjusted = 0
    /// The photos and virtual copies whose file's size the catalog records.
    public var sizes = 0
    /// The photos and virtual copies whose settings could be read, by their ProcessVersion.
    public var processVersions: [String: Int] = [:]
    public var settings: [Setting] = []
    /// Masks (`MaskGroupBasedCorrections`), and the photos and virtual copies with any.
    public var masks = 0
    public var photosWithMasks = 0
    /// The photos and virtual copies with more masks, or more components, than one of Redlamp's edits holds.
    public var overMaskLimit = 0
    public var overComponentLimit = 0
    /// Masks' components, by kind.
    public var components: [Kind] = []
    /// Masks' own settings, current and earlier masks', by the masks carrying each.
    public var maskSettings: [Setting] = []
    /// Lightroom 10's and earlier masks, by kind.
    public var earlierMasks: [Kind] = []
    /// Spots (`RetouchAreas`), by kind.
    public var spots: [Kind] = []
    /// Process 2010's and earlier spots (`RetouchInfo`), by kind.
    public var earlierSpots: [Kind] = []
    /// The photos and virtual copies with each profile (`CameraProfile`), look (the `Look`'s name) and Upright
    /// mode (`PerspectiveUpright`).
    public var profiles: [String: Int] = [:]
    public var looks: [String: Int] = [:]
    public var upright: [String: Int] = [:]
    public var snapshots = 0
    public var photosWithSnapshots = 0
    public var historySteps = 0
    public var photosWithHistory = 0
    public var rotations: [Rotation] = []
    /// Whether the rotation codes were paired with a library's photos, and of the photos and virtual copies,
    /// those whose files the library has.
    public var paired = false
    public var found = 0
    /// What the catalog lacked or how it was read, in words.
    public var notes: [String] = []

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public extension LightroomCensus {
    /// The census of the catalog at `url`, read off the caller's thread, each rotation code paired with the EXIF
    /// orientations of the files `index` has, found by path as `LightroomPlan` finds them: the roots `moved`
    /// names (by the catalog's paths) are looked for where they went.
    static func make(
        _ url: URL, index: LibraryIndex? = nil, moved: [String: URL] = [:],
    ) async throws -> LightroomCensus {
        let read = try await Task.detached(priority: .userInitiated) { try LightroomCensusReading.read(url) }.value
        var orientations: [Int64: Int?]?
        if let index {
            orientations = try await Self.orientations(of: read.catalog, in: index, moved: moved)
        }
        return LightroomCensus(
            read.tally, version: read.catalog.version, adjusted: read.adjusted, orientations: orientations,
            notes: read.notes,
        )
    }

    /// The EXIF orientation of each photo's file the index has, by the photo's ID in the catalog.
    private static func orientations(
        of catalog: LightroomCatalog, in index: LibraryIndex, moved: [String: URL],
    ) async throws -> [Int64: Int?] {
        var planner = LightroomPlanner(catalog: catalog, moved: moved)
        let library = try await index.read { reader in
            let removed = try Set(reader.removedRoots().values)
            return try reader.roots().map(\.path).filter { !removed.contains($0) }
        }
        planner.locateRoots(library: library)
        let requests = planner.requests()
        let photos = catalog.photos
        let matches = try await index.read { reader in try LightroomPlanner.match(requests, photos, in: reader) }
        var orientations: [Int64: Int?] = [:]
        for (place, match) in matches {
            orientations[photos[place].id] = .some(match.row.orientation)
        }
        return orientations
    }
}

/// A catalog's photos and its edits' tally, read in one opening of it: the census pairs the rotation codes
/// with the library's files afterwards.
struct LightroomCensusReading: Sendable {
    var catalog: LightroomCatalog
    var tally: LightroomCensusTally
    var adjusted: Int
    var notes: [String]

    static func read(
        _ url: URL, partSize: Int = LightroomCatalogReader.developPart,
    ) throws(LightroomCatalogError) -> LightroomCensusReading {
        try LightroomCatalog.opened(url) { reader in
            let catalog = try reader.files(url: url)
            var notes: [String] = []
            var tally = LightroomCensusTally()
            for part in try reader.develop(partSize: partSize, notes: &notes, { LightroomCensusTally($0) }) {
                tally.merge(part)
            }
            if reader.copied {
                notes.append(LightroomCatalogReader.copiedNote)
            }
            return try LightroomCensusReading(
                catalog: catalog, tally: tally, adjusted: reader.editedCount(), notes: notes,
            )
        }
    }
}

extension LightroomCensus {
    /// The census of `tally`, named as `LightroomCensusNames` allows; `orientations` pairs the rotation codes
    /// with the files the library has, by their photos' IDs in the catalog.
    init(
        _ tally: LightroomCensusTally, version: String?, adjusted: Int, orientations: [Int64: Int?]?,
        notes: [String],
    ) {
        self.version = version.map { version in
            let fits = version.utf8.count <= 16 && version.utf8.allSatisfy { byte in
                (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) || byte == UInt8(ascii: ".")
            }
            return fits ? version : LightroomCensusNames.other
        }
        photos = tally.photos
        virtualCopies = tally.virtualCopies
        withSettings = tally.withSettings + tally.unreadable
        unreadable = tally.unreadable
        self.adjusted = adjusted
        sizes = tally.sizes
        for (version, count) in tally.processVersions {
            processVersions[LightroomCensusNames.processVersion(version), default: 0] += count
        }
        settings = Self.settings(tally.settings)
        masks = tally.masks.count
        photosWithMasks = tally.masks.photos
        overMaskLimit = tally.overMasks
        overComponentLimit = tally.overComponents
        components = Self.kinds(tally.components)
        maskSettings = Self.settings(tally.maskSettings)
        earlierMasks = Self.kinds(tally.earlierMasks)
        spots = Self.kinds(tally.spots)
        earlierSpots = Self.kinds(tally.earlierSpots)
        for (name, count) in tally.profiles {
            profiles[LightroomCensusNames.profile(name), default: 0] += count
        }
        for (name, count) in tally.looks {
            looks[LightroomCensusNames.profile(name), default: 0] += count
        }
        for (mode, count) in tally.upright {
            upright[LightroomCensusNames.upright(mode), default: 0] += count
        }
        snapshots = tally.snapshots.count
        photosWithSnapshots = tally.snapshots.photos
        historySteps = tally.history.count
        photosWithHistory = tally.history.photos
        var rotations: [String: Rotation] = [:]
        for (file, code) in tally.rotations {
            let code = LightroomCensusNames.rotation(code)
            rotations[code, default: Rotation(code: code, photos: 0, orientations: [:])].photos += 1
            if let orientation = orientations?[file] {
                rotations[code]?
                    .orientations[orientation.map(String.init) ?? LightroomCensusNames.none, default: 0] += 1
                found += 1
            }
        }
        self.rotations = rotations.values.sorted { $0.code < $1.code }
        paired = orientations != nil
        self.notes = notes
    }

    private static func settings(_ tally: [String: LightroomCensusTally.Values]) -> [Setting] {
        var named: [String: LightroomCensusTally.Values] = [:]
        for (name, values) in tally {
            named[LightroomCensusNames.setting(name), default: .init()].merge(values)
        }
        return named.map { Setting(name: $0.key, carried: $0.value.carried, changed: $0.value.changed) }
            .sorted { $0.name < $1.name }
    }

    private static func kinds(_ tally: [String: LightroomCensusTally.Held]) -> [Kind] {
        tally.map { Kind(name: $0.key, count: $0.value.count, photos: $0.value.photos) }.sorted { $0.name < $1.name }
    }
}

public extension LightroomCensus {
    /// The census in lines, as `redlamp library lightroom --census` prints it.
    func lines() -> [String] {
        var lines = ["Lightroom Classic catalog\(version.map { " version \($0)" } ?? ""): what its edits use, "
            + "naming no photo, path, keyword or value"]
        lines.append("  \(Self.count(photos)) photos and \(Self.count(virtualCopies)) virtual copies: "
            + "\(Self.count(withSettings)) with Develop settings"
            + (unreadable > 0 ? " (\(Self.count(unreadable)) of them couldn't be read)" : "")
            + ", \(Self.count(adjusted)) marked as adjusted, \(Self.count(sizes)) with their file's size")
        lines.append("  process versions (ProcessVersion): " + Self.list(processVersions))
        lines.append("  settings, by the photos carrying each and of those the ones whose value isn't the one most "
            + "of them have:")
        lines += Self.settingLines(settings, indent: "    ")
        lines.append("  masks (MaskGroupBasedCorrections): \(Self.count(masks)) on \(Self.photos(photosWithMasks)); "
            + "beyond what one of Redlamp's edits holds, \(Self.photos(overMaskLimit)) with more than "
            + "\(MaskLayer.maximumLayers) masks and \(Self.count(overComponentLimit)) with more than "
            + "\(MaskLayer.maximumComponents) components")
        if !components.isEmpty {
            lines.append("    components, by What, MaskSubType and range mask Type:")
            lines += components.map { "      \($0.name): \(Self.count($0.count)) on \(Self.photos($0.photos))" }
        }
        if !maskSettings.isEmpty {
            lines.append("    masks' own settings, by the masks carrying each and of those the ones whose value "
                + "isn't the one most of them have:")
            lines += Self.settingLines(maskSettings, indent: "      ")
        }
        lines.append("  earlier masks: " + Self.list(earlierMasks))
        lines.append("  spots (RetouchAreas), by SpotType, Method and masks: " + Self.list(spots))
        lines.append("  earlier spots (RetouchInfo), by spotType: " + Self.list(earlierSpots))
        lines.append("  profiles (CameraProfile): " + Self.list(profiles))
        lines.append("  looks (Look's Name): " + Self.list(looks))
        let modes = upright.sorted { $0.key.count != $1.key.count ? $0.key.count < $1.key.count : $0.key < $1.key }
        lines.append("  Upright (PerspectiveUpright): " + (modes.isEmpty ? "none" : modes.map { mode, count in
            "\(mode)\(LightroomCensusNames.uprightModes[mode].map { " (\($0))" } ?? ""): \(Self.count(count))"
        }.joined(separator: ", ")))
        lines.append("  snapshots: \(Self.count(snapshots)) on \(Self.photos(photosWithSnapshots)); history steps: "
            + "\(Self.count(historySteps)) on \(Self.photos(photosWithHistory))")
        lines.append(paired
            ? "  rotations (Adobe_images.orientation), with the EXIF orientations of the files the library has "
            + "(\(Self.count(found)) of \(Self.count(photos + virtualCopies))):"
            : "  rotations (Adobe_images.orientation), not paired with files: no library index was read:")
        for rotation in rotations {
            let found = rotation.orientations.values.reduce(0, +)
            let orientations = rotation.orientations.sorted { $0.key < $1.key }.map { orientation, count in
                (orientation == LightroomCensusNames.none ? "no EXIF orientation" : "EXIF \(orientation)")
                    + ": \(Self.count(count))"
            }.joined(separator: ", ")
            let code = rotation.code == LightroomCensusNames.none ? "no code" : rotation.code
            lines.append("    \(code): \(Self.photos(rotation.photos))"
                + (paired ? "; \(Self.count(found)) in the library" + (found > 0 ? ", \(orientations)" : "") : ""))
        }
        lines += notes.map { "  note: \($0)" }
        return lines
    }

    private static func count(_ value: Int) -> String {
        LightroomReport.count(value)
    }

    private static func photos(_ count: Int) -> String {
        "\(Self.count(count)) photo\(count == 1 ? "" : "s")"
    }

    private static func list(_ counts: [String: Int]) -> String {
        guard !counts.isEmpty else { return "none" }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key): \(count($0.value))" }.joined(separator: ", ")
    }

    private static func list(_ kinds: [Kind]) -> String {
        guard !kinds.isEmpty else { return "none" }
        return kinds.map { "\($0.name): \(count($0.count)) on \(photos($0.photos))" }.joined(separator: "; ")
    }

    /// Settings, those changed on the most photos first, then the names of those nothing changes.
    private static func settingLines(_ settings: [Setting], indent: String) -> [String] {
        var lines = settings.filter { $0.changed > 0 }
            .sorted { $0.changed != $1.changed ? $0.changed > $1.changed : $0.name < $1.name }
            .map { "\(indent)\($0.name): \(count($0.carried)), \(count($0.changed)) changed" }
        let unchanged = settings.filter { $0.changed == 0 }.map(\.name).sorted()
        guard !unchanged.isEmpty else { return lines }
        var line = "\(indent)none changed (\(count(unchanged.count))):"
        for (place, name) in unchanged.enumerated() {
            let word = " " + name + (place == unchanged.count - 1 ? "" : ",")
            if line.count + word.count > 116 {
                lines.append(line)
                line = indent + "  " + name + (place == unchanged.count - 1 ? "" : ",")
            } else {
                line += word
            }
        }
        lines.append(line)
        return lines
    }
}
