#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampDocument
    @_spi(Harness) import RedlampLibrary
    @_spi(Harness) import RedlampUI

    /// Import from Apple Photos (LIB-54), on a simulated Photos library the run makes of copies of its raws: nothing a
    /// run does can be given access to Photos, and Photos is never read.
    enum ApplePhotosScenarios {
        static let all: [Scenario] = [importAlbums]

        static let importAlbums = Scenario(
            "library.apple-photos",
            "File › Import from Apple Photos… asks for access with Continue, chooses albums with their boxes, Review "
                + "reports what comes across and what stays in Photos, Import copies the photos named by their "
                + "albums with the favourite as a pick and the albums as collections in their sidecars, and Undo "
                + "Import takes the copies back",
            claims: [.action(.importFromApplePhotos)],
        ) { app in
            try app.openWorking()
            let photos = try ApplePhotosScratch(app)
            let trash = TrashedFiles()
            defer {
                trash.empty()
                photos.remove(app)
            }
            try photos.simulate(
                app,
                [0: ["album-trip", "album-selects"], 1: ["album-trip"], 2: ["album-selects"]],
                access: "notDetermined",
            )
            try app.main { model in model.showLibrary(.grid) }
            try app.choose(.importFromApplePhotos)
            try app.wait("the Apple Photos window", timeout: 30) { _ in
                ApplePhotosWindowController.current?.window?.isVisible == true
            }
            try app.waitInPhotosWindow("access") { $0.phase == "access" }
            let heading = try app.inPhotosWindow { $0.heading }
            try app.expect(heading == "Allow Redlamp to read Photos", "the first page: \(heading)")
            try app.clickInPhotosWindow("photos.allow")
            try app.waitInPhotosWindow("the albums") { $0.phase == "choosing" }
            let chosen = try app.inPhotosWindow { $0.chosen }
            try app.expect(chosen == ["album-trip", "album-selects"], "the albums chosen to begin with: \(chosen)")
            try app.clickInPhotosWindow("photos.album.album-selects")
            try app.waitInPhotosWindow("E2E Selects let go") { $0.chosen == ["album-trip"] }
            try app.clickInPhotosWindow("photos.album.album-selects")
            try app.waitInPhotosWindow("E2E Selects chosen again") { $0.chosen == ["album-trip", "album-selects"] }
            // To's destination panel can't be driven: the folder it would give is handed to the window.
            try app.inPhotosWindow { $0.prepare(destination: photos.destination, folders: "{album}", names: "{name}") }

            try app.clickInPhotosWindow("photos.review")
            try app.waitInPhotosWindow("the report", timeout: 60) { $0.phase == "reviewing" }
            let report = try app.inPhotosWindow { window in window.report.map { "\($0.photos) \($0.videosLeft)" } }
            try app.expect(report == "3 1", "photos to import and videos left: \(report ?? "no report")")
            let lines = try app.inPhotosWindow { $0.lines }
            try app.expect(
                lines.contains("1 video: Redlamp edits photos") && lines.contains("1 favourite, flagged as picks"),
                "the report: \(lines)",
            )
            try app.clickInPhotosWindow("photos.importPhotos")
            try app.waitInPhotosWindow("the import", timeout: 180) { $0.phase == "imported" }
            let (imported, problem) = try app.inPhotosWindow { ($0.outcome?.imported ?? 0, $0.problem ?? "") }
            try app.expect(imported == 3, "imported: \(imported) \(problem)")
            let first = photos.copy(0, in: "E2E Trip")
            for copy in [first, photos.copy(1, in: "E2E Trip"), photos.copy(2, in: "E2E Selects")] {
                try app.expect(FileManager.default.fileExists(atPath: copy.path), "\(copy.path) copied")
            }
            let sidecar = SidecarStore(locator: .besidePhotos).load(for: first)?.metadata
            try app.expect(
                sidecar?.flag == .pick && sidecar?.collections == ["E2E/E2E Trip", "E2E Selects"]
                    && sidecar?.applePhotos?.id == photos.asset(0),
                "the first photo's sidecar: \(String(describing: sidecar))",
            )

            try app.clickInPhotosWindow("photos.undo")
            try app.waitInPhotosWindow("the import taken back", timeout: 120) { $0.phase == "undone" }
            try trash.add(app.inPhotosWindow { $0.trashed })
            try app.expect(!FileManager.default.fileExists(atPath: first.path), "the copies taken back")
            try app.clickInPhotosWindow("photos.done")
            try app.waitInPhotosWindow("the albums again") { $0.phase == "choosing" }
            app.covered(.action(.importFromApplePhotos), via: .menu)
        }
    }

    /// A simulated Photos library over copies of the run's raws, each with a content key of its own (`ImportScratch`),
    /// in an album, E2E Trip, inside a folder, E2E, and an album beside it, E2E Selects; and a destination.
    struct ApplePhotosScratch: Sendable {
        let scratch: ImportScratch
        /// The run's own, in its assets' local identifiers: an earlier scenario's record never names them.
        let tag = UUID().uuidString.prefix(8)

        init(_ app: RunningApp) throws {
            scratch = try ImportScratch(app, photos: 3)
        }

        var destination: URL {
            scratch.destination
        }

        func asset(_ number: Int) -> String {
            "E2E\(number)-\(tag)-4000-8000-000000000000/L0/001"
        }

        /// Where the import copies photo `number` in `album`, as `{album}/{name}` names it.
        func copy(_ number: Int, in album: String) -> URL {
            destination.appending(path: album).appending(path: scratch.names[number])
        }

        /// Reads Photos as a library of the photos `albums` names, by number, each in the albums given, the first a
        /// favourite and the third only in iCloud, with a video in E2E Trip; Redlamp's access as `access` says.
        func simulate(_ app: RunningApp, _ albums: [Int: [String]], access: String = "authorized") throws {
            var assets: [[String: Any]] = albums.keys.sorted().map { number in
                [
                    "id": asset(number), "favorite": number == 0, "albums": albums[number] ?? [],
                    "resources": [[
                        "kind": "photo", "name": scratch.names[number], "file": "Card/" + scratch.names[number],
                        "inCloud": number == 2,
                    ]],
                ]
            }
            assets.append(["id": "E2E-video-\(tag)", "mediaType": "video", "albums": ["album-trip"], "resources": [
                ["kind": "other", "name": "IMG_0099.MOV", "type": "com.apple.quicktime-movie"],
            ]])
            let manifest: [String: Any] = [
                "format": SimulatedPhotosLibrary.format, "version": 1, "access": access, "grants": "authorized",
                "collections": [
                    ["id": "folder-e2e", "title": "E2E", "kind": "folder"],
                    ["id": "album-trip", "title": "E2E Trip", "kind": "album", "parent": "folder-e2e"],
                    ["id": "album-selects", "title": "E2E Selects", "kind": "album"],
                ],
                "assets": assets,
            ]
            let url = scratch.root.appending(path: "manifest-\(UUID().uuidString.prefix(8)).json")
            try JSONSerialization.data(withJSONObject: manifest).write(to: url)
            let library = try SimulatedPhotosLibrary(manifest: url)
            try app.main { model in model.simulateApplePhotos(library) }
        }

        /// An import of the albums `albums` names through the Apple Photos window, which is closed after it.
        func importThroughWindow(_ app: RunningApp, _ albums: [Int: [String]]) throws {
            try simulate(app, albums)
            try app.choose(.importFromApplePhotos)
            try app.waitInPhotosWindow("the albums", timeout: 30) { $0.phase == "choosing" }
            try app.inPhotosWindow { $0.prepare(destination: destination, folders: "{album}", names: "{name}") }
            try app.clickInPhotosWindow("photos.review")
            try app.waitInPhotosWindow("the report", timeout: 60) { $0.phase == "reviewing" }
            try app.clickInPhotosWindow("photos.importPhotos")
            try app.waitInPhotosWindow("the import", timeout: 180) { $0.phase == "imported" }
            try app.main { _ in ApplePhotosWindowController.current?.close() }
            try app.wait("the Apple Photos window closed") { _ in ApplePhotosWindowController.current == nil }
        }

        /// Closes the window, reads Photos again, and takes the copies and the scratch away.
        func remove(_ app: RunningApp) {
            try? app.main { model in
                ApplePhotosWindowController.current?.close()
                model.simulateApplePhotos(nil)
            }
            scratch.remove(app)
        }
    }

    extension RunningApp {
        /// Runs `body` on the main thread with the Apple Photos window open now.
        @discardableResult
        func inPhotosWindow<T: Sendable>(_ body: @escaping @MainActor (ApplePhotosWindowController) throws -> T)
            throws -> T {
            try main { _ in
                guard let window = ApplePhotosWindowController.current else {
                    throw ScenarioFailure("The Apple Photos window isn't open")
                }
                return try body(window)
            }
        }

        func waitInPhotosWindow(
            _ what: String, timeout: Double = 30,
            _ condition: @escaping @MainActor (ApplePhotosWindowController) -> Bool,
        ) throws {
            do {
                try wait(what, timeout: timeout) { _ in ApplePhotosWindowController.current.map(condition) ?? false }
            } catch {
                let state = (try? inPhotosWindow { "\($0.phase): \($0.heading); \($0.problem ?? $0.statusText)" })
                    ?? "no window"
                throw ScenarioFailure("\(error) (\(state))")
            }
        }

        /// Clicks the button or box carrying `identifier` in the Apple Photos window open now, as the mouse does. While
        /// the app isn't active or the window isn't key, a press goes nowhere, so there the control is clicked as the
        /// keyboard clicks it, as `click(_:inWindowTitled:)` does.
        func clickInPhotosWindow(_ identifier: String) throws {
            try waitInPhotosWindow("\(identifier) shown and enabled") { window in
                window.control(identifier).map { $0.shown && $0.enabled } ?? false
            }
            let location = try inPhotosWindow { controller -> NSPoint? in
                guard let window = controller.window, let content = window.contentView,
                      let control = Views.shown(identifier, in: window) as? NSControl
                else { throw ScenarioFailure("\(identifier) isn't in the Apple Photos window") }
                guard NSApp.isActive, window.isKeyWindow else {
                    control.performClick(nil)
                    return nil
                }
                content.layoutSubtreeIfNeeded()
                let frame = control.convert(control.bounds, to: nil)
                return NSPoint(x: frame.midX, y: frame.midY)
            }
            if let location {
                post { _ in
                    guard let window = ApplePhotosWindowController.current?.window else { return }
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
            }
            pause(0.2)
        }
    }
#endif
