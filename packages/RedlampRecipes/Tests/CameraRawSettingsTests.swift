import Foundation
import Testing
@testable import RedlampRecipes

/// Camera Raw settings read alike from a Lightroom Classic catalog's Lua and from XMP (EDT-23, EDT-12): the
/// same settings, written both ways from ExifTool's table of `crs` tags, read with the same accessors at every
/// depth.
struct CameraRawSettingsTests {
    /// Each setting of `fields` as the accessors read it from `settings`, and nothing more.
    private static func expect(_ settings: CameraRawSettings, holds fields: DevelopFields, at path: String = "") {
        for (name, setting) in fields {
            let place = path + name
            switch setting {
            case let .number(number), let .slider(number): #expect(settings.number(name) == number, "\(place)")
            case let .text(text): #expect(settings.text(name) == text, "\(place)")
            case let .flag(flag): #expect(settings.flag(name) == flag, "\(place)")
            case let .curve(numbers): #expect(settings.list(name) == DevelopSettings.points(numbers), "\(place)")
            case let .list(items): #expect(settings.list(name) == items, "\(place)")
            case let .structure(fields):
                guard let structure = settings.structure(name) else {
                    Issue.record("\(place) isn't a structure: \(String(describing: settings[name]))")
                    continue
                }
                expect(structure, holds: fields, at: place + ".")
            case let .structures(items):
                let structures = settings.structures(name) ?? []
                #expect(structures.count == items.count, "\(place)")
                for (index, (structure, fields)) in zip(structures, items).enumerated() {
                    expect(structure, holds: fields, at: "\(place)[\(index)].")
                }
            }
        }
        #expect(settings.values.count == fields.count, "\(path.isEmpty ? "the settings" : path) hold nothing more")
    }

    @Test(arguments: DevelopSettings.Form.allCases)
    func `a photo's settings read alike from the catalog's Lua and from XMP in every RDF form`(
        form: DevelopSettings.Form,
    ) throws {
        let fields = DevelopSettings.photo()
        let lua = try CameraRawSettings(lua: DevelopSettings.lua(fields))
        let xmp = try #require(CameraRawSettings(xmp: DevelopSettings.xmp(fields, form: form)))
        for settings in [lua, xmp] {
            Self.expect(settings, holds: fields)
            #expect(settings.text("WhiteBalance") == "Custom" && settings.number("Temperature") == 4500)
            #expect(settings.flag("HasCrop") == true && settings.flag("LensProfileEnable") == true)
            #expect(settings.list("ToneCurvePV2012Blue") == ["0, 0", "128.5, 120", "255, 255"])
            let look = try #require(settings.structure("Look"))
            #expect(look.text("Name") == "Adobe Color" && look.number("Amount") == 1)
            #expect(look.structure("Parameters")?.list("ToneCurvePV2012")?.prefix(2) == ["0, 0", "22, 16"])
            let corrections = try #require(settings.structures("MaskGroupBasedCorrections"))
            #expect(corrections.map { $0.text("CorrectionName") } == ["Sky", "Subject", "Shadows", "Faces"])
            let brush = try #require(corrections[1].structures("CorrectionMasks")?.last)
            #expect(brush.text("What") == "Mask/Paint" && brush.number("MaskBlendMode") == 1)
            #expect(brush.list("Dabs")?.count == 24 && brush.number("Radius") == 0.04)
            let color = corrections[2].structures("CorrectionMasks")?[1].structure("CorrectionRangeMask")
            #expect(color?.structures("AreaModels")?.first?.list("AreaComponents")?.count == 1)
            #expect(corrections[3].structures("CorrectionMasks")?.first?.structures("Masks")?.count == 2)
            let legacy = try #require(settings.structures("GradientBasedCorrections")?.first)
            #expect(legacy.structures("CorrectionMasks")?.first?.number("FullY") == 0.31)
            let spots = try #require(settings.structures("RetouchAreas"))
            #expect(spots.map { $0.text("SpotType") } == ["heal", "clone"])
            #expect(spots[0].structures("Masks")?.first?.number("SizeX") == 0.02)
            #expect(settings.numbered("UprightFourSegments") == [
                "0.210000 0.080000 0.240000 0.910000",
                "0.780000 0.100000 0.750000 0.880000",
            ])
            #expect(settings.numbered("UprightTransform").count == 6)
            #expect(settings.list("PointColors") == [] && settings.structures("RedEyeInfo") == [])
        }
    }

    @Test func `a sidecar reads the same in every RDF form`() throws {
        let fields = DevelopSettings.photo(7)
        let forms = try DevelopSettings.Form.allCases.map {
            try #require(CameraRawSettings(xmp: DevelopSettings.xmp(fields, form: $0)))
        }
        #expect(forms.allSatisfy { $0 == forms[0] })
        #expect(forms[0].describesPhoto && !forms[0].isPreset)
    }

    @Test(arguments: [0, 1, 2, 3, 5, 10])
    func `photos with and without masks and spots read alike`(seed: Int) throws {
        let fields = DevelopSettings.photo(seed, masks: seed % 5, spots: seed % 3 == 0, upright: seed % 2 == 0)
        Self.expect(try CameraRawSettings(lua: DevelopSettings.lua(fields)), holds: fields)
        Self.expect(try #require(CameraRawSettings(xmp: DevelopSettings.xmp(fields, form: .compact))), holds: fields)
    }

    // MARK: - Lua

    @Test func `a catalog's numbers and booleans read as XMP's text does`() throws {
        let settings = try CameraRawSettings(lua: """
        s = { Exposure2012 = 0.35,
        	Contrast2012 = -12,
        	Temperature = 5500,
        	UprightVersion = 151388160,
        	CropAngle = -1.25e0,
        	HasCrop = true,
        	AutoTone = false,
        	WhiteBalance = "As Shot",
        	LensProfileName = 'Example 35mm "Prime"',
        	NegativeCacheMaximumSize = 1e20,
        	GrainSeed = 0x10,
        	Unset = nil }
        """)
        #expect(settings.text("Exposure2012") == "0.35" && settings.number("Exposure2012") == 0.35)
        #expect(settings.text("Contrast2012") == "-12" && settings.text("Temperature") == "5500")
        #expect(settings.text("UprightVersion") == "151388160" && settings.number("CropAngle") == -1.25)
        #expect(settings.text("HasCrop") == "True" && settings.flag("HasCrop") == true)
        #expect(settings.text("AutoTone") == "False" && settings.flag("AutoTone") == false)
        #expect(settings.text("WhiteBalance") == "As Shot")
        #expect(settings.text("LensProfileName") == "Example 35mm \"Prime\"")
        #expect(settings.number("NegativeCacheMaximumSize") == 1e20 && settings.text("GrainSeed") == "16")
        #expect(settings["Unset"] == nil && settings.values.count == 11)
    }

    @Test func `a point curve's flat list of numbers reads as XMP's points, by its name`() throws {
        let settings = try CameraRawSettings(lua: """
        s = { ToneCurvePV2012 = { 0, 0, 128.5, 120, 255, 255 },
        	ToneCurve = { 0, 0, 64, 60, 255, 255, },
        	ToneCurveRed = { 0, 0, 255 },
        	ToneCurveGreen = { "0, 0", "255, 255" },
        	Look = { Name = "Adobe Color", Parameters = { ToneCurvePV2012Blue = { 0, 10, 255, 245 } } },
        	MaskGroupBasedCorrections = { { ToneCurvePV2012 = { 0, 0, 255, 255 }, What = "Correction" } },
        	RedEyeInfo = { 1, 2, 3, 4 } }
        """)
        #expect(settings.list("ToneCurvePV2012") == ["0, 0", "128.5, 120", "255, 255"])
        #expect(settings.list("ToneCurve") == ["0, 0", "64, 60", "255, 255"])
        #expect(settings.list("ToneCurveRed") == ["0", "0", "255"], "an odd count isn't a curve's points")
        #expect(settings.list("ToneCurveGreen") == ["0, 0", "255, 255"])
        #expect(settings.structure("Look")?.structure("Parameters")?.list("ToneCurvePV2012Blue") == [
            "0, 10",
            "255, 245",
        ])
        #expect(settings.structures("MaskGroupBasedCorrections")?.first?.list("ToneCurvePV2012") == [
            "0, 0",
            "255, 255",
        ])
        #expect(settings.list("RedEyeInfo") == ["1", "2", "3", "4"], "a list that isn't a curve stays as it is")
    }

    @Test func `tables with keys are structures, tables of tables arrays of them, and an empty table any`() throws {
        let settings = try CameraRawSettings(lua: """
        s = { Look = { Name = "Adobe Color", Parameters = { ProcessVersion = "11.0" } },
        	RetouchAreas = { { SpotType = "heal", Masks = { { What = "Mask/Ellipse", X = 0.5 } } }, { SpotType = "clone" } },
        	PointColors = {},
        	Mixed = { 1, { What = "Mask/Gradient" } },
        	Both = { "item", Field = 2 },
        	"an item of the settings themselves" }
        """)
        #expect(settings.structure("Look")?.structure("Parameters")?.text("ProcessVersion") == "11.0")
        #expect(settings.text("ProcessVersion") == nil)
        let spots = try #require(settings.structures("RetouchAreas"))
        #expect(spots.map { $0.text("SpotType") } == ["heal", "clone"])
        #expect(spots[0].structures("Masks")?.first?.number("X") == 0.5)
        #expect(settings.list("PointColors") == [] && settings.structures("PointColors") == [])
        #expect(settings.structure("PointColors") == CameraRawSettings())
        #expect(settings.structures("Mixed") == [
            CameraRawSettings(),
            CameraRawSettings(["What": .text("Mask/Gradient")]),
        ])
        #expect(settings.structure("Both") == CameraRawSettings(["Field": .text("2")]))
        #expect(settings.values.count == 5)
    }

    @Test func `develop settings that aren't a table of data are refused`() {
        for text in ["s = { Exposure2012 = os.exit() }", "s = { Exposure2012 = 0.35", "Exposure2012 = 0.35", ""] {
            #expect(throws: LuaTableError.self, "\(text)") { try CameraRawSettings(lua: text) }
        }
    }

    // MARK: - XMP and the accessors

    @Test func `an XMP packet larger than a recipe file may be isn't read`() {
        let packet = String(decoding: PresetXMP.preset([("Exposure2012", "+0.50")]), as: UTF8.self)
        let padding = String(repeating: " ", count: RecipeValidator.maximumFileSize)
        let padded = packet.replacingOccurrences(of: "</x:xmpmeta>", with: padding + "</x:xmpmeta>")
        #expect(CameraRawSettings(xmp: Data(packet.utf8)) != nil)
        #expect(CameraRawSettings(xmp: Data(padded.utf8)) == nil)
    }

    @Test func `numbered settings read up to their count and to the first that's missing`() {
        let settings = CameraRawSettings([
            "UprightTransformCount": .text("2"), "UprightTransform_0": .text("a"), "UprightTransform_1": .text("b"),
            "UprightTransform_2": .text("c"), "Guide_0": .text("x"), "Guide_1": .text("y"), "Guide_3": .text("z"),
            "HugeCount": .text("1e300"), "Huge_0": .text("h"), "NoneCount": .text("-4"), "None_0": .text("n"),
        ])
        #expect(settings.numbered("UprightTransform") == ["a", "b"])
        #expect(settings.numbered("Guide") == ["x", "y"])
        #expect(settings.numbered("Huge") == ["h"])
        #expect(settings.numbered("None") == [] && settings.numbered("Missing") == [])
    }

    @Test func `each accessor reads only its own kind of value`() {
        let settings = CameraRawSettings([
            "Text": .text("1"), "List": .list(["1"]), "Structure": .structure(CameraRawSettings(["Name": .text("x")])),
            "Structures": .structures([CameraRawSettings()]),
        ])
        #expect(settings.number("Text") == 1 && settings.number("List") == nil && settings.text("Structure") == nil)
        #expect(settings.list("Text") == nil && settings.list("Structures") == nil)
        #expect(settings.structure("Structures") == nil && settings.structure("Structure")?.text("Name") == "x")
        #expect(settings.structures("Structure") == nil && settings.structures("Structures")?.count == 1)
        #expect(settings.flag("List") == nil && !settings.isBlank("Structure"))
    }
}
