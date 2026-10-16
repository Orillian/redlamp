import Foundation
import RedlampLibrary
import Testing
@testable @_spi(Harness) import RedlampUI

/// What the Lightroom import window's screens say, worked out from a report and from the import's counts and
/// times (LIB-52), on the harness's made-up catalog.
struct LightroomImportScreenTests {
    private typealias Screen = LightroomImportScreen

    private func sample(_ id: String) throws -> Screen {
        try #require(LightroomImportSamples.states.first { $0.id == id }).screen
    }

    private var review: Screen.Review {
        Screen.Review(
            LightroomImportSamples.report(), disks: LightroomImportSamples.disks, edits: LightroomImportSamples.edits,
        )
    }

    // MARK: - Review

    @Test func `the headline counts come from the report`() {
        let headline = review.headline
        #expect(headline.map(\.figure) == ["48,212", "31,400", "1 folder", "2,818"])
        #expect(headline.map(\.label) == [
            "photos found, of 51,030", "change in the library", "added first, 12,400 photos",
            "not found where Lightroom had them",
        ])
        #expect(review.reachable == 48212 && review.unreachable == 2818)
    }

    @Test func `with every folder in the library, none is added first`() {
        let review = Screen.Review(LightroomImportSamples.smallReport())
        #expect(review.headline[2].figure == "None" && review.headline[2].label == "folders to add first")
        #expect(review.fieldsNote == nil)
        #expect(review.edits == nil)
    }

    @Test func `each field Lightroom gives is a bar, with the part that replaces a value the library has`() {
        let fields = review.fields
        #expect(fields.map(\.name) == [
            "Ratings", "Picks, rejects", "Colour labels", "Marks", "Titles", "Captions", "Locations", "Keywords",
            "Collections",
        ])
        #expect(fields[0] == Screen.Field("Ratings", 31204, replacing: 2100))
        #expect(fields[1] == Screen.Field("Picks, rejects", 4590, replacing: 120))
        #expect(fields[0].figures == "31,204 · 2,100 replace")
        #expect(fields[3].figures == "120")
        #expect(fields[0].accessibilityValue == "31,204 photos, 2,100 replacing another value")
        #expect(review.fieldsCounted == 35812)
        #expect(review.fieldsNote
            == "Counted over the 35,812 photos the library has; the 12,400 in folders added first are read once "
            + "they're indexed.")
    }

    @Test func `the keyword list, collections and smart collections are summed up in a line`() {
        #expect(review.lists
            == "4,812 keywords with their hierarchy and synonyms; 86 collections in 12 sets; 9 of 11 smart collections")
        var report = LightroomImportSamples.blankReport()
        report.keywords = 1
        report.collections = 1
        report.sets = 1
        #expect(Screen.Review(report).lists == "1 keyword with their hierarchy and synonyms; 1 collection in 1 set")
        #expect(Screen.Review(LightroomImportSamples.blankReport()).lists == nil)
    }

    @Test func `each root says where it is and offers Locate or Allow Access when it needs them`() {
        let roots = review.roots
        #expect(roots.map(\.action) == [nil, nil, nil, nil, .locate, .allowAccess, .locate])
        #expect(roots.map(\.stateText) == [
            "In the library: 9,812 of 9,812 found", "Added first: 12,400 photos",
            "In the library: 25,000 of 25,102 found",
            "Moved: in the library, 1,000 of 1,000 found", "Not where Lightroom had it",
            "Redlamp can't read it until you allow access", "On a disk that isn't connected",
        ])
        #expect(roots[3].place == "/Volumes/Archive/Scans → /Volumes/Archive 2/Scans")
        #expect(roots[4].place == "/Volumes/Old Drive/Travel")
        #expect(roots[0].disk == LightroomImportSamples.lacie && roots[4].disk == nil)
    }

    @Test func `the disks are named once each, in the roots' order`() {
        #expect(review.disks
            ==
            "LaCie: external, spinning disk · Macintosh HD: internal · Archive 2: external SSD · Family NAS: network disk")
        #expect(Screen.Review(LightroomImportSamples.report()).disks == nil)
    }

    @Test func `what stays behind lists each thing with its count, smart collections last`() {
        #expect(review.left.map(\.line) == [
            "1,204 virtual copies", "312 stacks", "880 places Lightroom's map gave photos",
            "2 Lightroom's own collections (Previous Import, Quick Collection)", "2 smart collections",
        ])
    }

    @Test func `the edits read fully, approximated and left out, with the commonest reasons`() {
        #expect(LightroomImportSamples.edits.summary
            == "22,100 fully · 9,800 approximated · 3,300 with settings left out (masks 2,900, Point Color 160, …)")
        #expect(Screen.Edits(fully: 10, approximated: 0, leftOut: 2, reasons: [.init("masks", 2)]).summary
            == "10 fully · 2 with settings left out (masks 2)")
        #expect(Screen.Edits(fully: 0, approximated: 0, leftOut: 0).summary == "No edits to bring")
    }

    // MARK: - The bar

    @Test func `the bottom bar's buttons follow the phase`() throws {
        let review = try sample("review")
        #expect(review.buttons.map(\.title) == ["Import 48,212 Photos"])
        #expect(review.buttons[0].isDefault && review.buttons[0].isEnabled)
        #expect(try sample("reading").buttons.map(\.isEnabled) == [false])
        #expect(try sample("writing-ssd").buttons.map(\.kind) == [.stop])
        #expect(try sample("stopping").buttons.map(\.isEnabled) == [false])
        #expect(try sample("done").buttons.map(\.title) == ["Undo Import", "Done"])
        #expect(try sample("stopped").buttons.map(\.kind) == [.undo, .importAgain])
        #expect(try sample("undone").buttons.map(\.title) == ["Import"])
        let empty = Screen(
            phase: .review,
            catalog: "Empty",
            review: Screen.Review(LightroomImportSamples.blankReport()),
        )
        #expect(empty.buttons.map(\.isEnabled) == [false])
        #expect(try sample("writing-ssd").barNote == "You can close this window: the import carries on.")
    }

    // MARK: - Importing

    @Test func `while it writes, the bar is in parts of 10,000 and the rate gives the time left`() throws {
        let screen = try sample("writing-ssd")
        let run = try #require(screen.run)
        #expect(run.parts == 5 && run.part == 2 && run.partCount == Screen.Count(8240, of: 10000))
        #expect(screen.progressTitle == "Writing Lightroom's fields")
        #expect(screen.progressFigure?.figure == "18,240")
        #expect(screen.progressFigure?.label == "of 48,212 photos · part 2 of 5")
        #expect(screen.progressPercent == "37%" && screen.progressParts == 5)
        #expect(screen.paceLine == ["120 a second", "about 4 minutes left", "7 min 12 s so far"])
        #expect(screen.progressAccessibilityValue == "18,240 of 48,212 photos, about 4 minutes left")
    }

    @Test func `the rail shows each stage done, under way or to come, with its detail`() throws {
        let stages = try sample("writing-ssd").stages
        #expect(stages.map(\.title) == ["Read the catalog", "Add 1 folder", "Write", "Done"])
        #expect(stages.map(\.state) == [.done, .done, .now, .next])
        #expect(stages.map(\.detail) == [
            "2.4 s", "12,400 photos indexed in 1 min 35 s", "18,240 of 48,212 photos", "about 4 minutes",
        ])
        #expect(try sample("adding").stages.map(\.state) == [.done, .now, .next, .next])
        #expect(try sample("reading").stages.map(\.state) == [.now, .next, .next])
        #expect(try sample("done").stages.map(\.detail).last == "in 41 minutes")
        #expect(try sample("stopped").stages.map(\.state) == [.done, .done, .stopped, .next])
    }

    @Test func `indexing is a stage of its own, and Paused replaces its rate`() throws {
        let screen = try sample("adding-paused")
        #expect(screen.screen == .importing && screen.progressParts == 1)
        #expect(screen.progressTitle == "Indexing the new folders")
        #expect(screen.progressFigure?.label == "of 12,400 photos indexed")
        #expect(screen.progressPercent == "45%")
        #expect(screen.paceLine == ["Paused", "Low Power Mode is on", "8 min 40 s so far"])
        #expect(screen.progressAccessibilityValue == "5,600 of 12,400 photos, paused: Low Power Mode is on")
        #expect(screen.throughputCaption == "Last 10 minutes · shaded: paused, Low Power Mode")
        #expect(screen.throughputAccessibilityValue.hasSuffix("paused for 2 minutes of the last 10 minutes"))
        #expect(screen.run?.notices.first?.text
            == "Paused: Low Power Mode is on. Plug in or turn it off in System Settings › Battery, and the import "
            + "carries on.")
    }

    @Test func `done, now and next say what's finished, what's under way and what's left`() throws {
        let lines = try #require(try sample("writing-ssd").doneNowNext)
        #expect(lines.done == Screen.Line(
            title: "Part 1: 10,000 photos",
            detail: "Keyword list and collections defined",
        ))
        #expect(lines.now == Screen.Line(title: "Part 2: 8,240 of 10,000", detail: "In Samsung T7 › Photos 2019"))
        #expect(lines.next == Screen.Line(title: "Parts 3 to 5: 28,212 photos", detail: "In 2 folders"))
        let adding = try #require(try sample("adding").doneNowNext)
        #expect(adding.done == Screen.Line(title: "Catalog read: 51,030 photos", detail: "In 2.4 s"))
        #expect(adding.next == Screen.Line(title: "Writing 48,212 photos", detail: "In 5 parts of 10,000"))
    }

    @Test func `Stop pressed says it stops after this part, with the part's own count`() throws {
        let screen = try sample("stopping")
        #expect(screen.progressTitle == "Stopping after this part")
        #expect(screen.progressFigure?.figure == "8,240")
        #expect(screen.progressFigure?.label == "of 10,000 photos in part 2 of 5")
        #expect(screen.paceLine == ["25 min so far"])
        #expect(screen.progressAccessibilityValue == "18,240 of 48,212 photos, stopping after part 2 of 5")
        #expect(screen.doneNowNext?.next.title == "The result")
    }

    @Test func `each root folder's progress reads done, under way or waiting`() throws {
        let roots = try #require(try sample("writing-ssd").run?.roots)
        #expect(roots.map(\.state) == [.done, .now, .waiting, .waiting])
        #expect(roots.map(\.label) == ["9,812", "8,428 of 12,400", "25,000 waiting", "1,000 waiting"])
        #expect(roots[1].accessibilityValue == "8,428 of 12,400 photos")
    }

    // MARK: - Result

    @Test func `done says what came across, and the sidecars that couldn't be written`() throws {
        let done = try sample("done")
        #expect(done.screen == .result && done.resultLabel == "Done")
        #expect(done.resultTitle == "Imported 48,212 photos from “Lightroom Catalog” in 41 minutes")
        #expect(done.resultLines.map(\.text) == [
            "31,204 ratings, 4,590 picks and rejects, 6,900 labels", "21,030 photos' keywords, 14,200 in collections",
            "35,200 edits, 3,300 with settings left out",
        ])
        #expect(done.resultLines.allSatisfy { $0.kind == .cameAcross })
        let unwritten = try sample("done-unwritten").resultLines.last
        #expect(unwritten == Screen.ResultLine("3 sidecars couldn't be written: the folder is read-only", .unwritten))
    }

    @Test func `stopped, failed and taken back each say what the library now holds`() throws {
        let stopped = try sample("stopped")
        #expect(stopped.resultTitle == "Stopped after part 3 of 5: 30,000 of 48,212 photos")
        #expect(stopped.resultLines.map(\.text) == [
            "The other 18,212 aren't changed.", "Import Again brings them; Undo Import takes back the 30,000.",
        ])
        let failed = try sample("failed")
        #expect(failed.resultTitle == "The import stopped in part 4: LaCie was disconnected")
        #expect(failed.resultLines.map(\.text) == [
            "The 30,000 photos written before are kept.", "Connect LaCie and Import Again, or Undo Import.",
        ])
        #expect(try sample("undoing").resultTitle == "Taking back the import: 12,000 of 48,212 photos")
        #expect(try sample("undone").resultTitle == "The import is taken back: 48,212 photos as they were")
    }

    // MARK: - The samples

    @Test func `the harness has a made-up state for every phase, each id once`() {
        let states = LightroomImportSamples.states
        #expect(Set(states.map(\.screen.phase)) == Set(Screen.Phase.allCases))
        #expect(Set(states.map(\.id)).count == states.count)
    }

    @Test func `the log copies as clock times and lines`() throws {
        let text = try sample("done").logText
        #expect(text.hasPrefix("10:22:02 Read “Lightroom Catalog” (Lightroom Classic 13): 51,030 photos"))
        #expect(text.split(separator: "\n").count == 9)
    }
}
