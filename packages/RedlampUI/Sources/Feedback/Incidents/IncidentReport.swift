import Foundation

// MARK: - What a report says of a crash or a hang

extension Incident {
    /// What a report on it is filed under: Performance & Stability › Crashes, or › Freezes.
    var featureID: String {
        kind == .crash ? "performance.crash" : "performance.freeze"
    }

    /// The thread on the main queue, or else the first: macOS's crash report and MetricKit both list it first.
    var mainThread: Int? {
        threads.firstIndex { $0.queue == "com.apple.main-thread" } ?? (threads.isEmpty ? nil : 0)
    }

    /// The report's What happened: the headline, then a fact a line.
    var summary: [String] {
        var lines = ["\(headline).", ""]
        if let exception {
            lines.append("- **Exception:** \(exception)")
        }
        if kind == .hang, let duration {
            lines.append("- **Not responding for:** \(Self.seconds(duration)), "
                + (endedSession ? "then Redlamp was closed" : "then it responded again"))
        }
        let reasons = reasons.map { $0.replacingOccurrences(of: "\n", with: " ") }
        if reasons.count == 1 {
            lines.append("- **Reason:** \(reasons[0])")
        } else if !reasons.isEmpty {
            lines += ["- **Reasons:**"] + reasons.map { "  - \($0)" }
        }
        if let culprit {
            lines.append("- **In:** \(culprit)")
        }
        if let version {
            lines.append("- **Version:** Redlamp \(version)")
        }
        lines.append("- **When:** \(Self.utc(time))")
        lines.append("- **Recorded by:** \(Self.list(sources.map(\.title)))")
        if threads.isEmpty {
            lines += ["", "No thread's stack was recorded."]
        }
        return lines
    }

    /// The stacks a report shows, each with its heading: the crashed thread's, the main thread's when it's another,
    /// and where an Objective-C exception was raised.
    var shownStacks: [(title: String, frames: [Frame])] {
        let main = mainThread
        var stacks: [(title: String, frames: [Frame])] = []
        if kind == .crash, let crashed = threads.firstIndex(where: \.crashed) {
            let thread = threads[crashed]
            let name = crashed == main ? "the main thread" : thread.name ?? thread.queue
            let about = ["thread \(crashed)", name].compactMap(\.self).joined(separator: ", ")
            stacks.append(("The crashed thread (\(about))", thread.frames))
        }
        if let main, kind == .hang || !threads[main].crashed {
            stacks.append(("The main thread (thread \(main))", threads[main].frames))
        }
        if let exceptionBacktrace {
            stacks.append(("Where the exception was raised", exceptionBacktrace))
        }
        return stacks.filter { !$0.frames.isEmpty }
    }

    /// A stack as text, a frame a line: its index, its binary's name, and the symbol the Mac named it by, or else its
    /// offset in the binary, which the release's dSYMs name.
    func stackLines(_ frames: [Frame], limit: Int) -> [String] {
        let shown = Array(frames.prefix(limit))
        let names = shown.map { binaries.indices.contains($0.binary) ? binaries[$0.binary].name : "?" }
        let width = names.map(\.count).max() ?? 0
        let digits = String(max(0, shown.count - 1)).count
        var lines = shown.indices.map { index in
            let number = String(index)
            let symbol = shown[index].symbol ?? String(format: "0x%llx", shown[index].offset)
            return String(repeating: " ", count: digits - number.count) + number + "  "
                + names[index].padding(toLength: width, withPad: " ", startingAt: 0) + "  " + symbol
        }
        if frames.count > shown.count {
            lines.append("… \(frames.count - shown.count) more, in \(FeedbackReport.diagnosticsName)")
        }
        return lines
    }

    /// "2026-10-14 09:08:08 UTC": the person's time zone stays on the Mac.
    static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

extension Incident.Source {
    var title: String {
        switch self {
        case .crashReport: "macOS's crash report"
        case .metricKit: "MetricKit"
        case .watchdog: "Redlamp's hang watchdog"
        }
    }
}

extension PendingIncident {
    /// Its session's activity from `FeedbackReport.activityWindow` before it: to the session's end, or to the end of a
    /// hang Redlamp came back from, which "Not responding for" marks just after.
    var activityBefore: [ActivityLog.Event] {
        let since = incident.time.addingTimeInterval(-FeedbackReport.activityWindow)
        let until = incident.kind == .hang && !incident.endedSession
            ? incident.time.addingTimeInterval((incident.duration ?? 0) + 2) : .distantFuture
        return activity.filter { $0.time >= since && $0.time <= until }
    }
}

public extension FeedbackContext {
    /// What a report on a crash or a hang knows: the activity, photos and folders of the session it happened in, and
    /// nothing of this one. `activityLog`: whether the activity log is on now; off, there's no activity.
    init(reporting pending: PendingIncident, activityLog: Bool = true, now: Date = Date()) {
        self.init(
            captured: now,
            state: State(
                tool: "", panels: [], zoom: "", beforeAfter: nil, selectedMask: nil, focusedSlider: nil,
                folderPhotos: nil, selectedPhotos: 0, hidden: [],
            ),
            activity: pending.activity, activityLog: activityLog, photos: pending.photos, folders: pending.folders,
            suggestion: pending.incident.featureID,
        )
    }
}

// MARK: - The issue and diagnostics.json

extension FeedbackReport {
    /// The relay takes diagnostics.json up to 2 MB.
    static let diagnosticsLimit = 1_900_000

    /// A crash or a hang's issue after its first lines: what happened, the person's words, the stacks, the activity
    /// before it and the Mac, each part as the person chose.
    func incidentLines(_ pending: PendingIncident, system: SystemSnapshot, limits: Limits) -> [String] {
        let incident = pending.incident
        var out: [String] = []
        if details.incident {
            out += ["", "### What happened", ""] + incident.summary.map(Self.sanitized)
        }
        out += section("What I was doing", body)
        if details.incident {
            for stack in incident.shownStacks {
                let lines = incident.stackLines(stack.frames, limit: limits.frames)
                    .map { Self.sanitized($0).replacingOccurrences(of: "```", with: "'''") }
                out += ["", "### \(Self.sanitized(stack.title))", "", "```text"] + lines + ["```"]
            }
        }
        if details.activity {
            let events = pending.activityBefore
            if !events.isEmpty {
                let shown = events.suffix(limits.activity)
                let rows = shown.map { event in
                    (
                        Self.before(event.time, incident.time),
                        Optional(event.text + (event.count > 1 ? " ×\(event.count)" : "")),
                    )
                }
                let before = "What happened before the \(incident.kind == .crash ? "crash" : "hang")"
                let title = shown.count < events.count
                    ? "\(before) (last 15 minutes, the latest \(shown.count) of \(events.count) events)"
                    : "\(before) (last 15 minutes, \(Self.count(events.count, "event")))"
                out += disclosure(title, table(rows, headers: ("Before", "What")))
            }
        }
        if details.system {
            out += disclosure("System", table(system.rows.map { ($0.0, Optional($0.1)) }))
        }
        out += ["", "---"]
        if includesDetails {
            out.append("[\(Self.diagnosticsName)](attachment:\(Self.diagnosticsName)) has these details in full"
                + (details.incident && !incident.threads.isEmpty
                    ? ", with every thread's stack and the binaries' UUIDs and load addresses to symbolicate them."
                    : "."))
        }
        out.append("<sub>Sent from Redlamp's crash and hang reports.</sub>")
        return out
    }

    private struct IncidentDiagnostics: Encodable {
        let format = "app.redlamp.feedback-diagnostics"
        let formatVersion = 1
        let report: UUID
        let kind: Kind
        let area: String?
        let captured: Date
        let system: SystemSnapshot?
        /// As `Incident` encodes it: every thread, and the binaries with their UUIDs and load addresses, which
        /// `scripts/symbolicate-report.py` reads.
        let incident: Incident?
        let activity: [ActivityLog.Event]?
    }

    /// A crash or a hang's details in full: the whole incident, and its session's activity in the window the
    /// switch names.
    func incidentDiagnostics(_ pending: PendingIncident, context: FeedbackContext, system: SystemSnapshot) throws
        -> Data? {
        let document = IncidentDiagnostics(
            report: id, kind: kind, area: featureID, captured: context.captured,
            system: details.system ? system : nil,
            incident: details.incident ? pending.incident : nil,
            activity: details.activity && context.activityLog ? pending.activityBefore : nil,
        )
        let encoder = JSONEncoder()
        // The redactor finds paths by their slashes.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let text = try redactor(context).redact(String(decoding: encoder.encode(document), as: UTF8.self))
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
        )
        guard data.count > Self.diagnosticsLimit else { return data }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
