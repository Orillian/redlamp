import Foundation
import Testing
@testable import RedlampUI

/// What the next launch offers for each way a session can end: a crash, a hang it ended in, a
/// long hang it came back from, and nothing for a Force Quit of a Redlamp that was responding or
/// for the Mac restarting.
struct IncidentCheckTests {
    static let header = SessionJournalTests.header
    static let began = header.started + 600

    static func session(quit: Bool, hangs: [SessionJournal.Hang] = []) -> PreviousSession {
        PreviousSession(
            url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).jsonl"), header: header,
            events: [ActivityLog.Event(time: began - 5, kind: .action, text: "Auto", key: nil)],
            photos: [], folders: [], hangs: hangs, quit: quit ? header.started + 3600 : nil, lastWritten: nil,
        )
    }

    static func hang(_ duration: TimeInterval, ended: Bool, after: TimeInterval = 0) -> SessionJournal.Hang {
        SessionJournal.Hang(began: began + after, duration: duration, ended: ended)
    }

    @Test func `a crash is offered as its reports have it`() throws {
        let crash = try IncidentTests.crashReport()
        let incident = try #require(IncidentCheck.incident(
            for: Self.session(quit: false), crash: crash, booted: Self.header.booted,
        ))
        #expect(incident.kind == .crash)
        #expect(incident.suggestedTitle == "Crash: EXC_BAD_ACCESS (SIGSEGV) in Redlamp")
    }

    @Test func `a session that ended in a hang offers it, unless the Mac restarted`() throws {
        let stuck = Self.session(
            quit: false,
            hangs: [Self.hang(3, ended: true, after: -60), Self.hang(14.2, ended: false)],
        )
        let incident = try #require(IncidentCheck.incident(for: stuck, crash: nil, booted: Self.header.booted))
        #expect(incident.kind == .hang)
        #expect(incident.endedSession)
        #expect(incident.duration == 14.2)
        #expect(incident.time == Self.began)
        #expect(incident.version == "0.3.2-alpha (431)")
        #expect(incident.suggestedTitle == "Hang: 14 s, then Redlamp was closed")

        let restarted = Self.header.booted + 7200
        #expect(IncidentCheck.incident(
            for: Self.session(quit: false, hangs: [Self.hang(4, ended: false)]), crash: nil, booted: restarted,
        ) == nil)
        let long = try #require(IncidentCheck.incident(for: stuck, crash: nil, booted: restarted))
        #expect(!long.endedSession, "a hang of 10 s or more is still offered, as one Redlamp had")
    }

    @Test func `a Force Quit of a Redlamp that was responding offers nothing`() {
        #expect(IncidentCheck.incident(for: Self.session(quit: false), crash: nil, booted: Self.header.booted) == nil)
        #expect(IncidentCheck.incident(
            for: Self.session(quit: false, hangs: [Self.hang(3, ended: true)]), crash: nil, booted: Self.header.booted,
        ) == nil)
    }

    @Test func `the longest hang of 10 s or more is offered after a quit`() throws {
        let hangs = [
            Self.hang(3, ended: true),
            Self.hang(12, ended: true, after: 60),
            Self.hang(11, ended: true, after: 120),
        ]
        let incident = try #require(IncidentCheck.incident(
            for: Self.session(quit: true, hangs: hangs), crash: nil, booted: Self.header.booted,
        ))
        #expect(incident.duration == 12)
        #expect(!incident.endedSession)
        #expect(incident.suggestedTitle == "Hang: 12 s")
        #expect(IncidentCheck.incident(
            for: Self.session(quit: true, hangs: [Self.hang(9, ended: true)]), crash: nil, booted: Self.header.booted,
        ) == nil)
    }

    @Test func `MetricKit's stacks join the watchdog's hang`() throws {
        let data = try Data(contentsOf: IncidentTests.folder.appending(path: "metrickit-crash.json"))
        let stacks = try #require(Incident(
            metricKit: data,
            kind: .hang,
            time: Self.began,
            duration: 13,
            appBinaries: ["Redlamp"],
        ))
        let incident = try #require(IncidentCheck.incident(
            for: Self.session(quit: true, hangs: [Self.hang(14, ended: true)]), crash: nil, diagnostics: [stacks],
            booted: Self.header.booted,
        ))
        #expect(incident.sources == [.watchdog, .metricKit])
        #expect(incident.duration == 14)
        #expect(!incident.threads.isEmpty)
    }

    @Test func `the launch reads its own build's ended sessions, finds their crashes and removes them`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "check-\(UUID().uuidString)")
        let folder = root.appending(path: "Session")
        let reports = root.appending(path: "DiagnosticReports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(contentsOf: IncidentTests.folder.appending(path: "crash.ips"))
            .write(to: reports.appending(path: "Redlamp-2026-10-14-100811.ips"))

        let crashed = try SessionJournal(header: Self.header, folder: folder)
        crashed.record(ActivityLog.Event(time: Self.began, kind: .action, text: "Auto", key: nil), seq: 0)
        var quitHeader = Self.header
        quitHeader.pid = 4300
        let quit = try SessionJournal(header: quitHeader, folder: folder)
        quit.quit()
        var developmentHeader = Self.header
        developmentHeader.development = true
        let development = try SessionJournal(header: developmentHeader, folder: folder)

        let found = await IncidentCheck.run(
            header: Self.header, folder: folder, reports: reports, diagnostics: { [] }, wait: .zero,
        )
        #expect(found.map(\.incident.kind) == [.crash])
        #expect(found.first?.activity.map(\.text) == ["Auto"])
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(left == [development.url.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: crashed.url.path))
        #expect(!FileManager.default.fileExists(atPath: quit.url.path))
    }
}
