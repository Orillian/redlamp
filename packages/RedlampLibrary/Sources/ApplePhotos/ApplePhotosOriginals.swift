import Foundation
import Network
import Synchronization

/// Originals of photos left in Apple Photos, downloaded from iCloud only when they're viewed at full size, edited,
/// exported or copied, never for browsing (LIB-60, DEC-107). Each lands at its row's address in Redlamp's cache,
/// written
/// to a partial file beside it and renamed once complete, so a cancelled or failed download leaves nothing behind.
///
/// Downloads queue by priority, a photo someone is waiting to see before an export's, an export's before Download
/// Originals', those before the next photo ahead; one asked for twice is downloaded once, and lets go only once nothing
/// wants it. The cache keeps originals up to a budget, 20 GB unless Settings says otherwise, the least recently opened
/// removed first, never one held (the photo open in Develop, one an export or a copy is reading) nor one downloading.
/// macOS may empty the cache too: a photo whose file went is downloaded again when it's next needed. When an original
/// first arrives its camera, lens and exposure are read into its row (decision 10).
public final class ApplePhotosOriginals: Sendable {
    /// What a download is for, which orders the queue.
    public enum Priority: Int, Sendable, Hashable, Comparable, CaseIterable {
        /// The next photo in Develop's filmstrip, on networks macOS doesn't mark as expensive.
        case ahead
        /// Download Originals.
        case request
        /// An export's or a copy's.
        case export
        /// Opened in Develop, or seen at 1:1, in Compare or Survey, or with focus peaking: someone waits for it.
        case open

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// How far a download has come.
    public struct Progress: Sendable, Hashable {
        /// From 0 to 1.
        public var fraction: Double
        /// The file's size in bytes, when Photos says: PhotoKit does from macOS 27.
        public var total: Int64?

        public init(fraction: Double, total: Int64? = nil) {
            self.fraction = fraction
            self.total = total
        }

        public var received: Int64? {
            total.map { Int64((Double($0) * min(max(fraction, 0), 1)).rounded()) }
        }
    }

    /// Why an original couldn't be had.
    public enum Failure: LocalizedError, Sendable, Hashable, CustomStringConvertible {
        /// iCloud can't be reached, and the original is only there.
        case offline
        /// Photos no longer has the photo, or it isn't a row of the Apple Photos root.
        case notInPhotos
        /// Redlamp may not read Photos.
        case noAccess
        /// Photos couldn't give it: what it said.
        case failed(String)

        public var description: String {
            switch self {
            case .offline: "iCloud can't be reached: this photo's original isn't on this Mac"
            case .notInPhotos: "Apple Photos no longer has this photo"
            case .noAccess: "Redlamp isn't allowed to read Photos"
            case let .failed(message): message
            }
        }

        public var errorDescription: String? {
            description
        }
    }

    /// Where a download stands, for the photos and the toolbar to show.
    public enum Status: Sendable, Hashable {
        case queued
        case downloading(Progress)
    }

    /// What the cache tells those listening.
    public enum Event: Sendable, Hashable {
        /// A download queued, or how far it has come.
        case status(URL, Status)
        case arrived(URL)
        /// A download that failed, other than by being cancelled.
        case failed(URL, Failure)
        case cancelled(URL)
        /// Originals taken out to keep the budget, or by Empty Cache.
        case evicted([URL])
    }

    /// The originals the cache holds, and its budget.
    public struct Usage: Sendable, Hashable {
        public var files: Int
        public var bytes: Int64
        public var budget: Int64
    }

    /// 20 GB (decision 2).
    public static let defaultBudget: Int64 = 20_000_000_000
    /// Downloads under way at once, besides those someone is waiting for, which start at once.
    static let width = 2
    static let budgetKey = "library.applePhotos.originalsBudget"
    /// Extended attributes on each original: when it was last opened, and the content version it was downloaded at.
    static let openedAttribute = "app.redlamp.opened"
    static let versionAttribute = "app.redlamp.version"
    /// The partial file a download writes beside its original: `.<name>.download`.
    static let partialExtension = "download"

    public let index: LibraryIndex
    public let paths: LibraryPaths
    public let live: LibraryLive?
    private let photos: @Sendable () -> any ApplePhotosLibrary
    private let network: any ApplePhotosNetwork
    /// The Apple Photos root's path, with a slash at its end: its rows are below it.
    private let below: String
    private let state = Mutex(State())
    /// What's in the cache as it opens, and its budget, read once before anything else touches it.
    private let opening: Task<(budget: Int64?, files: [String: Entry]), Never>

    private struct Job {
        let id = UUID()
        var priority: Priority
        /// When it was first asked for, which orders jobs of one priority.
        var asked: Int
        /// Those waiting for it, each with what hears its progress.
        var waiters: [UUID: Waiter] = [:]
        /// Asked for without waiting, by Download Originals or ahead of Develop: kept until it's done or cancelled.
        var requested = false
        var task: Task<Void, Never>?
        var status = Status.queued
    }

    private struct Waiter {
        let continuation: CheckedContinuation<URL, any Error>
        let progress: (@Sendable (Progress) -> Void)?
    }

    /// An original in the cache.
    private struct Entry {
        var bytes: Int64
        var opened: Date
    }

    private struct State {
        /// What was in the cache as it opened is in `files`.
        var opened = false
        var jobs: [String: Job] = [:]
        var asked = 0
        /// Waiters cancelled before they were registered.
        var cancelledWaiters = Set<UUID>()
        var files: [String: Entry] = [:]
        var holds: [String: Int] = [:]
        var budget = ApplePhotosOriginals.defaultBudget
        var observers: [UUID: AsyncStream<Event>.Continuation] = [:]

        var running: Int {
            jobs.values.count { $0.task != nil }
        }

        var bytes: Int64 {
            files.values.reduce(0) { $0 + $1.bytes }
        }
    }

    /// The cache of the library at `paths`, whose rows `index` has, downloading from the Photos library `photos` gives
    /// as each download starts, so it follows a simulated library standing in.
    public init(
        index: LibraryIndex, paths: LibraryPaths, live: LibraryLive? = nil,
        photos: @escaping @Sendable () -> any ApplePhotosLibrary,
        network: any ApplePhotosNetwork = SystemNetwork.shared,
    ) {
        self.index = index
        self.paths = paths
        self.live = live
        self.photos = photos
        self.network = network
        below = LibraryIndexer.path(ApplePhotosPlace.root(in: paths)) + "/"
        opening = Task.detached(priority: .utility) {
            let budget = await (try? index.read { try $0.setting(Self.budgetKey) }).flatMap { $0.flatMap(Int64.init) }
            return (budget, Self.scan(ApplePhotosPlace.root(in: paths)))
        }
    }

    /// Waits until what was in the cache as it opened, and its budget, are read.
    private func ready() async {
        guard !state.withLock(\.opened) else { return }
        let (budget, files) = await opening.value
        state.withLock { state in
            guard !state.opened else { return }
            state.opened = true
            state.budget = budget ?? Self.defaultBudget
            for (path, entry) in files where state.files[path] == nil {
                state.files[path] = entry
            }
        }
    }

    deinit {
        for job in state.withLock({ Array($0.jobs.values) }) {
            job.task?.cancel()
        }
    }

    // MARK: - Originals

    /// Whether `url` is a row of the Apple Photos root, whose file is the cache's.
    public func owns(_ url: URL) -> Bool {
        LibraryIndexer.path(url).hasPrefix(below)
    }

    /// Whether `url`'s original is in the cache, as far as the cache knows without looking once it has opened: from
    /// any thread, the main one included.
    public func isLocal(_ url: URL) -> Bool {
        let path = LibraryIndexer.path(url)
        return state.withLock { state in
            state.files[path] != nil ? true : state.opened ? false : nil
        } ?? FileManager.default.fileExists(atPath: path)
    }

    /// Where `url`'s download stands; nil for none.
    public func status(of url: URL) -> Status? {
        let path = LibraryIndexer.path(url)
        return state.withLock { $0.jobs[path]?.status }
    }

    /// The downloads queued or under way.
    public var downloads: [URL: Status] {
        state.withLock { state in
            Dictionary(uniqueKeysWithValues: state.jobs.map { (URL(fileURLWithPath: $0.key), $0.value.status) })
        }
    }

    /// `url`'s original, downloaded first when the cache hasn't it, `progress` hearing how far it has come. Cancelling
    /// the task lets go of the download, unless something else wants it too. Throws a `Failure`, or
    /// `CancellationError`.
    @discardableResult
    public func local(
        _ url: URL, priority: Priority = .open, progress: (@Sendable (Progress) -> Void)? = nil,
    ) async throws -> URL {
        await ready()
        let path = LibraryIndexer.path(url)
        guard owns(url) else { throw Failure.notInPhotos }
        let row = try await row(at: path)
        if try current(path, row: row) {
            touch(path)
            return url
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(path, priority: priority, waiter: (id, Waiter(continuation: continuation, progress: progress)))
            }
        } onCancel: {
            letGo(id, of: path)
        }
    }

    /// Queues downloads of the originals of `urls` the cache hasn't, without waiting for them: Download Originals, the
    /// next photo ahead. Ahead of Develop, only on networks macOS doesn't mark as expensive or constrained, and one at
    /// a
    /// time: asking for another lets go of the last, unless it's wanted otherwise.
    public func request(_ urls: [URL], priority: Priority = .request) {
        let wanted = urls.filter(owns).map(LibraryIndexer.path)
        guard !wanted.isEmpty, priority != .ahead || !network.isExpensive else { return }
        Task.detached(priority: .utility) { [self] in
            await ready()
            if priority == .ahead {
                letGoAhead(except: Set(wanted))
            }
            for path in wanted where !FileManager.default.fileExists(atPath: path) {
                enqueue(path, priority: priority, waiter: nil)
            }
        }
    }

    /// Queues downloads of the originals of the photos `ids` names that are the Apple Photos root's, a version as its
    /// file: Download Originals on a selection, its rows read or not.
    public func request(photos ids: [Int64], priority: Priority = .request) {
        guard !ids.isEmpty else { return }
        Task.detached(priority: .utility) { [self] in
            let paths = await (try? index.read { try $0.applePhotosPaths(ofPhotos: ids) }) ?? []
            request(paths.map { URL(fileURLWithPath: $0, isDirectory: false) }, priority: priority)
        }
    }

    /// Cancels the downloads of `urls`, for everything waiting for them.
    public func cancel(_ urls: [URL]) {
        let paths = Set(urls.map(LibraryIndexer.path))
        cancel { paths.contains($0) }
    }

    /// Cancels every download: the toolbar's Cancel All.
    public func cancelAll() {
        cancel { _ in true }
    }

    /// Keeps `url`'s original from being taken out until it's let go as often: the photo open in Develop, one an
    /// export or a copy is reading.
    public func hold(_ url: URL) {
        let path = LibraryIndexer.path(url)
        state.withLock { $0.holds[path, default: 0] += 1 }
    }

    public func release(_ url: URL) {
        let path = LibraryIndexer.path(url)
        state.withLock { state in
            let held = (state.holds[path] ?? 1) - 1
            state.holds[path] = held > 0 ? held : nil
        }
        Task.detached(priority: .utility) { [self] in await trim() }
    }

    /// Hears of downloads queued, their progress, arrivals, failures and originals taken out, until the stream is let
    /// go.
    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        state.withLock { $0.observers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.observers.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: - The budget

    /// The originals the cache holds, and its budget.
    public func usage() async -> Usage {
        await ready()
        return state.withLock { Usage(files: $0.files.count, bytes: $0.bytes, budget: $0.budget) }
    }

    /// Keeps the cache within `bytes` from now on, kept in the library's index, and takes out what's over it.
    public func setBudget(_ bytes: Int64) async throws {
        await ready()
        let budget = max(bytes, 0)
        try await index.write { try $0.setSetting(
            budget == Self.defaultBudget ? nil : String(budget),
            for: Self.budgetKey,
        ) }
        state.withLock { $0.budget = budget }
        await trim()
    }

    /// Takes out every original but those held or downloading: Settings' Empty Cache and `--evict`. Returns what went.
    @discardableResult
    public func empty() async -> Usage {
        await ready()
        return await evict { _, _ in true }
    }

    /// Takes out the originals of `urls` but those held or downloading: photos whose copies stand in for them now
    /// (LIB-63), so nothing shows them. Returns what went.
    @discardableResult
    public func evict(_ urls: [URL]) async -> Usage {
        await ready()
        let paths = Set(urls.map(LibraryIndexer.path))
        return await evict(choosing: { paths.contains($0) }) { _, _ in true }
    }

    /// Takes out the least recently opened originals until the cache is within its budget.
    func trim() async {
        await ready()
        _ = await evict { bytes, budget in bytes > budget }
    }

    /// Takes out originals not held nor downloading of those `chosen` picks, the least recently opened first, while
    /// `over` says so of the bytes kept and the budget.
    private func evict(
        choosing chosen: @escaping @Sendable (String) -> Bool = { _ in true },
        while over: @escaping @Sendable (Int64, Int64) -> Bool,
    ) async -> Usage {
        let (taken, budget) = state.withLock { state -> ([(String, Entry)], Int64) in
            var bytes = state.bytes
            var taken: [(String, Entry)] = []
            let candidates = state.files
                .filter { chosen($0.key) && state.holds[$0.key] == nil && state.jobs[$0.key] == nil }
                .sorted { $0.value.opened < $1.value.opened }
            for (path, entry) in candidates {
                guard over(bytes, state.budget) else { break }
                state.files[path] = nil
                bytes -= entry.bytes
                taken.append((path, entry))
            }
            return (taken, state.budget)
        }
        guard !taken.isEmpty else { return Usage(files: 0, bytes: 0, budget: budget) }
        let manager = FileManager.default
        for (path, _) in taken {
            try? manager.removeItem(atPath: path)
            let folder = (path as NSString).deletingLastPathComponent
            if (try? manager.contentsOfDirectory(atPath: folder))?.isEmpty == true {
                try? manager.removeItem(atPath: folder)
            }
        }
        tell(.evicted(taken.map { URL(fileURLWithPath: $0.0, isDirectory: false) }))
        return Usage(files: taken.count, bytes: taken.reduce(0) { $0 + $1.1.bytes }, budget: budget)
    }

    // MARK: - The queue

    /// Asks for `path`'s download, `waiter` waiting for it, or none for one only requested; starts what can start. A
    /// download cancelled and still stopping is replaced by a new one.
    private func enqueue(_ path: String, priority: Priority, waiter: (id: UUID, waiter: Waiter)?) {
        let refused = state.withLock { state -> Bool in
            if let waiter, state.cancelledWaiters.remove(waiter.id) != nil {
                return true
            }
            let existing = state.jobs[path].flatMap { $0.task?.isCancelled == true ? nil : $0 }
            var job = existing ?? Job(priority: priority, asked: state.asked)
            if existing == nil {
                state.asked += 1
            }
            job.priority = max(job.priority, priority)
            if let waiter {
                job.waiters[waiter.id] = waiter.waiter
            } else {
                job.requested = true
            }
            state.jobs[path] = job
            return false
        }
        if refused {
            waiter?.waiter.continuation.resume(throwing: CancellationError())
            return
        }
        tell(.status(URL(fileURLWithPath: path, isDirectory: false), status(ofPath: path) ?? .queued))
        startWhatCan()
    }

    private func status(ofPath path: String) -> Status? {
        state.withLock { $0.jobs[path]?.status }
    }

    /// Starts the queued downloads there's room for, the highest priority first: those someone waits to see at once.
    /// Each is downloading from when it starts, before Photos says how far it has come.
    private func startWhatCan() {
        let started = state.withLock { state -> [(String, Status)] in
            let queued = state.jobs.filter { $0.value.task == nil }
                .sorted { ($0.value.priority, -$0.value.asked) > ($1.value.priority, -$1.value.asked) }
            var running = state.running
            var started: [(String, Status)] = []
            for (path, job) in queued where running < Self.width || job.priority == .open {
                let id = job.id
                let status = Status.downloading(Progress(fraction: 0))
                state.jobs[path]?.status = status
                state.jobs[path]?.task = Task.detached(priority: job.priority == .open ? .userInitiated : .utility) {
                    [self] in
                    await run(path, job: id)
                }
                running += 1
                started.append((path, status))
            }
            return started
        }
        for (path, status) in started {
            tell(.status(URL(fileURLWithPath: path, isDirectory: false), status))
        }
    }

    /// A waiter whose task was cancelled lets go of its download, which stops once nothing else wants it.
    private func letGo(_ waiter: UUID, of path: String) {
        let (found, stopped) = state.withLock { state -> (Waiter?, Job?) in
            guard var job = state.jobs[path], let found = job.waiters.removeValue(forKey: waiter) else {
                state.cancelledWaiters.insert(waiter)
                return (nil, nil)
            }
            guard job.waiters.isEmpty, !job.requested else {
                state.jobs[path] = job
                return (found, nil)
            }
            if job.task == nil {
                state.jobs[path] = nil
            } else {
                state.jobs[path] = job
            }
            return (found, job)
        }
        found?.continuation.resume(throwing: CancellationError())
        if let stopped {
            if let task = stopped.task {
                task.cancel()
            } else {
                tell(.cancelled(URL(fileURLWithPath: path, isDirectory: false)))
            }
        }
    }

    /// Lets go of the downloads only asked for ahead of Develop, but those of `kept`.
    private func letGoAhead(except kept: Set<String>) {
        cancel { path in !kept.contains(path) } where: { $0.priority == .ahead && $0.waiters.isEmpty }
    }

    /// Cancels the downloads of the paths `chosen` picks whose jobs `wanted` picks: those queued go at once, and those
    /// under way stop, their waiters told at once in both cases.
    private func cancel(
        _ chosen: (String) -> Bool, where wanted: (Job) -> Bool = { _ in true },
    ) {
        let (queued, waiters, running) = state.withLock { state -> ([String], [Waiter], [Task<Void, Never>]) in
            var queued: [String] = []
            var waiters: [Waiter] = []
            var running: [Task<Void, Never>] = []
            for (path, job) in state.jobs where chosen(path) && wanted(job) && job.task?.isCancelled != true {
                waiters += job.waiters.values
                if let task = job.task {
                    state.jobs[path]?.waiters = [:]
                    running.append(task)
                } else {
                    state.jobs[path] = nil
                    queued.append(path)
                }
            }
            return (queued, waiters, running)
        }
        for waiter in waiters {
            waiter.continuation.resume(throwing: CancellationError())
        }
        for task in running {
            task.cancel()
        }
        for path in queued {
            tell(.cancelled(URL(fileURLWithPath: path, isDirectory: false)))
        }
    }

    /// Downloads `path`, then tells its waiters, and starts what's next. A job replaced while it stopped tells nothing:
    /// the one in its place does.
    private func run(_ path: String, job: UUID) async {
        let url = URL(fileURLWithPath: path, isDirectory: false)
        let outcome: Result<URL, any Error>
        do {
            try await download(url, job: job)
            outcome = .success(url)
        } catch is CancellationError {
            outcome = .failure(CancellationError())
        } catch {
            outcome = .failure(Self.failure(error, network: network))
        }
        let waiters = state.withLock { state -> [Waiter]? in
            guard let found = state.jobs[path], found.id == job else { return nil }
            state.jobs[path] = nil
            return Array(found.waiters.values)
        }
        guard let waiters else {
            startWhatCan()
            return
        }
        switch outcome {
        case let .success(url):
            for waiter in waiters {
                waiter.continuation.resume(returning: url)
            }
            tell(.arrived(url))
            await trim()
        case let .failure(error):
            for waiter in waiters {
                waiter.continuation.resume(throwing: error)
            }
            if let failure = error as? Failure {
                tell(.failed(url, failure))
            } else {
                tell(.cancelled(url))
            }
        }
        startWhatCan()
    }

    /// The download itself: the asset's file as Photos has it, written to a partial file of the job's own in its
    /// folder, then renamed; its camera, lens and exposure read into its row the first time.
    private func download(_ url: URL, job: UUID) async throws {
        let path = LibraryIndexer.path(url)
        let row = try await row(at: path)
        guard try !current(path, row: row) else { return }
        let library = photos()
        guard let asset = try await library.assets(withIDs: [row.local]).first,
              let resource = asset.resources.first(where: { $0.kind == row.resource.kind })
        else { throw Failure.notInPhotos }
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        Self.excludeFromBackups(paths.applePhotos)
        let partial = Self.partial(of: url, job: job)
        let total = resource.size
        do {
            try await library.write(resource, of: row.local, to: partial) { [weak self] fraction in
                self?.progressed(path, Progress(fraction: fraction, total: total))
            }
            try Task.checkCancellation()
            if manager.fileExists(atPath: path) {
                try manager.removeItem(atPath: path)
            }
            try manager.moveItem(at: partial, to: url)
        } catch {
            try? manager.removeItem(at: partial)
            if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? manager.removeItem(at: folder)
            }
            throw error
        }
        let now = Date()
        Self.setAttribute(Self.versionAttribute, row.contentVersion.timeIntervalSince1970, of: url)
        Self.setAttribute(Self.openedAttribute, now.timeIntervalSince1970, of: url)
        let bytes = Self.bytes(of: url)
        state.withLock { $0.files[path] = Entry(bytes: bytes, opened: now) }
        if !row.hasCamera {
            await readCamera(of: url, photo: row.photo)
        }
    }

    /// Reads the camera, lens and exposure of the original at `url`, which PhotoKit doesn't give (decision 10), into
    /// the
    /// rows of its file, `photo` and its versions, and tells open lists. Photos' date, place and size stay as Photos
    /// has
    /// them.
    private func readCamera(of url: URL, photo: Int64) async {
        guard let metadata = PhotoMetadataReader.read(url: url),
              metadata.cameraName != nil || metadata.lens != nil || metadata.iso != nil
        else { return }
        let updated = try? await index.write { writer -> [Int64] in
            let camera = try metadata.cameraName.map { try writer.cameraID(
                for: $0,
                make: metadata.make,
                model: metadata.model,
            ) }
            let lens = try metadata.lens.map { try writer.lensID(for: $0) }
            let rows = try writer.database.cached("""
            SELECT p.id FROM photos p JOIN photos f ON f.folder = p.folder AND f.name = p.name WHERE f.id = ?
            """)
            try rows.bind(photo, at: 1)
            var records: [PhotoRecord] = []
            for id in try rows.map({ $0.int64(at: 0) }) {
                guard var record = try writer.photo(id: id) else { continue }
                record.camera = camera ?? record.camera
                record.lens = lens ?? record.lens
                record.iso = metadata.iso ?? record.iso
                record.aperture = metadata.aperture ?? record.aperture
                record.shutter = metadata.shutter ?? record.shutter
                record.focal = metadata.focalLength ?? record.focal
                record.widestAperture = metadata.widestAperture ?? record.widestAperture
                record.focal35 = metadata.focal35 ?? record.focal35
                records.append(record)
            }
            return try writer.upsertPhotos(records)
        }
        if let updated, !updated.isEmpty {
            live?.receive(.photosUpdated(updated))
        }
    }

    private func progressed(_ path: String, _ progress: Progress) {
        let waiters = state.withLock { state -> [Waiter]? in
            guard state.jobs[path] != nil else { return nil }
            state.jobs[path]?.status = .downloading(progress)
            return state.jobs[path].map { Array($0.waiters.values) }
        }
        guard let waiters else { return }
        for waiter in waiters {
            waiter.progress?(progress)
        }
        tell(.status(URL(fileURLWithPath: path, isDirectory: false), .downloading(progress)))
    }

    private func tell(_ event: Event) {
        for observer in state.withLock({ Array($0.observers.values) }) {
            observer.yield(event)
        }
    }

    // MARK: - Files

    /// The row at `path`, as its download needs it.
    private func row(at path: String) async throws -> ApplePhotosOriginalRow {
        guard let row = try await index.read({ try $0.applePhotosOriginal(atPath: path) }) else {
            throw Failure.notInPhotos
        }
        return row
    }

    /// Whether the cache's file for `row` is there and shows its picture as it is now: Photos' edit is downloaded again
    /// once it's edited again in Photos. One that doesn't is taken out.
    private func current(_ path: String, row: ApplePhotosOriginalRow) throws -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            state.withLock { _ = $0.files.removeValue(forKey: path) }
            return false
        }
        let url = URL(fileURLWithPath: path, isDirectory: false)
        guard row.resource == .edit,
              Self.attribute(Self.versionAttribute, of: url) != row.contentVersion.timeIntervalSince1970
        else {
            if state.withLock({ $0.files[path] == nil }) {
                let entry = Entry(bytes: Self.bytes(of: url), opened: Date())
                state.withLock { $0.files[path] = entry }
            }
            return true
        }
        guard state.withLock({ $0.holds[path] == nil }) else { return true }
        try FileManager.default.removeItem(atPath: path)
        state.withLock { _ = $0.files.removeValue(forKey: path) }
        return false
    }

    /// Marks `path` as opened now, so it's the last the budget takes out.
    private func touch(_ path: String) {
        let now = Date()
        state.withLock { $0.files[path]?.opened = now }
        Self.setAttribute(Self.openedAttribute, now.timeIntervalSince1970, of: URL(fileURLWithPath: path))
    }

    /// The partial file job `job` writes `url`'s original to: `.<name>.<job>.download`, beside it.
    static func partial(of url: URL, job: UUID) -> URL {
        url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).\(job.uuidString).\(partialExtension)")
    }

    /// The originals under `root`, each asset's folder's files, and when each was last opened; partial files a quit cut
    /// short are taken out.
    private static func scan(_ root: URL) -> [String: Entry] {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(atPath: root.path) else { return [:] }
        excludeFromBackups(root.deletingLastPathComponent())
        var files: [String: Entry] = [:]
        for folder in folders where !folder.hasPrefix(".") {
            let place = root.appending(path: folder, directoryHint: .isDirectory)
            for name in (try? manager.contentsOfDirectory(atPath: place.path)) ?? [] {
                let url = place.appending(path: name, directoryHint: .notDirectory)
                if name.hasPrefix(".") {
                    if url.pathExtension == partialExtension {
                        try? manager.removeItem(at: url)
                    }
                    continue
                }
                let opened = attribute(openedAttribute, of: url).map(Date.init(timeIntervalSince1970:))
                    ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                files[LibraryIndexer.path(url)] = Entry(bytes: bytes(of: url), opened: opened)
            }
        }
        return files
    }

    private static func bytes(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    /// Time Machine leaves `~/Library/Caches` out; a library elsewhere has its cache marked so.
    private static func excludeFromBackups(_ folder: URL) {
        var folder = folder
        guard FileManager.default.fileExists(atPath: folder.path),
              (try? folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) != true
        else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    private static func setAttribute(_ name: String, _ value: Double, of url: URL) {
        var value = value
        _ = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return setxattr(path, name, &value, MemoryLayout<Double>.size, 0, 0)
        }
    }

    private static func attribute(_ name: String, of url: URL) -> Double? {
        var value = 0.0
        let read = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return getxattr(path, name, &value, MemoryLayout<Double>.size, 0, 0)
        }
        return read == MemoryLayout<Double>.size ? value : nil
    }

    /// `error` as the cache tells it: iCloud out of reach when Photos says so, or when the network was down as Photos
    /// failed.
    static func failure(_ error: any Error, network: any ApplePhotosNetwork) -> Failure {
        switch error {
        case let failure as Failure: failure
        case ApplePhotosError.offline: .offline
        case ApplePhotosError.notFound: .notInPhotos
        case ApplePhotosError.noAccess: .noAccess
        case is CocoaError: .failed(error.localizedDescription)
        case _ where !network.isReachable: .offline
        case let error as ApplePhotosError: .failed(error.description)
        default: .failed(error.localizedDescription)
        }
    }
}

/// A row of the Apple Photos root as its original's download needs it.
struct ApplePhotosOriginalRow: Sendable, Hashable {
    var photo: Int64
    var local: String
    var resource: ApplePhotosRow.Resource
    var contentVersion: Date
    /// Its camera was read from its original already.
    var hasCamera: Bool
}

extension ApplePhotosRow.Resource {
    /// Which of the asset's files Photos has it as.
    var kind: ApplePhotosResource.Kind {
        switch self {
        case .original: .photo
        case .alternate: .alternatePhoto
        case .edit: .fullSizePhoto
        }
    }
}

extension IndexQueries {
    /// The paths of the files of the photos `ids` names that are rows of the Apple Photos root, each once, in their
    /// order.
    func applePhotosPaths(ofPhotos ids: [Int64]) throws -> [String] {
        let statement = try database.cached("""
        SELECT f.path, p.name FROM photos p JOIN folders f ON f.id = p.folder JOIN roots r ON r.id = f.root
          WHERE p.id = ? AND r.kind = \(RootRecord.Kind.applePhotos.rawValue)
        """)
        var seen = Set<String>()
        var paths: [String] = []
        for id in ids {
            try statement.bind(id, at: 1)
            try statement.forEachRow { row in
                let path = (row.string(at: 0) ?? "") + "/" + (row.string(at: 1) ?? "")
                if seen.insert(path).inserted {
                    paths.append(path)
                }
            }
        }
        return paths
    }

    /// The file's own row at `path` in the Apple Photos root, with its asset; nil for a path that isn't one.
    func applePhotosOriginal(atPath path: String) throws -> ApplePhotosOriginalRow? {
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let statement = try database.cached("""
        SELECT p.id, a.local_id, a.resource, a.content_version, p.camera FROM photos p JOIN folders f ON f.id = p.folder
          JOIN photo_assets a ON a.photo = p.id WHERE f.path = ? AND p.name = ? AND p.version = ''
        """)
        try statement.bind(String(path[..<slash]), at: 1)
        try statement.bind(String(path[path.index(after: slash)...]), at: 2)
        return try statement.first { row in
            ApplePhotosOriginalRow(
                photo: row.int64(at: 0), local: row.string(at: 1) ?? "",
                resource: ApplePhotosRow.Resource(rawValue: row.int(at: 2)) ?? .original,
                contentVersion: Date(timeIntervalSince1970: row.double(at: 3)),
                hasCamera: row.optionalInt64(at: 4) != nil,
            )
        } ?? nil
    }
}

/// The network as downloads from iCloud meet it (LIB-60): whether it's up, and whether macOS marks it as expensive (a
/// phone's hotspot) or constrained (Low Data Mode), when nothing is downloaded ahead of Develop (decision 4).
public protocol ApplePhotosNetwork: Sendable {
    var isReachable: Bool { get }
    var isExpensive: Bool { get }
}

/// The Mac's network, as `NWPathMonitor` follows it.
public final class SystemNetwork: ApplePhotosNetwork {
    public static let shared = SystemNetwork()

    private let monitor = NWPathMonitor()
    private let path = Mutex((reachable: true, expensive: false))

    private init() {
        monitor.pathUpdateHandler = { [weak self] update in
            self?.path.withLock { $0 = (update.status == .satisfied, update.isExpensive || update.isConstrained) }
        }
        monitor.start(queue: DispatchQueue(label: "app.redlamp.network", qos: .utility))
    }

    public var isReachable: Bool {
        path.withLock(\.reachable)
    }

    public var isExpensive: Bool {
        path.withLock(\.expensive)
    }
}
