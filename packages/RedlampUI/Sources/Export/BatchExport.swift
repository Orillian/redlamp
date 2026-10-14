import Foundation
import Observation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary

/// Several photos exported at once, in the background (EDT-16, `docs/plans/2026-10-01-export-design.md`), in an
/// engine of the batch's own with its own GPU queue, so Develop's frames never wait behind an export.
///
/// - **As they were when Export was clicked:** a batch takes every photo's edit as soon as it's asked for, the
///   open photo's as it is on screen and the others' from their sidecars once their saves are on disk, so a change
///   made while it runs or waits its turn is never in its file. Until a photo's edit is taken, opening it waits, and
///   so do Sync Settings' writes to it (`wait(for:)`). The edits are kept without their masks' bitmaps, which are
///   read again from each photo's sidecar when its turn comes.
/// - **One at a time:** a downscaled export still renders at full resolution, in half floats, so each photo is
///   opened, rendered and written, and let go, before the next one opens.
/// - **Cancel** stops after the photo being written: what's written stays, and no file is left half written.
/// - **A photo that fails** (moved or deleted while it waited, a file that doesn't open, a write that fails) is
///   left, and the rest go on; the report names each with its reason.
/// - A batch asked for while one runs waits its turn.
@MainActor
@Observable
public final class BatchExport {
    public struct Progress: Equatable, Sendable {
        public var done: Int
        public var total: Int
    }

    /// A photo a batch didn't export, and why, in words.
    public struct Failure: Equatable, Sendable {
        public var photo: URL
        public var reason: String
    }

    /// How a batch went.
    public struct Report: Equatable, Sendable {
        /// The files written, in the batch's order.
        public var written: [URL] = []
        public var failures: [Failure] = []
        /// Photos left because a file was there and the batch was to skip them.
        public var skipped = 0
        /// Photos left when the batch was cancelled.
        public var cancelled = 0
        public var total = 0
    }

    /// A batch to export: where each photo goes, and the settings.
    struct Job {
        var targets: [ExportNames.Target]
        var settings: ExportSettings
        /// The open photo and its edit as it is on screen, when it's one of them.
        var open: (url: URL, recipe: EditRecipe)?
        var done: @MainActor (Report) -> Void = { _ in }
    }

    /// The batch under way: its photos done and in all; nil while none runs.
    public private(set) var progress: Progress?
    /// How the last batch went, in a line, for a few seconds after it ends.
    public private(set) var summary: String?
    /// How long `summary` shows.
    static let summaryShown = Duration.seconds(6)
    @ObservationIgnored private var summaryTask: Task<Void, Never>?

    /// Makes the engine photos are exported in; nil exports nothing.
    @ObservationIgnored var makeEngine: () -> (any EditingEngine)? = { nil }
    @ObservationIgnored var sidecars = SidecarPlacement()
    /// Returns once a photo's saves are on disk: the editor's and Sync Settings'.
    @ObservationIgnored var saved: @MainActor (URL) async -> Void = { _ in }
    /// A Base Look an edit uses that the engine doesn't know, from the looks installed.
    @ObservationIgnored var baseLook: @MainActor (BaseLookReference) -> BaseLookDefinition? = { _ in nil }
    /// The library's fields for a photo, which go with it under the settings' metadata policy.
    @ObservationIgnored var fields: @MainActor (URL) async -> ExportMetadata.Fields? = { _ in nil }
    /// Waited for as each photo's export starts (tests hold a photo here).
    @ObservationIgnored var beforeExporting: @MainActor (URL) async -> Void = { _ in }

    /// A job and the edits it took when it was asked for.
    private struct Queued {
        var job: Job
        var photos: [ExportNames.Target]
        var edits: Task<[Edit], Never>
    }

    @ObservationIgnored private var queue: [Queued] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The photos whose edits are being taken, and the tasks taking them, by batch.
    @ObservationIgnored private var taking: [UUID: (photos: Set<URL>, task: Task<[Edit], Never>)] = [:]

    init() {}

    public var isRunning: Bool {
        task != nil
    }

    /// Takes `job`'s edits now, and exports it once the batch under way, if any, is done.
    func run(_ job: Job) {
        let photos = job.targets.filter { $0.existing != .skipped }
        queue.append(Queued(job: job, photos: photos, edits: take(photos.map(\.photo), open: job.open)))
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !queue.isEmpty {
                await export(queue.removeFirst())
            }
            self?.progress = nil
            self?.task = nil
        }
    }

    /// Stops the batch after the photo being written, and drops those waiting.
    public func cancel() {
        queue = []
        task?.cancel()
    }

    /// Returns once the batches asked for so far have taken `url`'s edit.
    func wait(for url: URL) async {
        for pending in taking.values where pending.photos.contains(url) {
            _ = await pending.task.value
        }
    }

    // MARK: - A batch

    private func export(_ queued: Queued) async {
        let (job, photos) = (queued.job, queued.photos)
        var report = Report(skipped: job.targets.count - photos.count, total: job.targets.count)
        progress = Progress(done: 0, total: photos.count)
        let edits = await queued.edits.value
        let engine = photos.isEmpty ? nil : makeEngine()
        for (index, target) in photos.enumerated() {
            if Task.isCancelled {
                report.cancelled = photos.count - index
                break
            }
            do {
                guard let engine else { throw Problem("Redlamp couldn't start its export engine.") }
                // A task of its own, which Cancel doesn't reach: the photo under way is finished.
                let edit = edits[index]
                try await Task { try await write(target, edit: edit, settings: job.settings, engine: engine) }.value
                report.written.append(target.url)
            } catch {
                report.failures.append(Failure(photo: target.photo, reason: Self.reason(error)))
            }
            await engine?.releaseResources()
            progress = Progress(done: index + 1, total: photos.count)
        }
        show(Self.summary(of: report))
        job.done(report)
    }

    /// "Exported 12 photos", "Exported 10 of 12 photos", or what Cancel left.
    static func summary(of report: Report) -> String {
        let written = report.written.count
        let photos = report.total == 1 ? "photo" : "photos"
        if report.cancelled > 0 {
            return "Export cancelled: \(written) of \(report.total) \(photos) exported"
        }
        return written == report.total ? "Exported \(written) \(photos)" : "Exported \(written) of \(report.total) \(photos)"
    }

    private func show(_ line: String) {
        summaryTask?.cancel()
        summary = line
        summaryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.summaryShown)
            guard !Task.isCancelled else { return }
            self?.summary = nil
        }
    }

    /// An edit as a batch took it.
    private enum Edit: Sendable {
        /// With its masks' bitmaps.
        case loaded(EditRecipe)
        /// Without them: they're read from the photo's sidecar.
        case unloaded(EditRecipe)
        /// Why the photo isn't exported.
        case unreadable(String)
    }

    /// Each photo's edit as it is now: `open`'s as given, the others' read from their sidecars off the main thread
    /// once their saves are on disk, without their masks' bitmaps.
    private func take(_ photos: [URL], open: (url: URL, recipe: EditRecipe)?) -> Task<[Edit], Never> {
        let id = UUID()
        let task = Task { [weak self, sidecars, saved] () -> [Edit] in
            defer { self?.taking[id] = nil }
            for url in photos where url != open?.url {
                await saved(url)
            }
            return await Task.detached(priority: .userInitiated) {
                photos.map { url -> Edit in
                    if let open, open.url == url {
                        return .loaded(open.recipe)
                    }
                    let read = sidecars.store(for: url).readForEditing(for: url)
                    guard !read.failed else { return .unreadable("Its edit couldn't be read.") }
                    if read.sidecar == nil, let protection = read.protection {
                        return .unreadable(protection == .damaged
                            ? "Its edit is damaged. Open it in Develop, where Start Over sets the edit aside."
                            : "Its edit couldn't be read: a newer Redlamp may have written it.")
                    }
                    var recipe = read.sidecar?.recipe ?? EditRecipe()
                    recipe.unloadMaskBitmaps()
                    return .unloaded(recipe)
                }
            }.value
        }
        taking[id] = (Set(photos), task)
        return task
    }

    /// Opens `target`'s photo, renders it with `edit` and writes it.
    private func write(
        _ target: ExportNames.Target, edit: Edit, settings: ExportSettings, engine: any EditingEngine,
    ) async throws {
        let url = target.photo
        await beforeExporting(url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Problem("It isn't there any more: it was moved, renamed or deleted while it waited.")
        }
        let recipe: EditRecipe
        switch edit {
        case let .loaded(loaded):
            recipe = loaded
        case let .unloaded(unloaded):
            let store = sidecars.store(for: url)
            recipe = await Task.detached(priority: .userInitiated) {
                var loaded = unloaded
                loaded.loadMaskBitmaps { try? Data(contentsOf: store.bitmapURL($0, for: url)) }
                return loaded
            }.value
            guard !recipe.maskBitmaps.contains(where: { $0.png == nil }) else {
                throw Problem("Its masks changed while it waited. Export it again.")
            }
        case let .unreadable(reason):
            throw Problem(reason)
        }
        engine.expect(recipe.rawRevision, for: url)
        let info = try await engine.open(url)
        if !engine.canRender(recipe.baseLook), let look = baseLook(recipe.baseLook) {
            engine.registerBaseLook(look)
        }
        guard engine.canRender(recipe.baseLook) else {
            throw Problem("Its Base Look, “\(recipe.baseLook.name)”, isn't installed.")
        }
        let request = settings.stillRequest(recipe: EditorModel.asShot(recipe, info), source: url, size: info.pixelSize)
        let image = try await engine.renderStill(request)
        let files = engine.files
        let libraryFields = settings.metadata == .none ? nil : await fields(url)
        try await Task.detached(priority: .utility) {
            let metadata = ExportMetadata.properties(
                from: url, reading: files, policy: settings.metadata, recipe: request.recipe, fields: libraryFields,
            )
            try ImageExporter.write(
                image,
                to: target.url,
                settings: settings,
                metadata: metadata,
                source: url,
                reading: files,
            )
        }.value
    }

    /// Why a photo wasn't exported, in words.
    private struct Problem: LocalizedError {
        let errorDescription: String?

        init(_ reason: String) {
            errorDescription = reason
        }
    }

    private static func reason(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
