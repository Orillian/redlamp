import Foundation
import RedlampDocument
import Synchronization

/// An import from Apple Photos into the library (LIB-54), as the import window and `redlamp library photos`
/// run it: the census of the albums chosen, their assets' files staged on the destination's volume
/// (`ApplePhotosStager`), then copied by the card import (LIB-27) with the staging folder as a folder source,
/// so naming, collisions, verification, the journal, the content-key check and Undo are the card import's.
///
/// - **Each photo's sidecar,** written once by the card import, gets the favourite as the pick flag, from
///   macOS 27 the rating, caption and keywords, a date changed in Photos as `captureShift` and
///   `captureOffset` against the time the file records, each album it's in as a collection by its path
///   (Photos' folders as sets), and `applePhotos`. An edit's rendering and a burst's frames are stacked with
///   their original and key photo, the rendering and the key photo on top.
/// - **The record** (`Apple Photos.json`) keeps each import, the albums followed and the assets imported;
///   photos it names aren't staged again. A stopped import keeps its staging folder, and the next import of
///   the same albums to the same destination takes up where it was; one that finishes or is undone removes
///   it.
/// - **Stop** (`stop`, or cancelling the task) stops it between files; **Undo Import** (`undo`) rolls back
///   every copy it made, as the card import does, and takes its assets out of the record.
public final class ApplePhotosImport: Sendable {
    /// What an import takes and where it puts it.
    public struct Settings: Sendable, Hashable, Codable {
        /// The collections chosen, by ID, a folder for its albums; nil for every album
        /// (`ApplePhotosTree.standardChoice`).
        public var collections: [String]?
        public var includesHidden: Bool
        /// The destination, templates, backup and metadata preset, as Import has them.
        public var copying: ImportSettings
        /// The albums are followed for the new photos that arrive in them (LIB-55).
        public var follows: Bool

        public init(
            collections: [String]? = nil, includesHidden: Bool = false, copying: ImportSettings, follows: Bool = true,
        ) {
            self.collections = collections
            self.includesHidden = includesHidden
            self.copying = copying
            self.follows = follows
        }
    }

    public enum Stage: String, Sendable, Hashable, Codable {
        /// Reading the albums' assets.
        case census
        /// Writing their files from Photos, downloading those only in iCloud.
        case staging
        /// The card import's copy.
        case copying
        /// Keeping the record, removing the staging folder.
        case finishing
    }

    /// Where an import has got to: in each stage, the photos done of those it takes.
    public struct Progress: Sendable, Hashable {
        public var stage: Stage
        public var photos: Int
        public var done: Int
        public var failed: Int
        /// The stage's bytes, when known, and those written.
        public var bytes: Int64?
        public var written: Int64
        /// Files Photos is downloading from iCloud now.
        public var downloading: Int
    }

    public struct Outcome: Sendable, Hashable {
        public var id: UUID
        public var state: ApplePhotosRecord.Import.State
        public var report: ApplePhotosReport
        public var staged: Int
        /// Assets whose files Photos couldn't give, with why, by local identifier.
        public var stagingFailures: [String: String]
        /// The card import's outcome; nil when nothing was copied.
        public var copy: ImportOutcome?
        /// Assets this import brought.
        public var imported: Int
        /// Photos placed only in Photos: their files hold no GPS, and sidecars have no field for a place.
        public var placesOnlyInPhotos: Int
    }

    public let photos: any ApplePhotosLibrary
    public let library: ImportLibrary
    public let record: ApplePhotosRecordFile
    private let destinationFileSystem: any LibraryFileSystem
    private let running = Mutex<Task<Outcome, any Error>?>(nil)

    public init(
        photos: any ApplePhotosLibrary, library: ImportLibrary,
        destinationFileSystem: any LibraryFileSystem = LocalFileSystem(),
    ) {
        self.photos = photos
        self.library = library
        record = ApplePhotosRecordFile(paths: library.paths)
        self.destinationFileSystem = destinationFileSystem
    }

    private var importer: Importer {
        Importer(library: library, destinationFileSystem: destinationFileSystem)
    }

    // MARK: - The census

    /// What `settings` would import and leave, reading nothing but the assets' fields; the assets the record
    /// names are left as imported.
    public func census(_ settings: Settings) async throws -> ApplePhotosCensus {
        let imported = try Set(record.load().assets.keys)
        return try await ApplePhotosCensus.make(
            photos, choosing: settings.collections, includesHidden: settings.includesHidden, imported: imported,
        )
    }

    /// The albums followed for their new photos (LIB-55).
    public func followedAlbums() throws -> [ApplePhotosRecord.Album] {
        try record.load().followed
    }

    /// The newest import not undone.
    public func lastImport() throws -> ApplePhotosRecord.Import? {
        try record.load().lastImport
    }

    /// The new photos in the albums followed (LIB-55): the census of every album followed, with the last import's
    /// settings, leaving the assets the record names; and those settings, which import them. Nil while no album is
    /// followed or no import is left to take its settings from. Throws while Redlamp may not read Photos.
    public func followedNews() async throws -> (settings: Settings, census: ApplePhotosCensus)? {
        let current = try record.load()
        guard !current.followed.isEmpty, let last = current.lastImport else { return nil }
        var settings = last.settings
        settings.collections = current.followed.map(\.id)
        settings.follows = true
        let census = try await ApplePhotosCensus.make(
            photos, choosing: settings.collections, includesHidden: settings.includesHidden,
            imported: Set(current.assets.keys),
        )
        return (settings, census)
    }

    // MARK: - Importing

    /// Runs the import `settings` describes, from `census` when it's given (the report shown), as the type
    /// describes, `progress` hearing of each stage. Throws while Redlamp may not read Photos, and while an
    /// import or rollback a forced quit cut short waits (`Importer.recover`).
    @discardableResult
    public func run(
        _ settings: Settings, census: ApplePhotosCensus? = nil, progress: (@Sendable (Progress) -> Void)? = nil,
    ) async throws -> Outcome {
        let task = Task { try await perform(settings, census: census, progress: progress) }
        running.withLock { $0 = task }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Stops the import running: the files being written are let go, and the photos being copied finish.
    public func stop() {
        running.withLock { $0 }?.cancel()
    }

    private func perform(
        _ settings: Settings, census given: ApplePhotosCensus?, progress: (@Sendable (Progress) -> Void)?,
    ) async throws -> Outcome {
        progress?(Progress(stage: .census, photos: 0, done: 0, failed: 0, written: 0, downloading: 0))
        let counted = if let given {
            given
        } else {
            try await census(settings)
        }
        let destination = settings.copying.destination
        let albums = counted.albums.map { album in
            ApplePhotosRecord.Album(
                id: album.id, title: album.title, kind: album.kind, path: counted.tree.path(of: album.id)?.text ?? "",
            )
        }
        var entry = try record.load().imports.last { entry in
            [.staging, .copying, .stopped].contains(entry.state) && entry.settings == settings
                && FileManager.default.fileExists(atPath: ApplePhotosStager(
                    library: photos, destination: destination, id: entry.id,
                ).folder.path)
        } ?? ApplePhotosRecord.Import(id: UUID(), date: Date(), albums: albums, settings: settings, state: .staging)
        entry.state = .staging
        entry.albums = albums
        try keep(entry, following: settings.follows ? albums : [])

        let stager = ApplePhotosStager(library: photos, destination: destination, id: entry.id)
        let staging = await stager.stage(counted.taken) { staged in
            progress?(Progress(
                stage: .staging, photos: staged.assets, done: staged.done, failed: staged.failed, bytes: staged.bytes,
                written: staged.written, downloading: staged.downloading,
            ))
        }
        var outcome = Outcome(
            id: entry.id, state: .stopped, report: counted.report, staged: staging.staged.count,
            stagingFailures: staging.failures, imported: 0, placesOnlyInPhotos: 0,
        )
        guard !staging.stopped, !Task.isCancelled else {
            entry.state = .stopped
            try keep(entry)
            return outcome
        }
        guard !staging.staged.isEmpty else {
            entry.state = .finished
            try keep(entry)
            stager.remove()
            outcome.state = .finished
            return outcome
        }

        entry.state = .copying
        try keep(entry)
        let assets = Dictionary(counted.taken.map { ($0.id, $0) }) { first, _ in first }
        let importer = importer
        if try await !importer.unfinishedEntries().isEmpty {
            try await importer.recover()
        }
        let copy = try await ApplePhotosCopy.plan(
            staging.staged, assets: assets, census: counted, settings: settings.copying, library: library,
            folder: stager.folder, destinationFileSystem: destinationFileSystem,
        )
        entry.plans.append(copy.plan.id)
        try keep(entry)
        let copied = try await importer.run(copy.plan) { copying in
            progress?(Progress(
                stage: .copying, photos: copying.photos, done: copying.done, failed: copying.failed,
                bytes: copying.bytes, written: copying.copied, downloading: 0,
            ))
        }
        outcome.copy = copied

        progress?(Progress(
            stage: .finishing, photos: copy.plan.items.count, done: copied.verified, failed: copied.failures.count,
            written: copied.bytes, downloading: 0,
        ))
        let journal = importer.journal
        let done = try await LibraryIndex.offCaller { try journal.load(copy.plan.id).progress.done }
        let root = LibraryIndexer.path(destination)
        var brought: [String: ApplePhotosRecord.Asset] = [:]
        for index in done.sorted() {
            let item = copy.plan.items[index]
            guard let origin = item.given?.applePhotos else { continue }
            var asset = brought[origin.id] ?? ApplePhotosRecord.Asset(
                cloud: origin.cloud, paths: [], importID: entry.id,
            )
            let paths = item.photos.map { root + "/" + $0.path }
            asset.paths = origin.version == .edited ? asset.paths + paths : paths + asset.paths
            brought[origin.id] = asset
        }
        outcome.imported = brought.count
        outcome.placesOnlyInPhotos = brought.keys.count { copy.placesOnlyInPhotos.contains($0) }
        let finished = copied.state == .finished
        entry.state = finished ? .finished : .stopped
        entry.photos += brought.count
        try record.change { record in
            record.assets.merge(brought) { _, new in new }
            record.keep(entry)
        }
        if finished {
            stager.remove()
        }
        outcome.state = entry.state
        return outcome
    }

    /// Keeps `entry` in the record, following `albums`.
    private func keep(_ entry: ApplePhotosRecord.Import, following albums: [ApplePhotosRecord.Album] = []) throws {
        try record.change { record in
            record.keep(entry)
            record.follow(albums)
        }
    }

    // MARK: - Undo

    /// Takes back import `id`, the newest not undone when nil: each of its copies rolled back as the card import
    /// does (to the Trash, out of the index), its assets out of the record, the albums only it followed
    /// unfollowed, and its staging folder removed. Throws `ApplePhotosImportError.nothingToUndo` when there's none.
    @discardableResult
    public func undo(
        _ id: UUID? = nil, progress: (@Sendable (ImportRollback.Progress) -> Void)? = nil,
    ) async throws -> Undone {
        let current = try record.load()
        guard var entry = id.map({ id in current.imports.first { $0.id == id && $0.state != .undone } })
            ?? current.lastImport
        else { throw ApplePhotosImportError.nothingToUndo }
        let importer = importer
        let journal = try await importer.entries()
        var rollbacks: [ImportRollback] = []
        for plan in entry.plans.reversed() {
            guard let logged = journal.first(where: { $0.id == plan }), logged.state != .rolledBack else { continue }
            try await rollbacks.append(importer.rollBack(plan, progress: progress))
        }
        entry.state = .undone
        try record.change { record in
            record.assets = record.assets.filter { $0.value.importID != entry.id }
            record.keep(entry)
            let kept = Set(record.imports.filter { $0.state != .undone && $0.settings.follows }.flatMap(\.albums)
                .map(\.id))
            let taken = Set(entry.albums.map(\.id))
            record.followed.removeAll { taken.contains($0.id) && !kept.contains($0.id) }
        }
        ApplePhotosStager(library: photos, destination: entry.settings.copying.destination, id: entry.id).remove()
        return Undone(record: entry, rollbacks: rollbacks)
    }

    /// What Undo Import did: the import as the record now keeps it, and each of its copies' rollbacks.
    public struct Undone: Sendable, Hashable {
        public var record: ApplePhotosRecord.Import
        public var rollbacks: [ImportRollback]
    }
}

public enum ApplePhotosImportError: Error, Sendable, Hashable, CustomStringConvertible {
    case nothingToUndo

    public var description: String {
        "there's no import from Apple Photos to undo"
    }
}

/// The card import's plan of a staging folder: its photos read, given Photos' fields and named by their albums.
enum ApplePhotosCopy {
    struct Planned: Sendable {
        var plan: ImportPlan
        /// The assets placed only in Photos, by local identifier.
        var placesOnlyInPhotos: Set<String>
    }

    static func plan(
        _ staged: [ApplePhotosStager.Staged], assets: [String: ApplePhotosAsset], census: ApplePhotosCensus,
        settings: ImportSettings, library: ImportLibrary, folder: URL, destinationFileSystem: any LibraryFileSystem,
    ) async throws -> Planned {
        let byFolder = Dictionary(staged.map { (LibraryIndexer.path($0.folder), $0) }) { first, _ in first }
        let wanted = Set(staged.map(\.folder.lastPathComponent))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            where !wanted.contains(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        let source = try ImportSource.at(folder)
        let session = ImportSession(sources: [source], library: library, makesPreviews: false)
        for await _ in session.browse() {}
        try Task.checkCancellation()

        let order = Dictionary(census.albums.enumerated().map { ($1.id, $0) }) { first, _ in first }
        var placesOnlyInPhotos = Set<String>()
        var origins: [String: (asset: ApplePhotosAsset, version: ApplePhotosOrigin.Version)] = [:]
        for photo in session.photos {
            guard let staged = byFolder[photo.folder], let asset = assets[staged.asset] else { continue }
            let version: ApplePhotosOrigin.Version = photo.primary.name == staged.edit ? .edited : .original
            origins[photo.id] = (asset, version)
            if asset.isFavorite {
                session.flag([photo.id], .pick)
            }
            if let rating = asset.rating, rating > 0 {
                session.rate([photo.id], rating)
            }
            let first = asset.albums.min { (order[$0] ?? .max) < (order[$1] ?? .max) }
            session.album([photo.id], first.flatMap { census.tree[$0]?.title })
            if version == .original, asset.location != nil, photo.metadata?.latitude == nil {
                placesOnlyInPhotos.insert(asset.id)
            }
        }
        var plan = try await session.plan(settings, destinationFileSystem: destinationFileSystem)

        var groups: [String: [Int]] = [:]
        for (index, item) in plan.items.enumerated() {
            guard let (asset, version) = origins[item.photo] else { continue }
            let time = captureTime(given: asset.created, recorded: session.photo(item.photo)?.metadata)
            plan.items[index].given = ImportPlan.Given(
                caption: asset.caption,
                keywords: (asset.keywords ?? []).compactMap { KeywordPath(names: [$0])?.text },
                collections: asset.albums.sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
                    .compactMap { census.tree.path(of: $0)?.text },
                captureShift: time.shift, captureOffset: time.offset,
                applePhotos: ApplePhotosOrigin(id: asset.id, cloud: asset.cloud, version: version),
            )
            groups[asset.burst?.id ?? asset.id, default: []].append(index)
        }
        for indices in groups.values where indices.count > 1 {
            let stack = UUID()
            let top = indices.max { rank(plan.items[$0], origins) < rank(plan.items[$1], origins) }
            for index in indices {
                plan.items[index].given?.stack = PhotoStack(id: stack, top: index == top)
            }
        }
        return Planned(plan: plan, placesOnlyInPhotos: placesOnlyInPhotos)
    }

    /// How a stack's photos rank for its top: a burst's key photo first, then an edit's rendering.
    private static func rank(
        _ item: ImportPlan.Item, _ origins: [String: (asset: ApplePhotosAsset, version: ApplePhotosOrigin.Version)],
    ) -> Int {
        guard let (asset, version) = origins[item.photo] else { return 0 }
        return (asset.burst?.isKey == true ? 2 : 0) + (version == .edited ? 1 : 0)
    }

    /// The shift, and the zone it's in, that give a file the date Photos has for it, `given`: none when that's
    /// the time the file records, `recorded`. A file that records no zone is read in `zone`, which the shift
    /// then names.
    static func captureTime(
        given: Date?, recorded: CaptureMetadata?, zone: TimeZone = .current,
    ) -> (shift: Int, offset: Int?) {
        guard let given, let captured = recorded?.captured else { return (0, nil) }
        let offset = recorded?.capturedOffset ?? zone.secondsFromGMT(for: captured)
        let shift = Int(given.timeIntervalSince(captured.addingTimeInterval(-Double(offset))).rounded())
        guard shift != 0 else { return (0, nil) }
        return (shift, recorded?.capturedOffset == nil ? offset : nil)
    }
}
