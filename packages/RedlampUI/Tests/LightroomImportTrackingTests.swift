import Foundation
import RedlampLibrary
import Testing
@testable @_spi(Harness) import RedlampUI

/// The Lightroom import window's screen as the model fills it (LIB-52): what the model knows, handed over as it
/// changes and on each second's tick, at made-up times, worked out into the phase, each stage's rate, each root
/// folder's progress, how the import ended and the log.
struct LightroomImportTrackingTests {
    private typealias Facts = LightroomImportTracking.Facts
    private typealias Screen = LightroomImportScreen

    private let start = LightroomMoment(date: Date(timeIntervalSinceReferenceDate: 800_000_000), uptime: 1000)
    private let lacie = "/Volumes/LaCie/Photos 2018"
    private let added = "/Volumes/LaCie/Photos 2019"

    /// A catalog of 1,800 photos: 600 in a folder the library has, 1,200 in one it adds first.
    private func report() -> LightroomReport {
        var report = LightroomImportSamples.blankReport(catalog: "/Users/pat/Lightroom/Lightroom Catalog.lrcat")
        report.roots = [
            LightroomImportSamples.root(1, lacie, .inLibrary, photos: 600, found: 600),
            LightroomImportSamples.root(2, added, .notInLibrary, photos: 1200),
        ]
        report.photos = 1800
        report.found = 600
        report.waiting = 1200
        report.changing = 600
        return report
    }

    private func at(_ seconds: TimeInterval) -> LightroomMoment {
        start.adding(seconds)
    }

    /// The catalog read in 2.4 s and reported.
    private func reported() -> (LightroomImportTracking, Facts) {
        var tracking = LightroomImportTracking()
        var facts = Facts()
        facts.catalog = "Lightroom Catalog"
        facts.phase = .reading
        tracking.observe(facts, at: at(0))
        facts.phase = .reported
        facts.report = report()
        facts.canImport = true
        tracking.observe(facts, at: at(2.4))
        return (tracking, facts)
    }

    /// Reported, then adding its folder from second 10, 15 photos indexed a second for `seconds`.
    private func indexing(for seconds: Int) -> (LightroomImportTracking, Facts) {
        var (tracking, facts) = reported()
        facts.phase = .adding
        tracking.observe(facts, at: at(10))
        for second in stride(from: 1, through: seconds, by: 1) {
            facts.indexed = (min(second * 15, 1200), 1200)
            facts.indexedRoots = [added: min(second * 15, 1200)]
            tracking.observe(facts, at: at(10 + Double(second)))
        }
        return (tracking, facts)
    }

    /// Writing `total` photos from second `from`.
    private func writing(
        _ tracking: inout LightroomImportTracking, _ facts: inout Facts, total: Int, from: TimeInterval,
    ) {
        facts.phase = .importing
        facts.indexed = nil
        facts.progress = LightroomImport.Progress(done: 0, total: total, part: 0, parts: Self.parts(total))
        tracking.observe(facts, at: at(from))
    }

    private func wrote(
        _ done: Int, of total: Int, _ tracking: inout LightroomImportTracking, _ facts: inout Facts,
        at seconds: TimeInterval,
    ) {
        facts.progress = LightroomImport.Progress(
            done: done, total: total, part: min(done / 10000, Self.parts(total) - 1), parts: Self.parts(total),
        )
        tracking.observe(facts, at: at(seconds))
    }

    private static func parts(_ total: Int) -> Int {
        max(1, (total + 9999) / 10000)
    }

    // MARK: - Phases

    @Test func `the model's phases show as the screen's, stopped and failed told apart from done`() {
        var (tracking, facts) = reported()
        #expect(tracking.screen(at: at(3)).phase == .review)
        facts.phase = .adding
        tracking.observe(facts, at: at(10))
        #expect(tracking.screen(at: at(11)).phase == .adding)
        writing(&tracking, &facts, total: 1800, from: 20)
        #expect(tracking.screen(at: at(21)).phase == .writing)
        facts.phase = .stopping
        tracking.observe(facts, at: at(22))
        #expect(tracking.screen(at: at(23)).phase == .stopping)

        var done = (tracking, facts)
        done.1.phase = .imported
        done.1.outcome = LightroomImportTracking.Outcome(stopped: false)
        done.0.observe(done.1, at: at(30))
        #expect(done.0.screen(at: at(31)).phase == .done)

        var stopped = (tracking, facts)
        stopped.1.phase = .imported
        stopped.1.outcome = LightroomImportTracking.Outcome(stopped: true)
        stopped.0.observe(stopped.1, at: at(30))
        #expect(stopped.0.screen(at: at(31)).phase == .stopped)

        var failed = (tracking, facts)
        failed.1.phase = .imported
        failed.1.problem = "The import stopped: the disk is full"
        failed.0.observe(failed.1, at: at(30))
        let screen = failed.0.screen(at: at(31))
        #expect(screen.phase == .failed && screen.result?.failure == .other("the disk is full"))

        facts.phase = .choosing
        facts.problem = "notes.lrcat isn't a Lightroom Classic catalog"
        var unread = LightroomImportTracking()
        var reading = Facts()
        reading.phase = .reading
        unread.observe(reading, at: at(0))
        unread.observe(facts, at: at(1))
        #expect(unread.screen(at: at(2)).phase == .reading)
        #expect(unread.screen(at: at(2)).problem == "notes.lrcat isn't a Lightroom Classic catalog")
    }

    @Test func `the review takes the read time, the report, each root folder's disk and the edits`() {
        var (tracking, facts) = reported()
        tracking.found([lacie: LightroomRootDisk(name: "LaCie", isLocal: true, isInternal: false)])
        facts.report?.edits.photos = 500
        facts.report?.edits.full = 420
        facts.report?.edits.approximated = 60
        facts.report?.edits.leftOut = 20
        facts.canUndo = true
        tracking.observe(facts, at: at(3))
        let screen = tracking.screen(at: at(4))
        #expect(ProgressText.duration(screen.readTime ?? 0) == "2.4 s")
        #expect(screen.review?.reachable == 1800 && screen.review?.foldersToAdd == 1)
        #expect(screen.review?.roots.first?.disk == Screen.Disk("LaCie", .external), "not known to spin yet")
        #expect(screen.review?.roots.last?.disk == nil)
        #expect(screen.review?.edits == Screen.Edits(fully: 420, approximated: 60, leftOut: 20))
        #expect(screen.buttons.map(\.kind) == [.undo, .importPhotos])
        #expect(screen.reportText.first?.hasPrefix("/Users/pat/Lightroom/Lightroom Catalog.lrcat: Lightroom") == true)
        #expect(LightroomImportTracking.short(
            "not yet checked against Lightroom: where masks and spots sit, Upright",
        ) == "not yet checked against Lightroom")
        #expect(LightroomImportTracking.short("Process 2003's and 2010's tone, which EDT-31 is to convert")
            == "Process 2003's and 2010's tone")
    }

    // MARK: - Rates

    @Test func `indexing and writing each have a rate of their own, from the last minute`() {
        var (tracking, facts) = indexing(for: 70)
        let indexingScreen = tracking.screen(at: at(80))
        #expect(indexingScreen.run?.indexed == Screen.Count(1050, of: 1200))
        #expect(indexingScreen.run?.pace == .steady(perSecond: 15, secondsLeft: 10))
        #expect(indexingScreen.progressFigure?.label == "of 1,200 photos indexed")

        writing(&tracking, &facts, total: 1800, from: 82)
        #expect(tracking.screen(at: at(85)).run?.pace == .measuring, "a stage's first 10 seconds")
        for second in 1 ... 60 {
            wrote(second * 20, of: 1800, &tracking, &facts, at: 82 + Double(second))
        }
        let writingScreen = tracking.screen(at: at(142))
        #expect(writingScreen.run?.pace == .steady(perSecond: 20, secondsLeft: 30))
        #expect(writingScreen.run?.written == Screen.Count(1200, of: 1800))
        #expect(writingScreen.run?.indexTime == 72 && writingScreen.run?.elapsed == 132)
        #expect(tracking.indexMeter?.start == 1010 && tracking.writeMeter?.start == 1082, "a meter for each stage")
        #expect((tracking.writeMeter?.samples.count ?? 0) > 60, "fed on every progress")
        #expect(writingScreen.run?.throughput.count == 60)
    }

    @Test func `while the Mac holds the indexer back and nothing moves, Paused shows and the log says why`() {
        var (tracking, facts) = indexing(for: 1)
        for second in 2 ... 15 {
            tracking.tick(at: at(10 + Double(second)), pausedBy: .lowPower, missing: [])
        }
        let screen = tracking.screen(at: at(25))
        #expect(screen.run?.pace == .paused(.lowPower))
        #expect(screen.run?.notices == [.paused(.lowPower)])
        #expect(screen.paceLine.prefix(2) == ["Paused", "Low Power Mode is on"])
        #expect(tracking.log.last?.text == "Paused: Low Power Mode is on")

        facts.indexed = (150, 1200)
        facts.pausedBy = nil
        tracking.observe(facts, at: at(26))
        tracking.tick(at: at(27), pausedBy: nil, missing: [])
        #expect(tracking.log.last?.text == "Carried on: Low Power Mode is off")
        #expect(tracking.screen(at: at(27)).run?.notices == [])
    }

    // MARK: - Root folders

    @Test func `each root folder's progress: indexed while it's added, then written in the import's order`() {
        var (tracking, facts) = indexing(for: 20)
        tracking.found([added: LightroomRootDisk(name: "LaCie", isLocal: true, isInternal: false, spins: true)])
        var screen = tracking.screen(at: at(30))
        #expect(screen.run?.roots == [Screen.RootProgress(
            "LaCie › Photos 2019", disk: Screen.Disk("LaCie", .spinning), Screen.Count(300, of: 1200),
        )])
        #expect(screen.run?.notices == [.spinning(disk: "LaCie")])

        writing(&tracking, &facts, total: 1800, from: 40)
        tracking.photoRoots(Array(repeating: 2, count: 3), run: tracking.run - 1)
        tracking.photoRoots(
            Array(repeating: 1, count: 600) + Array(repeating: 2, count: 1200) + [nil],
            run: tracking.run,
        )
        wrote(900, of: 1800, &tracking, &facts, at: 50)
        screen = tracking.screen(at: at(50))
        let roots = screen.run?.roots ?? []
        #expect(roots.map(\.name) == ["LaCie › Photos 2018", "LaCie › Photos 2019"])
        #expect(roots.map(\.count) == [Screen.Count(600, of: 600), Screen.Count(300, of: 1200)])
        #expect(roots.map(\.state) == [.done, .now])
        #expect(screen.doneNowNext?.now.detail == "In LaCie › Photos 2019")
    }

    // MARK: - How it ended

    @Test func `the sidecars that couldn't be written are grouped by reason, most first`() {
        var (tracking, facts) = reported()
        writing(&tracking, &facts, total: 600, from: 10)
        wrote(600, of: 600, &tracking, &facts, at: 40)
        facts.phase = .imported
        facts.outcome = LightroomImportTracking.Outcome(stopped: false, skipped: [
            "/Volumes/LaCie/Photos 2018/Locked/A.CR3": "the folder is read-only",
            "/Volumes/LaCie/Photos 2018/Locked/B.CR3": "the folder is read-only",
            "/Volumes/LaCie/Photos 2018/C.CR3": "its sidecar was written by a newer Redlamp",
        ])
        tracking.observe(facts, at: at(41))
        let screen = tracking.screen(at: at(42))
        #expect(screen.result?.unwritten == [
            .init(2, reason: "the folder is read-only"), .init(1, reason: "its sidecar was written by a newer Redlamp"),
        ])
        #expect(screen.resultTitle == "Imported 600 photos from “Lightroom Catalog” in 31 seconds")
        #expect(screen.resultLines.filter { $0.kind == .unwritten }.count == 2)
        #expect(tracking.log.suffix(2).map(\.text) == [
            "2 sidecars couldn't be written: the folder is read-only",
            "1 sidecar couldn't be written: its sidecar was written by a newer Redlamp",
        ])
    }

    @Test func `a stopped import keeps the part it was writing, and a failed one the parts before`() {
        var (tracking, facts) = reported()
        writing(&tracking, &facts, total: 25000, from: 10)
        wrote(12000, of: 25000, &tracking, &facts, at: 100)
        var stopped = (tracking, facts)
        stopped.1.phase = .stopping
        stopped.0.observe(stopped.1, at: at(101))
        stopped.1.phase = .imported
        stopped.1.outcome = LightroomImportTracking.Outcome(stopped: true)
        stopped.0.observe(stopped.1, at: at(150))
        let screen = stopped.0.screen(at: at(151))
        #expect(screen.result?.written == 20000)
        #expect(screen.resultTitle == "Stopped after part 2 of 3: 20,000 of 25,000 photos")
        #expect(stopped.0.log.suffix(2).map(\.text) == [
            "Stop pressed: the import stops after part 2 of 3",
            "Stopped after part 2 of 3: 20,000 photos written, 5,000 not changed",
        ])

        tracking.photoRoots(Array(repeating: 2, count: 25000), run: tracking.run)
        tracking.found([added: LightroomRootDisk(name: "LaCie", isLocal: true, isInternal: false)])
        tracking.tick(at: at(101), pausedBy: nil, missing: [added])
        #expect(tracking.screen(at: at(102)).run?.notices == [.disconnected(disk: "LaCie")])
        facts.phase = .imported
        facts.problem = "The import stopped: The file “C.CR3.redlamp” couldn't be saved."
        tracking.observe(facts, at: at(103))
        let failed = tracking.screen(at: at(104))
        #expect(failed.result?.failure == .disconnected(disk: "LaCie") && failed.result?.written == 10000)
        #expect(failed.resultTitle == "The import stopped in part 2: LaCie was disconnected")
        #expect(tracking.log.suffix(2).map(\.text) == [
            "LaCie was disconnected",
            "The import stopped in part 2: LaCie was disconnected; the 10,000 photos written before are kept",
        ])
    }

    @Test func `an import that fails as the library closes says so`() {
        var (tracking, facts) = reported()
        writing(&tracking, &facts, total: 600, from: 10)
        facts.phase = .imported
        facts.problem = "The import stopped: CancellationError()"
        facts.libraryOpen = false
        tracking.observe(facts, at: at(12))
        #expect(tracking.screen(at: at(13)).result?.failure == .libraryClosed)
        #expect(tracking.log.last?.text == "The import stopped in part 1: the library was closed; nothing was written")
    }

    @Test func `Undo Import's progress counts the photos taken back`() {
        var (tracking, facts) = reported()
        facts.phase = .undoing
        facts.undoPhotos = 600
        tracking.observe(facts, at: at(10))
        tracking.undid(1, of: 2)
        var screen = tracking.screen(at: at(11))
        #expect(screen.phase == .undoing && screen.result?.undoing == Screen.Count(300, of: 600))
        #expect(screen.resultTitle == "Taking back the import: 300 of 600 photos")
        facts.phase = .undone
        tracking.observe(facts, at: at(12))
        screen = tracking.screen(at: at(13))
        #expect(screen.resultTitle == "The import is taken back: 600 photos as they were")
        #expect(tracking.log.suffix(2).map(\.text) == [
            "Taking back the import of 600 photos", "Took back the import: 600 photos as they were",
        ])
    }

    // MARK: - The log

    @Test func `the log says each stage's start and end, with its count and time`() {
        var (tracking, facts) = indexing(for: 80)
        writing(&tracking, &facts, total: 21800, from: 100)
        wrote(10500, of: 21800, &tracking, &facts, at: 160)
        wrote(21800, of: 21800, &tracking, &facts, at: 220)
        facts.phase = .imported
        facts.outcome = LightroomImportTracking.Outcome(stopped: false)
        tracking.observe(facts, at: at(221))
        #expect(tracking.log.map(\.text) == [
            "Read “Lightroom Catalog”: 1,800 photos in 2 root folders, in 2.4 s",
            "Added 1 folder to Folders: LaCie › Photos 2019",
            "Indexed 1,200 photos in 1 min 30 s, 13 a second",
            "Writing Lightroom's fields to 21,800 photos, in 3 parts of 10,000",
            "Part 1 of 3 written: 10,000 photos in 1 min; keyword list and collections defined",
            "Part 2 of 3 written: 10,000 photos in 1 min",
            "Part 3 of 3 written: 1,800 photos in 0 s",
            "Imported 21,800 photos in 4 minutes",
        ])
        #expect(tracking.log.first?.time == at(2.4).date)
        let screen = tracking.screen(at: at(222))
        #expect(screen.logText.hasPrefix("\(screen.log[0].clockTime) Read “Lightroom Catalog”"))
    }

    @Test func `root folders are named by the disk or folder they're in`() {
        #expect(LightroomImportTracking.name(of: "/Volumes/LaCie/Photos 2019") == "LaCie › Photos 2019")
        #expect(LightroomImportTracking.name(of: "/Users/pat/Pictures/2020 to 2024") == "Pictures › 2020 to 2024")
        #expect(LightroomImportTracking.name(of: "/Volumes/Archive") == "Archive")
        #expect(LightroomImportTracking.count([0, 1, 5, 9], below: 6) == 3)
    }
}
