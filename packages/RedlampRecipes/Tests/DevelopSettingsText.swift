import Foundation

/// A photo's develop settings written in the tests from ExifTool's table of `crs` tags, never copied from
/// Adobe's files or a catalog: a tree that writes itself as the Lua a Lightroom Classic catalog keeps and
/// as an XMP sidecar in each RDF form (`DevelopSettings`).
enum DevelopSetting: Sendable {
    case number(Double)
    /// A slider's value, which XMP signs as Lightroom signs it (`+0.35`).
    case slider(Double)
    case text(String)
    case flag(Bool)
    /// A point curve's x and y numbers, one after the other, as Lua keeps them.
    case curve([Double])
    case list([String])
    case structure([(String, DevelopSetting)])
    case structures([[(String, DevelopSetting)]])

    var isSimple: Bool {
        switch self {
        case .number, .slider, .text, .flag: true
        case .curve, .list, .structure, .structures: false
        }
    }
}

typealias DevelopFields = [(String, DevelopSetting)]

enum DevelopSettings {
    /// The RDF forms of a sidecar (XMP Specification Part 1, 7.4–7.9).
    enum Form: String, CaseIterable, Sendable {
        /// As Adobe's XMP toolkit writes one: simple values and fields as attributes, a structure with other
        /// fields as a nested `rdf:Description`.
        case compact
        /// Every value an element, each structure `rdf:parseType="Resource"`, arrays of them in `rdf:Bag`.
        case resources
        /// Every value an element, each structure a nested `rdf:Description` of elements.
        case descriptions
    }

    /// A number's shortest text, a whole one without a fraction.
    static func shortest(_ number: Double) -> String {
        number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
    }

    /// A curve's numbers as XMP's points.
    static func points(_ numbers: [Double]) -> [String] {
        stride(from: 0, to: numbers.count - 1, by: 2).map { "\(shortest(numbers[$0])), \(shortest(numbers[$0 + 1]))" }
    }

    // MARK: - Lua

    /// The settings as a catalog keeps them (`Adobe_imageDevelopSettings.text`), one to a line.
    static func lua(_ fields: DevelopFields) -> String {
        "s = " + table(fields, depth: 1)
    }

    private static func table(_ fields: DevelopFields, depth: Int) -> String {
        let indent = String(repeating: "\t", count: depth)
        let lines = fields.map { "\(indent)\($0.0) = \(lua($0.1, depth: depth + 1)),\n" }.joined()
        return "{\n" + lines + String(repeating: "\t", count: depth - 1) + "}"
    }

    private static func lua(_ setting: DevelopSetting, depth: Int) -> String {
        switch setting {
        case let .number(number), let .slider(number): shortest(number)
        case let .text(text): quoted(text)
        case let .flag(flag): flag ? "true" : "false"
        case let .curve(numbers): "{ " + numbers.map { shortest($0) }.joined(separator: ", ") + " }"
        case let .list(items): "{ " + items.map { quoted($0) }.joined(separator: ", ") + " }"
        case let .structure(fields): table(fields, depth: depth)
        case let .structures(items):
            "{\n" + items.map { String(repeating: "\t", count: depth) + table($0, depth: depth + 1) + ",\n" }.joined()
                + String(repeating: "\t", count: depth - 1) + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - XMP

    /// The settings as a photo's sidecar in `form`, with the photo's own TIFF metadata beside them.
    static func xmp(_ fields: DevelopFields, form: Form) -> Data {
        let attributes = form == .compact ? fields.filter(\.1.isSimple) : []
        let elements = form == .compact ? fields.filter { !$0.1.isSimple } : fields
        let attributeText = attributes.map { "\n    crs:\($0.0)=\"\(PresetXMP.escaped(xmpText($0.1)))\"" }.joined()
        let elementText = elements.map { "\n" + element($0.0, $0.1, form: form, depth: 3) }.joined()
        return Data(PresetXMP.packet("""
          <rdf:Description rdf:about=""
            xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
            xmlns:crs="\(PresetXMP.namespace)"
            tiff:Make="Example"\(attributeText)>\(elementText)
          </rdf:Description>
        """).utf8)
    }

    private static func xmpText(_ setting: DevelopSetting) -> String {
        switch setting {
        case let .number(number): shortest(number)
        case let .slider(number): number > 0 ? "+" + shortest(number) : shortest(number)
        case let .text(text): text
        case let .flag(flag): flag ? "True" : "False"
        case .curve, .list, .structure, .structures: ""
        }
    }

    private static func element(_ name: String, _ setting: DevelopSetting, form: Form, depth: Int) -> String {
        let indent = String(repeating: " ", count: depth)
        let tag = "crs:" + name
        switch setting {
        case .number, .slider, .text, .flag:
            return "\(indent)<\(tag)>\(PresetXMP.escaped(xmpText(setting)))</\(tag)>"
        case let .curve(numbers):
            return element(name, .list(points(numbers)), form: form, depth: depth)
        case let .list(items):
            let lines = items.map { "\n\(indent)  <rdf:li>\(PresetXMP.escaped($0))</rdf:li>" }.joined()
            return "\(indent)<\(tag)>\n\(indent) <rdf:Seq>\(lines)\n\(indent) </rdf:Seq>\n\(indent)</\(tag)>"
        case let .structure(fields):
            return structure(tag, fields, form: form, depth: depth)
        case let .structures(items):
            let array = form == .resources ? "rdf:Bag" : "rdf:Seq"
            let lines = items.map { "\n" + structure("rdf:li", $0, form: form, depth: depth + 2) }.joined()
            return "\(indent)<\(tag)>\n\(indent) <\(array)>\(lines)\n\(indent) </\(array)>\n\(indent)</\(tag)>"
        }
    }

    /// A structure as the property or array item `tag`.
    private static func structure(_ tag: String, _ fields: DevelopFields, form: Form, depth: Int) -> String {
        let indent = String(repeating: " ", count: depth)
        let simple = fields.filter(\.1.isSimple)
        let attributes = simple.map { " crs:\($0.0)=\"\(PresetXMP.escaped(xmpText($0.1)))\"" }.joined()
        func elements(_ fields: DevelopFields, depth: Int) -> String {
            fields.map { "\n" + element($0.0, $0.1, form: form, depth: depth) }.joined()
        }
        switch form {
        case .compact where simple.count == fields.count:
            return "\(indent)<\(tag)\(attributes)/>"
        case .compact:
            let others = elements(fields.filter { !$0.1.isSimple }, depth: depth + 2)
            return "\(indent)<\(tag)>\n\(indent) <rdf:Description\(attributes)>\(others)\n\(indent) </rdf:Description>"
                + "\n\(indent)</\(tag)>"
        case .resources:
            return "\(indent)<\(tag) rdf:parseType=\"Resource\">\(elements(fields, depth: depth + 1))\n\(indent)</\(tag)>"
        case .descriptions:
            return "\(indent)<\(tag)>\n\(indent) <rdf:Description>\(elements(fields, depth: depth + 2))"
                + "\n\(indent) </rdf:Description>\n\(indent)</\(tag)>"
        }
    }
}

// MARK: - A photo's settings

extension DevelopSettings {
    /// A raw's develop settings as Lightroom Classic keeps them in Process 2012 and later: every global
    /// setting, the point curves and a profile with its parameters; `masks` of the mask group's four
    /// corrections, which between them have each kind of component, and with all four a legacy gradient;
    /// with `spots`, a heal and a clone; with `upright`, Guided Upright with its guides. `seed` varies the
    /// values.
    static func photo(_ seed: Int = 0, masks: Int = 4, spots: Bool = true, upright: Bool = true) -> DevelopFields {
        var fields = basic(seed) + mixer(seed) + grading(seed) + detail(seed) + lens(seed)
        fields += transform(seed, upright: upright) + effects(seed) + curves(seed)
        fields.append(("Look", look(seed)))
        fields += maskGroups(seed, count: masks)
        if spots {
            fields += retouch(seed)
        }
        return fields
    }

    /// A slider from `-range` to `range` in steps of one over `scale`, varied by `seed` and `key`.
    private static func vary(_ seed: Int, _ key: Int, _ range: Int, scale: Int = 1) -> DevelopSetting {
        let step = abs(seed &* 7919 &+ key &* 104_729) % (2 * range + 1) - range
        return .slider(Double(step) / Double(scale))
    }

    private static func sliders(_ seed: Int, _ names: [String], range: Int, scale: Int = 1, key: Int) -> DevelopFields {
        names.enumerated().map { ($0.element, vary(seed, key + $0.offset, range, scale: scale)) }
    }

    private static func basic(_ seed: Int) -> DevelopFields {
        let fixed: DevelopFields = [
            ("Version", .text("15.4")), ("ProcessVersion", .text("15.4")),
            ("WhiteBalance", .text(seed % 3 == 0 ? "Custom" : "As Shot")),
            ("Temperature", .number(Double(4500 + seed % 2000))), ("Tint", vary(seed, 1, 30)),
            ("CameraProfile", .text("Adobe Standard")), (
                "CameraProfileDigest",
                .text("3C1F7E9A0B2D4C6E8F1A3B5C7D9E0F2A"),
            ),
            ("ConvertToGrayscale", .flag(false)), ("HasSettings", .flag(true)), ("AlreadyApplied", .flag(false)),
            ("AutoLateralCA", .number(1)), ("AutoWhiteVersion", .number(134_348_800)),
            ("OverrideLookVignette", .flag(false)), ("ToneCurveName2012", .text("Custom")),
            ("HasCrop", .flag(true)), ("CropTop", .number(0.0521)), ("CropLeft", .number(0.031)),
            ("CropBottom", .number(0.9479)), ("CropRight", .number(0.969)), (
                "CropAngle",
                vary(seed, 2, 450, scale: 100),
            ),
            ("CropConstrainToWarp", .number(0)),
        ]
        let tone = ["Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012", "Texture"]
        let presence = ["Clarity2012", "Dehaze", "Vibrance", "Saturation"]
        return fixed + sliders(seed, ["Exposure2012"], range: 300, scale: 100, key: 3)
            + sliders(seed, tone + presence, range: 100, key: 4)
    }

    private static let bands = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]

    private static func mixer(_ seed: Int) -> DevelopFields {
        sliders(seed, bands.map { "HueAdjustment" + $0 }, range: 100, key: 20)
            + sliders(seed, bands.map { "SaturationAdjustment" + $0 }, range: 100, key: 30)
            + sliders(seed, bands.map { "LuminanceAdjustment" + $0 }, range: 100, key: 40)
            + sliders(seed, bands.map { "GrayMixer" + $0 }, range: 100, key: 50)
    }

    private static func grading(_ seed: Int) -> DevelopFields {
        let hues = ["SplitToningShadowHue", "SplitToningHighlightHue", "ColorGradeMidtoneHue", "ColorGradeGlobalHue"]
        let others = [
            "SplitToningShadowSaturation", "SplitToningHighlightSaturation", "SplitToningBalance",
            "ColorGradeMidtoneSat",
            "ColorGradeShadowLum", "ColorGradeMidtoneLum", "ColorGradeHighlightLum", "ColorGradeGlobalSat",
            "ColorGradeGlobalLum",
        ]
        let wheels: DevelopFields = hues.map { name in (name, .number(Double((seed + name.count * 29) % 360))) }
        return wheels + sliders(seed, others, range: 100, key: 60) + [("ColorGradeBlending", .number(50))]
    }

    private static func detail(_ seed: Int) -> DevelopFields {
        [
            ("Sharpness", .number(40)), ("SharpenRadius", .number(1)), ("SharpenDetail", .number(25)),
            ("SharpenEdgeMasking", .number(0)), ("LuminanceSmoothing", .number(Double(seed % 40))),
            ("LuminanceNoiseReductionDetail", .number(50)), ("LuminanceNoiseReductionContrast", .number(0)),
            ("ColorNoiseReduction", .number(25)), ("ColorNoiseReductionDetail", .number(50)),
            ("ColorNoiseReductionSmoothness", .number(50)),
        ]
    }

    private static func lens(_ seed: Int) -> DevelopFields {
        [
            ("LensProfileEnable", .number(1)), ("LensProfileSetup", .text("LensDefaults")),
            ("LensProfileName", .text("Example 35mm F1.8")), ("LensProfileFilename", .text("Example 35mm F1.8.lcp")),
            ("LensProfileDistortionScale", .number(100)), ("LensProfileVignettingScale", .number(100)),
            ("LensManualDistortionAmount", vary(seed, 70, 20)), ("VignetteAmount", .number(0)),
            ("DefringePurpleAmount", .number(0)), ("DefringePurpleHueLo", .number(30)),
            ("DefringePurpleHueHi", .number(70)), ("DefringeGreenAmount", .number(0)),
            ("DefringeGreenHueLo", .number(40)), ("DefringeGreenHueHi", .number(60)),
        ]
    }

    private static func transform(_ seed: Int, upright: Bool) -> DevelopFields {
        let fixed: DevelopFields = [
            ("PerspectiveUpright", .number(upright ? 5 : 0)), ("PerspectiveScale", .number(100)),
            ("PerspectiveAspect", .number(0)), ("PerspectiveX", .number(0)), ("PerspectiveY", .number(0)),
            ("UprightVersion", .number(151_388_160)), ("UprightCenterMode", .number(0)),
            ("UprightCenterNormX", .number(0.5)), ("UprightCenterNormY", .number(0.5)),
            ("UprightFocalMode", .number(0)), ("UprightFocalLength35mm", .number(35)), ("UprightPreview", .flag(false)),
            ("UprightFourSegmentsCount", .number(upright ? 2 : 0)), ("UprightTransformCount", .number(upright ? 6 : 0)),
        ]
        let guides: DevelopFields = [
            ("UprightFourSegments_0", .text("0.210000 0.080000 0.240000 0.910000")),
            ("UprightFourSegments_1", .text("0.780000 0.100000 0.750000 0.880000")),
        ]
        let solved: DevelopFields = (0 ..< 6).map { ("UprightTransform_\($0)", .text("1 0 0 0 1 0 0 0 1")) }
        return fixed + (upright ? guides + solved : [])
            + sliders(seed, ["PerspectiveVertical", "PerspectiveHorizontal"], range: 100, key: 80)
            + sliders(seed, ["PerspectiveRotate"], range: 100, scale: 10, key: 82)
    }

    private static func effects(_ seed: Int) -> DevelopFields {
        [
            ("PostCropVignetteAmount", vary(seed, 90, 100)), ("PostCropVignetteMidpoint", .number(50)),
            ("PostCropVignetteFeather", .number(50)), ("PostCropVignetteRoundness", .number(0)),
            ("PostCropVignetteStyle", .number(1)), ("PostCropVignetteHighlightContrast", .number(0)),
            ("GrainAmount", .number(Double(seed % 30))), ("GrainSize", .number(25)), ("GrainFrequency", .number(50)),
            ("ShadowTint", .number(0)), ("RedHue", .number(0)), ("RedSaturation", .number(0)), ("GreenHue", .number(0)),
            ("GreenSaturation", .number(0)), ("BlueHue", vary(seed, 95, 20)), ("BlueSaturation", vary(seed, 96, 20)),
            ("PointColors", .list([])), ("RedEyeInfo", .list([])), ("RetouchInfo", .list([])),
        ]
    }

    private static func curves(_ seed: Int) -> DevelopFields {
        [
            ("ToneCurvePV2012", .curve([0, 0, 64, Double(52 + seed % 12), 128, 128, 192, 200, 255, 255])),
            ("ToneCurvePV2012Red", .curve([0, 0, 255, 255])), ("ToneCurvePV2012Green", .curve([0, 0, 255, 255])),
            ("ToneCurvePV2012Blue", .curve([0, 0, 128.5, 120, 255, 255])),
        ]
    }

    private static func look(_ seed: Int) -> DevelopSetting {
        .structure([
            ("Name", .text("Adobe Color")), ("Amount", .number(seed % 4 == 0 ? 1 : 0.85)),
            ("UUID", .text("4F1C80B26D7E4A5B9C3D2E1F0A9B8C7D")), ("SupportsAmount", .flag(false)),
            ("SupportsMonochrome", .flag(false)), ("SupportsOutputReferred", .flag(false)),
            ("Parameters", .structure([
                ("Version", .text("15.4")), ("ProcessVersion", .text("11.0")), ("ConvertToGrayscale", .flag(false)),
                ("CameraProfile", .text("Adobe Standard")), ("LookTable", .text("9A2C6F0E3B7D4815A6C2E9F1B3D5A7C9")),
                ("ToneCurvePV2012", .curve([0, 0, 22, 16, 40, 35, 127, 127, 224, 230, 240, 246, 255, 255])),
                ("ToneCurvePV2012Red", .curve([0, 0, 255, 255])),
            ])),
        ])
    }

    // MARK: - Masks and spots

    private static func maskGroups(_ seed: Int, count: Int) -> DevelopFields {
        guard count > 0 else { return [] }
        let corrections: [DevelopFields] = [
            correction("Sky", seed, masks: [linear(seed), sky()]),
            correction("Subject", seed, masks: [radial(seed), brush(seed, dabs: 24, blend: 1)]),
            correction("Shadows", seed, masks: [luminanceRange(), colorRange(), depthRange()]),
            correction("Faces", seed, masks: [person()]),
        ]
        let group: DevelopFields = [("MaskGroupBasedCorrections", .structures(Array(corrections.prefix(count))))]
        guard count >= corrections.count else { return group }
        let legacy = correction("Graduated Filter", seed, masks: [linear(seed)])
        return group + [("GradientBasedCorrections", .structures([legacy]))]
    }

    private static func correction(_ name: String, _ seed: Int, masks: [DevelopFields]) -> DevelopFields {
        let fixed: DevelopFields = [
            ("What", .text("Correction")), ("CorrectionAmount", .number(1)), ("CorrectionActive", .flag(true)),
            ("CorrectionName", .text(name)), ("CorrectionSyncID", .text("6E3D2A61C4F84B1D9A0F\(name.count)")),
        ]
        let local = ["LocalContrast2012", "LocalHighlights2012", "LocalShadows2012", "LocalClarity2012"]
        return fixed + sliders(seed, ["LocalExposure2012"], range: 200, scale: 100, key: name.count)
            + sliders(seed, local + ["LocalTemperature", "LocalSaturation"], range: 100, key: 100 + name.count)
            + [("CorrectionMasks", .structures(masks))]
    }

    private static func mask(_ what: String, blend: Int = 0, _ shape: DevelopFields) -> DevelopFields {
        [
            ("What", .text(what)), ("MaskActive", .flag(true)), ("MaskBlendMode", .number(Double(blend))),
            ("MaskInverted", .flag(false)), ("MaskValue", .number(1)), ("MaskVersion", .text("1")),
        ] + shape
    }

    private static func linear(_ seed: Int) -> DevelopFields {
        mask("Mask/Gradient", [
            ("ZeroX", .number(0.5)), ("ZeroY", .number(0.62)), ("FullX", .number(0.5 + Double(seed % 5) / 100)),
            ("FullY", .number(0.31)),
        ])
    }

    private static func radial(_ seed: Int) -> DevelopFields {
        mask("Mask/CircularGradient", [
            ("Top", .number(0.2)), ("Left", .number(0.3)), ("Bottom", .number(0.7)), ("Right", .number(0.65)),
            ("Angle", .number(Double(seed % 90))), ("Midpoint", .number(50)), ("Roundness", .number(0)),
            ("Feather", .number(50)), ("Flipped", .flag(false)),
        ])
    }

    private static func brush(_ seed: Int, dabs count: Int, blend: Int = 0) -> DevelopFields {
        let dabs = (0 ..< count).map { "d \(0.4 + Double(($0 + seed) % 50) / 250) \(0.5 + Double($0 % 20) / 200)" }
        return mask("Mask/Paint", blend: blend, [
            ("Radius", .number(0.04)), ("Flow", .number(1)), ("CenterWeight", .number(0)), ("Dabs", .list(dabs)),
        ])
    }

    private static func sky() -> DevelopFields {
        mask("Mask/Image", blend: 2, [("MaskSubType", .text("2")), ("ReferencePoint", .text("0.500000 0.300000"))])
    }

    private static func person() -> DevelopFields {
        mask("Mask/Image", [
            ("MaskSubType", .text("3")), ("MaskName", .text("Person 1")),
            ("Masks", .structures([sky(), brush(0, dabs: 3, blend: 1)])),
        ])
    }

    private static func luminanceRange() -> DevelopFields {
        mask("Mask/RangeMask", blend: 2, [("CorrectionRangeMask", .structure([
            ("Version", .text("3")), ("Type", .text("1")), ("LumMin", .number(0.1)), ("LumMax", .number(0.6)),
            ("LumFeather", .number(0.5)), ("LumRange", .text("0.1 0.2 0.5 0.6")),
        ]))])
    }

    private static func colorRange() -> DevelopFields {
        let area: DevelopFields = [
            ("AreaComponents", .list(["0.200000 0.300000 0.250000 0.350000"])),
            ("ColorRangeMaskAreaSampleInfo", .text("0.400000 0.550000 0.120000 0.300000")),
        ]
        return mask("Mask/RangeMask", blend: 2, [("CorrectionRangeMask", .structure([
            ("Version", .text("3")), ("Type", .text("2")), ("ColorAmount", .number(0.5)), ("SampleType", .number(0)),
            ("AreaModels", .structures([area])),
        ]))])
    }

    private static func depthRange() -> DevelopFields {
        mask("Mask/RangeMask", blend: 2, [("CorrectionRangeMask", .structure([
            ("Version", .text("3")), ("Type", .text("3")), ("DepthMin", .number(0.1)), ("DepthMax", .number(0.4)),
            ("DepthFeather", .number(0.25)),
        ]))])
    }

    private static func retouch(_ seed: Int) -> DevelopFields {
        let circle = mask("Mask/Ellipse", [
            ("X", .number(0.6)), ("Y", .number(0.45)), ("SizeX", .number(0.02)), ("SizeY", .number(0.02)),
            ("Alpha", .number(0)), ("CenterValue", .number(1)), ("PerimeterValue", .number(0)), ("Angle", .number(0)),
            ("Feather", .number(0.5)),
        ])
        let heal: DevelopFields = [
            ("SpotType", .text("heal")), ("SourceState", .text("sourceSetExplicitly")), ("Method", .text("gaussian")),
            ("SourceX", .number(0.62)), ("OffsetY", .number(-0.04)), ("Opacity", .number(1)), ("Feather", .number(0.5)),
            ("Seed", .number(Double(seed % 100))), ("Masks", .structures([circle])),
        ]
        let clone: DevelopFields = [
            ("SpotType", .text("clone")), ("SourceState", .text("sourceAutoComputed")), ("Opacity", .number(0.8)),
            ("Masks", .structures([brush(seed, dabs: 8)])),
        ]
        return [("RetouchAreas", .structures([heal, clone]))]
    }
}
