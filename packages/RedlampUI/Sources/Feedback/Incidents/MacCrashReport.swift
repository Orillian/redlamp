import Foundation

/// The crash reports macOS writes to `~/Library/Logs/DiagnosticReports` as `<name>-<date>.ips`: a
/// line of JSON naming the app, then the report. Redlamp isn't sandboxed, so it can read its own,
/// a few seconds after the crash. The regression suite's copy, other builds and the CLI write
/// there too, so a report is taken only for the bundle ID and process asked for.
public enum MacCrashReport {
    public static var folder: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Logs/DiagnosticReports")
    }

    /// `bundleID`'s crash in process `pid`, among the reports written since `since`.
    public static func find(pid: Int32, bundleID: String, since: Date, in folder: URL = folder) -> Incident? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
        ) else { return nil }
        let recent = files.filter { $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: keys).contentModificationDate, date >= since
                else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(100)
        for (url, _) in recent {
            guard let data = try? Data(contentsOf: url), let report = read(data),
                  report.bundleID == bundleID, report.incident.pid == pid
            else { continue }
            return report.incident
        }
        return nil
    }

    /// The report's app and incident; `nil` unless it's a crash (bug type 309).
    static func read(_ data: Data) -> (bundleID: String?, incident: Incident)? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
              header["bug_type"] as? String == "309",
              let body = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...]) as? [String: Any],
              let pid = body["pid"] as? Int
        else { return nil }
        var incident = Incident(
            kind: .crash,
            time: (body["captureTime"] as? String).flatMap(date) ?? Date(),
            pid: Int32(pid),
            sources: [.crashReport],
        )
        let bundle = body["bundleInfo"] as? [String: Any]
        if let version = bundle?["CFBundleShortVersionString"] as? String {
            incident.version = (bundle?["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
        }
        if let exception = body["exception"] as? [String: Any] {
            let names = [exception["type"], exception["signal"]].compactMap { $0 as? String }
            incident.exception = names.isEmpty ? nil
                : names.count == 2 ? "\(names[0]) (\(names[1]))" : names[0]
            if let subtype = exception["subtype"] as? String {
                incident.reasons.append(subtype)
            }
        }
        if let termination = body["termination"] as? [String: Any] {
            if let namespace = termination["namespace"] as? String,
               let indicator = termination["indicator"] as? String {
                incident.reasons.append("\(namespace): \(indicator)")
            }
            incident.reasons += termination["reasons"] as? [String] ?? []
            incident.reasons += termination["details"] as? [String] ?? []
        }
        // What the app and its libraries said as it ended: an abort's message, an exception's reason.
        if let asi = body["asi"] as? [String: [String]] {
            incident.reasons += asi.keys.sorted().flatMap { asi[$0] ?? [] }
        }
        // The rest of the region list names mapped files.
        if let region = (body["vmRegionInfo"] as? String)?.split(separator: "\n").first {
            incident.reasons.append(String(region))
        }
        incident.binaries = (body["usedImages"] as? [[String: Any]] ?? []).map { image in
            Incident.Binary(
                name: image["name"] as? String ?? "???",
                uuid: (image["uuid"] as? String ?? "").uppercased(),
                base: (image["base"] as? NSNumber)?.uint64Value,
                inApp: (image["path"] as? String)?.contains(".app/Contents/") == true,
            )
        }
        let crashed = body["faultingThread"] as? Int
        incident.threads = (body["threads"] as? [[String: Any]] ?? []).enumerated().map { index, thread in
            Incident.Thread(
                name: thread["name"] as? String,
                queue: thread["queue"] as? String,
                crashed: thread["triggered"] as? Bool ?? (index == crashed),
                frames: frames(thread["frames"], binaries: incident.binaries.count),
            )
        }
        if let backtrace = body["lastExceptionBacktrace"] {
            incident.exceptionBacktrace = frames(backtrace, binaries: incident.binaries.count)
        }
        return (header["bundleID"] as? String ?? bundle?["CFBundleIdentifier"] as? String, incident)
    }

    private static func frames(_ value: Any?, binaries: Int) -> [Incident.Frame] {
        (value as? [[String: Any]] ?? []).compactMap { frame in
            guard let binary = frame["imageIndex"] as? Int, binary < binaries,
                  let offset = (frame["imageOffset"] as? NSNumber)?.uint64Value
            else { return nil }
            return Incident.Frame(binary: binary, offset: offset, symbol: frame["symbol"] as? String)
        }
    }

    /// "2026-10-14 10:08:08.1234 +0100".
    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
