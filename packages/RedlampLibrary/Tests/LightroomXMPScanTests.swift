import CoreGraphics
import Foundation
import ImageIO
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes
import Testing
import UniformTypeIdentifiers
@testable import RedlampLibrary

/// Convert Lightroom Edits…'s look at the photos before anything is written, and the XMP metadata sync (LIB-24)
/// leaving Lightroom's develop settings as they are.
struct LightroomXMPScanTests {
    @Test func `photos with a Lightroom edit and none in Redlamp convert, and those edited in Redlamp keep theirs`(
    ) throws {
        let folder = try TemporaryFolder()
        let store = SidecarStore()
        func photo(_ name: String, xmp: String?) throws -> URL {
            let url = folder.url.appending(path: name)
            try LightroomXMPFixture.image(url, type: .jpeg, xmp: xmp)
            return url
        }
        let full = try photo("IMG_0001.jpg", xmp: LightroomXMPFixture.packet(rawFileName: nil, masks: false))
        let masked = try photo("IMG_0002.jpg", xmp: LightroomXMPFixture.packet(rawFileName: nil))
        let edited = try photo("IMG_0003.jpg", xmp: LightroomXMPFixture.packet(rawFileName: nil))
        var recipe = EditRecipe()
        recipe[.exposure] = 0.7
        try store.save(Sidecar(recipe: recipe), for: edited)
        let rated = try photo("IMG_0004.jpg", xmp: LightroomXMPFixture.packet(rawFileName: nil, masks: false))
        try store.save(Sidecar(recipe: EditRecipe(), metadata: PhotoMetadata(rating: 4)), for: rated)
        let plain = try photo("IMG_0005.jpg", xmp: nil)
        let once = try photo("IMG_0010.jpg", xmp: LightroomXMPFixture.packet(rawFileName: nil, exposure: "+2.00"))
        let first = try LightroomPhoto.convert(
            #require(LightroomPhotoXMP.edit(for: full)?.settings),
            photo: LightroomPhotoContext(size: PixelSize(width: 8, height: 6), isRaw: false), source: .embedded(once),
        )
        try store.save(Sidecar(recipe: first.recipe), for: once)
        let raw = folder.url.appending(path: "IMG_0006.CR3")
        try Data("not an image".utf8).write(to: raw)
        try Data(LightroomXMPFixture.packet(rawFileName: nil, masks: false).utf8)
            .write(to: folder.url.appending(path: "IMG_0006.xmp"))

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let scan = LightroomXMPScan.scan([full, masked, edited, rated, plain, raw, once], date: date) { url in
            LightroomPhotoXMP.redlampEdit(of: url, in: store)
        }
        #expect(scan.conversions.map(\.photo) == [full, masked, rated])
        #expect(scan.edited == [edited] && scan.unsized == [raw] && scan.converted == [once] && scan.found == 6)
        #expect(scan.photos(.full) == [full, rated] && scan.photos(.leftOut) == [masked])
        #expect(scan.reasons.map(\.reason) == [.notYetChecked] && scan.reasons.first?.photos == [masked])
        let converted = try #require(scan.conversions.first)
        #expect(converted.imported.recipe[.exposure] == 0.4)
        #expect(converted.imported.provenance.source == .embedded(full) && converted.imported.provenance.date == date)
    }

    @Test func `a raw's edit names the photographer's Adobe profile where its camera's list has it, else Redlamp's look`(
    ) throws {
        let folder = try TemporaryFolder()
        let store = SidecarStore()
        let settings = """
           crs:Version="15.4"
           crs:ProcessVersion="11.0"
           crs:CameraProfile="Adobe Standard"
           crs:Exposure2012="+0.40"
           crs:HasSettings="True"
        """
        func raw(_ name: String) throws -> URL {
            let url = folder.url.appending(path: "\(name).CR3")
            try Data("not an image".utf8).write(to: url)
            try Data(LightroomXMPFixture.packet(rawFileName: nil, settings: settings, masks: false).utf8)
                .write(to: folder.url.appending(path: "\(name).xmp"))
            return url
        }
        let (canon, nikon, unindexed) = try (raw("IMG_0001"), raw("IMG_0002"), raw("IMG_0003"))
        let r5 = LightroomXMPScan.Camera(make: "Canon", model: "Canon EOS R5")
        let z8 = LightroomXMPScan.Camera(make: "Nikon", model: "NIKON Z 8")
        let size = PixelSize(width: 6000, height: 4000)
        let standard = CameraProfileLook(
            reference: BaseLookReference(
                id: BaseLookReference.adobeIDPrefix + "0123456789abcdef",
                name: "Adobe Standard",
            ),
            group: .adobeRaw, summary: "Adobe Standard, for the test",
        )
        let scan = LightroomXMPScan.scan(
            [canon, nikon, unindexed],
            indexed: [
                canon: LightroomXMPScan.Indexed(context: LightroomPhotoContext(size: size, isRaw: true), camera: r5),
                nikon: LightroomXMPScan.Indexed(context: LightroomPhotoContext(size: size, isRaw: true), camera: z8),
            ],
            adobeProfiles: [r5: [standard], z8: []],
        ) { LightroomPhotoXMP.redlampEdit(of: $0, in: store) }

        #expect(scan.conversions.map(\.photo) == [canon, nikon], "the index sizes them, as ImageIO can't")
        #expect(scan.unsized == [unindexed])
        let own = scan.conversions[0].imported
        #expect(own.recipe.baseLook == standard.reference && own.report.profile == .onThisMac("Adobe Standard"))
        let standIn = scan.conversions[1].imported
        #expect(!standIn.recipe.baseLook.isAdobeProfile)
        let look = AdobeProfileStandIn.look(forProfileNamed: "Adobe Standard")
        #expect(standIn.report.profile == .standIn(profile: "Adobe Standard", look: look.name))
    }

    @Test func `a Fujifilm simulation takes the look filling its slot on this Mac, else Redlamp's film look`() throws {
        let folder = try TemporaryFolder()
        let store = SidecarStore()
        func raw(_ name: String, profile: String) throws -> URL {
            let url = folder.url.appending(path: "\(name).RAF")
            try Data("not an image".utf8).write(to: url)
            let settings = """
               crs:Version="15.4"
               crs:ProcessVersion="11.0"
               crs:CameraProfile="\(profile)"
               crs:Exposure2012="+0.40"
               crs:HasSettings="True"
            """
            try Data(LightroomXMPFixture.packet(rawFileName: nil, settings: settings, masks: false).utf8)
                .write(to: folder.url.appending(path: "\(name).xmp"))
            return url
        }
        let chrome = try raw("DSCF0001", profile: "Camera CLASSIC CHROME")
        let velvia = try raw("DSCF0002", profile: "Camera Velvia/Vivid")
        let size = PixelSize(width: 6240, height: 4160)
        let indexed = LightroomXMPScan.Indexed(context: LightroomPhotoContext(size: size))
        let lut = BaseLookReference(id: BaseLookReference.makerIDPrefix + "chrome", name: "Classic Chrome LUT")
        let scan = LightroomXMPScan.scan(
            [chrome, velvia], indexed: [chrome: indexed, velvia: indexed], slotLooks: [.chrome: lut],
        ) { LightroomPhotoXMP.redlampEdit(of: $0, in: store) }

        #expect(scan.conversions.map(\.photo) == [chrome, velvia])
        func note(_ imported: LightroomPhotoImport) -> String? {
            imported.report.entries.first { $0.setting == "CameraProfile" }?.note
        }
        let filled = scan.conversions[0].imported
        #expect(filled.recipe.baseLook == lut)
        #expect(note(filled) == "Classic Chrome LUT stands in for Lightroom's “Camera CLASSIC CHROME”.")
        let unfilled = scan.conversions[1].imported
        let film = FilmSlot.vividSlide.baseLook
        #expect(unfilled.recipe.baseLook == film)
        #expect(note(unfilled) == "\(film.name) stands in for Lightroom's “Camera Velvia/Vivid”.")
    }

    @Test func `the index's size and orientation of a photo are ImageIO's, its size turned back for the camera's turn`(
    ) async throws {
        let sandbox = try await XMPSandbox.make()
        defer { sandbox.remove() }
        func jpeg(_ name: String, orientation: Int) throws -> URL {
            let url = sandbox.url(name)
            let context = try #require(CGContext(
                data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            ))
            let image = try #require(context.makeImage())
            let destination = try #require(
                CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil),
            )
            let tiff: [CFString: Any] = [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "Canon EOS R5"]
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyOrientation: orientation, kCGImagePropertyTIFFDictionary: tiff,
            ] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            return url
        }
        let (turned, upright) = try (jpeg("IMG_0011.jpg", orientation: 6), jpeg("IMG_0012.jpg", orientation: 1))
        try await sandbox.indexAll()
        let unindexed = try jpeg("IMG_0013.jpg", orientation: 1)

        let indexed = try await LightroomXMPScan.indexed([turned, upright, unindexed], in: sandbox.index)
        #expect(indexed.count == 2)
        #expect(indexed[turned]?.context == LightroomPhotoXMP.context(of: turned))
        #expect(indexed[turned]?.context.size == PixelSize(width: 8, height: 6))
        #expect(indexed[turned]?.context.cameraOrientation == ImageOrientation(quarterTurns: 1))
        #expect(indexed[upright]?.context == LightroomPhotoXMP.context(of: upright))
        #expect(indexed[turned]?.camera == LightroomXMPScan.Camera(make: "Canon", model: "Canon EOS R5"))
    }

    @Test func `a photo reset to the defaults in Redlamp keeps its edit, though its edit no longer says it was converted`(
    ) throws {
        let folder = try TemporaryFolder()
        let store = SidecarStore()
        let photo = folder.url.appending(path: "IMG_0014.jpg")
        try LightroomXMPFixture.image(photo, type: .jpeg, xmp: LightroomXMPFixture.packet(rawFileName: nil))
        let converted = try LightroomPhoto.convert(
            #require(LightroomPhotoXMP.edit(for: photo)?.settings),
            photo: LightroomPhotoContext(size: PixelSize(width: 8, height: 6), isRaw: false), source: .embedded(photo),
        ).recipe
        try store.save(Sidecar(recipe: EditRecipe(), session: HistorySession(steps: [
            HistoryStep(action: .open, title: "Converted from Lightroom", recipe: converted),
            HistoryStep(action: .reset, title: "Reset", recipe: EditRecipe()),
        ])), for: photo)
        #expect(store.load(for: photo)?.recipe.provenance == nil && store.hasHistory(for: photo))

        #expect(LightroomPhotoXMP.redlampEdit(of: photo, in: store) == .edited)
        let scan = LightroomXMPScan.scan([photo]) { LightroomPhotoXMP.redlampEdit(of: $0, in: store) }
        #expect(scan.edited == [photo] && scan.conversions.isEmpty)
    }

    @Test func `a photo whose sidecar can't be read is left alone`() throws {
        let folder = try TemporaryFolder()
        let photo = folder.url.appending(path: "IMG_0007.jpg")
        try LightroomXMPFixture.image(photo, type: .jpeg, xmp: LightroomXMPFixture.packet(rawFileName: nil))
        let store = SidecarStore()
        try Data("{ not json".utf8).write(to: store.locator.url(for: photo))
        #expect(LightroomPhotoXMP.redlampEdit(of: photo, in: store) == .unreadable)
        let scan = LightroomXMPScan.scan([photo]) { LightroomPhotoXMP.redlampEdit(of: $0, in: store) }
        #expect(scan.unreadable == [photo] && scan.conversions.isEmpty)
    }

    @Test func `the XMP metadata sync writes no Camera Raw setting, and keeps Lightroom's as they are`() async throws {
        #expect(XMPNamespace.prefixes[CameraRawSettings.namespace] == nil)

        let sandbox = try await XMPSandbox.make()
        defer { sandbox.remove() }
        let raw = try sandbox.photo("IMG_0008.CR3")
        let lightroom = OtherApps.lightroom(rating: 2)
        try sandbox.write("IMG_0008.xmp", lightroom, modified: -600)
        let settings = try #require(LightroomPhotoXMP.edit(for: raw)?.settings)
        let imported = LightroomPhoto.convert(
            settings, photo: LightroomPhotoContext(size: PixelSize(width: 6000, height: 4000)),
            source: .sidecar(sandbox.url("IMG_0008.xmp")),
        )
        try SidecarStore().save(Sidecar(recipe: imported.recipe, metadata: PhotoMetadata(rating: 2)), for: raw)

        let jpeg = sandbox.url("IMG_0009.jpg")
        try LightroomXMPFixture.image(jpeg, type: .jpeg, xmp: LightroomXMPFixture.packet(rawFileName: nil))
        let jpegBytes = try Data(contentsOf: jpeg)
        let embedded = try #require(LightroomPhotoXMP.edit(for: jpeg)?.settings)
        let fromJPEG = LightroomPhoto.convert(
            embedded, photo: LightroomPhotoContext(size: PixelSize(width: 8, height: 6), isRaw: false),
            source: .embedded(jpeg),
        )
        try SidecarStore().save(Sidecar(recipe: fromJPEG.recipe, metadata: PhotoMetadata(rating: 5)), for: jpeg)
        try await sandbox.indexAll()
        try await sandbox.xmp.setSettings(XMPSettings(writes: true))
        _ = try await sandbox.sync()

        var sidecar = try #require(SidecarStore().load(for: raw))
        sidecar.metadata?.rating = 4
        try SidecarStore().save(sidecar, for: raw)
        let report = try await sandbox.sync()
        #expect(report.photo("IMG_0008.CR3")?.written == [.rating])
        let written = try sandbox.text("IMG_0008.xmp")
        let crs = { (text: String) in text.split(separator: "\n").filter { $0.contains("crs:") } }
        #expect(crs(written) == crs(lightroom) && !crs(lightroom).isEmpty)
        #expect(CameraRawSettings(xmp: Data(written.utf8)) == CameraRawSettings(xmp: Data(lightroom.utf8)))

        #expect(try Data(contentsOf: jpeg) == jpegBytes)
        for name in ["IMG_0009.xmp", "IMG_0009.jpg.xmp"] where sandbox.exists(name) {
            #expect(try !sandbox.text(name).contains(CameraRawSettings.namespace))
        }
    }
}
