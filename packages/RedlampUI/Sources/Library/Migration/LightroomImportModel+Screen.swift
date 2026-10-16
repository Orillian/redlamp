import AppKit
import RedlampDocument
import RedlampLibrary

/// A moment as the window's log dates it and as its rate meters measure it, on a clock that only goes forward.
struct LightroomMoment: Sendable {
    var date: Date
    var uptime: TimeInterval

    static var now: LightroomMoment {
        LightroomMoment(date: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    }

    func adding(_ seconds: TimeInterval) -> LightroomMoment {
        LightroomMoment(date: date.addingTimeInterval(seconds), uptime: uptime + seconds)
    }

    func since(_ other: LightroomMoment) -> TimeInterval {
        max(uptime - other.uptime, 0)
    }
}

/// The disk a root folder is on, as the window names it.
struct LightroomRootDisk: Sendable, Hashable {
    var name: String
    var isLocal: Bool
    var isInternal: Bool
    /// Whether it spins (true) or is solid state (false), as its device says (`VolumeInfo.isRotational`), which names
    /// its kind and puts up the spinning disk's notice; nil when the device doesn't say.
    var spins: Bool?

    var screenDisk: LightroomImportScreen.Disk {
        let kind: LightroomImportScreen.Disk.Kind = if !isLocal {
            .network
        } else if isInternal {
            .internal
        } else {
            switch spins {
            case true?: .spinning
            case false?: .externalSSD
            case nil: .external
            }
        }
        return LightroomImportScreen.Disk(name, kind)
    }

    /// The disk the folder at `path` is on, as the file system says; nil when it can't be asked. It can wait on a
    /// disk that sleeps: never call it on the main thread.
    static func of(_ path: String) -> LightroomRootDisk? {
        guard let volume = try? LocalFileSystem().volume(of: URL(fileURLWithPath: path, isDirectory: true))
        else { return nil }
        let name = volume.name ?? URL(fileURLWithPath: path).pathComponents.dropFirst(2).first ?? path
        return LightroomRootDisk(
            name: name, isLocal: volume.isLocal, isInternal: volume.isInternal, spins: volume.isRotational,
        )
    }
}

/// What the Lightroom import window shows beyond what the model keeps (LIB-52): when each stage started and how fast
/// it goes, each root folder's disk and progress, and the log. `LightroomImportModel` hands it what it knows on every
/// change and about once a second while it works, and the screen is worked out from it.
struct LightroomImportTracking {
    /// What the model knows, as it hands it over.
    struct Facts: Sendable {
        var phase = LightroomImportModel.Phase.choosing
        /// The catalog's name: `Lightroom Catalog`.
        var catalog = ""
        var report: LightroomReport?
        var problem: String?
        var canUndo = false
        var canImport = false
        /// While the folders are added: photos indexed of those the catalog has there, and in each folder, by path.
        var indexed: (done: Int, total: Int)?
        var indexedRoots: [String: Int] = [:]
        /// Why the indexer isn't reading the folders added, when the Mac holds its work back.
        var pausedBy: PauseReason?
        var progress: LightroomImport.Progress?
        var outcome: Outcome?
        /// The photos the import Undo Import takes back changed.
        var undoPhotos = 0
        var libraryOpen = true
    }

    /// How an import ended, once it has.
    struct Outcome: Sendable, Hashable {
        var stopped: Bool
        /// The photos whose sidecars couldn't be written, by path, and why.
        var skipped: [String: String] = [:]
    }

    private(set) var facts = Facts()
    private(set) var log: [LightroomImportScreen.LogEntry] = []
    private(set) var readTime: TimeInterval?
    private var readStarted: LightroomMoment?
    /// The import running, or the last, and when it ended.
    private var started: LightroomMoment?
    private var ended: LightroomMoment?
    /// Counts the imports started, so what's worked out for one isn't given to the next.
    private(set) var run = 0
    /// The root folders added first, as the report had them as adding began.
    private var adding: [LightroomReport.Root] = []
    private var indexStarted: LightroomMoment?
    private var indexTime: TimeInterval?
    private var indexed: LightroomImportScreen.Count?
    private var indexedRoots: [String: Int] = [:]
    private(set) var indexMeter: RateMeter?
    private(set) var writeMeter: RateMeter?
    private var pausedBy: PauseReason?
    /// The pause the log last said, to say when it ends.
    private var loggedPause: PauseReason?
    /// The report the import ran, as its plan was when writing began.
    private var imported: LightroomReport?
    private var written: LightroomImportScreen.Count?
    /// The part being written, from 0, and when it began.
    private var part: (number: Int, began: LightroomMoment)?
    /// Each root folder's photos' places in the order the import takes them, ascending, by the root's ID.
    private var places: [Int64: [Int]] = [:]
    /// The root folders in the order the import reaches them.
    private var order: [Int64] = []
    /// The disks of the root folders, by their paths, once looked up.
    private(set) var disks: [String: LightroomRootDisk] = [:]
    /// The root folders, by path, whose folders went away while the import ran.
    private var gone: [String] = []
    private var failure: LightroomImportScreen.Result.Failure?
    /// Undo Import's batches taken back, of its batches.
    private var undone: (done: Int, total: Int)?
    private var undoPhotos = 0
    private var reportLines: (report: LightroomReport, lines: [String])?

    // What the model runs to follow the import: its ticks while it works, and the disks it has asked about.
    var ticker: Task<Void, Never>?
    var askedDisks = Set<String>()

    private static let partSize = LightroomImport.standardPartSize

    // MARK: - Following

    /// Takes what the model knows now, noting each change of phase once.
    mutating func observe(_ new: Facts, at now: LightroomMoment) {
        let old = facts
        facts = new
        if let report = new.report, reportLines?.report != report {
            reportLines = (report, report.lines())
        }
        switch new.phase {
        case .reading where old.phase != .reading:
            readStarted = now
        case .reported where old.phase == .reading:
            readTime = readStarted.map { now.since($0) }
            if let report = new.report {
                note(
                    "Read “\(new.catalog)”: \(ProgressText.count(report.photos, "photo")) in "
                        + "\(ProgressText.count(report.roots.count, "root folder")), in "
                        + ProgressText.duration(readTime ?? 0),
                    at: now,
                )
            }
        case .choosing where old.phase == .reading:
            if let problem = new.problem {
                note("Couldn't read “\(new.catalog)”: \(problem)", at: now)
            }
        case .adding where old.phase != .adding:
            begin(at: now)
            adding = (new.report ?? old.report)?.roots.filter { $0.state == .notInLibrary && $0.path != nil } ?? []
            indexStarted = now
            indexed = LightroomImportScreen.Count(0, of: new.indexed?.total ?? new.report?.waiting ?? 0)
            indexMeter = RateMeter(start: now.uptime)
            note(
                "Added \(ProgressText.count(adding.count, "folder")) to Folders: "
                    + adding.map { Self.name(of: $0.path ?? $0.lightroomPath) }.joined(separator: ", "),
                at: now,
            )
        case .importing where old.phase != .importing:
            if old.phase == .adding {
                endIndexing(at: now)
            } else {
                begin(at: now)
            }
            imported = new.report
            let total = new.progress?.total ?? 0
            written = LightroomImportScreen.Count(0, of: total)
            writeMeter = RateMeter(start: now.uptime)
            part = (0, now)
            let parts = (total + Self.partSize - 1) / Self.partSize
            note(
                "Writing Lightroom's fields to \(ProgressText.count(total, "photo"))"
                    + (parts > 1 ? ", in \(parts) parts of \(ProgressText.count(Self.partSize))" : ""),
                at: now,
            )
        case .stopping where old.phase == .importing:
            let parts = max(1, ((written?.total ?? 0) + Self.partSize - 1) / Self.partSize)
            note("Stop pressed: the import stops after part \((part?.number ?? 0) + 1) of \(parts)", at: now)
        case .reported where old.phase == .adding:
            let count = indexed ?? LightroomImportScreen.Count(0, of: 0)
            note(
                "Stopped while indexing: \(ProgressText.count(count.done)) of "
                    + "\(ProgressText.count(count.total, "photo")) indexed; nothing was written",
                at: now,
            )
            started = nil
        case .imported where old.phase != .imported:
            end(at: now)
        case .undoing where old.phase != .undoing:
            undoPhotos = new.undoPhotos
            undone = nil
            note("Taking back the import of \(ProgressText.count(undoPhotos, "photo"))", at: now)
        case .undone where old.phase == .undoing:
            if let problem = new.problem {
                note("The import was taken back in part: \(problem)", at: now)
            } else {
                note("Took back the import: \(ProgressText.count(undoPhotos, "photo")) as they were", at: now)
            }
        default:
            break
        }
        if new.phase == .adding, let count = new.indexed {
            pausedBy = new.pausedBy
            indexed = LightroomImportScreen.Count(count.done, of: count.total)
            indexedRoots = new.indexedRoots
            indexMeter?.record(count.done, at: now.uptime, pausedBy: pausedBy)
        }
        if new.phase == .importing || new.phase == .stopping, let progress = new.progress {
            wrote(progress, at: now)
        }
    }

    /// About once a second while the import runs: the count again, with whether the Mac holds the indexer back, so a
    /// pause shows; and the root folders whose folders went away, by path.
    mutating func tick(at now: LightroomMoment, pausedBy: PauseReason?, missing: Set<String>) {
        switch facts.phase {
        case .adding:
            self.pausedBy = pausedBy
            if let indexed {
                indexMeter?.record(indexed.done, at: now.uptime, pausedBy: pausedBy)
            }
            let paused: PauseReason? = if case let .paused(reason) = pace(at: now) {
                reason
            } else {
                nil
            }
            if paused != loggedPause {
                note(paused.map(Self.pausedLine) ?? loggedPause.map(Self.carriedOnLine) ?? "", at: now)
                loggedPause = paused
            }
        case .importing, .stopping:
            if let written {
                writeMeter?.record(written.done, at: now.uptime)
            }
        default:
            return
        }
        for path in stagePaths where missing.contains(path) && !gone.contains(path) {
            gone.append(path)
            note("\(diskName(of: path)) was disconnected", at: now)
        }
    }

    /// The import's root folders went away as it failed, by path.
    mutating func lost(_ paths: [String]) {
        gone += paths.filter { !gone.contains($0) }
    }

    /// Each photo's root folder, by its ID in the report, in the order import `run` takes them.
    mutating func photoRoots(_ roots: [Int64?], run: Int) {
        guard run == self.run else { return }
        places = [:]
        order = []
        for (place, root) in roots.enumerated() {
            guard let root else { continue }
            if places[root] == nil {
                order.append(root)
            }
            places[root, default: []].append(place)
        }
    }

    mutating func found(_ disks: [String: LightroomRootDisk]) {
        self.disks.merge(disks) { _, new in new }
    }

    /// Undo Import's progress: batches taken back, of its batches.
    mutating func undid(_ done: Int, of total: Int) {
        undone = (done, total)
    }

    /// The paths of the root folders the stage under way reads or writes, which a tick looks for.
    var stagePaths: [String] {
        switch facts.phase {
        case .adding: adding.compactMap(\.path)
        case .importing, .stopping: order.compactMap { id in imported?.roots.first { $0.id == id }?.path }
        default: []
        }
    }

    private mutating func begin(at now: LightroomMoment) {
        run += 1
        started = now
        ended = nil
        adding = []
        indexStarted = nil
        indexTime = nil
        indexed = nil
        indexedRoots = [:]
        indexMeter = nil
        writeMeter = nil
        pausedBy = nil
        loggedPause = nil
        imported = nil
        written = nil
        part = nil
        places = [:]
        order = []
        gone = []
        failure = nil
    }

    private mutating func endIndexing(at now: LightroomMoment) {
        indexTime = indexStarted.map { now.since($0) }
        let count = indexed?.done ?? 0
        let time = indexTime ?? 0
        let names = Set(adding.compactMap { $0.path.flatMap { disks[$0]?.name } })
        note(
            "Indexed \(ProgressText.count(count, "photo")) in \(ProgressText.duration(time))"
                + (time > 0 && count > 0 ? ", \(ProgressText.rate(Double(count) / time))" : "")
                + (names.count == 1 ? ", on \(names.first ?? "")" : ""),
            at: now,
        )
        pausedBy = nil
        loggedPause = nil
    }

    private mutating func wrote(_ progress: LightroomImport.Progress, at now: LightroomMoment) {
        written = LightroomImportScreen.Count(progress.done, of: progress.total)
        writeMeter?.record(progress.done, at: now.uptime)
        guard progress.parts > 1 else { return }
        let finished = progress.done >= progress.total ? progress.parts : progress.done / Self.partSize
        while let current = part, current.number < finished {
            let count = min(Self.partSize, progress.total - current.number * Self.partSize)
            note(
                "Part \(current.number + 1) of \(progress.parts) written: \(ProgressText.count(count, "photo")) in "
                    + ProgressText.duration(now.since(current.began))
                    + (current.number == 0 ? "; keyword list and collections defined" : ""),
                at: now,
            )
            part = (current.number + 1, now)
        }
    }

    private mutating func end(at now: LightroomMoment) {
        ended = now
        let total = written?.total ?? 0
        let done = written?.done ?? 0
        let elapsed = ProgressText.spoken(started.map { now.since($0) } ?? 0)
        let parts = max(1, (total + Self.partSize - 1) / Self.partSize)
        if let outcome = facts.outcome {
            if outcome.stopped {
                // Stop lets the part being written end.
                let kept = min((done + Self.partSize - 1) / Self.partSize * Self.partSize, total)
                written = LightroomImportScreen.Count(kept, of: total)
                note(
                    "Stopped after part \(kept / Self.partSize) of \(parts): \(ProgressText.count(kept, "photo")) "
                        + "written, \(ProgressText.count(total - kept)) not changed",
                    at: now,
                )
            } else {
                written = LightroomImportScreen.Count(total, of: total)
                note("Imported \(ProgressText.count(total, "photo")) in \(elapsed)", at: now)
            }
            for unwritten in Self.unwritten(outcome.skipped) {
                note(
                    "\(ProgressText.count(unwritten.count, "sidecar")) couldn't be written: \(unwritten.reason)",
                    at: now,
                )
            }
            return
        }
        // A part that fails is rolled back: the parts before it are kept.
        let kept = done / Self.partSize * Self.partSize
        written = LightroomImportScreen.Count(kept, of: total)
        let reason = facts.problem
            .map { $0.hasPrefix(Self.stoppedPrefix) ? String($0.dropFirst(Self.stoppedPrefix.count)) : $0 }
        if let path = gone.first {
            failure = .disconnected(disk: diskName(of: path))
        } else if !facts.libraryOpen {
            failure = .libraryClosed
        } else {
            failure = .other(reason ?? "something went wrong")
        }
        note(
            "The import stopped in part \(min(kept / Self.partSize + 1, parts)): \(failure?.text ?? ""); "
                +
                (kept > 0 ? "the \(ProgressText.count(kept, "photo")) written before are kept" :
                    "nothing was written"),
            at: now,
        )
    }

    private mutating func note(_ text: String, at now: LightroomMoment) {
        guard !text.isEmpty else { return }
        log.append(LightroomImportScreen.LogEntry(now.date, text))
    }

    /// What the model says when an import fails, before the error's own words.
    private static let stoppedPrefix = "The import stopped: "

    private static func pausedLine(_ reason: PauseReason) -> String {
        switch reason {
        case .lowPower: "Paused: Low Power Mode is on"
        case .heat: "Paused while the Mac cools down"
        }
    }

    private static func carriedOnLine(_ reason: PauseReason) -> String {
        switch reason {
        case .lowPower: "Carried on: Low Power Mode is off"
        case .heat: "Carried on: the Mac has cooled down"
        }
    }

    // MARK: - The screen

    /// The window's content at `now`.
    func screen(at now: LightroomMoment) -> LightroomImportScreen {
        let phase = screenPhase
        var screen = LightroomImportScreen(
            phase: phase, catalog: facts.catalog, readTime: readTime, log: log, reportText: reportLines?.lines ?? [],
            canUndo: facts.canUndo, canImport: facts.canImport,
        )
        if [.reading, .review, .undone].contains(phase) {
            screen.problem = facts.problem
        }
        if let report = facts.report {
            screen.review = LightroomImportScreen.Review(
                report, disks: screenDisks(report), edits: Self.edits(report.edits),
            )
        }
        switch phase {
        case .reading, .review:
            break
        case .adding, .writing, .stopping, .done, .stopped, .failed:
            screen.run = runScreen(phase, at: now)
            if [.done, .stopped, .failed].contains(phase) {
                screen.result = resultScreen(phase)
            }
        case .undoing, .undone:
            let total = max(undoPhotos, 0)
            let done = undone.map { total * $0.done / max($0.total, 1) } ?? 0
            screen.run = started.map { _ in runScreen(phase, at: now) }
            screen.result = LightroomImportScreen.Result(
                written: total, total: total,
                undoing: phase == .undoing ? LightroomImportScreen.Count(done, of: total) : nil,
            )
        }
        return screen
    }

    var screenPhase: LightroomImportScreen.Phase {
        switch facts.phase {
        case .choosing, .reading: .reading
        case .reported: .review
        case .adding: .adding
        case .importing: .writing
        case .stopping: .stopping
        case .imported: facts.outcome.map { $0.stopped ? .stopped : .done } ?? .failed
        case .undoing: .undoing
        case .undone: .undone
        }
    }

    /// The pace of the stage under way.
    private func pace(at now: LightroomMoment) -> Pace {
        switch facts.phase {
        case .adding:
            indexMeter?.pace(total: indexed?.total ?? 0, now: now.uptime, pausedBy: pausedBy) ?? .measuring
        case .importing:
            writeMeter?.pace(total: written?.total ?? 0, now: now.uptime, pausedBy: nil) ?? .measuring
        default:
            .measuring
        }
    }

    private func runScreen(_ phase: LightroomImportScreen.Phase, at now: LightroomMoment) -> LightroomImportScreen.Run {
        let running = [.adding, .writing, .stopping].contains(phase)
        let elapsed = started.map { (ended ?? now).since($0) } ?? 0
        let pace = running ? pace(at: now) : .measuring
        let meter = phase == .adding ? indexMeter : writeMeter
        let reachable = facts.report.map { $0.found + $0.waiting } ?? 0
        return LightroomImportScreen.Run(
            folders: adding.count, indexed: adding.isEmpty ? nil : indexed, indexTime: indexTime,
            written: written ?? LightroomImportScreen.Count(0, of: reachable), partSize: Self.partSize,
            elapsed: elapsed, pace: pace, throughput: running ? meter?.throughput(now: now.uptime) ?? [] : [],
            roots: rootProgress(phase), notices: notices(phase, pace: pace),
        )
    }

    private func rootProgress(_ phase: LightroomImportScreen.Phase) -> [LightroomImportScreen.RootProgress] {
        if phase == .adding {
            return adding.map { root in
                let path = root.path ?? root.lightroomPath
                let done = min(indexedRoots[path] ?? 0, root.photos)
                return LightroomImportScreen.RootProgress(
                    Self.name(of: path), disk: disks[path]?.screenDisk, LightroomImportScreen.Count(
                        done,
                        of: root.photos,
                    ),
                )
            }
        }
        let done = written?.done ?? 0
        return order.compactMap { id in
            guard let places = places[id], let root = imported?.roots.first(where: { $0.id == id }) else { return nil }
            let path = root.path ?? root.lightroomPath
            return LightroomImportScreen.RootProgress(
                Self.name(of: path), disk: disks[path]?.screenDisk,
                LightroomImportScreen.Count(Self.count(places, below: done), of: places.count),
            )
        }
    }

    private func notices(_ phase: LightroomImportScreen.Phase, pace: Pace) -> [LightroomImportScreen.Notice] {
        guard [.adding, .writing, .stopping, .failed].contains(phase) else { return [] }
        var notices: [LightroomImportScreen.Notice] = []
        if case let .paused(reason) = pace {
            notices.append(.paused(reason))
        }
        var named = Set<String>()
        for path in gone {
            let name = diskName(of: path)
            if named.insert(name).inserted {
                notices.append(.disconnected(disk: name))
            }
        }
        guard phase != .failed else { return notices.filter {
            if case .disconnected = $0 {
                true
            } else {
                false
            }
        } }
        var spinning = Set<String>()
        for path in stagePaths {
            if let disk = disks[path], disk.spins == true, spinning.insert(disk.name).inserted {
                notices.append(.spinning(disk: disk.name))
            }
        }
        return notices
    }

    private func resultScreen(_ phase: LightroomImportScreen.Phase) -> LightroomImportScreen.Result {
        let written = written ?? LightroomImportScreen.Count(0, of: 0)
        var fields: LightroomImportScreen.Result.Fields?
        var edits: LightroomImportScreen.Edits?
        if phase == .done, let imported {
            let given = imported.fields
            fields = .init(
                ratings: given.ratings, picksAndRejects: given.picks + given.rejects,
                labels: given.labels + given.customLabels, keywords: given.keywords, collections: given.collections,
            )
            edits = Self.edits(imported.edits)
        }
        return LightroomImportScreen.Result(
            written: written.done, total: written.total, partSize: Self.partSize,
            elapsed: started.map { (ended ?? $0).since($0) }, fields: fields, edits: edits,
            unwritten: Self.unwritten(facts.outcome?.skipped ?? [:]), failure: phase == .failed ? failure : nil,
        )
    }

    /// The disks of `report`'s root folders that were looked up, by the roots' IDs.
    private func screenDisks(_ report: LightroomReport) -> [Int64: LightroomImportScreen.Disk] {
        var found: [Int64: LightroomImportScreen.Disk] = [:]
        for root in report.roots {
            if let path = root.path, let disk = disks[path] {
                found[root.id] = disk.screenDisk
            }
        }
        return found
    }

    private func diskName(of path: String) -> String {
        disks[path]?.name ?? Self.name(of: path)
    }

    // MARK: - Words

    /// Step 9's Edits section, when the report has edits that come across.
    static func edits(_ edits: LightroomReport.Edits) -> LightroomImportScreen.Edits? {
        guard edits.photos > 0 else { return nil }
        return LightroomImportScreen.Edits(
            fully: edits.full, approximated: edits.approximated, leftOut: edits.leftOut,
            reasons: edits.reasons.sorted { $0.photos > $1.photos }.map { .init(short($0.why), $0.photos) },
        )
    }

    /// A reason's words up to its first colon or comma: "not yet checked against Lightroom".
    static func short(_ why: String) -> String {
        let end = why.firstIndex { $0 == ":" || $0 == "," } ?? why.endIndex
        return String(why[..<end])
    }

    /// The sidecars that couldn't be written, by reason, most first.
    static func unwritten(_ skipped: [String: String]) -> [LightroomImportScreen.Result.Unwritten] {
        Dictionary(grouping: skipped.values, by: \.self)
            .map { LightroomImportScreen.Result.Unwritten($0.value.count, reason: $0.key) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason < $1.reason }
    }

    /// "LaCie › Photos 2019": a root folder by the disk or folder it's in, and its own name.
    static func name(of path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        guard let own = components.last else { return path }
        let parent = components.count > 2 ? components[components.count - 2] : nil
        return parent.map { $0 == "Volumes" ? own : "\($0) › \(own)" } ?? own
    }

    /// How many of `places`, ascending, are below `limit`.
    static func count(_ places: [Int], below limit: Int) -> Int {
        var low = 0, high = places.count
        while low < high {
            let middle = (low + high) / 2
            if places[middle] < limit {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

// MARK: - The model

extension LightroomImportModel {
    /// What the window shows, as the import goes (LIB-52).
    var screen: LightroomImportScreen {
        tracking.screen(at: .now)
    }

    /// Hands the tracking what the model knows; called on every change.
    func track() {
        let starting = phase == .importing && tracking.facts.phase != .importing
        if phase == .imported, outcome == nil, tracking.facts.phase != .imported {
            tracking.lost(tracking.stagePaths.filter { !FileManager.default.fileExists(atPath: $0) })
        }
        tracking.observe(facts, at: .now)
        if starting {
            findPhotoRoots()
        }
        lookUpDisks()
        if isBusy, tracking.ticker == nil {
            tracking.ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    await tick()
                }
            }
        } else if !isBusy, let ticker = tracking.ticker {
            ticker.cancel()
            tracking.ticker = nil
        }
    }

    private var facts: LightroomImportTracking.Facts {
        var facts = LightroomImportTracking.Facts()
        facts.phase = phase
        facts.catalog = catalogURL?.deletingPathExtension().lastPathComponent ?? ""
        facts.report = report
        facts.problem = problem
        facts.canUndo = canUndo
        facts.canImport = canImport
        facts.indexed = indexed
        facts.indexedRoots = indexedRoots
        facts.pausedBy = indexerPause
        facts.progress = progress
        facts.outcome = outcome.map { LightroomImportTracking.Outcome(stopped: $0.record.stopped, skipped: $0.skipped) }
        facts.undoPhotos = lastImport?.photos ?? 0
        facts.libraryOpen = core != nil
        return facts
    }

    /// Why the indexer isn't reading the folders added: the Mac holds its background work back, in Low Power Mode or
    /// while it's hot, and none of it runs.
    private var indexerPause: PauseReason? {
        guard phase == .adding, !WorkScheduler.isRelaxed(), let load = core?.indexer.scheduler.load(),
              load.waiting[.background, default: 0] > 0, load.running[.background, default: 0] == 0
        else { return nil }
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? .lowPower : .heat
    }

    private func tick() async {
        let paths = tracking.stagePaths
        let missing = await Task.detached(priority: .utility) {
            Set(paths.filter { !FileManager.default.fileExists(atPath: $0) })
        }.value
        guard isBusy else { return }
        tracking.tick(at: .now, pausedBy: indexerPause, missing: missing)
        onChange?()
    }

    /// Each photo's root folder in the order the import takes them, worked out off the main thread as it starts.
    private func findPhotoRoots() {
        guard let plan, let index = core?.index else { return }
        let run = tracking.run
        Task { [weak self] in
            let roots = await Task.detached(priority: .utility) { try? await plan.photoRoots(in: index) }.value
            guard let self, let roots else { return }
            tracking.photoRoots(roots, run: run)
            onChange?()
        }
    }

    /// Looks up the disks of the report's root folders not looked up yet, off the main thread.
    private func lookUpDisks() {
        let paths = Set((report?.roots ?? []).compactMap(\.path)).subtracting(tracking.askedDisks)
        guard !paths.isEmpty else { return }
        tracking.askedDisks.formUnion(paths)
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                paths
                    .reduce(into: [String: LightroomRootDisk]()) { found, path in
                        found[path] = LightroomRootDisk.of(path)
                    }
            }.value
            guard let self else { return }
            tracking.found(found)
            onChange?()
        }
    }

    /// Undo Import's progress, as it takes the import's batches back.
    func undoProgressed(_ progress: LightroomImport.Progress) {
        guard phase == .undoing else { return }
        tracking.undid(progress.done, of: progress.total)
        onChange?()
    }

    /// The photos whose sidecars couldn't be written for `reason`, as the last import left them.
    func unwrittenPhotos(_ reason: String) -> [URL] {
        (outcome?.skipped ?? [:]).filter { $0.value == reason }.keys.sorted().map { URL(fileURLWithPath: $0) }
    }
}
