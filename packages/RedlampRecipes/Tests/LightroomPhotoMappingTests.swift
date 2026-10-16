import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// A photo's develop settings converted to its whole edit (EDT-23, EDT-12), a test for each row of the
/// Lightroom edits design's table: settings written as a catalog keeps them, in Lua from ExifTool's table of
/// `crs` tags, and the edit's values and the report's outcomes out.
struct LightroomPhotoMappingTests {
    private typealias Note = LightroomPreset.Note
    private typealias PhotoNote = LightroomPhoto.Note

    static let raw = LightroomPhotoContext(size: PixelSize(width: 6000, height: 4000))
    static let catalog = URL(filePath: "/Photos/Lightroom Catalog.lrcat")

    static func convert(_ lua: String, photo: LightroomPhotoContext = raw) throws -> LightroomPhotoImport {
        try LightroomPhoto.convert(
            CameraRawSettings(lua: lua), photo: photo, source: .catalog(catalog, photo: 42, digest: "D1"),
            date: Date(timeIntervalSince1970: 0),
        )
    }

    // MARK: - The global settings, as EDT-11 maps them

    @Test func `Basic, Presence, the Color Mixer, Color Grading, Detail, Effects and the curves map as presets do`()
        throws {
        let imported = try Self.convert("""
        s = { ProcessVersion = "15.4", ConvertToGrayscale = false,
        	Exposure2012 = 0.65, Contrast2012 = 12, Highlights2012 = -45, Shadows2012 = 38, Whites2012 = 7,
        	Blacks2012 = -15, Texture = 10, Clarity2012 = 8, Dehaze = 4.5, Vibrance = 20, Saturation = -5,
        	ParametricDarks = 6, ParametricShadowSplit = 30,
        	ToneCurvePV2012 = { 0, 0, 64, 58, 128, 128, 192, 200, 255, 255 },
        	HueAdjustmentRed = 5, SaturationAdjustmentGreen = -35, LuminanceAdjustmentBlue = -12, GrayMixerRed = -10,
        	SplitToningShadowHue = 205, SplitToningShadowSaturation = 20, ColorGradeMidtoneHue = 40,
        	ColorGradeBlending = 60, SplitToningBalance = 15,
        	Sharpness = 60, SharpenRadius = 1.2, LuminanceSmoothing = 20, ColorNoiseReduction = 25,
        	PostCropVignetteAmount = -18, PostCropVignetteStyle = 1, GrainAmount = 12 }
        """)
        let recipe = imported.recipe
        let expected: [ParameterID: Double] = [
            .exposure: 0.65, .contrast: 12, .highlights: -45, .shadows: 38, .whites: 7, .blacks: -15, .texture: 10,
            .clarity: 8, .dehaze: 4.5, .vibrance: 20, .saturation: -5, .curveDarks: 6, .curveSplitShadows: 30,
            .hueRed: 5, .saturationGreen: -35, .luminanceBlue: -12, .gradeShadowsHue: 205,
            .gradeShadowsSaturation: 20, .gradeMidtonesHue: 40, .gradeBlending: 60, .gradeBalance: 15,
            .sharpenAmount: 60, .sharpenRadius: 1.2, .noiseLuminance: 20, .vignetteAmount: -18, .grainAmount: 12,
        ]
        for (parameter, value) in expected {
            #expect(recipe[parameter] == value, "\(parameter.rawValue)")
        }
        #expect(recipe.treatment == .color && recipe.pointCurve.count == 5)
        #expect(recipe.isDefault(.luminanceRed), "the B&W mix does nothing to a colour photo")
        #expect(imported.report.entries.allSatisfy { $0.outcome == .mapped })
        #expect(imported.report.entries.map(\.setting).contains("GrayMixerRed") == false)
        #expect(imported.report.conversion == .full && imported.report.processVersion == "15.4")
    }

    @Test func `a black-and-white photo's B&W mix becomes the Color Mixer's luminance, approximated`() throws {
        let imported = try Self.convert("""
        s = { ConvertToGrayscale = true, GrayMixerRed = -10, GrayMixerBlue = -40, LuminanceAdjustmentRed = 30 }
        """)
        #expect(imported.recipe.treatment == .blackAndWhite)
        #expect(imported.recipe[.luminanceRed] == -10 && imported.recipe[.luminanceBlue] == -40)
        #expect(imported.report.outcome("GrayMixerRed") == .approximated)
        #expect(imported.report.note("GrayMixerRed") == Note.grayMix)
        #expect(imported.report.outcome("LuminanceAdjustmentRed") == nil, "Lightroom doesn't apply it in B&W")
        #expect(imported.report.outcome("ConvertToGrayscale") == .mapped)
    }

    @Test func `red's, green's and blue's point curves map to their channels`() throws {
        let imported = try Self.convert("""
        s = { ToneCurvePV2012Red = { 0, 10, 255, 245 }, ToneCurvePV2012Green = { 0, 0, 255, 255 },
        	ToneCurvePV2012Blue = { 0, 0, 128, 140, 255, 255 } }
        """)
        #expect(imported.recipe[curve: .red] == [CurvePoint(x: 0, y: 10 / 255), CurvePoint(x: 1, y: 245 / 255)])
        #expect(imported.recipe[curve: .green] == EditRecipe.linearPointCurve)
        #expect(imported.recipe[curve: .blue].count == 3)
        #expect(imported.report.entries.map(\.outcome) == [.mapped, .mapped, .mapped])
    }

    // MARK: - White balance

    @Test(arguments: [
        ("As Shot", WhiteBalanceMode.asShot), ("Daylight", .daylight), ("Cloudy", .cloudy), ("Shade", .shade),
        ("Tungsten", .tungsten), ("Fluorescent", .fluorescent), ("Flash", .flash),
    ])
    func `a raw's named white balance maps, its temperature and tint set by it`(
        name: String,
        mode: WhiteBalanceMode,
    ) throws {
        let imported = try Self.convert("s = { WhiteBalance = \"\(name)\", Temperature = 5150, Tint = 6 }")
        #expect(imported.recipe.whiteBalanceMode == mode)
        #expect(imported.recipe.isDefault(.temperature) && imported.recipe.isDefault(.tint))
        #expect(imported.report.conversion == .full)
        #expect(imported.report.note("Temperature") == PhotoNote.setByMode(mode))
    }

    @Test func `a raw's custom white balance keeps its temperature and tint`() throws {
        let imported = try Self.convert("s = { WhiteBalance = \"Custom\", Temperature = 4850, Tint = -12 }")
        #expect(imported.recipe.whiteBalanceMode == .custom)
        #expect(imported.recipe[.temperature] == 4850 && imported.recipe[.tint] == -12)
        #expect(imported.report.conversion == .full)
    }

    @Test func `a raw's Auto white balance is kept as Custom with the values Lightroom found`() throws {
        let found = try Self.convert("s = { WhiteBalance = \"Auto\", Temperature = 6100, Tint = 4 }")
        #expect(found.recipe.whiteBalanceMode == .custom && found.recipe[.temperature] == 6100)
        #expect(found.report.outcome("WhiteBalance") == .approximated)
        #expect(found.report.note("WhiteBalance") == PhotoNote.autoWhiteBalance)
        let measured = try Self.convert("s = { WhiteBalance = \"Auto\" }")
        #expect(measured.recipe.whiteBalanceMode == .auto)
        #expect(measured.report.note("WhiteBalance") == PhotoNote.autoMeasured)
    }

    @Test func `a rendered photo's white balance is its shift, as Red and Blue Shift`() throws {
        let jpeg = LightroomPhotoContext(size: PixelSize(width: 4000, height: 3000), isRaw: false)
        let shifted = try Self.convert("""
        s = { WhiteBalance = "Custom", IncrementalTemperature = 20, IncrementalTint = -5, Temperature = 5500 }
        """, photo: jpeg)
        #expect(shifted.recipe.whiteBalanceMode == .asShot)
        #expect(shifted.recipe[.wbShiftRed] == 15 && shifted.recipe[.wbShiftBlue] == -25)
        #expect(shifted.report.outcome("IncrementalTemperature") == .approximated)
        #expect(shifted.report.outcome("Temperature") == nil, "a rendered photo's white balance is its shift")
        let asShot = try Self.convert("""
        s = { WhiteBalance = "As Shot", IncrementalTemperature = 0, IncrementalTint = 0 }
        """, photo: jpeg)
        #expect(asShot.recipe.whiteBalanceMode == .asShot && asShot.recipe.isDefault(.wbShiftRed))
        #expect(asShot.report.entries.map(\.setting) == ["WhiteBalance"] && asShot.report.conversion == .full)
        let auto = try Self.convert("s = { WhiteBalance = \"Auto\", IncrementalTemperature = -8 }", photo: jpeg)
        #expect(auto.recipe[.wbShiftBlue] == 8 && auto.report.note("WhiteBalance") == PhotoNote.autoShift)
    }

    // MARK: - Treatment and the profile

    @Test(arguments: [
        ("Adobe Color", BuiltInBaseLook.color), ("Adobe Vivid", .vivid), ("Adobe Portrait", .portrait),
        ("Adobe Landscape", .landscape), ("Adobe Neutral", .neutral), ("Adobe Monochrome", .monochrome),
    ])
    func `Adobe's raw profiles map to the Base Looks named as they are, with their amount`(
        name: String,
        look: BuiltInBaseLook,
    ) throws {
        let imported = try Self.convert("""
        s = { CameraProfile = "Adobe Standard", Look = { Name = "\(name)", Amount = 0.5 } }
        """)
        #expect(imported.recipe.baseLook == look.reference.withAmount(50))
        #expect(imported.report.outcome("Look") == .mapped && imported.report.note("Look") == nil)
        #expect(imported.report.outcome("CameraProfile") == .mapped)
        #expect(imported.report.note("CameraProfile") == PhotoNote.underLook(name))
    }

    @Test func `Adobe Standard and the camera's own profiles take the look the file embeds`() throws {
        let embedded = BaseLookReference(id: BaseLookReference.embeddedIDPrefix + "00ff", name: "Adobe Standard")
        var photo = Self.raw
        photo.embeddedLook = embedded
        let same = try Self.convert("s = { CameraProfile = \"Adobe Standard\" }", photo: photo)
        #expect(same.recipe.baseLook == embedded && same.report.outcome("CameraProfile") == .mapped)
        let other = try Self.convert("s = { CameraProfile = \"Camera Neutral\" }", photo: photo)
        #expect(other.recipe.baseLook == embedded && other.report.outcome("CameraProfile") == .approximated)
        #expect(other.report.note("CameraProfile") == PhotoNote.embedded("Adobe Standard", for: "Camera Neutral"))
        let dng = try Self.convert("s = { CameraProfile = \"Embedded\" }", photo: photo)
        #expect(dng.recipe.baseLook == embedded && dng.report.conversion == .full)
    }

    @Test(arguments: [
        ("Adobe Standard", BuiltInBaseLook.color), ("Camera Standard", .color), ("Camera Neutral", .neutral),
        ("Camera Faithful", .neutral), ("Camera Vivid", .vivid), ("Camera Portrait", .portrait),
        ("Camera Landscape", .landscape), ("Camera Monochrome", .monochrome),
    ])
    func `without an embedded look, the camera's own profiles take the nearest Base Look by name`(
        name: String,
        look: BuiltInBaseLook,
    ) throws {
        let imported = try Self.convert("s = { CameraProfile = \"\(name)\" }")
        #expect(imported.recipe.baseLook == look.reference)
        #expect(imported.report.outcome("CameraProfile") == .approximated)
        #expect(imported.report.note("CameraProfile") == PhotoNote.standIn(look.name, for: name))
    }

    @Test(arguments: [
        ("Camera PROVIA/Standard", FilmSlot.standard), ("Camera Velvia/Vivid", .vividSlide),
        ("Camera ASTIA/Soft", .softSlide), ("Camera CLASSIC CHROME", .chrome), ("Camera PRO Neg. Hi", .negativeHigh),
        ("Camera PRO Neg. Std", .negativeStandard), ("Camera CLASSIC Neg.", .negativeClassic),
        ("Camera Nostalgic Neg.", .negativeNostalgic), ("Camera ETERNA/Cinema", .cinema),
        ("Camera ETERNA BLEACH BYPASS", .bleach), ("Camera ACROS", .monochrome),
        ("Camera ACROS+Ye FILTER", .monochromeYellow), ("Camera ACROS+R FILTER", .monochromeRed),
        ("Camera ACROS+G FILTER", .monochromeGreen), ("Camera Sepia", .sepia),
    ])
    func `Fujifilm's film simulations take Redlamp's film looks of their kind`(name: String, slot: FilmSlot) throws {
        let imported = try Self.convert("s = { CameraProfile = \"\(name)\" }")
        #expect(imported.recipe.baseLook == slot.baseLook)
        #expect(imported.report.outcome("CameraProfile") == .approximated)
    }

    @Test func `a Fujifilm LUT imported for a slot stands in for its simulation`() throws {
        let imported = BaseLookReference(id: BaseLookReference.makerIDPrefix + "chrome", name: "Classic Chrome LUT")
        var photo = Self.raw
        photo.slotLooks = [.chrome: imported]
        let converted = try Self.convert("s = { CameraProfile = \"Camera CLASSIC CHROME\" }", photo: photo)
        #expect(converted.recipe.baseLook == imported)
        #expect(converted.report.note("CameraProfile") == PhotoNote.standIn(
            "Classic Chrome LUT",
            for: "Camera CLASSIC CHROME",
        ))
    }

    @Test(arguments: ["Vintage 03", "Artistic 01", "B&W 05", "Studio Portrait Pro", "Camera REALA ACE"])
    func `creative and third-party profiles take Color`(name: String) throws {
        let imported = try Self.convert("""
        s = { CameraProfile = "Adobe Standard", Look = { Name = "\(name)", Amount = 1.5 } }
        """)
        #expect(imported.recipe.baseLook == BuiltInBaseLook.color.reference.withAmount(150))
        #expect(imported.report.outcome("Look") == .approximated && imported.report.note("Look") == PhotoNote
            .noLike(name))
        #expect(imported.report.outcome("CameraProfile") == .approximated)
    }

    // MARK: - Lens and Transform

    @Test func `the lens profile is the file's own correction where it carries one`() throws {
        var photo = Self.raw
        photo.hasLensCorrection = true
        let imported = try Self.convert("""
        s = { LensProfileEnable = 1, LensProfileSetup = "LensDefaults", LensProfileName = "Example 35mm F1.8",
        	LensProfileFilename = "Example 35mm F1.8.lcp", LensProfileIsEmbedded = false,
        	LensProfileDistortionScale = 80, LensProfileVignettingScale = 120, LensProfileChromaticAberrationScale = 100 }
        """, photo: photo)
        #expect(imported.recipe[.lensProfile] == 1)
        #expect(imported.recipe[.lensProfileDistortion] == 80 && imported.recipe[.lensProfileVignetting] == 120)
        #expect(imported.report.note("LensProfileEnable") == PhotoNote.lensFile("Example 35mm F1.8"))
        #expect(imported.report.conversion == .full)
        #expect(imported.report.entries.map(\.setting) == [
            "LensProfileEnable", "LensProfileDistortionScale", "LensProfileVignettingScale",
        ])
    }

    @Test func `a lens profile the file doesn't carry is approximated, and a profile switched off maps`() throws {
        let profile = try Self.convert("""
        s = { LensProfileEnable = 1, LensProfileName = "Example 35mm F1.8", LensProfileFilename = "Example.lcp",
        	LensProfileChromaticAberrationScale = 50 }
        """)
        #expect(profile.recipe[.lensProfile] == 1)
        #expect(profile.report.outcome("LensProfileEnable") == .approximated)
        #expect(profile.report.note("LensProfileEnable") == PhotoNote.lensFolder(
            "Example 35mm F1.8",
            file: "Example.lcp",
        ))
        #expect(profile.report.entries(.ignored).map(\.setting) == ["LensProfileChromaticAberrationScale"])
        let off = try Self.convert("s = { LensProfileEnable = 0 }")
        #expect(off.recipe[.lensProfile] == 0 && off.report.conversion == .full)
    }

    @Test func `manual lens corrections, Transform and calibration map on Lightroom's scales, yet to check`() throws {
        let imported = try Self.convert("""
        s = { LensManualDistortionAmount = 12, VignetteAmount = -20, VignetteMidpoint = 40, AutoLateralCA = 1,
        	DefringePurpleAmount = 5, DefringePurpleHueLo = 25, DefringePurpleHueHi = 75, DefringeGreenAmount = 3,
        	DefringeGreenHueLo = 40, DefringeGreenHueHi = 60, ChromaticAberrationR = 0, Defringe = 0,
        	PerspectiveVertical = -15, PerspectiveHorizontal = 8, PerspectiveRotate = 1.5, PerspectiveScale = 95,
        	PerspectiveAspect = 10, PerspectiveX = 2.5, PerspectiveY = -3,
        	ShadowTint = 4, RedHue = -10, RedSaturation = 12, GreenHue = 5, GreenSaturation = -8, BlueHue = -12,
        	BlueSaturation = 15 }
        """)
        let expected: [ParameterID: Double] = [
            .lensDistortion: 12, .lensVignetting: -20, .lensVignettingMidpoint: 40,
            .lensRemoveChromaticAberration: 1, .defringePurpleAmount: 5, .defringePurpleHueLow: 25,
            .defringePurpleHueHigh: 75, .defringeGreenAmount: 3, .transformVertical: -15, .transformHorizontal: 8,
            .transformRotate: 1.5, .transformScale: 95, .transformAspect: 10, .transformOffsetX: 2.5,
            .transformOffsetY: -3, .calibrationShadowsTint: 4, .calibrationRedHue: -10,
            .calibrationRedSaturation: 12, .calibrationGreenHue: 5, .calibrationGreenSaturation: -8,
            .calibrationBlueHue: -12, .calibrationBlueSaturation: 15,
        ]
        for (parameter, value) in expected {
            #expect(imported.recipe[parameter] == value, "\(parameter.rawValue)")
        }
        #expect(imported.report.entries.allSatisfy { $0.outcome == .mapped })
        #expect(imported.report.note("PerspectiveVertical") == PhotoNote.uncheckedScale)
        #expect(imported.report.note("DefringeGreenHueLo") == nil, "at its default, its scale doesn't matter")
        #expect(imported.report.outcome("ChromaticAberrationR") == nil && imported.report.outcome("Defringe") == nil)
    }

    @Test func `Process 2010's manual chromatic aberration and Defringe menu are left out while they're set`() throws {
        let imported = try Self.convert("s = { ChromaticAberrationR = 10, ChromaticAberrationB = -5, Defringe = 1 }")
        #expect(imported.report.entries(.ignored).map(\.setting) == [
            "ChromaticAberrationR",
            "ChromaticAberrationB",
            "Defringe",
        ])
        #expect(imported.report.reasons == [.notInRedlamp(row: nil)])
        #expect(imported.report.note("ChromaticAberrationR") == PhotoNote.manualAberration)
    }

    @Test(arguments: [(1, "Auto"), (2, "Full"), (3, "Level"), (4, "Vertical"), (5, "Guided")])
    func `Upright is left out, not yet checked, with its guides and solved transforms`(mode: Int, name: String) throws {
        let imported = try Self.convert("""
        s = { PerspectiveUpright = \(mode), UprightVersion = 151388160, UprightFourSegmentsCount = 2,
        	UprightFourSegments_0 = "0.2 0.1 0.25 0.9", UprightFourSegments_1 = "0.8 0.1 0.75 0.9",
        	UprightTransformCount = 1, UprightTransform_0 = "1 0 0 0 1 0 0 0 1", PerspectiveVertical = 0 }
        """)
        let leftOut = imported.report.entries(.ignored)
        #expect(leftOut.map(\.setting) == [
            "UprightTransformCount", "UprightTransform_0", "UprightFourSegmentsCount", "UprightFourSegments_0",
            "UprightFourSegments_1", "PerspectiveUpright", "UprightVersion",
        ])
        #expect(leftOut.allSatisfy { $0.reason == .notYetChecked && $0.note == PhotoNote.upright(name) })
        #expect(imported.recipe.isDefault(.transformVertical))
        let off = try Self
            .convert("s = { PerspectiveUpright = 0, UprightVersion = 151388160, UprightTransformCount = 6 }")
        #expect(off.report.entries.isEmpty)
    }

    // MARK: - What's left out

    @Test func `panel switches, Point Color, Lens Blur, red-eye and HDR are left out with their reasons`() throws {
        let imported = try Self.convert("""
        s = { EnableCalibration = false, EnableDetail = true, PointColors = { "0.5, 0.2, 0.1" }, ColorVariance = { 0.3 },
        	LensBlur = { Active = true, BlurAmount = 50 }, RedEyeInfo = { "0.5 0.5 0.01" }, HDREditMode = 1,
        	SDRBrightness = 10, RetouchInfo = {} }
        """)
        let reasons = Dictionary(uniqueKeysWithValues: imported.report.entries(.ignored).compactMap { entry in
            entry.reason.map { (entry.setting, $0) }
        })
        #expect(reasons == [
            "EnableCalibration": .notYetChecked, "PointColors": .notYetChecked, "ColorVariance": .notYetChecked,
            "LensBlur": .notInRedlamp(row: "OTH-03"), "RedEyeInfo": .notInRedlamp(row: "OTH-01"),
            "HDREditMode": .notInRedlamp(row: "TON-42"), "SDRBrightness": .notInRedlamp(row: "TON-42"),
        ])
        #expect(imported.report.note("LensBlur") == PhotoNote.lensBlur && imported.report
            .note("HDREditMode") == PhotoNote.hdr)
        #expect(imported.report.conversion == .leftOut && imported.recipe.pointColor.isEmpty)
        let off = try Self.convert("""
        s = { EnableCalibration = true, PointColors = {}, LensBlur = { Active = false }, RedEyeInfo = {},
        	HDREditMode = 0, SDRBrightness = 10, MoireFilter = "Off" }
        """)
        #expect(off.report.entries.isEmpty, "what does nothing isn't reported")
    }

    @Test func `masks and spots are counted and left out until checked against Lightroom`() throws {
        let imported = try Self.convert(DevelopSettings.lua(DevelopSettings.photo()))
        #expect(imported.recipe.masks.isEmpty && imported.recipe.spots.isEmpty)
        let masks = try #require(imported.report.entries.first { $0.setting == "MaskGroupBasedCorrections" })
        #expect(masks.outcome == .ignored && masks.reason == .notYetChecked)
        #expect(masks.note == PhotoNote.masks(4, components: 10))
        #expect(imported.report.note("GradientBasedCorrections") == PhotoNote.masks(1, components: 1))
        #expect(imported.report.note("RetouchAreas") == PhotoNote.spots(2))
        #expect(imported.report.reasons.contains(.notYetChecked))
        let process2010 = try Self.convert("""
        s = { ProcessVersion = "5.7", RetouchInfo = { "centerX = 0.4, centerY = 0.5, radius = 0.02, spotType = heal" } }
        """)
        #expect(process2010.report.note("RetouchInfo") == PhotoNote.spots(1))
    }

    @Test func `settings Redlamp doesn't know are reported while they do something`() throws {
        let imported = try Self.convert("s = { FutureSetting = 3, OtherFutureSetting = 0, Blank = \"\" }")
        #expect(imported.report.entries.map(\.setting) == ["FutureSetting"])
        #expect(imported.report.entries.first?.reason == .unknown)
        #expect(imported.report.note("FutureSetting") == Note.unknown)
    }

    @Test func `Lightroom's Auto keeps the values it found`() throws {
        let imported = try Self.convert("s = { AutoTone = true, Exposure2012 = 0.85 }")
        #expect(imported.recipe[.exposure] == 0.85)
        #expect(imported.report.outcome("AutoTone") == .approximated && imported.report.note("AutoTone") == PhotoNote
            .auto)
    }

    // MARK: - Process 2003 and 2010

    @Test func `a Process 2010 photo carries what doesn't depend on the process and waits on EDT-31 for its tone`()
        throws {
        let imported = try Self.convert("""
        s = { ProcessVersion = "5.7", WhiteBalance = "Custom", Temperature = 5200, Tint = 3,
        	Exposure = 0.5, HighlightRecovery = 20, FillLight = 10, Shadows = 5, Brightness = 50, Contrast = 25,
        	Clarity = 15, ToneCurveName = "Medium Contrast", ToneCurve = { 0, 0, 32, 22, 64, 56, 128, 128, 192, 196, 255, 255 },
        	ParametricDarks = 10, ParametricShadowSplit = 25,
        	Exposure2012 = 0, Contrast2012 = 0, Dehaze = 0, ToneCurvePV2012 = { 0, 0, 255, 255 },
        	Vibrance = 10, HueAdjustmentRed = 5, SplitToningShadowHue = 200, SplitToningShadowSaturation = 30,
        	Sharpness = 25, LuminanceSmoothing = 10, PostCropVignetteAmount = -10, GrainAmount = 5,
        	LensManualDistortionAmount = 4, PerspectiveVertical = -5, AutoExposure = false }
        """)
        let recipe = imported.recipe
        #expect(recipe.processVersion == EditRecipe.currentProcessVersion)
        #expect(recipe[.exposure] == 0 && recipe[.contrast] == 0 && recipe[.clarity] == 0 && !recipe.hasPointCurve)
        #expect(recipe.isDefault(.curveDarks))
        #expect(recipe.whiteBalanceMode == .custom && recipe[.temperature] == 5200)
        #expect(recipe[.vibrance] == 10 && recipe[.hueRed] == 5 && recipe[.gradeShadowsHue] == 200)
        #expect(recipe[.gradeBlending] == 100, "Split Toning renders with Blending at 100")
        #expect(recipe[.sharpenAmount] == 25 && recipe[.noiseLuminance] == 10)
        #expect(recipe[.vignetteAmount] == -10 && recipe[.grainAmount] == 5)
        #expect(recipe[.lensDistortion] == 4 && recipe[.transformVertical] == -5)
        let waiting = imported.report.entries.filter { $0.reason == .earlierProcess }.map(\.setting)
        #expect(waiting == [
            "Exposure", "HighlightRecovery", "FillLight", "Shadows", "Brightness", "Contrast", "Clarity",
            "ParametricDarks", "ToneCurve", "ToneCurveName",
        ])
        #expect(imported.report.note("Brightness") == PhotoNote.earlierProcess("Brightness", .process2010))
        #expect(imported.report.note("ParametricDarks") == PhotoNote.earlierProcess("tone curve", .process2010))
        for setting in ["Exposure2012", "Contrast2012", "Dehaze", "ToneCurvePV2012", "AutoExposure"] {
            #expect(imported.report.outcome(setting) == nil, "\(setting) isn't used by Process 2010")
        }
        #expect(imported.report.reasons == [.earlierProcess] && imported.report.processVersion == "5.7")
    }

    @Test func `a Process 2003 photo's noise reduction waits on EDT-31 too`() throws {
        let imported = try Self.convert("""
        s = { ProcessVersion = "5.0", LuminanceSmoothing = 30, ColorNoiseReduction = 25, Sharpness = 25, Brightness = 60 }
        """)
        #expect(imported.recipe.isDefault(.noiseLuminance) && imported.recipe[.sharpenAmount] == 25)
        #expect(imported.report.note("LuminanceSmoothing") == PhotoNote.earlierProcess("noise reduction", .process2003))
        #expect(imported.report.outcome("ColorNoiseReduction") == nil, "at its default it isn't reported")
        #expect(imported.report.note("Brightness") == PhotoNote.earlierProcess("Brightness", .process2003))
    }

    // MARK: - Reading alike, and the report

    @Test(arguments: DevelopSettings.Form.allCases)
    func `a sidecar's settings convert as the catalog's do`(form: DevelopSettings.Form) throws {
        let fields = DevelopSettings.photo()
        let lua = try Self.convert(DevelopSettings.lua(fields))
        let settings = try #require(CameraRawSettings(xmp: DevelopSettings.xmp(fields, form: form)))
        let xmp = LightroomPhoto.convert(
            settings, photo: Self.raw, source: .sidecar(URL(filePath: "/Photos/IMG_0001.xmp")),
            date: Date(timeIntervalSince1970: 0),
        )
        var recipe = xmp.recipe
        #expect(recipe.provenance?.source == .xmpSidecar && recipe.provenance?.path == "/Photos/IMG_0001.xmp")
        recipe.provenance = lua.recipe.provenance
        #expect(recipe == lua.recipe)
        #expect(xmp.report == lua.report)
        #expect(LightroomPhoto.holdsEdit(settings))
    }

    @Test func `the report says how fully a photo converts, and why settings are left out`() throws {
        let full = try Self.convert("s = { Exposure2012 = 0.5, WhiteBalance = \"As Shot\" }")
        #expect(full.report.conversion == .full && full.report.reasons.isEmpty)
        let approximated = try Self.convert("s = { Exposure2012 = 0.5, CameraProfile = \"Camera Vivid\" }")
        #expect(approximated.report.conversion == .approximated)
        var photo = Self.raw
        photo.orientationCode = "BC"
        let leftOut = try Self.convert("s = { Exposure2012 = 9, LensBlur = { Active = true } }", photo: photo)
        #expect(leftOut.report.conversion == .leftOut)
        #expect(leftOut.report.reasons == [.notInRedlamp(row: "OTH-03"), .notYetChecked])
        #expect(leftOut.report.outcome("Exposure2012") == .approximated, "clamped to Redlamp's ±5")
        #expect(leftOut.provenance == LightroomProvenance(
            source: .catalog(Self.catalog, photo: 42, digest: "D1"), date: Date(timeIntervalSince1970: 0),
            approximated: ["Exposure2012"], leftOut: ["LensBlur", "orientation"],
        ))
        #expect(leftOut.recipe.provenance == EditProvenance(
            source: .lightroomCatalog, path: Self.catalog.path, photo: 42, digest: "D1",
            date: Date(timeIntervalSince1970: 0), approximated: ["Exposure2012"], leftOut: ["LensBlur", "orientation"],
        ))
        #expect(!leftOut.recipe.isPristine)
    }

    @Test func `presets, and XMP without develop settings, don't hold a photo's edit`() throws {
        let preset = try #require(CameraRawSettings(xmp: PresetXMP.preset([("Exposure2012", "+0.50")])))
        let unset = try #require(CameraRawSettings(xmp: LightroomPresetRefusalTests.sidecar(form: .attributes)))
        #expect(!LightroomPhoto.holdsEdit(preset))
        #expect(LightroomPhoto.holdsEdit(unset))
        #expect(try !LightroomPhoto
            .holdsEdit(CameraRawSettings(lua: "s = { HasSettings = false, Exposure2012 = 0.5 }")))
        #expect(try !LightroomPhoto
            .holdsEdit(CameraRawSettings(lua: "s = { ProcessVersion = \"15.4\", RawFileName = \"A.CR3\" }")))
    }
}
