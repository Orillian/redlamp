#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampDocument
    @_spi(Harness) import RedlampEngineAPI
    @_spi(Harness) import RedlampLibrary
    @_spi(Harness) import RedlampUI

    /// Lightroom Classic catalogs (LIB-29), from a catalog the run makes of photos of its own: never one Lightroom
    /// made, and never the run's working folder.
    enum LightroomScenarios {
        static let all: [Scenario] = [importCatalog, importEdits, allowAccess, setup]

        static let importEdits = Scenario(
            "library.lightroom-edits",
            "File › Import from Lightroom Classic… brings a photo's Lightroom edit and snapshot into its sidecar with its "
                + "fields, the photo opens in Develop with them, and Undo Import takes the edit back there, as a step of "
                + "its history",
            claims: [.action(.importFromLightroom)],
        ) { app in
            let scratch = try SourcesScratch(
                app, photos: ["Shoot/LR_0001.jpg", "Shoot/LR_0002.jpg", "Shoot/LR_0003.jpg"],
            )
            let tag = String(scratch.folder.lastPathComponent.suffix(8))
            let catalog = try LightroomScratchCatalog.make(of: scratch.folder, tag: tag, edits: true)
            defer {
                try? app.main { _ in LightroomWindowController.current?.close() }
                scratch.remove(app)
                try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent())
            }
            try app.main { model in model.showLibrary(.grid) }
            try app.choose(.importFromLightroom)
            try app.wait("the Lightroom Classic window", timeout: 30) { _ in
                LightroomWindowController.current?.window?.isVisible == true
            }
            try app.inLightroomWindow { $0.choose(catalog: catalog) }
            try app.wait("the catalog's report", timeout: 60) { _ in
                LightroomWindowController.current?.isReported == true
            }
            // The folder isn't in the library yet: its photos, and their edits, are found once Import adds it.
            let waiting = try app.inLightroomWindow { $0.report?.waiting }
            try app.expect(
                waiting == 3,
                "the photos waiting for their folder: \(String(describing: waiting))",
            )
            try app.clickInLightroomWindow("lightroom.import")
            try app.wait("the import", timeout: 180) { _ in LightroomWindowController.current?.isImported == true }
            let photo = scratch.photo(scratch.names[0])
            let written = SidecarStore(locator: .besidePhotos).load(for: photo)
            try app.expect(
                written?.recipe[.exposure] == 0.75 && written?.recipe.provenance?.source == .lightroomCatalog
                    && written?.snapshots.map(\.name) == ["Brighter"] && written?.metadata?.rating == 5,
                "the first photo's sidecar: \(String(describing: written))",
            )

            try app.main { model in
                Views.editorWindow?.makeKeyAndOrderFront(nil)
                model.select(photo)
            }
            try app.choose(.developModule)
            try app.wait("the photo in Develop with Lightroom's edit", timeout: 60) { model in
                model.selection == photo && model.info != nil && model.recipe[.exposure] == 0.75
            }
            let snapshots = try app.main { model in model.snapshots.map(\.name) }
            try app.expect(snapshots == ["Brighter"], "the snapshots in Develop: \(snapshots)")

            try app.wait("Undo Import", timeout: 30) { _ in
                LightroomWindowController.current?.button("lightroom.undo")?.enabled == true
            }
            try app.clickInLightroomWindow("lightroom.undo")
            try app.wait("the import taken back", timeout: 120) { _ in
                LightroomWindowController.current?.isUndone == true
            }
            try app.wait("the edit taken back in Develop, as a step of its history", timeout: 30) { model in
                model.recipe.isPristine && model.snapshots.isEmpty
                    && model.history.last?.title == "Undo Import from Lightroom Classic"
            }
            app.covered(.action(.importFromLightroom), via: .menu)
        }

        /// A catalog's root folder Redlamp can't read, as each one is in the App Sandbox until it's chosen in a panel
        /// (ARC-17): its permissions keep it from being read until the panel would have given access to it.
        static let allowAccess = Scenario(
            "library.lightroom-access",
            "File › Import from Lightroom Classic… asks for access to a catalog's folder Redlamp can't read, with "
                + "Allow Access…, and once it's allowed Import adds the folder and brings its photos' ratings",
            claims: [.action(.importFromLightroom)],
        ) { app in
            let scratch = try SourcesScratch(
                app, photos: ["Shoot/LR_0001.jpg", "Shoot/LR_0002.jpg", "Shoot/LR_0003.jpg"],
            )
            let tag = String(scratch.folder.lastPathComponent.suffix(8))
            let catalog = try LightroomScratchCatalog.make(of: scratch.folder, tag: tag)
            let root = scratch.folder.standardizedFileURL.path + "/"
            let shut = scratch.folder.path
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shut)
                try? app.main { _ in LightroomWindowController.current?.close() }
                scratch.remove(app)
                try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent())
            }
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: shut)
            try app.main { model in model.showLibrary(.grid) }
            try app.choose(.importFromLightroom)
            try app.wait("the Lightroom Classic window", timeout: 30) { _ in
                LightroomWindowController.current?.window?.isVisible == true
            }
            try app.inLightroomWindow { $0.choose(catalog: catalog) }
            try app.wait("the catalog's report", timeout: 60) { _ in
                LightroomWindowController.current?.isReported == true
            }
            let state = try app.inLightroomWindow { $0.report?.roots.first?.state }
            try app.expect(state == .needsAccess, "the folder Redlamp can't read is \(String(describing: state))")
            let button = try app.inLightroomWindow { $0.button("lightroom.locate.0") }
            try app.expect(
                button?.title == "Allow Access…" && button?.shown == true && button?.enabled == true,
                "the folder's button: \(String(describing: button))",
            )

            // Allow Access…'s panel can't be driven: the folder it would give access to is handed to the window.
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shut)
            try app.inLightroomWindow { $0.locate(root, at: scratch.folder) }
            try app.wait("the folder ready to add", timeout: 60) { _ in
                guard let window = LightroomWindowController.current, window.isReported else { return false }
                return window.report?.roots.first?.state == .notInLibrary
            }
            try app.clickInLightroomWindow("lightroom.import")
            try app.wait("the import", timeout: 180) { _ in LightroomWindowController.current?.isImported == true }
            let outcome = try app.inLightroomWindow { window in
                window.outcome.map { "\($0.record.photos) \($0.skipped.count)" } ?? (window.problem ?? "nothing")
            }
            try app.expect(outcome == "3 0", "imported: \(outcome)")
            try app.expect(
                try app.main { model in model.library.root(containing: scratch.folder) != nil },
                "the folder allowed is in Folders",
            )
            let rating = SidecarStore(locator: .besidePhotos).load(for: scratch.photo(scratch.names[0]))?.metadata?
                .rating
            try app.expect(rating == 5, "the first photo's rating: \(String(describing: rating))")
            app.covered(.action(.importFromLightroom), via: .menu)
        }

        static let importCatalog = Scenario(
            "library.lightroom",
            "File › Import from Lightroom Classic… reports a catalog of a folder the library doesn't have, Import adds "
                + "the folder and brings its ratings, picks, labels, keywords, title and collections into the photos' "
                + "sidecars, and Undo Import takes them back",
            claims: [.action(.importFromLightroom)],
        ) { app in
            let scratch = try SourcesScratch(
                app, photos: ["Shoot/LR_0001.jpg", "Shoot/LR_0002.jpg", "Shoot/LR_0003.jpg"],
            )
            let tag = String(scratch.folder.lastPathComponent.suffix(8))
            let catalog = try LightroomScratchCatalog.make(of: scratch.folder, tag: tag)
            defer {
                try? app.main { _ in LightroomWindowController.current?.close() }
                scratch.remove(app)
                try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent())
            }
            try app.main { model in model.showLibrary(.grid) }
            try app.choose(.importFromLightroom)
            try app.wait("the Lightroom Classic window", timeout: 30) { _ in
                LightroomWindowController.current?.window?.isVisible == true
            }
            // Choose…'s open panel can't be driven: the catalog it would pick is handed to the window.
            try app.inLightroomWindow { $0.choose(catalog: catalog) }
            try app.wait("the catalog's report", timeout: 60) { _ in
                LightroomWindowController.current?.isReported == true
            }
            let report = try app.inLightroomWindow { $0.report }
            try app.expect(
                report?.photos == 3 && report?.waiting == 3 && report?.roots.first?.state == .notInLibrary,
                "the report: \(report.map { $0.lines().joined(separator: " / ") } ?? "none")",
            )
            try app.expect(report?.smartMapped.count == 1 && report?.smartLeft.count == 1, "the smart collections")
            let sidecars = SidecarStore(locator: .besidePhotos)
            let photos = scratch.names.map(scratch.photo)
            try app.expect(photos.allSatisfy { sidecars.load(for: $0) == nil }, "the report wrote nothing")

            try app.clickInLightroomWindow("lightroom.import")
            try app.wait("the import", timeout: 180) { _ in LightroomWindowController.current?.isImported == true }
            let outcome = try app.inLightroomWindow { window in
                window.outcome.map { "\($0.record.photos) \($0.skipped.count)" } ?? (window.problem ?? "nothing")
            }
            try app.expect(outcome == "3 0", "imported: \(outcome)")
            try app.expect(
                try app.main { model in model.library.root(containing: scratch.folder) != nil },
                "the catalog's root folder is in Folders",
            )
            let first = sidecars.load(for: photos[0])?.metadata
            try app.expect(
                first?.rating == 5 && first?.flag == .pick && first?.label == .red && first?.title == "Tram \(tag)"
                    && first?.keywords == ["Places \(tag)/Lisbon"] && first?.collections == ["Lightroom \(tag)/Trip"],
                "the first photo's sidecar: \(String(describing: first))",
            )
            let second = sidecars.load(for: photos[1])?.metadata
            try app.expect(
                second?.flag == .reject && second?.customLabel == "Client \(tag)",
                "the second photo's sidecar: \(String(describing: second))",
            )
            try app.expect(sidecars.load(for: photos[2])?.metadata?.mark == true, "the Quick Collection is the mark")
            try app.wait("the import's keyword in the Keyword List", timeout: 30) { model in
                model.libraryPanels.refreshKeywords()
                return model.libraryPanels.keywordList?.keywords[KeywordPath("Places \(tag)/Lisbon")!]?.photos == 1
            }

            try app.wait("Undo Import", timeout: 30) { _ in
                LightroomWindowController.current?.button("lightroom.undo")?.enabled == true
            }
            try app.clickInLightroomWindow("lightroom.undo")
            try app.wait("the import taken back", timeout: 120) { _ in
                LightroomWindowController.current?.isUndone == true
            }
            for photo in photos {
                let metadata = sidecars.load(for: photo)?.metadata
                try app.expect(
                    metadata == nil || metadata?.isEmpty == true,
                    "\(photo.lastPathComponent)'s sidecar after Undo: \(String(describing: metadata))",
                )
            }
            app.covered(.action(.importFromLightroom), via: .menu)
        }
    }

    extension RunningApp {
        /// Runs `body` on the main thread with the Lightroom Classic window open now.
        @discardableResult
        func inLightroomWindow<T: Sendable>(_ body: @escaping @MainActor (LightroomWindowController) throws -> T)
            throws -> T {
            try main { _ in
                guard let window = LightroomWindowController.current else {
                    throw ScenarioFailure("The Lightroom Classic window isn't open")
                }
                return try body(window)
            }
        }

        /// Clicks the button carrying `identifier` in the Lightroom Classic window through the window, as the mouse
        /// does.
        func clickInLightroomWindow(_ identifier: String) throws {
            let location = try inLightroomWindow { controller -> NSPoint in
                guard let window = controller.window, let content = window.contentView,
                      let control = Self.lightroomView(identifier, in: content)
                else { throw ScenarioFailure("\(identifier) isn't in the Lightroom Classic window") }
                guard control.isHiddenOrHasHiddenAncestor == false, (control as? NSControl)?.isEnabled != false else {
                    throw ScenarioFailure("\(identifier) is hidden or disabled: \(controller.statusText)")
                }
                window.makeKeyAndOrderFront(nil)
                let frame = control.convert(control.bounds, to: nil)
                return NSPoint(x: frame.midX, y: frame.midY)
            }
            post { _ in
                guard let window = LightroomWindowController.current?.window else { return }
                let events = [NSEvent.EventType.leftMouseDown, .leftMouseUp].compactMap { type in
                    NSEvent.mouseEvent(
                        with: type, location: location, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1,
                    )
                }
                guard events.count == 2 else { return }
                // The button tracks the press, and takes the release from the queue as the mouse's.
                NSApp.postEvent(events[1], atStart: false)
                window.sendEvent(events[0])
            }
            pause(0.2)
        }

        @MainActor private static func lightroomView(_ identifier: String, in view: NSView) -> NSView? {
            if view.accessibilityIdentifier() == identifier {
                return view
            }
            for subview in view.subviews {
                if let found = lightroomView(identifier, in: subview) {
                    return found
                }
            }
            return nil
        }
    }

    /// The window's first screen (EDT-34), in a home the run makes of synthetic files only: Lightroom Classic's
    /// startup preferences naming the run's catalog, two presets and a profile in Camera Raw's Settings folder, a
    /// camera profile and a lens profile in the photographer's Camera Raw folder, and one of each in a Camera Raw
    /// folder of the run's own in place of the one Lightroom installs.
    extension LightroomScenarios {
        static let setup = Scenario(
            "library.lightroom-setup",
            "File › Import from Lightroom Classic… opens on what it found of Lightroom Classic in a home of the run's "
                + "own: the catalog Lightroom last used, the presets in Camera Raw's Settings folder and the camera and "
                + "lens profiles, read where they are; Import brings the presets in as recipes with their report, and "
                + "the catalog's Import… goes on to its report",
            claims: [.action(.importFromLightroom)],
        ) { app in
            let scratch = try SourcesScratch(
                app, photos: ["Shoot/LR_0001.jpg", "Shoot/LR_0002.jpg", "Shoot/LR_0003.jpg"],
            )
            let tag = String(scratch.folder.lastPathComponent.suffix(8))
            let catalog = try LightroomScratchCatalog.make(of: scratch.folder, tag: tag)
            let base = app.scratch.appending(path: "lightroom-home-\(tag)", directoryHint: .isDirectory)
            let locations = LightroomSetup.Locations(
                home: base.appending(path: "Home", directoryHint: .isDirectory),
                cameraRaw: base.appending(
                    path: "Library/Application Support/Adobe/CameraRaw",
                    directoryHint: .isDirectory,
                ),
                lensProfiles: base.appending(path: "Lens Profiles", directoryHint: .isDirectory),
            )
            try makeHome(locations, catalog: catalog, tag: tag)
            defer {
                try? app.main { model in
                    LightroomWindowController.current?.close()
                    LightroomWindowController.setupLocations = nil
                    for recipe in model.recipes.all where recipe.name.hasSuffix(tag) {
                        model.recipes.delete(recipe)
                    }
                }
                scratch.remove(app)
                try? FileManager.default.removeItem(at: catalog.deletingLastPathComponent())
                try? FileManager.default.removeItem(at: base)
            }
            try app.main { model in
                LightroomWindowController.setupLocations = locations
                model.showLibrary(.grid)
            }
            try app.choose(.importFromLightroom)
            try app.wait("the Lightroom Classic window", timeout: 30) { _ in
                LightroomWindowController.current?.window?.isVisible == true
            }
            try app.wait("what the first screen found", timeout: 30) { _ in
                LightroomWindowController.current?.setupFound != nil
            }
            let parts = ["catalog", "presets", "camera-profiles", "lens-profiles"]
            let shown = try app.inLightroomWindow { window in
                (window.isShowingSetup, parts.map { window.setupLine("lightroom.setup.\($0).found")?.text ?? "" })
            }
            try app.expect(shown.0, "the window opens on what it found")
            try app.expect(shown.1 == [
                "Lightroom Catalog.lrcat, the catalog Lightroom Classic last used",
                "2 presets in Camera Raw's Settings folder",
                "4 camera profiles: 2 where Lightroom Classic and Camera Raw install them and 2 in your Camera Raw folder",
                "2 lens profiles: 1 in Camera Raw's lens profiles and 1 in your Camera Raw lens profiles",
            ], "what the first screen says it found: \(shown.1)")
            let shots = app.runDirectory.appending(path: "shots", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
            try app.main { _ in
                guard let window = LightroomWindowController.current?.window else { return }
                Snapshot.capture(window, to: shots.appending(path: "lightroom-setup.png"))
            }

            try app.clickInLightroomWindow("lightroom.setup.presets.import")
            try app.wait("the presets imported", timeout: 60) { _ in
                LightroomWindowController.current?.presetsImported != nil
            }
            let names = try app.main { model in Set(model.recipes.all.filter { $0.group == "Lightroom" }.map(\.name)) }
            try app.expect(
                names.isSuperset(of: ["Warm \(tag)", "Cool \(tag)"]), "the presets as recipes: \(names.sorted())",
            )
            try app.wait("the presets' report over the window", timeout: 10) { _ in
                LightroomWindowController.current?.window?.attachedSheet != nil
            }
            // Return is the report's OK.
            try app.main { _ in
                _ = try LightroomWindowController.current?.window?.attachedSheet?
                    .performKeyEquivalent(with: Keyboard.event(KeyCombo(.character("\r"))))
            }
            try app.wait("the presets' report closed", timeout: 10) { _ in
                LightroomWindowController.current?.window?.attachedSheet == nil
            }

            try app.clickInLightroomWindow("lightroom.setup.catalog.import")
            try app.wait("the catalog's report", timeout: 60) { _ in
                LightroomWindowController.current?.isReported == true
            }
            let photos = try app.inLightroomWindow { $0.report?.photos }
            try app.expect(photos == 3, "the catalog's report: \(String(describing: photos)) photos")
            try app.clickInLightroomWindow("lightroom.back")
            try app.wait("the first screen again") { _ in LightroomWindowController.current?.isShowingSetup == true }
            app.covered(.action(.importFromLightroom), via: .menu)
        }

        /// The home's synthetic files: Lightroom Classic's startup preferences naming `catalog`, then presets and
        /// profiles, each named with `tag`.
        private static func makeHome(_ locations: LightroomSetup.Locations, catalog: URL, tag: String) throws {
            func write(_ data: Data, _ url: URL) throws {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                )
                try data.write(to: url)
            }
            func lua(_ text: String) -> String {
                text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            }
            let table = "recentLibraries = {\n\t\"\(lua(catalog.path))\",\n}\n"
            let preferences = "prefs = {\n\tlibraryToLoad20 = \"\(lua(catalog.path))\",\n\trecentLibraries20 = \""
                + lua(table).replacingOccurrences(of: "\n", with: "\\\n") + "\",\n}\n"
            try write(Data(preferences.utf8), locations.home.appending(
                path: "Library/Application Support/Adobe/Lightroom/Preferences/"
                    + "Lightroom Classic CC 7 Startup Preferences.agprefs",
            ))
            for name in ["Warm", "Cool"] {
                try write(Data(preset("\(name) \(tag)").utf8), locations.settings.appending(path: "\(name) \(tag).xmp"))
            }
            let look = SyntheticCameraProfiles.xmpLook(name: "Look \(tag)")
            let dcp = SyntheticCameraProfiles.dcp(
                name: "Profile \(tag)", camera: "SONY ILCE-7M3",
                colorMatrices: [[0.7, -0.1, -0.05, -0.4, 1.2, 0.2, -0.1, 0.2, 0.6]], illuminants: [21],
            )
            let lens = Data(LensProfileScenarios.profile(
                lens: "Lens \(tag)",
                prettyName: "Lens \(tag)",
                focalLength: 50,
            )
            .utf8)
            try write(look, locations.settings.appending(path: "Profiles/Look \(tag).xmp"))
            try write(dcp, locations.userCameraRaw.appending(path: "CameraProfiles/Profile \(tag).dcp"))
            try write(lens, locations.userCameraRaw.appending(path: "LensProfiles/Lens \(tag).lcp"))
            try write(look, locations.cameraRaw.appending(path: "Settings/Adobe/Profiles/Adobe Raw/Look \(tag).xmp"))
            try write(dcp, locations.cameraRaw.appending(path: "CameraProfiles/Adobe Standard/Profile \(tag).dcp"))
            try write(lens, locations.cameraRaw.appending(path: "LensProfiles/1.0/Scenario/Lens \(tag).lcp"))
        }

        /// A develop preset as Lightroom Classic writes one, made up.
        private static func preset(_ name: String) -> String {
            """
            <x:xmpmeta xmlns:x="adobe:ns:meta/">
             <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
              <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
               crs:PresetType="Normal" crs:UUID="\(UUID().uuidString)" crs:Version="15.0" crs:ProcessVersion="11.0"
               crs:Exposure2012="+0.50" crs:Contrast2012="+10">
               <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">\(name)</rdf:li></rdf:Alt></crs:Name>
              </rdf:Description>
             </rdf:RDF>
            </x:xmpmeta>
            """
        }
    }
#endif
