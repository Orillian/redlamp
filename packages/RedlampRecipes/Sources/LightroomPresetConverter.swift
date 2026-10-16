import Foundation
import RedlampEngineAPI

extension LightroomPreset {
    /// Process 2012's version: earlier processes have other sliders.
    static let firstProcessVersion = [6, 7]

    static func convert(_ settings: CameraRawSettings, name: String?) throws -> LightroomPresetImport {
        guard settings.isPreset else { throw LightroomPresetError.notAPreset }
        let processVersion = settings.text("ProcessVersion")
        if let processVersion, let numbers = versionNumbers(processVersion),
           numbers.lexicographicallyPrecedes(firstProcessVersion) {
            throw LightroomPresetError.unsupportedProcessVersion(processVersion)
        }
        guard orderedSettings(settings).contains(where: { $0.rule?.isMetadata != true }) else {
            throw LightroomPresetError.notAPreset
        }
        let converter = LightroomConverter(settings)
        let recipe = Recipe(
            id: RecipeNamespace.newLocalID(),
            name: trimmed(name) ?? trimmed(settings.text("Name")) ?? "",
            group: trimmed(settings.text("Group")) ?? "",
            summary: trimmed(settings.text("Description")),
            tags: ["lightroom"],
            includes: converter.includes,
            settings: converter.recipeSettings,
            created: Date(),
        )
        var result = LightroomPresetImport(
            recipe: recipe,
            report: LightroomImportReport(processVersion: processVersion, entries: converter.entries),
        )
        result.crop = LightroomCrop(settings)
        return result
    }

    static func versionNumbers(_ version: String) -> [Int]? {
        let numbers = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        return numbers.compactMap(\.self)
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// A preset's or a photo's settings carried over one Camera Raw setting at a time, with the report
/// of how each was: a preset's to a recipe's settings, a photo's to its whole edit's
/// (`LightroomConverter.init(_:photo:)`).
struct LightroomConverter {
    typealias Note = LightroomPreset.Note
    typealias Entry = LightroomImportReport.Entry

    let settings: CameraRawSettings
    /// What a photo's conversion needs of the photo; nil for a preset.
    let photo: LightroomPhotoContext?
    /// The process a photo's settings were made in; a preset's are of Process 2012 or later.
    var process = LightroomPhoto.Process.current
    var values: [ParameterID: Double] = [:]
    var includes: Set<RecipeSettingGroup> = []
    var treatment: Treatment?
    var whiteBalanceMode: WhiteBalanceMode?
    var pointCurve: [CurvePoint]?
    var channelCurves: [CurveChannel: [CurvePoint]] = [:]
    var entries: [LightroomImportReport.Entry] = []
    /// A photo's Base Look, crop and its angle, which a recipe doesn't carry.
    var baseLook: BaseLookReference?
    var crop: (rect: CropRect, angle: Double)?
    /// What renders a photo's profile, as its report says.
    var profile: LightroomImportReport.Profile?

    init(_ settings: CameraRawSettings) {
        self.settings = settings
        photo = nil
        for (key, rule) in LightroomPreset.orderedSettings(settings) {
            apply(rule ?? .ignored(Note.unknown), to: key)
        }
        setSplitToningBlending()
    }

    var recipeSettings: RecipeSettings {
        RecipeSettings(
            values: values, treatment: treatment, whiteBalanceMode: whiteBalanceMode, pointCurve: pointCurve,
            channelCurves: channelCurves,
        )
    }

    var isBlackAndWhite: Bool {
        settings.flag("ConvertToGrayscale") == true
    }

    mutating func apply(_ rule: LightroomRule, to key: String) {
        switch rule {
        case .metadata:
            break
        case let .perPhoto(_, preset):
            apply(preset.rule, to: key)
        case let .ignored(note):
            ignore(key, note)
        case let .unlessOff(note, switchKey):
            if settings.flag(switchKey ?? key) != false {
                ignore(key, note)
            }
        case let .parameter(spec):
            setNumber(key, spec)
        case let .colorLuminance(spec):
            if isBlackAndWhite {
                ignore(key, Note.luminanceInBlackAndWhite)
            } else {
                setNumber(key, spec)
            }
        case let .grayMix(spec):
            if isBlackAndWhite {
                setNumber(key, spec, approximated: Note.grayMix)
            } else {
                ignore(key, Note.grayMixInColor)
            }
        case .treatment:
            setTreatment(key)
        case .whiteBalance:
            setWhiteBalance(key)
        case let .kelvin(spec):
            setKelvin(key, spec)
        case .incremental:
            setIncremental(key)
        case let .pointCurve(channel):
            setPointCurve(key, channel)
        case .vignetteStyle:
            setVignetteStyle(key)
        case .lensProfile:
            ignore(key, settings.flag(key) == false ? Note.lensProfileOff : Note.lensProfileOn)
        case .look:
            ignore(key, lookNote)
        }
    }

    // MARK: - Treatment and white balance

    static let whiteBalanceModes: [String: WhiteBalanceMode] = [
        "As Shot": .asShot, "Auto": .auto, "Daylight": .daylight, "Cloudy": .cloudy, "Shade": .shade,
        "Tungsten": .tungsten, "Fluorescent": .fluorescent, "Flash": .flash, "Custom": .custom,
    ]

    private mutating func setTreatment(_ key: String) {
        guard let blackAndWhite = settings.flag(key) else { return ignore(key, Note.unreadable) }
        treatment = blackAndWhite ? .blackAndWhite : .color
        includes.insert(.treatment)
        report(key, .mapped)
    }

    /// The white balance the preset sets by name; nil for Custom, which its values set.
    private var namedWhiteBalance: WhiteBalanceMode? {
        guard let mode = settings.text("WhiteBalance").flatMap({ Self.whiteBalanceModes[$0] }), mode != .custom
        else { return nil }
        return mode
    }

    var hasKelvin: Bool {
        settings.number("Temperature") != nil || settings.number("Tint") != nil
    }

    var hasIncremental: Bool {
        settings.number("IncrementalTemperature") != nil || settings.number("IncrementalTint") != nil
    }

    private mutating func setWhiteBalance(_ key: String) {
        guard let name = settings.text(key) else { return ignore(key, Note.unreadable) }
        guard let mode = Self.whiteBalanceModes[name] else { return ignore(key, Note.unknownWhiteBalance(name)) }
        if mode != .custom || hasKelvin {
            whiteBalanceMode = mode
            includes.insert(.whiteBalance)
            report(key, .mapped)
        } else if hasIncremental {
            report(key, .approximated, Note.incrementalCustom)
        } else {
            ignore(key, Note.customWithoutValues)
        }
    }

    /// Temperature or Tint, for raw photos, unless the preset names a white balance.
    private mutating func setKelvin(_ key: String, _ spec: ParameterSpec) {
        if let mode = namedWhiteBalance {
            return ignore(key, Note.setByMode(mode))
        }
        guard let value = settings.number(key) else { return ignore(key, Note.unreadable) }
        whiteBalanceMode = .custom
        // A custom white balance takes a temperature or tint it doesn't list from the photo.
        set(spec, value, key: key, keepingDefault: true)
    }

    /// Lightroom's relative white balance for rendered photos, as Red and Blue Shift when the
    /// preset has no Temperature or Tint.
    mutating func setIncremental(_ key: String) {
        if let mode = namedWhiteBalance {
            return ignore(key, Note.setByMode(mode))
        }
        if hasKelvin {
            return ignore(key, Note.kelvinUsed)
        }
        shiftWhiteBalance(key)
    }

    /// Lightroom's relative white balance as Red and Blue Shift.
    mutating func shiftWhiteBalance(_ key: String) {
        guard settings.number(key) != nil else { return ignore(key, Note.unreadable) }
        let temperature = settings.number("IncrementalTemperature") ?? 0
        let tint = settings.number("IncrementalTint") ?? 0
        // Warmer is more red and less blue; a magenta tint is more of both.
        let shifts = [(Spec.shiftRed, temperature + tint), (Spec.shiftBlue, tint - temperature)]
        for (spec, shift) in shifts {
            store(spec, spec.clamp(shift))
        }
        let clamped = shifts.contains { abs($0.1) > 100 }
        report(key, .approximated, clamped ? Note.incremental + " " + Note.clamped("±100") : Note.incremental)
    }

    // MARK: - Tone curve and effects

    private mutating func setPointCurve(_ key: String, _ channel: CurveChannel) {
        guard let curve = curve(key) else { return ignore(key, Note.unreadable) }
        guard curve.count <= 64 else { return ignore(key, Note.pointCurveSize) }
        let bent = Self.isStraight(curve) ? nil : curve
        if channel == .rgb {
            pointCurve = bent
        } else {
            channelCurves[channel] = bent
        }
        includes.insert(.toneCurve)
        report(key, .mapped)
    }

    /// A point curve's `x, y` pairs on Lightroom's 0…255 scale, as 0…1, in order.
    private func curve(_ key: String) -> [CurvePoint]? {
        guard let items = settings.list(key), items.count >= 2 else { return nil }
        var points: [CurvePoint] = []
        for item in items {
            let coordinates = item.split(separator: ",").compactMap { CameraRawSettings.number(in: $0) }
            guard coordinates.count == 2, coordinates.allSatisfy({ (0 ... 255).contains($0) }) else { return nil }
            points.append(CurvePoint(x: coordinates[0] / 255, y: coordinates[1] / 255))
        }
        return points.sorted { $0.x < $1.x }
    }

    private static func isStraight(_ curve: [CurvePoint]) -> Bool {
        curve.first == CurvePoint(x: 0, y: 0) && curve.last == CurvePoint(x: 1, y: 1)
            && curve.allSatisfy { $0.x == $0.y }
    }

    private mutating func setVignetteStyle(_ key: String) {
        guard let style = settings.number(key) else { return ignore(key, Note.unreadable) }
        includes.insert(.effects)
        if style == 1 {
            report(key, .mapped)
        } else {
            report(key, .approximated, Note.vignetteStyle)
        }
    }

    /// A Split Toning preset, from before Color Grading, renders as Lightroom renders one: with
    /// Blending at 100 (Adobe, "Introducing Color Grading", 2020).
    mutating func setSplitToningBlending() {
        let keys = settings.values.keys
        guard keys.contains(where: { $0.hasPrefix("SplitToning") }),
              !keys.contains(where: { $0.hasPrefix("ColorGrade") })
        else { return }
        store(Spec.blending, 100)
        let after = entries.lastIndex { $0.setting.hasPrefix("SplitToning") }.map { $0 + 1 } ?? entries.endIndex
        entries.insert(
            Entry(setting: "ColorGradeBlending", outcome: .mapped, note: Note.splitToningBlending),
            at: after,
        )
    }

    private var lookNote: String {
        guard let name = settings.structure("Look")?.text("Name"), !name.isEmpty else {
            return Note.profile
        }
        return Note.look(name)
    }

    // MARK: - Values and the report

    /// `note` says how the value is approximated; `remark` says something of a value it maps.
    mutating func setNumber(
        _ key: String,
        _ spec: ParameterSpec,
        approximated note: String? = nil,
        remark: String? = nil,
    ) {
        guard let value = settings.number(key) else { return ignore(key, Note.unreadable) }
        set(spec, value, key: key, note: note, remark: remark)
    }

    mutating func set(
        _ spec: ParameterSpec,
        _ value: Double,
        key: String,
        note: String? = nil,
        remark: String? = nil,
        keepingDefault: Bool = false,
    ) {
        let clamped = spec.clamp(value)
        store(spec, clamped, keepingDefault: keepingDefault)
        if clamped != value {
            report(
                key,
                .approximated,
                [note, remark, Note.clamped(spec.formatted(clamped))].compactMap(\.self).joined(separator: " "),
            )
        } else {
            report(key, note == nil ? .mapped : .approximated, note ?? remark)
        }
    }

    /// Lists a value unless it is the default, which an included group's unlisted values take.
    mutating func store(_ spec: ParameterSpec, _ value: Double, keepingDefault: Bool = false) {
        if let group = RecipeSettingGroup(parameter: spec.id) {
            includes.insert(group)
        }
        values[spec.id] = keepingDefault || abs(value - spec.defaultValue) > 1e-9 ? value : nil
    }

    /// The parameters the converter sets itself, specified once.
    enum Spec {
        static let shiftRed = ParameterID.wbShiftRed.spec
        static let shiftBlue = ParameterID.wbShiftBlue.spec
        static let blending = ParameterID.gradeBlending.spec
        static let lensProfile = ParameterID.lensProfile.spec
    }

    mutating func report(
        _ key: String,
        _ outcome: LightroomImportReport.Outcome,
        _ note: String? = nil,
        reason: LightroomImportReport.Reason? = nil,
    ) {
        entries.append(Entry(setting: key, outcome: outcome, note: note, reason: reason))
    }

    /// A photo's setting left out says why: a value that can't be read, unless `reason` says otherwise.
    mutating func ignore(_ key: String, _ note: String, reason: LightroomImportReport.Reason? = nil) {
        report(key, .ignored, note, reason: reason ?? (photo == nil ? nil : .unreadable))
    }
}
