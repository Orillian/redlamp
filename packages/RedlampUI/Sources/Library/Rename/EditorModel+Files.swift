import AppKit
import Foundation
import Observation
import RedlampDocument
import RedlampLibrary
import Synchronization

/// Renaming, moving and copying photos in Library (LIB-25, LIB-26), and moving them to the Trash in either module
/// (LIB-46, `EditorModel+MoveToTrash`), each one of the library's journaled batches with Undo and Redo on Library's ⌘Z
/// and ⇧⌘Z, in turn with the library's other changes (`EditorModel+LibraryUndo`); a copy's Undo moves its copies to
/// the Trash, and its Redo copies again.
///
/// - **Shown at once:** the photos go where the batch puts them in the grid and the filmstrip before it runs
///   (`LibraryMoves`), each keeping its ID, so the selection follows; the active photo, leaving Develop's
///   document first, goes with it, or, leaving the photos shown, hands over to the photo after it. The library's
///   lists then find each photo where it already is.
/// - **Saved first:** the sidecars the photos' saves still write are on disk before the batch plans, and the
///   batch runs in the library's changes' turn, after the culling batches asked for before it.
/// - **Afterwards,** each photo is shown where the index has it, so a batch that stopped or was rolled back
///   shows what it left.
/// - **Undo and Redo:** a step takes its turn on Undo as it's asked for, so ⌘Z pressed while its batch runs takes
///   it back once the batch is done; Redo makes it again with a batch planned anew, and a change made since its Undo
///   ends that, as it ends every Redo. Steps are made one at a time, in the order they're asked for.
public extension EditorModel {
    /// Rename Photos…: the template sheet for the photos selected, with their raw and JPEG pairs.
    @discardableResult
    func renamePhotos() -> Bool {
        guard let sheet = renameSheet() else { return false }
        RenameSheetController.present(sheet, editor: self)
        return true
    }

    /// Rename Photos and Move to Folder act on Library's selection, with the library open.
    var canRenamePhotos: Bool {
        module == .library && !isModalDialogOpen && selection != nil && library.service?.isReady == true
    }
}

extension EditorModel {
    /// What Rename Photos shows for the photos selected, in their order, read once it starts.
    func renameSheet(presets: NamingPresetStore? = nil) -> RenameModel? {
        guard canRenamePhotos, let service = library.service, let core = service.core else { return nil }
        // A source's photos are found by their own IDs, which are the index's, without reading their rows.
        let shownIDs = library.showsIndexIDs ? selectedIDs : nil
        let urls = shownIDs == nil ? selectedPhotos : []
        return RenameModel(
            photos: shownIDs?.count ?? urls.count, presets: presets ?? NamingPresetStore.shared(for: service.paths),
            sidecars: library.sidecars,
        ) {
            if let shownIDs {
                return try await RenameJob.read(shownIDs, core: core)
            }
            let ids = await LibraryService.indexIDs(of: urls, in: core.index)
            return try await RenameJob.read(urls.compactMap { ids[$0] }, core: core)
        }
    }

    // MARK: - Keys, menus and the palette

    /// Rename Photos, Move to Folder, Copy to Folder and Move to Trash; nil for every other action.
    func performFileShortcut(_ action: ShortcutAction) -> Bool? {
        switch action {
        case .renamePhotos: renamePhotos()
        case .moveToFolder: moveToFolder()
        case .copyToFolder: copyToFolder()
        case .moveToTrash: moveToTrash()
        default: nil
        }
    }

    func canPerformFileShortcut(_ action: ShortcutAction) -> Bool? {
        switch action {
        case .renamePhotos, .moveToFolder, .copyToFolder: canRenamePhotos
        case .moveToTrash: canMoveToTrash
        default: nil
        }
    }

    /// The renames and moves Undo and Redo take back and make again.
    var fileSteps: LibraryFileSteps {
        if let steps = Self.fileSteps.object(forKey: self) {
            return steps
        }
        let steps = LibraryFileSteps()
        Self.fileSteps.setObject(steps, forKey: self)
        return steps
    }

    private static let fileSteps = NSMapTable<EditorModel, LibraryFileSteps>.weakToStrongObjects()

    /// `step` on Undo as it's asked for, newest, ending every Redo.
    func push(_ step: LibraryFileStep) {
        step.turn = nextLibraryTurn()
        fileSteps.undo.append(step)
        endLibraryRedo()
    }

    // MARK: - Renaming

    /// Renames the photos `sheet` names, as one batch: shown at once, then made in the background, after the
    /// file steps asked for before it, with its progress in the sheet, until it's done or `stop` stops it.
    /// Returns why it didn't happen, or nil.
    func rename(_ sheet: RenameModel, stop: FileStop? = nil) async -> String? {
        guard let service = library.service, service.isReady else { return "The library isn't open" }
        guard let (renames, batch) = await sheet.renames() else { return "The template has an error" }
        guard !renames.isEmpty else { return nil }
        let photos = renames.map { rename -> (id: Int64, from: String, to: String?) in
            (
                id: rename.id,
                from: rename.path,
                to: (rename.path as NSString).deletingLastPathComponent + "/" + rename.name,
            )
        }
        let step = LibraryFileStep(kind: .rename(renames), photos: photos)
        let relay = FileProgressRelay { progress in
            sheet.setPhase(.renaming(done: progress.done, total: progress.total))
        }
        push(step)
        let run = await fileSteps.make { [self] in
            await perform(step, undoing: false) {
                await service.rename(renames, progress: { relay.send($0) }, stop: stop)
            }
        }
        if run.batch != nil {
            sheet.renamed(batch)
        }
        record(run, of: step)
        return run.error
    }

    /// Says in the activity log what `run` made of `step`, asked for now.
    func record(_ run: LibraryService.FileRun, of step: LibraryFileStep) {
        if let error = run.error {
            activity.record(.error, "\(step.title) wasn't done: \(error)")
        } else if run.stopped {
            activity.record(
                .action,
                run.batch == nil ? "\(step.title) stopped before it began" : "\(step.title), stopped",
            )
        } else if run.batch != nil {
            activity.record(.action, step.title)
        }
    }

    // MARK: - Undo and Redo

    /// Takes back the latest file step, in either module: shown, then its batch's Undo in the background, once the
    /// steps asked for before it are made, its own batch among them, its progress and Stop in Library's toolbar.
    /// Stopped partway, the step goes back on Undo, for ⌘Z to take back the rest.
    @discardableResult
    func undoFiles() -> Bool {
        guard let service = library.service, let step = fileSteps.undo.popLast() else {
            return false
        }
        let made = step.turn
        step.turn = nextLibraryTurn()
        fileSteps.redo.append(step)
        activity.record(.action, "Undo \(step.title)")
        let ids = step.photos.map(\.id)
        fileSteps.enqueue { [weak self] in
            guard let self else { return }
            guard let batch = step.batch else {
                if step.versions.isEmpty {
                    // Its own batch made nothing to take back.
                    fileSteps.redo.removeAll { $0 === step }
                } else {
                    await putBack(step.versions)
                }
                return
            }
            let run = await showingProgress("Undo " + step.title) { relay, stop in
                await self.perform(step, undoing: true) {
                    await service.undoFiles(batch, photos: ids, progress: { relay.send($0) }, stop: stop)
                }
            }
            await putBack(step.versions)
            if let error = run.error {
                activity.record(.error, "Undo \(step.title) wasn't done: \(error)")
            } else if run.stopped {
                activity.record(.action, "Undo \(step.title), stopped")
            }
            // Nothing, or not everything, was taken back: back on Undo in its place, unless a change made since
            // ended its Redo.
            if run.batch == nil && run.error != nil || run.stopped,
               let place = fileSteps.redo.lastIndex(where: { $0 === step }) {
                fileSteps.redo.remove(at: place)
                step.turn = made
                fileSteps.undo.append(step)
            }
        }
        return true
    }

    /// Makes the file step Undo took back last again, in either module, with a batch planned anew, its progress and
    /// Stop in Library's toolbar; stopped partway, the step is what its batch did.
    @discardableResult
    func redoFiles() -> Bool {
        guard let service = library.service, let step = fileSteps.redo.popLast() else {
            return false
        }
        let undone = step.turn
        step.turn = nextLibraryTurn()
        fileSteps.undo.append(step)
        activity.record(.action, "Redo \(step.title)")
        fileSteps.enqueue { [weak self] in
            guard let self else { return }
            if !step.versions.isEmpty {
                step.versions = await removeVersions(of: step.versions.map(\.address))
            }
            // A step to the Trash that took only versions has no files to move again.
            if step.isTrash, step.photos.isEmpty {
                return
            }
            let run = await showingProgress("Redo " + step.title) { relay, stop in
                await self.perform(step, undoing: false) {
                    let progress: @Sendable (FileProgress) -> Void = { relay.send($0) }
                    return switch step.kind {
                    case let .rename(renames): await service.rename(renames, progress: progress, stop: stop)
                    case let .move(ids, folder): await service.move(ids, to: folder, progress: progress, stop: stop)
                    case let .copy(ids, folder): await service.copy(ids, to: folder, progress: progress, stop: stop)
                    case let .trash(ids): await service.trash(ids, progress: progress, stop: stop)
                    }
                }
            }
            if let batch = run.batch {
                step.batch = batch
            }
            if let error = run.error {
                activity.record(.error, "Redo \(step.title) wasn't done: \(error)")
            } else if run.stopped {
                activity.record(.action, "Redo \(step.title), stopped")
            }
            // Nothing was made again: back on Redo while it's still the newest change, off Undo either way.
            if run.batch == nil, run.error != nil || run.stopped,
               let place = fileSteps.undo.lastIndex(where: { $0 === step }) {
                let newest = place == fileSteps.undo.count - 1 && libraryUndoKind == .files
                fileSteps.undo.remove(at: place)
                if newest {
                    step.turn = undone
                    fileSteps.redo.append(step)
                }
            }
        }
        return true
    }

    // MARK: - Making a step

    /// Shows `step` (or its Undo) at once, waits for its photos' saves, runs `batch`, then shows each photo
    /// where the index has it; a copy's photos stay, its copies reaching the lists as the index gets them. A batch
    /// that was stopped leaves the step what it did. A new step, on Undo since it was asked for (`push`), leaves it
    /// when its batch made nothing.
    func perform(
        _ step: LibraryFileStep, undoing: Bool, batch: @escaping () async -> LibraryService.FileRun,
    ) async -> LibraryService.FileRun {
        let isNew = step.batch == nil && !undoing
        let moves: [FileMove] = step.isCopy ? [] : step.photos.map { photo -> FileMove in
            if undoing {
                return (photo.id, photo.to, photo.from)
            }
            return (photo.id, photo.from, photo.to)
        }
        let saving: [URL]
        if step.isCopy {
            await cullingTail?.value
            saving = step.photos.map { URL(fileURLWithPath: $0.from) }
        } else {
            saving = await show(moves, of: step, undoing: undoing)
        }
        await waitForSaves(of: saving)
        let shown = selection
        let run = await batch()
        await follow(moves, of: step, paths: run.paths)
        // A source's photos come back as its list has them again, which it hands over after the batch.
        if undoing, step.isTrash, let active = step.active, selection != active, selection == shown {
            for _ in 0 ..< 100 where library.index(of: active) == nil {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if selection == shown {
                selectAgain(step)
            }
        }
        libraryPanels.photosMoved()
        if !undoing, run.stopped, run.batch != nil, let done = run.outcome?.photoIDs {
            step.keep(Set(done))
        }
        if isNew {
            if let made = run.batch {
                step.batch = made
            } else {
                fileSteps.undo.removeAll { $0 === step }
            }
        }
        return run
    }

    /// A photo a step moves, by its ID in the index: its path before and after, nil in the Trash.
    typealias FileMove = (id: Int64, from: String?, to: String?)

    /// Shows `moves` at once: the photos at their new URLs, or out of the photos shown; a move's Undo shows
    /// again the photos it took away, selected as they were. The active photo goes with them, or, when it
    /// leaves the photos shown, the photo after it becomes active, and with none left, a step to the Trash lets it
    /// go. Returns the URLs of the photos as they were, whose saves the batch waits for.
    private func show(_ moves: [FileMove], of step: LibraryFileStep, undoing: Bool) async -> [URL] {
        // Culling's batches asked for before reach the lists first; the list's changes made before or meanwhile
        // reach the photos where they're shown (`MovesAhead`).
        await cullingTail?.value
        var shown: [LibraryMoves.Move] = []
        var restoring: [LibraryItem] = []
        var keys: [URL: ContentKey] = [:]
        var ids: [URL: Int64] = [:]
        var saving: [URL] = []
        // The photos leaving those shown, by their IDs there: moved where the folders shown don't reach, or to the
        // Trash, which takes a source's photo out of it too.
        var leaving = Set<Int64>()
        let urls = await listedURLs(of: moves)
        for (move, url) in zip(moves, urls) {
            if let file = url.file {
                saving.append(file)
            }
            let to = url.to
            guard let from = url.from, library.index(of: from) != nil else {
                if move.to == nil, library.showsIndexIDs, library.photoList.index(of: move.id) != nil {
                    leaving.insert(move.id)
                }
                if let to, let item = step.items[move.id] {
                    restoring.append(FolderLibrary.item(item, at: to))
                    keys[to] = step.keys[move.id]
                    ids[to] = move.id
                }
                continue
            }
            saving.append(from)
            if to == nil, let id = library.photoID(of: from) {
                leaving.insert(id)
            }
            if !undoing, step.items[move.id] == nil, let item = library.item(for: from) {
                step.items[move.id] = item
                step.keys[move.id] = library.contentKey(of: from)
            }
            shown.append(LibraryMoves.Move(from: from, to: to, id: move.id))
        }
        if !undoing, step.active == nil {
            step.selected = Set(selectedPhotos)
            step.active = selection
        }
        let destination = selection.flatMap { active in shown.first { $0.from == active } }?.to
        let active = selectionID
        let leaves = active.map(leaving.contains) == true
        let next = active.flatMap { leaves ? photo(after: $0, leaving: leaving) : nil }
        await library.show(LibraryMoves(moves: shown, restoring: restoring, keys: keys, ids: ids)) { [self] in
            if let destination {
                select(destination, keepingSelection: true)
            } else if let next {
                select(photo: next)
            } else if leaves, step.isTrash {
                letGoOfActivePhoto()
            }
            if let anchor = selectionAnchor, let moved = shown.first(where: { $0.from == anchor.url }) {
                selectionAnchor = moved.to.map { PhotoAddress(url: $0, version: anchor.version) }
            }
        }
        if !restoring.isEmpty {
            selectAgain(step)
        }
        return saving
    }

    /// The photo shown after `active` that isn't `leaving`, by the photos' IDs, else the nearest before it.
    private func photo(after active: Int64, leaving: Set<Int64>) -> Int64? {
        let ids = library.photoIDs
        guard let row = library.photoList.index(of: active), ids.indices.contains(row) else { return nil }
        return ids[(row + 1)...].first { !leaving.contains($0) } ?? ids[..<row].last { !leaving.contains($0) }
    }

    /// Selects photo `id` of those shown alone: at once, or, for a large source's row not read yet, once it's read.
    private func select(photo id: Int64) {
        if let url = library.url(ofPhoto: id) {
            return select(url)
        }
        library.whenRead([id]) { [weak self] in
            guard let self, let url = library.url(ofPhoto: id) else { return }
            select(url)
        }
    }

    /// The photos `step` took away, shown again, selected as they were.
    private func selectAgain(_ step: LibraryFileStep) {
        guard let active = step.active, library.index(of: active) != nil else { return }
        select(active, keepingSelection: true)
        photoSelection.select(
            step.selected.compactMap(library.photoID(of:)), active: library.photoID(of: active),
            in: library.photoList,
        )
    }

    /// Each move's file, and the URLs the folders shown give its photo where it is and where it goes, worked out off
    /// the main thread: a thousand photos' take milliseconds. Should the folders shown change meanwhile, they're
    /// worked out again for those shown then. A photo in the Trash has neither.
    private func listedURLs(of moves: [FileMove]) async -> [(file: URL?, from: URL?, to: URL?)] {
        let urls: @Sendable (ListedURLs) -> [(file: URL?, from: URL?, to: URL?)] = { listed in
            moves.map { move in
                (
                    file: move.from.map { URL(fileURLWithPath: $0) },
                    from: move.from.flatMap(listed.url(ofPath:)),
                    to: move.to.flatMap(listed.url(ofPath:)),
                )
            }
        }
        let listed = library.listedURLs
        let made = await Task.detached(priority: .userInitiated) { urls(listed) }.value
        return library.listedURLs == listed ? made : urls(library.listedURLs)
    }

    /// Once a batch has run: each photo shown where the index has it, should the batch have stopped, been rolled
    /// back or left some out; then, once the open folder's list has handed over the batch's change, as the list has
    /// it.
    private func follow(_ moves: [FileMove], of step: LibraryFileStep, paths: [Int64: String]) async {
        var corrections: [LibraryMoves.Move] = []
        var restoring: [LibraryItem] = []
        var keys: [URL: ContentKey] = [:]
        var ids: [URL: Int64] = [:]
        let listed = library.listedURLs
        for move in moves {
            guard let path = paths[move.id], path != move.to else { continue }
            let actual = listed.url(ofPath: path)
            if let shown = move.to.flatMap(listed.url(ofPath:)), library.index(of: shown) != nil {
                corrections.append(LibraryMoves.Move(from: shown, to: actual, id: move.id))
            } else if let actual, library.index(of: actual) == nil, let item = step.items[move.id] {
                restoring.append(FolderLibrary.item(item, at: actual))
                keys[actual] = step.keys[move.id]
                ids[actual] = move.id
            }
        }
        if !corrections.isEmpty || !restoring.isEmpty {
            await library.show(LibraryMoves(moves: corrections, restoring: restoring, keys: keys, ids: ids))
        }
        await library.caughtUp()
    }

    /// Runs `body` with its batch's progress and Stop in the grid's toolbar, as a drop's move shows them, for Undo
    /// and Redo, which leave actions on.
    func showingProgress(
        _ title: String, _ body: (FileProgressRelay, FileStop) async -> LibraryService.FileRun,
    ) async -> LibraryService.FileRun {
        let stop = FileStop()
        let shown = moveProgress
        let token = shown.begin(title, stop: stop)
        defer { shown.end(token) }
        return await body(FileProgressRelay { shown.show($0, for: token) }, stop)
    }

    /// Returns once the saves asked for any of `photos` before the call are on disk.
    private func waitForSaves(of photos: [URL]) async {
        let saves = saves
        for photo in await Task.detached(priority: .userInitiated, operation: { saves.pending(photos) }).value {
            await saves.wait(for: photo)
        }
    }
}

/// The renames, moves and copies Library's Undo and Redo take back and make again, made one at a time in the order
/// they're asked for. Observed, so the menu bar's Undo and Redo follow them when nothing shown changes, as with a
/// copy's.
@MainActor
@Observable
final class LibraryFileSteps {
    var undo: [LibraryFileStep] = []
    var redo: [LibraryFileStep] = []
    @ObservationIgnored private var tail: Task<Void, Never>?

    /// Runs `body` once the steps asked for before it are made.
    func enqueue(_ body: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await body()
        }
    }

    /// `body` in its turn, and what it returns.
    func make<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> T {
        await withCheckedContinuation { continuation in
            enqueue { await continuation.resume(returning: body()) }
        }
    }

    /// Returns once every step asked for is made.
    func made() async {
        while let tail {
            await tail.value
            if self.tail == tail {
                break
            }
        }
    }
}

/// One of Library's renames, moves, copies or moves to the Trash, as Undo takes it back and Redo makes it again. A
/// step whose batch was stopped is what the batch did: its photos, and its title saying how many.
@MainActor
final class LibraryFileStep {
    enum Kind {
        case rename([PhotoRename])
        /// The photos asked for, by index ID, and the folder they go to.
        case move([Int64], URL)
        /// The photos asked for, by index ID, and the folder their copies go to.
        case copy([Int64], URL)
        /// The photos asked for and their pairs, by index ID, which go to the Trash.
        case trash([Int64])
    }

    private(set) var kind: Kind
    /// Each photo, by index ID, and its path before and after the step, none in the Trash; a copy's photos stay where
    /// they are.
    private(set) var photos: [(id: Int64, from: String, to: String?)]
    /// The batch that made it last, for its Undo.
    var batch: UUID?
    /// The photos as the folders shown listed them before it, and their content keys, by index ID: a move's Undo
    /// shows them again.
    var items: [Int64: LibraryItem] = [:]
    var keys: [Int64: ContentKey] = [:]
    /// The photos selected and the active one, before it.
    var selected: Set<URL> = []
    var active: URL?
    /// Its turn in Library's Undo and Redo (`EditorModel+LibraryUndo`).
    var turn = 0
    /// The versions a step to the Trash took out of their files' sidecars, their files staying (LIB-48).
    var versions: [RemovedVersion] = []

    init(kind: Kind, photos: [(id: Int64, from: String, to: String?)]) {
        self.kind = kind
        self.photos = photos
    }

    /// As Undo and the activity log name it: "Rename 12 Photos", "Copy 3 Photos to Picked".
    var title: String {
        let count = Set(photos.map(\.id)).count
        let photos = "\(count) Photo\(count == 1 ? "" : "s")"
        return switch kind {
        case .rename: "Rename \(photos)"
        case let .move(_, folder): "Move \(photos) to \(folder.lastPathComponent)"
        case let .copy(_, folder): "Copy \(photos) to \(folder.lastPathComponent)"
        case .trash where versions.isEmpty: "Move \(photos) to the Trash"
        case .trash:
            [
                count == 0 ? nil : "Move \(photos) to the Trash",
                "Remove \(versions.count) Version\(versions.count == 1 ? "" : "s")",
            ].compactMap(\.self).joined(separator: " and ")
        }
    }

    var isCopy: Bool {
        if case .copy = kind {
            return true
        }
        return false
    }

    var isTrash: Bool {
        if case .trash = kind {
            return true
        }
        return false
    }

    /// The step as a batch that stopped partway left it: the photos `done`, with their pairs.
    func keep(_ done: Set<Int64>) {
        photos = photos.filter { done.contains($0.id) }
        switch kind {
        case let .rename(renames): kind = .rename(renames.filter { done.contains($0.id) })
        case let .move(ids, folder): kind = .move(ids.filter(done.contains), folder)
        case let .copy(ids, folder): kind = .copy(ids.filter(done.contains), folder)
        case let .trash(ids): kind = .trash(ids.filter(done.contains))
        }
    }
}

/// A batch's progress for the main thread: the latest only, at most ten times a second.
final class FileProgressRelay: Sendable {
    private struct State {
        var latest: FileProgress?
        var waiting = false
        var shown: ContinuousClock.Instant?
    }

    static let interval = Duration.milliseconds(100)
    private let state = Mutex(State())
    private let deliver: @MainActor @Sendable (FileProgress) -> Void

    init(_ deliver: @escaping @MainActor @Sendable (FileProgress) -> Void) {
        self.deliver = deliver
    }

    func send(_ progress: FileProgress) {
        let delay = state.withLock { state -> Duration? in
            state.latest = progress
            guard !state.waiting else { return nil }
            state.waiting = true
            return state.shown.map { max($0 + Self.interval - .now, .zero) } ?? .zero
        }
        guard let delay else { return }
        Task { @MainActor [self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            let latest = state.withLock { state -> FileProgress? in
                state.waiting = false
                state.shown = .now
                return state.latest
            }
            if let latest {
                deliver(latest)
            }
        }
    }
}
