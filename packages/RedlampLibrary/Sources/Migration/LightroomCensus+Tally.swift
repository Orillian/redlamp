import Foundation
import RedlampEngineAPI
import RedlampRecipes

/// What a part of a catalog's photos and virtual copies hold, counted for `LightroomCensus` (EDT-23) and merged
/// with the other parts'. Kinds of masks and spots are named as `LightroomCensusNames` allows as each photo is
/// counted; settings, profiles, process versions and rotation codes keep the catalog's text until the census
/// names them.
struct LightroomCensusTally: Sendable {
    /// A setting's values among the photos, or masks, carrying it.
    struct Values: Sendable {
        var carried = 0
        /// How many carry each value, by its hash.
        var values: [Int: Int] = [:]

        mutating func add(_ value: LuaValue) {
            carried += 1
            values[value.hashValue, default: 0] += 1
        }

        mutating func merge(_ other: Values) {
            carried += other.carried
            for (value, count) in other.values {
                values[value, default: 0] += count
            }
        }

        /// Those whose value isn't the one most of them carry; all of them when no two carry the same.
        var changed: Int {
            let most = values.values.max() ?? 0
            return most > 1 ? carried - most : carried
        }
    }

    /// Things photos hold several of: how many, and the photos holding any.
    struct Held: Sendable {
        var count = 0
        var photos = 0

        mutating func add(_ count: Int) {
            self.count += count
            photos += count > 0 ? 1 : 0
        }

        mutating func merge(_ other: Held) {
            count += other.count
            photos += other.photos
        }
    }

    /// The arrays of Lightroom 10's and earlier masks, one shape to a correction.
    static let earlierMaskKinds = [
        "GradientBasedCorrections",
        "CircularGradientBasedCorrections",
        "PaintBasedCorrections",
    ]

    var photos = 0
    var virtualCopies = 0
    var withSettings = 0
    var unreadable = 0
    var sizes = 0
    var processVersions: [String?: Int] = [:]
    var settings: [String: Values] = [:]
    var masks = Held()
    var overMasks = 0
    var overComponents = 0
    var components: [String: Held] = [:]
    var maskSettings: [String: Values] = [:]
    var earlierMasks: [String: Held] = [:]
    var spots: [String: Held] = [:]
    var earlierSpots: [String: Held] = [:]
    var profiles: [String: Int] = [:]
    var looks: [String: Int] = [:]
    var upright: [String: Int] = [:]
    var snapshots = Held()
    var history = Held()
    /// Each photo's and virtual copy's rotation code, with the photo whose file it shows.
    var rotations: [(file: Int64, code: String?)] = []

    init() {}

    init(_ part: [LightroomCatalog.Develop]) {
        for develop in part {
            add(develop)
        }
    }

    mutating func add(_ develop: LightroomCatalog.Develop) {
        if develop.master == nil {
            photos += 1
        } else {
            virtualCopies += 1
        }
        rotations.append((develop.master ?? develop.image, develop.orientation))
        if develop.fileWidth != nil, develop.fileHeight != nil {
            sizes += 1
        }
        snapshots.add(develop.snapshots.count)
        history.add(develop.historySteps)
        let table: LuaTable
        do {
            guard let settings = try develop.settings() else { return }
            table = settings
        } catch {
            unreadable += 1
            return
        }
        withSettings += 1
        processVersions[table.text("ProcessVersion") ?? develop.processVersion, default: 0] += 1
        for (name, value) in table.fields {
            settings[name, default: Values()].add(value)
        }
        addMasks(table)
        addEarlierMasks(table)
        addSpots(table)
        if let profile = table.text("CameraProfile") {
            profiles[profile, default: 0] += 1
        }
        if let look = table["Look"]?.table?.text("Name") {
            looks[look, default: 0] += 1
        }
        if let mode = table.text("PerspectiveUpright") {
            upright[mode, default: 0] += 1
        }
    }

    /// Lightroom 11's and later masks: each correction a mask, with its components and its own settings.
    private mutating func addMasks(_ settings: LuaTable) {
        guard let groups = settings["MaskGroupBasedCorrections"]?.table else { return }
        let corrections = groups.items.compactMap(\.table)
        masks.add(corrections.count)
        var kinds: [String: Int] = [:]
        var total = 0
        for correction in corrections {
            addMaskSettings(correction)
            for mask in Self.masks(correction["CorrectionMasks"]) {
                total += 1
                kinds[LightroomCensusNames.component(mask), default: 0] += 1
                for inner in Self.masks(mask["Masks"]) {
                    kinds[LightroomCensusNames.component(inner, inside: mask), default: 0] += 1
                }
            }
        }
        overMasks += corrections.count > MaskLayer.maximumLayers ? 1 : 0
        overComponents += total > MaskLayer.maximumComponents ? 1 : 0
        for (kind, count) in kinds {
            components[kind, default: Held()].add(count)
        }
    }

    private mutating func addEarlierMasks(_ settings: LuaTable) {
        for kind in Self.earlierMaskKinds {
            guard let corrections = settings[kind]?.table?.items.compactMap(\.table) else { continue }
            var kinds: [String: Int] = [:]
            for correction in corrections {
                addMaskSettings(correction)
                let range = ([correction] + Self.masks(correction["CorrectionMasks"])).lazy
                    .compactMap(LightroomCensusNames.rangeMask).first
                kinds[kind + LightroomCensusNames.range(range), default: 0] += 1
            }
            for (name, count) in kinds {
                earlierMasks[name, default: Held()].add(count)
            }
        }
    }

    private mutating func addMaskSettings(_ correction: LuaTable) {
        for (name, value) in correction.fields where name != "CorrectionMasks" {
            maskSettings[name, default: Values()].add(value)
        }
    }

    private mutating func addSpots(_ settings: LuaTable) {
        var kinds: [String: Int] = [:]
        for area in Self.masks(settings["RetouchAreas"]) {
            kinds[LightroomCensusNames.spot(area), default: 0] += 1
        }
        for (kind, count) in kinds {
            spots[kind, default: Held()].add(count)
        }
        var earlier: [String: Int] = [:]
        for case let .string(info) in settings["RetouchInfo"]?.table?.items ?? [] {
            earlier[LightroomCensusNames.earlierSpot(info), default: 0] += 1
        }
        for (kind, count) in earlier {
            earlierSpots[kind, default: Held()].add(count)
        }
    }

    /// The structures a field holds: one, when it has a kind of its own (`What`), else each in its list.
    static func masks(_ value: LuaValue?) -> [LuaTable] {
        guard let table = value?.table else { return [] }
        return table["What"] != nil ? [table] : table.items.compactMap(\.table)
    }

    mutating func merge(_ other: LightroomCensusTally) {
        photos += other.photos
        virtualCopies += other.virtualCopies
        withSettings += other.withSettings
        unreadable += other.unreadable
        sizes += other.sizes
        Self.add(other.processVersions, to: &processVersions)
        for (name, values) in other.settings {
            settings[name, default: Values()].merge(values)
        }
        masks.merge(other.masks)
        overMasks += other.overMasks
        overComponents += other.overComponents
        Self.add(other.components, to: &components)
        for (name, values) in other.maskSettings {
            maskSettings[name, default: Values()].merge(values)
        }
        Self.add(other.earlierMasks, to: &earlierMasks)
        Self.add(other.spots, to: &spots)
        Self.add(other.earlierSpots, to: &earlierSpots)
        Self.add(other.profiles, to: &profiles)
        Self.add(other.looks, to: &looks)
        Self.add(other.upright, to: &upright)
        snapshots.merge(other.snapshots)
        history.merge(other.history)
        rotations += other.rotations
    }

    private static func add<Key>(_ counts: [Key: Int], to total: inout [Key: Int]) {
        for (key, count) in counts {
            total[key, default: 0] += count
        }
    }

    private static func add(_ held: [String: Held], to total: inout [String: Held]) {
        for (key, things) in held {
            total[key, default: Held()].merge(things)
        }
    }
}

/// What the census may name of what a catalog holds, so that it names no photo, path, keyword or value: setting
/// names, the kinds, subtypes and methods masks and spots are written with, Adobe's profiles and the
/// camera-matching ones, process versions and rotation codes, each only in the form those take. Anything else
/// is `other`, and nothing at all is `none`.
enum LightroomCensusNames {
    static let other = "other"
    static let none = "none"

    /// A setting's name: a name as Lua writes one, as every Camera Raw setting's is.
    static func setting(_ name: String) -> String {
        let bytes = name.utf8
        guard let first = bytes.first, isLetter(first), bytes.count <= 64,
              bytes.allSatisfy({ isLetter($0) || isDigit($0) || $0 == UInt8(ascii: "_") })
        else { return other }
        return name
    }

    /// A kind, subtype or method as masks and spots write them: `Mask/Gradient`, `heal`, `1`.
    static func kind(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return none }
        let fits = text.utf8.count <= 40
            && text.utf8.allSatisfy { isLetter($0) || isDigit($0) || kindMarks.contains($0) }
        return fits ? text : other
    }

    private static let kindMarks = Array(" /._-+&".utf8)
    private static let cameraMarks = Array(" /.+-&()'".utf8)

    /// A mask component's kind: its `What`, with the subtype AI masks carry (`MaskSubType`), the type of a range
    /// mask's, and the kind of the component it sits in.
    static func component(_ mask: LuaTable, inside outer: LuaTable? = nil) -> String {
        var name = kind(mask.text("What"))
        if let subtype = mask.text("MaskSubType") {
            name += ", MaskSubType " + kind(subtype)
        }
        name += range(rangeMask(mask))
        if let outer {
            name += ", inside " + kind(outer.text("What"))
        }
        return name
    }

    /// The range mask a correction or component carries (`CorrectionRangeMask`, as ExifTool's `CorrRangeMask`).
    static func rangeMask(_ table: LuaTable) -> LuaTable? {
        (table["CorrectionRangeMask"] ?? table["CorrRangeMask"])?.table
    }

    static func range(_ mask: LuaTable?) -> String {
        guard let mask else { return "" }
        return mask.text("Type").map { ", range mask Type " + kind($0) } ?? ", range mask"
    }

    /// A spot's kind: its `SpotType`, its `Method` and its masks' kinds.
    static func spot(_ area: LuaTable) -> String {
        var name = kind(area.text("SpotType"))
        if let method = area.text("Method") {
            name += ", Method " + kind(method)
        }
        var shapes: [String] = []
        for mask in LightroomCensusTally.masks(area["Masks"]) {
            let shape = kind(mask.text("What"))
            if !shapes.contains(shape) {
                shapes.append(shape)
            }
        }
        return shapes.isEmpty ? name : name + ", " + shapes.joined(separator: " + ")
    }

    /// The `spotType` of one of Process 2010's spots, written as text: `centerX = 0.5, …, spotType = heal`.
    static func earlierSpot(_ info: String) -> String {
        for field in info.split(separator: ",") {
            let parts = field.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "spotType" {
                return kind(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return none
    }

    /// Adobe's own profiles by name; the creative ones (`Artistic 01`) are matched by their form.
    static let adobeProfiles: Set = [
        "Adobe Standard", "Adobe Color", "Adobe Monochrome", "Adobe Landscape", "Adobe Neutral", "Adobe Portrait",
        "Adobe Vivid", "Adobe Standard B&W", "Adobe Adaptive", "Adobe Adaptive Color", "Adobe Adaptive B&W",
        "Adobe Adaptive Monochrome", "Adaptive: Color", "Adaptive: B&W", "Adaptive: Portrait", "Embedded",
    ]
    static let creativeGroups = ["Artistic", "B&W", "Modern", "Vintage"]

    /// A profile's or look's name when it's one of Adobe's or a camera-matching one (`Camera Standard`), else
    /// `other`: a photographer's own profile can name a client.
    static func profile(_ name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return none }
        return isAdobe(name) || isCameraMatching(name) ? name : other
    }

    private static func isAdobe(_ name: String) -> Bool {
        if adobeProfiles.contains(name) {
            return true
        }
        if name.hasPrefix("ACR "), Double(name.dropFirst(4)) != nil, name.utf8.count <= 8 {
            return true
        }
        return creativeGroups.contains { group in
            let number = name.utf8.dropFirst(group.utf8.count + 1)
            return name.hasPrefix(group + " ") && number.count == 2 && number.allSatisfy(isDigit)
        }
    }

    private static func isCameraMatching(_ name: String) -> Bool {
        name.hasPrefix("Camera ") && name.utf8.count <= 48
            && name.utf8.allSatisfy { isLetter($0) || isDigit($0) || cameraMarks.contains($0) }
    }

    /// A process version as Lightroom numbers them: `11.0`, `6.7`.
    static func processVersion(_ text: String?) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return none }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let fits = parts.count <= 2 && parts
            .allSatisfy { (1 ... 3).contains($0.utf8.count) && $0.utf8.allSatisfy(isDigit) }
        return fits ? text : other
    }

    /// One of Lightroom's rotation codes (`Adobe_images.orientation`): a few letters or digits.
    static func rotation(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return none }
        return code.utf8.count <= 8 && code.utf8.allSatisfy { isLetter($0) || isDigit($0) } ? code : other
    }

    /// Upright's mode (`PerspectiveUpright`), a number.
    static func upright(_ mode: String) -> String {
        guard let number = Int(mode.trimmingCharacters(in: .whitespaces)), (0 ... 99).contains(number) else {
            return other
        }
        return String(number)
    }

    /// Upright's modes as ExifTool's tables name them.
    static let uprightModes = ["0": "Off", "1": "Auto", "2": "Full", "3": "Level", "4": "Vertical", "5": "Guided"]

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte | 0x20)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
    }
}
