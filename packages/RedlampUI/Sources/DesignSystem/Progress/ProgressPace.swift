import Foundation

/// Why the Mac has paused a stage of long work, as the window says it.
@_spi(Harness) public enum PauseReason: String, Sendable, Hashable, CaseIterable {
    case lowPower
    case heat

    /// What the progress line says in place of the time left.
    public var short: String {
        switch self {
        case .lowPower: "Low Power Mode is on"
        case .heat: "The Mac is cooling down"
        }
    }
}

/// How a stage of long work is going, as its progress line shows it.
@_spi(Harness) public enum Pace: Sendable, Hashable {
    /// The stage's first seconds, or before 1% of it: the rate isn't steady yet, so nothing is shown.
    case measuring
    case steady(perSecond: Double, secondsLeft: TimeInterval)
    /// Nothing done in the last minute, and the Mac hasn't said why.
    case idle
    /// Nothing done for a while, because the Mac pauses the work.
    case paused(PauseReason)

    /// "42 a second · about 12 minutes left", or what stands in their place; empty while measuring.
    public var parts: [String] {
        switch self {
        case .measuring: []
        case let .steady(rate, left): [ProgressText.rate(rate), "\(ProgressText.timeLeft(left)) left"]
        case .idle: ["Nothing done in the last minute"]
        case let .paused(reason): ["Paused", reason.short]
        }
    }
}

/// Photos a second over a stretch of the chart, and whether the Mac paused the work in it.
@_spi(Harness) public struct ThroughputBin: Sendable, Hashable {
    /// `nil` before the stage started.
    public var perSecond: Double?
    public var paused: PauseReason?

    public init(perSecond: Double?, paused: PauseReason? = nil) {
        self.perSecond = perSecond
        self.paused = paused
    }
}

/// A stage's progress over time, from which its rate, its time left and its chart are worked out (LIB-52): the rate
/// from the last minute, nothing in the stage's first 10 seconds or before 1% of it, and Paused once nothing has
/// moved for 10 seconds while the Mac pauses the work. Times are seconds on any clock that only goes forward.
@_spi(Harness) public struct RateMeter: Sendable, Hashable {
    public struct Sample: Sendable, Hashable {
        public var time: TimeInterval
        public var done: Int
        public var paused: PauseReason?
    }

    /// When the stage started.
    public let start: TimeInterval
    public private(set) var samples: [Sample]

    /// The stretch the rate is measured over.
    public static let window: TimeInterval = 60
    /// How long a stage runs before its rate is shown.
    public static let settling: TimeInterval = 10
    /// The share of a stage done before its rate is shown.
    public static let settlingShare = 0.01
    /// How long nothing moves while paused before Paused is shown.
    public static let pauseAfter: TimeInterval = 10
    /// What the chart shows.
    public static let history: TimeInterval = 600

    public init(start: TimeInterval, done: Int = 0) {
        self.start = start
        samples = [Sample(time: start, done: done, paused: nil)]
    }

    /// Records the stage's count at `time`; record at least every few seconds, and whenever the Mac pauses the work
    /// or lets it carry on, so the chart shades the pause where it was.
    public mutating func record(_ done: Int, at time: TimeInterval, pausedBy paused: PauseReason? = nil) {
        guard time >= (samples.last?.time ?? start) else { return }
        samples.append(Sample(time: time, done: done, paused: paused))
        let oldest = time - Self.history - Self.window
        if let keep = samples.lastIndex(where: { $0.time <= oldest }), keep > 0 {
            samples.removeFirst(keep)
        }
    }

    /// How the stage is going at `now`, of `total`, while the Mac pauses it for `paused`, if it does.
    public func pace(total: Int, now: TimeInterval, pausedBy paused: PauseReason?) -> Pace {
        guard let last = samples.last else { return .measuring }
        if let paused, now - lastMoved >= Self.pauseAfter {
            return .paused(paused)
        }
        guard total > 0, now - start >= Self.settling,
              Double(last.done) >= Double(total) * Self.settlingShare else { return .measuring }
        let base = sample(at: now - Self.window) ?? samples[0]
        let span = now - base.time
        guard span > 0 else { return .measuring }
        let rate = Double(last.done - base.done) / span
        guard rate > 0 else { return .idle }
        return .steady(perSecond: rate, secondsLeft: Double(max(total - last.done, 0)) / rate)
    }

    /// When the count last changed: the first sample that reached the latest count.
    private var lastMoved: TimeInterval {
        guard let last = samples.last else { return start }
        var index = samples.count - 1
        while index > 0, samples[index - 1].done == last.done {
            index -= 1
        }
        return index == 0 ? start : samples[index].time
    }

    /// Photos a second over the last ten minutes in `bins` equal stretches, oldest first.
    public func throughput(now: TimeInterval, bins: Int = 60) -> [ThroughputBin] {
        guard bins > 0 else { return [] }
        let width = Self.history / Double(bins)
        return (0 ..< bins).map { bin in
            let from = now - Self.history + Double(bin) * width
            let to = from + width
            guard to > start else { return ThroughputBin(perSecond: nil) }
            let begin = max(from, start)
            let rate = Double(done(at: to) - done(at: begin)) / max(to - begin, .ulpOfOne)
            var paused = sample(at: begin)?.paused
            var next = index(after: begin)
            while paused == nil, next < samples.count, samples[next].time < to {
                paused = samples[next].paused
                next += 1
            }
            return ThroughputBin(perSecond: max(rate, 0), paused: paused)
        }
    }

    /// The count at `time`, as the last sample at or before it gave it.
    private func done(at time: TimeInterval) -> Int {
        sample(at: time)?.done ?? samples.first?.done ?? 0
    }

    private func sample(at time: TimeInterval) -> Sample? {
        let index = index(after: time)
        return index > 0 ? samples[index - 1] : nil
    }

    /// The place of the first sample after `time`, or the count when there's none: samples are in time order.
    private func index(after time: TimeInterval) -> Int {
        var low = 0, high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].time <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}

/// Counts, rates and durations in the words the progress screens use.
@_spi(Harness) public enum ProgressText {
    /// `20,000`, whatever the locale, as the Lightroom report writes counts.
    public static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    /// `1 photo`, `48,212 photos`.
    public static func count(_ value: Int, _ noun: String, plural: String? = nil) -> String {
        "\(count(value)) \(value == 1 ? noun : plural ?? noun + "s")"
    }

    /// "42 a second", "4.2 a second".
    public static func rate(_ perSecond: Double) -> String {
        if perSecond >= 9.5 {
            return "\(count(Int(perSecond.rounded()))) a second"
        }
        let tenths = (perSecond * 10).rounded() / 10
        return tenths < 0.1 ? "less than 1 a second" : "\(tenths.formatted(.number.locale(Locale(identifier: "en_US")))) a second"
    }

    /// The time left, rounded so it doesn't flicker: "less than a minute", "about 12 minutes", then hours and
    /// minutes to the nearest five, "about 1 h 45 min".
    public static func timeLeft(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "less than a minute"
        }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return minutes == 1 ? "about a minute" : "about \(minutes) minutes"
        }
        let rounded = Int((Double(minutes) / 5).rounded()) * 5
        let hours = rounded / 60, rest = rounded % 60
        return rest == 0 ? "about \(hours) h" : "about \(hours) h \(rest) min"
    }

    /// A measured time, as the log writes it: "2.4 s", "12 s", "7 min 12 s", "1 h 12 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 9.95 {
            let tenths = (max(seconds, 0) * 10).rounded() / 10
            return "\(tenths.formatted(.number.locale(Locale(identifier: "en_US")))) s"
        }
        let whole = Int(seconds.rounded())
        if whole < 60 {
            return "\(whole) s"
        }
        if whole < 3600 {
            return whole % 60 == 0 ? "\(whole / 60) min" : "\(whole / 60) min \(whole % 60) s"
        }
        let minutes = (whole + 30) / 60
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// A time said in a sentence: "12 seconds", "41 minutes", "1 h 25 min".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        if whole < 60 {
            return count(whole, "second")
        }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return count(minutes, "minute")
        }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
