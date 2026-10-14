#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import Foundation
    @_spi(Harness) import RedlampUI

    /// Crash and hang reports (UX-11). The main launch leaves two earlier sessions of this build that ended without
    /// quitting, as their journals and macOS's crash report have them: one that crashed, and one force quit while it
    /// hung. The relaunch's own launch check finds them, the banner over the photo offers them, and the crash's report
    /// goes to the stub relay.
    enum IncidentScenarios {
        /// In the main launch: the relaunch's launch check reads what it leaves.
        static let left: [Scenario] = [sessionsLeft]
        /// In the relaunch, the hang first: the launch check finds it last, so the banner offers it first.
        static let found: [Scenario] = [hangNotNow, crashReport]

        /// What the relaunch should find, written by the main launch.
        struct Left: Codable {
            /// The process IDs of the session that crashed and of the one force quit while it hung.
            var crash: Int32
            var hang: Int32
            /// The photo both had open, by its file name, which no report may hold.
            var photo: String
            /// Their journals, which the launch check removes once it has read them.
            var journals: [String]

            static func read(_ app: RunningApp) throws -> Left {
                guard let data = try? Data(contentsOf: app.runDirectory.appending(path: "incidents-left.json")) else {
                    throw ScenarioFailure(
                        "The main launch left no earlier sessions: \(sessionsLeft.id) didn't run in it",
                    )
                }
                return try JSONDecoder().decode(Left.self, from: data)
            }
        }

        /// The titles the reports suggest: macOS's report on the fixture's crash, and the hang the session ended in.
        static let crashTitle = "Crash: EXC_BAD_ACCESS (SIGSEGV) in Redlamp"
        static let hangTitle = "Hang: 14 s, then Redlamp was closed"
        /// The person's words in the crash's report.
        static let words = "Exporting the photo when it quit"

        static let sessionsLeft = Scenario(
            "feedback.incidents-left",
            "Two earlier sessions are left for the next launch to find: one that crashed, with macOS's crash report, "
                + "and one force quit while it hung",
            claims: [],
        ) { app in
            let fixture = app.runDirectory.appending(path: "fixtures/crash.ips")
            guard let report = try? Data(contentsOf: fixture) else {
                throw ScenarioFailure(
                    "The run has no crash report to leave: scripts/e2e.py copies one to \(fixture.path)",
                )
            }
            let photo = try app.photos.appending(path: app.workingPhoto())
            let run = app.runDirectory.standardizedFileURL.path
            let left = try app.main { model -> Left in
                // Only in the test home: in the person's, a crash report on the test app fails the run as a crash.
                for folder in [SessionJournal.folder, MacCrashReport.folder]
                    where !folder.standardizedFileURL.path.hasPrefix(run) {
                    throw ScenarioFailure("\(folder.path) isn't in the run's test home")
                }
                guard let current = model.activity.journal?.header else {
                    throw ScenarioFailure("This session keeps no journal, so none can be left as an earlier one's")
                }
                let now = Date()
                /// One of this build's sessions on this Mac since it last started up.
                func session(_ pid: Int32, started: Date) -> SessionJournal.Header {
                    SessionJournal.Header(
                        pid: pid, started: started, bundleID: current.bundleID, version: current.version,
                        development: current.development, booted: current.booted,
                    )
                }
                let format = photo.pathExtension.uppercased()
                let exported = "\(NSHomeDirectory())/Desktop/\(photo.deletingPathExtension().lastPathComponent).jpg"
                // An hour ago, a session that crashed 20 minutes in, reading the photo.
                let crashed = session(4242, started: now.addingTimeInterval(-3600))
                let crashTime = crashed.started.addingTimeInterval(1200)
                let crashJournal = try leave(crashed, photo: photo, at: crashTime) { alias in
                    [
                        (-250, .photo, "Opened \(alias): \(format), unedited, in 0.9 s"),
                        (-120, .edit, "Exposure: 0.00 → +0.50"),
                        (-30, .error, "Save failed: Couldn’t write “\(photo.path).redlamp”"),
                        (-10, .export, "Exported \(alias) to \(exported)"),
                    ]
                }
                try FileManager.default.createDirectory(at: MacCrashReport.folder, withIntermediateDirectories: true)
                try macOSReport(report, on: crashed, at: crashTime, reading: photo).write(
                    to: MacCrashReport.folder
                        .appending(path: "Redlamp-\(reportTime(crashTime, "yyyy-MM-dd-HHmmss")).ips"),
                )
                // Then one force quit 12 minutes ago, 14 s into a hang, as the watchdog marks one each second.
                let hung = session(4343, started: now.addingTimeInterval(-1800))
                let hangBegan = now.addingTimeInterval(-720)
                let marks = (2 ... 14).map { SessionJournal.Hang(began: hangBegan, duration: Double($0), ended: false) }
                let hangJournal = try leave(hung, photo: photo, at: hangBegan, hangs: marks) { alias in
                    [
                        (-300, .photo, "Opened \(alias): \(format), unedited, in 0.8 s"),
                        (-60, .edit, "Contrast: 0 → +20"),
                        (-5, .action, "Export…"),
                    ]
                }
                // As the next launch's check reads them.
                let crash = PreviousSession.read(crashJournal).flatMap { session in
                    IncidentCheck.incident(
                        for: session,
                        crash: MacCrashReport.find(
                            pid: crashed.pid,
                            bundleID: crashed.bundleID,
                            since: crashed.started,
                        ),
                        booted: current.booted,
                    )
                }
                let hang = PreviousSession.read(hangJournal).flatMap {
                    IncidentCheck.incident(for: $0, crash: nil, booted: current.booted)
                }
                guard crash?.suggestedTitle == crashTitle, hang?.suggestedTitle == hangTitle else {
                    throw ScenarioFailure(
                        "What's left reads as \(crash?.suggestedTitle ?? "no crash") and \(hang?.suggestedTitle ?? "no hang")",
                    )
                }
                UserDefaults.standard.set(true, forKey: SessionRecorder.offersInDevelopmentKey)
                return Left(
                    crash: crashed.pid, hang: hung.pid, photo: photo.lastPathComponent,
                    journals: [crashJournal.lastPathComponent, hangJournal.lastPathComponent],
                )
            }
            try JSONEncoder().encode(left).write(to: app.runDirectory.appending(path: "incidents-left.json"))
        }

        static let hangNotNow = Scenario(
            "feedback.hang-not-now",
            "Reopened after a session force quit while it hung, the banner over the photo offers the hang, in Develop "
                + "and over the Library's photos; Not Now keeps it in Your Reports",
            group: .relaunch,
            claims: [.feature("performance.freeze")],
            needsFocus: true,
        ) { app in
            let left = try Left.read(app)
            try app.settle(timeout: 60)
            let (crash, hang) = try app.incidents(left)
            try app.expect(
                hang.incident.suggestedTitle == hangTitle && hang.incident.sources == [Incident.Source.watchdog],
                "The hang reads \(hang.incident.suggestedTitle), recorded by \(hang.incident.sources)",
            )
            try app.putAside(except: [crash.id, hang.id])
            let focused = try app.focus()
            try app.waitForBanner(offering: hang, in: .develop)

            app.step("Not Now")
            if focused {
                try app.tap(.identifier("incident.banner.notNow"))
            } else {
                // What its button does: SwiftUI's buttons take no click while the app isn't active.
                try app.main { $0.incidentHistory?.dismiss(hang.id) }
            }
            try app.wait("Not Now to keep the hang, no longer offered") { model in
                model.incidentHistory?.incidents.first { $0.id == hang.id }?.dismissed == true
            }
            try app.waitForBanner(offering: crash, in: .develop)
            app.covered(.feature("performance.freeze"), via: focused ? .mouse : .model)

            app.step("the banner over the Library's photos")
            try app.press(.gridView)
            try app.waitForBanner(offering: crash, in: .library)
            try app.press(.developModule)
            try app.waitForBanner(offering: crash, in: .develop)

            app.step("Your Reports")
            try app.openYourReports(listing: [hang, crash])
            try app.closeYourReports()
        }

        static let crashReport = Scenario(
            "feedback.crash-report",
            "The banner's Review Report… opens the crash's report, with its stacks, the activity before it and the Mac "
                + "but no photo or log; sent to the stub relay, it holds them under Crashes, and none of its session's "
                + "file names or folders",
            group: .relaunch,
            claims: [.feature("performance.crash")],
            needsFocus: true,
        ) { app in
            let left = try Left.read(app)
            try app.settle(timeout: 60)
            let (crash, hang) = try app.incidents(left)
            let incident = crash.incident
            try app.expect(
                incident.suggestedTitle == crashTitle && incident.sources == [Incident.Source.crashReport]
                    && incident.threads.count == 4 && incident.binaries.count == 2,
                "The crash reads \(incident.suggestedTitle), recorded by \(incident.sources), with "
                    + "\(incident.threads.count) threads and \(incident.binaries.count) binaries",
            )
            defer { try? app.main { _ in
                UserDefaults.standard.removeObject(forKey: SessionRecorder.offersInDevelopmentKey)
            } }
            try app.putAside(except: [crash.id])
            let focused = try app.focus()
            try app.waitForBanner(offering: crash, in: .develop)

            app.step("Review Report…")
            if focused {
                try app.tap(.identifier("incident.banner.review"))
            } else {
                // What its button does: SwiftUI's buttons take no click while the app isn't active.
                try app.main { $0.sendFeedback(FeedbackPrefill(incident: crash)) }
            }
            try app.waitForSheet("the crash's report")
            try app.wait("the report on the crash") { _ in inSheet("feedback.title") }
            app.covered(.feature("performance.crash"), via: focused ? .mouse : .model)
            let (title, offered, controls) = try app.main { _ -> (String?, [String: Bool], String) in
                guard let sheet = Views.editorWindow?.attachedSheet else { return (nil, [:], "no sheet") }
                return (
                    IncidentScenarios.field("feedback.title", in: sheet)?.stringValue,
                    IncidentScenarios.switches(in: sheet), IncidentScenarios.describe(sheet),
                )
            }
            try app.expect(
                title == crashTitle,
                "The report's title is \(title ?? "missing"), not \(crashTitle) (\(controls))",
            )
            let details = [
                "feedback.details.incident": true,
                "feedback.details.activity": true,
                "feedback.details.system": true,
            ]
            try app.expect(
                offered == details,
                "The report offers \(offered.sorted { $0.key < $1.key }), not the crash's stacks, the activity before it "
                    + "and the Mac, each on (\(controls))",
            )

            app.step("the person's words")
            try app.focusWords(clicking: focused)
            try app.typeInAttachedSheet(words)
            try app.wait("the words typed") { _ in
                Views.editorWindow?.attachedSheet.flatMap { IncidentScenarios.wordsBox(in: $0) }?.string == words
            }

            app.step("Send Report")
            let relay = app.runDirectory.appending(path: "relay")
            let before = Set((try? FileManager.default.contentsOfDirectory(atPath: relay.path)) ?? [])
            @Sendable func received() -> URL? {
                let now = Set((try? FileManager.default.contentsOfDirectory(atPath: relay.path)) ?? [])
                return now.subtracting(before).sorted().last.map { relay.appending(path: $0) }
            }
            if focused {
                try app.tapInSheet("feedback.send")
            } else {
                try app.expect(try app.pressInSheet(KeyCombo(.character("\r"))), "Send Report didn't take Return")
            }
            try app.wait("the stub relay to get the report", timeout: 30) { _ in received() != nil }
            try app.wait("the report to say the dry run filed nothing", timeout: 30) { _ in
                Views.editorWindow?.attachedSheet != nil && !inSheet("feedback.send")
            }
            try app.expect(try app.pressInSheet(KeyCombo(.character("\r"))), "Done didn't take Return")
            try app.waitForNoSheet("the crash's report")

            app.step("what the relay got")
            guard let url = received() else { throw ScenarioFailure("The relay's report went away") }
            let sent = try Sent(url)
            try app.expect(
                sent.title == "[Performance & Stability › Crashes] \(crashTitle)",
                "The issue is titled \(sent.title)",
            )
            try app.expect(
                sent.dryRun && Set(sent.labels).isSuperset(of: ["in-app", "bug", "component:performance"]),
                "It went \(sent.dryRun ? "as" : "not as") a dry run, labelled \(sent.labels)",
            )
            let line = sent.hiddenLine
            try app.expect(
                line["incident"] as? String == "crash" && line["area"] as? String == "performance.crash"
                    && line["kind"] as? String == "bug",
                "The issue's hidden line holds \(line)",
            )
            for part in [
                "Redlamp quit unexpectedly.", "**Exception:** EXC_BAD_ACCESS (SIGSEGV)", "while reading …/Photo A",
                "### What I was doing\n\n\(words)", "### The crashed thread (thread 0, the main thread)",
                "What happened before the crash", "Exported Photo A to …/Photo A.jpg", "<summary>System</summary>",
            ] {
                try app.expect(sent.body.contains(part), "The issue doesn't say “\(part)”:\n\(sent.body)")
            }
            let sentIncident = sent.diagnostics["incident"] as? [String: Any] ?? [:]
            let threads = sentIncident["threads"] as? [[String: Any]] ?? []
            let binaries = sentIncident["binaries"] as? [[String: Any]] ?? []
            try app.expect(sent.attachments == [FeedbackReport.diagnosticsName], "It came with \(sent.attachments)")
            try app.expect(
                sentIncident["kind"] as? String == "crash" && sentIncident["pid"] as? Int == Int(left.crash),
                "diagnostics.json's incident is \(sentIncident["kind"] ?? "missing") in process "
                    + "\(sentIncident["pid"] ?? "none")",
            )
            try app.expect(
                threads.count == 4 && threads.contains { thread in
                    thread["crashed"] as? Bool == true && !(thread["frames"] as? [Any] ?? []).isEmpty
                },
                "diagnostics.json has \(threads.count) threads, none crashed with its frames",
            )
            try app.expect(
                binaries.count == 2 && binaries
                    .allSatisfy { !($0["uuid"] as? String ?? "").isEmpty && $0["base"] is NSNumber },
                "diagnostics.json's binaries are \(binaries)",
            )
            let photoAndLog = ["photo", "edit", "history", "log", "sidecar"].filter { sent.diagnostics[$0] != nil }
            try app.expect(
                photoAndLog.isEmpty && sent.diagnostics["activity"] is [Any] && sent.diagnostics["system"] != nil,
                "diagnostics.json holds \(sent.diagnostics.keys.sorted())",
            )
            let stem = (left.photo as NSString).deletingPathExtension
            for leak in [left.photo, stem, app.photos.path, app.runDirectory.path, "/Users/"] {
                for (part, text) in [
                    ("title", sent.title),
                    ("issue", sent.body),
                    ("diagnostics.json", sent.diagnosticsText),
                ]
                    where text.contains(leak) {
                    throw ScenarioFailure("The report's \(part) holds \(leak)")
                }
            }
            try app.wait("the crash still offered, since a dry run files nothing") { model in
                model.incidentHistory?.offeredIncident?.id == crash.id
            }
            try app.waitForBanner(offering: crash, in: .develop)

            app.step("Your Reports")
            try app.openYourReports(listing: [hang, crash])
            if focused {
                try app.tapInSheet("reports.incident.\(crash.id.uuidString).review")
                try app.wait("Review Report… to open the crash's report again") { _ in
                    Views.editorWindow?.attachedSheet.flatMap { IncidentScenarios.field("feedback.title", in: $0) }?
                        .stringValue == crashTitle
                }
                try app.pressInSheet(KeyCombo(.escape))
                try app.waitForNoSheet("the crash's report")
                try app.openYourReports(listing: [hang, crash])
            }
            for pending in [crash, hang] {
                let remove = "reports.incident.\(pending.id.uuidString).remove"
                if focused {
                    try app.tapInSheet(remove)
                } else {
                    // What its button does: SwiftUI's buttons take no click while the app isn't active.
                    try app.main { $0.incidentHistory?.forgetIncident(pending.id) }
                }
                try app.wait("Remove to take the \(pending.incident.kind) off the list") { model in
                    model.incidentHistory?.incidents.contains { $0.id == pending.id } == false && !inSheet(remove)
                }
            }
            try app.closeYourReports()
            try app.wait("the banner gone, with nothing left to report") { model in
                guard let window = Views.editorWindow else { return false }
                return model.incidentHistory?.offeredIncident == nil
                    && Views.find("incident.banner.review", in: window) == nil
            }
        }

        // MARK: - Leaving earlier sessions

        /// Leaves the journal of an earlier session as it kept it, without its last line: the photo it opened, its
        /// folder, `events` (given the photo's alias) at their seconds from `time`, and the marks of its hangs.
        @MainActor static func leave(
            _ header: SessionJournal.Header, photo: URL, at time: Date, hangs: [SessionJournal.Hang] = [],
            events: (String) -> [(TimeInterval, ActivityLog.Event.Kind, String)],
        ) throws -> URL {
            let journal = try SessionJournal(header: header)
            var clock = time
            let activity = ActivityLog(now: { clock })
            activity.journal = journal
            activity.folders = [photo.deletingLastPathComponent().path]
            let alias = activity.alias(for: photo)
            for (seconds, kind, text) in events(alias) {
                clock = time.addingTimeInterval(seconds)
                activity.record(kind, text)
            }
            hangs.forEach(journal.hang)
            return journal.url
        }

        /// macOS's report on the crash of `header`'s process at `time`, as it writes it a few seconds later: the
        /// fixture's, for this build, crashing while it read `photo`.
        static func macOSReport(
            _ fixture: Data, on header: SessionJournal.Header, at time: Date, reading photo: URL,
        ) throws -> Data {
            guard let newline = fixture.firstIndex(of: UInt8(ascii: "\n")),
                  var first = try JSONSerialization.jsonObject(with: fixture[..<newline]) as? [String: Any],
                  var body = try JSONSerialization.jsonObject(with: fixture[fixture.index(after: newline)...])
                  as? [String: Any]
            else { throw ScenarioFailure("The crash report fixture isn't one") }
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            first["bundleID"] = header.bundleID
            first["app_version"] = version
            first["build_version"] = build
            first["timestamp"] = reportTime(time.addingTimeInterval(3))
            body["pid"] = Int(header.pid)
            body["captureTime"] = reportTime(time)
            body["procLaunch"] = reportTime(header.started)
            body["bundleInfo"] = [
                "CFBundleShortVersionString": version, "CFBundleVersion": build, "CFBundleIdentifier": header.bundleID,
            ]
            if var termination = body["termination"] as? [String: Any] {
                termination["byPid"] = Int(header.pid)
                body["termination"] = termination
            }
            // The fixture's crash names the photo it was reading by its path.
            let read = "/Users/someone/Pictures/Holiday/IMG_0001.CR3"
            if let asi = body["asi"] as? [String: [String]] {
                body["asi"] = asi.mapValues { $0.map { $0.replacingOccurrences(of: read, with: photo.path) } }
            }
            if let region = body["vmRegionInfo"] as? String {
                body["vmRegionInfo"] = region.replacingOccurrences(of: read, with: photo.path)
            }
            var data = try JSONSerialization.data(withJSONObject: first, options: [.withoutEscapingSlashes])
            data.append(0x0A)
            try data.append(JSONSerialization.data(
                withJSONObject: body,
                options: [.prettyPrinted, .withoutEscapingSlashes],
            ))
            return data
        }

        /// As macOS's crash reports write times, "2026-10-14 10:08:08.3999 +0100".
        static func reportTime(_ date: Date, _ format: String = "yyyy-MM-dd HH:mm:ss.SSSS Z") -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter.string(from: date)
        }

        // MARK: - The report's sheet

        /// The view carrying `identifier` in `window` that isn't hidden.
        @MainActor static func view(_ identifier: String, in window: NSWindow) -> NSView? {
            guard let root = window.contentView else { return nil }
            return Views.all(NSView.self, in: root)
                .first { $0.accessibilityIdentifier() == identifier && !$0.isHiddenOrHasHiddenAncestor }
        }

        @MainActor static func inSheet(_ identifier: String) -> Bool {
            Views.editorWindow?.attachedSheet.flatMap { view(identifier, in: $0) } != nil
        }

        /// The text field `identifier` marks in `sheet`.
        @MainActor static func field(_ identifier: String, in sheet: NSWindow) -> NSTextField? {
            guard let root = sheet.contentView, let marker = view(identifier, in: sheet) else { return nil }
            if let field = marker as? NSTextField {
                return field
            }
            let frame = marker.convert(marker.bounds, to: nil)
            return Views.all(NSTextField.self, in: root)
                .first { $0.isEditable && $0.convert($0.bounds, to: nil).intersects(frame) }
        }

        /// The report's box for the person's own words.
        @MainActor static func wordsBox(in sheet: NSWindow) -> NSTextView? {
            guard let root = sheet.contentView, let marker = view("feedback.words", in: sheet) else { return nil }
            let frame = marker.convert(marker.bounds, to: nil)
            return Views.all(NSTextView.self, in: root)
                .first { !$0.isFieldEditor && $0.isEditable && $0.convert($0.bounds, to: nil).intersects(frame) }
        }

        /// The switches `sheet` offers, by the identifier each control marks, and whether each is on.
        @MainActor static func switches(in sheet: NSWindow) -> [String: Bool] {
            guard let root = sheet.contentView else { return [:] }
            let views = Views.all(NSView.self, in: root)
            let marked = views.filter { $0.accessibilityIdentifier().hasPrefix("feedback.") }
            var found: [String: Bool] = [:]
            for control in views.compactMap({ $0 as? NSControl })
                where control is NSSwitch || control.accessibilityRole() == .checkBox {
                let middle = control.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
                let marker = marked.first { $0.convert($0.bounds, to: nil).contains(middle) }
                let own = control.accessibilityIdentifier()
                let unmarked = "an unmarked \(String(describing: Swift.type(of: control)))"
                var name = own.isEmpty ? marker?.accessibilityIdentifier() ?? unmarked : own
                if found[name] != nil {
                    name += " \(found.count + 1)"
                }
                found[name] = (control as? NSButton)?.state == .on || (control as? NSSwitch)?.state == .on
            }
            return found
        }

        /// The sheet's controls and the identifiers they carry, for a failure's message.
        @MainActor static func describe(_ sheet: NSWindow) -> String {
            guard let root = sheet.contentView else { return "no sheet" }
            return Views.all(NSView.self, in: root).compactMap { view in
                let identifier = view.accessibilityIdentifier()
                guard view is NSControl || view is NSTextView || !identifier.isEmpty else { return nil }
                return String(describing: Swift.type(of: view)) + (identifier.isEmpty ? "" : " \(identifier)")
            }.joined(separator: ", ")
        }

        /// A report as the stub relay got it: the issue's title, body and labels, its attachments, and
        /// diagnostics.json.
        struct Sent {
            var title: String
            var body: String
            var labels: [String]
            var attachments: [String]
            var dryRun: Bool
            var diagnostics: [String: Any]
            /// diagnostics.json as it was sent.
            var diagnosticsText: String

            init(_ url: URL) throws {
                guard let file = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                      let payload = file["body"] as? [String: Any]
                else { throw ScenarioFailure("The relay's \(url.lastPathComponent) holds no report") }
                title = payload["title"] as? String ?? ""
                body = payload["body"] as? String ?? ""
                labels = payload["labels"] as? [String] ?? []
                dryRun = payload["dryRun"] as? Bool ?? false
                let files = payload["attachments"] as? [[String: Any]] ?? []
                attachments = files.compactMap { $0["name"] as? String }
                let encoded = files
                    .first { $0["name"] as? String == FeedbackReport.diagnosticsName }?["data"] as? String
                let data = encoded.flatMap { Data(base64Encoded: $0) } ?? Data()
                diagnosticsText = String(decoding: data, as: UTF8.self)
                diagnostics = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            }

            /// The fields of the issue's hidden line, which the reports room sorts reports by.
            var hiddenLine: [String: Any] {
                guard let match = body.firstMatch(of: /<!-- redlamp-feedback v1 (\{[^\n]*?\}) -->/) else { return [:] }
                return (try? JSONSerialization.jsonObject(with: Data(match.1.utf8))) as? [String: Any] ?? [:]
            }
        }
    }

    extension RunningApp {
        /// The crash and the hang the relaunch's launch check found in the sessions the main launch left, whose
        /// journals it removed once it had read them.
        func incidents(_ left: IncidentScenarios.Left) throws -> (crash: PendingIncident, hang: PendingIncident) {
            @MainActor func found(_ model: EditorModel) -> (crash: PendingIncident, hang: PendingIncident)? {
                let listed = model.incidentHistory?.incidents ?? []
                guard let crash = listed.first(where: { $0.incident.kind == .crash && $0.incident.pid == left.crash }),
                      let hang = listed.first(where: { $0.incident.kind == .hang && $0.incident.pid == left.hang })
                else { return nil }
                return (crash, hang)
            }
            do {
                try wait("the launch check to find the crash and the hang", timeout: 30) { found($0) != nil }
            } catch {
                let state = try main { model -> String in
                    guard let history = model.incidentHistory else {
                        return "this launch offers no crash or hang reports, as "
                            + "\(SessionRecorder.offersInDevelopmentKey) wasn't set when it began"
                    }
                    let listed = history.incidents.map { "the \($0.incident.kind) of process \($0.incident.pid)" }
                    let journals = (try? FileManager.default.contentsOfDirectory(atPath: SessionJournal.folder.path)) ??
                        []
                    return "it found \(listed.isEmpty ? "nothing" : listed.joined(separator: ", ")), and the journals' "
                        + "folder holds \(journals)"
                }
                throw ScenarioFailure("\(error): \(state)")
            }
            let kept = left.journals.filter {
                FileManager.default.fileExists(atPath: SessionJournal.folder.appending(path: $0).path)
            }
            try expect(kept.isEmpty, "The launch check kept the journals it read: \(kept)")
            guard let incidents = try main({ found($0) }) else { throw ScenarioFailure("The crash and the hang went") }
            return incidents
        }

        /// Not Now, as a set-up, for what the launch found but `kept`: the hang, when the scenario that dismisses it
        /// didn't run, or a long hang in the main launch's own session.
        func putAside(except kept: [UUID]) throws {
            let others = try main { model -> [String] in
                guard let history = model.incidentHistory else { return [] }
                return history.incidents.filter { !kept.contains($0.id) && !$0.dismissed }.map { pending in
                    history.dismiss(pending.id)
                    return "\(pending.incident.suggestedTitle) (process \(pending.incident.pid))"
                }
            }
            if !others.isEmpty {
                recorder.write("note", ["step": "put aside, as Not Now does", "incidents": others])
            }
        }

        /// Waits for the banner to offer `pending` over the photo in Develop, or over the Library's photos.
        func waitForBanner(offering pending: PendingIncident, in module: AppModule) throws {
            let place = module == .library ? "over the Library's photos" : "over the photo"
            try wait("the banner \(place) to offer the \(pending.incident.kind)", timeout: 10) { model in
                guard model.module == module, model.incidentHistory?.offeredIncident?.id == pending.id,
                      let window = Views.editorWindow
                else { return false }
                return Views.find("incident.banner.review", in: window) != nil
                    && Views.find("incident.banner.notNow", in: window) != nil
            }
        }

        /// Help › Your Reports…, listing each of `incidents` not reported yet, to review or remove.
        func openYourReports(listing incidents: [PendingIncident]) throws {
            try choose("Your Reports…")
            try waitForSheet("Your Reports")
            let rows = incidents.flatMap { pending in
                ["review", "remove"].map { "reports.incident.\(pending.id.uuidString).\($0)" }
            }
            let kinds = incidents.map { "\($0.incident.kind)" }.joined(separator: " and ")
            try wait("Your Reports to list the \(kinds)") { _ in rows.allSatisfy { IncidentScenarios.inSheet($0) } }
        }

        func closeYourReports() throws {
            try pressInSheet(KeyCombo(.character("\r")))
            pause(0.5)
            if try sheetIsUp() {
                try pressInSheet(KeyCombo(.escape))
            }
            try waitForNoSheet("Your Reports")
        }

        /// Clicks the control carrying `identifier` in the sheet in front, through the sheet as the mouse does: in a
        /// run with focus, whose sheet is key, since SwiftUI's buttons take no click while the app isn't active.
        func tapInSheet(_ identifier: String) throws {
            let place = try main { _ -> (window: Int, location: NSPoint) in
                guard let sheet = Views.editorWindow?.attachedSheet,
                      let view = IncidentScenarios.view(identifier, in: sheet)
                else { throw ScenarioFailure("\(identifier) isn't in the sheet") }
                view.scrollToVisible(view.bounds)
                sheet.contentView?.layoutSubtreeIfNeeded()
                let frame = view.convert(view.bounds, to: nil)
                return (sheet.windowNumber, NSPoint(x: frame.midX, y: frame.midY))
            }
            post { _ in Views.tap(at: place.location, inWindow: place.window, clicks: 1, modifiers: []) }
            pause(0.2)
        }

        /// Gives the words box of the report in front the keyboard: a click on it where the run has focus, otherwise
        /// Tab, as the keyboard moves through the sheet.
        func focusWords(clicking: Bool) throws {
            @MainActor func hasKeyboard() -> Bool {
                guard let sheet = Views.editorWindow?.attachedSheet, let box = IncidentScenarios.wordsBox(in: sheet)
                else { return false }
                return sheet.firstResponder === box
            }
            if clicking {
                try tapInSheet("feedback.words")
            } else {
                for _ in 0 ..< 6 where try !main({ _ in hasKeyboard() }) {
                    try main { _ in try Views.editorWindow?.attachedSheet?.sendEvent(Keyboard.event(KeyCombo(.tab))) }
                    pause(0.15)
                }
            }
            if (try? wait("the words box to take the keyboard", timeout: 3, until: { _ in hasKeyboard() })) != nil {
                return
            }
            // A sheet in the background may keep the keyboard from it; the rest of the report still goes through its
            // keys, and the run says how it got there.
            let state = try main { _ -> String in
                guard let sheet = Views.editorWindow?.attachedSheet,
                      let box = IncidentScenarios.wordsBox(in: sheet) else {
                    throw ScenarioFailure("The report has no words box")
                }
                let responder = sheet.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nothing"
                sheet.makeFirstResponder(box)
                return "\(responder) had it, among \(IncidentScenarios.describe(sheet))"
            }
            recorder.write("note", [
                "step": "the words box didn't take the keyboard from \(clicking ? "a click" : "Tab"), so it was given it",
                "state": state,
            ])
            try wait("the words box to take the keyboard", timeout: 3) { _ in hasKeyboard() }
        }
    }
#endif
