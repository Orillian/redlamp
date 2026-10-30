import AppKit
import Foundation
import RedlampDocument
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// File › Add Albums from Apple Photos… (LIB-54, LIB-62) on a simulated Photos library: access asked for once and
/// explained when there's none, and limited access's one entry kept; Keep in Photos as it opens, the albums kept
/// already chosen and dimmed, and Add Albums
/// keeping the albums chosen in place; Copy into a Folder's albums chosen with their folders, the report, the import
/// and Undo Import.
@MainActor
@Suite(.serialized)
struct ApplePhotosWindowTests {
    /// A Photos library of small JPEGs: Selects, the folder Trips with Lisbon and Porto, a smart album and a shared
    /// one, over a favourite in Selects and Lisbon, a photo in Porto, a video in Lisbon and a shared album's copy;
    /// `extra` more photos in `album`, those `dropping` names gone; and access as `access` says, limited to the photos
    /// `limitedTo` names.
    static func manifest(
        in sandbox: SourcesSandbox, access: String = "authorized", extra: Int = 0, into album: String = "album-lisbon",
        dropping: Set<String> = [], limitedTo: [String] = [],
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
            "limitedTo": limitedTo,
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

    /// Chooses `way`'s segment at the top of the setup's right column, as a click on it does.
    private func choose(_ way: ApplePhotosImportModel.Way, in window: ApplePhotosWindowController) throws {
        let content = try #require(window.window?.contentView)
        let ways = try #require(Self.view("photos.way", in: content) as? NSSegmentedControl)
        #expect(!ways.isHiddenOrHasHiddenAncestor && ways.isEnabled, "photos.way shown and enabled")
        ways.selectedSegment = try #require(ApplePhotosImportModel.Way.allCases.firstIndex(of: way))
        ways.sendAction(ways.action, to: ways.target)
        content.layoutSubtreeIfNeeded()
    }

    /// Whether the view carrying `identifier` is shown, laid out afresh; nil when there's none.
    private static func isShown(_ identifier: String, in window: ApplePhotosWindowController) -> Bool? {
        window.window?.contentView?.layoutSubtreeIfNeeded()
        return window.window?.contentView.flatMap { view(identifier, in: $0) }.map { !$0.isHiddenOrHasHiddenAncestor }
    }

    static func view(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        return view.subviews.lazy.compactMap { Self.view(identifier, in: $0) }.first
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
        #expect(opened == 2)
        #expect(ApplePhotosImportModel.words(for: .limited) == "limited to some photos")
    }

    @Test func `with limited access the one entry is Photos Chosen for Redlamp, which Add Albums keeps as an album`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let photos = try SimulatedPhotosLibrary(manifest: Self.manifest(
            in: sandbox, access: "limited", limitedTo: ["asset-1", "asset-2", "asset-video"],
        ))
        let service = try #require(sandbox.service)
        service.followApplePhotos(photos)
        try await sandbox.eventually { service.applePhotosIndexer != nil }
        let window = await Self.window(photos, model: model)
        defer { window.close() }
        try await sandbox.eventually { window.phase == "choosing" }
        let chosen = ApplePhotosCollection.chosenForRedlamp.id
        let groups = window.model.screen.groups
        #expect(groups.map(\.title) == ["Albums"])
        #expect(groups.first?.albums.map(\.title) == ["Photos Chosen for Redlamp"])
        #expect(groups.first?.albums.first?.count == 3)
        #expect(groups.first?.note?.hasSuffix("Photos shows your albums.") == true)

        try await sandbox.eventually {
            window.window?.contentView?.layoutSubtreeIfNeeded()
            return window.control("photos.album.\(chosen)") != nil
        }
        try click("photos.album.\(chosen)", in: window)
        try click("photos.addAlbums", in: window)
        #expect(model.librarySources.shown == .applePhotos(chosen), "the grid shows the photos chosen for Redlamp")
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 2 }
        #expect(try await service.applePhotosIndexer?.albums().map(\.id) == [chosen])
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
        try choose(.copy, in: window)
        try await sandbox.eventually {
            window.window?.contentView?.layoutSubtreeIfNeeded()
            return window.control("photos.album.shared-family") != nil && window.control("photos.hidden") != nil
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
        #expect(ShortcutAction.importFromApplePhotos.title == "Add Albums from Apple Photos…")
        #expect(ShortcutAction.importFromApplePhotos.category == .file)
    }

    @Test func `each way says what it makes of a smart album, and Copy into a Folder's To that Review asks for one`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let window = try await Self.window(SimulatedPhotosLibrary(manifest: Self.manifest(in: sandbox)), model: model)
        defer { window.close() }
        try await sandbox.eventually { window.phase == "choosing" }
        func smart() -> String? {
            window.model.screen.groups.first { $0.id == "smart" }?.note
        }
        #expect(window.way == "keep")
        #expect(smart() == "Each holds the photos its rules find in Photos, now and later.")

        try choose(.copy, in: window)
        #expect(smart() == "Each becomes a collection of the photos it holds now.")
        #expect(window.control("import.destination")?.title == "Not chosen yet: Review asks for it")
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
        try choose(.copy, in: window)
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
        #expect(window.window?.title == "Add Albums from Apple Photos")
    }

    /// The window over `photos`, the library following it through its one Photos indexer as the app does, with `ids`
    /// kept in place first.
    private static func keeping(
        _ ids: [String], _ photos: SimulatedPhotosLibrary, in sandbox: SourcesSandbox, model: EditorModel,
    ) async throws -> (ApplePhotosWindowController, ApplePhotosIndexer) {
        let service = try #require(sandbox.service)
        service.followApplePhotos(photos)
        try await sandbox.eventually { service.applePhotosIndexer != nil }
        if !ids.isEmpty {
            #expect(try await service.keepApplePhotos(ids))
        }
        let window = await Self.window(photos, model: model)
        try await sandbox.eventually { window.phase == "choosing" }
        try await sandbox.eventually {
            window.window?.contentView?.layoutSubtreeIfNeeded()
            return window.control("photos.album.album-lisbon") != nil
        }
        return try (window, #require(service.applePhotosIndexer))
    }

    @Test func `Keep in Photos opens with the albums kept already chosen and dimmed, and each way keeps its own albums`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let photos = try SimulatedPhotosLibrary(manifest: Self.manifest(in: sandbox))
        let (window, _) = try await Self.keeping(["album-lisbon"], photos, in: sandbox, model: model)
        defer { window.close() }

        #expect(window.way == "keep" && window.control("photos.way")?.title == "Keep in Photos")
        #expect(window.kept == ["album-lisbon"] && window.chosen == ["album-lisbon"])
        let lisbon = try #require(window.model.screen.groups[0].albums.first { $0.id == "album-lisbon" })
        #expect(lisbon.isKept && lisbon.check == .on && lisbon.help?.hasPrefix("In the library") == true)
        #expect(window.control("photos.album.album-lisbon").map { $0.on == .on && !$0.enabled } == true, "dimmed")
        #expect(window.control("photos.album.folder-trips").map { $0.on == .mixed && $0.enabled } == true)
        #expect(window.control("photos.hidden") == nil && window.control("photos.follow") == nil, "only for copying")
        #expect(Self.isShown("photos.keep", in: window) == true && Self
            .isShown("import.destination", in: window) == false)
        #expect(window.control("photos.addAlbums").map { $0.title == "Add Albums" && $0.shown && !$0.enabled } == true)
        #expect(window.control("photos.review")?.shown == false)
        #expect(window.statusText == "Choose the albums to add: those In Library are kept already.")

        try click("photos.album.album-porto", in: window)
        #expect(window.chosen == ["album-lisbon", "album-porto"] && window.control("photos.album.folder-trips")?
            .on == .on)
        #expect(window.control("photos.addAlbums")?.enabled == true)
        #expect(window.model.screen.chosenLine == "1 album chosen, about 1 photo.", "the albums kept already left out")
        try click("photos.album.folder-trips", in: window)
        #expect(window.chosen == ["album-lisbon"], "a folder's box lets go of its albums but those kept")
        try click("photos.album.folder-trips", in: window)
        #expect(window.chosen == ["album-lisbon", "album-porto"])

        try choose(.copy, in: window)
        try await sandbox.eventually {
            window.window?.contentView?.layoutSubtreeIfNeeded()
            return window.control("photos.hidden") != nil
        }
        #expect(window.way == "copy" && window.chosen == ["album-selects", "album-porto"], "every album but those kept")
        #expect(window.control("photos.album.album-lisbon").map { $0.on == .off && !$0.enabled } == true)
        #expect(window.control("photos.album.folder-trips")?.on == .on, "its albums not kept are all chosen")
        #expect(window.control("photos.follow")?.shown == true && window.control("photos.review")?.shown == true)
        #expect(window.control("photos.addAlbums")?.shown == false)
        #expect(Self.isShown("photos.keep", in: window) == false && Self
            .isShown("import.destination", in: window) == true)
        try click("photos.album.album-selects", in: window)
        #expect(window.chosen == ["album-porto"])
        try choose(.keep, in: window)
        #expect(window.chosen == ["album-lisbon", "album-porto"], "each way keeps the albums chosen in it")
    }

    @Test func `Add Albums keeps a new album, or a folder whose albums are all chosen, and shows the first album added`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        try sandbox.photos(["A.jpg"])
        let model = try await sandbox.open()
        let photos = try SimulatedPhotosLibrary(manifest: Self.manifest(in: sandbox))
        let (first, indexer) = try await Self.keeping([], photos, in: sandbox, model: model)
        defer { first.close() }
        #expect(first.kept.isEmpty && first.chosen.isEmpty && first.statusText == "Choose the albums to add.")

        try click("photos.album.album-porto", in: first)
        #expect(first.model.keeping == ["album-porto"], "an album of a folder not all chosen is kept on its own")
        try click("photos.addAlbums", in: first)
        #expect(first.window?.isVisible == false, "the window closes")
        #expect(model.librarySources.shown == .applePhotos("album-porto"), "the grid shows the album added")
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 1 }
        #expect(try await indexer.albums().map(\.id) == ["album-porto"])
        try await sandbox.counts { $0.count(of: .applePhotos("album-porto")) == 1 }

        // Photos' changes are followed from then on, though nothing was kept as the library began following them.
        photos.insert(ApplePhotosAsset(
            id: "asset-porto", created: Date(timeIntervalSince1970: 1_790_000_000), albums: ["album-porto"],
            resources: [ApplePhotosResource(kind: .photo, type: "public.jpeg", originalFilename: "IMG_0050.JPG")],
        ))
        try await sandbox.counts { $0.count(of: .applePhotos("album-porto")) == 2 }
        try await sandbox.eventually { model.items.count == 2 }

        let second = await Self.window(photos, model: model)
        defer { second.close() }
        try await sandbox.eventually { second.phase == "choosing" }
        #expect(second.kept == ["album-porto"] && second.chosen == ["album-porto"])
        try click("photos.album.album-lisbon", in: second)
        try click("photos.album.smart-favourites", in: second)
        #expect(
            second.model.keeping == ["folder-trips", "smart-favourites"],
            "a folder whose albums are all chosen is kept whole, so the albums Photos adds to it are kept too",
        )
        try click("photos.addAlbums", in: second)
        #expect(model.librarySources.shown == .applePhotos("album-lisbon"), "the first album added, in Photos' order")
        try await SourcesSandbox.eventually {
            try await indexer.albums().map(\.id) == ["album-porto", "folder-trips", "smart-favourites"]
        }
        try await sandbox
            .counts { $0.applePhotos["folder-trips"] != nil && $0.count(of: .applePhotos("album-lisbon")) == 1 }
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 1 }
    }
}
