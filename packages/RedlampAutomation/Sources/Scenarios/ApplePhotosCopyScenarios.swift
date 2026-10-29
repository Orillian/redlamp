#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampDocument
    import RedlampEngineAPI
    @_spi(Harness) import RedlampLibrary
    @_spi(Harness) import RedlampUI

    /// Copy to Folder… for photos kept in Apple Photos (LIB-63), on the simulated Photos library `ApplePhotosScratch`
    /// makes: an album kept in place through Add Albums from Apple Photos…, photos chosen in it in the Apple Photos
    /// section copied with their edits, each copy then standing in for its photo, Undo Copy, and the album row's own
    /// Copy to Folder….
    enum ApplePhotosCopyScenarios {
        static let all: [Scenario] = [copyToFolder]

        static let copyToFolder = Scenario(
            "library.apple-photos-copy-to-folder",
            "Photos selected in an album kept in Apple Photos through Add Albums are copied by Photo › Copy to "
                + "Folder… with their edits, each copy then listed in its photo's place, and Undo Copy gives the "
                + "photos back with their own; a photo copied from its menu in the grid stays copied, and the album "
                + "row's Copy to Folder… copies the rest into a folder of the album's title",
            claims: [.action(.copyToFolder), .action(.importFromApplePhotos)],
        ) { app in
            try app.openWorking()
            let photos = try ApplePhotosScratch(app)
            let trash = TrashedFiles()
            defer {
                try? app.main { model in
                    ApplePhotosCopyWindowController.current?.close()
                    ApplePhotosRemoval.answer = true
                    model.librarySources.removeApplePhotos("album-selects")
                }
                try? app.wait("E2E Selects no longer kept", timeout: 30) { !$0.librarySources.keepsApplePhotos }
                try? app.main { _ in ApplePhotosRemoval.answer = nil }
                trash.empty()
                photos.remove(app)
            }
            try photos.simulate(app, [0: ["album-selects"], 1: ["album-selects"], 2: ["album-selects"]])
            try app.main { model in model.showLibrary(.grid) }

            // Add Albums keeps E2E Selects in Photos, and the grid shows it.
            try app.choose(.importFromApplePhotos)
            try app.waitInPhotosWindow("the albums", timeout: 30) { $0.phase == "choosing" && $0.way == "keep" }
            try app.clickInPhotosWindow("photos.album.album-selects")
            try app.waitInPhotosWindow("E2E Selects chosen") { $0.chosen == ["album-selects"] }
            try app.clickInPhotosWindow("photos.addAlbums")
            try app.wait("the Apple Photos window closed") { _ in
                ApplePhotosWindowController.current?.window?.isVisible != true
            }
            let names = photos.scratch.names
            try app.wait("E2E Selects in the grid", timeout: 60) { model in
                model.librarySources.shown == .applePhotos("album-selects") && !model.librarySources.isListing
                    && Set(model.items.map(\.name)) == Set(names)
            }
            let urls = try app.main { model -> [URL] in
                try names.map { name -> URL in
                    guard let item = model.items.first(where: { $0.name == name }) else {
                        throw ScenarioFailure("\(name) isn't listed in E2E Selects")
                    }
                    return item.url
                }
            }

            // The first photo's edit, made in Develop: black and white.
            try app.click(.identifier("grid.\(names[0])"))
            try app.wait("\(names[0]) alone") { $0.selectedPhotos == [urls[0]] }
            try app.press(.developModule)
            try app.wait("\(names[0]) open in Develop", timeout: 60) { model in
                model.module == .develop && model.info.map { Self.paths([$0.url]) } == Self.paths([urls[0]])
            }
            try app.press(.toggleBlackAndWhite)
            try app.wait("black & white") { $0.treatment == .blackAndWhite }
            try app.press(.gridView)
            // The grid marks the photo edited once its edit is on disk, which waits a moment after the last change.
            try app.wait("E2E Selects in the grid again, the edit saved", timeout: 30) { model in
                model.module == .library && model.librarySources.shown == .applePhotos("album-selects")
                    && Self.listsEdited(urls[0], in: model)
            }

            // Photo › Copy to Folder… copies the two selected, the first with its edit, and the copies stand in.
            try app.click(.identifier("grid.\(names[0])"))
            try app.click(.identifier("grid.\(names[1])"), modifiers: .command)
            try app.wait("the first two selected") { Set($0.selectedPhotos) == [urls[0], urls[1]] }
            try app.choose(.copyToFolder)
            try app.waitInCopyWindow("the two counted", timeout: 30) { $0.phase == "choosing" }
            let asked = try app.inCopyWindow { (Set($0.assets), $0.heading) }
            try app.expect(
                asked.0 == [photos.asset(0), photos.asset(1)] && asked.1 == "2 photos kept in Apple Photos",
                "what's chosen: \(asked)",
            )
            // To's destination panel can't be driven: the folder it would give is handed to the window.
            try app.inCopyWindow { $0.prepare(destination: photos.destination, folders: "", names: "{name}") }
            try app.clickInCopyWindow("copy")
            try app.waitInCopyWindow("the copy", timeout: 120) { $0.phase == "copied" }
            let copied = try app.inCopyWindow { $0.outcome?.imported ?? 0 }
            try app.expect(copied == 2, "copied: \(copied)")
            let copies = names.prefix(2).map { photos.destination.appending(path: $0) }
            for copy in copies {
                try app.expect(FileManager.default.fileExists(atPath: copy.path), "\(copy.path) copied")
            }
            let carried = SidecarStore(locator: .besidePhotos).load(for: copies[0])
            try app.expect(
                carried?.recipe.treatment == .blackAndWhite && carried?.metadata?.applePhotos?.id == photos.asset(0),
                "the first copy's sidecar: \(carried.map { "\($0.recipe.treatment)" } ?? "none"), "
                    + (carried?.metadata?.applePhotos?.id ?? "no asset"),
            )
            try app.wait("the copies in the photos' places, the first with its edit", timeout: 30) { model in
                Self.listed(model) == Self.paths(copies + [urls[2]])
                    && Self.listsEdited(copies[0], in: model)
            }

            try app.clickInCopyWindow("undo")
            try app.waitInCopyWindow("the copy taken back", timeout: 120) { $0.phase == "undone" }
            try trash.add(app.inCopyWindow { $0.trashed })
            try app.expect(
                copies.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "the copies in the Trash",
            )
            try app.wait("the photos back from Photos, the first with its own edit", timeout: 30) { model in
                Self.listed(model) == Self.paths(urls) && Self.listsEdited(urls[0], in: model)
            }
            try app.clickInCopyWindow("done")
            try app.wait("the Copy to Folder window closed") { _ in ApplePhotosCopyWindowController.current == nil }

            // The first photo copied again from its menu in the grid, and left copied.
            try app.click(.identifier("grid.\(names[0])"))
            try app.wait("\(names[0]) alone again") { $0.selectedPhotos == [urls[0]] }
            try app.rightClick(.identifier("grid.\(names[0])"), choosing: ShortcutAction.copyToFolder.title)
            try app.waitInCopyWindow("the first counted", timeout: 30) { window in
                window.phase == "choosing" && window.assets == [photos.asset(0)]
            }
            try app.inCopyWindow { $0.prepare(destination: photos.destination, folders: "", names: "{name}") }
            try app.clickInCopyWindow("copy")
            try app.waitInCopyWindow("the first copied", timeout: 120) { window in
                window.phase == "copied" && window.outcome?.imported == 1
            }
            app.covered(.action(.copyToFolder), via: .mouse)
            try app.clickInCopyWindow("done")
            try app.wait("the Copy to Folder window closed again") { _ in
                ApplePhotosCopyWindowController.current == nil
            }
            try app.wait("the first photo's copy in its place", timeout: 30) { model in
                Self.listed(model) == Self.paths([copies[0], urls[1], urls[2]])
            }

            // The album row's Copy to Folder… copies the rest, the one only in iCloud downloaded, into {album}.
            try app.rightClickSourceRow("apple-photos.album-selects", choosing: ShortcutAction.copyToFolder.title)
            try app.waitInCopyWindow("the album counted", timeout: 30) { $0.phase == "choosing" }
            let album = try app.inCopyWindow { (Set($0.assets), $0.heading) }
            try app.expect(
                album.0 == [photos.asset(1), photos.asset(2)]
                    && album.1 == "“E2E Selects”: 2 photos kept in Apple Photos",
                "what the album's Copy to Folder… chose: \(album)",
            )
            try app.inCopyWindow { $0.prepare(destination: photos.destination, folders: "{album}", names: "{name}") }
            try app.clickInCopyWindow("copy")
            try app.waitInCopyWindow("the album copied", timeout: 180) { window in
                window.phase == "copied" && window.outcome?.imported == 2
            }
            let rest = [1, 2].map { photos.copy($0, in: "E2E Selects") }
            for copy in rest {
                try app.expect(FileManager.default.fileExists(atPath: copy.path), "\(copy.path) copied")
            }
            try app.wait("every copy in its photo's place", timeout: 30) { model in
                Self.listed(model) == Self.paths([copies[0]] + rest)
            }
            try app.clickInCopyWindow("undo")
            try app.waitInCopyWindow("the album's copy taken back", timeout: 120) { $0.phase == "undone" }
            try trash.add(app.inCopyWindow { $0.trashed })
            try app.wait("the rest back from Photos", timeout: 30) { model in
                Self.listed(model) == Self.paths([copies[0], urls[1], urls[2]])
            }
            try app.clickInCopyWindow("done")
        }

        /// The photos the grid lists, by path.
        @MainActor static func listed(_ model: EditorModel) -> Set<String> {
            paths(model.items.map(\.url))
        }

        static func paths(_ urls: [URL]) -> Set<String> {
            Set(urls.map(\.standardizedFileURL.path))
        }

        /// Whether the grid lists the photo at `url` with an edit.
        @MainActor static func listsEdited(_ url: URL, in model: EditorModel) -> Bool {
            model.items.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }?.hasEdits == true
        }
    }

    extension RunningApp {
        /// Runs `body` on the main thread with the Copy to Folder window open now.
        @discardableResult
        func inCopyWindow<T: Sendable>(_ body: @escaping @MainActor (ApplePhotosCopyWindowController) throws -> T)
            throws -> T {
            try main { _ in
                guard let window = ApplePhotosCopyWindowController.current else {
                    throw ScenarioFailure("The Copy to Folder window isn't open")
                }
                return try body(window)
            }
        }

        func waitInCopyWindow(
            _ what: String, timeout: Double = 30,
            _ condition: @escaping @MainActor (ApplePhotosCopyWindowController) -> Bool,
        ) throws {
            do {
                try wait(what, timeout: timeout) { _ in
                    ApplePhotosCopyWindowController.current.map(condition) ?? false
                }
            } catch {
                let state = (try? inCopyWindow { window in
                    "\(window.phase): \(window.heading); \(window.problem ?? window.barNote)"
                }) ?? "no window"
                throw ScenarioFailure("\(error) (\(state))")
            }
        }

        /// Clicks the bottom bar's button `kind` names (`copy`, `undo`, `done`…) in the Copy to Folder window open
        /// now, once it's shown and enabled, as `click(_:inWindowTitled:)` clicks a control.
        func clickInCopyWindow(_ kind: String) throws {
            let identifier = "copy." + kind
            try waitInCopyWindow("\(identifier) shown and enabled") { window in
                window.control(identifier).map { $0.shown && $0.enabled } ?? false
            }
            try click(identifier, inWindowTitled: ApplePhotosCopyWindowController.title)
        }
    }
#endif
