import Foundation
import RedlampLibrary

/// Everything File › Import from Lightroom Classic…'s window shows (LIB-52), as a plain value: the model fills it as
/// the import goes, and the harness fills it with made-up values. It holds counts and times; the wording is worked
/// out here, so the views only lay it out.
@_spi(Harness) public struct LightroomImportScreen: Sendable, Hashable {
    public enum Phase: String, Sendable, Hashable, CaseIterable {
        case reading, review
        /// The root folders the library lacks are added and indexed.
        case adding
        case writing, stopping
        case done, stopped, failed
        case undoing, undone
    }

    public var phase: Phase
    /// The catalog's name, as the report gives it.
    public var catalog: String
    /// How long reading the catalog took, once it's read.
    public var readTime: TimeInterval?
    /// What the catalog brings, once it's read; kept while it imports.
    public var review: Review?
    /// The import, once it has started; kept once it has ended.
    public var run: Run?
    /// How it ended, or is being taken back.
    public var result: Result?
    public var log: [LogEntry] = []
    /// The report's lines, as `redlamp library lightroom` prints them.
    public var reportText: [String] = []
    /// Why the catalog couldn't be read, or the report worked out, in words.
    public var problem: String?
    /// There's an import not taken back, which Undo Import takes back from Review too.
    public var canUndo = false
    /// Importing would change something: false when nothing the catalog brings differs from the library.
    public var canImport = true

    public init(
        phase: Phase, catalog: String, readTime: TimeInterval? = nil, review: Review? = nil, run: Run? = nil,
        result: Result? = nil, log: [LogEntry] = [], reportText: [String] = [], problem: String? = nil,
        canUndo: Bool = false, canImport: Bool = true,
    ) {
        self.phase = phase
        self.catalog = catalog
        self.readTime = readTime
        self.review = review
        self.run = run
        self.result = result
        self.log = log
        self.reportText = reportText
        self.problem = problem
        self.canUndo = canUndo
        self.canImport = canImport
    }

    /// `done` of `total`.
    public struct Count: Sendable, Hashable {
        public var done: Int
        public var total: Int

        public init(_ done: Int, of total: Int) {
            self.done = done
            self.total = total
        }

        public var fraction: Double {
            total > 0 ? min(max(Double(done) / Double(total), 0), 1) : 0
        }
    }

    /// The disk a root folder is on.
    public struct Disk: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable, CaseIterable {
            /// `external` is an external disk that hasn't said whether it spins.
            case `internal`, external, externalSSD, spinning, network

            public var name: String {
                switch self {
                case .internal: "internal"
                case .external: "external"
                case .externalSSD: "external SSD"
                case .spinning: "external, spinning disk"
                case .network: "network disk"
                }
            }
        }

        public var name: String
        public var kind: Kind

        public init(_ name: String, _ kind: Kind) {
            self.name = name
            self.kind = kind
        }

        /// "LaCie: external, spinning disk".
        public var described: String {
            "\(name): \(kind.name)"
        }
    }

    /// Something the window points out: why work is slow or paused, or what couldn't be done.
    public enum Notice: Sendable, Hashable {
        case paused(PauseReason)
        case spinning(disk: String)
        case disconnected(disk: String)
        case unwritten(count: Int, reason: String)

        public var text: String {
            switch self {
            case .paused(.lowPower):
                "Paused: Low Power Mode is on. Plug in or turn it off in System Settings › Battery, and the import "
                    + "carries on."
            case .paused(.heat): "Paused while the Mac cools down; the import carries on by itself."
            case let .spinning(disk):
                "Photos on \(disk), a spinning disk: Redlamp reads and writes one file at a time, in folder order, "
                    + "which is quickest for it."
            case let .disconnected(disk): "\(disk) was disconnected: connect it and Import Again brings the rest."
            case let .unwritten(count, reason):
                "\(ProgressText.count(count, "sidecar")) couldn't be written: \(reason)."
            }
        }

        /// Whether it asks for something to be done, rather than explaining.
        public var isCaution: Bool {
            switch self {
            case .paused, .disconnected, .unwritten: true
            case .spinning: false
            }
        }
    }

    /// A line of the log.
    public struct LogEntry: Sendable, Hashable {
        public var time: Date
        public var text: String

        public init(_ time: Date, _ text: String) {
            self.time = time
            self.text = text
        }

        private static let clock: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        /// "10:41:12".
        public var clockTime: String {
            Self.clock.string(from: time)
        }
    }

    // MARK: - The screen's parts

    /// Which of the window's screens the phase shows.
    public enum Screen: Sendable, Hashable {
        case reading, review, importing, result
    }

    public var screen: Screen {
        switch phase {
        case .reading: .reading
        case .review: .review
        case .adding, .writing, .stopping: .importing
        case .done, .stopped, .failed, .undoing, .undone: .result
        }
    }

    /// A button of the window's bottom bar, which stays AppKit's so the regression suite clicks it.
    public struct Button: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable {
            case importPhotos, stop, undo, importAgain, done
        }

        public var kind: Kind
        public var title: String
        public var isEnabled = true
        /// Return presses it.
        public var isDefault = false
    }

    /// What the bottom bar says beside its buttons, and its buttons, left to right.
    public var barNote: String? {
        if let problem, phase == .reading || phase == .review {
            return problem
        }
        return switch phase {
        case .reading: "The catalog is read from a copy and never changed."
        case .review: canImport
            ? "Lightroom's value replaces the library's where it has one. Undo Import takes it all back."
            : "Nothing in the catalog would change the library."
        case .adding, .writing, .stopping: "You can close this window: the import carries on."
        case .done, .stopped, .failed, .undone: nil
        case .undoing: "Taking the import back…"
        }
    }

    public var buttons: [Button] {
        let photos = review?.reachable ?? 0
        let importTitle = "Import \(ProgressText.count(photos, "Photo"))"
        let undo = canUndo ? [Button(kind: .undo, title: "Undo Import")] : []
        switch phase {
        case .reading:
            return undo + [Button(kind: .importPhotos, title: "Import", isEnabled: false, isDefault: true)]
        case .review:
            return undo + [Button(
                kind: .importPhotos, title: importTitle, isEnabled: canImport && photos > 0, isDefault: true,
            )]
        case .adding, .writing:
            return [Button(kind: .stop, title: "Stop")]
        case .stopping:
            return [Button(kind: .stop, title: "Stop", isEnabled: false)]
        case .done:
            return [
                Button(kind: .undo, title: "Undo Import", isEnabled: canUndo),
                Button(kind: .done, title: "Done", isDefault: true),
            ]
        case .stopped, .failed:
            return [
                Button(kind: .undo, title: "Undo Import", isEnabled: canUndo),
                Button(kind: .importAgain, title: "Import Again", isEnabled: canImport, isDefault: true),
            ]
        case .undoing:
            return [Button(kind: .undo, title: "Undo Import", isEnabled: false)]
        case .undone:
            return undo + [Button(kind: .importPhotos, title: "Import", isEnabled: canImport, isDefault: true)]
        }
    }

    /// The log as Copy puts it on the pasteboard.
    public var logText: String {
        log.map { "\($0.clockTime) \($0.text)" }.joined(separator: "\n")
    }
}

// MARK: - Review

@_spi(Harness) public extension LightroomImportScreen {
    /// What the catalog brings, before anything is written: the report as a picture.
    struct Review: Sendable, Hashable {
        /// The catalog's photos, virtual copies aside.
        public var photos: Int
        /// The photos the import reaches: those the library has and those in folders it adds first.
        public var reachable: Int
        /// Of the photos the library has, those whose fields change.
        public var changing: Int
        public var foldersToAdd: Int
        public var photosToAdd: Int
        public var roots: [Root]
        public var fields: [Field]
        /// The photos the field bars are counted over: those the library has now.
        public var fieldsCounted: Int
        /// "4,812 keywords with their hierarchy and synonyms; 86 collections in 12 sets; 9 of 11 smart collections".
        public var lists: String?
        /// Step 9's Edits section, once the report has it.
        public var edits: Edits?
        public var left: [Left]

        /// Photos the import doesn't reach: in folders not found, not readable, on disks not connected, or not found.
        public var unreachable: Int {
            max(photos - reachable, 0)
        }

        /// The four headline counts, figure first.
        public var headline: [(figure: String, label: String)] {
            [
                (ProgressText.count(reachable), "photos found, of \(ProgressText.count(photos))"),
                (ProgressText.count(changing), "change in the library"),
                foldersToAdd == 0
                    ? ("None", "folders to add first")
                    : (
                        ProgressText.count(foldersToAdd, "folder"),
                        "added first, \(ProgressText.count(photosToAdd, "photo"))",
                    ),
                (ProgressText.count(unreachable), "not found where Lightroom had them"),
            ]
        }

        /// "LaCie: external, spinning disk · Archive 2: external SSD", each disk once, in the roots' order.
        public var disks: String? {
            var seen: [Disk] = []
            for disk in roots.compactMap(\.disk) where !seen.contains(disk) {
                seen.append(disk)
            }
            return seen.isEmpty ? nil : seen.map(\.described).joined(separator: " · ")
        }

        /// Under the field bars when some photos are in folders added first, which are counted once indexed.
        public var fieldsNote: String? {
            photosToAdd > 0
                ? "Counted over the \(ProgressText.count(fieldsCounted, "photo")) the library has; the "
                + "\(ProgressText.count(photosToAdd)) in folders added first are read once they're indexed."
                : nil
        }
    }

    /// A root folder of the catalog, where it is and what becomes of it.
    struct Root: Sendable, Hashable, Identifiable {
        public enum Action: String, Sendable, Hashable {
            case locate, allowAccess

            public var title: String {
                switch self {
                case .locate: "Locate…"
                case .allowAccess: "Allow Access…"
                }
            }
        }

        public var id: Int64
        public var lightroomPath: String
        public var path: String?
        public var moved: Bool
        public var state: LightroomReport.Root.State
        public var photos: Int
        public var found: Int
        public var disk: Disk?

        public init(_ root: LightroomReport.Root, disk: Disk? = nil) {
            id = root.id
            lightroomPath = root.lightroomPath
            path = root.path
            moved = root.moved
            state = root.state
            photos = root.photos
            found = root.found
            self.disk = disk
        }

        /// Where the catalog has it, and where it is now when it moved.
        public var place: String {
            if moved, let path {
                return "\(lightroomPath) → \(path)"
            }
            return lightroomPath
        }

        public var stateText: String {
            let found = "\(ProgressText.count(found)) of \(ProgressText.count(photos)) found"
            let isMoved = moved && path != nil
            switch state {
            case .inLibrary: return isMoved ? "Moved: in the library, \(found)" : "In the library: \(found)"
            case .notInLibrary:
                return isMoved
                    ? "Moved: added first, \(ProgressText.count(photos, "photo"))"
                    : "Added first: \(ProgressText.count(photos, "photo"))"
            case .missing: return "Not where Lightroom had it"
            case .needsAccess: return "Redlamp can't read it until you allow access"
            case .offline: return "On a disk that isn't connected"
            }
        }

        public var action: Action? {
            switch state {
            case .missing, .offline: .locate
            case .needsAccess: .allowAccess
            case .inLibrary, .notInLibrary: nil
            }
        }
    }

    /// A field Lightroom gives photos, and how many of those replace another value the library shows.
    struct Field: Sendable, Hashable {
        public var name: String
        public var count: Int
        public var replacing: Int

        public init(_ name: String, _ count: Int, replacing: Int = 0) {
            self.name = name
            self.count = count
            self.replacing = replacing
        }

        /// "31,204 · 2,100 replace".
        public var figures: String {
            ProgressText.count(count) + (replacing > 0 ? " · \(ProgressText.count(replacing)) replace" : "")
        }

        public var accessibilityValue: String {
            ProgressText.count(count, "photo")
                + (replacing > 0 ? ", \(ProgressText.count(replacing)) replacing another value" : "")
        }
    }

    /// Step 9's Edits section: how the photos' Lightroom edits convert.
    struct Edits: Sendable, Hashable {
        public struct Reason: Sendable, Hashable {
            public var name: String
            public var count: Int

            public init(_ name: String, _ count: Int) {
                self.name = name
                self.count = count
            }
        }

        public var fully: Int
        public var approximated: Int
        public var leftOut: Int
        /// The settings left out, most photos first.
        public var reasons: [Reason]

        public init(fully: Int, approximated: Int, leftOut: Int, reasons: [Reason] = []) {
            self.fully = fully
            self.approximated = approximated
            self.leftOut = leftOut
            self.reasons = reasons
        }

        public var total: Int {
            fully + approximated + leftOut
        }

        /// "22,100 fully · 9,800 approximated · 3,300 with settings left out (masks 2,900, Lens Blur 140, …)".
        public var summary: String {
            var parts: [String] = []
            if fully > 0 {
                parts.append("\(ProgressText.count(fully)) fully")
            }
            if approximated > 0 {
                parts.append("\(ProgressText.count(approximated)) approximated")
            }
            if leftOut > 0 {
                let shown = reasons.prefix(2).map { "\($0.name) \(ProgressText.count($0.count))" }
                let list = shown.isEmpty ? "" : " (\(shown.joined(separator: ", "))\(reasons.count > 2 ? ", …" : ""))"
                parts.append("\(ProgressText.count(leftOut)) with settings left out\(list)")
            }
            return parts.isEmpty ? "No edits to bring" : parts.joined(separator: " · ")
        }
    }

    /// Something the catalog holds that stays behind.
    struct Left: Sendable, Hashable {
        public var what: String
        public var count: Int
        public var why: String

        public init(_ what: String, _ count: Int, why: String) {
            self.what = what
            self.count = count
            self.why = why
        }

        /// "1,204 virtual copies".
        public var line: String {
            "\(ProgressText.count(count)) \(what)"
        }
    }
}

@_spi(Harness) public extension LightroomImportScreen.Review {
    /// The review of `report`, the disks the window found its roots on, and step 9's edits, when there are any.
    init(
        _ report: LightroomReport, disks: [Int64: LightroomImportScreen.Disk] = [:],
        edits: LightroomImportScreen.Edits? = nil,
    ) {
        typealias Screen = LightroomImportScreen
        photos = report.photos
        reachable = report.found + report.waiting
        changing = report.changing
        let adding = report.roots.filter { $0.state == .notInLibrary }
        foldersToAdd = adding.count
        photosToAdd = report.waiting
        roots = report.roots.map { Screen.Root($0, disk: disks[$0.id]) }
        let fields = report.fields, differing = report.differing
        self.fields = [
            Screen.Field("Ratings", fields.ratings, replacing: differing.ratings),
            Screen.Field(
                "Picks, rejects", fields.picks + fields.rejects, replacing: differing.picks + differing.rejects,
            ),
            Screen.Field("Colour labels", fields.labels, replacing: differing.labels),
            Screen.Field("Custom labels", fields.customLabels, replacing: differing.customLabels),
            Screen.Field("Marks", fields.marks, replacing: differing.marks),
            Screen.Field("Titles", fields.titles, replacing: differing.titles),
            Screen.Field("Captions", fields.captions, replacing: differing.captions),
            Screen.Field("Creators", fields.creators, replacing: differing.creators),
            Screen.Field("Copyrights", fields.copyrights, replacing: differing.copyrights),
            Screen.Field("Locations", fields.locations, replacing: differing.locations),
            Screen.Field("Keywords", fields.keywords),
            Screen.Field("Collections", fields.collections),
        ].filter { $0.count > 0 }
        fieldsCounted = report.found
        var lists: [String] = []
        if report.keywords > 0 {
            lists.append("\(ProgressText.count(report.keywords, "keyword")) with their hierarchy and synonyms")
        }
        if report.collections > 0 {
            lists.append(ProgressText.count(report.collections, "collection")
                + (report.sets > 0 ? " in \(ProgressText.count(report.sets, "set"))" : ""))
        }
        if !report.smart.isEmpty {
            lists.append("\(ProgressText.count(report.smartMapped.count)) of "
                + "\(ProgressText.count(report.smart.count, "smart collection"))")
        }
        self.lists = lists.isEmpty ? nil : lists.joined(separator: "; ")
        self.edits = edits
        var left = report.left.map { Screen.Left($0.what, $0.count, why: $0.why) }
        if !report.smartLeft.isEmpty {
            left.append(Screen.Left(
                report.smartLeft.count == 1 ? "smart collection" : "smart collections", report.smartLeft.count,
                why: "their rules ask for what Redlamp doesn't have",
            ))
        }
        self.left = left
    }
}

// MARK: - Importing

@_spi(Harness) public extension LightroomImportScreen {
    /// The import while it runs, and as it was when it ended.
    struct Run: Sendable, Hashable {
        /// Root folders added to the library first; with none, there's no stage for them.
        public var folders: Int
        /// Photos indexed in those folders, of the catalog's photos there.
        public var indexed: Count?
        /// How long indexing them took, once it's done.
        public var indexTime: TimeInterval?
        /// Photos written, of the import's.
        public var written: Count
        public var partSize: Int
        /// Since the import started.
        public var elapsed: TimeInterval
        /// The stage under way's.
        public var pace: Pace
        /// Photos a second over the last ten minutes, oldest first.
        public var throughput: [ThroughputBin]
        public var roots: [RootProgress]
        public var notices: [Notice]

        public init(
            folders: Int = 0, indexed: Count? = nil, indexTime: TimeInterval? = nil, written: Count,
            partSize: Int = LightroomImport.standardPartSize, elapsed: TimeInterval = 0, pace: Pace = .measuring,
            throughput: [ThroughputBin] = [], roots: [RootProgress] = [], notices: [Notice] = [],
        ) {
            self.folders = folders
            self.indexed = indexed
            self.indexTime = indexTime
            self.written = written
            self.partSize = max(partSize, 1)
            self.elapsed = elapsed
            self.pace = pace
            self.throughput = throughput
            self.roots = roots
            self.notices = notices
        }

        public var parts: Int {
            max(1, (written.total + partSize - 1) / partSize)
        }

        /// The part being written, from 1.
        public var part: Int {
            min(parts, written.done / partSize + 1)
        }

        /// The part being written's own count.
        public var partCount: Count {
            let first = (part - 1) * partSize
            return Count(written.done - first, of: min(partSize, written.total - first))
        }

        /// Whole parts written.
        public var partsWritten: Int {
            written.done >= written.total ? parts : written.done / partSize
        }
    }

    /// A root folder's progress through the stage under way.
    struct RootProgress: Sendable, Hashable, Identifiable {
        public enum State: Sendable, Hashable {
            case done, now, waiting
        }

        /// "LaCie › Photos 2019".
        public var name: String
        public var disk: Disk?
        public var count: Count

        public init(_ name: String, disk: Disk? = nil, _ count: Count) {
            self.name = name
            self.disk = disk
            self.count = count
        }

        public var id: String {
            name
        }

        public var state: State {
            count.done >= count.total ? .done : count.done > 0 ? .now : .waiting
        }

        /// "9,812", "8,240 of 12,300", "26,000 waiting"; a done folder's tick is drawn beside it.
        public var label: String {
            switch state {
            case .done: ProgressText.count(count.total)
            case .now: "\(ProgressText.count(count.done)) of \(ProgressText.count(count.total))"
            case .waiting: "\(ProgressText.count(count.total)) waiting"
            }
        }

        public var accessibilityValue: String {
            switch state {
            case .done: "\(ProgressText.count(count.total, "photo")), done"
            case .now: "\(ProgressText.count(count.done)) of \(ProgressText.count(count.total, "photo"))"
            case .waiting: "\(ProgressText.count(count.total, "photo")), waiting"
            }
        }
    }

    typealias Stage = ProgressStage

    /// One of the done, now and next columns: what it is, and where.
    struct Line: Sendable, Hashable {
        public var title: String
        public var detail: String?
    }

    /// The stages left to right: reading the catalog, adding its folders when there are any, writing, and done.
    var stages: [Stage] {
        let unread = phase == .reading && problem != nil
        let read = Stage(
            id: "read", title: "Read the catalog",
            detail: unread ? "Couldn't read it" : readTime.map(ProgressText.duration) ?? "Reading…",
            state: unread ? .stopped : phase == .reading ? .now : .done,
        )
        guard let run else {
            return [
                read,
                Stage(
                    id: "write",
                    title: "Write",
                    detail: review.map { ProgressText.count($0.reachable, "photo") } ?? "",
                    state: .next,
                ),
                Stage(id: "done", title: "Done", detail: "", state: .next),
            ]
        }
        var stages = [read]
        if run.folders > 0 {
            let indexed = run.indexed ?? Count(0, of: review?.photosToAdd ?? 0)
            let detail = if phase == .adding {
                "\(ProgressText.count(indexed.done)) of \(ProgressText.count(indexed.total)) photos indexed"
            } else {
                "\(ProgressText.count(indexed.total)) photos indexed"
                    + (run.indexTime.map { " in \(ProgressText.duration($0))" } ?? "")
            }
            stages.append(Stage(
                id: "add", title: "Add \(ProgressText.count(run.folders, "folder"))", detail: detail,
                state: phase == .adding ? .now : phase == .failed && run.written.done == 0 ? .stopped : .done,
            ))
        }
        let written = run.written
        let writeState: Stage.State = switch phase {
        case .reading, .review, .adding: .next
        case .writing, .stopping: .now
        case .done, .undoing, .undone: .done
        case .stopped: .stopped
        case .failed: run.folders > 0 && written.done == 0 ? .next : .stopped
        }
        let writeDetail = writeState == .done
            ? ProgressText.count(written.total, "photo")
            : "\(ProgressText.count(written.done)) of \(ProgressText.count(written.total, "photo"))"
        stages.append(Stage(id: "write", title: "Write", detail: writeDetail, state: writeState))
        let finished = [.done, .undoing, .undone].contains(phase)
        var doneDetail = ""
        if finished {
            doneDetail = result?.elapsed.map { "in \(ProgressText.spoken($0))" } ?? ""
        } else if phase == .writing, case let .steady(_, left) = run.pace {
            doneDetail = ProgressText.timeLeft(left)
        }
        stages.append(Stage(id: "done", title: "Done", detail: doneDetail, state: finished ? .done : .next))
        return stages
    }

    /// The stage under way's title over its progress.
    var progressTitle: String {
        switch phase {
        case .adding: "Indexing the new folders"
        case .stopping: "Stopping after this part"
        default: "Writing Lightroom's fields"
        }
    }

    /// The stage under way's count, and what it counts: "18,240" "of 48,212 photos · part 2 of 5".
    var progressFigure: (figure: String, label: String)? {
        guard let run else { return nil }
        switch phase {
        case .adding:
            let indexed = run.indexed ?? Count(0, of: 0)
            return (ProgressText.count(indexed.done), "of \(ProgressText.count(indexed.total)) photos indexed")
        case .stopping:
            let part = run.partCount
            return (
                ProgressText.count(part.done),
                "of \(ProgressText.count(part.total)) photos in part \(run.part) of \(run.parts)",
            )
        default:
            return (
                ProgressText.count(run.written.done),
                "of \(ProgressText.count(run.written.total)) photos · part \(run.part) of \(run.parts)",
            )
        }
    }

    /// The share of the stage under way that's done.
    var progressFraction: Double {
        guard let run else { return 0 }
        return phase == .adding ? (run.indexed?.fraction ?? 0) : run.written.fraction
    }

    /// "38%", rounded down so it reads 100% only when it's all done.
    var progressPercent: String {
        "\(Int((progressFraction * 100).rounded(.down)))%"
    }

    /// The bar's parts: the import's parts while it writes, one while it indexes.
    var progressParts: Int {
        phase == .adding ? 1 : run?.parts ?? 1
    }

    /// The rate and time left, or what stands in their place, then the time so far.
    var paceLine: [String] {
        guard let run else { return [] }
        let pace = phase == .stopping ? [] : run.pace.parts
        return pace + ["\(ProgressText.duration(run.elapsed)) so far"]
    }

    /// What VoiceOver reads for the bar: "18,240 of 48,212 photos, about 12 minutes left".
    var progressAccessibilityValue: String {
        guard let run else { return "" }
        let count = phase == .adding ? run.indexed ?? Count(0, of: 0) : run.written
        var value = "\(ProgressText.count(count.done)) of \(ProgressText.count(count.total, "photo"))"
        if phase == .stopping {
            value += ", stopping after part \(run.part) of \(run.parts)"
            return value
        }
        switch run.pace {
        case .measuring: break
        case let .steady(_, left): value += ", \(ProgressText.timeLeft(left)) left"
        case .idle: value += ", nothing done in the last minute"
        case let .paused(reason): value += ", paused: \(reason.short)"
        }
        return value
    }

    /// The chart's caption: "Last 10 minutes · shaded: paused, Low Power Mode".
    var throughputCaption: String {
        let reasons = Set(run?.throughput.compactMap(\.paused) ?? [])
        guard !reasons.isEmpty else { return "Last 10 minutes" }
        let names = PauseReason.allCases.filter(reasons.contains).map { reason in
            switch reason {
            case .lowPower: "Low Power Mode"
            case .heat: "the Mac cooling down"
            }
        }
        return "Last 10 minutes · shaded: paused, \(names.joined(separator: ", "))"
    }

    /// The chart for VoiceOver: the rate now, and how much of the last ten minutes was paused.
    var throughputAccessibilityValue: String {
        guard let run else { return "" }
        let latest = run.throughput.last { $0.perSecond != nil }?.perSecond ?? 0
        let paused = run.throughput.filter { $0.paused != nil }.count
        var value = "\(ProgressText.rate(latest)) now"
        if paused > 0, !run.throughput.isEmpty {
            let seconds = RateMeter.history * Double(paused) / Double(run.throughput.count)
            value += "; paused for \(ProgressText.spoken(seconds)) of the last 10 minutes"
        }
        return value
    }

    /// What's finished, what's under way and what's left.
    var doneNowNext: (done: Line, now: Line, next: Line)? {
        guard let run else { return nil }
        let catalogRead = Line(
            title: "Catalog read: \(ProgressText.count(review?.photos ?? 0, "photo"))",
            detail: readTime.map { "In \(ProgressText.duration($0))" },
        )
        let current = run.roots.first { $0.state == .now }.map { "In \($0.name)" }
        let waiting = run.roots.filter { $0.state == .waiting }.count
        if phase == .adding {
            let indexed = run.indexed ?? Count(0, of: 0)
            return (
                catalogRead,
                Line(
                    title: "Indexing: \(ProgressText.count(indexed.done)) of \(ProgressText.count(indexed.total))",
                    detail: current,
                ),
                Line(
                    title: "Writing \(ProgressText.count(run.written.total, "photo"))",
                    detail: "In \(ProgressText.count(run.parts, "part")) of \(ProgressText.count(run.partSize))",
                ),
            )
        }
        let done: Line = if run.partsWritten > 0 {
            Line(
                title: run.partsWritten == 1
                    ? "Part 1: \(ProgressText.count(min(run.partSize, run.written.total), "photo"))"
                    : "Parts 1 to \(run.partsWritten): \(ProgressText.count(run.partsWritten * run.partSize, "photo"))",
                detail: "Keyword list and collections defined",
            )
        } else if run.folders > 0 {
            Line(
                title: "\(ProgressText.count(run.folders, "folder")) added",
                detail: (run.indexed?.total).map { "\(ProgressText.count($0, "photo")) indexed" },
            )
        } else {
            catalogRead
        }
        let part = run.partCount
        let now = Line(
            title: "Part \(run.part): \(ProgressText.count(part.done)) of \(ProgressText.count(part.total))",
            detail: current,
        )
        let next: Line
        if phase == .stopping || run.part == run.parts {
            next = Line(title: "The result", detail: "What came across, with Undo Import")
        } else {
            let left = run.written.total - run.part * run.partSize
            next = Line(
                title: run.part + 1 == run.parts
                    ? "Part \(run.parts): \(ProgressText.count(left, "photo"))"
                    : "Parts \(run.part + 1) to \(run.parts): \(ProgressText.count(left, "photo"))",
                detail: waiting > 0 ? "In \(ProgressText.count(waiting, "folder"))" : nil,
            )
        }
        return (done, now, next)
    }
}

// MARK: - Result

@_spi(Harness) public extension LightroomImportScreen {
    /// How the import ended, or how far taking it back has got.
    struct Result: Sendable, Hashable {
        /// Why an import failed.
        public enum Failure: Sendable, Hashable {
            case disconnected(disk: String)
            case libraryClosed
            case other(String)

            public var text: String {
                switch self {
                case let .disconnected(disk): "\(disk) was disconnected"
                case .libraryClosed: "the library was closed"
                case let .other(text): text
                }
            }
        }

        /// What came across, for Done.
        public struct Fields: Sendable, Hashable {
            public var ratings: Int
            public var picksAndRejects: Int
            public var labels: Int
            public var keywords: Int
            public var collections: Int

            public init(ratings: Int, picksAndRejects: Int, labels: Int, keywords: Int, collections: Int) {
                self.ratings = ratings
                self.picksAndRejects = picksAndRejects
                self.labels = labels
                self.keywords = keywords
                self.collections = collections
            }
        }

        /// Photos written: all of them when done, those kept when stopped or failed.
        public var written: Int
        public var total: Int
        public var partSize: Int
        /// How long the import took.
        public var elapsed: TimeInterval?
        /// Sidecars that couldn't be written for one reason.
        public struct Unwritten: Sendable, Hashable {
            public var count: Int
            /// "the folder is read-only".
            public var reason: String

            public init(_ count: Int, reason: String) {
                self.count = count
                self.reason = reason
            }
        }

        public var fields: Fields?
        public var edits: Edits?
        /// The sidecars that couldn't be written, by reason, most first.
        public var unwritten: [Unwritten]
        public var failure: Failure?
        /// Photos taken back, while Undo Import runs.
        public var undoing: Count?

        public init(
            written: Int, total: Int, partSize: Int = LightroomImport.standardPartSize, elapsed: TimeInterval? = nil,
            fields: Fields? = nil, edits: Edits? = nil, unwritten: [Unwritten] = [], failure: Failure? = nil,
            undoing: Count? = nil,
        ) {
            self.written = written
            self.total = total
            self.partSize = max(partSize, 1)
            self.elapsed = elapsed
            self.fields = fields
            self.edits = edits
            self.failure = failure
            self.undoing = undoing
            self.unwritten = unwritten
        }

        public var parts: Int {
            max(1, (total + partSize - 1) / partSize)
        }
    }

    /// The result's label over its card.
    var resultLabel: String {
        switch phase {
        case .done: "Done"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .undoing: "Taking back"
        case .undone: "Taken back"
        default: ""
        }
    }

    /// The result's sentence.
    var resultTitle: String {
        guard let result else { return "" }
        let written = ProgressText.count(result.written)
        switch phase {
        case .done:
            return "Imported \(ProgressText.count(result.written, "photo")) from “\(catalog)”"
                + (result.elapsed.map { " in \(ProgressText.spoken($0))" } ?? "")
        case .stopped:
            let parts = result.written / result.partSize
            return "Stopped after part \(parts) of \(result.parts): \(written) of \(ProgressText.count(result.total)) "
                + "photos"
        case .failed:
            let part = min(result.parts, result.written / result.partSize + 1)
            return "The import stopped in part \(part): \(result.failure?.text ?? "something went wrong")"
        case .undoing:
            let undoing = result.undoing ?? Count(0, of: result.written)
            return "Taking back the import: \(ProgressText.count(undoing.done)) of "
                + "\(ProgressText.count(undoing.total, "photo"))"
        case .undone:
            return "The import is taken back: \(ProgressText.count(result.written, "photo")) as they were"
        default:
            return ""
        }
    }

    /// A line under the result's sentence.
    struct ResultLine: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            /// What came across, ticked.
            case cameAcross
            case note
            /// The sidecars that couldn't be written, with Show.
            case unwritten
        }

        public var text: String
        public var kind: Kind
        /// The unwritten sidecars' reason, which Show reveals the photos of.
        public var reason: String?

        init(_ text: String, _ kind: Kind = .note, reason: String? = nil) {
            self.text = text
            self.kind = kind
            self.reason = reason
        }
    }

    /// The lines under the result's sentence.
    var resultLines: [ResultLine] {
        guard let result else { return [] }
        switch phase {
        case .done:
            var lines: [ResultLine] = []
            if let fields = result.fields {
                let marks = [
                    fields.ratings > 0 ? ProgressText.count(fields.ratings, "rating") : nil,
                    fields
                        .picksAndRejects > 0 ? "\(ProgressText.count(fields.picksAndRejects)) picks and rejects" : nil,
                    fields.labels > 0 ? ProgressText.count(fields.labels, "label") : nil,
                ].compactMap(\.self)
                if !marks.isEmpty {
                    lines.append(ResultLine(marks.joined(separator: ", "), .cameAcross))
                }
                let lists = [
                    fields.keywords > 0
                        ? "\(ProgressText.count(fields.keywords)) \(fields.keywords == 1 ? "photo's" : "photos'") keywords"
                        : nil,
                    fields.collections > 0 ? "\(ProgressText.count(fields.collections)) in collections" : nil,
                ].compactMap(\.self)
                if !lists.isEmpty {
                    lines.append(ResultLine(lists.joined(separator: ", "), .cameAcross))
                }
            }
            if let edits = result.edits, edits.total > 0 {
                lines.append(ResultLine(
                    ProgressText.count(edits.total, "edit")
                        + (edits.leftOut > 0 ? ", \(ProgressText.count(edits.leftOut)) with settings left out" : ""),
                    .cameAcross,
                ))
            }
            return lines + unwrittenLines(result)
        case .stopped:
            let rest = result.total - result.written
            return [
                ResultLine("The other \(ProgressText.count(rest)) aren't changed."),
                ResultLine(
                    "Import Again brings them; Undo Import takes back the \(ProgressText.count(result.written)).",
                ),
            ] + unwrittenLines(result)
        case .failed:
            let connect = if case let .disconnected(disk) = result.failure {
                "Connect \(disk) and "
            } else {
                ""
            }
            return [
                ResultLine("The \(ProgressText.count(result.written, "photo")) written before are kept."),
                ResultLine("\(connect)Import Again, or Undo Import."),
            ]
        case .undoing:
            return [ResultLine("Edits made since in Redlamp are kept.")]
        case .undone:
            return [ResultLine("Edits made since in Redlamp are kept.")] + (problem.map { [ResultLine($0)] } ?? [])
        default:
            return []
        }
    }

    /// A line for each reason sidecars couldn't be written, with Show.
    private func unwrittenLines(_ result: Result) -> [ResultLine] {
        result.unwritten.map { unwritten in
            ResultLine(
                "\(ProgressText.count(unwritten.count, "sidecar")) couldn't be written: \(unwritten.reason)",
                .unwritten, reason: unwritten.reason,
            )
        }
    }
}
