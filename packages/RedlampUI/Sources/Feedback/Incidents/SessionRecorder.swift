import Foundation
import Synchronization

/// This session's record for the next launch, and what the sessions before it left to report.
/// Started as the app finishes launching, it opens the session's journal for the activity log,
/// watches for hangs, takes MetricKit's diagnostics and runs the launch check, whose crashes and
/// hangs go to Your Reports. Stopped as the app quits, it writes the journal's last line.
@MainActor
public final class SessionRecorder {
    /// Development builds offer reports only with this set, as the regression suite sets it:
    /// Xcode's Stop button and the suite end them without quitting.
    public static let offersInDevelopmentKey = "feedback.offersIncidentReports"

    /// MetricKit's diagnostics as they arrive, for the launch check.
    private final class Inbox: Sendable {
        let incidents = Mutex<[Incident]>([])
    }

    public let journal: SessionJournal?
    /// Whether what the launch check finds is kept and offered to report: in Release builds, and in development builds
    /// with `offersInDevelopmentKey`.
    public let offers: Bool
    private let activity: ActivityLog
    private let history: FeedbackHistory
    private let setting: ActivityLogSetting
    private let folder: URL
    private let inbox = Inbox()
    private var watchdog: HangWatchdog?
    private var metricKit: MetricKitDiagnostics?

    public convenience init(
        activity: ActivityLog, history: FeedbackHistory = .shared, setting: ActivityLogSetting = .shared,
        development: Bool, defaults: UserDefaults = .standard,
    ) {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let header = SessionJournal.Header.current(
            bundleID: Bundle.main.bundleIdentifier ?? "app.redlamp.mac", version: version, development: development,
        )
        self.init(
            journal: header.flatMap { try? SessionJournal(header: $0) }, activity: activity, history: history,
            setting: setting, offers: !development || defaults.bool(forKey: Self.offersInDevelopmentKey),
        )
    }

    /// One keeping `journal`, kept in `folder`, as a test makes one.
    init(
        journal: SessionJournal?, activity: ActivityLog, history: FeedbackHistory, setting: ActivityLogSetting,
        offers: Bool, folder: URL = SessionJournal.folder,
    ) {
        self.journal = journal
        self.activity = activity
        self.history = history
        self.setting = setting
        self.folder = folder
        self.offers = offers
        setting.onChange { [weak self] isOn in
            if !isOn {
                self?.forgetActivity()
            }
        }
    }

    /// As the activity log is turned off: the journals of sessions that have ended, which the launch check would read,
    /// are deleted, and the crashes and hangs not reported yet lose their activity. This session's journal forgets
    /// its own as the log does.
    func forgetActivity() {
        activity.isOn = false
        for session in PreviousSession.ended(in: folder) {
            session.remove()
        }
        history.forgetActivity()
    }

    public func start() {
        activity.journal = journal
        let journal = journal
        let activity = activity
        let watchdog = HangWatchdog { hang in
            journal?.hang(hang)
            if hang.ended {
                Task { @MainActor in
                    activity.record(.system, "Not responding for \(Incident.seconds(hang.duration))")
                }
            }
        }
        watchdog.start()
        self.watchdog = watchdog
        guard let header = journal?.header else { return }
        let inbox = inbox
        let metricKit = MetricKitDiagnostics(bundleID: header.bundleID, appBinaries: Self.appBinaries) { incidents in
            inbox.incidents.withLock { $0 += incidents }
        }
        metricKit.start()
        self.metricKit = metricKit
        Task.detached(priority: .utility) { [weak self] in
            let found = await IncidentCheck.run(header: header, diagnostics: { inbox.incidents.withLock { $0 } })
            await self?.found(found)
        }
    }

    /// Stops watching for hangs, as the app begins to quit.
    public func stop() {
        watchdog?.stop()
    }

    /// The session has quit: the journal's last line.
    public func quit() {
        journal?.quit()
    }

    func found(_ incidents: [PendingIncident]) {
        guard offers, !incidents.isEmpty else { return }
        history.add(setting.isOn ? incidents : incidents.map(\.withoutActivity))
    }

    /// The names of Redlamp's own executables and frameworks, whose frames the release's dSYMs name.
    nonisolated static var appBinaries: Set<String> {
        let bundle = Bundle.main
        let folders = [bundle.executableURL?.deletingLastPathComponent(), bundle.privateFrameworksURL]
        let names = folders.compactMap(\.self).flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .map { ($0 as NSString).deletingPathExtension }
        }
        return Set(names)
    }
}
