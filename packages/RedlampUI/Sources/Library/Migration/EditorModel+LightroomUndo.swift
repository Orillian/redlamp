import Foundation
import Observation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary

/// ⌘Z for an import from Lightroom Classic (LIB-29): an import that ends having changed photos goes on Undo as a
/// change of its own, newest, ending every Redo, and ⌘Z takes it back through the import's own Undo, as Undo Import in
/// its window does, each of its batches keeping what changed since. It takes its turn as it ends: the changes made
/// while it ran come before it. ⇧⌘Z doesn't make it again; importing the catalog again does. Undo Import in the
/// window takes it off Undo.
extension EditorModel {
    /// The imports Undo takes back, newest last.
    var lightroomSteps: LightroomSteps {
        if let steps = Self.lightroomSteps.object(forKey: self) {
            return steps
        }
        let steps = LightroomSteps()
        Self.lightroomSteps.setObject(steps, forKey: self)
        return steps
    }

    private static let lightroomSteps = NSMapTable<EditorModel, LightroomSteps>.weakToStrongObjects()

    /// An import that ended, `record` as the library keeps it: on Undo, newest, ending every Redo, unless it changed
    /// nothing or is there already.
    func pushLightroomImport(_ record: LightroomImportRecord) {
        guard !(record.batches.isEmpty && (record.inEditor ?? []).isEmpty), !record.undone,
              !lightroomSteps.undo.contains(where: { $0.record == record.id }) else { return }
        let step = LightroomStep(record: record.id, photos: record.photos)
        step.turn = nextLibraryTurn()
        lightroomSteps.undo.append(step)
        endLibraryRedo()
    }

    /// The import's way to the photo open here (EDT-23): its edit is made as a step of its history, as Settings
    /// Sync makes a batch's, never by its sidecar being written behind it.
    var lightroomEditor: LightroomEditor {
        LightroomEditor { [weak self] in
            await self?.openPhotoPath
        } change: { [weak self] path, recipe, over, adding, removing in
            await self?.changeFromLightroom(path, recipe, over: over, adding: adding, removing: removing) ?? .notOpen
        }
    }

    /// The path of the photo open here, or opening, as the index has it.
    private var openPhotoPath: String? {
        guard let url = opening ?? selection, isOpen(url) else { return nil }
        let path = url.standardizedFileURL.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The photo at `path` given `recipe` as a step titled as Undo Import's or the import's, while its edit is
    /// `over` (nil: while it's unedited), and its snapshots changed.
    private func changeFromLightroom(
        _ path: String, _ next: EditRecipe, over: EditRecipe?, adding: [Snapshot], removing: Set<UUID>,
    ) async -> LightroomEditor.Outcome {
        let url = URL(fileURLWithPath: path)
        await finishOpening(url)
        guard let visit = currentVisit, visit.url.standardizedFileURL == url.standardizedFileURL else {
            return isOpen(url) ? .left : .notOpen
        }
        guard !isReadOnly, over.map({ recipe == $0 }) ?? recipe.isPristine else { return .left }
        let (before, had) = (recipe, snapshots)
        commit(next, .paste, over == nil ? "Import from Lightroom Classic" : "Undo Import from Lightroom Classic")
        changeSnapshots(adding: adding, removing: removing)
        return .changed(before, had, recipe)
    }

    /// Whether an import from Lightroom Classic, or its Undo, is running: ⌘Z takes an import back once it's done.
    var isRunningLightroomImport: Bool {
        LightroomWindowController.current?.model.isBusy == true
    }

    /// ⌘Z: the newest import taken back in the background, by its window when it's open, which shows it.
    @discardableResult
    func undoLightroomImport() -> Bool {
        guard !isRunningLightroomImport, let core = library.service?.core, let step = lightroomSteps.undo.popLast()
        else { return false }
        activity.record(.action, "Undo \(step.title)")
        if let window = LightroomWindowController.current {
            window.model.undo(step.record)
            return true
        }
        let importer = LightroomImportModel.importer(core, editor: self)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<
                LightroomImportRecord,
                any Error,
            > in
                do {
                    return try await .success(importer.undo(step.record))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.lightroomImportUndone(result)
        }
        return true
    }

    /// An import's Undo ended, by ⌘Z or by Undo Import: what it did in the activity log, the import off Undo, and the
    /// panels reading the keywords and collections again. Returns what went wrong, in words.
    @discardableResult
    func lightroomImportUndone(_ result: Result<LightroomImportRecord, any Error>) -> String? {
        var problem: String?
        switch result {
        case let .success(record):
            activity.record(.action, "Undo the import from Lightroom Classic of \(record.photos) photos")
            lightroomSteps.undo.removeAll { $0.record == record.id }
        case let .failure(error):
            problem = "The import wasn't all taken back: \(error)"
            activity.record(.error, problem ?? "")
        }
        libraryPanels.refreshKeywords()
        libraryPanels.refresh()
        return problem
    }
}

/// The imports from Lightroom Classic Undo takes back. Observed, so the menu bar's Undo follows an import that ends
/// when nothing shown changes.
@MainActor
@Observable
final class LightroomSteps {
    var undo: [LightroomStep] = []
}

/// One import from Lightroom Classic, as Undo takes it back: by its record in the library.
@MainActor
final class LightroomStep {
    let record: UUID
    let photos: Int
    /// Its turn in Undo (`EditorModel+LibraryUndo`).
    var turn = 0

    init(record: UUID, photos: Int) {
        self.record = record
        self.photos = photos
    }

    var title: String {
        "Import from Lightroom Classic of \(LightroomImportModel.count(photos, "photo"))"
    }
}
