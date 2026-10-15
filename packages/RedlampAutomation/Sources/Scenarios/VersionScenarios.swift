#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import Foundation
    import RedlampDocument
    import RedlampEngineAPI
    @_spi(Harness) import RedlampUI

    /// Versions of a photo's edit (EDT-09), as Lightroom Classic's virtual copies are: made with ⌘', opened, renamed
    /// and removed from the Photo menu, and kept through saving, opening the photo again, Sync and export.
    enum VersionScenarios {
        static let all: [Scenario] = [versions]

        static let versions = Scenario(
            "develop.versions",
            "A version is another edit of the photo, kept through saving, reopening, Sync and export",
            claims: [.action(.createVersion)],
        ) { app in
            try app.openRaw(1)
            let name = try app.main { $0.selection?.lastPathComponent ?? "" }
            try app.set(.exposure, 0.3)

            try app.press(.createVersion)
            try app.wait("Copy 1, open") { $0.versions.map(\.name) == ["Copy 1"] && $0.openVersion != nil }
            try app.expect(try app.main { abs($0.value(.exposure) - 0.3) < 1e-6 }, "Copy 1 isn't the edit it copied")
            try app.set(.contrast, 25)

            try app.choose(EditorModel.originalName)
            try app.wait("the photo's own edit") { $0.openVersion == nil && $0.value(.contrast) == 0 }
            try app.choose("Copy 1")
            try app.wait("Copy 1 again") { $0.openVersion != nil && abs($0.value(.contrast) - 25) < 1e-6 }

            try app.choose("Rename Version…")
            try app.waitForSheet("Rename Version")
            try app.selectSheetField()
            try app.typeInAttachedSheet("Contrast")
            try app.pressInSheet(KeyCombo(.character("\r")))
            try app.waitForNoSheet("Rename Version")
            try app.wait("the new name") { $0.versions.map(\.name) == ["Contrast"] }
            try app.waitSaved(name, containing: "\"name\" : \"Contrast\"")

            // Opening the photo again opens its own edit, with the version beside it.
            try app.openRaw(2)
            try app.openRaw(1)
            try app.wait("the photo with its version") { model in
                model.selection?.lastPathComponent == name && model.versions.map(\.name) == ["Contrast"]
                    && model.openVersion == nil && abs(model.value(.exposure) - 0.3) < 1e-6
            }
            try app.choose("Contrast")
            try app.wait("the version's edit") { $0.openVersion != nil && abs($0.value(.contrast) - 25) < 1e-6 }

            try syncsFromVersion(app, open: name)
            try exportsVersion(app)

            try app.choose("Remove Version…")
            try app.waitForSheet("Remove Version")
            try app.pressInSheet(KeyCombo(.character("\r")))
            try app.waitForNoSheet("Remove Version")
            try app.wait("the version removed") { $0.versions.isEmpty && $0.openVersion == nil }
            try app.wait("the sidecar without it", timeout: 15) { _ in !app.sidecarJSON(name).contains("\"versions\"") }
            try app.choose(.resetAll)
            app.covered(.action(.createVersion), via: .key)
        }

        /// Sync Settings from the version open onto the rest of the folder, then Undo Sync.
        private static func syncsFromVersion(_ app: RunningApp, open name: String) throws {
            let other = try app.photoNames().first { $0 != name && $0.uppercased().hasSuffix(".NEF") }
                ?? app.photoNames().first { $0 != name } ?? ""
            try app.choose(.selectAllPhotos)
            try app.wait("every photo selected") { $0.selectedPhotos.count == $0.items.count }
            try app.choose(.syncSettingsAgain)
            try app.wait("the sync", timeout: 180) { $0.settingsSync.progress == nil && $0.settingsSync.canUndo }
            try app.expect(
                app.sidecarJSON(other).contains("basic.contrast"), "\(other) didn't get the version's Contrast",
            )
            try app.expect(try app.main { $0.openVersion != nil }, "Sync left the version")
            try app.choose(.undoSync)
            try app.wait("Undo Sync", timeout: 180) { $0.settingsSync.progress == nil && !$0.settingsSync.canUndo }
            try app.choose(.deselectOtherPhotos)
        }

        /// Exports the version open, and finds its edit in the file.
        private static func exportsVersion(_ app: RunningApp) throws {
            let settings = try app.host.map { host in try app.main { _ in host.exports.initialSettings } }
                ?? ExportSettings()
            let folder = settings.destinationFolder ?? app.photos
            let file = folder.appending(path: "Version-export.\(settings.format.fileExtension)")
            try? FileManager.default.removeItem(at: file)
            defer { try? FileManager.default.removeItem(at: file) }
            try app.choose(Menus.title(of: .export))
            try app.waitForSheet("the Export dialog")
            app.pause(0.5)
            try app.clickInSheet("export.naming")
            try app.selectSheetField()
            try app.typeInAttachedSheet("Version-export")
            app.pause(0.5)
            try app.expect(
                try app.pressInSheet(KeyCombo(.character("\r"))),
                "The Export dialog's Export button didn't take Return",
            )
            try app.waitForNoSheet("the Export dialog")
            try app.wait("the export", timeout: 120) { _ in FileManager.default.fileExists(atPath: file.path) }
            try app.wait("the export written", timeout: 30) { _ in EmbeddedEdit.read(file) != nil }
            let contrast = EmbeddedEdit.read(file)?.recipe[.contrast]
            try app.expect(contrast == 25, "The export carries Contrast \(contrast.map { "\($0)" } ?? "none"), not 25")
        }
    }
#endif
