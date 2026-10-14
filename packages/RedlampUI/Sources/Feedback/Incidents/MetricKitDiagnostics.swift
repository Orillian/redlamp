import Foundation
import MetricKit

/// Receives MetricKit's crash and hang diagnostics. A crash's arrives within a second of the next
/// launch, even with sharing with developers turned off, and MetricKit hands each over once:
/// `pastDiagnosticPayloads` was empty after a delivery (measured 14 October 2026, macOS 26.6), so
/// `received` is given every incident to keep. MetricKit only collects for an app once it has
/// asked for `MXMetricManager.shared`, so this starts at launch.
public final class MetricKitDiagnostics: NSObject, MXMetricManagerSubscriber, Sendable {
    private let bundleID: String
    private let appBinaries: Set<String>
    private let received: @Sendable ([Incident]) -> Void

    /// `appBinaries`: the names of Redlamp's own executables and frameworks.
    public init(bundleID: String, appBinaries: Set<String>, received: @escaping @Sendable ([Incident]) -> Void) {
        self.bundleID = bundleID
        self.appBinaries = appBinaries
        self.received = received
    }

    public func start() {
        MXMetricManager.shared.add(self)
    }

    /// Called on a background queue.
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var incidents: [Incident] = []
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] where crash.metaData.bundleIdentifier == bundleID {
                if var incident = Incident(
                    metricKit: crash.jsonRepresentation(), kind: .crash, time: payload.timeStampEnd,
                    appBinaries: appBinaries,
                ) {
                    if let message = crash.exceptionReason?.composedMessage, !incident.reasons.contains(message) {
                        incident.reasons.append(message)
                    }
                    incidents.append(incident)
                }
            }
            for hang in payload.hangDiagnostics ?? [] where hang.metaData.bundleIdentifier == bundleID {
                if let incident = Incident(
                    metricKit: hang.jsonRepresentation(), kind: .hang, time: payload.timeStampBegin,
                    duration: hang.hangDuration.converted(to: .seconds).value, appBinaries: appBinaries,
                ) {
                    incidents.append(incident)
                }
            }
        }
        if !incidents.isEmpty {
            received(incidents)
        }
    }
}

public extension Incident {
    /// A diagnostic's JSON (`MXDiagnostic.jsonRepresentation()`): one call stack per thread, each
    /// frame's binary name and UUID, its offset in the binary's text segment (measured to be the
    /// offset, as the crash report's `imageOffset` is) and address, and the diagnostic's metadata.
    init?(metricKit json: Data, kind: Kind, time: Date, duration: TimeInterval? = nil, appBinaries: Set<String>) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tree = object["callStackTree"] as? [String: Any]
        else { return nil }
        let meta = object["diagnosticMetaData"] as? [String: Any] ?? [:]
        self.init(kind: kind, time: time, pid: Int32(meta["pid"] as? Int ?? -1), sources: [.metricKit])
        self.duration = duration
        if let version = meta["appVersion"] as? String {
            self.version = (meta["appBuildVersion"] as? String).map { "\(version) (\($0))" } ?? version
        }
        exception = Self.exceptionName(type: meta["exceptionType"] as? Int, signal: meta["signal"] as? Int)
        for key in ["terminationReason", "virtualMemoryRegionInfo"] {
            // The region list after the first line names mapped files.
            if let text = (meta[key] as? String)?.split(separator: "\n").first {
                reasons.append(String(text))
            }
        }
        var table: [Binary] = []
        var index: [String: Int] = [:]
        func binary(_ frame: [String: Any]) -> Int? {
            guard let name = frame["binaryName"] as? String,
                  let uuid = frame["binaryUUID"] as? String else { return nil }
            if let known = index[uuid] {
                return known
            }
            let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value
            let address = (frame["address"] as? NSNumber)?.uint64Value
            let base = offset.flatMap { offset in address.map { $0 &- offset } }
            table.append(Binary(name: name, uuid: uuid.uppercased(), base: base, inApp: appBinaries.contains(name)))
            index[uuid] = table.count - 1
            return table.count - 1
        }
        for stack in tree["callStacks"] as? [[String: Any]] ?? [] {
            var frames: [Frame] = []
            // A crash's stack is one chain of callers; a hang's is sampled, so it follows the
            // callers that took the most samples.
            var next = (stack["callStackRootFrames"] as? [[String: Any]])?.max(by: Self.fewerSamples)
            while let frame = next, frames.count < 512 {
                if let binary = binary(frame),
                   let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value {
                    frames.append(Frame(binary: binary, offset: offset))
                }
                next = (frame["subFrames"] as? [[String: Any]])?.max(by: Self.fewerSamples)
            }
            if !frames.isEmpty {
                threads.append(Thread(crashed: stack["threadAttributed"] as? Bool ?? false, frames: frames))
            }
        }
        binaries = table
    }

    private static func fewerSamples(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        (a["sampleCount"] as? Int ?? 0) < (b["sampleCount"] as? Int ?? 0)
    }
}
