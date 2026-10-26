import Foundation
import Observation
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes

/// The editor, to Settings Sync: a photo open in it is changed there, never by writing its sidecar behind it: the edit
/// open as a step of its history, and its other edits (LIB-48) in what saving writes for them.
@MainActor
protocol SyncEditor: AnyObject {
    /// Whether `url` is open in the editor, or opening there.
    func isOpen(_ url: URL) -> Bool
    /// `change` made to `photo`, one of the edits of the photo open in the editor, once it has opened: the edit open as
    /// a step titled `title`; another only by `.edit`, `.change` giving back what the editor holds of it.
    func apply(_ change: SettingsSync.EditorChange, to photo: PhotoAddress, title: String) async
        -> SettingsSync.EditorOutcome
}

/// Changes photos that aren't open, one at a time in the background: Sync Settings, Paste onto a
/// selection, Update AI Masks and mask presets across it
/// (`docs/plans/2026-10-02-copy-paste-sync-design.md`).
///
/// For each photo it reads the sidecar, pastes, recomputes the AI masks the paste brought (and an
/// Auto white balance) in an engine of its own, so the open photo is never disturbed, and saves
/// with a history step. A photo whose sidecar a newer Redlamp wrote, or this version can't read,
/// is left alone, and so is one edited between the read and the save. The photo open in the
/// editor, or opening there, when the batch reaches it or is about to save it, is changed by the
/// editor instead (`SyncEditor`). Batches run one after another. Undo puts back what the last
/// batch changed, on every photo not edited since.
///
/// A version of a photo's edit is a photo of its own (LIB-48), known by its address: the edits of one file that a
/// batch's photos read at a time hold are read and written together, one write a sidecar, each in its own edit
/// (`sidecar[edit: version]`) with a history session of its own.
///
/// While Auto Sync is on, the batches that follow the open photo's steps make a run (`AutoSyncRun`):
/// each photo keeps one history session for it, and Undo, Redo and history clicks on the open
/// photo give each photo back its edit at that step.
@MainActor
@Observable
public final class SettingsSync {
    public enum Change {
        /// `selection` of `source`, pasted.
        case paste(EditRecipe, SettingsSelection)
        /// Every AI mask computed again with today's models.
        case updateAIMasks
        /// A mask preset added as a new mask, its AI masks computed for each photo.
        case applyMaskPreset(MaskPreset)
        /// Each photo's sensor dust (found across the selection) healed, a source found for each speck: the same for
        /// each of a file's edits.
        case healDust([URL: [DetectedSpot]])
        /// Each photo of the run as the open photo's step left it: its edit before the run, with
        /// `source` (the open photo's edit at that step) pasted for what the run's steps carried
        /// to it, but for those undone (the open photo's steps after it).
        case follow(EditRecipe, Set<UUID>)
        /// Each photo's Lightroom edit as Convert Lightroom Edits… converted it, written where the photo still
        /// has no edit in Redlamp (EDT-12).
        case convertLightroom([URL: LightroomPhotoImport])
    }

    /// What a batch asks of the photo open in the editor.
    enum EditorChange {
        /// The batch's change, made to the edit open; another of the photo's edits answers `.otherEdit`.
        case change(Change)
        /// `recipe` for the edit, if the editor's is still `over`: Undo, following the open photo's history, and
        /// what the batch made of another of the photo's edits than the one open, which `session` records.
        case edit(EditRecipe, over: EditRecipe, session: HistorySession? = nil)
    }

    enum EditorOutcome {
        /// Made as a step of the photo's history; the edit it left (nil: nothing changed).
        case applied(EditRecipe?)
        /// Made to another of the photo's edits than the one open (LIB-48), whose history the editor doesn't hold:
        /// the batch's Undo puts it back.
        case appliedBeside(EditRecipe)
        /// Left as it is: edited since, or read-only.
        case left
        /// It isn't open in the editor (any more): the batch saves it.
        case notOpen
        /// Another of the photo's edits than the one open, as the editor holds it: the batch works its change out,
        /// and hands it back as `.edit`.
        case otherEdit(EditRecipe)
    }

    /// One of the open photo's steps reaching the rest of the selection while Auto Sync is on.
    struct RunStep {
        /// The open photo's history session.
        var session: UUID
        var id: UUID
        /// The step's title in the open photo's history ("Exposure").
        var title: String
        /// What it carries: an Auto Sync step's changes, or a paste's items and the masks it brought.
        var carried: SettingsSelection
    }

    /// The open photo's steps that reached the other photos while Auto Sync was on, and what each
    /// of those photos was before them, so following the open photo's history gives each its own
    /// edit back.
    private struct AutoSyncRun {
        var session: UUID
        /// What each step carried, by the step's id.
        var steps: [UUID: SettingsSelection] = [:]
        var photos: [PhotoAddress: Member] = [:]

        struct Member {
            /// Its edit before the run first wrote it (nil: it had no sidecar).
            var base: EditRecipe?
            /// The steps written to it.
            var reached: Set<UUID>
            /// Its edit as the run last wrote it, read back: any other is an edit made since.
            var last: EditRecipe
            /// The run's history session in its sidecar.
            var session: HistorySession
        }

        /// What the steps that reached `member` carried to it, but for those `undone`.
        func carried(to member: Member, without undone: Set<UUID>) -> SettingsSelection {
            member.reached.subtracting(undone).compactMap { steps[$0] }.reduce(.nothing) { $0.union($1) }
        }
    }

    public struct Progress: Equatable, Sendable {
        public var title: String
        public var done: Int
        public var total: Int
    }

    public private(set) var progress: Progress?
    /// Auto Sync: each step on the open photo repeats on the rest of the selection.
    public var isAutoSyncing = false {
        didSet {
            if !isAutoSyncing {
                run = nil
            }
        }
    }

    /// How the last batch went, when there is something to say ("1 photo was left alone…").
    public private(set) var report: String?
    public var canUndo: Bool {
        !written.isEmpty && progress == nil
    }

    /// The batch started last, which Undo takes back while it `canUndo` (`run` returns each batch's).
    @ObservationIgnored private(set) var lastBatch: UUID?

    /// An engine for photos that aren't open; nil leaves AI masks and Auto white balance as pasted.
    @ObservationIgnored var makeEngine: () -> (any EditingEngine)?
    /// The exposure anchor a photo's edit gets under Redlamp Reproduction (nil when it isn't raw),
    /// set by the editor; without it, the typical anchor.
    @ObservationIgnored var photoAnchor: (@MainActor (URL, Int) async -> ExposureAnchor?)?
    /// Where each photo's sidecar is read and written: the editor's, set by it.
    @ObservationIgnored var sidecars: SidecarPlacement
    /// The library's locator for photos in its folders; any other photo's sidecar is beside it.
    var store: SidecarStore {
        SidecarStore(locator: sidecars.locator)
    }

    /// The editor's saves: a photo just left may still be on its way to disk. The batch's own
    /// saves go through their queue too, after those asked for before them.
    @ObservationIgnored var saves: SaveQueue?
    @ObservationIgnored weak var editor: (any SyncEditor)?
    /// Waited for before each write of a photo's sidecar, which holds all its edits (tests change the photo here).
    @ObservationIgnored var beforeWriting: @MainActor (URL) async -> Void = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The batch's saves on their way, by photo: the editor reads a photo it opens after them.
    @ObservationIgnored private var writing: [URL: Task<Void, Never>] = [:]
    /// The last batch: each edit before (nil: its photo had no sidecar) and after, and the sidecars it made where there
    /// were none, as read back.
    @ObservationIgnored private var before: [PhotoAddress: EditRecipe?] = [:]
    @ObservationIgnored private var written: [PhotoAddress: EditRecipe] = [:]
    @ObservationIgnored private var made: [URL: Sidecar] = [:]
    @ObservationIgnored private var title = ""
    /// Batches that came while one ran, in order; Auto Sync's steps are gathered into one.
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var run: AutoSyncRun?
    /// A photo's history session for a run keeps this many steps at most, as the editor's does.
    static let maximumRunSteps = 500
    /// The photos a batch reads the addresses of at a time, for a large source's selection, and whose edits of one
    /// file it writes together.
    static let batch = 256

    private struct Job {
        let id = UUID()
        var change: Change
        var photos: SelectedPhotos
        var title: String
        /// The step's title in each photo's history.
        var stepTitle: String
        var isAutoSync = false
        /// The run the batch belongs to, and the open photo's steps it carries.
        var session: UUID?
        var steps: [UUID] = []
        var done: (PhotoAddress, EditRecipe) -> Void

        var isFollow: Bool {
            if case .follow = change {
                true
            } else {
                false
            }
        }
    }

    /// How a batch's save of one edit went.
    private enum Saving: Sendable {
        /// As read back.
        case saved(EditRecipe)
        case editedSince
        /// Protected, or it can't be read now.
        case unreadable
        case failed
    }

    /// A batch's save of one photo's edits, in one write of its sidecar: how each went, and the sidecar as read back.
    private struct Saved: Sendable {
        var edits: [PhotoAddress: Saving]
        var sidecar: Sidecar?
    }

    /// One edit a batch writes: as it was, as it becomes, and the history session that records it.
    private struct EditWrite: Sendable {
        var photo: PhotoAddress
        var original: EditRecipe
        var next: EditRecipe
        var session: HistorySession
    }

    /// One edit Undo puts back: as the batch left it, as it was before (nil: its photo had no sidecar), and the
    /// history session that records it.
    private struct PutBack: Sendable {
        var photo: PhotoAddress
        var after: EditRecipe
        var previous: EditRecipe?
        var session: HistorySession
    }

    /// How Undo's putting back of one edit went.
    private enum PuttingBack: Sendable {
        case done(EditRecipe)
        case editedSince
        case unreadable

        var isDone: Bool {
            if case .done = self {
                true
            } else {
                false
            }
        }
    }

    /// Where one photo's changes landed: what the batch saved, and what the editor made, each edit's by its address.
    private struct Landed<T> {
        var saved: T?
        var inEditor: [PhotoAddress: EditorOutcome] = [:]
    }

    /// What a batch left alone, and why, for its report.
    private struct Tally {
        var skipped = 0
        var editedSince = 0
        var changedMeanwhile = 0
        var failedMasks = 0
        var presetsNotMade = 0
        var presetsFull = 0
        var editedInRedlamp = 0
    }

    /// A change worked out for one photo: the edit it leaves, how many of the AI masks it
    /// recomputed couldn't be, and why a preset's mask wasn't added, when it wasn't.
    private struct Applied {
        var recipe: EditRecipe
        var failedMasks = 0
        var missedPreset: MissedPreset?
    }

    private enum MissedPreset {
        /// An AI mask it needs couldn't be computed for the photo.
        case notMade
        /// The photo has as many masks as it can.
        case full
    }

    init(sidecars: SidecarPlacement = SidecarPlacement(), makeEngine: @escaping () -> (any EditingEngine)?) {
        self.sidecars = sidecars
        self.makeEngine = makeEngine
    }

    /// Starts `change` on `photos`, recorded in each one's history as `title`, or queues it after
    /// the batch running; `done` is told of each photo changed. With `step` (a paste onto the
    /// selection) and Auto Sync on, the batch joins the run, so the open photo's Undo takes it
    /// back too.
    @discardableResult
    func run(
        _ change: Change, on photos: [PhotoAddress], title: String, step: RunStep? = nil,
        done: @escaping (PhotoAddress, EditRecipe) -> Void,
    ) -> UUID {
        run(change, on: SelectedPhotos(photos), title: title, step: step, done: done)
    }

    /// `run` on a selection's photos, which a large source's are read for a batch at a time as the batch reaches them.
    @discardableResult
    func run(
        _ change: Change, on photos: SelectedPhotos, title: String, step: RunStep? = nil,
        done: @escaping (PhotoAddress, EditRecipe) -> Void,
    ) -> UUID {
        var job = Job(change: change, photos: photos, title: title, stepTitle: title, done: done)
        if let step, isAutoSyncing {
            record(step)
            job.session = step.session
            job.steps = [step.id]
        }
        enqueue(job)
        return job.id
    }

    public func cancel() {
        queue = []
        task?.cancel()
    }

    /// One Auto Sync step of `source`, onto `photos`; gathered with the steps queued just before it.
    func autoSync(
        _ source: EditRecipe, step: RunStep, on photos: [PhotoAddress],
        done: @escaping (PhotoAddress, EditRecipe) -> Void,
    ) {
        autoSync(source, step: step, on: SelectedPhotos(photos), done: done)
    }

    func autoSync(
        _ source: EditRecipe, step: RunStep, on photos: SelectedPhotos,
        done: @escaping (PhotoAddress, EditRecipe) -> Void,
    ) {
        guard !step.carried.isEmpty, photos.count > 0 else { return }
        record(step)
        let stepTitle = "Auto Sync: \(step.title)"
        if progress != nil, let last = queue.last, last.isAutoSync, last.session == step.session,
           case let .paste(_, gathered) = last.change {
            queue[queue.count - 1].change = .paste(source, gathered.union(step.carried))
            queue[queue.count - 1].photos = photos
            queue[queue.count - 1].steps.append(step.id)
            if !last.stepTitle.contains(step.title) {
                queue[queue.count - 1].stepTitle = "\(last.stepTitle), \(step.title)"
            }
            return
        }
        enqueue(Job(
            change: .paste(source, step.carried), photos: photos, title: "Auto Sync", stepTitle: stepTitle,
            isAutoSync: true, session: step.session, steps: [step.id], done: done,
        ))
    }

    /// The open photo moved through its history (Undo, Redo, a click) to the step whose edit is
    /// `source`, the steps after it being `undone`: each photo of the run in `photos` follows.
    func follow(
        _ source: EditRecipe, undone: Set<UUID>, session: UUID, on photos: [PhotoAddress], title: String,
        done: @escaping (PhotoAddress, EditRecipe) -> Void,
    ) {
        follow(source, undone: undone, session: session, on: SelectedPhotos(photos), title: title, done: done)
    }

    /// `follow` on a selection's photos: those a large source's aren't known by address yet are told from the run's as
    /// the batch reaches them.
    func follow(
        _ source: EditRecipe, undone: Set<UUID>, session: UUID, on photos: SelectedPhotos, title: String,
        done: @escaping (PhotoAddress, EditRecipe) -> Void,
    ) {
        guard isAutoSyncing, let run, run.session == session, !run.photos.isEmpty else { return }
        let members = photos.addresses.map { SelectedPhotos($0.filter { run.photos[$0] != nil }) } ?? photos
        guard members.count > 0 else { return }
        let job = Job(
            change: .follow(source, undone), photos: members, title: title, stepTitle: title, session: session,
            done: done,
        )
        if progress != nil, let last = queue.last, last.isFollow, last.session == session {
            queue[queue.count - 1] = job
            return
        }
        enqueue(job)
    }

    /// The open photo's steps that a new step replaced, after an Undo: none of them applies again.
    func forget(_ steps: some Sequence<UUID>) {
        for id in steps {
            run?.steps[id] = nil
        }
    }

    /// The open photo's history was cleared: its earlier steps can't be followed back.
    func endRun() {
        run = nil
    }

    private func record(_ step: RunStep) {
        if run?.session != step.session {
            run = AutoSyncRun(session: step.session)
        }
        run?.steps[step.id] = step.carried
    }

    private func enqueue(_ job: Job) {
        guard job.photos.count > 0 else { return }
        if progress == nil {
            start(job)
        } else {
            queue.append(job)
        }
    }

    private func start(_ job: Job) {
        progress = Progress(title: job.title, done: 0, total: job.photos.count)
        title = job.title
        lastBatch = job.id
        report = nil
        before = [:]
        written = [:]
        made = [:]
        task = Task { [weak self] in
            await self?.process(job)
        }
    }

    /// Waits for the batch running, if any.
    func idle() async {
        await task?.value
    }

    /// Returns once the batch's save of `url`, if one is on its way, has landed.
    func wait(for url: URL) async {
        await writing[url]?.value
    }

    /// `save` run on the editor's save queue for the edits `changes` name, unless `url` is open in the editor, which
    /// makes each change instead; those of a photo it stops having open are saved. Between the check and the save being
    /// registered there is no suspension, so the editor opening it reads it after the save.
    private func land<T: Sendable>(
        _ url: URL, _ changes: [(PhotoAddress, EditorChange)], title: String,
        _ save: @escaping @Sendable (Set<PhotoAddress>, SidecarStore) -> T,
    ) async -> Landed<T> {
        var landed = Landed<T>()
        var left = changes
        while let editor, editor.isOpen(url), !left.isEmpty {
            var notOpen: [(PhotoAddress, EditorChange)] = []
            for (photo, change) in left {
                let outcome = await editor.apply(change, to: photo, title: title)
                if case .notOpen = outcome {
                    notOpen.append((photo, change))
                } else {
                    landed.inEditor[photo] = outcome
                }
            }
            left = notOpen
        }
        guard !left.isEmpty else { return landed }
        let photos = Set(left.map(\.0))
        let (store, saves) = (store, saves)
        let saving = Task.detached {
            guard let saves else { return save(photos, store) }
            return await saves.read { save(photos, store) }
        }
        let landing = Task { _ = await saving.value }
        writing[url] = landing
        landed.saved = await saving.value
        if writing[url] == landing {
            writing[url] = nil
        }
        return landed
    }

    /// Puts back every edit of the last batch not edited since, as a batch of its own: batches
    /// started meanwhile wait for it.
    func undo(done: @escaping (PhotoAddress, EditRecipe) -> Void) {
        guard canUndo else { return }
        let (written, before, made) = (written, before, made)
        let title = "Undo \(title)"
        self.written = [:]
        self.before = [:]
        self.made = [:]
        progress = Progress(title: title, done: 0, total: written.count)
        report = nil
        task = Task { [weak self] in
            await self?.putBack(written, before: before, made: made, title: title, done: done)
        }
    }

    private func putBack(
        _ written: [PhotoAddress: EditRecipe], before: [PhotoAddress: EditRecipe?], made: [URL: Sidecar],
        title: String, done: (PhotoAddress, EditRecipe) -> Void,
    ) async {
        var unread = 0
        for (url, photos) in Self.byFile(Array(written.keys)) {
            guard !Task.isCancelled else { break }
            defer { progress?.done += photos.count }
            let edits = photos.compactMap { photo -> PutBack? in
                guard let after = written[photo], let previous = before[photo] else { return nil }
                let session = Self.session(previous ?? EditRecipe(), from: after, of: photo.version, title: title)
                return PutBack(photo: photo, after: after, previous: previous, session: session)
            }
            await saves?.wait(for: url)
            await beforeWriting(url)
            let changes = edits.map { (
                $0.photo,
                EditorChange.edit($0.previous ?? EditRecipe(), over: $0.after, session: $0.session),
            ) }
            let landed = await land(url, changes, title: title) { [made = made[url]] photos, store in
                Self.puttingBack(edits.filter { photos.contains($0.photo) }, made: made, for: url, in: store)
            }
            for edit in edits {
                switch landed.inEditor[edit.photo] {
                case let .applied(recipe?)?, let .appliedBeside(recipe)?:
                    run?.photos[edit.photo] = nil
                    done(edit.photo, recipe)
                    continue
                case .some:
                    continue
                case nil:
                    break
                }
                switch landed.saved?[edit.photo] {
                case let .done(recipe)?:
                    run?.photos[edit.photo] = nil
                    done(edit.photo, recipe)
                case .unreadable?:
                    unread += 1
                case .editedSince?, nil:
                    continue
                }
            }
        }
        let photos = "\(unread) photo\(unread == 1 ? "" : "s")"
        let parts = [
            Task.isCancelled ? "Stopped before the end." : nil,
            unread > 0 ? "\(photos) couldn't be put back: the edit can't be read." : nil,
        ].compactMap(\.self)
        report = parts.isEmpty ? nil : parts.joined(separator: " ")
        progress = nil
        if !queue.isEmpty {
            start(queue.removeFirst())
            await task?.value
        }
    }

    /// The edits `edits` name of the photo at `url` given back what they were, each still as the batch left it, in one
    /// read and one write on the save queue. A sidecar the batch made, `made`, still as it made it, is removed.
    private nonisolated static func puttingBack(
        _ edits: [PutBack], made: Sidecar?, for url: URL, in store: SidecarStore,
    ) -> [PhotoAddress: PuttingBack] {
        guard store.protection(for: url) == nil, case let .success(read) = Result(catching: {
            try store.loadThrowing(for: url)
        }) else { return Dictionary(edits.map { ($0.photo, .unreadable) }) { first, _ in first } }
        guard var sidecar = read
        else { return Dictionary(edits.map { ($0.photo, .editedSince) }) { first, _ in first } }
        var results: [PhotoAddress: PuttingBack] = [:]
        for edit in edits {
            guard sidecar[edit: edit.photo.version]?.recipe == edit.after else {
                results[edit.photo] = .editedSince
                continue
            }
            if edit.previous == nil, let made, sidecar.hasSameContent(as: made) {
                store.delete(for: url)
                return [edit.photo: .done(EditRecipe())]
            }
            // Rated, say, since the sync made it: only the edit goes back.
            sidecar.change(edit.photo.version, to: edit.previous ?? EditRecipe(), session: edit.session)
            results[edit.photo] = .done(edit.previous ?? EditRecipe())
        }
        if results.values.contains(where: \.isDone) {
            sidecar.modified = Date()
            try? store.saveOrRemove(sidecar, for: url)
        }
        return results
    }

    /// `photos` by file, in the order of each file's first, each file's in their order: a batch reads and writes the
    /// edits of one file together.
    static func byFile(_ photos: [PhotoAddress]) -> [(url: URL, photos: [PhotoAddress])] {
        var files: [URL] = []
        var edits: [URL: [PhotoAddress]] = [:]
        for photo in photos {
            guard let found = edits[photo.url] else {
                files.append(photo.url)
                edits[photo.url] = [photo]
                continue
            }
            if !found.contains(photo) {
                edits[photo.url]?.append(photo)
            }
        }
        return files.map { ($0, edits[$0] ?? []) }
    }

    private func process(_ job: Job) async {
        var engine: (any EditingEngine)?
        var tally = Tally()
        let inRun = job.session != nil && run?.session == job.session
        var batches = job.photos.batches(of: Self.batch)
        photos: while !Task.isCancelled, let batch = await batches.next() {
            for (url, photos) in Self.byFile(batch) {
                guard !Task.isCancelled else { break photos }
                await process(photos, of: url, job, inRun: inRun, engine: &engine, tally: &tally)
                progress?.done += photos.count
            }
        }
        var preset: (name: String, notMade: Int, full: Int)?
        if case let .applyMaskPreset(applied) = job.change {
            preset = (applied.name, tally.presetsNotMade, tally.presetsFull)
        }
        report = Self.report(
            skipped: tally.skipped, editedSince: tally.editedSince, changedMeanwhile: tally.changedMeanwhile,
            failedMasks: tally.failedMasks, preset: preset, cancelled: Task.isCancelled,
        )
        if tally.editedInRedlamp > 0 {
            let photos = "\(tally.editedInRedlamp) photo\(tally.editedInRedlamp == 1 ? " was" : "s were")"
            report = [report, "\(photos) left alone: edited in Redlamp since the report."].compactMap(\.self)
                .joined(separator: " ")
        }
        progress = nil
        if !queue.isEmpty {
            start(queue.removeFirst())
            await task?.value
        }
    }

    /// `job`'s change to `photos`, edits of the photo at `url`: made by the editor while it has the photo open,
    /// otherwise read, worked out and saved in one write of its sidecar.
    private func process(
        _ photos: [PhotoAddress], of url: URL, _ job: Job, inRun: Bool, engine: inout (any EditingEngine)?,
        tally: inout Tally,
    ) async {
        var photos = photos
        if job.isFollow, job.photos.addresses == nil {
            // A large selection's photos aren't told from the run's before the batch reaches them.
            photos.removeAll { run?.photos[$0] == nil }
        }
        if !job.isFollow, let editor, editor.isOpen(url) {
            var left: [PhotoAddress] = []
            for photo in photos {
                let outcome = await editor.apply(.change(job.change), to: photo, title: job.stepTitle)
                switch outcome {
                case .notOpen:
                    left.append(photo)
                case let .otherEdit(held):
                    await changeBeside(photo, held: held, job, inRun: inRun, engine: &engine, tally: &tally)
                default:
                    madeInEditor(photo, outcome, job, &tally)
                }
            }
            photos = left
        }
        guard !photos.isEmpty else { return }
        await saves?.wait(for: url)
        // Sidecars are read and written off the main thread: on a busy disk one write can take seconds.
        let store = store
        // Nil when it's protected; a failure when it's there but can't be read now.
        let read = await Task.detached { () -> Result<Sidecar?, any Error>? in
            store.protection(for: url) == nil ? Result { try store.loadThrowing(for: url) } : nil
        }.value
        guard case let .success(existing)? = read else {
            tally.skipped += photos.count
            return
        }
        if case .convertLightroom = job.change, existing?.recipe.isPristine == false
            || existing?.versions.isEmpty == false {
            tally.editedInRedlamp += photos.count
            return
        }
        var writes: [EditWrite] = []
        var members: [PhotoAddress: AutoSyncRun.Member] = [:]
        for photo in photos {
            // A version its sidecar no longer has was removed while the batch ran.
            guard let original = existing.map({ $0[edit: photo.version]?.recipe }) ?? (photo.version == nil
                ? EditRecipe() : nil)
            else {
                tally.changedMeanwhile += 1
                continue
            }
            let worked = await work(
                job, on: photo, original: original, opened: existing != nil, inRun: inRun, engine: &engine,
                tally: &tally,
            )
            if case let (write, member)? = worked {
                writes.append(write)
                members[photo] = member
            }
        }
        guard !writes.isEmpty else { return }
        await beforeWriting(url)
        let changes = writes.map { write in
            (
                write.photo,
                job.isFollow
                    ? EditorChange.edit(write.next, over: write.original, session: write.session) : .change(job.change),
            )
        }
        let landed = await land(url, changes, title: job.stepTitle) { [writes] photos, store in
            Self.saving(writes.filter { photos.contains($0.photo) }, for: url, in: store)
        }
        let hadSidecar = existing != nil
        for write in writes {
            let photo = write.photo
            if let outcome = landed.inEditor[photo] {
                switch outcome {
                case let .otherEdit(held):
                    // Opened in the editor while the batch worked it out.
                    await changeBeside(
                        photo, held: held, worked: (write, members[photo]), job, inRun: inRun, engine: &engine,
                        tally: &tally,
                    )
                case let .appliedBeside(recipe):
                    note(
                        photo,
                        before: hadSidecar ? write.original : nil,
                        written: recipe,
                        member: members[photo],
                        session: write.session,
                        job,
                        inRun: inRun,
                    )
                    job.done(photo, recipe)
                default:
                    madeInEditor(photo, outcome, job, &tally)
                }
                continue
            }
            switch landed.saved?.edits[photo] {
            case let .saved(recipe)?:
                note(
                    photo,
                    before: hadSidecar ? write.original : nil,
                    written: recipe,
                    member: members[photo],
                    session: write.session,
                    job,
                    inRun: inRun,
                )
                job.done(photo, write.next)
            case .unreadable?:
                tally.skipped += 1
            case .editedSince?:
                tally.changedMeanwhile += 1
            case .failed?, nil:
                continue
            }
        }
        if !hadSidecar, let sidecar = landed.saved?.sidecar {
            made[url] = sidecar
        }
    }

    /// What `job` makes of `photo`'s edit, `original`, and its member of the run: nil when it changes nothing, or the
    /// run has no part of it. `opened` says the photo has a sidecar.
    private func work(
        _ job: Job, on photo: PhotoAddress, original: EditRecipe, opened: Bool, inRun: Bool,
        engine: inout (any EditingEngine)?, tally: inout Tally,
    ) async -> (EditWrite, AutoSyncRun.Member?)? {
        // The run goes on for a photo it last left as it is; otherwise it starts over from here.
        let member = inRun ? run?.photos[photo].flatMap { $0.last == original ? $0 : nil } : nil
        var change = job.change
        var start = original
        if case let .follow(source, undone) = job.change {
            guard let run, let member else {
                if run?.photos[photo] != nil {
                    tally.editedSince += 1
                }
                return nil
            }
            change = .paste(source, run.carried(to: member, without: undone))
            start = member.base ?? EditRecipe()
        }
        guard let applied = await applying(change, to: start, current: original, photo.url, &engine) else {
            return nil
        }
        let next = applied.recipe
        tally.failedMasks += applied.failedMasks
        switch applied.missedPreset {
        case .notMade: tally.presetsNotMade += 1
        case .full: tally.presetsFull += 1
        case nil: break
        }
        guard next != original else {
            if var member {
                member.reached.formUnion(job.steps)
                run?.photos[photo] = member
            }
            return nil
        }
        var session = member?.session ?? HistorySession(
            steps: [HistoryStep(action: .open, title: opened ? "Opened" : "Import", recipe: original)],
            versionID: photo.version,
        )
        session.steps.append(HistoryStep(action: change.action, title: job.stepTitle, recipe: next))
        if session.steps.count > Self.maximumRunSteps {
            session.steps.removeFirst(session.steps.count - Self.maximumRunSteps)
        }
        return (EditWrite(photo: photo, original: original, next: next, session: session), member)
    }

    /// `job`'s change to `photo`, one of the edits of the photo open in the editor other than the one open there, which
    /// holds it as `held`: worked out here, unless `worked` was made from the same, and changed in the editor.
    private func changeBeside(
        _ photo: PhotoAddress, held: EditRecipe, worked: (EditWrite, AutoSyncRun.Member?)? = nil, _ job: Job,
        inRun: Bool, engine: inout (any EditingEngine)?, tally: inout Tally,
    ) async {
        var made = worked.flatMap { $0.0.original == held ? $0 : nil }
        if made == nil {
            made = await work(
                job,
                on: photo,
                original: held,
                opened: true,
                inRun: inRun,
                engine: &engine,
                tally: &tally,
            )
        }
        guard case let (write, member)? = made, let editor else { return }
        let outcome = await editor.apply(
            .edit(write.next, over: held, session: write.session), to: photo, title: job.stepTitle,
        )
        switch outcome {
        case let .appliedBeside(recipe):
            note(photo, before: held, written: recipe, member: member, session: write.session, job, inRun: inRun)
            job.done(photo, recipe)
        case .left:
            tally.changedMeanwhile += 1
        default:
            madeInEditor(photo, outcome, job, &tally)
        }
    }

    /// The editor made `photo`'s change, or left it as it is.
    private func madeInEditor(_ photo: PhotoAddress, _ outcome: EditorOutcome, _ job: Job, _ tally: inout Tally) {
        run?.photos[photo] = nil
        switch outcome {
        case let .applied(recipe?), let .appliedBeside(recipe):
            job.done(photo, recipe)
        case .left where job.isFollow:
            tally.editedSince += 1
        case .left:
            tally.skipped += 1
        case .applied(nil), .notOpen, .otherEdit:
            break
        }
    }

    /// What the batch wrote to `photo`, for Undo and the run: its edit before (nil: its photo had no sidecar), as
    /// written, and its history session.
    private func note(
        _ photo: PhotoAddress, before original: EditRecipe?, written recipe: EditRecipe, member: AutoSyncRun.Member?,
        session: HistorySession, _ job: Job, inRun: Bool,
    ) {
        if before.index(forKey: photo) == nil {
            // updateValue: a photo without a sidecar keeps its nil (a subscript would drop the key).
            before.updateValue(original, forKey: photo)
        }
        written[photo] = recipe
        if inRun {
            run?.photos[photo] = AutoSyncRun.Member(
                base: member.map(\.base) ?? original, reached: (member?.reached ?? []).union(job.steps),
                last: recipe, session: session,
            )
        } else {
            run?.photos[photo] = nil
        }
    }

    /// `writes` saved for the photo at `url` in one write of its sidecar, each edit that is still as it was, keeping
    /// what else changed since (a rating, say). Read and written in one go on the save queue, and never over a sidecar
    /// that can't be read.
    private nonisolated static func saving(_ writes: [EditWrite], for url: URL, in store: SidecarStore) -> Saved {
        guard store.protection(for: url) == nil, case let .success(current) = Result(catching: {
            try store.loadThrowing(for: url)
        }) else { return Saved(edits: Dictionary(writes.map { ($0.photo, .unreadable) }) { first, _ in first }) }
        var sidecar = current ?? Sidecar(recipe: EditRecipe())
        var edits: [PhotoAddress: Saving] = [:]
        for write in writes {
            guard sidecar[edit: write.photo.version]?.recipe == write.original else {
                edits[write.photo] = .editedSince
                continue
            }
            sidecar.change(write.photo.version, to: write.next, session: write.session)
            edits[write.photo] = .saved(write.next)
        }
        let saved = writes.filter {
            if case .saved = edits[$0.photo] {
                true
            } else {
                false
            }
        }
        guard !saved.isEmpty else { return Saved(edits: edits) }
        sidecar.modified = Date()
        guard (try? store.save(sidecar, for: url)) != nil else {
            for write in saved {
                edits[write.photo] = .failed
            }
            return Saved(edits: edits)
        }
        // As read back, so Undo can tell the photo hasn't been edited since (dates round).
        let back = store.load(for: url) ?? sidecar
        for write in saved {
            edits[write.photo] = .saved(back[edit: write.photo.version]?.recipe ?? write.next)
        }
        return Saved(edits: edits, sidecar: back)
    }

    /// `change` made to `start` for the photo at `url`, whose edit is `current`: the AI masks it
    /// brings, and an Auto white balance, computed for that photo. Nil when it changes nothing.
    private func applying(
        _ change: Change, to start: EditRecipe, current: EditRecipe, _ url: URL, _ engine: inout (any EditingEngine)?,
    ) async -> Applied? {
        var next = start
        var masks: Set<UUID>?
        var autoWhiteBalance = false
        switch change {
        case let .paste(source, selection):
            let pasted = start.pasting(source, selection)
                .reusingAIMasks(from: current, in: EditRecipe.pastedMasks(from: source, selection))
            next = await anchored(pasted.recipe, url)
            masks = pasted.recompute
            if selection.items.contains("whiteBalance") {
                // As Shot is the photo's own, read when it opens; Auto is measured for it.
                if next.whiteBalanceMode == .asShot {
                    next.reset([.temperature, .tint])
                }
                autoWhiteBalance = next.whiteBalanceMode == .auto
            }
        case .updateAIMasks:
            masks = nil
        case let .applyMaskPreset(preset):
            masks = []
            guard next.masks.count < MaskLayer.maximumLayers else { return Applied(recipe: start, missedPreset: .full) }
            // Computed only on this photo: an engine that couldn't open it still has another open.
            var opened: (any EditingEngine)?
            if !preset.aiKinds.isEmpty {
                engine = engine ?? makeEngine()
                if let engine, await (try? engine.open(url)) != nil {
                    opened = engine
                }
            }
            guard let mask = try? await EditorModel.mask(of: preset, engine: opened) else {
                return Applied(recipe: start, missedPreset: .notMade)
            }
            next.masks.append(mask)
        case let .healDust(found):
            masks = []
            let specks = found[url] ?? []
            guard !specks.isEmpty else { return nil }
            engine = engine ?? makeEngine()
            var opened = false
            if let engine {
                opened = await (try? engine.open(url)) != nil
            }
            for speck in specks {
                var spot = RetouchSpot(center: speck.center, source: speck.center, radius: speck.radius)
                let found = opened ? await engine?.retouchSource(for: spot, recipe: start) : nil
                spot.source = found ?? ImagePoint(x: min(speck.center.x + speck.radius * 2.5, 1), y: speck.center.y)
                next.spots.append(spot)
            }
        case .follow:
            return nil
        case let .convertLightroom(conversions):
            guard let imported = conversions[url] else { return nil }
            next = await anchored(imported.recipe, url)
            masks = []
        }
        let needsMasks = next.masks.contains { layer in
            (masks?.contains(layer.id) ?? true) && layer.components.contains { $0.shape.isAIRaster }
        }
        var failedMasks = 0
        if needsMasks || autoWhiteBalance {
            engine = engine ?? makeEngine()
            if let engine, await (try? engine.open(url)) != nil {
                if autoWhiteBalance, let wb = await engine.autoWhiteBalance() {
                    next[.temperature] = wb.temperature
                    next[.tint] = wb.tint
                }
                if needsMasks {
                    let (recomputed, failed) = await EditorModel.recomputingAIMasks(next, in: masks, engine: engine)
                    next = recomputed
                    failedMasks = failed
                }
            }
        }
        return Applied(recipe: next, failedMasks: failedMasks)
    }

    /// `edit` with the photo's own exposure anchor (`EditRecipe.anchored`), its camera read from the
    /// file only when the edit needs an anchor it hasn't got.
    private func anchored(_ edit: EditRecipe, _ url: URL) async -> EditRecipe {
        guard edit.baseLook.isReproduction || edit.processVersion >= 16,
              edit.exposureAnchor == nil else { return edit.anchored(edit.exposureAnchor) }
        let photo: ExposureAnchor? = if let photoAnchor {
            await photoAnchor(url, edit.processVersion)
        } else {
            .typical(for: nil)
        }
        return edit.anchored(photo)
    }

    /// A history session of its own for a change made to edit `version` (nil: the photo's own) without opening the
    /// photo: as it was, `current`, then `recipe`.
    private nonisolated static func session(
        _ recipe: EditRecipe, from current: EditRecipe, of version: UUID?, title: String,
    ) -> HistorySession {
        HistorySession(steps: [
            HistoryStep(action: .open, title: "Opened", recipe: current),
            HistoryStep(action: .paste, title: title, recipe: recipe),
        ], versionID: version)
    }

    private static func report(
        skipped: Int, editedSince: Int, changedMeanwhile: Int, failedMasks: Int,
        preset: (name: String, notMade: Int, full: Int)? = nil, cancelled: Bool,
    ) -> String? {
        var parts: [String] = []
        if cancelled {
            parts.append("Stopped before the end.")
        }
        if skipped > 0 {
            let photos = "\(skipped) photo\(skipped == 1 ? " was" : "s were")"
            parts.append("\(photos) left alone: edited by a newer Redlamp, or the edit can't be read.")
        }
        if editedSince > 0 {
            let photos = "\(editedSince) photo\(editedSince == 1 ? " was" : "s were")"
            parts.append("\(photos) left alone: edited since Auto Sync changed them.")
        }
        if changedMeanwhile > 0 {
            let photos = "\(changedMeanwhile) photo\(changedMeanwhile == 1 ? " was" : "s were")"
            parts.append("\(photos) left alone: edited while the batch ran.")
        }
        if failedMasks > 0 {
            parts.append("\(failedMasks) AI mask\(failedMasks == 1 ? "" : "s") couldn't be computed for its photo.")
        }
        if let preset, preset.notMade > 0 {
            let photos = "\(preset.notMade) photo\(preset.notMade == 1 ? " was" : "s were")"
            let them = preset.notMade == 1 ? "it" : "them"
            parts.append("\(photos) left alone: \(preset.name)'s masks couldn't be made for \(them).")
        }
        if let preset, preset.full > 0 {
            let photos = "\(preset.full) photo\(preset.full == 1 ? " was" : "s were")"
            let have = preset.full == 1 ? "it has" : "they have"
            parts.append("\(photos) left alone: \(have) \(MaskLayer.maximumLayers) masks already.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

private extension SettingsSync.Change {
    var action: HistoryAction {
        switch self {
        case .paste, .follow: .paste
        case .updateAIMasks: .mask(nil)
        case let .applyMaskPreset(preset): .mask(preset.components.first.flatMap(\.kind))
        case .healDust: .retouch
        case .convertLightroom: .recipe
        }
    }
}

private extension MaskPreset.Component {
    var kind: MaskKind? {
        switch self {
        case let .shape(shape, _, _): shape.kind
        case let .ai(kind, _, _, _): kind
        }
    }
}

extension MaskShape {
    /// A bitmap an AI model computed for one photo (Depth Range's depth map too).
    var isAIRaster: Bool {
        switch self {
        case .ai, .depthRange: true
        default: false
        }
    }
}

private extension Sidecar {
    /// Gives edit `version` (nil: the photo's own) `recipe`, its change recorded by `session`: the first session a
    /// write
    /// holds is the one it saves as open, the others are written beside it.
    mutating func change(_ version: UUID?, to recipe: EditRecipe, session: HistorySession) {
        guard var edit = self[edit: version] else { return }
        edit.recipe = recipe
        self[edit: version] = edit
        if self.session == nil || self.session?.id == session.id {
            self.session = session
        } else {
            unsavedSessions.removeAll { $0.id == session.id }
            unsavedSessions.append(session)
        }
    }
}
