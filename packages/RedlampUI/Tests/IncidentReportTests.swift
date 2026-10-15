import AppKit
import Foundation
import Testing
@_spi(Harness) @testable import RedlampUI

/// A report on a crash or a hang in an earlier session: its issue and diagnostics.json from the fixtures
/// (`IncidentTests`), what's redacted from them, what each detail's switch leaves out, the sheet's crash mode, what
/// sending, queueing and Not Now do to Your Reports, and which crash or hang the banner offers, and when it waits for a
/// failed save's banner.
@MainActor
struct IncidentReportTests {
    private final class Relay: FeedbackSending, @unchecked Sendable {
        var result: Result<FeedbackResult, FeedbackError> = .success(.filed(
            number: 42,
            url: URL(string: "https://github.com/pdcgomes/redlamp/issues/42")!,
        ))
        var sent: [FeedbackSubmission] = []

        func send(_ submission: FeedbackSubmission) async throws -> FeedbackResult {
            sent.append(submission)
            return try result.get()
        }
    }

    private let defaults = UserDefaults(suiteName: "IncidentReportTests-\(UUID().uuidString)")!
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "IncidentReportTests-\(UUID().uuidString)")

    static func event(_ seconds: TimeInterval, from time: Date, _ kind: ActivityLog.Event.Kind, _ text: String)
        -> ActivityLog.Event {
        ActivityLog.Event(time: time.addingTimeInterval(seconds), kind: kind, text: text, key: nil)
    }

    /// The fixtures' crash as the launch check merges it, with what its session did: a photo opened, an edit, a save
    /// that failed in a folder under a made-up home, and an export to this Mac's home folder.
    static func crash() throws -> PendingIncident {
        let incident = try IncidentTests.crashReport().merged(with: IncidentTests.metricKit())
        let time = incident.time
        return PendingIncident(
            incident: incident,
            activity: [
                event(-3600, from: time, .photo, "Opened Photo Z: CR3, 6000 × 4000, unedited, in 0.9 s"),
                event(-250, from: time, .photo, "Opened Photo A: CR3, Canon EOS R5, 8192 × 5464, unedited, in 1.1 s"),
                event(-120, from: time, .edit, "Exposure: 0.00 → +0.50"),
                event(
                    -30, from: time, .error,
                    "Save failed: Couldn’t write “/Users/someone/Pictures/Holiday/IMG_0001.CR3.redlamp”",
                ),
                event(-10, from: time, .export, "Exported Photo A to \(NSHomeDirectory())/Desktop/IMG_0001.jpg"),
            ],
            photos: [PhotoName(alias: "Photo A", fileName: "IMG_0001.CR3")],
            folders: ["/Users/someone/Pictures/Holiday"],
            found: time.addingTimeInterval(120),
        )
    }

    static let hangBegan = Date(timeIntervalSinceReferenceDate: 812_000_000)

    /// A hang the watchdog marked, which macOS sent no stacks for.
    static func hang(seconds: TimeInterval, closed: Bool, activity: [ActivityLog.Event] = []) -> PendingIncident {
        var hang = Incident(kind: .hang, time: hangBegan, pid: 4300, sources: [.watchdog])
        hang.duration = seconds
        hang.endedSession = closed
        hang.version = "0.3.2-alpha (431)"
        return PendingIncident(incident: hang, activity: activity, found: hangBegan.addingTimeInterval(600))
    }

    private func sheet(_ pending: PendingIncident, relay: Relay = Relay()) -> FeedbackSheetModel {
        FeedbackSheetModel(
            context: FeedbackContext(reporting: pending), system: FeedbackReportTests.system, windowShot: nil,
            prefill: FeedbackPrefill(incident: pending), sender: relay, dryRun: false, defaults: defaults,
        )
    }

    private func issue(_ report: FeedbackReport, _ pending: PendingIncident) -> String {
        report.issueBody(context: FeedbackContext(reporting: pending), system: FeedbackReportTests.system, log: [])
    }

    private func diagnostics(_ report: FeedbackReport, _ pending: PendingIncident) throws -> [String: Any]? {
        let data = try report.diagnostics(
            context: FeedbackContext(reporting: pending),
            system: FeedbackReportTests.system,
            log: [],
        )
        return try data.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// What identifies the Mac, its memory or the person, in the fixtures or the session.
    static let secrets = [
        "AAAAAAAA-BBBB", "99999999-8888", "11111111-2222", "78BDDDBE", "3JP75Z3F98", "ARM_THREAD_STATE64",
        "/Applications/Redlamp.app", "app.redlamp.probe", "mapped file", "/Users/", "someone", "Holiday", "IMG_0001",
        NSHomeDirectory(),
    ]

    // MARK: - The issue

    @Test func `a crash's issue says what happened, then the crashed thread's stack and what came before it`() throws {
        let pending = try Self.crash()
        let report = sheet(pending).outgoing
        #expect(report.issueTitle(context: FeedbackContext(reporting: pending))
            == "[Performance & Stability › Crashes] Crash: EXC_BAD_ACCESS (SIGSEGV) in Redlamp")
        #expect(report.labels == ["in-app", "bug", "component:performance"])
        let body = issue(report, pending)
        #expect(body.hasPrefix(
            #"<!-- redlamp-feedback v1 {"area":"performance.crash","incident":"crash","kind":"bug","report":""#,
        ))
        for line in [
            "### What happened", "Redlamp quit unexpectedly.", "- **Exception:** EXC_BAD_ACCESS (SIGSEGV)",
            "  - KERN_INVALID_ADDRESS at 0x0000000000000010", "  - while reading …/Photo A", "- **In:** Redlamp",
            "- **Version:** Redlamp 0.3.2-alpha (431)", "- **When:** 2026-10-14 09:08:08 UTC",
            "- **Recorded by:** macOS's crash report and MetricKit",
            "### The crashed thread (thread 0, the main thread)",
            "0  Redlamp" + String(repeating: " ", count: 12)
                + "partial apply for closure #1 in Delegate.applicationDidFinishLaunching(_:)",
            "7  libdispatch.dylib  _dispatch_main_queue_drain",
            "<summary>What happened before the crash (last 15 minutes, 4 events)</summary>",
            "| 4:10 | Opened Photo A: CR3, Canon EOS R5, 8192 × 5464, unedited, in 1.1 s |",
            "| 0:30 | Save failed: Couldn’t write “…/Photo A.redlamp” |",
            "<summary>System</summary>", "[diagnostics.json](attachment:diagnostics.json) has these details in full",
        ] {
            #expect(body.contains(line), "\(line)")
        }
        #expect(!body.contains("### The main thread"), "the main thread crashed, and is shown once")
        #expect(!body.contains("Photo Z"), "more than 15 minutes before")
        for secret in Self.secrets {
            #expect(!body.contains(secret), "the body contains \(secret)")
        }
        for part in ["### Screenshots", "Editor state", "Redlamp's log", "<summary>Photo</summary>"] {
            #expect(!body.contains(part), "this session's \(part)")
        }
    }

    @Test func `a crash on another thread shows it and the main thread, named where the Mac named them`() throws {
        var pending = try Self.crash()
        pending.incident.threads[0].crashed = false
        pending.incident.threads[2] = Incident.Thread(
            name: nil, queue: "app.redlamp.render", crashed: true,
            frames: [Incident.Frame(binary: 0, offset: 0x4448), Incident.Frame(binary: 1, offset: 0x1B4B0)],
        )
        let body = issue(sheet(pending).outgoing, pending)
        #expect(body.contains("### The crashed thread (thread 2, app.redlamp.render)"))
        #expect(body.contains("0  Redlamp" + String(repeating: " ", count: 12) + "0x4448"))
        #expect(body.contains("1  libdispatch.dylib  0x1b4b0"))
        #expect(body.contains("### The main thread (thread 0)"))
        let crashed = try #require(body.range(of: "### The crashed thread"))
        let main = try #require(body.range(of: "### The main thread"))
        #expect(crashed.lowerBound < main.lowerBound)
    }

    @Test func `a deep stack still fits GitHub's limit, shortened`() throws {
        var pending = try Self.crash()
        let frame = Incident.Frame(binary: 0, offset: 0x4448, symbol: String(repeating: "recursion ", count: 15))
        pending.incident.threads[0].frames = Array(repeating: frame, count: 512)
        pending.incident.threads[0].crashed = false
        pending.incident.threads[1] = Incident.Thread(crashed: true, frames: Array(repeating: frame, count: 512))
        let body = issue(sheet(pending).outgoing, pending)
        #expect(body.count <= FeedbackReport.bodyLimit)
        #expect(body.contains("more, in diagnostics.json"))
        #expect(body.contains("### The main thread (thread 0)"))
    }

    @Test func `a hang's issue says how long it lasted, and that Redlamp was closed during it`() {
        let pending = Self.hang(seconds: 14.2, closed: true, activity: [
            Self.event(-60, from: Self.hangBegan, .tool, "Tool: Masking"),
            Self.event(-5, from: Self.hangBegan, .mask, "Selected mask “Mask 1”: Objects"),
        ])
        let report = sheet(pending).outgoing
        #expect(report.issueTitle(context: FeedbackContext(reporting: pending))
            == "[Performance & Stability › Freezes] Hang: 14 s, then Redlamp was closed")
        let body = issue(report, pending)
        #expect(body.contains(#""incident":"hang""#) && body.contains(#""area":"performance.freeze""#))
        for line in [
            "Redlamp stopped responding.", "- **Not responding for:** 14 s, then Redlamp was closed",
            "- **Recorded by:** Redlamp's hang watchdog", "No thread's stack was recorded.",
            "<summary>What happened before the hang (last 15 minutes, 2 events)</summary>", "| 1:00 | Tool: Masking |",
        ] {
            #expect(body.contains(line), "\(line)")
        }
        #expect(!body.contains("### The crashed thread") && !body.contains("**Exception:**"))
        #expect(body.contains("has these details in full.\n"), "no stacks to symbolicate")
    }

    @Test func `a hang Redlamp came back from takes the activity up to its end`() {
        let pending = Self.hang(seconds: 12, closed: false, activity: [
            Self.event(-60, from: Self.hangBegan, .tool, "Tool: Masking"),
            Self.event(12.1, from: Self.hangBegan, .system, "Not responding for 12 s"),
            Self.event(300, from: Self.hangBegan, .edit, "Exposure: 0.00 → +0.50"),
        ])
        let body = issue(sheet(pending).outgoing, pending)
        #expect(body.contains("- **Not responding for:** 12 s, then it responded again"))
        #expect(body.contains("| 0:00 | Not responding for 12 s |"))
        #expect(!body.contains("Exposure"), "after the hang")
    }

    @Test func `what happened, the activity and the Mac can each be left out`() throws {
        let pending = try Self.crash()
        var report = sheet(pending).outgoing
        report.details.incident = false
        var body = issue(report, pending)
        #expect(!body.contains("### What happened") && !body.contains("EXC_BAD_ACCESS"))
        #expect(!body.contains("### The crashed thread"))
        #expect(body.contains("What happened before the crash"))
        var object = try #require(try diagnostics(report, pending))
        #expect(object["incident"] == nil && object["activity"] != nil)
        #expect(!report.isComplete, "without what happened, the person's words are needed")
        report.body = "I was opening a photo."
        #expect(report.isComplete)
        #expect(issue(report, pending).contains("### What I was doing\n\nI was opening a photo."))

        report.details.activity = false
        body = issue(report, pending)
        #expect(!body.contains("What happened before the crash"))
        object = try #require(try diagnostics(report, pending))
        #expect(object["activity"] == nil && object["system"] != nil)

        report.details.system = false
        body = issue(report, pending)
        #expect(!body.contains("<details>") && !body.contains("diagnostics.json"))
        #expect(body.contains("**From:** Redlamp 0.2.1-prealpha (412, 1a2b3c4d5e6f)\n"))
        #expect(try diagnostics(report, pending) == nil)
    }

    @Test func `a title the person changes is redacted with the session's photos and folders, always by alias`(
    ) throws {
        let pending = try Self.crash()
        var report = sheet(pending).outgoing
        report.title = "Crash opening IMG_0001.CR3 from /Users/someone/Pictures/Holiday, then "
            + "\(NSHomeDirectory())/Desktop/Edits"
        report.details.fileNames = true
        let title = report.issueTitle(context: FeedbackContext(reporting: pending))
        #expect(title == "[Performance & Stability › Crashes] Crash opening Photo A from a folder, then …/Edits")
        for secret in Self.secrets {
            #expect(!title.contains(secret), "the title contains \(secret)")
        }
    }

    // MARK: - diagnostics.json

    @Test func `diagnostics hold every thread and the binaries to symbolicate them, and the activity before it`(
    ) throws {
        let pending = try Self.crash()
        let report = sheet(pending).outgoing
        let data = try #require(try report.diagnostics(
            context: FeedbackContext(reporting: pending),
            system: FeedbackReportTests.system,
            log: [],
        ))
        let text = String(decoding: data, as: UTF8.self)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? String == "app.redlamp.feedback-diagnostics")
        #expect(object["area"] as? String == "performance.crash")
        #expect((object["activity"] as? [Any])?.count == 4, "the 15 minutes before the crash, as the switch says")
        for key in ["photo", "edit", "history", "state", "messages", "log", "sidecar", "photoNames"] {
            #expect(object[key] == nil, "\(key) is this session's")
        }
        let incident = try #require(object["incident"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let kept = try decoder.decode(Incident.self, from: JSONSerialization.data(withJSONObject: incident))
        #expect(kept.threads == pending.incident.threads)
        #expect(kept.threads.count == 4)
        #expect(kept.binaries == pending.incident.binaries)
        let binary = try #require(kept.binaries.first)
        #expect(binary.name == "Redlamp" && binary.uuid == "36C86B66-FBC5-32A1-8382-A6FE8E59D8B4")
        #expect(binary.base == 4_332_453_888 && binary.inApp)
        #expect(kept.reasons.contains("while reading …/Photo A"))
        for secret in Self.secrets {
            #expect(!text.contains(secret), "diagnostics.json contains \(secret)")
        }
    }

    // MARK: - The sheet and Your Reports

    @Test func `the sheet's crash mode is a bug titled for it, and leaves the person's other report alone`(
    ) async throws {
        let other = FeedbackSheetModel(
            context: FeedbackReportTests.context(), system: FeedbackReportTests.system, windowShot: nil,
            sender: Relay(), dryRun: false, defaults: defaults,
        )
        other.report.title = "Objects drop"
        other.report.body = "The first object goes."

        let relay = Relay()
        let pending = try Self.crash()
        let sheet = sheet(pending, relay: relay)
        #expect(sheet.report.kind == .bug && sheet.report.featureID == "performance.crash")
        #expect(sheet.report.title == "Crash: EXC_BAD_ACCESS (SIGSEGV) in Redlamp")
        #expect(sheet.report.body.isEmpty && !sheet.restoredDraft)
        #expect(!sheet.report.details.photo && !sheet.report.details.log && sheet.report.details.incident)
        sheet.acceptNote()
        #expect(sheet.canSend, "what happened says enough")
        sheet.report.body = "Opening a photo."
        await sheet.send()
        let sent = try #require(relay.sent.first)
        #expect(sent.labels == ["in-app", "bug", "component:performance"])
        #expect(sent.attachments.map(\.name) == ["diagnostics.json"])

        let again = FeedbackSheetModel(
            context: FeedbackReportTests.context(), system: FeedbackReportTests.system, windowShot: nil,
            sender: Relay(), dryRun: false, defaults: defaults,
        )
        #expect(again.restoredDraft && again.report.title == "Objects drop")
    }

    @Test func `after Not Now it stays in Your Reports, and sending or queueing its report takes it off`(
    ) async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = FeedbackHistory(directory: directory, defaults: defaults)
        let crash = try Self.crash()
        let hang = Self.hang(seconds: 14.2, closed: true)
        history.add([crash])
        history.add([hang])
        #expect(history.offeredIncident?.id == hang.id)
        history.dismiss(hang.id)
        #expect(history.offeredIncident?.id == crash.id)
        #expect(history.incidents.map(\.id) == [hang.id, crash.id], "Not Now keeps it listed")

        let sending = sheet(crash)
        sending.acceptNote()
        sending.onSent = { submission, result in
            if case let .filed(number, url) = result {
                history.record(submission, incident: crash.id, number: number, url: url)
            }
        }
        await sending.send()
        #expect(history.incidents.map(\.id) == [hang.id])
        #expect(history.reports.first?.number == 42)
        #expect(history.reports.first?.title
            == "[Performance & Stability › Crashes] Crash: EXC_BAD_ACCESS (SIGSEGV) in Redlamp")

        let offline = Relay()
        offline.result = .failure(.unreachable("The Internet connection appears to be offline."))
        let queueing = sheet(hang, relay: offline)
        queueing.acceptNote()
        await queueing.send()
        #expect(queueing.unreachable)
        queueing.onQueue = { history.enqueue($0, incident: hang.id) }
        queueing.queue()
        #expect(history.incidents.isEmpty && history.offeredIncident == nil)
        #expect(history.queued.first?.submission.title
            == "[Performance & Stability › Freezes] Hang: 14 s, then Redlamp was closed")
        let relaunched = FeedbackHistory(directory: directory, defaults: defaults)
        #expect(relaunched.incidents.isEmpty && relaunched.queued.count == 1 && relaunched.reports.count == 1)
    }

    // MARK: - The banner

    @Test func `the banner offers the first crash or hang not dismissed, in the module shown`() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = EditorModel(engine: StubEngine())
        let crash = try Self.crash()
        #expect(IncidentBanner.offered(model, in: .develop) == nil, "no history, as in tests")
        let history = FeedbackHistory(directory: directory, defaults: defaults)
        model.incidentHistory = history
        #expect(IncidentBanner.offered(model, in: .develop) == nil, "nothing found")
        history.add([crash])
        #expect(IncidentBanner.offered(model, in: .develop)?.id == crash.id)
        #expect(IncidentBanner.offered(model, in: .library) == nil, "Develop is shown")
        model.module = .library
        #expect(IncidentBanner.offered(model, in: .library)?.id == crash.id)
        #expect(IncidentBanner.offered(model, in: .develop) == nil, "the Library covers Develop's")
        model.cullingProblem = CullingProblem(
            title: "3 Stars", field: .rating, photos: [], values: [], reasons: [], step: ObjectIdentifier(model),
        )
        #expect(IncidentBanner.offered(model, in: .library) == nil, "the culling problem is in its place")
        model.cullingProblem = nil
        history.dismiss(crash.id)
        #expect(IncidentBanner.offered(model, in: .library) == nil, "Not Now")
    }

    @Test func `the banner says when, and a hang's how long`() throws {
        let read = ". You can read the report before you send it."
        #expect(try IncidentBanner.detail(Self.crash().incident).hasSuffix(read))
        #expect(IncidentBanner.detail(Self.hang(seconds: 14.2, closed: true).incident).hasSuffix(", for 14 s" + read))
    }

    @Test func `a failed save's banner shows in the module shown, and in the Library the crash waits for it`() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = EditorModel(engine: StubEngine())
        let crash = try Self.crash()
        let history = FeedbackHistory(directory: directory, defaults: defaults)
        model.incidentHistory = history
        history.add([crash])
        let error = SaveError(
            url: URL(fileURLWithPath: "/tmp/IMG_0001.ARW"),
            message: "Edits to IMG_0001 can't be saved: the disk is full",
            canRetry: true,
        )
        model.saveError = error
        #expect(SaveErrorBanner.shown(model, in: .develop) == error)
        #expect(IncidentBanner.offered(model, in: .develop)?.id == crash.id, "below it in Develop")
        #expect(SaveErrorBanner.shown(model, in: .library) == nil, "Develop is shown")
        model.module = .library
        #expect(SaveErrorBanner.shown(model, in: .library) == error)
        #expect(SaveErrorBanner.shown(model, in: .develop) == nil, "the Library covers Develop's")
        #expect(IncidentBanner.offered(model, in: .library) == nil, "the failed save is in its place")
        model.saveError = nil
        #expect(IncidentBanner.offered(model, in: .library)?.id == crash.id)
    }

    @Test func `over the Library's photos, a failed save's banner is on top and a culling problem moves below it`(
    ) async throws {
        let fixture = ModuleFixture()
        defer { fixture.cleanUp() }
        try await fixture.open(count: 2)
        let model = fixture.model
        let modules = fixture.showModules()
        model.showLibrary(.grid)
        model.cullingProblem = CullingProblem(
            title: "3 Stars", field: .rating, photos: [fixture.photos[1]], values: [], reasons: ["permission denied"],
            step: ObjectIdentifier(model),
        )
        func frame(_ identifier: String) -> NSRect? {
            func search(_ view: NSView) -> NSView? {
                guard !view.isHidden else { return nil }
                return view.accessibilityIdentifier() == identifier ? view : view.subviews.lazy.compactMap(search).first
            }
            modules.window.layoutIfNeeded()
            return search(modules.content.library).map { $0.convert($0.bounds, to: nil) }
        }
        try await fixture.eventually { frame("library.cullingProblem") != nil }
        let alone = try #require(frame("library.cullingProblem"))

        model.saveError = SaveError(
            url: fixture.photos[0], message: "Edits to IMG_00000 can't be saved: the disk is full", canRetry: true,
        )
        try await fixture.eventually {
            frame("saving.banner.retry") != nil && frame("library.cullingProblem").map { $0.maxY < alone.minY } == true
        }
        let banner = try #require(frame("saving.banner"))
        let problem = try #require(frame("library.cullingProblem"))
        #expect(banner.minY > problem.maxY, "the failed save on top, the culling problem below it")
        #expect(abs(banner.maxY - alone.maxY) < 1, "in the culling problem's place")

        model.saveError = nil
        try await fixture.eventually { frame("saving.banner") == nil && frame("library.cullingProblem") == alone }
        #expect(frame("library.cullingProblem") == alone, "back in its place")
    }
}
