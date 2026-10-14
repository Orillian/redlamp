import Darwin
import Foundation
import Synchronization

/// This session, kept on disk as it happens for the next launch to read if it ends without
/// quitting: a file of JSON lines in `Application Support/Redlamp/Feedback/Session`. Its first line
/// names the process; then come the activity, the photos opened, the folders shown and the hangs,
/// each line written as it happens, so a crash or a forced quit loses none of them; and a last
/// line once the session has quit. A report on a crash or a hang takes its activity from it, and
/// redacts with its photos and folders.
public final class SessionJournal: Sendable {
    /// The process a journal is for, and the Mac it ran on.
    public struct Header: Codable, Sendable, Hashable {
        public var pid: Int32
        /// When the kernel started the process, which tells it from a later one given the same ID.
        public var started: Date
        public var bundleID: String
        /// "0.3.2-alpha (431)".
        public var version: String
        /// A development build: Xcode and the regression suite end those without quitting.
        public var development: Bool
        /// When the Mac started up. A later start-up at the next launch means it restarted since,
        /// as a power cut, a kernel panic or a forced restart makes it.
        public var booted: Date

        public init(pid: Int32, started: Date, bundleID: String, version: String, development: Bool, booted: Date) {
            self.pid = pid
            self.started = started
            self.bundleID = bundleID
            self.version = version
            self.development = development
            self.booted = booted
        }

        /// This process's.
        public static func current(bundleID: String, version: String, development: Bool) -> Header? {
            let pid = getpid()
            guard let started = startTime(of: pid), let booted = bootTime() else { return nil }
            return Header(
                pid: pid, started: started, bundleID: bundleID, version: version, development: development,
                booted: booted,
            )
        }

        /// A process with its ID that started when it did is running.
        public var isRunning: Bool {
            Self.startTime(of: pid).map { abs($0.timeIntervalSince(started)) < 0.001 } ?? false
        }

        static func startTime(of pid: Int32) -> Date? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            // Without such a process, sysctl succeeds and writes nothing.
            guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
            return date(info.kp_proc.p_un.__p_starttime)
        }

        public static func bootTime() -> Date? {
            var time = timeval()
            var size = MemoryLayout<timeval>.stride
            guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return nil }
            return date(time)
        }

        private static func date(_ time: timeval) -> Date {
            Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
        }
    }

    /// A hang as the watchdog marks it, while it lasts and once it has ended.
    public struct Hang: Codable, Sendable, Hashable {
        public var began: Date
        /// How long it had lasted when it was marked.
        public var duration: TimeInterval
        public var ended: Bool

        public init(began: Date, duration: TimeInterval, ended: Bool) {
            self.began = began
            self.duration = duration
            self.ended = ended
        }
    }

    /// A line of the journal: one of its fields is set.
    struct Line: Codable {
        var header: Header?
        var event: ActivityLog.Event?
        /// The event's place in the session: a repeat of an event, or one replacing it, comes
        /// again with its number.
        var seq: Int?
        var photo: PhotoName?
        var folders: [String]?
        /// A hang comes again with each mark; the last for its start says how it went.
        var hang: Hang?
        var quit: Date?
    }

    /// What a rewrite keeps, and its descriptor.
    private struct State {
        var descriptor: Int32
        var lines = 0
        var events: [(seq: Int, event: ActivityLog.Event)] = []
        var photos: [PhotoName] = []
        var folders: [String] = []
        var hangs: [Hang] = []
    }

    public static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Redlamp/Feedback/Session")
    }

    /// Past this many lines the journal is rewritten with what it keeps: the latest events, as many
    /// as `ActivityLog` keeps, every photo and the folders, and the latest hangs.
    static let rewriteAfter = 4 * ActivityLog.defaultCapacity
    static let keptHangs = 50

    public let url: URL
    public let header: Header
    private let state: Mutex<State>

    /// Starts a journal for `header`'s session in `folder`.
    public init(header: Header, folder: URL = SessionJournal.folder) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "\(UUID().uuidString).jsonl")
        self.header = header
        // The person's own file names are in it.
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var state = State(descriptor: descriptor)
        Self.append(Line(header: header), to: &state)
        self.state = Mutex(state)
    }

    deinit {
        state.withLock { _ = close($0.descriptor) }
    }

    /// An event as `ActivityLog` has it now, at its place in the session.
    public func record(_ event: ActivityLog.Event, seq: Int) {
        write(Line(event: event, seq: seq)) { state in
            if state.events.last?.seq == seq {
                state.events[state.events.count - 1].event = event
            } else {
                state.events.append((seq, event))
                state.events.removeFirst(max(0, state.events.count - ActivityLog.defaultCapacity))
            }
        }
    }

    public func photo(_ photo: PhotoName) {
        write(Line(photo: photo)) { $0.photos.append(photo) }
    }

    /// The folders the app shows now: the open folder and the working set.
    public func folders(_ folders: [String]) {
        write(Line(folders: folders)) { $0.folders = folders }
    }

    public func hang(_ hang: Hang) {
        write(Line(hang: hang)) { state in
            state.hangs.removeAll { $0.began == hang.began }
            state.hangs.append(hang)
            state.hangs.removeFirst(max(0, state.hangs.count - Self.keptHangs))
        }
    }

    /// The session has quit: its last line.
    public func quit(at time: Date = Date()) {
        write(Line(quit: time)) { _ in }
    }

    private func write(_ line: Line, keeping keep: (inout State) -> Void) {
        state.withLock { state in
            keep(&state)
            Self.append(line, to: &state)
            if state.lines > Self.rewriteAfter {
                rewrite(&state)
            }
        }
    }

    /// Replaces the journal with a shorter one holding what it keeps, renamed into place.
    private func rewrite(_ state: inout State) {
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent)")
        let descriptor = open(temporary.path, O_WRONLY | O_APPEND | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return }
        var fresh = State(
            descriptor: descriptor, events: state.events, photos: state.photos, folders: state.folders,
            hangs: state.hangs,
        )
        let lines = [Line(header: header)] + state.photos.map { Line(photo: $0) }
            + (state.folders.isEmpty ? [] : [Line(folders: state.folders)])
            + state.hangs.map { Line(hang: $0) } + state.events.map { Line(event: $0.event, seq: $0.seq) }
        for line in lines {
            Self.append(line, to: &fresh)
        }
        guard rename(temporary.path, url.path) == 0 else {
            close(descriptor)
            unlink(temporary.path)
            return
        }
        close(state.descriptor)
        state = fresh
    }

    private static func append(_ line: Line, to state: inout State) {
        guard var data = try? JSONEncoder().encode(line) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(state.descriptor, bytes.baseAddress! + written, bytes.count - written)
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { return }
                written += count
            }
        }
        state.lines += 1
    }
}

/// A session as its journal tells it, read at a later launch.
public struct PreviousSession: Sendable {
    public var url: URL
    public var header: SessionJournal.Header
    /// Its activity, oldest first: the latest events, as many as `ActivityLog` keeps.
    public var events: [ActivityLog.Event]
    public var photos: [PhotoName]
    public var folders: [String]
    /// Its hangs in the order they began. One that hadn't ended was going on as the session ended.
    public var hangs: [SessionJournal.Hang]
    /// When it quit; `nil` when it ended some other way.
    public var quit: Date?
    /// When its journal was last written: about when the session ended, if it didn't quit.
    public var lastWritten: Date?

    /// The journal at `url` as far as it was written; a crash can leave its last line cut short.
    public static func read(_ url: URL) -> PreviousSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        var header: SessionJournal.Header?
        var events: [Int: ActivityLog.Event] = [:]
        var photos: [PhotoName] = []
        var folders: [String] = []
        var hangs: [Date: SessionJournal.Hang] = [:]
        var quit: Date?
        for text in data.split(separator: 0x0A) {
            guard let line = try? decoder.decode(SessionJournal.Line.self, from: text) else { continue }
            header = header ?? line.header
            if let event = line.event, let seq = line.seq {
                events[seq] = event
            }
            if let photo = line.photo, !photos.contains(photo) {
                photos.append(photo)
            }
            folders = line.folders ?? folders
            if let hang = line.hang {
                hangs[hang.began] = hang
            }
            quit = line.quit ?? quit
        }
        guard let header else { return nil }
        return PreviousSession(
            url: url,
            header: header,
            events: events.sorted { $0.key < $1.key }.suffix(ActivityLog.defaultCapacity).map(\.value),
            photos: photos,
            folders: folders,
            hangs: hangs.values.sorted { $0.began < $1.began },
            quit: quit,
            lastWritten: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        )
    }

    /// The sessions journaled in `folder` that have ended, whichever way.
    public static func ended(in folder: URL = SessionJournal.folder) -> [PreviousSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap(read)
            .filter { !$0.header.isRunning }
            .sorted { $0.header.started < $1.header.started }
    }

    /// The hang it was in as it ended.
    public var openHang: SessionJournal.Hang? {
        hangs.last.flatMap { $0.ended ? nil : $0 }
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
