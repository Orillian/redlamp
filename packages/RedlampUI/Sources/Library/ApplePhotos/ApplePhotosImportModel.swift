import AppKit
import RedlampLibrary
import Synchronization

/// What File › Import from Apple Photos… does (LIB-54): whether Redlamp may read Photos, asked the first time; its
/// albums, chosen with their folders, smart and shared albums apart; To as the card import keeps it (`destination`,
/// its saved `ImportSettings`); the census of what the albums chosen would bring, before anything is copied; then the
/// import (`ApplePhotosImport`), its stages with Stop, and how it ended, with Show in Library and Undo Import. It
/// also runs the Library panel's From Apple Photos, the new photos in the albums followed (LIB-55). Photos is only
/// ever read (DEC-106).
@MainActor
final class ApplePhotosImportModel {
    enum Phase: Equatable {
        /// Reading whether Redlamp may read Photos, or asking.
        case checking
        /// Redlamp hasn't asked yet, or may not read Photos' albums: `access` says which.
        case access
        /// Reading Photos' albums.
        case loading
        case choosing
        /// The census of the albums chosen.
        case counting
        case reviewing
        case importing, stopping, imported, undoing, undone
    }

    /// How an album's or a folder's box is checked.
    enum Check: Equatable, Sendable {
        case on, off, mixed
    }

    let photos: any ApplePhotosLibrary
    let importer: ApplePhotosImport
    /// To: the destination, the templates with their example, the backup and the metadata preset, kept with the card
    /// import's (`ImportPreferences`).
    let destination: ImportWindowModel
    private weak var editor: EditorModel?
    var onChange: (@MainActor () -> Void)?

    private(set) var phase = Phase.checking
    private(set) var access = ApplePhotosAccess.notDetermined
    private(set) var tree: ApplePhotosTree?
    /// The albums, smart and shared albums chosen, by ID: never a folder, whose box checks its albums.
    private(set) var chosen: Set<String> = []
    private(set) var includesHidden = false
    private(set) var follows = true
    private(set) var census: ApplePhotosCensus?
    /// The settings the census was made with, which Import runs.
    private(set) var counted: ApplePhotosImport.Settings?
    private(set) var progress: ApplePhotosImport.Progress?
    /// Photos the census took, as the import started: what its progress counts against.
    private(set) var total = 0
    private(set) var outcome: ApplePhotosImport.Outcome?
    private(set) var undone: ApplePhotosImport.Undone?
    private(set) var lastImport: ApplePhotosRecord.Import?
    /// Started from the Library panel's From Apple Photos: the new photos in the albums followed (LIB-55).
    private(set) var isFollowUp = false
    /// What went wrong last, in words.
    private(set) var problem: String?
    private var work: Task<Void, Never>?
    private(set) var started: ContinuousClock.Instant?
    private(set) var elapsed: Duration?

    init(
        photos: any ApplePhotosLibrary, library: ImportLibrary, editor: EditorModel?,
        preferences: ImportPreferences = .shared,
    ) {
        self.photos = photos
        importer = ApplePhotosImport(photos: photos, library: library)
        destination = ImportWindowModel(library: library, preferences: preferences)
        self.editor = editor
        destination.exampleStandIn = { [weak self] in self?.examplePhoto() }
    }

    /// Reads whether Redlamp may read Photos and, when it may, Photos' albums; and the newest import, for Undo. With
    /// `news`, the Library panel's From Apple Photos (LIB-55), it imports them at once, the albums read once it's done.
    func start(importing news: (settings: ApplePhotosImport.Settings, census: ApplePhotosCensus)? = nil) {
        destination.loadCompletions()
        Task { await readLastImport() }
        if let news {
            access = photos.access()
            importNew(news.settings, census: news.census)
        } else {
            checkAccess()
        }
    }

    /// Lets To's sources go, as the window closes.
    func close() {
        destination.close()
    }

    var isBusy: Bool {
        [.checking, .loading, .counting].contains(phase) || isRunning
    }

    /// Importing or taking an import back, which carry on when the window closes.
    var isRunning: Bool {
        [.importing, .stopping, .undoing].contains(phase)
    }

    private func changed() {
        onChange?()
    }

    // MARK: - Access

    /// Whether Redlamp may read Photos now: as the window opens, and each time it comes forward, from System Settings
    /// where access may have been given.
    func checkAccess() {
        guard phase == .checking || phase == .access else { return }
        access = photos.access()
        if access == .authorized {
            loadAlbums()
        } else {
            phase = .access
            changed()
        }
    }

    /// Continue: macOS asks, once, whether Redlamp may read Photos.
    func askForAccess() {
        guard phase == .access, access == .notDetermined else { return }
        phase = .checking
        changed()
        let photos = photos
        Task {
            let given = await photos.requestAccess()
            editor?.activity.record(.action, "Photos access asked for: \(Self.words(for: given))")
            phase = .checking
            checkAccess()
        }
    }

    static func words(for access: ApplePhotosAccess) -> String {
        switch access {
        case .notDetermined: "not asked yet"
        case .denied: "not allowed"
        case .restricted: "restricted on this Mac"
        case .limited: "limited to some photos"
        case .authorized: "allowed"
        }
    }

    // MARK: - Albums

    private func loadAlbums() {
        phase = .loading
        problem = nil
        changed()
        let photos = photos
        work = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<
                [ApplePhotosCollection],
                any Error,
            > in
                do {
                    return try await .success(photos.collections())
                } catch {
                    return .failure(error)
                }
            }.value
            self?.loaded(result)
        }
    }

    private func loaded(_ result: Result<[ApplePhotosCollection], any Error>) {
        guard phase == .loading else { return }
        switch result {
        case let .success(collections):
            let tree = ApplePhotosTree(collections)
            let before = self.tree == nil ? nil : chosen
            self.tree = tree
            let present = Set(tree.collections.filter { $0.kind != .folder }.map(\.id))
            let last = lastImport.map { Set($0.albums.map(\.id)).intersection(present) }
            chosen = before?.intersection(present) ?? last.flatMap { $0.isEmpty ? nil : $0 } ?? Set(tree.standardChoice)
            phase = .choosing
        case let .failure(error):
            if case let ApplePhotosError.noAccess(access) = error {
                self.access = access
                phase = .access
            } else {
                problem = "Photos' albums couldn't be read: \(error)"
                phase = .choosing
            }
        }
        destination.updateExample()
        changed()
    }

    /// The albums a folder's box checks: those in it, at any depth, shared albums apart.
    func albums(in folder: String) -> [ApplePhotosCollection] {
        tree?.albums(in: [folder]).filter { $0.kind != .sharedAlbum } ?? []
    }

    func check(of id: String) -> Check {
        guard let collection = tree?[id] else { return .off }
        guard collection.kind == .folder else { return chosen.contains(id) ? .on : .off }
        let inside = albums(in: id).map(\.id)
        let on = inside.count { chosen.contains($0) }
        return on == 0 ? .off : on == inside.count ? .on : .mixed
    }

    /// An album's box, or a folder's, which checks every album in it.
    func choose(_ id: String, _ on: Bool) {
        guard phase == .choosing, let collection = tree?[id] else { return }
        let ids = collection.kind == .folder ? albums(in: id).map(\.id) : [id]
        if on {
            chosen.formUnion(ids)
        } else {
            chosen.subtract(ids)
        }
        destination.updateExample()
        changed()
    }

    func setIncludesHidden(_ includes: Bool) {
        guard phase == .choosing else { return }
        includesHidden = includes
        changed()
    }

    func setFollows(_ follows: Bool) {
        guard phase == .choosing else { return }
        self.follows = follows
        changed()
    }

    /// The chosen albums in the tree's order.
    var chosenAlbums: [ApplePhotosCollection] {
        tree?.collections.filter { $0.kind != .folder && chosen.contains($0.id) } ?? []
    }

    /// What Review counts and Import runs: the albums chosen, To as it's set.
    var settings: ApplePhotosImport.Settings {
        ApplePhotosImport.Settings(
            collections: chosenAlbums.map(\.id), includesHidden: includesHidden, copying: destination.settings,
            follows: follows,
        )
    }

    // MARK: - Review

    /// Review: the census of the albums chosen, nothing copied.
    func review() {
        guard phase == .choosing, !chosen.isEmpty else { return }
        phase = .counting
        problem = nil
        changed()
        let settings = settings
        let importer = importer
        work = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ApplePhotosCensus, any Error> in
                do {
                    return try await .success(importer.census(settings))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.reviewed(result, settings: settings)
        }
    }

    private func reviewed(_ result: Result<ApplePhotosCensus, any Error>, settings: ApplePhotosImport.Settings) {
        guard phase == .counting else { return }
        switch result {
        case let .success(census):
            self.census = census
            counted = settings
            phase = .reviewing
        case let .failure(error):
            problem = "The albums couldn't be counted: \(error)"
            phase = .choosing
        }
        destination.updateExample()
        changed()
    }

    /// Back, from the report to the albums.
    func back() {
        guard phase == .reviewing else { return }
        census = nil
        counted = nil
        phase = .choosing
        destination.updateExample()
        changed()
    }

    // MARK: - Importing

    var canImport: Bool {
        phase == .reviewing && (census?.report.photos ?? 0) > 0
    }

    /// Import, from the report.
    func startImport() {
        guard canImport, let counted else { return }
        run(counted, census: census)
    }

    /// Import from the Library panel's From Apple Photos (LIB-55): the new photos `census` found in the albums
    /// followed, with the last import's settings.
    func importNew(_ settings: ApplePhotosImport.Settings, census: ApplePhotosCensus) {
        guard !isRunning, census.report.photos > 0 else { return }
        work?.cancel()
        isFollowUp = true
        counted = settings
        self.census = census
        run(settings, census: census)
    }

    /// Resume, after Stop: the same settings again, which take up where the import was.
    func resume() {
        guard phase == .imported, outcome?.state == .stopped, let counted else { return }
        run(counted, census: nil)
    }

    private func run(_ settings: ApplePhotosImport.Settings, census: ApplePhotosCensus?) {
        guard let editor else { return }
        phase = .importing
        problem = nil
        outcome = nil
        undone = nil
        total = census?.report.photos ?? total
        progress = nil
        started = .now
        elapsed = nil
        changed()
        let albums = settings.collections?.compactMap { tree?[$0]?.title ?? census?.tree[$0]?.title } ?? []
        editor.activity.record(
            .action,
            "Import from Apple Photos: \(Self.count(total, "photo")) from "
                + (albums.isEmpty ? "the albums followed" : albums.map { "“\($0)”" }.joined(separator: ", ")),
        )
        let importer = importer
        let destination = destination
        let shown = Mutex<ContinuousClock.Instant?>(nil)
        let progressed: @Sendable (ApplePhotosImport.Progress) -> Void = { [weak self] progress in
            let due = shown.withLock { last in
                let now = ContinuousClock.now
                let stageEnds = progress.done + progress.failed == progress.photos
                guard stageEnds || last.map({ now - $0 > .milliseconds(100) }) ?? true else { return false }
                last = now
                return true
            }
            if due {
                Task { @MainActor [weak self] in self?.progressed(progress) }
            }
        }
        work = Task { [weak self] in
            var settings = settings
            settings.copying = await destination.withPreset(settings.copying)
            let result = await Task.detached(priority: .userInitiated) { [settings] () -> Result<
                ApplePhotosImport.Outcome, any Error,
            > in
                do {
                    return try await .success(importer.run(settings, census: census, progress: progressed))
                } catch {
                    return .failure(error)
                }
            }.value
            await self?.finished(result)
        }
    }

    private func progressed(_ progress: ApplePhotosImport.Progress) {
        guard phase == .importing || phase == .stopping else { return }
        self.progress = progress
        if progress.stage == .staging {
            total = max(total, progress.photos)
        }
        changed()
    }

    /// Shows `progress` as an import's, with nothing running: for the harness's states, which an import on a small
    /// library passes too fast to see.
    func show(_ progress: ApplePhotosImport.Progress, stopping: Bool = false) {
        guard !isRunning else { return }
        phase = stopping ? .stopping : .importing
        total = progress.photos
        self.progress = progress
        changed()
    }

    /// Stop: the files being written from Photos are let go, and the photos being copied finish.
    func stop() {
        guard phase == .importing else { return }
        importer.stop()
        phase = .stopping
        changed()
    }

    private func finished(_ result: Result<ApplePhotosImport.Outcome, any Error>) async {
        elapsed = started.map { ContinuousClock.now - $0 }
        switch result {
        case let .success(outcome):
            self.outcome = outcome
            editor?.activity.record(
                .action,
                "Imported \(Self.count(outcome.imported, "photo")) from Apple Photos"
                    + (outcome.state == .stopped ? ", stopped before the end" : ""),
            )
            let unavailable = outcome.stagingFailures.count + (outcome.copy?.failures.count ?? 0)
            if unavailable > 0 {
                editor?.activity.record(
                    .error, "\(Self.count(unavailable, "photo")) from Apple Photos couldn't be imported",
                )
            }
        case let .failure(error):
            problem = "The import stopped: \(error)"
            editor?.activity.record(.error, problem ?? "")
        }
        progress = nil
        phase = .imported
        changed()
        editor?.libraryPanels.refresh()
        editor?.applePhotosFollower.recount()
        await readLastImport()
        changed()
    }

    // MARK: - Undo

    var canUndo: Bool {
        phase == .imported && (outcome?.imported ?? 0) > 0
    }

    /// Undo Import: the import's copies to the Trash and out of the library, and the record as it was.
    func undo() {
        guard canUndo, let id = outcome?.id else { return }
        phase = .undoing
        problem = nil
        changed()
        let importer = importer
        work = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<
                ApplePhotosImport.Undone,
                any Error,
            > in
                do {
                    return try await .success(importer.undo(id))
                } catch {
                    return .failure(error)
                }
            }.value
            await self?.undid(result)
        }
    }

    private func undid(_ result: Result<ApplePhotosImport.Undone, any Error>) async {
        switch result {
        case let .success(undone):
            self.undone = undone
            let taken = Set(undone.rollbacks.flatMap(\.rolledBack)).count
            editor?.activity.record(
                .action, "Took back the import from Apple Photos: \(Self.count(taken, "photo")) to the Trash",
            )
            phase = .undone
        case let .failure(error):
            problem = "Undo Import stopped: \(error)"
            editor?.activity.record(.error, problem ?? "")
            phase = .imported
        }
        changed()
        editor?.libraryPanels.refresh()
        editor?.applePhotosFollower.recount()
        await readLastImport()
        changed()
    }

    // MARK: - Done

    /// Show in Library: the photos the import brought, in Library's grid, selected.
    func showInLibrary() {
        guard let id = outcome?.id, let editor else { return }
        let record = importer.record
        Task {
            let paths = await Task.detached { () -> [String] in
                ((try? record.load())?.assets.values.filter { $0.importID == id }.flatMap(\.paths) ?? []).sorted()
            }.value
            editor.showImported(paths.map { URL(fileURLWithPath: $0) })
        }
    }

    /// Done: the albums again, their counts read afresh.
    func done() {
        guard phase == .imported || phase == .undone else { return }
        outcome = nil
        undone = nil
        census = nil
        counted = nil
        isFollowUp = false
        problem = nil
        loadAlbums()
    }

    private func readLastImport() async {
        let importer = importer
        lastImport = await Task.detached { try? importer.lastImport() }.value
    }

    // MARK: - The example

    /// The photo To's example names: the census's first, or, until there's one, a stand-in in the first album chosen.
    private func examplePhoto() -> (ImportPhoto, ImportSource)? {
        guard let source = Self.exampleSource, let album = chosenAlbums.first ?? census?.albums.first else {
            return nil
        }
        let asset = census?.taken.first
        let name = asset?.resource(.photo)?.originalFilename ?? "IMG_0001.HEIC"
        let folder = source.url.path
        let photo = ImportPhoto(
            id: folder + "/" + name, source: source.id, folder: folder,
            files: [ImportFile(
                name: name,
                role: .photo,
                size: asset?.resource(.photo)?.size ?? 1,
                modified: asset?
                    .created ?? Date(),
            )],
            album: asset.flatMap { asset in asset.albums.first.flatMap { tree?[$0]?.title } } ?? album.title,
        )
        return (photo, source)
    }

    private static let exampleSource = try? ImportSource.at(FileManager.default.temporaryDirectory)

    // MARK: - Words

    static func count(_ value: Int, _ noun: String, plural: String? = nil) -> String {
        ProgressText.count(value, noun, plural: plural)
    }
}
