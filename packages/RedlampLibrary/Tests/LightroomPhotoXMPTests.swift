import CoreGraphics
import Foundation
import ImageIO
import RedlampEngineAPI
import RedlampRecipes
import Testing
import UniformTypeIdentifiers
@testable import RedlampLibrary

/// A photo's develop settings as Lightroom Classic and Camera Raw write them, from the format note
/// (`docs/research/notes/EDT-lightroom-develop-settings.md`): the photo's TIFF and Exif metadata, the file they
/// were written for, the settings as attributes, and a mask group, whose corrections and their masks are arrays
/// of structures.
enum LightroomXMPFixture {
    static func packet(
        rawFileName: String? = "IMG_0001.CR3", exposure: String = "+0.40", settings: String? = nil, masks: Bool = true,
    ) -> String {
        let rawFile = rawFileName.map { "\n   crs:RawFileName=\"\($0)\"" } ?? ""
        let develop = settings ?? """
           crs:Version="15.4"
           crs:ProcessVersion="11.0"\(rawFile)
           crs:WhiteBalance="As Shot"
           crs:Exposure2012="\(exposure)"
           crs:HasSettings="True"
           crs:HasCrop="False"
        """
        let maskGroup = masks ? Self.maskGroup : ""
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           tiff:Make="Example"
           xmp:Rating="3"
        \(develop)>\(maskGroup)
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    private static let maskGroup = """

           <crs:MaskGroupBasedCorrections>
            <rdf:Seq>
             <rdf:li rdf:parseType="Resource">
              <crs:What>Correction</crs:What>
              <crs:LocalExposure2012>0.5</crs:LocalExposure2012>
              <crs:CorrectionMasks>
               <rdf:Seq>
                <rdf:li crs:What="Mask/CircularGradient" crs:MaskValue="1" crs:Top="0.2" crs:Left="0.2"
                 crs:Bottom="0.8" crs:Right="0.8"/>
               </rdf:Seq>
              </crs:CorrectionMasks>
             </rdf:li>
            </rdf:Seq>
           </crs:MaskGroupBasedCorrections>
    """

    /// Ratings and keywords only, as the XMP sync or Bridge leave them: no develop settings.
    static let metadataOnly = packet(settings: "   crs:HasSettings=\"False\"\n   crs:Exposure2012=\"+1.00\"")

    /// A small photo at `url` of `type` holding `xmp` as its own XMP, or else turned by the camera's
    /// `orientation`, written by ImageIO.
    static func image(_ url: URL, type: UTType, xmp: String? = nil, orientation: Int? = nil) throws {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil,
        ))
        if let xmp {
            let metadata = try #require(CGImageMetadataCreateFromXMPData(Data(xmp.utf8) as CFData))
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        } else {
            CGImageDestinationAddImage(
                destination,
                image,
                orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary },
            )
        }
        #expect(CGImageDestinationFinalize(destination))
    }
}

struct LightroomPhotoXMPTests {
    @Test func `a raw's settings are read from the .xmp beside it, and only when they hold an edit`() throws {
        let folder = try TemporaryFolder()
        let raw = folder.url.appending(path: "IMG_0001.CR3")
        try Data("not an image".utf8).write(to: raw)
        #expect(LightroomPhotoXMP.edit(for: raw) == nil)

        let sidecar = folder.url.appending(path: "IMG_0001.xmp")
        try Data(LightroomXMPFixture.packet().utf8).write(to: sidecar)
        let edit = try #require(LightroomPhotoXMP.edit(for: raw))
        #expect(edit.source == .sidecar(sidecar) && edit.settings.text("Exposure2012") == "+0.40")
        #expect(edit.settings.structures("MaskGroupBasedCorrections")?.count == 1)

        try Data(LightroomXMPFixture.metadataOnly.utf8).write(to: sidecar)
        #expect(LightroomPhotoXMP.edit(for: raw) == nil)
        let preset = LightroomXMPFixture.packet(settings: """
           crs:PresetType="Normal"
           crs:Exposure2012="+1.00"
        """)
        try Data(preset.utf8).write(to: sidecar)
        #expect(LightroomPhotoXMP.edit(for: raw) == nil)
    }

    @Test func `darktable's .xmp is looked at after Lightroom's name, and holds no Camera Raw settings`() throws {
        let folder = try TemporaryFolder()
        let raw = folder.url.appending(path: "IMG_0002.ARW")
        try Data("not an image".utf8).write(to: raw)
        let darktable = folder.url.appending(path: "IMG_0002.ARW.xmp")
        try Data(LightroomXMPFixture.packet(rawFileName: nil).utf8).write(to: darktable)
        #expect(LightroomPhotoXMP.edit(for: raw)?.source == .sidecar(darktable))

        try Data(LightroomXMPFixture.packet(rawFileName: nil, exposure: "-0.25").utf8)
            .write(to: folder.url.appending(path: "IMG_0002.xmp"))
        #expect(LightroomPhotoXMP.edit(for: raw)?.settings.text("Exposure2012") == "-0.25")
    }

    @Test(arguments: [("jpg", UTType.jpeg), ("tif", .tiff), ("heic", .heic)])
    func `a photo's own XMP is read with every structure it holds`(ext: String, type: UTType) throws {
        let folder = try TemporaryFolder()
        let photo = folder.url.appending(path: "IMG_0003.\(ext)")
        try LightroomXMPFixture.image(photo, type: type, xmp: LightroomXMPFixture.packet(rawFileName: nil))
        let edit = try #require(LightroomPhotoXMP.edit(for: photo))
        #expect(edit.source == .embedded(photo) && edit.settings.number("Exposure2012") == 0.4)
        let correction = try #require(edit.settings.structures("MaskGroupBasedCorrections")?.first)
        #expect(correction.number("LocalExposure2012") == 0.5)
        #expect(correction.structures("CorrectionMasks")?.first?.text("What") == "Mask/CircularGradient")

        let plain = folder.url.appending(path: "IMG_0004.\(ext)")
        try LightroomXMPFixture.image(plain, type: type, xmp: LightroomXMPFixture.metadataOnly)
        #expect(LightroomPhotoXMP.edit(for: plain) == nil)
    }

    @Test func `the .xmp a raw and its JPEG share is the raw's, unless it names the JPEG`() throws {
        let folder = try TemporaryFolder()
        let jpeg = folder.url.appending(path: "IMG_0005.JPG")
        try LightroomXMPFixture.image(jpeg, type: .jpeg)
        let shared = folder.url.appending(path: "IMG_0005.xmp")
        try Data(LightroomXMPFixture.packet(rawFileName: nil).utf8).write(to: shared)
        #expect(LightroomPhotoXMP.edit(for: jpeg, rawBeside: { LightroomPhotoXMP.rawBeside(jpeg) })?
            .source == .sidecar(shared))

        let raw = folder.url.appending(path: "IMG_0005.cr3")
        try Data("not an image".utf8).write(to: raw)
        #expect(LightroomPhotoXMP.rawBeside(jpeg))
        #expect(LightroomPhotoXMP.edit(for: jpeg, rawBeside: { LightroomPhotoXMP.rawBeside(jpeg) }) == nil)
        #expect(LightroomPhotoXMP.edit(for: raw)?.source == .sidecar(shared))

        try Data(LightroomXMPFixture.packet(rawFileName: "IMG_0005.JPG").utf8).write(to: shared)
        #expect(LightroomPhotoXMP.edit(for: jpeg, rawBeside: { true })?.source == .sidecar(shared))
        #expect(LightroomPhotoXMP.edit(for: raw) == nil)
        try Data(LightroomXMPFixture.packet(rawFileName: "IMG_0005.CR3").utf8).write(to: shared)
        #expect(LightroomPhotoXMP.edit(for: jpeg, rawBeside: { false }) == nil)
        try Data(LightroomXMPFixture.packet(rawFileName: "DSC_9999.CR3").utf8).write(to: shared)
        #expect(LightroomPhotoXMP.edit(for: raw)?.source == .sidecar(shared))
    }

    @Test func `a photo's size as stored and its camera's orientation are read without decoding it`() throws {
        let folder = try TemporaryFolder()
        let photo = folder.url.appending(path: "IMG_0006.jpg")
        try LightroomXMPFixture.image(photo, type: .jpeg, orientation: 6)
        let context = try #require(LightroomPhotoXMP.context(of: photo))
        #expect(context.size == PixelSize(width: 8, height: 6) && !context.isRaw)
        #expect(context.cameraOrientation == ImageOrientation(quarterTurns: 1))
        #expect(LightroomPhotoXMP.context(of: folder.url.appending(path: "missing.jpg")) == nil)
        #expect((1 ... 8).map { ImageOrientation(exif: $0).swapsAxes } == [
            false,
            false,
            false,
            false,
            true,
            true,
            true,
            true,
        ])
    }
}
