import Foundation
import RedlampEngineAPI

/// How a Camera Raw setting carries over to a recipe, and to a photo's whole edit.
enum LightroomRule: Sendable {
    /// Redlamp's control on Lightroom's scale.
    case parameter(ParameterSpec)
    /// HSL Luminance, which Lightroom applies to colour photos only.
    case colorLuminance(ParameterSpec)
    /// The B&W mix, which Lightroom applies to black-and-white photos only, carried to a band's Luminance.
    case grayMix(ParameterSpec)
    case treatment
    case whiteBalance
    /// Kelvin or tint, which Lightroom applies to raw photos.
    case kelvin(ParameterSpec)
    /// Lightroom's relative white balance (−100…100), which it applies to JPEGs and other
    /// rendered photos only.
    case incremental
    /// The point curve for RGB, or a channel's own.
    case pointCurve(CurveChannel)
    case vignetteStyle
    case lensProfile
    case look
    /// A Lightroom feature Redlamp doesn't have, reported only when it, or the setting that
    /// switches it, is on.
    case unlessOff(String, switchedBy: String? = nil)
    case ignored(String)
    /// The preset's own description or Lightroom's bookkeeping rather than a setting.
    case metadata
    /// A setting a photo's edit carries otherwise than a recipe: `photo` in a photo's settings
    /// (`LightroomPhoto`), `preset` in a preset's.
    case perPhoto(LightroomPhotoRule, preset: Preset)

    /// What a preset does with a setting a photo's edit carries otherwise.
    enum Preset: Sendable {
        case ignored(String)
        case unlessOff(String, switchedBy: String? = nil)
        case look
        case metadata

        var rule: LightroomRule {
            switch self {
            case let .ignored(note): .ignored(note)
            case let .unlessOff(note, switchKey): .unlessOff(note, switchedBy: switchKey)
            case .look: .look
            case .metadata: .metadata
            }
        }
    }

    var isMetadata: Bool {
        switch self {
        case .metadata, .perPhoto(_, preset: .metadata): true
        default: false
        }
    }

    // Rules carry their parameters' specifications, read once: threads converting at once contend for each
    // lookup in the shared catalogue.

    static func parameter(_ parameter: ParameterID) -> LightroomRule {
        .parameter(parameter.spec)
    }

    static func colorLuminance(_ band: ColorBand) -> LightroomRule {
        .colorLuminance(band.luminanceParameter.spec)
    }

    static func grayMix(_ band: ColorBand) -> LightroomRule {
        .grayMix(band.luminanceParameter.spec)
    }

    static func kelvin(_ parameter: ParameterID) -> LightroomRule {
        .kelvin(parameter.spec)
    }
}

extension LightroomPreset {
    /// How each Camera Raw setting carries over, in Lightroom's panel order, which the report
    /// follows. A key ending in `*` covers the keys that start with it and no earlier entry names.
    static let rules: [(key: String, rule: LightroomRule)] = metadataRules + basicRules + curveRules + mixerRules
        + gradingRules + detailRules + lensRules + transformRules + effectsRules + calibrationRules + cropRules
        + localRules

    private static let metadataRules: [(key: String, rule: LightroomRule)] = [
        "Name", "ShortName", "SortName", "Group", "Description", "UUID", "Cluster", "PresetType", "Copyright",
        "ContactInfo", "Version", "CompatibleVersion", "ProcessVersion", "HasSettings", "AlreadyApplied",
        "RawFileName", "Converter", "SupportsAmount", "SupportsColor", "SupportsMonochrome", "SupportsHighDynamicRange",
        "SupportsNormalDynamicRange", "SupportsSceneReferred", "SupportsOutputReferred", "JPEGHandling",
        "TIFFHandling", "What", "DNGIgnoreSidecars", "NegativeCache*", "ClipboardAspectRatio", "ClipboardOrientation",
        "ToggleStyleAmount", "ToggleStyleDigest", "DefaultAutoTone", "DefaultAutoGray", "DefaultsSpecificToISO",
        "DefaultsSpecificToSerial", "AutoToneDigest", "AutoToneDigestNoSat", "AutoWhiteVersion", "CameraProfileDigest",
        "ToneCurveName2012", "GrainSeed", "LensProfileDigest", "LensProfileFilename", "LensProfileIsEmbedded",
        "LensProfileMatchKey*",
    ].map { ($0, .metadata) } + [
        "UprightDependentDigest", "UprightGuidedDependentDigest", "UprightPreview", "UprightTransformCount",
        "UprightTransform_*", "UprightFourSegmentsCount", "UprightFourSegments_*",
    ].map { ($0, .perPhoto(.upright, preset: .metadata)) }

    private static let basicRules: [(key: String, rule: LightroomRule)] = [
        ("CameraModelRestriction", .perPhoto(.metadata, preset: .ignored(Note.camera))),
        ("ConvertToGrayscale", .treatment),
        ("CameraProfile", .perPhoto(.profile, preset: .ignored(Note.profile))),
        ("Look", .perPhoto(.profile, preset: .look)),
        ("OverrideLookVignette", .perPhoto(.metadata, preset: .unlessOff(Note.profile))),
        ("WhiteBalance", .whiteBalance),
        ("Temperature", .kelvin(.temperature)),
        ("Tint", .kelvin(.tint)),
        ("IncrementalTemperature", .incremental),
        ("IncrementalTint", .incremental),
        ("AutoTone", .perPhoto(.auto, preset: .unlessOff(Note.auto))),
        ("Exposure2012", .parameter(.exposure)),
        ("Contrast2012", .parameter(.contrast)),
        ("Highlights2012", .parameter(.highlights)),
        ("Shadows2012", .parameter(.shadows)),
        ("Whites2012", .parameter(.whites)),
        ("Blacks2012", .parameter(.blacks)),
        ("Texture", .parameter(.texture)),
        ("Clarity2012", .parameter(.clarity)),
        ("Dehaze", .parameter(.dehaze)),
        ("Vibrance", .parameter(.vibrance)),
        ("Saturation", .parameter(.saturation)),
        ("Exposure", earlier("Exposure", .ignored(Note.replacedExposure))),
        ("HighlightRecovery", earlier("Recovery", .ignored(Note.replacedRecovery))),
        ("FillLight", earlier("Fill Light", .ignored(Note.replacedFillLight))),
        ("Shadows", earlier("Blacks", .ignored(Note.replacedBlacks))),
        ("Brightness", earlier("Brightness", .ignored("Process 2010's Brightness, which Process 2012 doesn't have."))),
        ("Contrast", earlier("Contrast", .ignored(Note.replacedContrast))),
        ("Clarity", earlier("Clarity", .ignored(Note.replacedClarity))),
        ("AutoExposure", earlier("Auto Exposure", .unlessOff(Note.auto))),
        ("AutoContrast", earlier("Auto Contrast", .unlessOff(Note.auto))),
        ("AutoBrightness", earlier("Auto Brightness", .unlessOff(Note.auto))),
        ("AutoShadows", earlier("Auto Blacks", .unlessOff(Note.auto))),
    ]

    /// A control of Process 2003 and 2010 that Process 2012 replaced: in a photo's settings, left out
    /// until EDT-31 converts it, and not used in a photo of a later process.
    private static func earlier(_ control: String, _ preset: LightroomRule.Preset) -> LightroomRule {
        .perPhoto(.earlierProcess(control), preset: preset)
    }

    private static let curveRules: [(key: String, rule: LightroomRule)] = [
        ("ToneCurvePV2012", .pointCurve(.rgb)),
        ("ToneCurvePV2012Red", .pointCurve(.red)),
        ("ToneCurvePV2012Green", .pointCurve(.green)),
        ("ToneCurvePV2012Blue", .pointCurve(.blue)),
        ("ParametricShadows", .parameter(.curveShadows)),
        ("ParametricDarks", .parameter(.curveDarks)),
        ("ParametricLights", .parameter(.curveLights)),
        ("ParametricHighlights", .parameter(.curveHighlights)),
        ("ParametricShadowSplit", .parameter(.curveSplitShadows)),
        ("ParametricMidtoneSplit", .parameter(.curveSplitMidtones)),
        ("ParametricHighlightSplit", .parameter(.curveSplitHighlights)),
    ] + ["ToneCurve", "ToneCurveName", "ToneCurveRed", "ToneCurveGreen", "ToneCurveBlue"].map {
        ($0, earlier("point curve", .ignored(Note.replacedPointCurve)))
    }

    /// Each band's keys written out: a key built at run time is counted each time a lookup compares it, which
    /// threads converting at once contend for, and literal text isn't.
    private static let mixerRules: [(key: String, rule: LightroomRule)] = zip(ColorBand.allCases, [
        "HueAdjustmentRed", "HueAdjustmentOrange", "HueAdjustmentYellow", "HueAdjustmentGreen", "HueAdjustmentAqua",
        "HueAdjustmentBlue", "HueAdjustmentPurple", "HueAdjustmentMagenta",
    ]).map { band, key in (key, .parameter(band.hueParameter)) } + zip(ColorBand.allCases, [
        "SaturationAdjustmentRed", "SaturationAdjustmentOrange", "SaturationAdjustmentYellow",
        "SaturationAdjustmentGreen", "SaturationAdjustmentAqua", "SaturationAdjustmentBlue",
        "SaturationAdjustmentPurple", "SaturationAdjustmentMagenta",
    ]).map { band, key in (key, .parameter(band.saturationParameter)) } + zip(ColorBand.allCases, [
        "LuminanceAdjustmentRed", "LuminanceAdjustmentOrange", "LuminanceAdjustmentYellow", "LuminanceAdjustmentGreen",
        "LuminanceAdjustmentAqua", "LuminanceAdjustmentBlue", "LuminanceAdjustmentPurple", "LuminanceAdjustmentMagenta",
    ]).map { band, key in (key, .colorLuminance(band)) } + zip(ColorBand.allCases, [
        "GrayMixerRed", "GrayMixerOrange", "GrayMixerYellow", "GrayMixerGreen", "GrayMixerAqua", "GrayMixerBlue",
        "GrayMixerPurple", "GrayMixerMagenta",
    ]).map { band, key in (key, .grayMix(band)) }

    /// Color Grading kept Split Toning's keys for the shadows and highlights wheels and Balance.
    private static let gradingRules: [(key: String, rule: LightroomRule)] = [
        ("SplitToningShadowHue", .parameter(.gradeShadowsHue)),
        ("SplitToningShadowSaturation", .parameter(.gradeShadowsSaturation)),
        ("ColorGradeShadowLum", .parameter(.gradeShadowsLuminance)),
        ("ColorGradeMidtoneHue", .parameter(.gradeMidtonesHue)),
        ("ColorGradeMidtoneSat", .parameter(.gradeMidtonesSaturation)),
        ("ColorGradeMidtoneLum", .parameter(.gradeMidtonesLuminance)),
        ("SplitToningHighlightHue", .parameter(.gradeHighlightsHue)),
        ("SplitToningHighlightSaturation", .parameter(.gradeHighlightsSaturation)),
        ("ColorGradeHighlightLum", .parameter(.gradeHighlightsLuminance)),
        ("ColorGradeGlobalHue", .parameter(.gradeGlobalHue)),
        ("ColorGradeGlobalSat", .parameter(.gradeGlobalSaturation)),
        ("ColorGradeGlobalLum", .parameter(.gradeGlobalLuminance)),
        ("ColorGradeBlending", .parameter(.gradeBlending)),
        ("SplitToningBalance", .parameter(.gradeBalance)),
    ]

    private static let detailRules: [(key: String, rule: LightroomRule)] = [
        ("Sharpness", .parameter(.sharpenAmount)),
        ("SharpenRadius", .parameter(.sharpenRadius)),
        ("SharpenDetail", .parameter(.sharpenDetail)),
        ("SharpenEdgeMasking", .parameter(.sharpenMasking)),
        ("LuminanceSmoothing", .parameter(.noiseLuminance)),
        ("LuminanceNoiseReductionDetail", .parameter(.noiseLuminanceDetail)),
        ("LuminanceNoiseReductionContrast", .parameter(.noiseLuminanceContrast)),
        ("ColorNoiseReduction", .parameter(.noiseColor)),
        ("ColorNoiseReductionDetail", .parameter(.noiseColorDetail)),
        ("ColorNoiseReductionSmoothness", .parameter(.noiseColorSmoothness)),
    ]

    private static let lensRules: [(key: String, rule: LightroomRule)] = [("LensProfileEnable", .lensProfile)]
        + perPhoto([
            (
                "LensProfileChromaticAberrationScale",
                .leftOut(.notInRedlamp(row: nil), PhotoNote.profileAberration, at: 100),
            ),
            ("LensProfileDistortionScale", .lensProfileAmount(.lensProfileDistortion)),
            ("LensProfileName", .metadata),
            ("LensProfileSetup", .metadata),
            ("LensProfileVignettingScale", .lensProfileAmount(.lensProfileVignetting)),
            ("LensProfile*", .leftOut(.unknown, Note.unknown)),
            ("AutoLateralCA", .unchecked(.lensRemoveChromaticAberration)),
            ("ChromaticAberrationR", .leftOut(.notInRedlamp(row: nil), PhotoNote.manualAberration)),
            ("ChromaticAberrationB", .leftOut(.notInRedlamp(row: nil), PhotoNote.manualAberration)),
            ("Defringe", .leftOut(.notInRedlamp(row: nil), PhotoNote.defringeMenu)),
            ("DefringePurpleAmount", .unchecked(.defringePurpleAmount)),
            ("DefringePurpleHueLo", .unchecked(.defringePurpleHueLow)),
            ("DefringePurpleHueHi", .unchecked(.defringePurpleHueHigh)),
            ("DefringeGreenAmount", .unchecked(.defringeGreenAmount)),
            ("DefringeGreenHueLo", .unchecked(.defringeGreenHueLow)),
            ("DefringeGreenHueHi", .unchecked(.defringeGreenHueHigh)),
            ("LensManualDistortionAmount", .unchecked(.lensDistortion)),
            ("VignetteAmount", .unchecked(.lensVignetting)),
            ("VignetteMidpoint", .unchecked(.lensVignettingMidpoint)),
        ], preset: .ignored(Note.lens))

    private static let transformRules: [(key: String, rule: LightroomRule)] = perPhoto(
        [("PerspectiveUpright", .upright), ("UprightVersion", .upright), ("Upright*", .upright)],
        preset: .ignored(Note.upright),
    ) + perPhoto([
        ("PerspectiveVertical", .unchecked(.transformVertical)),
        ("PerspectiveHorizontal", .unchecked(.transformHorizontal)),
        ("PerspectiveRotate", .unchecked(.transformRotate)),
        ("PerspectiveScale", .unchecked(.transformScale)),
        ("PerspectiveAspect", .unchecked(.transformAspect)),
        ("PerspectiveX", .unchecked(.transformOffsetX)),
        ("PerspectiveY", .unchecked(.transformOffsetY)),
    ], preset: .ignored(Note.transform))

    private static let effectsRules: [(key: String, rule: LightroomRule)] = [
        ("PostCropVignetteAmount", .parameter(.vignetteAmount)),
        ("PostCropVignetteMidpoint", .parameter(.vignetteMidpoint)),
        ("PostCropVignetteRoundness", .parameter(.vignetteRoundness)),
        ("PostCropVignetteFeather", .parameter(.vignetteFeather)),
        ("PostCropVignetteHighlightContrast", .parameter(.vignetteHighlights)),
        ("PostCropVignetteStyle", .vignetteStyle),
        ("GrainAmount", .parameter(.grainAmount)),
        ("GrainSize", .parameter(.grainSize)),
        ("GrainFrequency", .parameter(.grainRoughness)),
    ]

    private static let calibrationRules: [(key: String, rule: LightroomRule)] = perPhoto([
        ("ShadowTint", .unchecked(.calibrationShadowsTint)),
        ("RedHue", .unchecked(.calibrationRedHue)),
        ("RedSaturation", .unchecked(.calibrationRedSaturation)),
        ("GreenHue", .unchecked(.calibrationGreenHue)),
        ("GreenSaturation", .unchecked(.calibrationGreenSaturation)),
        ("BlueHue", .unchecked(.calibrationBlueHue)),
        ("BlueSaturation", .unchecked(.calibrationBlueSaturation)),
    ], preset: .ignored(Note.calibration))

    private static let cropRules: [(key: String, rule: LightroomRule)] = perPhoto([
        ("HasCrop", .crop), ("CropTop", .crop), ("CropLeft", .crop), ("CropBottom", .crop), ("CropRight", .crop),
        ("CropAngle", .crop), ("CropConstrainToWarp", .metadata), ("CropConstrainToUnitSquare", .metadata),
    ], preset: .ignored(Note.crop)) + perPhoto(
        ["CropWidth", "CropHeight", "CropUnit", "CropUnits"]
            .map { ($0, .leftOut(.notInRedlamp(row: nil), Note.cropSize)) },
        preset: .ignored(Note.cropSize),
    )

    private static let localRules: [(key: String, rule: LightroomRule)] = perPhoto([
        ("MaskGroupBasedCorrections", .masks), ("GradientBasedCorrections", .masks),
        ("CircularGradientBasedCorrections", .masks), ("PaintBasedCorrections", .masks),
        ("DepthBasedCorrections", .masks), ("RangeMaskMapInfo", .metadata), ("DepthMapInfo", .metadata),
    ], preset: .ignored(Note.masks)) + perPhoto(
        [("RetouchAreas", .spots), ("RetouchInfo", .spots)],
        preset: .ignored(Note.spots),
    ) + perPhoto(
        [("RedEyeInfo", .leftOut(.notInRedlamp(row: "OTH-01"), PhotoNote.redEye))],
        preset: .ignored(Note.redEye),
    ) + perPhoto(
        [("LensBlur", .leftOut(.notInRedlamp(row: "OTH-03"), PhotoNote.lensBlur))],
        preset: .ignored(Note.lensBlur),
    ) + perPhoto(
        [("PointColors", .leftOut(.notYetChecked, PhotoNote.pointColor))],
        preset: .ignored(Note.pointColor),
    ) + perPhoto(
        [("HDREditMode", .leftOut(.notInRedlamp(row: "TON-42"), PhotoNote.hdr))],
        preset: .unlessOff(Note.hdr),
    ) + perPhoto(
        ["HDRMaxValue", "SDRBlend", "SDRBrightness", "SDRContrast", "SDRHighlights", "SDRShadows", "SDRWhites"].map {
            ($0, .leftOut(.notInRedlamp(row: "TON-42"), PhotoNote.hdr, switchedBy: "HDREditMode"))
        },
        preset: .unlessOff(Note.hdr, switchedBy: "HDREditMode"),
    )

    /// Settings a photo's edit carries by each one's own rule, which a preset's carry by `preset`.
    private static func perPhoto(
        _ rules: [(String, LightroomPhotoRule)],
        preset: LightroomRule.Preset,
    ) -> [(key: String, rule: LightroomRule)] {
        rules.map { key, photo in (key, .perPhoto(photo, preset: preset)) }
    }

    private typealias PhotoNote = LightroomPhoto.Note

    /// The preset's settings in report order, each with its rule: nil for one Redlamp doesn't know.
    /// Blank ones are left out.
    static func orderedSettings(_ settings: CameraRawSettings) -> [(key: String, rule: LightroomRule?)] {
        order(settings, by: rules)
    }

    /// Each rule's key is looked up among the settings', never the other way: a lookup in a shared table counts
    /// references to it, which threads converting at once contend for.
    @inline(never)
    private static func order(
        _ settings: CameraRawSettings,
        by rules: [(key: String, rule: LightroomRule)],
    ) -> [(key: String, rule: LightroomRule?)] {
        var remaining = Set(settings.values.keys.filter { !settings.isBlank($0) })
        var ordered: [(key: String, rule: LightroomRule?)] = []
        ordered.reserveCapacity(remaining.count)
        for (pattern, rule) in rules where !remaining.isEmpty {
            guard pattern.hasSuffix("*") else {
                if remaining.remove(pattern) != nil {
                    ordered.append((pattern, rule))
                }
                continue
            }
            let prefix = pattern.utf8.dropLast()
            for key in remaining.filter({ $0.utf8.starts(with: prefix) }).sorted() {
                remaining.remove(key)
                ordered.append((key, rule))
            }
        }
        return ordered + remaining.sorted().map { ($0, nil) }
    }
}

extension LightroomPreset {
    /// The report's reasons and explanations.
    enum Note {
        static let unknown = "Redlamp doesn't read this setting."
        static let unreadable = "Its value can't be read."
        static let camera = "Redlamp's recipes apply to photos from every camera."
        static let profile = "Redlamp doesn't convert Lightroom's profiles, so the photo keeps its Base Look."
        static let auto = "Lightroom works Auto out for each photo, and a recipe holds fixed values."
        static let lens = "Redlamp keeps lens corrections with each photo, so recipes don't carry them."
        static let lensProfileOn = lens + " Redlamp applies a photo's own lens profile unless it's switched off."
        static let lensProfileOff = lens + " This preset switches the lens profile off; Redlamp applies it by default."
        static let upright = """
        Upright is worked out for each photo, and Redlamp keeps Transform with each photo, so recipes don't carry it.
        """
        static let transform = "Redlamp keeps Transform with each photo, so recipes don't carry it."
        static let calibration = "Redlamp keeps calibration with each photo, so recipes don't carry it."
        static let crop = "Redlamp keeps the crop with each photo, so recipes don't carry it."
        static let cropSize = "The size Camera Raw crops to; Redlamp sets the size when exporting."
        static let masks = "Redlamp keeps masks with each photo, so recipes don't carry them."
        static let spots = "Redlamp keeps Heal and Clone spots with each photo, so recipes don't carry them."
        static let redEye = "Red-eye corrections belong to each photo, so recipes don't carry them."
        static let lensBlur = "Redlamp has no Lens Blur yet."
        static let pointColor = "Redlamp has no Point Color yet."
        static let hdr = "Redlamp doesn't edit in HDR yet."
        static let kelvinUsed = """
        Redlamp has one white balance for raw and rendered photos, so the preset's Temperature \
        and Tint are used.
        """
        static let incremental = """
        Lightroom's relative white balance for JPEGs and other rendered photos, carried as Red \
        and Blue Shift, one unit for one (±100 is ±0.3 EV on red or blue, not yet measured against Lightroom). \
        Redlamp applies the shift to raw photos too.
        """
        static let incrementalCustom = """
        Custom white balance from IncrementalTemperature and IncrementalTint, carried \
        as Red and Blue Shift.
        """
        static let customWithoutValues = "Custom white balance, but the preset has no temperature or tint to set."
        static let grayMix = """
        Redlamp has no separate B&W mix: its Color Mixer's Luminance brightens or darkens each \
        colour before the photo turns grey.
        """
        static let grayMixInColor = """
        Lightroom applies the B&W mix only to black-and-white photos, and this preset \
        doesn't make one.
        """
        static let luminanceInBlackAndWhite = """
        Lightroom doesn't apply HSL Luminance to a black-and-white photo; \
        Redlamp's Luminance sliders hold the B&W mix instead.
        """
        static let pointCurveSize = "Redlamp's point curve holds up to 64 points."
        static let vignetteStyle = "Rendered as Highlight Priority, the only style Redlamp's vignette has."
        static let splitToningBlending = """
        Not in this Split Toning preset: Lightroom renders Split Toning with \
        Blending at 100.
        """

        static let replacedExposure = "Process 2010's Exposure, which Process 2012 replaced with Exposure2012."
        static let replacedRecovery = "Process 2010's Recovery, which Process 2012 replaced with Highlights2012."
        static let replacedFillLight = "Process 2010's Fill Light, which Process 2012 replaced with Shadows2012."
        static let replacedBlacks = "Process 2010's Blacks, which Process 2012 replaced with Blacks2012."
        static let replacedContrast = "Process 2010's Contrast, which Process 2012 replaced with Contrast2012."
        static let replacedClarity = "Process 2010's Clarity, which Process 2012 replaced with Clarity2012."
        static let replacedPointCurve = """
        Process 2010's point curve, which Process 2012 replaced with ToneCurvePV2012.
        """

        static func setByMode(_ mode: WhiteBalanceMode) -> String {
            "The white balance, \(mode.name), sets it."
        }

        static func unknownWhiteBalance(_ name: String) -> String {
            "Lightroom's white balance “\(name)” isn't one Redlamp has."
        }

        static func clamped(_ text: String) -> String {
            "Clamped to \(text), the end of Redlamp's range."
        }

        static func look(_ name: String) -> String {
            "The profile “\(name)” isn't carried over: \(profile)"
        }
    }
}
