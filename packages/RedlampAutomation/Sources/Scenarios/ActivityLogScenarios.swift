#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import Foundation
    @_spi(Harness) import RedlampUI
    import Synchronization

    extension FeedbackScenarios {
        /// UX-52: Settings › Privacy's activity log, for App Review's guideline 2.5.14.
        static let activityLogOff = Scenario(
            "feedback.activity-log-off",
            "Settings › Privacy turns the activity log off: the log and the session's journal forget what they held "
                + "and record nothing, Report a Bug says the log is off, and a report to the stub relay holds no "
                + "activity; turned back on, it records again",
            claims: [.feature("workspace.settings")],
        ) { app in
            let toggle = "settings.privacy.activity-log"
            defer { try? app.main { _ in ActivityLogSetting.shared.isOn = true } }
            try app.openWorking()
            try app.waitForCanvas()

            /// What the session's journal holds now, as the next launch would read it.
            @MainActor func journaled(_ model: EditorModel) -> PreviousSession? {
                model.activity.journal.flatMap { PreviousSession.read($0.url) }
            }
            let before = try app.main { model in (model.activity.isOn, model.activity.events.count, journaled(model)) }
            try app.expect(
                before.0 && before.1 > 0,
                "The activity log is \(before.0 ? "on" : "off") with \(before.1) events",
            )
            guard let journal = before.2 else {
                throw ScenarioFailure("This session keeps no journal, so there's nothing for the setting to delete")
            }
            try app.expect(
                !journal.events.isEmpty && !journal.photos.isEmpty,
                "The journal holds \(journal.events.count) events and \(journal.photos.count) photos before",
            )

            /// Turns the switch in Settings › Privacy, or on macOS 27, where SwiftUI draws it (UX-44), the setting.
            func turn(_ on: Bool) throws {
                app.step("Settings › Privacy › Keep an activity log \(on ? "on" : "off")")
                try app.openSettings(tab: "Privacy")
                if app.settingsControlsDrawnBySwiftUI {
                    try app.main { _ in ActivityLogSetting.shared.isOn = on }
                } else {
                    try app.expect(try app.isOn(toggle, inWindowTitled: "Privacy") == !on, "The switch isn't \(!on)")
                    try app.clickInSettings(toggle, fallback: 0)
                }
                try app.wait("the activity log \(on ? "on" : "off")") { model in
                    ActivityLogSetting.shared.isOn == on && model.activity.isOn == on
                }
                try app.closeSettings()
            }

            try turn(false)
            try app.wait("the log and the journal to forget what they held") { model in
                guard model.activity.events.isEmpty, let session = journaled(model) else { return false }
                return session.events.isEmpty && session.photos.isEmpty && session.folders.isEmpty
                    && session.header == journal.header
            }
            let saved = try app
                .main { _ in UserDefaults.standard.object(forKey: ActivityLogSetting.defaultsKey) as? Bool }
            try app.expect(saved == false, "The setting saved is \(String(describing: saved))")
            app.covered(.feature("workspace.settings"), via: app.settingsControlsDrawnBySwiftUI ? .model : .mouse)

            app.step("nothing new is recorded")
            try app.main { $0.activeTool = .masking }
            app.pause(0.5)
            try app.main { $0.activeTool = .edit }
            app.pause(0.5)
            let off = try app.main { model in (model.activity.events.map(\.text), journaled(model)) }
            try app.expect(off.0.isEmpty, "The log recorded \(off.0) while off")
            try app.expect(
                off.1.map { $0.events.isEmpty && $0.photos.isEmpty && $0.folders.isEmpty } == true,
                "The journal was written while off: \(off.1.map { "\($0.events.map(\.text)), \($0.photos)" } ?? "")",
            )

            app.step("Report a Bug says the log is off")
            // The driver sees an action reach the editor in the activity log, which is off.
            try app.choose(.sendFeedback, expectPerformed: false)
            try app.waitForSheet("Report a Bug")
            if try !app.main({ _ in IncidentScenarios.inSheet("feedback.send") }) {
                // The note asking people to be kind, the first time: Continue.
                _ = try app.pressInSheet(KeyCombo(.character("\r")))
            }
            try app.wait("the report's details to say the activity log is off") { _ in
                IncidentScenarios.inSheet("feedback.activity-log.off")
                    && !IncidentScenarios.inSheet("feedback.activity-log.on")
            }
            try app.pressInSheet(KeyCombo(.escape))
            try app.waitForNoSheet("Report a Bug")

            app.step("a report sent to the stub relay")
            let relay = app.runDirectory.appending(path: "relay")
            let sentBefore = Set((try? FileManager.default.contentsOfDirectory(atPath: relay.path)) ?? [])
            let offered = OfferedActivity()
            try app.run("a report sent with the activity log off", timeout: 60) { model in
                let sheet = await FeedbackActions.makeSheet(model: model)
                offered.set(log: sheet.context.activityLog, events: sheet.context.activity.count)
                var report = sheet.report
                report.title = "Regression suite: a report with the activity log off"
                report.body = "Sent by the regression suite to its own relay."
                report.featureID = "workspace.settings"
                report.details.activity = true
                sheet.report = report
                await sheet.send()
            }
            try app.expect(
                offered.log == false && offered.events == 0,
                "The report's sheet had the log \(offered.log == true ? "on" : "off") with \(offered.events) events",
            )
            try app.wait("the relay to get the report", timeout: 20) { _ in
                Set((try? FileManager.default.contentsOfDirectory(atPath: relay.path)) ?? []).count > sentBefore.count
            }
            let latest = try Set(FileManager.default.contentsOfDirectory(atPath: relay.path)).subtracting(sentBefore)
                .sorted().last
            guard let latest else { throw ScenarioFailure("The relay's report went away") }
            let sent = try IncidentScenarios.Sent(relay.appending(path: latest))
            try app.expect(
                sent.attachments == [FeedbackReport.diagnosticsName],
                "The report came with \(sent.attachments)",
            )
            try app.expect(
                sent.diagnostics["activity"] == nil && sent.diagnostics["state"] != nil,
                "diagnostics.json holds \(sent.diagnostics.keys.sorted())",
            )
            try app.expect(
                sent.body.contains("| Activity log | Off, so no activity is included |")
                    && !sent.body.contains("What happened before"),
                "The issue doesn't say the activity log is off, or holds activity:\n\(sent.body)",
            )

            try turn(true)
            app.step("recorded again")
            try app.main { $0.activeTool = .masking }
            try app.wait("the log and the journal to record the tool") { model in
                model.activity.events.contains { $0.text == "Tool: Masking" }
                    && journaled(model)?.events.contains { $0.text == "Tool: Masking" } == true
            }
            try app.main { $0.activeTool = .edit }
            if app.settingsControlsDrawnBySwiftUI {
                throw app.leftOutSettingsStep("Settings › Privacy's Keep an activity log switch")
            }
        }
    }

    /// Whether the report's sheet had the activity log on, and how many events it offered.
    final class OfferedActivity: Sendable {
        private let value = Mutex<(log: Bool?, events: Int)>((nil, 0))

        func set(log: Bool, events: Int) {
            value.withLock { $0 = (log, events) }
        }

        var log: Bool? {
            value.withLock { $0.log }
        }

        var events: Int {
            value.withLock { $0.events }
        }
    }
#endif
