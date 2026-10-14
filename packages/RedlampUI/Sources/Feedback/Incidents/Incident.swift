import Foundation

/// A crash or a hang in an earlier session, as its report offers it: what happened, the threads'
/// stacks, and where each came from. Only what helps fix it is kept: no identifiers, registers or
/// memory map, and binaries by name rather than path.
public struct Incident: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case crash, hang
    }

    public enum Source: String, Codable, Sendable {
        /// The `.ips` file macOS writes (`MacCrashReport`).
        case crashReport
        case metricKit
        /// Redlamp's own `HangWatchdog`.
        case watchdog
    }

    public struct Binary: Codable, Sendable, Hashable {
        public var name: String
        public var uuid: String
        /// Where it was loaded; with a frame's offset, enough to symbolicate the frame.
        public var base: UInt64?
        /// Part of Redlamp, so named from the release's dSYMs rather than by the Mac.
        public var inApp: Bool
    }

    public struct Frame: Codable, Sendable, Hashable {
        /// Its index in `binaries`.
        public var binary: Int
        /// From the start of the binary's text segment.
        public var offset: UInt64
        /// As the Mac named it: Apple's frames, and Redlamp's in a build that isn't stripped.
        public var symbol: String?
    }

    public struct Thread: Codable, Sendable, Hashable {
        public var name: String?
        public var queue: String?
        public var crashed: Bool
        public var frames: [Frame]
    }

    public var id = UUID()
    public var kind: Kind
    /// When it crashed, or when the hang began.
    public var time: Date
    public var pid: Int32
    /// "0.3.2-alpha (431)".
    public var version: String?
    /// "EXC_BAD_ACCESS (SIGSEGV)".
    public var exception: String?
    /// The termination reason, an Objective-C exception's message, and what the app said as it ended.
    public var reasons: [String] = []
    /// How long a hang lasted: until it ended, or until the session did.
    public var duration: TimeInterval?
    /// The session ended during the hang, as it does when a stuck Redlamp is force quit.
    public var endedSession = false
    public var threads: [Thread] = []
    public var binaries: [Binary] = []
    /// Where an Objective-C exception was raised, which the crashed thread's stack no longer shows.
    public var exceptionBacktrace: [Frame]?
    public var sources: [Source]

    public init(kind: Kind, time: Date, pid: Int32, sources: [Source]) {
        self.kind = kind
        self.time = time
        self.pid = pid
        self.sources = sources
    }

    /// "Redlamp quit unexpectedly", "Redlamp stopped responding".
    public var headline: String {
        kind == .crash ? "Redlamp quit unexpectedly" : "Redlamp stopped responding"
    }

    /// The first of the crashed thread's frames in Redlamp's own code, which is where a fix starts.
    public var culprit: String? {
        let thread = threads.first(where: \.crashed) ?? threads.first
        guard let frame = thread?.frames
            .first(where: { binaries.indices.contains($0.binary) && binaries[$0.binary].inApp })
        else { return nil }
        return binaries[frame.binary].name
    }

    /// The issue's title before the person changes it: "Crash: EXC_BAD_ACCESS (SIGSEGV) in
    /// RedlampEngine", "Hang: 14 s, then Redlamp was closed".
    public var suggestedTitle: String {
        switch kind {
        case .crash:
            let what = exception ?? "Redlamp quit unexpectedly"
            return "Crash: " + what + (culprit.map { " in \($0)" } ?? "")
        case .hang:
            let length = duration.map { Self.seconds($0) } ?? "the main thread stopped"
            return "Hang: " + length + (endedSession ? ", then Redlamp was closed" : "")
        }
    }

    /// "14 s", "2 min 5 s".
    static func seconds(_ interval: TimeInterval) -> String {
        let seconds = max(1, Int(interval.rounded()))
        return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min" + (seconds % 60 == 0 ? "" : " \(seconds % 60) s")
    }

    /// Mach exception and signal names, as `sys/exception_types.h` and `sys/signal.h` have them.
    static func exceptionName(type: Int?, signal: Int?) -> String? {
        let types = [
            1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION",
            5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL", 9: "EXC_RPC_ALERT",
            10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY",
        ]
        let signals = [
            1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 7: "SIGEMT",
            8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 12: "SIGSYS", 13: "SIGPIPE", 14: "SIGALRM",
            15: "SIGTERM",
        ]
        let typeName = type.map { types[$0] ?? "exception \($0)" }
        let signalName = signal.map { signals[$0] ?? "signal \($0)" }
        switch (typeName, signalName) {
        case let (type?, signal?): return "\(type) (\(signal))"
        case let (type?, nil): return type
        case let (nil, signal?): return signal
        case (nil, nil): return nil
        }
    }

    /// Adds `other`'s stacks and reasons where this one has none: the crash report names more
    /// than MetricKit does, so it goes first.
    public func merged(with other: Incident) -> Incident {
        var merged = self
        // Frames point into their own incident's binaries, so they come across together.
        if merged.threads.isEmpty {
            merged.threads = other.threads
            merged.binaries = other.binaries
            merged.exceptionBacktrace = other.exceptionBacktrace
        }
        merged.exception = merged.exception ?? other.exception
        merged.reasons += other.reasons.filter { !merged.reasons.contains($0) }
        merged.duration = merged.duration ?? other.duration
        merged.version = merged.version ?? other.version
        merged.sources += other.sources.filter { !merged.sources.contains($0) }
        return merged
    }
}
