import AppKit
import Foundation
import RedlampDesign
import RedlampLibrary
import Testing
@_spi(Harness) @testable import RedlampUI

/// The Apple Photos section (LIB-62), on a simulated Photos library: after Folders once an album is kept in place, the
/// albums in Photos' folders with their counts; a click on an album shows its photos from Photos' thumbnails, and a
/// click on a folder its albums' photos; an album's menu shows Photos and takes the album out of the library, Photos
/// unchanged; and an album renamed in Photos is renamed in the section, though no photo changed.
@MainActor
@Suite(.serialized)
struct ApplePhotosSectionTests {
    /// Trips, a folder holding Lisbon and Porto, beside Selects: a photo in Lisbon, one in Lisbon and Porto, one in
    /// Porto and one in Selects, with Photos' pictures of them.
    private static func photos() -> SimulatedPhotosLibrary {
        let albums = [["album-lisbon"], ["album-lisbon", "album-porto"], ["album-porto"], ["album-selects"]]
        let assets = albums.enumerated().map { offset, albums in
            ApplePhotosAsset(
                id: "asset-\(offset + 1)", created: Date(timeIntervalSince1970: 1_790_000_000 + Double(offset) * 60),
                albums: albums, resources: [ApplePhotosResource(
                    kind: .photo, type: "public.jpeg", originalFilename: String(format: "IMG_%04d.JPG", offset + 1),
                )],
            )
        }
        return SimulatedPhotosLibrary(
            collections: [
                ApplePhotosCollection(id: "album-selects", title: "Selects", kind: .album),
                ApplePhotosCollection(id: "folder-trips", title: "Trips", kind: .folder),
                ApplePhotosCollection(id: "album-lisbon", title: "Lisbon", kind: .album, parent: "folder-trips"),
                ApplePhotosCollection(id: "album-porto", title: "Porto", kind: .album, parent: "folder-trips"),
            ],
            assets: assets,
        ) { _, version, size in
            ApplePhotosThumbnailsTests.picture(version, size: size).map(ApplePhotosImage.image) ?? .unavailable
        }
    }

    /// The sandbox's library in an editor, its Library module's left column in a window, Photos read from `photos`.
    private static func open(
        _ sandbox: SourcesSandbox, _ photos: SimulatedPhotosLibrary,
    ) async throws -> (EditorModel, LibraryFoldersColumn, NSWindow) {
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        let model = try await sandbox.open(photos: photos)
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 800), styleMask: [.titled], backing: .buffered,
            defer: false,
        )
        let column = LibraryFoldersColumn(model: model)
        window.contentView = column
        column.layoutSubtreeIfNeeded()
        try await sandbox.counts { $0.isCounted }
        return (model, column, window)
    }

    /// Keeps `ids` in place, then follows Photos as the app does, through the library's one Photos indexer.
    private static func keep(
        _ ids: [String], _ sandbox: SourcesSandbox, _ photos: SimulatedPhotosLibrary,
    ) async throws -> ApplePhotosIndexer {
        let service = try #require(sandbox.service)
        let core = try #require(service.core)
        try await ApplePhotosIndexer(photos: photos, index: core.index, paths: core.paths, live: core.live).keep(ids)
        service.followApplePhotos(photos)
        try await sandbox.eventually { service.applePhotosIndexer != nil }
        return try #require(service.applePhotosIndexer)
    }

    private static func views<View: NSView>(_: View.Type, in root: NSView) -> [View] {
        root.subviews.flatMap { view -> [View] in
            if let match = view as? View {
                return [match]
            }
            return views(View.self, in: view)
        }
    }

    /// What VoiceOver says of each row of `list`, top to bottom.
    private static func labels(_ list: SidebarOutlineView) -> [String] {
        (0 ..< list.numberOfRows).compactMap { row in
            (list.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCellView)?.accessibilityLabel()
        }
    }

    /// The row of `list` showing the album or folder titled `title`.
    private static func row(_ title: String, in list: SidebarOutlineView) throws -> Int {
        try #require((0 ..< list.numberOfRows).first { row in
            guard case let .source(source)? = (list.item(atRow: row) as? SidebarNode)?.kind else { return false }
            return source.title == title
        })
    }

    /// Presses the row titled `title`, as a click on it does.
    private static func click(_ title: String, in list: SidebarOutlineView, _ window: NSWindow) throws {
        let rect = try list.rect(ofRow: row(title, in: list))
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: list.convert(CGPoint(x: rect.midX, y: rect.midY), to: nil),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
        ))
        list.mouseDown(with: event)
    }

    /// The menu of the row titled `title`, as a right-click on it opens it.
    private static func menu(_ title: String, in list: SidebarOutlineView) throws -> NSMenu {
        let cell = try list.view(atColumn: 0, row: row(title, in: list), makeIfNecessary: true) as? SidebarCellView
        return try #require(cell?.contextMenu())
    }

    @Test func `the section shows after Folders once an album is kept, its albums in Photos' folders with their counts`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos()
        let (model, column, window) = try await Self.open(sandbox, photos)
        defer { window.contentView = nil }
        let section = try #require(Self.views(SourceListSectionView.self, in: column).first {
            $0.accessibilityIdentifier() == "sidebar.apple-photos"
        })
        #expect(section.isHidden && !model.librarySources.keepsApplePhotos, "no album is kept yet")

        _ = try await Self.keep(["folder-trips", "album-selects"], sandbox, photos)
        try await sandbox.counts { $0.count(of: .applePhotos("album-porto")) == 2 }
        try await sandbox.eventually { !section.isHidden }
        column.layoutSubtreeIfNeeded()
        let shown = Self.views(SourceListSectionView.self, in: column).filter { !$0.isHidden }
        #expect(shown.map { $0.accessibilityIdentifier() } == [
            "sources.library", "sidebar.folders", "sidebar.apple-photos", "sources.collections",
        ])
        for (above, below) in zip(shown, shown.dropFirst()) {
            #expect(below.frame.minY >= above.frame.maxY, "\(below.accessibilityIdentifier()) starts below")
        }
        let list = try #require(Self.views(ApplePhotosOutlineView.self, in: column).first)
        try await sandbox.eventually { Self.labels(list).count == 4 }
        #expect(Self.labels(list) == ["Selects, 1 photo", "Trips", "Lisbon, 2 photos", "Porto, 2 photos"])
        let folder = try Self.menu("Trips", in: list).items.map(\.title)
        #expect(folder == [
            "Show",
            "Show Summary…",
            "",
            "Show in Photos",
            "Download Originals",
            "",
            "Remove from Library…",
        ])
    }

    @Test func `a click on an album shows its photos from Photos' thumbnails, and a click on a folder its albums' photos`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos()
        let (model, column, window) = try await Self.open(sandbox, photos)
        defer { window.contentView = nil }
        _ = try await Self.keep(["folder-trips", "album-selects"], sandbox, photos)
        try await sandbox.counts { $0.count(of: .applePhotos("album-lisbon")) == 2 }
        let list = try #require(Self.views(ApplePhotosOutlineView.self, in: column).first)
        try await sandbox.eventually { Self.labels(list).count == 4 }
        model.showLibrary(.grid)
        let shown = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.borderless], backing: .buffered,
            defer: false,
        )
        let grid = LibraryGridView(model: model)
        grid.frame = shown.contentLayoutRect
        shown.contentView = grid
        defer { shown.contentView = nil }
        grid.layoutSubtreeIfNeeded()

        try Self.click("Lisbon", in: list, window)
        try await sandbox.eventually {
            model.librarySources.shown == .applePhotos("album-lisbon") && !model.librarySources.isListing
                && model.items.count == 2
        }
        #expect(Set(model.items.map(\.name)) == ["IMG_0001.JPG", "IMG_0002.JPG"])
        try await sandbox.eventually { grid.cells.values.filter { $0.item != nil && $0.image != nil }.count == 2 }
        for asset in ["asset-1", "asset-2"] {
            #expect(
                photos.askedImages[ApplePhotosPicture(asset: asset, version: .current)] == 1,
                "\(asset) from Photos",
            )
        }
        #expect(photos.askedImages[ApplePhotosPicture(asset: "asset-3", version: .current)] == nil)
        let lisbon = try Self.row("Lisbon", in: list)
        try await sandbox.eventually { list.selectedRowIndexes == [lisbon] }
        #expect(list.selectedRowIndexes == [lisbon], "the album shown is the section's selection")
        #expect(LibrarySource(key: LibrarySource.applePhotos("album-lisbon").key) == .applePhotos("album-lisbon"))

        try Self.click("Trips", in: list, window)
        try await sandbox.eventually {
            model.librarySources.shown == .applePhotos("folder-trips") && !model.librarySources.isListing
                && model.items.count == 3
        }
        #expect(Set(model.items.map(\.name)) == ["IMG_0001.JPG", "IMG_0002.JPG", "IMG_0003.JPG"])
    }

    @Test func `an album's menu shows Photos, and Remove from Library takes the album out of the library, Photos unchanged`(
    ) async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos()
        let (model, column, window) = try await Self.open(sandbox, photos)
        defer { window.contentView = nil }
        let indexer = try await Self.keep(["folder-trips", "album-selects"], sandbox, photos)
        try await sandbox.counts { $0.count(of: .applePhotos("album-selects")) == 1 }
        let list = try #require(Self.views(ApplePhotosOutlineView.self, in: column).first)
        try await sandbox.eventually { Self.labels(list).count == 4 }
        try Self.click("Selects", in: list, window)
        try await sandbox.eventually { model.librarySources.shown == .applePhotos("album-selects") }

        let menu = try Self.menu("Selects", in: list)
        #expect(menu.items.map(\.title) == [
            "Show", "Show Summary…", "", "Show in Photos", "Download Originals", "Copy to Folder…", "",
            "Remove from Library…",
        ])
        let opening = ApplePhotosActions.openPhotos
        var opened = 0
        ApplePhotosActions.openPhotos = { opened += 1 }
        defer { ApplePhotosActions.openPhotos = opening }
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "Show in Photos"))
        #expect(opened == 1)

        ApplePhotosRemoval.answer = true
        defer { ApplePhotosRemoval.answer = nil }
        menu.performActionForItem(at: menu.indexOfItem(withTitle: "Remove from Library…"))
        try await sandbox.counts { $0.applePhotos["album-selects"] == nil }
        #expect(try await indexer.albums().map(\.id) == ["folder-trips"])
        #expect(model.librarySources.shown == .allPhotographs, "the album shown gave way to All Photographs")
        try await sandbox.eventually { !model.librarySources.isListing && model.items.count == 3 }
        #expect(!model.items.contains { $0.name == "IMG_0004.JPG" })
        #expect(try await photos.collections().contains { $0.id == "album-selects" }, "Photos still has the album")
        try await sandbox.eventually { Self.labels(list) == ["Trips", "Lisbon, 2 photos", "Porto, 2 photos"] }
    }

    @Test func `Remove from Library's question says the photos another album kept holds stay`() {
        let album = ApplePhotosCollection(id: "album-selects", title: "Selects", kind: .album)
        let folder = ApplePhotosCollection(id: "folder-trips", title: "Trips", kind: .folder)
        let held = "but for those another album you've kept holds."
        #expect(ApplePhotosRemoval.message(album, photos: 3).hasPrefix("Its 3 photos leave Redlamp's lists until "))
        #expect(ApplePhotosRemoval.message(album, photos: 3).contains(held))
        #expect(ApplePhotosRemoval.message(album, photos: nil).contains(held))
        #expect(ApplePhotosRemoval.message(album, photos: 1).contains("unless another album you've kept holds it."))
        #expect(ApplePhotosRemoval.message(folder, photos: 4).contains(held))
        #expect(ApplePhotosRemoval.message(folder, photos: 4).hasSuffix("on this Mac. Apple Photos isn't changed."))
    }

    @Test func `an album renamed in Photos is renamed in the section, though no photo changed`() async throws {
        let sandbox = SourcesSandbox()
        defer { sandbox.remove() }
        let photos = Self.photos()
        let (_, column, window) = try await Self.open(sandbox, photos)
        defer { window.contentView = nil }
        _ = try await Self.keep(["folder-trips"], sandbox, photos)
        try await sandbox.counts { $0.count(of: .applePhotos("album-porto")) == 2 }
        let list = try #require(Self.views(ApplePhotosOutlineView.self, in: column).first)
        try await sandbox.eventually { Self.labels(list) == ["Trips", "Lisbon, 2 photos", "Porto, 2 photos"] }
        let passes = try #require(sandbox.service).applePhotosPasses

        photos.add(ApplePhotosCollection(id: "album-porto", title: "Porto 2026", kind: .album, parent: "folder-trips"))
        try await sandbox.eventually { Self.labels(list).last == "Porto 2026, 2 photos" }
        #expect(Self.labels(list) == ["Trips", "Lisbon, 2 photos", "Porto 2026, 2 photos"])
        #expect(try #require(sandbox.service).applePhotosPasses > passes)
    }
}
