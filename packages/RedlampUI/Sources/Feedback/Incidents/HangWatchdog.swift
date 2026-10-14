import CoreFoundation
import Darwin
import Foundation
import Synchronization

/// Watches the main thread for hangs, which MetricKit doesn't report on the Mac (measured 14 October
/// 2026). The main run loop stamps each turn; a timer on another thread marks a hang once the main
/// thread has been away from its run loop for `threshold`, again at each tick while it lasts, and
/// with its length once it's back, so the next launch knows of a hang even when the session ended
/// in it, as one does when a stuck Redlamp is force quit. Time is the uptime clock's, which stops
/// while the Mac sleeps.
public final class HangWatchdog: Sendable {
    /// A stretch the main thread spent away from its run loop, in nanoseconds of uptime.
    struct Stall: Equatable, Sendable {
        var began: UInt64
        var length: UInt64
    }

    /// What the timer keeps between ticks: the hang going on, by its stamp, and when it began.
    struct Watch: Sendable {
        var open: (stamp: UInt64, began: Date)?
    }

    /// What the main thread and the timer share: when the run loop last turned, shifted left
    /// once with the low bit set while it waits, and the stalls it has come back from.
    private final class Shared: Sendable {
        let stamp = Atomic<UInt64>(0)
        let stalls = Mutex<[Stall]>([])
    }

    private let threshold: UInt64
    private let interval: DispatchTimeInterval
    private let marked: @Sendable (SessionJournal.Hang) -> Void
    /// Both are safe to use from any thread.
    private struct Running: @unchecked Sendable {
        let observer: CFRunLoopObserver
        let timer: DispatchSourceTimer
    }

    private let shared = Shared()
    private let watch = Mutex(Watch())
    private let running = Mutex<Running?>(nil)

    /// `marked` is called on the watchdog's own queue with each mark of each hang.
    public init(
        threshold: Duration = .seconds(2), interval: Duration = .seconds(1),
        marked: @escaping @Sendable (SessionJournal.Hang) -> Void,
    ) {
        self.threshold = Self.nanoseconds(threshold)
        self.interval = .nanoseconds(Int(Self.nanoseconds(interval)))
        self.marked = marked
    }

    public func start() {
        stop()
        let shared = shared
        let threshold = threshold
        let activities: [CFRunLoopActivity] = [.beforeTimers, .beforeSources, .beforeWaiting, .afterWaiting]
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, activities.reduce(0) { $0 | $1.rawValue }, true, 0,
        ) { _, activity in
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let previous = shared.stamp.load(ordering: .relaxed)
            let last = previous >> 1
            if previous & 1 == 0, last > 0, now > last, now - last >= threshold {
                shared.stalls.withLock { $0.append(Stall(began: last, length: now - last)) }
            }
            shared.stamp.store(now << 1 | (activity == .beforeWaiting ? 1 : 0), ordering: .relaxed)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "app.redlamp.hang-watchdog"))
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.check()
        }
        timer.resume()
        let started = Running(observer: observer!, timer: timer)
        running.withLock { $0 = started }
    }

    /// Stops watching, once the hangs the main thread has come back from are marked.
    public func stop() {
        let current = running.withLock { running in
            defer { running = nil }
            return running
        }
        guard let current else { return }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), current.observer, .commonModes)
        current.timer.cancel()
        check(opening: false)
    }

    private func check(opening: Bool = true) {
        // The stalls first: one the main thread records after this has its stamp replaced too.
        let stalls = shared.stalls.withLock { stalls in
            defer { stalls.removeAll() }
            return stalls
        }
        let stamp = opening ? shared.stamp.load(ordering: .relaxed) : 0
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let marks = watch.withLock { watch in
            Self.tick(&watch, stalls: stalls, stamp: stamp, now: now, date: Date(), threshold: threshold)
        }
        for mark in marks {
            marked(mark)
        }
    }

    /// A tick's marks: each stall the main thread has come back from, then the hang it's in, if
    /// it has been away from its run loop for `threshold` and not waiting.
    static func tick(
        _ watch: inout Watch, stalls: [Stall], stamp: UInt64, now: UInt64, date: Date, threshold: UInt64,
    ) -> [SessionJournal.Hang] {
        func began(_ stamp: UInt64) -> Date {
            watch.open.flatMap { $0.stamp == stamp ? $0.began : nil } ?? date - seconds(now - stamp)
        }
        var marks: [SessionJournal.Hang] = []
        for stall in stalls {
            marks.append(SessionJournal.Hang(began: began(stall.began), duration: seconds(stall.length), ended: true))
            if watch.open?.stamp == stall.began {
                watch.open = nil
            }
        }
        let last = stamp >> 1
        guard stamp & 1 == 0, last > 0, now > last, now - last >= threshold,
              !stalls.contains(where: { $0.began == last })
        else { return marks }
        let hang = SessionJournal.Hang(began: began(last), duration: seconds(now - last), ended: false)
        watch.open = (last, hang.began)
        marks.append(hang)
        return marks
    }

    private static func seconds(_ nanoseconds: UInt64) -> TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let (seconds, attoseconds) = duration.components
        return UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds) / 1_000_000_000)
    }
}
