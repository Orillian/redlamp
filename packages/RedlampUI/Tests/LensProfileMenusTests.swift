import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampUI

/// Lightroom's Setup, Make, Model and Profile menus for lens profiles (LNS-15), as the editor works them.
@MainActor
struct LensProfileMenusTests {
    static let options = [
        LensProfileOption(
            make: "Canon", model: "Canon EF 24-70mm f/2.8L II USM", name: "Adobe (Canon EF 24-70mm f/2.8L II USM)",
            fileName: "Canon EOS 5D Mark III (Canon EF 24-70mm f2.8L II USM) - RAW.lcp", folder: .cameraRaw,
        ),
        LensProfileOption(
            make: "Helios", model: "Helios 44-2 58mm f/2", name: "Mine (Helios 44-2)", fileName: "Helios.lcp",
            folder: .redlamp,
        ),
        LensProfileOption(
            make: "Helios", model: "Helios 44-2 58mm f/2", name: "Mine (Helios 44-2)", fileName: "Helios A7.lcp",
            folder: .cameraRawUser,
        ),
    ]

    private func openEditor() async throws -> (EditorModel, () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let engine = StubEngine()
        engine.lensCorrection = LensPanelTextTests.correction(.sony)
        let model = EditorModel(engine: engine)
        model.select(folder.appending(path: "IMG_0001.ARW"))
        for _ in 0 ..< 200 where model.info == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(model.info != nil)
        model.lensProfileOptions = Self.options
        return (model, { try? FileManager.default.removeItem(at: folder) })
    }

    @Test func `the menus choose a profile by its make, its model or itself, which makes the Setup Custom`(
    ) async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        #expect(model.lensProfileSetup == .defaults && model.shownLensProfile == nil)
        #expect(LensProfilePicker.items(.make, in: model).map(\.title) == ["None", "Canon", "Helios"])
        #expect(LensProfilePicker.items(.model, in: model).map(\.title) == ["None"])
        model.chooseLensProfile(make: "Helios")
        #expect(model.recipe.lensProfileChoice == Self.options[1].choice && model.lensProfileSetup == .custom)
        #expect(LensProfilePicker.items(.model, in: model).map(\.title) == ["Helios 44-2 58mm f/2"])
        // Two profiles of one name are told apart by their folders.
        #expect(LensProfilePicker.items(.profile, in: model).map(\.title) == [
            "Mine (Helios 44-2) (Redlamp)", "Mine (Helios 44-2) (your Camera Raw)",
        ])
        model.chooseLensProfile(Self.options[2])
        #expect(LensProfilePicker.selection(.profile, in: model) == "Helios A7.lcp")
        #expect(model.history.last?.name.hasPrefix("Lens Profile") == true)
    }

    @Test func `Default and Auto forget a profile chosen by hand, and Custom keeps the one shown`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        model.chooseLensProfile(Self.options[0])
        model.setLensProfileSetup(.auto)
        #expect(model.recipe.lensProfileChoice == LensProfileChoice(setup: .auto))
        model.setLensProfileSetup(.custom)
        #expect(model.recipe.lensProfileChoice == LensProfileChoice(setup: .custom), "the file's own correction shown")
        model.setLensProfileSetup(.defaults)
        #expect(model.recipe.lensProfileChoice == nil)
    }

    @Test func `a profile the edit names that isn't used is reported, with what stands in`() async throws {
        let (model, cleanup) = try await openEditor()
        defer { cleanup() }
        #expect(model.missingLensProfile == nil)
        model.setLensProfileChoice(LensProfileChoice(setup: .custom, name: "Gone", fileName: "Gone.lcp"))
        #expect(model.missingLensProfile?.text == "Profile not on this Mac: Gone")
        #expect(model.missingLensProfile?.help.hasSuffix("using the lens correction the Sony file carries") == true)
        // On this Mac, but the stub engine resolves nothing.
        model.chooseLensProfile(Self.options[0])
        #expect(model.missingLensProfile?.text == "Profile can't be used: Adobe (Canon EF 24-70mm f/2.8L II USM)")
        // Auto passes over a named profile of another lens for the photo's own correction, quietly.
        model.setLensProfileChoice(LensProfileChoice(
            setup: .auto,
            name: Self.options[0].name,
            fileName: Self.options[0].fileName,
        ))
        #expect(model.missingLensProfile == nil)
    }
}
