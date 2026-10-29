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
/// - **Copy to Folder** (LIB-63, `Settings.photos`) runs it over photos the library keeps in place, as
///   `ApplePhotosKept` describes: their files come from Redlamp's cache of originals and their sidecars from this Mac,
///   and once they're copied the copies stand in for them, so the Photos indexer is asked to bring their rows up to
///   date, and again once Undo Import has taken the copies back.
public final class ApplePhotosImport: Sendable {
    /// What an import takes and where it puts it.
    public struct Settings: Sendable, Hashable, Codable {
        /// The collections chosen, by ID, a folder for its albums; nil for every album
        /// (`ApplePhotosTree.standardChoice`). With `photos`, the albums whose titles `{album}` gives the copies
        /// first, before the other albums kept in place.
        public var collections: [String]?
        public var includesHidden: Bool
        /// The destination, templates, backup and metadata preset, as Import has them.
        public var copying: ImportSettings
        /// The albums are followed for the new photos that arrive in them (LIB-55).
        public var follows: Bool
        /// Copy to Folder (LIB-63): the photos kept in place to copy, by their assets' local identifiers, in place of
        /// albums' photos. Nil for an import of albums.
        public var photos: [String]?

        public init(
            collections: [String]? = nil, includesHidden: Bool = false, copying: ImportSettings, follows: Bool = true,
            photos: [String]? = nil,
        ) {
            self.collections = collections
            self.includesHidden = includesHidden
            self.copying = copying
            self.follows = follows
            self.photos = photos
        }

        /// Copy to Folder over `photos` kept in place, `{album}` naming them by `albums` first: no album followed.
        public static func copyToFolder(
            _ photos: [String], naming albums: [String]? = nil, to copying: ImportSettings,
        ) -> Settings {
            Settings(collections: albums, includesHidden: true, copying: copying, follows: false, photos: photos)
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

        public init(
            stage: Stage, photos: Int, done: Int, failed: Int = 0, bytes: Int64? = nil, written: Int64 = 0,
            downloading: Int = 0,
        ) {
            self.stage = stage
            self.photos = photos
            self.done = done
            self.failed = failed
            self.bytes = bytes
            self.written = written
            self.downloading = downloading
        }
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
    /// Copy to Folder's (LIB-63): the library's cache of originals, which its files are copied from, and the indexer of
    /// the albums it keeps in place, which brings the rows of the photos copied up to date. Without the cache the files
    /// are written from Photos, as an import of albums writes them.
    public let originals: ApplePhotosOriginals?
    public let indexer: ApplePhotosIndexer?
    private let destinationFileSystem: any LibraryFileSystem
    private let running = Mutex<Task<Outcome, any Error>?>(nil)

    public init(
        photos: any ApplePhotosLibrary, library: ImportLibrary,
        destinationFileSystem: any LibraryFileSystem = LocalFileSystem(), originals: ApplePhotosOriginals? = nil,
        indexer: ApplePhotosIndexer? = nil,
    ) {
        self.photos = photos
        self.library = library
        record = ApplePhotosRecordFile(paths: library.paths)
        self.originals = originals
        self.indexer = indexer
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
        if let chosen = settings.photos {
            let kept = try await library.index?.read { try ApplePhotosIndexer.chosen($0).map(\.id) } ?? []
            return try await ApplePhotosCensus.make(
                photos, photos: chosen, naming: settings.collections ?? [], kept: kept, imported: imported,
            )
        }
        return try await ApplePhotosCensus.make(
            photos, choosing: settings.collections, includesHidden: settings.includesHidden, imported: imported,
        )
    }

    /// The albums followed for their new photos (LIB-55).
    public func followedAlbums() throws -> [ApplePhotosRecord.Album] {
        try record.load().followed
    }

    /// The newest import of albums not undone, whose albums the import window chooses again: Copy to Folder's are left
    /// out.
    public func lastImport() throws -> ApplePhotosRecord.Import? {
        try record.load().lastAlbumImport
    }

    /// The new photos in the albums followed (LIB-55): the census of every album followed and not kept in place, with
    /// the last import of albums' settings, leaving the assets the record names; and those settings, which import them.
    /// Nil while no album is followed but those kept in place, or no import of albums is left to take its settings
    /// from. Throws while Redlamp may not read Photos.
    public func followedNews() async throws -> (settings: Settings, census: ApplePhotosCensus)? {
        let current = try record.load()
        guard !current.followed.isEmpty, let last = current.lastAlbumImport else { return nil }
        let followed = try await copied(current.followed)
        guard !followed.isEmpty else { return nil }
        var settings = last.settings
        settings.collections = followed.map(\.id)
        settings.follows = true
        let census = try await ApplePhotosCensus.make(
            photos, choosing: settings.collections, includesHidden: settings.includesHidden,
            imported: Set(current.assets.keys),
        )
        return (settings, census)
    }

    /// Those of the albums `followed` that aren't kept in place (LIB-64, decision 6): an album kept in place, or in a
    /// folder kept, follows Photos by itself, so the albums imports follow are offered only while they're copied.
    private func copied(_ followed: [ApplePhotosRecord.Album]) async throws -> [ApplePhotosRecord.Album] {
        guard let index = library.index else { return followed }
        let kept = try await index.read { try ApplePhotosIndexer.chosen($0) }.map(\.id)
        guard !kept.isEmpty else { return followed }
        let inPlace = try await Set(ApplePhotosTree(photos.collections()).albums(in: kept).map(\.id)).union(kept)
        return followed.filter { !inPlace.contains($0.id) }
    }

    /// The albums, smart and shared albums of `tree` kept in place (LIB-62), those in a folder kept included, by ID:
    /// Add Albums from Apple Photos… shows them In Library.
    public func keptInPlace(in tree: ApplePhotosTree) async throws -> Set<String> {
        guard let index = library.index else { return [] }
        let kept = try await index.read { try ApplePhotosIndexer.chosen($0) }.map(\.id)
        return Set(tree.albums(in: kept).map(\.id))
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
        let named = settings.photos == nil ? nil : Set(settings.collections ?? [])
        let albums = counted.albums.filter { named?.contains($0.id) ?? true }.map { album in
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

        var kept: ApplePhotosKept?
        if settings.photos != nil {
            kept = try await ApplePhotosKept.read(counted.taken.map(\.id), library: library, originals: originals)
        }
        let stager = ApplePhotosStager(library: photos, destination: destination, id: entry.id, kept: kept)
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
            folder: stager.folder, destinationFileSystem: destinationFileSystem, kept: kept,
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
        if let kept, !brought.isEmpty {
            await standIn(Set(brought.keys), kept: kept)
        }
        outcome.state = entry.state
        return outcome
    }

    /// The copies of the photos kept in place `ids` names standing in for them (LIB-63, decision 9): the Photos
    /// indexer brings their rows up to date, which leaves them out of the library now that their copies are in it,
    /// and their originals leave Redlamp's cache, which nothing shows any more.
    private func standIn(_ ids: Set<String>, kept: ApplePhotosKept) async {
        _ = try? await indexer?.refresh(ids)
        await originals?.evict(kept.urls(of: ids))
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
    /// unfollowed, and its staging folder removed; for Copy to Folder's, the photos it copied kept in place listed
    /// again, with what Redlamp kept of them. Throws `ApplePhotosImportError.nothingToUndo` when there's none.
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
        let brought = try record.change { record in
            let brought = Set(record.assets.filter { $0.value.importID == entry.id }.keys)
            record.assets = record.assets.filter { $0.value.importID != entry.id }
            record.keep(entry)
            let kept = Set(record.imports.filter { $0.state != .undone && $0.settings.follows }.flatMap(\.albums)
                .map(\.id))
            let taken = Set(entry.albums.map(\.id))
            record.followed.removeAll { taken.contains($0.id) && !kept.contains($0.id) }
            return brought
        }
        ApplePhotosStager(library: photos, destination: entry.settings.copying.destination, id: entry.id).remove()
        if entry.settings.photos != nil, !brought.isEmpty {
            _ = try? await indexer?.refresh(brought)
        }
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

/// The card import's plan of a staging folder: its photos read, given Photos' fields and named by their albums. For
/// Copy to Folder (`kept`, LIB-63), the sidecars staged with them hold what Redlamp keeps of them, which stands over
/// Photos' fields, and no album becomes a collection.
enum ApplePhotosCopy {
    struct Planned: Sendable {
        var plan: ImportPlan
        /// The assets placed only in Photos, by local identifier.
        var placesOnlyInPhotos: Set<String>
    }

    static func plan(
        _ staged: [ApplePhotosStager.Staged], assets: [String: ApplePhotosAsset], census: ApplePhotosCensus,
        settings: ImportSettings, library: ImportLibrary, folder: URL, destinationFileSystem: any LibraryFileSystem,
        kept: ApplePhotosKept? = nil,
    ) async throws -> Planned {
        let byFolder = Dictionary(staged.map { (LibraryIndexer.path($0.folder), $0) }) { first, _ in first }
        let wanted = Set(staged.map(\.folder.lastPathComponent))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            where !wanted.contains(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        let prepared = try kept?.prepare(staged, assets: assets)
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
            if prepared == nil, asset.isFavorite {
                session.flag([photo.id], .pick)
            }
            if prepared == nil, let rating = asset.rating, rating > 0 {
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
            let origin = ApplePhotosOrigin(id: asset.id, cloud: asset.cloud, version: version)
            let recorded = session.photo(item.photo)?.metadata
            if let prepared {
                let own = prepared.captureTimes[item.photo]
                let time = captureTime(
                    given: asset.created?.addingTimeInterval(Double(own?.shift ?? 0)), recorded: recorded,
                )
                plan.items[index].given = ImportPlan.Given(
                    captureShift: time.shift, captureOffset: own?.offset == nil ? time.offset : nil,
                    applePhotos: origin,
                )
                if prepared.stacked.contains(item.photo) {
                    continue
                }
            } else {
                let time = captureTime(given: asset.created, recorded: recorded)
                plan.items[index].given = ImportPlan.Given(
                    caption: asset.caption,
                    keywords: (asset.keywords ?? []).compactMap { KeywordPath(names: [$0])?.text },
                    collections: asset.albums.sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
                        .compactMap { census.tree.path(of: $0)?.text },
                    captureShift: time.shift, captureOffset: time.offset, applePhotos: origin,
                )
            }
            groups[asset.burst?.id ?? asset.id, default: []].append(index)
        }
        let edited = prepared?.editedOriginals ?? []
        for indices in groups.values where indices.count > 1 {
            let stack = UUID()
            let top = indices.max { rank(plan.items[$0], origins, edited) < rank(plan.items[$1], origins, edited) }
            for index in indices {
                plan.items[index].given?.stack = PhotoStack(id: stack, top: index == top)
            }
        }
        return Planned(plan: plan, placesOnlyInPhotos: placesOnlyInPhotos)
    }

    /// How a stack's photos rank for its top: a burst's key photo first, then an edit's rendering, unless its original
    /// has a Redlamp edit (`edited`, by local identifier), which then goes on top, as the library shows it in place.
    private static func rank(
        _ item: ImportPlan.Item, _ origins: [String: (asset: ApplePhotosAsset, version: ApplePhotosOrigin.Version)],
        _ edited: Set<String>,
    ) -> Int {
        guard let (asset, version) = origins[item.photo] else { return 0 }
        return (asset.burst?.isKey == true ? 2 : 0) + ((version == .edited) != edited.contains(asset.id) ? 1 : 0)
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
