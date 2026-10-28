import AppKit
import RedlampLibrary
import Synchronization

/// Copy to Folder… for photos kept in Apple Photos (LIB-63, decision 7): what's chosen, counted as the window opens,
/// beside To as Import keeps it (its destination, templates, backup and metadata preset), or the folder the photos
/// were dropped on; Copy runs LIB-54's import over them (`ApplePhotosImport.Settings.copyToFolder`), each copy
/// carrying what Redlamp keeps of its photo and then standing in for it in the library, with its stages and Stop; and
/// how it ended, with Show in Library and Undo Copy, which puts the photos kept in place back. Photos is only read
/// (DEC-106).
@MainActor
final class ApplePhotosCopyModel {
    enum Phase: Equatable {
        /// The census of what's chosen.
        case counting
        case choosing
        case copying, stopping, copied, undoing, undone
    }

    /// What Copy to Folder was asked to copy.
    struct Request: Equatable {
        /// The photos kept in place, by their assets' local identifiers, in the order chosen.
        var assets: [String]
        /// An album's Copy to Folder: the album, whose title `{album}` gives the copies first.
        var album: String?
        var albumTitle: String?
        /// The folder they were dropped on, which they're copied into, Import's own destination left as it is.
        var folder: URL?
        /// Photos in folders chosen with them, which Copy to Folder leaves where they are.
        var inFolders = 0
    }

    let photos: any ApplePhotosLibrary
    let importer: ApplePhotosImport
    /// To: Import's destination, templates, backup and metadata preset; for a drop, a copy of them that keeps nothing,
    /// whose destination is the folder dropped on, the photos going straight into it.
    let destination: ImportWindowModel
    let request: Request
    private weak var editor: EditorModel?
    var onChange: (@MainActor () -> Void)?

    private(set) var phase = Phase.counting
    private(set) var census: ApplePhotosCensus?
    private(set) var progress: ApplePhotosImport.Progress?
    private(set) var outcome: ApplePhotosImport.Outcome?
    private(set) var undone: ApplePhotosImport.Undone?
    /// What went wrong last, in words.
    private(set) var problem: String?
    private var work: Task<Void, Never>?
    private var started: ContinuousClock.Instant?
    private(set) var elapsed: Duration?

    init(
        photos: any ApplePhotosLibrary, library: ImportLibrary, originals: ApplePhotosOriginals?,
        indexer: ApplePhotosIndexer?, request: Request, editor: EditorModel?, preferences: ImportPreferences = .shared,
    ) {
        self.photos = photos
        self.request = request
        importer = ApplePhotosImport(photos: photos, library: library, originals: originals, indexer: indexer)
        var kept = preferences
        if let folder = request.folder {
            kept = ImportPreferences(copying: preferences)
            kept.chooseDestination(folder)
            kept.chooseBackup(nil)
            if let flat = try? NamingTemplate(parsing: "") {
                kept.update { $0.folders = flat }
            }
        }
        destination = ImportWindowModel(library: library, preferences: kept)
        self.editor = editor
        destination.exampleStandIn = { [weak self] in self?.examplePhoto() }
    }

    /// Counts what's chosen: the census of their assets, nothing copied.
    func start() {
        destination.loadCompletions()
        count()
    }

    /// Lets To's sources go, as the window closes.
    func close() {
        destination.close()
    }

    /// Copying or taking a copy back, which carry on when the window closes.
    var isRunning: Bool {
        [.copying, .stopping, .undoing].contains(phase)
    }

    private func changed() {
        onChange?()
    }

    /// What Copy runs: the photos chosen, To as it's set.
    var settings: ApplePhotosImport.Settings {
        .copyToFolder(request.assets, naming: request.album.map { [$0] }, to: destination.settings)
    }

    private func count() {
        phase = .counting
        problem = nil
        changed()
        let (importer, settings) = (importer, settings)
        work = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ApplePhotosCensus, any Error> in
                do {
                    return try await .success(importer.census(settings))
                } catch {
                    return .failure(error)
                }
            }.value
            self?.counted(result)
        }
    }

    private func counted(_ result: Result<ApplePhotosCensus, any Error>) {
        guard phase == .counting else { return }
        switch result {
        case let .success(census):
            self.census = census
        case let .failure(error):
            problem = "The photos couldn’t be counted: \(error)"
        }
        phase = .choosing
        destination.updateExample()
        changed()
    }

    // MARK: - Copying

    var canCopy: Bool {
        phase == .choosing && (census?.report.photos ?? 0) > 0
    }

    /// Copy: the photos counted copied to To's folder by its templates.
    func copy() {
        guard canCopy, let census else { return }
        run(census: census)
    }

    /// Resume, after Stop: the same settings again, which take up where the copy was.
    func resume() {
        guard phase == .copied, outcome?.state == .stopped else { return }
        run(census: nil)
    }

    private func run(census: ApplePhotosCensus?) {
        guard let editor else { return }
        phase = .copying
        problem = nil
        outcome = nil
        undone = nil
        progress = nil
        started = .now
        elapsed = nil
        changed()
        let total = census?.report.photos ?? self.census?.report.photos ?? request.assets.count
        editor.activity.record(
            .action,
            "Copy to Folder: \(Self.count(total, "photo")) kept in Apple Photos to "
                + destination.settings.destination.path,
        )
        let (importer, destination, settings) = (importer, destination, settings)
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
        guard phase == .copying || phase == .stopping else { return }
        self.progress = progress
        changed()
    }

    /// Stop: the files being written from Photos are let go, and the photos being copied finish.
    func stop() {
        guard phase == .copying else { return }
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
                "Copied \(Self.count(outcome.imported, "photo")) kept in Apple Photos to a folder"
                    + (outcome.state == .stopped ? ", stopped before the end" : ""),
            )
            let unavailable = outcome.stagingFailures.count + (outcome.copy?.failures.count ?? 0)
            if unavailable > 0 {
                editor?.activity.record(
                    .error, "\(Self.count(unavailable, "photo")) kept in Apple Photos couldn't be copied",
                )
            }
        case let .failure(error):
            problem = "The copy stopped: \(error)"
            editor?.activity.record(.error, problem ?? "")
        }
        progress = nil
        phase = .copied
        changed()
        editor?.libraryPanels.refresh()
    }

    // MARK: - Undo

    var canUndo: Bool {
        phase == .copied && (outcome?.imported ?? 0) > 0
    }

    /// Undo Copy: the copies to the Trash and out of the library, and the photos kept in place listed again.
    func undo() {
        guard canUndo, let id = outcome?.id else { return }
        phase = .undoing
        problem = nil
        changed()
        let importer = importer
        work = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<
                ApplePhotosImport.Undone, any Error,
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
                .action, "Took back the copy to a folder: \(Self.count(taken, "photo")) to the Trash",
            )
            phase = .undone
        case let .failure(error):
            problem = "Undo Copy stopped: \(error)"
            editor?.activity.record(.error, problem ?? "")
            phase = .copied
        }
        changed()
        editor?.libraryPanels.refresh()
    }

    // MARK: - Done

    /// Show in Library: the copies, in Library's grid, selected.
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

    // MARK: - The example

    /// The photo To's example names: the census's first, or, until there's one, a stand-in.
    private func examplePhoto() -> (ImportPhoto, ImportSource)? {
        guard let source = Self.exampleSource else { return nil }
        let asset = census?.taken.first
        let name = asset?.resource(.photo)?.originalFilename ?? "IMG_0001.HEIC"
        let folder = source.url.path
        let album = request.albumTitle
            ?? asset.flatMap { asset in asset.albums.first.flatMap { census?.tree[$0]?.title } }
        let photo = ImportPhoto(
            id: folder + "/" + name, source: source.id, folder: folder,
            files: [ImportFile(
                name: name, role: .photo, size: asset?.resource(.photo)?.size ?? 1,
                modified: asset?.created ?? Date(),
            )],
            album: album,
        )
        return (photo, source)
    }

    private static let exampleSource = try? ImportSource.at(FileManager.default.temporaryDirectory)

    static func count(_ value: Int, _ noun: String, plural: String? = nil) -> String {
        ProgressText.count(value, noun, plural: plural)
    }
}

/// What the Copy to Folder window shows, worked out from its model: the page (drawn as the Apple Photos window draws
/// its own), what's chosen beside To while it's being set, and the bottom bar.
struct ApplePhotosCopyScreen: Equatable {
    struct Button: Equatable {
        enum Kind: String, CaseIterable {
            case copy, stop, resume, undo, showInLibrary, done
        }

        var kind: Kind
        var title: String
        var isEnabled = true
        var isDefault = false
    }

    var page: ApplePhotosScreen
    /// Beside To, on the setup page: what's chosen and what Copy does with it.
    var chosen: ApplePhotosScreen
    var buttons: [Button] = []
    var barNote = ""
}

extension ApplePhotosCopyModel {
    var screen: ApplePhotosCopyScreen {
        var screen = switch phase {
        case .counting, .choosing: setupScreen
        case .copying, .stopping: progressScreen
        case .copied, .undoing, .undone: resultScreen
        }
        screen.page.problem = problem
        return screen
    }

    // MARK: - Setup

    private var setupScreen: ApplePhotosCopyScreen {
        let photos = census?.report.photos ?? request.assets.count
        let what = "\(Self.count(photos, "photo")) kept in Apple Photos"
        var chosen = ApplePhotosScreen(
            page: phase == .counting ? .working : .review,
            heading: phase == .counting ? "Counting what’s chosen…" : request.albumTitle.map { "“\($0)”: " + what }
                ?? what,
        )
        chosen.problem = problem
        if let report = census?.report {
            chosen.sections = Self.chosenSections(report, asked: request.assets.count, inFolders: request.inFolders)
        }
        let title = photos == 1 ? "Copy 1 Photo" : "Copy \(Self.count(photos, "Photo"))"
        return ApplePhotosCopyScreen(
            page: ApplePhotosScreen(page: .setup), chosen: chosen,
            buttons: [.init(kind: .copy, title: title, isEnabled: canCopy, isDefault: true)],
            barNote: phase == .counting
                ? "Counting what’s chosen. Nothing is copied until you copy."
                : "Copy puts them in To’s folder by its templates. Photos is only read: nothing in it changes.",
        )
    }

    /// What's chosen as the setup shows it: what's copied and what each copy carries, and what stays.
    static func chosenSections(
        _ report: ApplePhotosReport, asked: Int, inFolders: Int,
    ) -> [ApplePhotosScreen.Section] {
        var across: [String] = []
        let size = report.bytes.map { ", " + ImportFormat.size($0) } ?? ""
        across.append("\(count(report.photos, "photo")) copied as \(count(report.files, "file"))\(size)")
        if report.pairs > 0 {
            across.append("\(count(report.pairs, "RAW+JPEG pair")), each kept together under one name")
        }
        if report.edited > 0 {
            across.append(
                "\(count(report.edited, "photo")) edited in Photos: each original, with Photos’ version stacked "
                    + "with it",
            )
        }
        if report.livePhotos > 0 {
            across.append(
                "\(count(report.livePhotos, "Live Photo")), as \(report.livePhotos == 1 ? "its" : "their") still",
            )
        }
        if report.bursts > 0 {
            across.append("\(count(report.bursts, "burst")): the frames shown or picked in Photos, stacked")
        }
        across.append("Each carries its edit, versions, history, keywords and collections from Redlamp")
        across.append("Originals that aren’t on this Mac are downloaded from iCloud first")
        across.append("In the library the copies then stand in for these photos")

        var left: [String] = []
        if report.videosLeft > 0 {
            left.append("\(count(report.videosLeft, "video")): Redlamp edits photos")
        }
        if report.alreadyImported > 0 {
            left.append("\(count(report.alreadyImported, "photo")) copied to a folder already")
        }
        let gone = asked - report.assets
        if gone > 0 {
            left.append("\(count(gone, "photo")) Apple Photos no longer has")
        }
        if inFolders > 0 {
            left.append(
                "\(count(inFolders, "photo")) in folders, chosen with them, stay where \(inFolders == 1 ? "it is" : "they are")",
            )
        }
        if report.withLocation > 0 {
            left.append("Places set only in Photos stay there: the copies keep the GPS their files hold")
        }
        var sections = [ApplePhotosScreen.Section(id: "across", title: "Copied", lines: across)]
        if !left.isEmpty {
            sections.append(.init(id: "left", title: "Not copied", lines: left))
        }
        return sections
    }

    // MARK: - Progress

    private var progressScreen: ApplePhotosCopyScreen {
        let stage = progress?.stage ?? .census
        var page = ApplePhotosScreen(
            page: .progress, heading: "Copying to \(destination.settings.destination.lastPathComponent)",
            stages: stages(now: stage, stopped: false),
        )
        let total = census?.report.photos ?? request.assets.count
        let photos = progress?.photos ?? total
        let done = progress.map { $0.done + $0.failed } ?? 0
        var lines: [String] = []
        if let progress, progress.stage == .staging || progress.stage == .copying {
            if let bytes = progress.bytes, bytes > 0 {
                lines.append("\(ImportFormat.size(progress.written)) of \(ImportFormat.size(bytes))")
            }
            if progress.downloading > 0 {
                lines.append("Downloading \(Self.count(progress.downloading, "original")) from iCloud")
            }
            if progress.failed > 0 {
                lines.append("\(Self.count(progress.failed, "photo")) Photos couldn’t give")
            }
        }
        page.progress = ApplePhotosScreen.Progress(
            title: Self.title(of: stage), done: done, total: photos,
            fraction: photos > 0 ? min(Double(done) / Double(photos), 1) : 0, lines: lines,
        )
        return ApplePhotosCopyScreen(
            page: page, chosen: ApplePhotosScreen(page: .review),
            buttons: [.init(
                kind: .stop,
                title: phase == .stopping ? "Stopping…" : "Stop",
                isEnabled: phase == .copying,
            )],
            barNote: phase == .stopping
                ? "Stopping: the photos being copied finish, and Resume takes up where it stopped."
                : "Stop ends it once the photos being copied are done. Closing the window lets it carry on.",
        )
    }

    private static func title(of stage: ApplePhotosImport.Stage) -> String {
        switch stage {
        case .census: "Reading Photos"
        case .staging: "From Photos"
        case .copying: "Copying"
        case .finishing: "Finishing"
        }
    }

    private func stages(now stage: ApplePhotosImport.Stage, stopped: Bool) -> [ProgressStage] {
        let order: [ApplePhotosImport.Stage] = [.census, .staging, .copying, .finishing]
        let place = order.firstIndex(of: stage) ?? 0
        return order.enumerated().map { index, each in
            let state: ProgressStage.State = index < place ? .done : index > place ? .next : stopped ? .stopped : .now
            let detail: String = switch (each, state) {
            case (.staging, .now), (.copying, .now):
                progress.map { "\($0.done + $0.failed) of \($0.photos)" } ?? ""
            case (_, .done): "done"
            default: ""
            }
            return ProgressStage(id: each.rawValue, title: Self.title(of: each), detail: detail, state: state)
        }
    }

    // MARK: - Result

    private var resultScreen: ApplePhotosCopyScreen {
        let done = ApplePhotosCopyScreen.Button(kind: .done, title: "Done", isDefault: true)
        if phase == .undoing {
            return ApplePhotosCopyScreen(
                page: ApplePhotosScreen(page: .result, heading: "Taking the copy back…"),
                chosen: ApplePhotosScreen(page: .review),
            )
        }
        if phase == .undone, let undone {
            let taken = Set(undone.rollbacks.flatMap(\.rolledBack)).count
            return ApplePhotosCopyScreen(
                page: ApplePhotosScreen(
                    page: .result, heading: "The copy is taken back",
                    sections: [.init(id: "undone", title: "Taken back", lines: [
                        "The copies of \(Self.count(taken, "photo")) are in the Trash and out of the library.",
                        "The photos kept in Apple Photos are back in the library, with what Redlamp keeps of them.",
                    ])],
                ),
                chosen: ApplePhotosScreen(page: .review), buttons: [done],
            )
        }
        guard let outcome else {
            return ApplePhotosCopyScreen(
                page: ApplePhotosScreen(page: .result, heading: "The copy didn’t finish"),
                chosen: ApplePhotosScreen(page: .review), buttons: [done],
            )
        }
        let stopped = outcome.state == .stopped
        let copied = outcome.imported
        let time = elapsed.map { " in " + ProgressText.duration($0 / .seconds(1)) } ?? ""
        var page = ApplePhotosScreen(
            page: .result,
            heading: stopped
                ? "Stopped with \(Self.count(copied, "photo")) copied"
                : "Copied \(Self.count(copied, "photo"))\(time)",
            stages: stopped ? stages(now: outcome.copy == nil ? .staging : .copying, stopped: true) : [],
        )
        var lines: [String] = []
        if let copy = outcome.copy {
            let edits = copy.verified - copied
            lines.append(
                "\(Self.count(copy.verified, "photo")) in the library"
                    +
                    (edits > 0 ? ", \(Self.count(edits, "version")) edited in Photos stacked with the originals" :
                        ""),
            )
        }
        lines.append("Copied to \(destination.settings.destination.path)")
        if copied > 0 {
            lines.append("Each copy stands in for its photo kept in Apple Photos, with its edits and metadata")
        }
        var left: [String] = []
        for (_, message) in outcome.stagingFailures.sorted(by: { $0.key < $1.key }).prefix(5) {
            left.append("Photos couldn’t give a photo: \(message)")
        }
        if outcome.stagingFailures.count > 5 {
            left.append("Photos couldn’t give \(Self.count(outcome.stagingFailures.count - 5, "more photo"))")
        }
        for failure in outcome.copy?.failures.prefix(5) ?? [] {
            left.append("\((failure.photo as NSString).lastPathComponent) couldn’t be copied: \(failure.message)")
        }
        if outcome.placesOnlyInPhotos > 0 {
            left.append(
                "\(Self.count(outcome.placesOnlyInPhotos, "photo")) placed only in Photos: the place stays there",
            )
        }
        if stopped {
            left.append("The rest are still only in Photos: Resume takes up where it stopped")
        }
        page.sections = [.init(id: "copied", title: stopped ? "Stopped" : "Copied", lines: lines)]
        if !left.isEmpty {
            page.sections.append(.init(id: "left", title: "Not copied", lines: left))
        }
        var buttons: [ApplePhotosCopyScreen.Button] = []
        if copied > 0 {
            buttons.append(.init(kind: .undo, title: "Undo Copy", isEnabled: canUndo))
            buttons.append(.init(kind: .showInLibrary, title: "Show in Library"))
        }
        if stopped {
            buttons.append(.init(kind: .resume, title: "Resume"))
        }
        buttons.append(done)
        return ApplePhotosCopyScreen(
            page: page, chosen: ApplePhotosScreen(page: .review), buttons: buttons,
            barNote: copied > 0
                ? "Undo Copy moves the copies to the Trash, and the photos kept in Apple Photos come back." : "",
        )
    }
}
