import AppKit
import Observation
import RedlampLibrary
@_spi(Harness) import RedlampUI
import SwiftUI

extension HarnessScene {
    static var libraryImport: HarnessScene {
        HarnessScene(
            id: "library-import",
            title: "Import Photos",
            symbol: "sdcard",
            synopsis: "The import window on a card, part of it already in the library, in each state",
            section: .library,
        ) {
            LibraryScene(surfaces: [.importPhotos], states: [.opened, .finished, .interrupted, .minimum])
        }
    }

    static var libraryLightroom: HarnessScene {
        HarnessScene(
            id: "library-lightroom",
            title: "Lightroom Classic",
            symbol: "square.stack.3d.down.right",
            synopsis: "Import from Lightroom Classic on a catalog with roots in, out of and missing from the library",
            section: .library,
        ) {
            LibraryScene(surfaces: [.lightroom], states: [.noCatalog, .opened, .imported, .undone, .minimum])
        }
    }

    static var libraryApplePhotos: HarnessScene {
        HarnessScene(
            id: "library-apple-photos",
            title: "Apple Photos",
            symbol: "photo.on.rectangle.angled",
            synopsis: "Add Albums from Apple Photos on a simulated library, in each state from asking for access on",
            section: .library,
        ) {
            LibraryScene(
                surfaces: [.applePhotos],
                states: [
                    .notAsked, .denied, .restricted, .limited, .opened, .copying, .reviewed, .importing, .imported,
                    .undone, .minimum,
                ],
            )
        }
    }

    static var librarySheets: HarnessScene {
        HarnessScene(
            id: "library-sheets",
            title: "Sheets",
            symbol: "rectangle.on.rectangle",
            synopsis: "Every library sheet over this window, on a library of the harness's own",
            section: .library,
        ) {
            LibraryScene(
                surfaces: LibrarySurface.allCases.filter { ![.importPhotos, .lightroom, .applePhotos].contains($0) },
                states: [.opened],
            )
        }
    }
}

/// What a surface shows when it opens.
enum LibrarySurfaceState: String, CaseIterable, Identifiable {
    case opened, noCatalog = "no-catalog", finished, interrupted, imported, undone, minimum
    case notAsked = "not-asked", denied, restricted, limited, copying, reviewed, importing

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .opened: "Open"
        case .noCatalog: "No catalog"
        case .finished: "Finished"
        case .interrupted: "Interrupted"
        case .imported: "Imported"
        case .undone: "Undone"
        case .minimum: "At its minimum size"
        case .notAsked: "Not asked"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .limited: "Limited"
        case .copying: "Copy into a Folder"
        case .reviewed: "Review"
        case .importing: "Importing"
        }
    }
}

/// Opens the Library scenes' surfaces, one at a time, closing the one before.
@MainActor @Observable
final class LibrarySceneState {
    static let shared = LibrarySceneState()

    private(set) var status = "Opening the harness's library…"
    private(set) var isReady = false
    @ObservationIgnored private var launched = false

    private var model: EditorModel {
        HarnessLibrary.model
    }

    func prepare() async {
        await HarnessLibrary.ready()
        isReady = true
        status = "\(model.items.count) photos in \(HarnessLibrary.fixture.photos.path)"
    }

    /// `--library-surface <id>` and `--library-state <state>` at launch, for the scene that has the surface.
    func openRequested(among surfaces: [LibrarySurface]) async {
        guard !launched, let id = HarnessLaunch.value(after: "--library-surface"),
              let surface = surfaces.first(where: { $0.id == id })
        else { return }
        launched = true
        let state = HarnessLaunch.value(after: "--library-state").flatMap(LibrarySurfaceState.init) ?? .opened
        await open(surface, state)
        try? await Task.sleep(for: .seconds(2))
        HarnessAppDelegate.snapshotIfRequested()
    }

    func open(_ surface: LibrarySurface, _ state: LibrarySurfaceState) async {
        let harness = Self.harnessWindow
        EditorWindowController.harnessWindow = harness
        model.closeHarnessSurface(over: harness)
        harness?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        var fixture = HarnessLibrary.fixture
        if state == .noCatalog {
            fixture.catalog = nil
        }
        fixture.applePhotosAccess = switch state {
        case .notAsked: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .limited: .limited
        default: .authorized
        }
        guard await model.openHarnessSurface(surface, fixture: fixture) else {
            status = "\(surface.title) didn't open: it needs a selection, a collection or a keyword the library lacks"
            return
        }
        status = "\(surface.title): \(state.title)"
        if surface == .applePhotos, [.copying, .reviewed, .importing, .imported, .undone].contains(state) {
            await photos(state)
            return
        }
        switch state {
        case .finished:
            await ImportWindowController.current?.importAndWait()
        case .interrupted:
            ImportWindowController.current?.simulateForcedQuit(afterPhotos: 3)
            await ImportWindowController.current?.importAndWait()
            ImportWindowController.current?.close()
            await model.openHarnessSurface(surface, fixture: fixture)
        case .imported, .undone:
            guard let window = await until({ LightroomWindowController.current?.isReported == true }) else { return }
            window.pressImport()
            guard await until({ LightroomWindowController.current?.isImported == true }) != nil, state == .undone
            else { return }
            window.pressUndoImport()
        case .minimum:
            for window in [
                ImportWindowController.current?.window, LightroomWindowController.current?.window,
                ApplePhotosWindowController.current?.window,
            ] {
                guard let window else { continue }
                window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: true)
            }
        case .opened, .noCatalog, .notAsked, .denied, .restricted, .limited, .copying, .reviewed, .importing:
            break
        }
    }

    /// The Apple Photos window taken to `state`: Copy into a Folder chosen, Review, an import's progress as it
    /// downloads from iCloud, the import done, or taken back.
    private func photos(_ state: LibrarySurfaceState) async {
        func reach(_ phase: String) async -> ApplePhotosWindowController? {
            for _ in 0 ..< 600 where ApplePhotosWindowController.current?.phase != phase {
                try? await Task.sleep(for: .milliseconds(100))
            }
            return ApplePhotosWindowController.current?.phase == phase ? ApplePhotosWindowController.current : nil
        }
        guard let window = await reach("choosing") else { return }
        if state == .importing {
            window.show(ApplePhotosImport.Progress(
                stage: .staging, photos: 1240, done: 312, bytes: 3_100_000_000, written: 780_000_000, downloading: 3,
            ))
            return
        }
        window.choose(way: "copy")
        guard state != .copying else { return }
        window.press(named: "review")
        guard await reach("reviewing") != nil, state != .reviewed else { return }
        window.press(named: "importPhotos")
        guard await reach("imported") != nil, state == .undone else { return }
        window.press(named: "undo")
    }

    private func until(_ condition: () -> Bool) async -> LightroomWindowController? {
        for _ in 0 ..< 600 where !condition() {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition() ? LightroomWindowController.current : nil
    }

    static var harnessWindow: NSWindow? {
        NSApp.windows.first { window in
            window.isVisible && window.canBecomeMain && window.sheetParent == nil
                && !(window.windowController is ImportWindowController)
                && !(window.windowController is LightroomWindowController)
                && !(window.windowController is ApplePhotosWindowController)
        }
    }
}

private struct LibraryScene: View {
    let surfaces: [LibrarySurface]
    let states: [LibrarySurfaceState]
    @State private var state = LibrarySceneState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.status).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(surfaces) { surface in
                    GridRow {
                        Text(surface.title)
                        HStack {
                            ForEach(states) { surfaceState in
                                Button(surfaceState.title) {
                                    Task { await state.open(surface, surfaceState) }
                                }
                            }
                        }
                    }
                }
            }
            .disabled(!state.isReady)
            SpecimenGroup(title: "Look for", note: """
            Labels and fields lined up in their columns, nothing clipped or truncated that has room, the Mac's \
            margins (20 points) and spacing, a heading on every sheet, and the same in light and dark (the theme \
            controls below the scene list). Each sheet opens over this window; Cancel closes it.
            """) {
                EmptyView()
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .task {
            await state.prepare()
            await state.openRequested(among: surfaces)
        }
    }
}
