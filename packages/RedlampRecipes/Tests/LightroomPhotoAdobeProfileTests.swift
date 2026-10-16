import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// A converted photo's profile rendered by the photographer's own copy of Adobe's profile where it's on this
/// Mac, and by Redlamp's look of the same name where it isn't, the report saying which (EDT-33). The Mac's
/// profiles are synthetic, named as `EditingEngine.cameraProfileLooks(make:model:)` names them: Adobe's files
/// are never committed (DEC-85).
struct LightroomPhotoAdobeProfileTests {
    private typealias PhotoNote = LightroomPhoto.Note

    static let canonStandard = "0123456789abcdef"

    /// A camera profile, as `local/adobe/<profile>`.
    static func profile(_ name: String, _ group: CameraProfileLook.Group, _ hash: String) -> CameraProfileLook {
        CameraProfileLook(
            reference: BaseLookReference(id: BaseLookReference.adobeIDPrefix + hash, name: name),
            group: group, summary: "\(name), for the test",
        )
    }

    /// An XMP look over a camera profile, as `local/adobe/<profile>/<look>`.
    static func look(
        _ name: String, _ group: CameraProfileLook.Group, _ hash: String, over base: String = canonStandard,
        monochrome: Bool = false, leftOut: [String] = [],
    ) -> CameraProfileLook {
        CameraProfileLook(
            reference: BaseLookReference(id: BaseLookReference.adobeIDPrefix + base + "/" + hash, name: name),
            group: group, summary: "\(name), for the test", isMonochrome: monochrome, leftOut: leftOut,
        )
    }

    static let canonProfiles = [
        look("Adobe Color", .adobeRaw, "1111111111111111"),
        look("Adobe Monochrome", .adobeRaw, "2222222222222222", monochrome: true),
        look("Adobe Vivid", .adobeRaw, "3333333333333333"),
        profile("Adobe Standard", .adobeRaw, canonStandard),
        profile("Camera Neutral", .cameraMatching, "4444444444444444"),
        look("B&W 05", .creative("B&W"), "5555555555555555", monochrome: true, leftOut: ["Clarity +8"]),
        look("Vintage 07", .creative("Vintage"), "6666666666666666"),
        profile("Studio Portrait Pro", .own(nil), "7777777777777777"),
        look("Portra 400", .own("Film"), "8888888888888888"),
    ]

    static let fujifilmProfiles = [
        profile("Adobe Standard", .adobeRaw, "fedcba9876543210"),
        profile("Camera CLASSIC CHROME", .cameraMatching, "9999999999999999"),
    ]

    static let size = PixelSize(width: 6000, height: 4000)
    /// Raws from cameras whose profiles are on this Mac, and from one whose aren't.
    static let canon = LightroomPhotoContext(size: size, adobeProfiles: canonProfiles)
    static let fujifilm = LightroomPhotoContext(size: size, adobeProfiles: fujifilmProfiles)
    static let elsewhere = LightroomPhotoContext(size: size, adobeProfiles: [])

    static func convert(_ lua: String, photo: LightroomPhotoContext) throws -> LightroomPhotoImport {
        try LightroomPhoto.convert(
            CameraRawSettings(lua: lua), photo: photo,
            source: .catalog(URL(filePath: "/Photos/Lightroom Catalog.lrcat"), photo: 7, digest: nil),
            date: Date(timeIntervalSince1970: 0),
        )
    }

    /// Settings applying the look `name` at `amount` over `profile`, the look naming `base` as its own.
    static func looked(
        _ name: String, amount: Double = 1, over profile: String = "Adobe Standard", base: String? = "Adobe Standard",
    ) -> String {
        let parameters = base.map { ", Parameters = { CameraProfile = \"\($0)\", ConvertToGrayscale = false }" } ?? ""
        return "s = { CameraProfile = \"\(profile)\", Look = { Name = \"\(name)\", Amount = \(amount)\(parameters) } }"
    }

    static func copy(_ name: String, in profiles: [CameraProfileLook] = canonProfiles) throws -> BaseLookReference {
        try #require(profiles.first { $0.reference.name == name }).reference
    }

    // MARK: - Adobe's raw looks

    @Test(arguments: ["Adobe Color", "Adobe Monochrome", "Adobe Vivid"])
    func `an Adobe raw look on this Mac renders the photo, at its amount`(name: String) throws {
        let imported = try Self.convert(Self.looked(name, amount: 0.5), photo: Self.canon)
        #expect(try imported.recipe.baseLook == Self.copy(name).withAmount(50))
        #expect(imported.recipe.baseLook.isAdobeProfile && imported.recipe.baseLook.staysOnThisMac)
        #expect(imported.report.outcome("Look") == .mapped)
        #expect(imported.report.note("Look") == PhotoNote.onThisMac(name, leavingOut: []))
        #expect(imported.report.outcome("CameraProfile") == .mapped)
        #expect(imported.report.note("CameraProfile") == PhotoNote.underLookOnThisMac(name))
        #expect(imported.report.profile == .onThisMac(name) && imported.report.conversion == .full)
    }

    @Test(arguments: AdobeProfileStandIn.adobeRawLooks.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
    func `where an Adobe raw look isn't on this Mac, Redlamp's look of its name stands in, as when an edit renders`(
        name: String,
        look: BuiltInBaseLook,
    ) throws {
        let imported = try Self.convert(Self.looked(name, amount: 0.5), photo: Self.elsewhere)
        #expect(imported.recipe.baseLook == look.reference.withAmount(50))
        #expect(AdobeProfileStandIn.look(forProfileNamed: name) == look)
        #expect(imported.report.outcome("Look") == .mapped)
        #expect(imported.report.note("Look") == PhotoNote.notOnThisMac(name, standIn: look.name))
        #expect(imported.report.note("CameraProfile") == PhotoNote.underLook(name))
        #expect(imported.report.profile == .standIn(profile: name, look: look.name))
    }

    // MARK: - Adobe Standard and Camera Matching

    @Test(arguments: ["Adobe Standard", "Camera Neutral"])
    func `the camera's own profiles on this Mac render the photo, before a copy the file embeds`(name: String) throws {
        let imported = try Self.convert("s = { CameraProfile = \"\(name)\" }", photo: Self.canon)
        #expect(try imported.recipe.baseLook == Self.copy(name))
        #expect(imported.report.outcome("CameraProfile") == .mapped)
        #expect(imported.report.note("CameraProfile") == PhotoNote.onThisMac(name, leavingOut: []))
        #expect(imported.report.profile == .onThisMac(name))
        var dng = Self.canon
        dng.embeddedLook = BaseLookReference(id: BaseLookReference.embeddedIDPrefix + "00ff", name: "Adobe Standard")
        #expect(try Self.convert("s = { CameraProfile = \"\(name)\" }", photo: dng).recipe.baseLook == Self.copy(name))
        let own = try Self.convert("s = { CameraProfile = \"Embedded\" }", photo: dng)
        #expect(own.recipe.baseLook == dng.embeddedLook && own.report.note("CameraProfile") == nil)
        #expect(own.report.profile == nil)
    }

    @Test func `without the camera's profiles, the look the file embeds or the nearest by name stands in`() throws {
        let neutral = try Self.convert("s = { CameraProfile = \"Camera Neutral\" }", photo: Self.elsewhere)
        #expect(neutral.recipe.baseLook == BuiltInBaseLook.neutral.reference)
        #expect(neutral.report.outcome("CameraProfile") == .approximated)
        #expect(neutral.report.note("CameraProfile") == PhotoNote.notOnThisMac(
            "Camera Neutral",
            standIn: "Redlamp Neutral",
        ))
        #expect(neutral.report.profile == .standIn(profile: "Camera Neutral", look: "Redlamp Neutral"))
        let standard = try Self.convert("s = { CameraProfile = \"Adobe Standard\" }", photo: Self.elsewhere)
        #expect(standard.recipe.baseLook == BuiltInBaseLook.color.reference)
        #expect(standard.report.note("CameraProfile") == PhotoNote.notOnThisMac(
            "Adobe Standard",
            standIn: "Redlamp Color",
        ))

        var dng = Self.elsewhere
        let embedded = BaseLookReference(id: BaseLookReference.embeddedIDPrefix + "00ff", name: "Adobe Standard")
        dng.embeddedLook = embedded
        let same = try Self.convert("s = { CameraProfile = \"Adobe Standard\" }", photo: dng)
        #expect(same.recipe.baseLook == embedded && same.report.outcome("CameraProfile") == .mapped)
        #expect(same.report.note("CameraProfile") == PhotoNote.notOnThisMac(
            "Adobe Standard",
            standIn: PhotoNote.embeddedCopy,
        ))
        #expect(same.report.profile == .standIn(profile: "Adobe Standard", look: "Adobe Standard"))
        let other = try Self.convert("s = { CameraProfile = \"Camera Neutral\" }", photo: dng)
        #expect(other.recipe.baseLook == embedded && other.report.outcome("CameraProfile") == .approximated)
        #expect(other.report.note("CameraProfile") == PhotoNote.notOnThisMac(
            "Camera Neutral",
            standIn: PhotoNote.embeddedProfile("Adobe Standard"),
        ))
    }

    // MARK: - Fujifilm's film simulations

    @Test func `a Fujifilm simulation on this Mac renders the photo, and without it Redlamp's film look stands in`()
        throws {
        let settings = "s = { CameraProfile = \"Camera CLASSIC CHROME\" }"
        let own = try Self.convert(settings, photo: Self.fujifilm)
        #expect(try own.recipe.baseLook == Self.copy("Camera CLASSIC CHROME", in: Self.fujifilmProfiles))
        #expect(own.report.outcome("CameraProfile") == .mapped)
        #expect(own.report.profile == .onThisMac("Camera CLASSIC CHROME"))

        let film = FilmSlot.chrome.baseLook
        let elsewhere = try Self.convert(settings, photo: Self.elsewhere)
        #expect(elsewhere.recipe.baseLook == film && elsewhere.report.outcome("CameraProfile") == .approximated)
        #expect(elsewhere.report.note("CameraProfile") == PhotoNote.notOnThisMac(
            "Camera CLASSIC CHROME",
            standIn: film.name,
        ))
        var withLUT = Self.elsewhere
        let lut = BaseLookReference(id: BaseLookReference.makerIDPrefix + "chrome", name: "Classic Chrome LUT")
        withLUT.slotLooks = [.chrome: lut]
        let imported = try Self.convert(settings, photo: withLUT)
        #expect(imported.recipe.baseLook == lut)
        #expect(imported.report.profile == .standIn(profile: "Camera CLASSIC CHROME", look: "Classic Chrome LUT"))
        // Another simulation of the same camera that isn't on this Mac.
        let provia = try Self.convert("s = { CameraProfile = \"Camera PROVIA/Standard\" }", photo: Self.fujifilm)
        #expect(provia.recipe.baseLook == FilmSlot.standard.baseLook)
        #expect(provia.report.profile == .standIn(
            profile: "Camera PROVIA/Standard",
            look: FilmSlot.standard.baseLook.name,
        ))
    }

    // MARK: - Creative and third-party profiles

    @Test func `a creative look on this Mac renders the photo over the profile it names`() throws {
        let vintage = try Self.convert(Self.looked("Vintage 07", amount: 1.4, base: nil), photo: Self.canon)
        #expect(try vintage.recipe.baseLook == Self.copy("Vintage 07").withAmount(140))
        #expect(vintage.report.outcome("Look") == .mapped && vintage.report.outcome("CameraProfile") == .mapped)
        #expect(vintage.report.profile == .onThisMac("Vintage 07"))
        let over = try Self.convert(Self.looked("Vintage 07", over: "Camera Neutral", base: nil), photo: Self.canon)
        #expect(over.report.outcome("CameraProfile") == .approximated)
        #expect(over.report.note("CameraProfile") == PhotoNote.overOtherProfile("Vintage 07", base: "Adobe Standard"))

        let elsewhere = try Self.convert(Self.looked("Vintage 07", amount: 1.4, base: nil), photo: Self.elsewhere)
        #expect(elsewhere.recipe.baseLook == BuiltInBaseLook.color.reference.withAmount(140))
        #expect(elsewhere.report.outcome("Look") == .approximated)
        #expect(elsewhere.report.note("Look") == PhotoNote.notOnThisMac("Vintage 07", standIn: nil))
        #expect(elsewhere.report.profile == .standIn(profile: "Vintage 07", look: "Redlamp Color"))
    }

    @Test func `a look's own develop settings, which Redlamp leaves out, make it approximated`() throws {
        let imported = try Self.convert(Self.looked("B&W 05", base: nil), photo: Self.canon)
        #expect(try imported.recipe.baseLook == Self.copy("B&W 05"))
        #expect(imported.report.outcome("Look") == .approximated)
        #expect(imported.report.note("Look") == PhotoNote.onThisMac("B&W 05", leavingOut: ["Clarity +8"]))
        #expect(imported.report.profile == .onThisMac("B&W 05"))
    }

    @Test(arguments: [("Portra 400", true), ("Studio Portrait Pro", false)])
    func `a third-party profile renders in the photographer's own copy, and Color stands in without it`(
        name: String,
        isLook: Bool,
    ) throws {
        let settings = isLook ? Self.looked(name, base: nil) : "s = { CameraProfile = \"\(name)\" }"
        let key = isLook ? "Look" : "CameraProfile"
        let own = try Self.convert(settings, photo: Self.canon)
        #expect(try own.recipe.baseLook == Self.copy(name))
        #expect(own.report.outcome(key) == .mapped && own.report.profile == .onThisMac(name))
        let elsewhere = try Self.convert(settings, photo: Self.elsewhere)
        #expect(elsewhere.recipe.baseLook == BuiltInBaseLook.color.reference)
        #expect(elsewhere.report.note(key) == PhotoNote.notOnThisMac(name, standIn: nil))
    }

    // MARK: - Which copy, and when

    @Test func `the copy taken is of the kind Lightroom applies, and Adobe's before the photographer's own`() {
        let profiles = [
            Self.profile("Adobe Standard", .own(nil), "0000000000000001"),
            Self.look("Adobe Standard", .adobeRaw, "0000000000000002"),
            Self.profile("Adobe Standard", .adobeRaw, Self.canonStandard),
            Self.look("Adobe Color", .own("Mine"), "0000000000000003"),
            Self.look("Adobe Color", .adobeRaw, "0000000000000004"),
            CameraProfileLook(reference: BuiltInBaseLook.vivid.reference, group: .adobeRaw, summary: "Not Adobe's"),
        ]
        func id(_ name: String, isLook: Bool) -> String? {
            LightroomPhoto.adobeProfile(named: name, isLook: isLook, in: profiles)?.reference.id
        }
        let prefix = BaseLookReference.adobeIDPrefix
        #expect(id("Adobe Standard", isLook: false) == prefix + Self.canonStandard)
        #expect(id("Adobe Standard", isLook: true) == prefix + Self.canonStandard + "/0000000000000002")
        #expect(id("Adobe Color", isLook: true) == prefix + Self.canonStandard + "/0000000000000004")
        #expect(id("Adobe Color", isLook: false) == prefix + Self.canonStandard + "/0000000000000004")
        #expect(id("Redlamp Vivid", isLook: true) == nil && id("Adobe Vivid", isLook: true) == nil)
    }

    @Test func `without the Mac's profiles, and for a rendered photo, the profile converts as it did`() throws {
        let settings = [
            Self.looked("Adobe Color", amount: 0.5), "s = { CameraProfile = \"Camera Neutral\" }",
            Self.looked("Vintage 07", base: nil), "s = { CameraProfile = \"Camera CLASSIC CHROME\" }",
        ]
        var rendered = Self.canon
        rendered.isRaw = false
        for lua in settings {
            let unknown = try Self.convert(lua, photo: LightroomPhotoContext(size: Self.size))
            #expect(unknown.report.profile == nil, "\(lua)")
            #expect(!unknown.report.entries.contains { $0.note?.contains("this Mac") == true }, "\(lua)")
            #expect(!unknown.recipe.baseLook.isAdobeProfile, "\(lua)")
            let jpeg = try Self.convert(lua, photo: rendered)
            var unlisted = rendered
            unlisted.adobeProfiles = nil
            let before = try Self.convert(lua, photo: unlisted)
            #expect(jpeg.recipe == before.recipe && jpeg.report == before.report, "\(lua)")
        }
    }

    @Test(arguments: DevelopSettings.Form.allCases)
    func `a sidecar's profile converts as the catalog's does`(form: DevelopSettings.Form) throws {
        let fields = DevelopSettings.photo()
        let lua = try LightroomPhoto.convert(
            CameraRawSettings(lua: DevelopSettings.lua(fields)), photo: Self.canon,
            source: .catalog(URL(filePath: "/Photos/Lightroom Catalog.lrcat"), photo: 7, digest: nil),
        )
        let settings = try #require(CameraRawSettings(xmp: DevelopSettings.xmp(fields, form: form)))
        let xmp = LightroomPhoto.convert(settings, photo: Self.canon, source: .sidecar(URL(filePath: "/IMG_0001.xmp")))
        #expect(try xmp.recipe.baseLook.isSameLook(as: Self.copy("Adobe Color")))
        #expect(xmp.recipe.baseLook == lua.recipe.baseLook && xmp.report == lua.report)
        #expect(xmp.report.profile == .onThisMac("Adobe Color"))
    }

    @Test func `the notes say in words which look renders the photo`() {
        #expect(PhotoNote
            .onThisMac("Adobe Color", leavingOut: []) == "“Adobe Color” is on this Mac, so it renders the photo.")
        #expect(PhotoNote.onThisMac("B&W 05", leavingOut: ["Clarity +8", "Grain Amount 20"])
            == "“B&W 05” is on this Mac, so it renders the photo, but Redlamp leaves out what it sets besides its "
            + "tables: Clarity +8, Grain Amount 20.")
        #expect(PhotoNote.notOnThisMac("Adobe Color", standIn: "Redlamp Color")
            == "“Adobe Color” isn't on this Mac, so Redlamp Color stands in.")
        #expect(PhotoNote.notOnThisMac("Adobe Standard", standIn: PhotoNote.embeddedCopy)
            == "“Adobe Standard” isn't on this Mac, so the copy the photo embeds stands in.")
        #expect(PhotoNote.notOnThisMac("Vintage 07", standIn: nil)
            == "“Vintage 07” isn't on this Mac, and Redlamp has no look like it, so Redlamp Color stands in.")
    }
}
