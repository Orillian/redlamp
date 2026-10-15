import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampUI

/// The photographer's Adobe camera profiles in the Base Look menu (TON-51, TON-52).
@MainActor
struct CameraProfileMenuTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "camera-profiles-\(UUID().uuidString)")

    static func look(_ name: String, _ group: CameraProfileLook.Group, monochrome: Bool = false) -> CameraProfileLook {
        CameraProfileLook(
            reference: BaseLookReference(id: BaseLookReference.adobeIDPrefix + "0123456789abcdef/" + name, name: name),
            group: group, summary: "\(name), for the test", isMonochrome: monochrome,
        )
    }

    static let looks = [
        look("Adobe Color", .adobeRaw), look("Adobe Monochrome", .adobeRaw, monochrome: true),
        look("Adobe Standard", .adobeRaw), look("Camera Faithful", .cameraMatching), look("B&W 01", .creative("B&W")),
        look("Vintage 01", .creative("Vintage")), look("Grain", .own(nil)),
    ]

    private func open(_ engine: StubEngine) async throws -> EditorModel {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        engine.camera = ("Canon", "EOS R5")
        let editor = EditorModel(engine: engine)
        let url = folder.appending(path: "IMG_0001.CR3")
        editor.library.insert(LibraryItem(url: url))
        editor.select(url)
        for _ in 0 ..< 400 where editor.info == nil || editor.cameraProfilesPhoto != url {
            try await Task.sleep(for: .milliseconds(5))
        }
        return editor
    }

    @Test func `the menu groups the photo's profiles as Lightroom does`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubEngine()
        engine.cameraProfiles = Self.looks
        let editor = try await open(engine)
        #expect(editor.cameraProfileSections.map(\.name) == [
            "Adobe Raw",
            "Camera Matching",
            "B&W",
            "Vintage",
            "Your Profiles",
        ])
        #expect(editor.cameraProfileSections[0].looks.map(\.reference.name) == [
            "Adobe Color",
            "Adobe Monochrome",
            "Adobe Standard",
        ])
    }

    @Test func `choosing a profile sets the edit's Base Look, and a black-and-white one the treatment`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubEngine()
        engine.cameraProfiles = Self.looks
        let editor = try await open(engine)
        editor.setBaseLook(Self.looks[0].reference)
        #expect(editor.baseLook.isSameLook(as: Self.looks[0].reference) && editor.treatment == .color)
        #expect(!editor.isBaseLookMissing && editor.cameraProfileStandIn == nil)
        editor.setBaseLook(Self.looks[1].reference)
        #expect(editor.treatment == .blackAndWhite)
    }

    @Test func `a look chosen over another camera's profile isn't missing on this camera`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubEngine()
        engine.cameraProfiles = Self.looks
        let editor = try await open(engine)
        let synced = BaseLookReference(
            id: BaseLookReference.adobeIDPrefix + "fedcba9876543210/Adobe Color",
            name: "Adobe Color",
        )
        editor.setBaseLook(synced)
        #expect(!editor.isBaseLookMissing && editor.cameraProfileStandIn == nil)
        let otherProfile = BaseLookReference(
            id: BaseLookReference.adobeIDPrefix + "fedcba9876543210",
            name: "Adobe Standard",
        )
        #expect(otherProfile.isSameAdobeLook(as: BaseLookReference(
            id: BaseLookReference.adobeIDPrefix + "0011223344556677",
            name: "Adobe Standard",
        )))
    }

    @Test func `where the profile isn't on this Mac, Redlamp's look of the same name stands in`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubEngine()
        engine.cameraProfiles = Self.looks
        let editor = try await open(engine)
        editor.setBaseLook(Self.look("Adobe Vivid", .adobeRaw).reference)
        #expect(editor.isBaseLookMissing && editor.cameraProfileStandIn == .vivid)
        editor.setBaseLook(Self.look("Camera Portrait", .cameraMatching).reference)
        #expect(editor.cameraProfileStandIn == .portrait)
    }

    @Test func `chosen files are remembered where they are, and those that can't be used are named`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = StubEngine()
        engine.refusedProfiles = ["Preset.xmp": "is a preset, not a profile"]
        let editor = try await open(engine)
        let good = folder.appending(path: "Mine.dcp")
        let preset = folder.appending(path: "Preset.xmp")
        try Data("profile".utf8).write(to: good)
        try Data("preset".utf8).write(to: preset)
        await editor.chooseCameraProfiles([good, preset])
        #expect(engine.chosenProfiles.withLock { $0 } == [good])
        #expect(editor.cameraProfileIssues == ["“Preset.xmp” is a preset, not a profile."])
        // A folder is taken whole, however its URL was made.
        let pack = folder.appending(path: "Pack")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        await editor.chooseCameraProfiles([URL(fileURLWithPath: pack.path, isDirectory: false)])
        #expect(engine.chosenProfiles.withLock { $0 }.map(\.path) == [pack.path] && editor.cameraProfileIssues.isEmpty)
    }

    @Test func `the stand-in follows the words in a profile's name`() {
        let cases: [(String, BuiltInBaseLook)] = [
            ("Adobe Standard", .color), ("Adobe Color", .color), ("Adobe Neutral", .neutral), ("Adobe Vivid", .vivid),
            ("Adobe Portrait", .portrait), ("Adobe Landscape", .landscape), ("Adobe Monochrome", .monochrome),
            ("B&W 03", .monochrome), ("Camera Velvia/VIVID", .vivid), ("Camera ASTIA/Soft", .portrait),
            ("Camera PRO Neg. Std", .portrait), ("Artistic 04", .color),
        ]
        for (name, expected) in cases {
            #expect(AdobeProfileStandIn.look(forProfileNamed: name) == expected, "\(name)")
        }
    }
}
