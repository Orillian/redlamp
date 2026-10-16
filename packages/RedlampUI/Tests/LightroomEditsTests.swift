import CoreGraphics
import Foundation
import ImageIO
import RedlampDocument
import RedlampEngineAPI
import Testing
import UniformTypeIdentifiers
@testable import RedlampUI

/// Lightroom's edits in XMP (EDT-12): Convert Lightroom Edits… with its report, batch and Undo, and a photo
/// converted as it opens, once, with Convert Again.
@MainActor
struct LightroomEditsTests {
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// A small JPEG holding a photo's develop settings as its own XMP, as Lightroom saves them to the file
    /// (`docs/research/notes/EDT-lightroom-develop-settings.md`), with Lightroom's `profile`; none with a nil
    /// `exposure`.
    private static func jpeg(_ url: URL, exposure: String?, profile: String? = nil) throws {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ))
        let xmp = exposure.map { exposure in
            """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
             <rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
               xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" tiff:Make="Example" crs:Version="15.4"
               crs:ProcessVersion="11.0" crs:WhiteBalance="As Shot" crs:Exposure2012="\(exposure)"
               crs:Contrast2012="+12"\(profile.map { " crs:CameraProfile=\"\($0)\"" } ?? "") crs:HasSettings="True"
               crs:HasCrop="False"/>
            </rdf:RDF></x:xmpmeta>
            """
        }
        let metadata = try xmp.map { try #require(CGImageMetadataCreateFromXMPData(Data($0.utf8) as CFData)) }
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func `Convert Lightroom Edits reports first, converts the photos with no edit in Redlamp, and Undo puts them back`(
    ) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (a, b, c) = (
            folder.appending(path: "A.jpg"),
            folder.appending(path: "B.jpg"),
            folder.appending(path: "C.jpg"),
        )
        try Self.jpeg(a, exposure: "+0.40")
        try Self.jpeg(b, exposure: "+0.40")
        try Self.jpeg(c, exposure: nil)
        let store = SidecarStore()
        var edited = EditRecipe()
        edited[.contrast] = 30
        try store.save(Sidecar(recipe: edited), for: b)
        let model = EditorModel(engine: StubEngine())
        [a, b, c].forEach { model.library.insert(LibraryItem(url: $0)) }
        model.select(c)
        try await eventually { model.info?.url == c }
        model.selectAllPhotos()

        #expect(model.canPerform(.convertLightroomEdits))
        model.perform(.convertLightroomEdits)
        try await eventually { model.lightroomConversion?.scan != nil }
        let scan = try #require(model.lightroomConversion?.scan)
        #expect(scan.conversions.map(\.photo) == [a] && scan.edited == [b] && scan.found == 2)
        #expect(scan.lines.contains("Already edited in Redlamp, keeping their edit: 1 photo"))
        #expect(store.load(for: a) == nil, "the report writes nothing")

        model.confirmLightroomConversion()
        try await eventually {
            if case .done? = model.lightroomConversion?.stage {
                true
            } else {
                false
            }
        }
        let converted = try #require(store.load(for: a))
        #expect(converted.recipe[.exposure] == 0.4 && converted.recipe[.contrast] == 12)
        #expect(converted.recipe.provenance?.source == .embeddedXMP && converted.recipe.provenance?.path == a.path)
        #expect(store.loadHistory(for: a).flatMap(\.steps).map(\.title).contains("Convert Lightroom Edits"))
        #expect(store.load(for: b)?.recipe == edited)

        #expect(model.libraryUndoKind == .lightroomConversion)
        model.undoLightroomConversion()
        await model.settingsSync.idle()
        #expect(store.load(for: a) == nil && model.lightroomConversion == nil)
        #expect(model.libraryUndoKind == nil, "the sheet's Undo takes it off ⌘Z's")
    }

    @Test func `⌘Z takes back Convert Lightroom Edits, as it takes back an import from Lightroom Classic`(
    ) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (a, b, c) = (
            folder.appending(path: "A.jpg"),
            folder.appending(path: "B.jpg"),
            folder.appending(path: "C.jpg"),
        )
        try Self.jpeg(a, exposure: "+0.40")
        try Self.jpeg(b, exposure: "+0.70")
        try Self.jpeg(c, exposure: nil)
        let store = SidecarStore()
        let model = EditorModel(engine: StubEngine())
        [a, b, c].forEach { model.library.insert(LibraryItem(url: $0)) }
        model.select(c)
        try await eventually { model.info?.url == c }
        model.selectAllPhotos()
        model.perform(.convertLightroomEdits)
        try await eventually { model.lightroomConversion?.scan != nil }
        model.confirmLightroomConversion()
        try await eventually { model.libraryUndoKind == .lightroomConversion }
        #expect(store.load(for: a)?.recipe[.exposure] == 0.4 && store.load(for: b)?.recipe[.exposure] == 0.7)
        model.closeLightroomConversion()

        #expect(model.canPerform(.undo) && model.perform(.undo))
        await model.settingsSync.idle()
        #expect(store.load(for: a) == nil && store.load(for: b) == nil)
        #expect(model.libraryUndoKind == nil && !model.canPerform(.redo))
    }

    @Test func `a raw opening converts its Lightroom edit with its camera's Adobe profile on this Mac, else Redlamp's look`(
    ) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The stub engine opens every photo as a raw.
        let (canon, nikon) = (folder.appending(path: "F.jpg"), folder.appending(path: "G.jpg"))
        try Self.jpeg(canon, exposure: "+0.40", profile: "Adobe Standard")
        try Self.jpeg(nikon, exposure: "+0.40", profile: "Adobe Standard")
        let standard = CameraProfileLook(
            reference: BaseLookReference(
                id: BaseLookReference.adobeIDPrefix + "0123456789abcdef",
                name: "Adobe Standard",
            ),
            group: .adobeRaw, summary: "Adobe Standard, for the test",
        )
        let engine = StubEngine()
        engine.camera = (make: "Canon", model: "EOS R5")
        engine.cameraProfiles = [standard]
        let model = EditorModel(engine: engine)
        [canon, nikon].forEach { model.library.insert(LibraryItem(url: $0)) }
        model.select(canon)
        try await eventually { model.info?.url == canon }
        #expect(model.recipe.baseLook == standard.reference && model.recipe.provenance != nil)
        #expect(engine.profiledCameras.withLock { $0 } == ["Canon EOS R5"])

        engine.camera = (make: "Nikon", model: "Z 8")
        engine.cameraProfiles = []
        model.select(nikon)
        try await eventually { model.info?.url == nikon }
        #expect(model.recipe.provenance != nil && !model.recipe.baseLook.isAdobeProfile)
        #expect(engine.profiledCameras.withLock { $0 }.last == "Nikon Z 8")
    }

    @Test func `a converted photo reset to the defaults doesn't convert again when it opens`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (photo, other) = (folder.appending(path: "H.jpg"), folder.appending(path: "I.jpg"))
        try Self.jpeg(photo, exposure: "+0.40")
        try Self.jpeg(other, exposure: nil)
        let store = SidecarStore()
        let model = EditorModel(engine: StubEngine())
        [photo, other].forEach { model.library.insert(LibraryItem(url: $0)) }
        model.select(photo)
        try await eventually { model.info?.url == photo }
        #expect(model.history.map(\.title) == ["Converted from Lightroom"])
        model.resetAll()
        #expect(model.recipe.provenance == nil && model.recipe[.exposure] == 0)
        try await eventually { store.hasHistory(for: photo) }

        model.select(other)
        try await eventually { model.info?.url == other }
        model.select(photo)
        try await eventually { model.info?.url == photo }
        #expect(model.recipe.provenance == nil && model.recipe[.exposure] == 0)
        #expect(model.history.map(\.title) == ["Opened"])
    }

    @Test func `a photo opens with its Lightroom edit converted once, and Convert Again keeps the edit it replaces`(
    ) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (photo, other) = (folder.appending(path: "D.jpg"), folder.appending(path: "E.jpg"))
        try Self.jpeg(photo, exposure: "+0.40")
        try Self.jpeg(other, exposure: nil)
        let store = SidecarStore()
        let model = EditorModel(engine: StubEngine())
        [photo, other].forEach { model.library.insert(LibraryItem(url: $0)) }
        model.select(photo)
        try await eventually { model.info?.url == photo }
        #expect(model.recipe[.exposure] == 0.4 && model.recipe.provenance?.source == .embeddedXMP)
        #expect(model.history.map(\.title) == ["Converted from Lightroom"])
        #expect(model.provenanceNotice?.title == "From Lightroom’s XMP in the photo: every setting converted")
        try await eventually { store.load(for: photo)?.recipe.provenance != nil }

        try Self.jpeg(photo, exposure: "+1.00")
        model.select(other)
        try await eventually { model.info?.url == other }
        #expect(model.provenanceNotice == nil)
        model.select(photo)
        try await eventually { model.info?.url == photo }
        #expect(model.recipe[.exposure] == 0.4, "converted once: its XMP changing since doesn't convert it again")

        model.setValue(.contrast, 40)
        model.convertLightroomEditAgain()
        try await eventually { model.recipe[.exposure] == 1 }
        #expect(model.recipe[.contrast] == 12 && model.history.last?.title == "Convert Again")
        #expect(model.snapshots.last?.name == "Before Convert Again" && model.snapshots.last?.recipe[.contrast] == 40)
    }
}
