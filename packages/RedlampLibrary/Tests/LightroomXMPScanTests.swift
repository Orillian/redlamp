import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes
import Testing
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
        let raw = folder.url.appending(path: "IMG_0006.CR3")
        try Data("not an image".utf8).write(to: raw)
        try Data(LightroomXMPFixture.packet(rawFileName: nil, masks: false).utf8)
            .write(to: folder.url.appending(path: "IMG_0006.xmp"))

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let scan = LightroomXMPScan.scan([full, masked, edited, rated, plain, raw], date: date) { url in
            LightroomPhotoXMP.redlampEdit(of: url, in: store)
        }
        #expect(scan.conversions.map(\.photo) == [full, masked, rated])
        #expect(scan.edited == [edited] && scan.unsized == [raw] && scan.found == 5)
        #expect(scan.photos(.full) == [full, rated] && scan.photos(.leftOut) == [masked])
        #expect(scan.reasons.map(\.reason) == [.notYetChecked] && scan.reasons.first?.photos == [masked])
        let converted = try #require(scan.conversions.first)
        #expect(converted.imported.recipe[.exposure] == 0.4)
        #expect(converted.imported.provenance.source == .embedded(full) && converted.imported.provenance.date == date)
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
