import Foundation

/// A Lightroom develop preset converted to a recipe (EDT-11): an `.xmp` file of Camera Raw
/// settings in the `crs` namespace, read with Redlamp's own reader. Only the settings the preset
/// carries are included, as Lightroom applies only those, and the report says how each one was
/// carried over.
public struct LightroomPresetImport: Sendable {
    public var recipe: Recipe
    public var report: LightroomImportReport
    /// The preset's crop, which a recipe doesn't hold, for applying to a photo directly
    /// (`LightroomCrop.redlampCrop(imageSize:cameraOrientation:orientation:)`).
    public var crop: LightroomCrop?

    public init(recipe: Recipe, report: LightroomImportReport) {
        self.recipe = recipe
        self.report = report
    }
}

/// How each of a preset's or a photo's settings was carried over.
public struct LightroomImportReport: Sendable, Equatable {
    public enum Outcome: String, Sendable, CaseIterable {
        /// Redlamp has the same control on the same scale.
        case mapped
        /// Carried over to the nearest Redlamp control or scale; `note` says how.
        case approximated
        /// Not carried over; `note` says why.
        case ignored
    }

    /// Why a photo's setting was left out of its edit, which the import's report groups photos by.
    public enum Reason: Sendable, Hashable {
        /// Only files Lightroom made can settle how it converts: where masks and spots sit, Upright, panel
        /// switches, the catalog's rotation codes and Point Color's fields.
        case notYetChecked
        /// Process 2003's or 2010's tone, which EDT-31 is to convert as Lightroom's Update to Current Process
        /// does; until then the photo keeps Redlamp's default tone.
        case earlierProcess
        /// A Lightroom feature Redlamp doesn't have, with the roadmap row that would bring it, if one would
        /// (`OTH-03` for Lens Blur).
        case notInRedlamp(row: String?)
        /// A value that can't be read.
        case unreadable
        /// A setting Redlamp doesn't know.
        case unknown
    }

    /// How fully a photo's edit converts.
    public enum Conversion: String, Sendable, CaseIterable {
        /// Every setting is mapped.
        case full
        /// Some settings are approximated, and none is left out.
        case approximated
        /// Some settings are left out.
        case leftOut
    }

    /// What renders a photo's profile, decided from the Adobe profiles on this Mac when it's converted (EDT-33).
    public enum Profile: Sendable, Hashable {
        /// The photographer's own copy of the Adobe profile Lightroom used, by Lightroom's name for it.
        case onThisMac(String)
        /// `look` stands in for the profile Lightroom used, which isn't on this Mac: Redlamp's look of the same
        /// name, or the camera profile the photo embeds.
        case standIn(profile: String, look: String)
    }

    public struct Entry: Sendable, Equatable {
        /// The Camera Raw setting's name without its namespace, for example `Exposure2012`.
        public var setting: String
        public var outcome: Outcome
        public var note: String?
        /// Why a photo's setting was left out; nil for one carried over, and for a preset's.
        public var reason: Reason?

        public init(setting: String, outcome: Outcome, note: String? = nil, reason: Reason? = nil) {
            self.setting = setting
            self.outcome = outcome
            self.note = note
            self.reason = reason
        }
    }

    /// The preset's or photo's `crs:ProcessVersion`, if it has one.
    public var processVersion: String?
    public var entries: [Entry]
    /// What renders the photo's profile. Nil for a preset's, for a rendered photo's and one the photo embeds
    /// (`Embedded`), which aren't looked for among the Adobe profiles, and where the caller didn't say which are
    /// on this Mac.
    public var profile: Profile?

    public init(processVersion: String? = nil, entries: [Entry] = [], profile: Profile? = nil) {
        self.processVersion = processVersion
        self.entries = entries
        self.profile = profile
    }

    public func entries(_ outcome: Outcome) -> [Entry] {
        entries.filter { $0.outcome == outcome }
    }

    /// How fully a photo's edit converts, by its settings' outcomes.
    public var conversion: Conversion {
        if entries.contains(where: { $0.outcome == .ignored }) {
            return .leftOut
        }
        return entries.contains { $0.outcome == .approximated } ? .approximated : .full
    }

    /// Why settings were left out, each reason once, in the report's order.
    public var reasons: [Reason] {
        var reasons: [Reason] = []
        for reason in entries.compactMap(\.reason) where !reasons.contains(reason) {
            reasons.append(reason)
        }
        return reasons
    }
}

public enum LightroomPresetError: Error, Equatable, CustomStringConvertible {
    /// Not an XMP file of Camera Raw settings.
    case notAPreset
    /// A process version whose sliders Redlamp doesn't map (before Process 2012).
    case unsupportedProcessVersion(String)

    public var description: String {
        switch self {
        case .notAPreset: "This isn't a Lightroom develop preset"
        case let .unsupportedProcessVersion(version):
            "Lightroom process version \(version) predates Process 2012, whose sliders Redlamp maps"
        }
    }
}

public enum LightroomPreset {
    /// Whether `data` is a Lightroom develop preset: XMP with Camera Raw settings that a preset
    /// carries, not a photo's sidecar or a profile (see `CameraRawSettings.isPreset`).
    public static func isPreset(_ data: Data) -> Bool {
        mentionsCameraRawSettings(data) && CameraRawSettings(xmp: data)?.isPreset == true
    }

    /// The preset as a recipe named `name`, else the preset's own name, else an empty name for the
    /// caller to fill in, with its report.
    public static func convert(_ data: Data, name: String? = nil) throws -> LightroomPresetImport {
        guard mentionsCameraRawSettings(data), let settings = CameraRawSettings(xmp: data) else {
            throw LightroomPresetError.notAPreset
        }
        return try convert(settings, name: name)
    }

    private static func mentionsCameraRawSettings(_ data: Data) -> Bool {
        let head = data.prefix(64 * 1024)
        return [CameraRawSettings.rdf, CameraRawSettings.namespace].allSatisfy { head.range(of: Data($0.utf8)) != nil }
    }
}
