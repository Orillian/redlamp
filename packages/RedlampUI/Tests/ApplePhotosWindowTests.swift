import AppKit
import Foundation
import RedlampDocument
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// File › Import from Apple Photos… (LIB-54) on a simulated Photos library: access asked for once and explained when
/// there's none, the albums chosen with their folders, the report, the import and Undo Import.
@MainActor
@Suite(.serialized)
struct ApplePhotosWindowTests {
    /// A Photos library of small JPEGs: Selects, the folder Trips with Lisbon and Porto, a smart album and a shared
    /// one, over a favourite in Selects and Lisbon, a photo in Porto, a video in Lisbon and a shared album's copy;
    /// `extra` more photos in `album`, those `dropping` names gone; and access as `access` says.
    static func manifest(
        in sandbox: SourcesSandbox, access: String = "authorized", extra: Int = 0, into album: String = "album-lisbon",
        dropping: Set<String> = [],
    ) throws -> URL {
        let folder = sandbox.base.appending(path: "Photos Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func photo(_ number: Int, albums: [String], extra: [String: Any] = [:]) throws -> [String: Any] {
            let name = String(format: "IMG_%04d.JPG", number)
            let file = folder.appending(path: name)
            if !FileManager.default.fileExists(atPath: file.path) {
                try SourcesSandbox.jpeg(number: 40 + number).write(to: file)
            }
            return ["id": "asset-\(number)", "albums": albums, "resources": [
                ["kind": "photo", "name": name, "file": name],
            ]].merging(extra) { $1 }
        }
        var assets = try [
            photo(1, albums: ["album-selects", "album-lisbon"], extra: ["favorite": true]),
            photo(2, albums: ["album-porto"]),
            ["id": "asset-video", "mediaType": "video", "albums": ["album-lisbon"], "resources": [
                ["kind": "other", "name": "IMG_0009.MOV", "type": "com.apple.quicktime-movie"],
            ]],
            photo(3, albums: ["shared-family"], extra: ["source": "cloudShared"]),
        ]
        for number in 0 ..< extra {
            try assets.append(photo(10 + number, albums: [album]))
        }
        assets.removeAll { dropping.contains($0["id"] as? String ?? "") }
        let object: [String: Any] = [
            "format": SimulatedPhotosLibrary.format, "version": 1, "access": access, "grants": "authorized",
            "collections": [
                ["id": "album-selects", "title": "Selects", "kind": "album"],
                ["id": "folder-trips", "title": "Trips", "kind": "folder"],
                ["id": "album-lisbon", "title": "Lisbon", "kind": "album", "parent": "folder-trips"],
                ["id": "album-porto", "title": "Porto", "kind": "album", "parent": "folder-trips"],
                ["id": "smart-favourites", "title": "Favourites", "kind": "smartAlbum"],
                ["id": "shared-family", "title": "Family", "kind": "sharedAlbum"],
            ],
            "assets": assets,
        ]
        let url = folder.appending(path: "manifest-\(UUID().uuidString.prefix(8)).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        return url
    }

    static func preferences() -> ImportPreferences {
        let suite = "app.redlamp.tests.apple-photos.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return ImportPreferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// The window over `photos`, for the library `model` has open, To's settings its own.
    static func window(
        _ photos: some ApplePhotosLibrary, model: EditorModel,
    ) async -> ApplePhotosWindowController {
        let library = await ImportActions.library(of: model)
        let importing = ApplePhotosImportModel(
            photos: photos, library: library, editor: model, preferences: preferences(),
        )
        let window = ApplePhotosWindowController(model: importing)
        importing.start()
        window.showWindow(nil)
        return window
    }

    private func click(_ identifier: String, in window: ApplePhotosWindowController) throws {
        let content = try #require(window.window?.contentView)
        let button = try #require(Self.button(identifier, in: content), "\(identifier)")
        #expect(!button.isHiddenOrHasHiddenAncestor && button.isEnabled, "\(identifier) shown and enabled")
        button.performClick(nil)
    }

    static func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityIdentifier() == identifier {
            return button
        }
        return view.subviews.lazy.compactMap { button(identifier, in: $0) }.first
    }

    private static func emptyTrash(_ undone: ApplePhotosImport.Undone?) {
        for file in undone?.rollbacks.flatMap(\.trashed) ?? [] {
            try? FileManager.default.removeItem(atPath: file.to)
        }
    }

    @Test func `the window asks for access once, and says why and where to give it when there's none`() async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()

        let asking = try await Self.window(SimulatedPhotosLibrary(manifest: Self.manifest(
            in: sandbox, access: "notDetermined",
        )), model: model)
        defer { asking.close() }
        try await sandbox.eventually { asking.phase == "access" }
        #expect(asking.heading == "Allow Redlamp to read Photos")
        #expect(asking.lines.first?.hasSuffix("It only reads your Photos library and never changes it.") == true)
        #expect(asking.control("photos.allow")?.title == "Continue" && asking.control("photos.allow")?.shown == true)
        try click("photos.allow", in: asking)
        try await sandbox.eventually { asking.phase == "choosing" }
        #expect(asking.access == .authorized && asking.control("photos.allow")?.shown == false)

        var opened = 0
        let opening = ApplePhotosSource.openPrivacySettings
        ApplePhotosWindowController.catchOpeningSettings { opened += 1 }
        defer { ApplePhotosSource.openPrivacySettings = opening }
        let headings: [(String, String)] = [
            ("denied", "Redlamp isn’t allowed to read Photos"),
            ("restricted", "Photos is restricted on this Mac"),
            ("limited", "Redlamp can read only some of your photos"),
        ]
        for (access, heading) in headings {
            let window = try await Self.window(SimulatedPhotosLibrary(manifest: Self.manifest(
                in: sandbox, access: access,
            )), model: model)
            defer { window.close() }
            try await sandbox.eventually { window.phase == "access" }
            #expect(window.heading == heading, "\(access)")
            #expect(window.lines.contains { $0.contains("System Settings › Privacy & Security › Photos") }, "\(access)")
            #expect(window.control("photos.openSettings")?.title == "Open System Settings")
            try click("photos.openSettings", in: window)
        }
        #expect(opened == 3)
        #expect(ApplePhotosImportModel.words(for: .limited) == "limited to some photos")
    }

    @Test func `albums are chosen with their folders, smart and shared albums apart, and To's example follows them`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let window = try await Self.window(SimulatedPhotosLibrary(manifest: Self.manifest(in: sandbox)), model: model)
        defer { window.close() }
        try await sandbox.eventually { window.phase == "choosing" }
        try await sandbox.eventually {
            window.window?.contentView?.layoutSubtreeIfNeeded()
            return window.control("photos.album.shared-family") != nil
        }
        #expect(window.chosen == ["album-selects", "album-lisbon", "album-porto"], "every album, none smart or shared")
        let screen = window.model.screen
        #expect(screen.groups.map(\.title) == ["Albums", "Smart Albums", "Shared Albums"])
        #expect(screen.groups[0].albums.map(\.title) == ["Selects", "Trips", "Lisbon", "Porto"])
        #expect(screen.groups[0].albums.map(\.depth) == [0, 0, 1, 1])
        #expect(screen.groups[0].albums[1].count == 3, "a folder counts its albums")
        #expect(screen.groups[2].note?.hasPrefix("Reduced copies, not the originals") == true)
        #expect(window.control("photos.album.shared-family")?.on == .off)
        #expect(window.control("photos.album.folder-trips")?.on == .on)
        #expect(screen.chosenLine == "3 albums chosen, about 4 photos.")

        try click("photos.album.album-lisbon", in: window)
        #expect(window.chosen == ["album-selects", "album-porto"])
        #expect(window.control("photos.album.folder-trips")?.on == .mixed)
        try click("photos.album.folder-trips", in: window)
        #expect(window.chosen == ["album-selects", "album-lisbon", "album-porto"], "a folder checks its albums")
        try click("photos.album.folder-trips", in: window)
        #expect(window.chosen == ["album-selects"])
        try click("photos.album.shared-family", in: window)
        #expect(window.chosen == ["album-selects", "shared-family"])
        try click("photos.hidden", in: window)
        try click("photos.follow", in: window)
        #expect(window.model.settings.includesHidden && !window.model.settings.follows)
        #expect(window.model.settings.collections == ["album-selects", "shared-family"])

        window.prepare(destination: sandbox.base.appending(path: "Pictures"), folders: "{album}", names: "{name}")
        await window.exampled()
        #expect(window.example == "Selects/IMG_0001.HEIC", "\(window.example ?? "none")")
        #expect(window.control("import.eject-after") == nil, "no Card section")
        #expect(ShortcutAction.importFromApplePhotos.title == "Import from Apple Photos…")
        #expect(ShortcutAction.importFromApplePhotos.category == .file)
    }

    @Test func `Review reports what comes across and stays, Import copies the photos, and Undo Import takes them back`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let destination = sandbox.base.appending(path: "Pictures", directoryHint: .isDirectory)
        let window = try await Self.window(SimulatedPhotosLibrary(manifest: Self.manifest(in: sandbox)), model: model)
        defer { window.close() }
        try await sandbox.eventually { window.phase == "choosing" }
        window.prepare(destination: destination, folders: "{album}", names: "{name}")
        try click("photos.review", in: window)
        try await sandbox.eventually { window.phase == "reviewing" }
        let report = try #require(window.report)
        #expect(report.photos == 2 && report.videosLeft == 1 && report.favorites == 1)
        #expect(window.heading == "2 photos from 3 albums")
        let sections = window.model.screen.sections
        #expect(sections.map(\.title) == ["Comes across", "Stays in Photos", "Fields"])
        #expect(sections[0].lines.contains("1 favourite, flagged as picks"))
        #expect(sections[1].lines.contains("1 video: Redlamp edits photos"))
        #expect(sections[2].lines == [
            "This Mac gives favourites, dates, original names, albums and places.",
            "macOS 27 would add ratings, captions and keywords.",
        ])
        #expect(window.control("photos.importPhotos")?.title == "Import 2 Photos")
        #expect(window.control("photos.back")?.shown == true)

        try click("photos.importPhotos", in: window)
        try await sandbox.eventually(seconds: 60) { window.phase == "imported" }
        #expect(window.problem == nil, "\(window.problem ?? "")")
        #expect(window.outcome?.imported == 2 && window.outcome?.state == .finished)
        #expect(window.heading.hasPrefix("Imported 2 photos from Apple Photos"))
        let selects = destination.appending(path: "Selects/IMG_0001.JPG")
        let porto = destination.appending(path: "Porto/IMG_0002.JPG")
        #expect(FileManager.default.fileExists(atPath: selects.path))
        #expect(FileManager.default.fileExists(atPath: porto.path))
        let sidecar = SidecarStore().load(for: selects)?.metadata
        #expect(sidecar?.flag == .pick && sidecar?.collections == ["Selects", "Trips/Lisbon"])
        #expect(sidecar?.applePhotos?.id == "asset-1")
        #expect(window.control("photos.undo")?.shown == true && window.control("photos.showInLibrary")?.shown == true)
        #expect(window.lines.contains("Their albums are followed: new photos in them show in the Library panel’s "
                + "From Apple Photos"))

        try click("photos.undo", in: window)
        try await sandbox.eventually(seconds: 60) { window.phase == "undone" }
        defer { Self.emptyTrash(window.model.undone) }
        #expect(window.heading == "The import is taken back")
        #expect(!FileManager.default.fileExists(atPath: selects.path))
        #expect(!FileManager.default.fileExists(atPath: porto.path))
        try click("photos.done", in: window)
        try await sandbox.eventually { window.phase == "choosing" }
    }

    @Test func `the window opens within CI's screen, no smaller than 720 by 480`() async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let window = try await Self.window(SimulatedPhotosLibrary(manifest: Self.manifest(in: sandbox)), model: model)
        defer { window.close() }
        let frame = try #require(window.window?.frame)
        #expect(frame.height <= 700 && frame.width >= 720 && frame.height >= 480)
        #expect(window.window?.minSize == NSSize(width: 720, height: 480))
        #expect(window.window?.title == "Import from Apple Photos")
    }
}
