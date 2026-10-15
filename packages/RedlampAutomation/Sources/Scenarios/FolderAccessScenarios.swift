#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import Foundation
    import RedlampDocument
    @_spi(Harness) import RedlampUI

    /// What Redlamp remembers of the folders people give it, as the App Sandbox needs it (ARC-17): each kept with a
    /// bookmark, security-scoped wherever one can be made, the settings that name folders copied to Redlamp's own
    /// folder, and the import's destination asked for at the first import rather than taken to be Pictures.
    enum FolderAccessScenarios {
        static let all: [Scenario] = [bookmarks, asksForDestination]

        /// File › Open's folder, as its panel hands it over, saved with its bookmark and copied to Redlamp's folder.
        static let bookmarks = Scenario(
            "folders.bookmarks",
            "A folder added to Folders is saved with its bookmark, security-scoped where one can be made, and "
                + "Redlamp's own folder holds a copy of the settings that name folders",
            claims: [.feature("library.folders")],
        ) { app in
            let scratch = try SourcesScratch(app, photos: ["FB_0001.jpg"])
            defer { scratch.remove(app) }
            try scratch.index(app)
            let path = scratch.folder.standardizedFileURL.path
            let scoped = FolderAccess.bookmark(for: scratch.folder) != nil
            @Sendable func saved(_ data: Data?) -> WorkingFolder? {
                data.flatMap { try? JSONDecoder().decode([WorkingFolder].self, from: $0) }?.first { $0.path == path }
            }

            try app.wait("the folder saved with its bookmark", timeout: 30) { _ in
                saved(UserDefaults.standard.data(forKey: "folders.roots"))?.bookmark != nil
            }
            let folder = saved(UserDefaults.standard.data(forKey: "folders.roots"))
            try app.expect(
                folder?.isSecurityScoped == scoped,
                "the folder's bookmark is \(folder?.isSecurityScoped == true ? "" : "not ")security-scoped, where "
                    + "this Mac \(scoped ? "makes" : "can't make") one",
            )
            try app.wait("the copy in Redlamp's folder", timeout: 15) { _ in
                let copy = (try? Data(contentsOf: FolderSettingsCopy.standard))
                    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                return saved(copy?["folders.roots"] as? Data)?.bookmark == folder?.bookmark
            }
            app.covered(.feature("library.folders"), via: .model)
        }

        /// With no destination chosen, Import opens the destination's panel and copies nothing until one is chosen;
        /// the folder chosen keeps its bookmark.
        static let asksForDestination = Scenario(
            "import.asks-destination",
            "The first import asks where the photos go: Import opens the destination's panel, Cancel copies nothing, "
                + "and once a destination is chosen the photos are copied there and it keeps its bookmark",
            claims: [.feature("library.import")],
        ) { app in
            try app.openWorking()
            let scratch = try ImportScratch(app, photos: 2)
            let imported = scratch.destination.appending(path: "Imported", directoryHint: .isDirectory)
            defer {
                try? app.main { model in
                    (ImportWindowController.current?.window?.attachedSheet as? NSOpenPanel)?.cancel(nil)
                    ImportWindowController.forget(imported, in: model)
                }
                scratch.remove(app)
            }
            try FileManager.default.createDirectory(at: scratch.destination, withIntermediateDirectories: true)
            try app.main { _ in
                ImportWindowController.ignoresVolumes = true
                ImportWindowController.forgetDestination()
            }
            try app.choose(.importPhotos)
            try app.waitForImportWindow()
            try app
                .run("adding the folder") { _ in try? await ImportWindowController.current?.add(folder: scratch.card) }
            try app.wait("the folder browsed", timeout: 60) { _ in
                ImportWindowController.current.map { $0.isBrowsed && $0.photoCount == 2 } == true
            }
            let shown = try app.inImportWindow { $0.destinationShown }
            try app.expect(shown == "Not chosen yet: Import asks for it", "To shows the destination as “\(shown)”")

            try app.clickInImportWindow("import.import")
            // A launch's first panel waits to connect to AppKit's panel service.
            try app.wait("the destination's panel", timeout: 60) { _ in
                ImportWindowController.current?.window?.attachedSheet is NSOpenPanel
            }
            let message = try app.main { _ in
                (ImportWindowController.current?.window?.attachedSheet as? NSOpenPanel)?.message
            }
            try app.expect(message == "Choose where the photos are copied to.", "the panel asks “\(message ?? "")”")
            try app.main { _ in (ImportWindowController.current?.window?.attachedSheet as? NSOpenPanel)?.cancel(nil) }
            try app.wait("the panel to close") { _ in ImportWindowController.current?.window?.attachedSheet == nil }
            app.pause(0.5)
            let copied = (try? FileManager.default.contentsOfDirectory(atPath: scratch.destination.path)) ?? []
            try app.expect(copied.isEmpty, "Cancel in the destination's panel left \(copied.sorted())")

            // The folder the panel would choose.
            try app.inImportWindow { window in
                window.prepare(destination: scratch.destination, backup: nil, folders: "Imported", names: "{name}")
            }
            try app.clickInImportWindow("import.import")
            try app.wait("the import", timeout: 120) { _ in ImportWindowController.current?.isFinished == true }
            let result = try app.inImportWindow { $0.result.map { "\($0.verified)" } }
            try app.expect(result == "2", "Imported: \(result ?? "nothing")")
            let found = Set((try? FileManager.default.contentsOfDirectory(atPath: imported.path)) ?? [])
            try app.expect(Set(scratch.names).isSubset(of: found), "\(imported.path) holds \(found.sorted())")
            let kept = try app.inImportWindow { $0.keepsDestinationBookmark }
            let scoped = FolderAccess.bookmark(for: scratch.destination) != nil
            try app.expect(kept == scoped, "the destination \(kept ? "keeps" : "doesn't keep") a bookmark")
            app.covered(.feature("library.import"), via: .mouse)
        }
    }
#endif
