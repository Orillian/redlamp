import Foundation
import Testing
@_spi(Harness) @testable import RedlampUI

/// Settings › Privacy's activity log (UX-52): on unless turned off; off, nothing is recorded, what was kept is deleted
/// from memory, from this session's journal, from the journals of sessions that have ended and from crashes not
/// reported yet, and a report sends no activity and says so.
@MainActor
struct ActivityLogSettingTests {
    private final class Relay: FeedbackSending, @unchecked Sendable {
        func send(_: FeedbackSubmission) async throws -> FeedbackResult {
            .dryRun(title: "", body: "", labels: [])
        }
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_791_960_100)
    }

    private let defaults = UserDefaults(suiteName: "ActivityLogSettingTests-\(UUID().uuidString)")!
    private let folder = FileManager.default.temporaryDirectory
        .appending(path: "ActivityLogSettingTests-\(UUID().uuidString)")

    /// A journal in `folder` for this session, which is running.
    private func journal() throws -> SessionJournal {
        let header = try #require(SessionJournal.Header.current(
            bundleID: "app.redlamp.mac", version: "0.3.2-alpha (431)", development: false,
        ))
        return try SessionJournal(header: header, folder: folder)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - The setting

    @Test func `the setting is on unless turned off, and keeps its choice`() {
        #expect(ActivityLogSetting(defaults: defaults).isOn)
        let setting = ActivityLogSetting(defaults: defaults)
        var heard: [Bool] = []
        setting.onChange { heard.append($0) }
        setting.isOn = false
        setting.isOn = false
        #expect(heard == [false])
        #expect(defaults.object(forKey: ActivityLogSetting.defaultsKey) as? Bool == false)
        #expect(!ActivityLogSetting(defaults: defaults).isOn)
        setting.isOn = true
        #expect(heard == [false, true])
        #expect(ActivityLogSetting(defaults: defaults).isOn)
    }

    @Test func `a log following the setting starts as it is and is turned on and off with it`() {
        let setting = ActivityLogSetting(defaults: defaults)
        setting.isOn = false
        let log = ActivityLog(following: setting)
        log.record(.system, "Redlamp started")
        #expect(!log.isOn && log.events.isEmpty)
        setting.isOn = true
        log.record(.action, "Auto")
        #expect(log.isOn && log.events.map(\.text) == ["Auto"])
        setting.isOn = false
        #expect(!log.isOn && log.events.isEmpty)
    }

    // MARK: - The log and its journal

    @Test func `turned off, the log forgets its activity and its journal keeps only what tells a crash`() throws {
        defer { cleanUp() }
        let clock = Clock()
        let log = ActivityLog { clock.now }
        let journal = try journal()
        log.journal = journal
        log.folders = ["/Users/someone/Pictures/Holiday"]
        let alias = log.alias(for: URL(fileURLWithPath: "/Users/someone/Pictures/Holiday/IMG_0001.CR3"))
        log.record(.photo, "Opened \(alias)")
        log.record(.edit, "Exposure: 0.00 → +0.50")
        let hang = SessionJournal.Hang(began: clock.now, duration: 12, ended: true)
        journal.hang(hang)

        log.isOn = false
        #expect(log.events.isEmpty)
        let forgotten = try #require(PreviousSession.read(journal.url))
        #expect(forgotten.header == journal.header)
        #expect(forgotten.events.isEmpty && forgotten.photos.isEmpty && forgotten.folders.isEmpty)
        #expect(forgotten.hangs == [hang])
        let text = try String(contentsOf: journal.url, encoding: .utf8)
        for left in ["IMG_0001", "Holiday", "Exposure", "Photo A"] {
            #expect(!text.contains(left), "The journal still holds \(left)")
        }

        // Nothing new is written while it's off, though photos still get the aliases a report names them by.
        clock.now += 5
        log.record(.action, "Auto")
        #expect(log.alias(for: URL(fileURLWithPath: "/Users/someone/Pictures/Holiday/IMG_0002.CR3")) == "Photo B")
        log.folders = ["/Users/someone/Pictures/Lisbon"]
        journal.quit(at: clock.now)
        let off = try #require(PreviousSession.read(journal.url))
        #expect(log.events.isEmpty)
        #expect(off.events.isEmpty && off.photos.isEmpty && off.folders.isEmpty)
        #expect(off.hangs == [hang] && off.quit == clock.now)
    }

    @Test func `turned back on, it records again and tells the journal its photos and folders`() throws {
        defer { cleanUp() }
        let log = ActivityLog(isOn: false)
        let journal = try journal()
        log.journal = journal
        _ = log.alias(for: URL(fileURLWithPath: "/Users/someone/Pictures/Holiday/IMG_0001.CR3"))
        log.folders = ["/Users/someone/Pictures/Holiday"]
        log.record(.action, "Auto")
        #expect(try #require(PreviousSession.read(journal.url)).photos.isEmpty)

        log.isOn = true
        log.record(.action, "Reset")
        let session = try #require(PreviousSession.read(journal.url))
        #expect(log.events.map(\.text) == ["Reset"])
        #expect(session.events.map(\.text) == ["Reset"])
        #expect(session.photos == [PhotoName(alias: "Photo A", fileName: "IMG_0001.CR3")])
        #expect(session.folders == ["/Users/someone/Pictures/Holiday"])
    }

    // MARK: - What earlier sessions left

    @Test func `turning it off deletes ended sessions' journals and the activity of crashes not reported yet`() throws {
        defer { cleanUp() }
        let setting = ActivityLogSetting(defaults: defaults)
        let log = ActivityLog(following: setting)
        let history = FeedbackHistory(directory: folder.appending(path: "history"), defaults: defaults)
        let current = try journal()
        // Without start(), whose launch check would read the Mac's own journals.
        let recorder = SessionRecorder(
            journal: current, activity: log, history: history, setting: setting, offers: true, folder: folder,
        )
        log.journal = current
        log.record(.action, "Auto")

        // A session that ended without quitting, whose journal the launch check hasn't read yet.
        let ended = try EndedSession.leave(in: folder)
        let pending = IncidentReportTests.hang(seconds: 14, closed: true, activity: [
            IncidentReportTests.event(-60, from: IncidentReportTests.hangBegan, .edit, "Contrast: 0 → +20"),
        ])
        var named = pending
        named.photos = [PhotoName(alias: "Photo A", fileName: "IMG_0001.CR3")]
        history.add([named])

        setting.isOn = false
        #expect(!FileManager.default.fileExists(atPath: ended.path))
        #expect(FileManager.default.fileExists(atPath: current.url.path))
        #expect(try #require(PreviousSession.read(current.url)).events.isEmpty)
        #expect(history.incidents.map(\.activity) == [[]])
        #expect(history.incidents.first?.photos == named.photos)
        // Read back as of when the hang was found: a history leaves out incidents found 30 days or more before.
        let reread = FeedbackHistory(directory: folder.appending(path: "history"), defaults: defaults) { pending.found }
        #expect(reread.incidents.map(\.activity) == [[]])
        withExtendedLifetime(recorder) {}
    }

    @Test func `with it off, a crash the launch check finds keeps no activity`() {
        defer { cleanUp() }
        let setting = ActivityLogSetting(defaults: defaults)
        setting.isOn = false
        let history = FeedbackHistory(directory: folder, defaults: defaults)
        let recorder = SessionRecorder(
            journal: nil, activity: ActivityLog(following: setting), history: history, setting: setting, offers: true,
            folder: folder,
        )
        recorder.found([IncidentReportTests.hang(seconds: 14, closed: true, activity: [
            IncidentReportTests.event(-60, from: IncidentReportTests.hangBegan, .edit, "Contrast: 0 → +20"),
        ])])
        #expect(history.incidents.count == 1)
        #expect(history.incidents.first?.activity.isEmpty == true)
    }

    // MARK: - Reports

    @Test func `with it off, a report sends no activity and says the log is off`() throws {
        var context = FeedbackReportTests.context()
        #expect(!context.activity.isEmpty)
        context = FeedbackContext(
            captured: context.captured, photo: context.photo, edit: context.edit, state: context.state,
            messages: context.messages, history: context.history, historyIndex: context.historyIndex,
            activity: context.activity, activityLog: false, photos: context.photos, folders: context.folders,
            sidecar: context.sidecar, suggestion: context.suggestion,
        )
        #expect(context.activity.isEmpty)
        let sheet = FeedbackSheetModel(
            context: context, system: FeedbackReportTests.system, windowShot: nil, sender: Relay(), dryRun: true,
            defaults: defaults,
        )
        #expect(sheet.report.details.activity)
        let report = sheet.outgoing
        let body = report.issueBody(context: context, system: FeedbackReportTests.system, log: [])
        #expect(!body.contains("What happened before"))
        #expect(!body.contains("Exposure: 0.00 → +0.50 |"))
        #expect(body.contains("| Activity log | Off, so no activity is included |"))
        #expect(body.contains("<summary>Editor state</summary>"))
        let data = try #require(try report.diagnostics(context: context, system: FeedbackReportTests.system, log: []))
        let diagnostics = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(diagnostics["activity"] == nil)
        #expect(diagnostics["state"] != nil)
    }

    @Test func `with it on, a report's editor state doesn't mention the log`() {
        let context = FeedbackReportTests.context()
        let body = FeedbackReportTests.report().issueBody(context: context, system: FeedbackReportTests.system, log: [])
        #expect(body.contains("What happened before"))
        #expect(!body.contains("Activity log"))
    }

    @Test func `with it off, a crash's report sends none of its session's activity`() throws {
        let pending = IncidentReportTests.hang(seconds: 14, closed: true, activity: [
            IncidentReportTests.event(-60, from: IncidentReportTests.hangBegan, .edit, "Contrast: 0 → +20"),
        ])
        let context = FeedbackContext(reporting: pending, activityLog: false)
        let sheet = FeedbackSheetModel(
            context: context, system: FeedbackReportTests.system, windowShot: nil,
            prefill: FeedbackPrefill(incident: pending), sender: Relay(), dryRun: true, defaults: defaults,
        )
        #expect(!sheet.report.details.activity)
        #expect(sheet.report.incident?.activity.isEmpty == true)
        let report = sheet.outgoing
        let body = report.issueBody(context: context, system: FeedbackReportTests.system, log: [])
        #expect(!body.contains("What happened before"))
        #expect(!body.contains("Contrast"))
        let data = try #require(try report.diagnostics(context: context, system: FeedbackReportTests.system, log: []))
        let diagnostics = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(diagnostics["activity"] == nil)
        #expect(diagnostics["incident"] != nil)
    }
}

/// Leaves a journal as an earlier session's that ended without quitting, with its activity.
private enum EndedSession {
    @MainActor static func leave(in folder: URL) throws -> URL {
        let header = SessionJournal.Header(
            pid: 4242, started: Date(timeIntervalSince1970: 1_791_960_000), bundleID: "app.redlamp.mac",
            version: "0.3.2-alpha (431)", development: false, booted: Date(timeIntervalSince1970: 1_791_950_000),
        )
        let journal = try SessionJournal(header: header, folder: folder)
        let log = ActivityLog()
        log.journal = journal
        log.folders = ["/Users/someone/Pictures/Holiday"]
        log.record(.photo, "Opened \(log.alias(for: URL(fileURLWithPath: "/Users/someone/Pictures/Holiday/A.CR3")))")
        return journal.url
    }
}
