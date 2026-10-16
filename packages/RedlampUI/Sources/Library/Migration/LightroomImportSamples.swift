import Foundation
import RedlampLibrary

/// Made-up screens of the Lightroom import window in every state (LIB-52), for the harness to show and the tests to
/// read: a catalog of 51,030 photos in seven root folders, 48,212 of which the import reaches, 12,400 of them in two
/// folders it adds first. The counts, folders and times are made up.
@_spi(Harness) public enum LightroomImportSamples {
    public struct State: Identifiable, Sendable {
        public enum Size: Sendable {
            /// As the window opens.
            case standard
            /// The window at its smallest.
            case minimum
        }

        public let id: String
        public let title: String
        public let note: String
        public let screen: LightroomImportScreen
        public var detailsOpen = false
        public var size = Size.standard
    }

    public static let catalog = "Lightroom Catalog"

    public static let lacie = LightroomImportScreen.Disk("LaCie", .spinning)
    public static let macintosh = LightroomImportScreen.Disk("Macintosh HD", .internal)
    public static let archive = LightroomImportScreen.Disk("Archive 2", .externalSSD)
    public static let nas = LightroomImportScreen.Disk("Family NAS", .network)
    public static let samsung = LightroomImportScreen.Disk("Samsung T7", .externalSSD)

    // MARK: - Reports

    /// A report with nothing in it, to fill in: `LightroomReport` has no public initialiser, and decodes from JSON.
    public static func blankReport(catalog: String = catalog) -> LightroomReport {
        let fields = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(LightroomReport.Fields()))) ?? [:]
        let edits = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(LightroomReport.Edits()))) ?? [:]
        let zeros = [
            "photos", "found", "waiting", "unlocated", "needingAccess", "offline", "notFound", "pairs", "changing",
            "keywords", "synonyms", "notExported", "people", "collections", "sets",
        ]
        var object: [String: Any] = Dictionary(uniqueKeysWithValues: zeros.map { ($0, 0) })
        object["catalog"] = catalog
        object["version"] = "13"
        for key in ["roots", "notFoundPaths", "smart", "outputs", "left", "notes"] {
            object[key] = [Any]()
        }
        object["renamed"] = [String: String]()
        object["fields"] = fields
        object["differing"] = fields
        object["edits"] = edits
        return decoded(object)
    }

    public static func root(
        _ id: Int64, _ lightroomPath: String, path: String? = nil, moved: Bool = false,
        _ state: LightroomReport.Root.State, photos: Int, found: Int = 0,
    ) -> LightroomReport.Root {
        var object: [String: Any] = [
            "id": id, "name": URL(fileURLWithPath: lightroomPath).lastPathComponent, "lightroomPath": lightroomPath,
            "moved": moved, "state": state.rawValue, "photos": photos, "found": found,
        ]
        if let path = path ?? (state == .missing || state == .offline ? nil : lightroomPath) {
            object["path"] = path
        }
        return decoded(object)
    }

    public static func left(_ what: String, _ count: Int, why: String) -> LightroomReport.Left {
        decoded(["what": what, "count": count, "why": why])
    }

    public static func smart(_ path: String, query: String?, reasons: [String] = []) -> LightroomReport.Smart {
        var object: [String: Any] = ["path": path, "differences": [String](), "reasons": reasons]
        if let query {
            object["query"] = query
        }
        return decoded(object)
    }

    private static func decoded<T: Decodable>(_ object: [String: Any]) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
        } catch {
            preconditionFailure("A made-up \(T.self) didn't decode: \(error)")
        }
    }

    /// The made-up catalog: roots in every state, fields with values the library replaces, and what stays behind.
    public static func report() -> LightroomReport {
        var report = blankReport()
        report.roots = [
            root(1, "/Volumes/LaCie/Photos 2018", .inLibrary, photos: 9812, found: 9812),
            root(2, "/Volumes/LaCie/Photos 2019", .notInLibrary, photos: 12400),
            root(3, "/Users/pat/Pictures/2020 to 2024", .inLibrary, photos: 25102, found: 25000),
            root(
                4, "/Volumes/Archive/Scans", path: "/Volumes/Archive 2/Scans", moved: true, .inLibrary, photos: 1000,
                found: 1000,
            ),
            root(5, "/Volumes/Old Drive/Travel", .missing, photos: 1800),
            root(6, "/Volumes/Family NAS/Family", .needsAccess, photos: 600),
            root(7, "/Volumes/Backup/2017", .offline, photos: 316),
        ]
        report.photos = 51030
        report.found = 35812
        report.waiting = 12400
        report.unlocated = 1800
        report.needingAccess = 600
        report.offline = 316
        report.notFound = 102
        report.notFoundPaths = (1 ... 20).map { "/Users/pat/Pictures/2020 to 2024/Lost/IMG_\(4000 + $0).CR3" }
        report.changing = 31400
        report.fields.ratings = 31204
        report.differing.ratings = 2100
        report.fields.picks = 4200
        report.differing.picks = 100
        report.fields.rejects = 390
        report.differing.rejects = 20
        report.fields.labels = 6900
        report.differing.labels = 410
        report.fields.marks = 120
        report.fields.titles = 1800
        report.differing.titles = 40
        report.fields.captions = 530
        report.differing.captions = 24
        report.fields.locations = 3050
        report.differing.locations = 12
        report.fields.keywords = 21030
        report.fields.collections = 14200
        report.keywords = 4812
        report.synonyms = 312
        report.collections = 86
        report.sets = 12
        report.smart = (1 ... 9).map { smart("Smart › Picks \($0)", query: "rating >= \($0 % 5 + 1)") } + [
            smart("Smart › Edited this week", query: nil, reasons: ["Has Develop edits isn't a rule Redlamp has"]),
            smart("Smart › Faces", query: nil, reasons: ["People aren't brought across"]),
        ]
        report.left = [
            left("virtual copies", 1204, why: "a virtual copy is another edit of its photo in Lightroom"),
            left("stacks", 312, why: "Lightroom's stacks aren't brought across"),
            left("places Lightroom's map gave photos", 880, why: "Redlamp reads where a photo was taken from its file"),
            left(
                "Lightroom's own collections (Previous Import, Quick Collection)", 2,
                why: "Lightroom keeps them for itself",
            ),
        ]
        return report
    }

    /// The disks of the made-up catalog's roots that are connected.
    public static let disks: [Int64: LightroomImportScreen.Disk] = [
        1: lacie,
        2: lacie,
        3: macintosh,
        4: archive,
        6: nas,
    ]

    /// Step 9's Edits section for the made-up catalog.
    public static let edits = LightroomImportScreen.Edits(
        fully: 22100, approximated: 9800, leftOut: 3300,
        reasons: [.init("masks", 2900), .init("Point Color", 160), .init("Lens Blur", 140), .init("profiles", 100)],
    )

    /// A catalog whose folders are all in the library, before step 9's edits: nothing to add first.
    public static func smallReport() -> LightroomReport {
        var report = blankReport(catalog: "Weddings 2025")
        report.roots = [
            root(1, "/Users/pat/Pictures/Weddings", .inLibrary, photos: 6120, found: 6120),
            root(2, "/Users/pat/Pictures/Portraits", .inLibrary, photos: 1880, found: 1874),
        ]
        report.photos = 8000
        report.found = 7994
        report.notFound = 6
        report.notFoundPaths = (1 ... 6).map { "/Users/pat/Pictures/Portraits/DSC_\(1200 + $0).NEF" }
        report.changing = 5210
        report.fields.ratings = 5100
        report.fields.picks = 1400
        report.fields.labels = 820
        report.differing.labels = 30
        report.fields.keywords = 3900
        report.fields.collections = 2400
        report.keywords = 310
        report.collections = 24
        report.sets = 3
        report.left = [left("virtual copies", 96, why: "a virtual copy is another edit of its photo in Lightroom")]
        return report
    }

    // MARK: - States

    private static let started: Date = {
        let components = DateComponents(year: 2026, month: 10, day: 16, hour: 10, minute: 22, second: 2)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }()

    private static func at(_ clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Double($0) }
        let seconds = parts.count == 3 ? parts[0] * 3600 + parts[1] * 60 + parts[2] : 0
        return started.addingTimeInterval(seconds - (10 * 3600 + 22 * 60 + 2))
    }

    private static let fullLog: [LightroomImportScreen.LogEntry] = [
        .init(
            at("10:22:02"),
            "Read “Lightroom Catalog” (Lightroom Classic 13): 51,030 photos, 7 root folders, in 2.4 s",
        ),
        .init(at("10:22:05"), "Added 1 folder to Folders: LaCie › Photos 2019"),
        .init(at("10:24:40"), "Paused: Low Power Mode is on"),
        .init(at("10:25:52"), "Carried on: Low Power Mode is off"),
        .init(at("10:33:10"), "Indexed 12,400 photos in 11 min 5 s, 19 a second, on LaCie (spinning disk)"),
        .init(
            at("10:33:12"),
            "Found 48,212 of the catalog's photos; 2,818 not found (the first 20 listed in the report)",
        ),
        .init(at("10:37:10"), "Part 1 of 5 written: 10,000 photos in 3 min 58 s; keyword list and collections defined"),
        .init(at("10:41:12"), "Part 2 of 5 written: 10,000 photos in 4 min 2 s"),
    ]

    private static func log(until clock: String) -> [LightroomImportScreen.LogEntry] {
        fullLog.filter { $0.time <= at(clock) }
    }

    /// Rates over the chart's sixty bins, steady with a little wobble, the newest `paused` bins paused for `reason`;
    /// bins before `from` are before the stage started.
    private static func bins(
        _ rate: Double, from: Int = 0, paused: Int = 0, reason: PauseReason = .lowPower, dip: Range<Int>? = nil,
    ) -> [ThroughputBin] {
        (0 ..< 60).map { index in
            guard index >= from else { return ThroughputBin(perSecond: nil) }
            if index >= 60 - paused {
                return ThroughputBin(perSecond: index == 60 - paused ? rate * 0.3 : 0, paused: reason)
            }
            let wobble = 1 + 0.07 * sin(Double(index) * 1.7) + 0.04 * sin(Double(index) * 4.3)
            let ramp = index == from ? 0.6 : 1
            let dipped = dip?.contains(index) == true ? 0.35 : 1
            return ThroughputBin(perSecond: rate * wobble * ramp * dipped)
        }
    }

    private static func roots(_ written: Int, disk: LightroomImportScreen.Disk? = nil) -> [LightroomImportScreen
        .RootProgress] {
        var left = written
        return [
            ("LaCie", "Photos 2018", lacie, 9812), ("LaCie", "Photos 2019", lacie, 12400),
            ("Pictures", "2020 to 2024", macintosh, 25000), ("Archive 2", "Scans", archive, 1000),
        ].map { place, folder, rootDisk, total in
            let done = min(left, total)
            left -= done
            return LightroomImportScreen.RootProgress(
                "\(disk?.name ?? place) › \(folder)", disk: disk ?? rootDisk, .init(done, of: total),
            )
        }
    }

    private static func screen(
        _ phase: LightroomImportScreen.Phase, review: LightroomImportScreen.Review? = nil, run: LightroomImportScreen
            .Run? = nil, result: LightroomImportScreen.Result? = nil, log: [LightroomImportScreen.LogEntry] = [],
    ) -> LightroomImportScreen {
        let report = report()
        return LightroomImportScreen(
            phase: phase, catalog: catalog, readTime: phase == .reading ? nil : 2.4,
            review: review ?? LightroomImportScreen.Review(report, disks: disks, edits: edits), run: run,
            result: result, log: log, reportText: report.lines(), canUndo: [.done, .stopped, .failed].contains(phase),
        )
    }

    private static let total = 48212

    private static let fields = LightroomImportScreen.Result.Fields(
        ratings: 31204, picksAndRejects: 4590, labels: 6900, keywords: 21030, collections: 14200,
    )

    public static var states: [State] {
        let indexed = LightroomImportScreen.Count(12400, of: 12400)
        let writingSpinning = LightroomImportScreen.Run(
            folders: 1, indexed: indexed, indexTime: 665, written: .init(9400, of: total), elapsed: 2520,
            pace: .steady(perSecond: 6.1, secondsLeft: Double(total - 9400) / 6.1), throughput: bins(6.1, from: 14),
            roots: roots(9400), notices: [.spinning(disk: "LaCie")],
        )
        let small = smallReport()
        return [
            State(
                id: "reading", title: "Reading the catalog",
                note: "The rail's first stage under way; no estimate before the import runs. Import waits, disabled.",
                screen: LightroomImportScreen(phase: .reading, catalog: catalog),
            ),
            State(
                id: "review", title: "Review: roots in every state, with edits",
                note: "In the library, added first, moved, not found, needing access and offline, each disk named; "
                    + "the field bars' first, stronger part replaces a value the library shows.",
                screen: screen(.review),
            ),
            State(
                id: "review-no-edits", title: "Review: every folder in the library, no edits",
                note: "As before step 9 lands: no Edits section, nothing to add first, one thing staying behind.",
                screen: LightroomImportScreen(
                    phase: .review, catalog: small.catalog, readTime: 0.6,
                    review: .init(small, disks: [1: macintosh, 2: macintosh]), reportText: small.lines(),
                ),
            ),
            State(
                id: "adding", title: "Adding a folder, with its rate",
                note: "Indexing is a stage of its own, with its own rate and time left (no part split while it indexes).",
                screen: screen(.adding, run: .init(
                    folders: 1, indexed: .init(3100, of: 12400), written: .init(0, of: total), elapsed: 170,
                    pace: .steady(perSecond: 19, secondsLeft: 9300 / 19), throughput: bins(19, from: 43),
                    roots: [.init("LaCie › Photos 2019", disk: lacie, .init(3100, of: 12400))],
                    notices: [.spinning(disk: "LaCie")],
                ), log: log(until: "10:22:05")),
            ),
            State(
                id: "adding-paused", title: "Indexing paused by Low Power Mode",
                note: "Nothing moved for 10 seconds while paused: Paused and why replace the rate; the chart shades it.",
                screen: screen(.adding, run: .init(
                    folders: 1, indexed: .init(5600, of: 12400), written: .init(0, of: total), elapsed: 520,
                    pace: .paused(.lowPower), throughput: bins(19, from: 8, paused: 12),
                    roots: [.init("LaCie › Photos 2019", disk: lacie, .init(5600, of: 12400))],
                    notices: [.paused(.lowPower), .spinning(disk: "LaCie")],
                ), log: log(until: "10:24:40")),
            ),
            State(
                id: "writing-ssd", title: "Writing part 2 of 5 on an SSD",
                note: "The bar in five parts; Stop ends at a part's end. No notices: nothing is slow.",
                screen: screen(.writing, run: .init(
                    folders: 1, indexed: indexed, indexTime: 95, written: .init(18240, of: total), elapsed: 432,
                    pace: .steady(perSecond: 120, secondsLeft: Double(total - 18240) / 120),
                    throughput: bins(120, from: 20, dip: 31 ..< 33), roots: roots(18240, disk: samsung),
                ), log: log(until: "10:37:10")),
            ),
            State(
                id: "writing-spinning", title: "Writing on a spinning disk, hours left",
                note: "About 1 h 45 min, rounded to five minutes past the hour; the spinning disk's notice says why.",
                screen: screen(.writing, run: writingSpinning, log: log(until: "10:33:12")),
            ),
            State(
                id: "writing-details", title: "Writing, Details open",
                note: "The log opened, as it stays once opened; Copy, and Report Text for the report's lines.",
                screen: screen(.writing, run: writingSpinning, log: log(until: "10:33:12")), detailsOpen: true,
            ),
            State(
                id: "stopping", title: "Stopping",
                note: "Stop pressed: “Stopping after this part” with the part's own count; Stop disabled.",
                screen: screen(.stopping, run: .init(
                    folders: 1, indexed: indexed, indexTime: 665, written: .init(18240, of: total), elapsed: 1500,
                    pace: .steady(perSecond: 42, secondsLeft: 714), throughput: bins(42, from: 10), roots: roots(18240),
                    notices: [.spinning(disk: "LaCie")],
                ), log: log(until: "10:41:12")),
            ),
            State(
                id: "done", title: "Done",
                note: "What came across, the time it took; Undo Import and Done in the bar.",
                screen: screen(
                    .done,
                    run: .init(
                        folders: 1, indexed: indexed, indexTime: 665, written: .init(total, of: total), elapsed: 2460,
                        roots: roots(total),
                    ),
                    result: .init(written: total, total: total, elapsed: 2460, fields: fields, edits: edits),
                    log: fullLog + [.init(at("11:03:02"), "Imported 48,212 photos in 41 min")],
                ),
            ),
            State(
                id: "done-unwritten", title: "Done, with sidecars that couldn't be written",
                note: "The sidecars this build couldn't write, why, and Show.",
                screen: screen(.done, run: .init(
                    folders: 1, indexed: indexed, indexTime: 665, written: .init(total, of: total), elapsed: 2460,
                    roots: roots(total),
                ), result: .init(
                    written: total, total: total, elapsed: 2460, fields: fields, edits: edits,
                    unwritten: [
                        .init(3, reason: "the folder is read-only"),
                        .init(1, reason: "its sidecar was written by a newer Redlamp"),
                    ],
                ), log: fullLog + [.init(
                    at("10:43:20"), "3 sidecars couldn't be written: /Volumes/LaCie/Photos 2019/Locked is read-only",
                )]),
            ),
            State(
                id: "stopped", title: "Stopped",
                note: "How many parts were written, and what Import Again and Undo Import do.",
                screen: screen(.stopped, run: .init(
                    folders: 1, indexed: indexed, indexTime: 665, written: .init(30000, of: total), elapsed: 1980,
                    roots: roots(30000),
                ), result: .init(written: 30000, total: total, elapsed: 1980), log: fullLog + [
                    .init(at("10:45:10"), "Part 3 of 5 written: 10,000 photos in 3 min 58 s"),
                    .init(at("10:45:11"), "Stopped after part 3 of 5: 30,000 photos written, 18,212 not changed"),
                ]),
            ),
            State(
                id: "failed", title: "Failed",
                note: "Why in words, what was kept, and both ways on.",
                screen: screen(.failed, run: .init(
                    folders: 1, indexed: indexed, indexTime: 665, written: .init(30000, of: total), elapsed: 2100,
                    roots: roots(30000), notices: [.disconnected(disk: "LaCie")],
                ), result: .init(written: 30000, total: total, failure: .disconnected(disk: "LaCie")), log: fullLog + [
                    .init(at("10:45:10"), "Part 3 of 5 written: 10,000 photos in 3 min 58 s"),
                    .init(
                        at("10:47:02"),
                        "LaCie was disconnected: the import stopped in part 4; the 30,000 photos written are kept",
                    ),
                ]),
            ),
            State(
                id: "undoing", title: "Undoing",
                note: "Taking the import back, with its own bar.",
                screen: screen(.undoing, run: .init(written: .init(total, of: total)), result: .init(
                    written: total, total: total, undoing: .init(12000, of: total),
                ), log: fullLog + [.init(at("11:02:30"), "Taking back the import of 48,212 photos")]),
            ),
            State(
                id: "undone", title: "Undone",
                note: "Each photo as it was; Import starts again.",
                screen: screen(.undone, run: .init(written: .init(total, of: total)), result: .init(
                    written: total, total: total,
                ), log: fullLog + [.init(at("11:04:12"), "Took back the import: 48,212 photos as they were")]),
            ),
            State(
                id: "minimum-writing", title: "Writing, at the window's minimum size",
                note: "600 × 480 points: the content scrolls rather than clips.",
                screen: screen(.writing, run: writingSpinning, log: log(until: "10:41:12")), size: .minimum,
            ),
            State(
                id: "minimum-review", title: "Review, at the window's minimum size",
                note: "600 × 480 points.",
                screen: screen(.review), size: .minimum,
            ),
        ]
    }
}
