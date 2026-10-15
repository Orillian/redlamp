import Foundation

/// A crash or a hang found at launch, with what its session was doing, kept until it's reported or
/// 30 days have passed.
public struct PendingIncident: Codable, Sendable, Hashable, Identifiable {
    public var incident: Incident
    /// The session's activity, oldest first.
    public var activity: [ActivityLog.Event]
    /// The session's photos and folders, to redact the report with.
    public var photos: [PhotoName]
    public var folders: [String]
    /// When the launch found it.
    public var found: Date
    /// Not Now: it stays in Your Reports, and the banner doesn't show it again.
    public var dismissed = false

    public var id: UUID {
        incident.id
    }

    public init(incident: Incident, session: PreviousSession, found: Date) {
        self.init(
            incident: incident, activity: session.events, photos: session.photos, folders: session.folders,
            found: found,
        )
    }

    /// One whose session is given by what it did, as a test or a scenario makes one up.
    @_spi(Harness) public init(
        incident: Incident, activity: [ActivityLog.Event] = [], photos: [PhotoName] = [], folders: [String] = [],
        found: Date,
    ) {
        self.incident = incident
        self.activity = activity
        self.photos = photos
        self.folders = folders
        self.found = found
    }

    /// It, as the activity log turned off leaves it: no activity. Its photos and folders stay, since they only take
    /// names and paths out of what macOS or MetricKit wrote about it before a report is sent.
    public var withoutActivity: PendingIncident {
        var pending = self
        pending.activity = []
        return pending
    }
}

/// What a session that has ended leaves to report: its crash, from macOS's crash report or
/// MetricKit's; the hang it ended in, as one does when a stuck Redlamp is force quit; or the
/// longest hang of 10 s or more it had. A Force Quit of a Redlamp that was responding leaves
/// nothing, nor does the Mac restarting during a session, as a power cut or a panic makes it: the
/// person knows why it ended.
public enum IncidentCheck {
    /// A hang Redlamp came back from is offered from this long.
    public static let reportedHang: TimeInterval = 10
    /// How long a session that ended without quitting waits for its crash's reports: macOS writes
    /// its own about 3 s after the crash, and MetricKit sent its within a second of the next launch.
    public static let crashWait = Duration.seconds(6)

    /// `crash`: the session's, from either report. `diagnostics`: MetricKit's so far, which can
    /// hold a hang's stacks. `booted`: when the Mac last started up.
    public static func incident(
        for session: PreviousSession, crash: Incident?, diagnostics: [Incident] = [], booted: Date,
    ) -> Incident? {
        var incident: Incident
        let restarted = booted.timeIntervalSince(session.header.booted) > 1
        if let crash {
            incident = crash
        } else if session.quit == nil, !restarted, let hang = session.openHang {
            incident = Incident(kind: .hang, time: hang.began, pid: session.header.pid, sources: [.watchdog])
            incident.duration = hang.duration
            incident.endedSession = true
        } else if let hang = session.hangs.filter({ $0.duration >= reportedHang })
            .max(by: { $0.duration < $1.duration }) {
            incident = Incident(kind: .hang, time: hang.began, pid: session.header.pid, sources: [.watchdog])
            incident.duration = hang.duration
        } else {
            return nil
        }
        if incident.kind == .hang,
           let stacks = diagnostics.first(where: { $0.kind == .hang && $0.pid == session.header.pid }) {
            incident = incident.merged(with: stacks)
        }
        incident.version = incident.version ?? session.header.version
        return incident
    }

    /// The session's crash, from its crash report merged with MetricKit's diagnostic.
    static func crash(for session: PreviousSession, reports: URL, diagnostics: [Incident]) -> Incident? {
        let header = session.header
        let report = MacCrashReport.find(pid: header.pid, bundleID: header.bundleID, since: header.started, in: reports)
        let metricKit = diagnostics.first { $0.kind == .crash && $0.pid == header.pid && $0.time >= header.started }
        switch (report, metricKit) {
        case let (report?, metricKit?): return report.merged(with: metricKit)
        case let (report?, nil): return report
        case let (nil, metricKit?): return metricKit
        case (nil, nil): return nil
        }
    }

    /// Reads the sessions of this build of the app that have ended, and what each leaves to
    /// report, then removes their journals. One that ended without quitting, and has no crash
    /// report yet, waits `wait` for one. `diagnostics` gives MetricKit's so far.
    public static func run(
        header: SessionJournal.Header, folder: URL = SessionJournal.folder, reports: URL = MacCrashReport.folder,
        diagnostics: @Sendable () -> [Incident], wait: Duration = crashWait, now: Date = Date(),
    ) async -> [PendingIncident] {
        let sessions = PreviousSession.ended(in: folder).filter {
            $0.header.bundleID == header.bundleID && $0.header.development == header.development
        }
        var found: [PendingIncident] = []
        var waiting: [PreviousSession] = []
        for session in sessions {
            let crash = crash(for: session, reports: reports, diagnostics: diagnostics())
            if crash == nil, session.quit == nil {
                waiting.append(session)
                continue
            }
            if let incident = incident(for: session, crash: crash, diagnostics: diagnostics(), booted: header.booted) {
                found.append(PendingIncident(incident: incident, session: session, found: now))
            }
            session.remove()
        }
        if !waiting.isEmpty {
            try? await Task.sleep(for: wait)
        }
        for session in waiting {
            let crash = crash(for: session, reports: reports, diagnostics: diagnostics())
            if let incident = incident(for: session, crash: crash, diagnostics: diagnostics(), booted: header.booted) {
                found.append(PendingIncident(incident: incident, session: session, found: now))
            }
            session.remove()
        }
        return found
    }
}
