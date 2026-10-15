import Foundation

/// What happened in this session, oldest first, so a report can say what someone did before
/// sending it.
///
/// It stays in memory and in the session's journal, never sent unless a report is, and what it
/// writes itself never names a file: photos are Photo A, Photo B and so on, in the order they were
/// opened, and their file names are kept apart for a report that asks for them. Messages it copies
/// from the UI can mention one, so reports redact them. Turned off (`ActivityLogSetting`), it
/// records nothing and forgets what it had; photos still get their aliases, which a report names
/// them by, but the journal isn't told them.
@MainActor
public final class ActivityLog {
    public struct Event: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case photo, tool, panel, action, edit, mask, view, message, error, export, model, system
        }

        public let time: Date
        public let kind: Kind
        public internal(set) var text: String
        /// How many times it happened in a row: a run of the same event is one entry.
        public internal(set) var count = 1
        /// Events with the same key a moment apart replace each other, as a pinch's zoom levels do.
        let key: String?

        private enum CodingKeys: String, CodingKey {
            case time, kind, text, count
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decode(Date.self, forKey: .time)
            kind = try container.decode(Kind.self, forKey: .kind)
            text = try container.decode(String.self, forKey: .text)
            count = try container.decode(Int.self, forKey: .count)
            key = nil
        }

        init(time: Date, kind: Kind, text: String, key: String?) {
            self.time = time
            self.kind = kind
            self.text = text
            self.key = key
        }
    }

    public nonisolated static let defaultCapacity = 500

    public private(set) var events: [Event] = []
    /// The folders the app shows: the open folder and the working set, to redact from a report.
    public var folders: [String] = [] {
        didSet {
            if isOn, folders != oldValue {
                journal?.folders(folders)
            }
        }
    }

    /// Off, nothing is recorded, and the events and the journal's activity are forgotten. Back on, the journal is told
    /// the photos and folders again, for the next launch to redact a crash's report with.
    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            if isOn {
                journal.map(fill)
            } else {
                events = []
                journal?.forgetActivity()
            }
        }
    }

    /// Keeps the session's activity on disk as it happens, for a report at the next launch if it
    /// doesn't quit. What was recorded before it's set goes to it first.
    public var journal: SessionJournal? {
        didSet {
            if isOn, let journal {
                fill(journal)
            }
        }
    }

    private let capacity: Int
    private let now: () -> Date
    private var aliases: [URL: String] = [:]
    private var fileNames: [String] = []
    /// How many events have been added this session, the first of `events` among them.
    private var appended = 0

    public init(
        capacity: Int = ActivityLog.defaultCapacity, isOn: Bool = true, now: @escaping () -> Date = Date.init,
    ) {
        self.capacity = capacity
        self.isOn = isOn
        self.now = now
    }

    /// One that follows `setting`, turned on and off with it.
    public convenience init(following setting: ActivityLogSetting) {
        self.init(isOn: setting.isOn)
        setting.onChange { [weak self] in self?.isOn = $0 }
    }

    /// Writes what the log holds to `journal`: its events, the photos and the folders.
    private func fill(_ journal: SessionJournal) {
        let first = appended - events.count
        for (index, event) in events.enumerated() {
            journal.record(event, seq: first + index)
        }
        for photo in photoNames {
            journal.photo(PhotoName(alias: photo.alias, fileName: photo.fileName))
        }
        if !folders.isEmpty {
            journal.folders(folders)
        }
    }

    /// Adds an event. With `key`, it replaces the last event when that has the same key and is
    /// less than `window` seconds old; without one, a repeat of the last event counts it again.
    public func record(
        _ kind: Event.Kind,
        _ text: String,
        replacing key: String? = nil,
        within window: TimeInterval = 2,
    ) {
        guard isOn else { return }
        let time = now()
        defer { journal?.record(events[events.count - 1], seq: appended - 1) }
        if var last = events.last {
            if let key, last.key == key, time.timeIntervalSince(last.time) < window {
                events[events.count - 1] = Event(time: time, kind: kind, text: text, key: key)
                return
            }
            if key == nil, last.key == nil, last.kind == kind, last.text == text {
                last.count += 1
                events[events.count - 1] = last
                return
            }
        }
        events.append(Event(time: time, kind: kind, text: text, key: key))
        appended += 1
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    public func events(since date: Date) -> [Event] {
        events.filter { $0.time >= date }
    }

    /// "Photo A", "Photo B", … "Photo AA", by the order photos were first opened this session.
    public func alias(for url: URL) -> String {
        if let alias = aliases[url] {
            return alias
        }
        let alias = "Photo \(Self.letters(aliases.count))"
        aliases[url] = alias
        fileNames.append(url.lastPathComponent)
        if isOn {
            journal?.photo(PhotoName(alias: alias, fileName: url.lastPathComponent))
        }
        return alias
    }

    /// Each alias with its photo's file name, in the order they were opened.
    public var photoNames: [(alias: String, fileName: String)] {
        fileNames.enumerated().map { ("Photo \(Self.letters($0.offset))", $0.element) }
    }

    /// 0 is A, 25 is Z, 26 is AA.
    static func letters(_ index: Int) -> String {
        var index = index
        var letters = ""
        repeat {
            letters = String(UnicodeScalar(UInt8(65 + index % 26))) + letters
            index = index / 26 - 1
        } while index >= 0
        return letters
    }
}
