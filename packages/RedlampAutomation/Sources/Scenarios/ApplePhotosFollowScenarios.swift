#if DEBUG || REDLAMP_PROFILING
    import AppKit
    @_spi(Harness) import RedlampUI

    /// The albums imports from Apple Photos follow (LIB-55), on the simulated Photos library `ApplePhotosScratch`
    /// makes: the Library panel's From Apple Photos and its Import, and Settings › Library's automatic import.
    enum ApplePhotosFollowScenarios {
        static let all: [Scenario] = [followedAlbums, automatic]

        static let followedAlbums = Scenario(
            "library.apple-photos-follow",
            "After an import from Apple Photos, the Library panel's From Apple Photos shows the new photos that arrive "
                + "in its albums with their count, its Import brings them with the import's settings in the Apple "
                + "Photos window, and it goes once there are none",
            claims: [.feature("library.library-panel")],
        ) { app in
            try app.openWorking()
            let photos = try ApplePhotosScratch(app)
            defer { photos.remove(app) }
            try photos.importThroughWindow(app, [0: ["album-trip"]])
            try photos.simulate(app, [0: ["album-trip"], 1: ["album-trip"], 2: ["album-trip"]])
            try app.wait("the new photos counted", timeout: 30) { $0.applePhotosNewPhotos == 2 }
            try app.main { model in
                Views.editorWindow?.makeKeyAndOrderFront(nil)
                model.showLibrary(.grid)
            }
            try app.waitForSourceRowInPlace("sources.apple-photos")
            try app.clickControl("sources.apple-photos.import")
            try app.waitInPhotosWindow("the new photos imported", timeout: 180) { window in
                window.phase == "imported" && window.outcome?.imported == 2
            }
            for number in [1, 2] {
                let copy = photos.copy(number, in: "E2E Trip")
                try app.expect(FileManager.default.fileExists(atPath: copy.path), "\(copy.path) copied")
            }
            try app.wait("nothing new left", timeout: 30) { $0.applePhotosNewPhotos == 0 }
            try app.wait("From Apple Photos gone") { _ in Self.offered() == nil }
            app.covered(.feature("library.library-panel"), via: .mouse)
        }

        static let automatic = Scenario(
            "library.apple-photos-automatic",
            "Settings › Library's Import new photos from followed albums automatically, off to begin with, imports the "
                + "new photos in the albums an import from Apple Photos follows without asking once Photos settles",
            claims: [.feature("workspace.settings")],
        ) { app in
            try app.openWorking()
            let photos = try ApplePhotosScratch(app)
            let delay = try app.main { _ in ApplePhotosFollower.automaticDelay }
            defer {
                try? app.main { _ in
                    ApplePhotosPreferences.shared.importsAutomatically = false
                    ApplePhotosFollower.automaticDelay = delay
                }
                photos.remove(app)
            }
            try photos.importThroughWindow(app, [0: ["album-trip"]])
            try app.main { _ in ApplePhotosFollower.automaticDelay = .seconds(1) }
            try app.expect(
                try app.main { _ in !ApplePhotosPreferences.shared.importsAutomatically }, "it's off to begin with",
            )
            try app.wait("the library's settings", timeout: 30) { $0.library.service?.xmpSettings != nil }
            try app.openSettings(tab: "Library")
            try app.clickInSettings("settings.library.apple-photos.automatic", fallback: 2)
            try app.wait("importing automatically on") { _ in ApplePhotosPreferences.shared.importsAutomatically }
            try app.closeSettings()

            try photos.simulate(app, [0: ["album-trip"], 1: ["album-trip"]])
            try app.wait("the new photo imported without asking", timeout: 120) { model in
                model.applePhotosNewPhotos == 0
                    && FileManager.default.fileExists(atPath: photos.copy(1, in: "E2E Trip").path)
            }
            try app.expect(
                try app.main { _ in ApplePhotosWindowController.current == nil }, "no window opened for it",
            )
            app.covered(.feature("workspace.settings"), via: .mouse)
        }

        /// From Apple Photos' count, while the Library panel shows it.
        @MainActor static func offered() -> String? {
            Views.editorWindow.flatMap { Views.shown("sources.apple-photos", in: $0) }?.accessibilityLabel()
        }
    }
#endif
