import AppKit
import RedlampLibrary
import Synchronization

/// What File › Add Albums from Apple Photos… does (LIB-54, LIB-62): whether Redlamp may read Photos, asked the first
/// time; its albums, chosen with their folders, smart and shared albums apart, those kept in place already In
/// Library; then one of two ways. Keep in Photos, the default, keeps the albums chosen in place (DEC-107), their
/// photos listed from Photos as they're read. Copy into a Folder is the import as 0.3.4 ships it: To as the card
/// import keeps it (`destination`, its saved `ImportSettings`); the census of what the albums chosen would bring,
/// before anything is copied; then the import (`ApplePhotosImport`), its stages with Stop, and how it ended, with Show
/// in Library and Undo Import. It also runs the Library panel's From Apple Photos, the new photos in the albums
/// followed (LIB-55). Photos is only ever read (DEC-106).
@MainActor
final class ApplePhotosImportModel {
    /// How the albums chosen come into the library (LIB-62): kept in Photos, their photos shown from Photos where they
    /// are, or copied into a folder.
    enum Way: String, CaseIterable, Sendable {
        case keep, copy

        var title: String {
            switch self {
            case .keep: "Keep in Photos"
            case .copy: "Copy into a Folder"
            }
        }
    }

    enum Phase: Equatable {
        /// Reading whether Redlamp may read Photos, or asking.
        case checking
        /// Redlamp hasn't asked yet, or may not read Photos: `access` says which.
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
    /// Keep in Photos each time the window opens; Copy into a Folder when the Library panel's From Apple Photos opens
    /// it to import.
    private(set) var way = Way.keep
    /// The albums, smart and shared albums kept in place already, those in a folder kept included, by ID: In Library
    /// in both ways, chosen in Keep in Photos, and never chosen in Copy into a Folder, whose import would make copies
    /// without their Redlamp edits stand in for them (LIB-64); the Apple Photos section's Copy to Folder… copies them
    /// with their edits (LIB-63).
    private(set) var kept: Set<String> = []
    /// Each way's albums, smart and shared albums chosen, by ID: never a folder, whose box checks its albums.
    private var choices: [Way: Set<String>] = [:]
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

    /// Reads whether Redlamp may read Photos and, when it may, Photos' albums, to add them the way `way` says; and the
    /// newest import, for Undo. With `news`, the Library panel's From Apple Photos (LIB-55), it imports them at once,
    /// the albums read once it's done.
    func start(
        way: Way = .keep, importing news: (settings: ApplePhotosImport.Settings, census: ApplePhotosCensus)? = nil,
    ) {
        self.way = way
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
        if access.canRead {
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
        let (photos, importer) = (photos, importer)
        work = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<
                (ApplePhotosTree, kept: Set<String>),
                any Error,
            > in
                do {
                    let tree = try await ApplePhotosTree(photos.collections())
                    return try await .success((tree, importer.keptInPlace(in: tree)))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.loaded(result)
        }
    }

    private func loaded(_ result: Result<(ApplePhotosTree, kept: Set<String>), any Error>) {
        guard phase == .loading else { return }
        switch result {
        case let .success((tree, kept)):
            let reloading = self.tree != nil
            self.tree = tree
            self.kept = kept
            let present = Set(tree.collections.filter { $0.kind != .folder }.map(\.id)).subtracting(kept)
            let last = lastImport.map { Set($0.albums.map(\.id)).intersection(present) }
            choices[.copy] = reloading
                ? chosen(for: .copy).intersection(present)
                : last.flatMap { $0.isEmpty ? nil : $0 } ?? Set(tree.standardChoice).subtracting(kept)
            choices[.keep] = (reloading ? chosen(for: .keep).intersection(present) : []).union(kept)
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

    /// The albums, smart and shared albums chosen in the way shown, by ID; Keep in Photos' hold those kept already.
    var chosen: Set<String> {
        chosen(for: way)
    }

    private func chosen(for way: Way) -> Set<String> {
        choices[way] ?? []
    }

    /// Keep in Photos or Copy into a Folder, each with the albums chosen in it: until the albums are counted or
    /// imported.
    func setWay(_ way: Way) {
        guard [.checking, .access, .loading, .choosing].contains(phase), way != self.way else { return }
        self.way = way
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
        let inside = albums(in: id).map(\.id).filter { way == .keep || !kept.contains($0) }
        let on = inside.count { chosen.contains($0) }
        return on == 0 ? .off : on == inside.count ? .on : .mixed
    }

    /// An album's box, or a folder's, which checks every album in it; those kept in place already stay as they are.
    func choose(_ id: String, _ on: Bool) {
        guard phase == .choosing, let collection = tree?[id] else { return }
        let ids = (collection.kind == .folder ? albums(in: id).map(\.id) : [id]).filter { !kept.contains($0) }
        if on {
            choices[way, default: []].formUnion(ids)
        } else {
            choices[way, default: []].subtract(ids)
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

    /// The albums chosen in the way shown, in the tree's order, those kept in place already left out.
    var chosenAlbums: [ApplePhotosCollection] {
        tree?.collections.filter { $0.kind != .folder && chosen.contains($0.id) && !kept.contains($0.id) } ?? []
    }

    /// What Review counts and Import runs: the albums chosen, To as it's set.
    var settings: ApplePhotosImport.Settings {
        ApplePhotosImport.Settings(
            collections: chosenAlbums.map(\.id), includesHidden: includesHidden, copying: destination.settings,
            follows: follows,
        )
    }

    // MARK: - Keeping in place

    /// What Add Albums keeps (LIB-62), in the tree's order: a folder whose albums are all chosen, some of them not kept
    /// yet, as a folder, so the albums Photos adds to it later are kept too; and each other album chosen that isn't
    /// kept yet on its own.
    var keeping: [String] {
        guard way == .keep, let tree else { return [] }
        let chosen = chosen
        var ids: [String] = []
        func visit(_ parent: String?) {
            for collection in tree.children(of: parent) {
                if collection.kind == .folder {
                    let inside = albums(in: collection.id).map(\.id)
                    if !inside.isEmpty, inside.allSatisfy(chosen.contains), !inside.allSatisfy(kept.contains) {
                        ids.append(collection.id)
                    } else {
                        visit(collection.id)
                    }
                } else if chosen.contains(collection.id), !kept.contains(collection.id) {
                    ids.append(collection.id)
                }
            }
        }
        visit(nil)
        return ids
    }

    /// Add Albums: what `keeping` names kept in place through the library's one Photos indexer, which lists their
    /// photos as it reads them, and the first album added shown in the grid meanwhile; Photos' changes to them are
    /// followed from then on, and the Library panel's From Apple Photos no longer counts them (LIB-64). False, with the
    /// reason, while the library can't keep albums.
    func addAlbums() -> Bool {
        let ids = keeping
        guard phase == .choosing, !ids.isEmpty, let first = chosenAlbums.first, let editor else { return false }
        guard let service = editor.library.service, service.applePhotosIndexer != nil else {
            problem = "Albums can be added once the library has opened."
            changed()
            return false
        }
        let titles = chosenAlbums.map { "“\($0.title)”" }.joined(separator: ", ")
        editor.activity.record(.action, "Add Albums from Apple Photos: \(titles), kept in Photos")
        Task {
            do {
                try await service.keepApplePhotos(ids)
                editor.applePhotosFollower.recount()
            } catch {
                editor.activity.record(
                    .error, "\(titles) weren't added from Apple Photos: \(LibraryService.describe(error))",
                )
            }
        }
        editor.librarySources.show(.applePhotos(first.id))
        return true
    }

    // MARK: - Review

    /// Review: the census of the albums chosen, nothing copied.
    func review() {
        guard phase == .choosing, way == .copy, !chosen.isEmpty else { return }
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
        way = .copy
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
