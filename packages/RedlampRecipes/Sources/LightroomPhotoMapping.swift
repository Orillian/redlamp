import Foundation
import RedlampEngineAPI

/// How a Camera Raw setting carries over to a photo's whole edit where a recipe carries it otherwise
/// (`LightroomRule.perPhoto`).
enum LightroomPhotoRule: Sendable {
    /// Lightroom's bookkeeping, or what another setting's conversion reads.
    case metadata
    /// Redlamp's control on Lightroom's scale, which isn't yet checked against Lightroom's rendering.
    case unchecked(ParameterSpec)
    /// The profile: `CameraProfile`, and the `Look` Lightroom applies over it.
    case profile
    /// The lens profile's distortion or vignetting amount.
    case lensProfileAmount(ParameterSpec)
    /// The crop and its angle (`LightroomCrop`).
    case crop
    /// Upright, while it's on: its mode, Guided's guides and the transforms it solved.
    case upright
    /// Masks: Lightroom's mask groups, and its earlier corrections of one shape each.
    case masks
    /// Healing and cloning spots, Process 2012's and Process 2003's and 2010's.
    case spots
    /// Lightroom's Auto, whose results the sliders hold.
    case auto
    /// A control of Process 2003 and 2010 that Process 2012 replaced, named `control`.
    case earlierProcess(String)
    /// Left out for `reason`, as `note` says, while it does something: its value isn't blank, empty, off or
    /// `at`, and the setting `switchedBy` names isn't off.
    case leftOut(LightroomImportReport.Reason, String, switchedBy: String? = nil, at: Double = 0)

    static func unchecked(_ parameter: ParameterID) -> LightroomPhotoRule {
        .unchecked(parameter.spec)
    }

    static func lensProfileAmount(_ parameter: ParameterID) -> LightroomPhotoRule {
        .lensProfileAmount(parameter.spec)
    }
}

extension LightroomPhoto {
    /// Which of Lightroom's processes a photo's settings were made in.
    enum Process: Sendable {
        case process2003, process2010, current

        init(_ version: String?) {
            guard let version, let numbers = LightroomPreset.versionNumbers(version) else {
                self = .current
                return
            }
            if numbers.lexicographicallyPrecedes([5, 7]) {
                self = .process2003
            } else if numbers.lexicographicallyPrecedes(LightroomPreset.firstProcessVersion) {
                self = .process2010
            } else {
                self = .current
            }
        }

        var isEarlier: Bool {
            self != .current
        }

        var name: String {
            switch self {
            case .process2003: "Process 2003"
            case .process2010: "Process 2010"
            case .current: "Process 2012"
            }
        }
    }

    /// Process 2012's tone controls, which a photo of an earlier process doesn't use.
    static let laterTone: Set = [
        "Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012", "Clarity2012",
        "Texture", "Dehaze", "ToneCurvePV2012", "ToneCurvePV2012Red", "ToneCurvePV2012Green", "ToneCurvePV2012Blue",
    ]

    /// The controls whose rendering a photo's earlier process changes, which wait on EDT-31 there: the
    /// parametric curve, which bends Process 2003's and 2010's own tone, and Process 2003's noise reduction.
    static func earlierControl(_ key: String, in process: Process) -> String? {
        if key.hasPrefix("Parametric") {
            return "tone curve"
        }
        return process == .process2003 && ["LuminanceSmoothing", "ColorNoiseReduction"].contains(key)
            ? "noise reduction" : nil
    }

    /// Settings in ExifTool's table that EDT-11's table doesn't name, and how a photo's edit carries them.
    static let otherRules: [String: LightroomPhotoRule] = [
        "ColorVariance": .leftOut(.notYetChecked, Note.pointColor),
        "LookName": .metadata,
        "MoireFilter": .leftOut(.notInRedlamp(row: nil), Note.moireFilter),
    ]

    /// Upright's modes by Lightroom's numbers (`PerspectiveUpright`).
    static let uprightModes = [1: "Auto", 2: "Full", 3: "Level", 4: "Vertical", 5: "Guided"]

    /// How many masks `masks` are, with those inside them.
    static func count(_ masks: [CameraRawSettings]) -> Int {
        masks.reduce(0) { $0 + 1 + count($1.structures("Masks") ?? []) }
    }
}

// MARK: - Profiles

extension LightroomPhoto {
    /// The Base Look standing in for Lightroom's profile, and how near it comes.
    struct Profile {
        var look: BaseLookReference
        var outcome: LightroomImportReport.Outcome
        var note: String?
    }

    /// Adobe's six Adobe Raw profiles, and the Base Looks named as they are.
    static let adobeLooks: [String: BuiltInBaseLook] = [
        "Adobe Color": .color, "Adobe Vivid": .vivid, "Adobe Portrait": .portrait, "Adobe Landscape": .landscape,
        "Adobe Neutral": .neutral, "Adobe Monochrome": .monochrome,
    ]

    /// Words of camera makers' styles in Camera Matching profiles' names (`Camera Neutral`), each with the
    /// Base Look nearest it; the first that a name holds is taken.
    static let styleLooks: [(word: String, look: BuiltInBaseLook)] = [
        ("monochrome", .monochrome), ("monotone", .monochrome), ("b&w", .monochrome), ("neutral", .neutral),
        ("faithful", .neutral), ("flat", .neutral), ("natural", .neutral), ("muted", .neutral), ("vivid", .vivid),
        ("vibrant", .vivid), ("landscape", .landscape), ("portrait", .portrait), ("standard", .color),
    ]

    /// Lightroom's profile `name` at `amount` percent as a Base Look, the camera's own profiles going to the
    /// look the file embeds where it embeds one.
    static func profile(_ name: String, amount: Double, photo: LightroomPhotoContext) -> Profile {
        if let look = adobeLooks[name] {
            return Profile(look: look.reference.withAmount(amount), outcome: .mapped)
        }
        let style = name.hasPrefix("Camera ") ? name.dropFirst("Camera ".count) : nil
        if let embedded = photo.embeddedLook, style != nil || ["Adobe Standard", "Embedded"].contains(name) {
            let same = name == "Embedded" || embedded.name.lowercased() == name.lowercased()
            return Profile(
                look: embedded.withAmount(amount), outcome: same ? .mapped : .approximated,
                note: same ? nil : Note.embedded(embedded.name, for: name),
            )
        }
        if let style, let slot = filmSlot(style) {
            let look = photo.slotLooks[slot] ?? slot.baseLook
            return Profile(
                look: look.withAmount(amount),
                outcome: .approximated,
                note: Note.standIn(look.name, for: name),
            )
        }
        let words = style.map { $0.lowercased() } ?? (name == "Adobe Standard" ? "standard" : "")
        guard let look = styleLooks.first(where: { words.contains($0.word) })?.look else {
            let color = BuiltInBaseLook.color.reference
            return Profile(look: color.withAmount(amount), outcome: .approximated, note: Note.noLike(name))
        }
        return Profile(
            look: look.reference.withAmount(amount), outcome: .approximated, note: Note.standIn(look.name, for: name),
        )
    }

    /// The film slot a Fujifilm Camera Matching profile names (`PROVIA/Standard`, `CLASSIC CHROME`,
    /// `ACROS+Ye FILTER`); nil for a style every maker names alike on its own (`Standard`, `Vivid`, `Soft`,
    /// `Monochrome`), and for Reala Ace, which has no slot yet (TON-47).
    static func filmSlot(_ style: some StringProtocol) -> FilmSlot? {
        let key = FujifilmLUT.key(style.split(separator: "/").first ?? "")
        if key.hasPrefix("ACROS") || key.hasPrefix("MONOCHROME") {
            let filters: [(String, FilmSlot)] = [
                ("YEFILTER", .monochromeYellow), ("RFILTER", .monochromeRed), ("GFILTER", .monochromeGreen),
            ]
            if let slot = filters.first(where: { key.hasSuffix($0.0) })?.1 {
                return slot
            }
        }
        guard !["STANDARD", "VIVID", "SOFT", "MONOCHROME"].contains(key) else { return nil }
        return FujifilmSimulation(named: key)?.slot
    }
}

// MARK: - The report's notes

extension LightroomPhoto {
    /// The report's reasons and explanations for what a photo's edit carries otherwise than a recipe.
    enum Note {
        static let uncheckedScale = """
        Carried one for one on Lightroom's scale, which isn't yet checked against \
        Lightroom's rendering.
        """
        static let pointColor = """
        Point Color's swatches aren't carried yet: their fields in Lightroom's settings aren't known yet (TON-34).
        """
        static let lensBlur = "Redlamp has no Lens Blur yet (OTH-03)."
        static let redEye = "Redlamp has no red-eye correction yet (OTH-01)."
        static let hdr = "Redlamp doesn't edit in HDR yet (TON-42)."
        static let manualAberration = """
        Process 2010's manual chromatic aberration sliders, which Redlamp doesn't have: its Remove Chromatic \
        Aberration corrects fringes from the lens profile or measures them.
        """
        static let defringeMenu = """
        Process 2010's Defringe menu, which Redlamp doesn't have: its Defringe has Lightroom's later purple and \
        green sliders.
        """
        static let profileAberration = """
        Redlamp's Remove Chromatic Aberration has no amount for the lens profile's correction.
        """
        static let moireFilter = "Camera Raw's moiré filter for the whole photo, which Redlamp doesn't have."
        static let panelSwitch = """
        Lightroom has this panel switched off; how it stores the switch isn't yet checked \
        against files Lightroom made, so the panel's settings apply.
        """
        static let auto = "Lightroom works Auto out for each photo; Redlamp keeps the values Lightroom found."
        static let autoWhiteBalance = """
        Lightroom's Auto white balance, kept as Custom with the temperature and tint \
        it found rather than worked out again.
        """
        static let autoMeasured = "Redlamp works Auto white balance out itself, which can differ from Lightroom's."
        static let autoShift = """
        Lightroom's Auto white balance for a rendered photo, kept as the shift it found, as \
        Red and Blue Shift.
        """

        static func setByMode(_ mode: WhiteBalanceMode) -> String {
            "Set by the white balance, \(mode.name), as Lightroom sets it."
        }

        static func notForRendered(_ name: String) -> String {
            "Lightroom doesn't offer the white balance “\(name)” for a rendered photo."
        }

        static func earlierProcess(_ control: String, _ process: Process) -> String {
            "\(process.name)'s \(control), left at Redlamp's default until EDT-31 converts it as Lightroom's "
                + "Update to Current Process does."
        }

        static func upright(_ mode: String?) -> String {
            "Upright\(mode.map { " (\($0))" } ?? "") isn't carried yet: how its modes, guides and solved transforms "
                + "convert isn't yet checked against files Lightroom made."
        }

        static func masks(_ corrections: Int, components: Int) -> String {
            "\(corrections) \(corrections == 1 ? "mask" : "masks") with \(components) "
                + "\(components == 1 ? "component" : "components") not carried yet: where Lightroom places them "
                + "isn't yet checked against files Lightroom made."
        }

        static func spots(_ count: Int) -> String {
            "\(count) healing and cloning \(count == 1 ? "spot" : "spots") not carried yet: where Lightroom places "
                + "them isn't yet checked against files Lightroom made."
        }

        static func rotation(_ code: String) -> String {
            "Lightroom's rotation code “\(code)” isn't yet matched to a rotation and flip, which a census of a real "
                + "catalog settles, so the photo keeps its camera's orientation."
        }

        static func lensFile(_ profile: String?) -> String? {
            profile
                .map { "Redlamp applies the lens correction the file carries; Lightroom applied the profile “\($0)”." }
        }

        static func lensFolder(_ profile: String?, file: String?) -> String {
            let used = profile.map { " Lightroom applied “\($0)”\(file.map { ", from Adobe's \($0)" } ?? "")." } ?? ""
            return "Redlamp applies a lens profile from its Lens Profiles folder when one matches the camera and lens "
                + "(LNS-04); without one, the lens isn't corrected.\(used)"
        }

        static func standIn(_ look: String, for profile: String) -> String {
            "\(look) stands in for Lightroom's “\(profile)”."
        }

        static func embedded(_ look: String, for profile: String) -> String {
            "The camera profile the photo embeds, “\(look)”, stands in for Lightroom's “\(profile)”."
        }

        static func noLike(_ profile: String) -> String {
            "Redlamp has no look like Lightroom's “\(profile)”, so \(BuiltInBaseLook.color.name) stands in."
        }

        static func underLook(_ look: String) -> String {
            "Lightroom applies the profile “\(look)” over this one, and one Base Look stands in for both."
        }

        static func frame(_ lightroom: PixelSize, file: PixelSize, offset: Int) -> String {
            "Lightroom's frame is \(lightroom.width) × \(lightroom.height) pixels and the file's \(file.width) × "
                + "\(file.height), so the crop, kept as fractions of each, can sit up to \(offset) "
                + "\(offset == 1 ? "pixel" : "pixels") from Lightroom's."
        }
    }
}
