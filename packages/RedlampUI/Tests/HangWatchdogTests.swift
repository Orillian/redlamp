import Foundation
import Synchronization
import Testing
@testable import RedlampUI

/// When the watchdog marks a hang: once the main thread has been away from its run loop past the
/// threshold, at each tick while it lasts, and with its length once it's back.
struct HangWatchdogTests {
    static let second: UInt64 = 1_000_000_000
    static let threshold = 2 * second
    static let date = Date(timeIntervalSince1970: 1_791_960_000)

    /// The run loop's stamp: when it last turned, and whether it went to wait.
    static func stamp(_ seconds: Double, waiting: Bool = false) -> UInt64 {
        UInt64(seconds * Double(second)) << 1 | (waiting ? 1 : 0)
    }

    static func tick(
        _ watch: inout HangWatchdog.Watch, stalls: [HangWatchdog.Stall] = [], stamp: UInt64, now: Double,
    ) -> [SessionJournal.Hang] {
        HangWatchdog.tick(
            &watch, stalls: stalls, stamp: stamp, now: UInt64(now * Double(second)), date: date, threshold: threshold,
        )
    }

    @Test func `a hang is marked past the threshold, while it lasts, and once it's back`() throws {
        var watch = HangWatchdog.Watch()
        #expect(Self.tick(&watch, stamp: Self.stamp(10), now: 11).isEmpty)

        let first = try #require(Self.tick(&watch, stamp: Self.stamp(10), now: 12.5).first)
        #expect(first == SessionJournal.Hang(began: Self.date - 2.5, duration: 2.5, ended: false))
        let lasting = Self.tick(&watch, stamp: Self.stamp(10), now: 13.5)
        #expect(lasting == [SessionJournal.Hang(began: first.began, duration: 3.5, ended: false)])

        let back = Self.tick(
            &watch, stalls: [HangWatchdog.Stall(began: 10 * Self.second, length: 4 * Self.second)],
            stamp: Self.stamp(14.2), now: 14.5,
        )
        #expect(back == [SessionJournal.Hang(began: first.began, duration: 4, ended: true)])
        #expect(watch.open == nil)
        #expect(Self.tick(&watch, stamp: Self.stamp(14.3), now: 15.5).isEmpty)
    }

    @Test func `waiting for events isn't a hang`() {
        var watch = HangWatchdog.Watch()
        #expect(Self.tick(&watch, stamp: Self.stamp(20, waiting: true), now: 40).isEmpty)
        #expect(Self.tick(&watch, stamp: 0, now: 40).isEmpty, "the run loop hasn't turned yet")
    }

    @Test func `a stall over between two ticks is marked once it's back`() {
        var watch = HangWatchdog.Watch()
        let marks = Self.tick(
            &watch, stalls: [HangWatchdog.Stall(began: 41 * Self.second, length: 2_400_000_000)],
            stamp: Self.stamp(43.4), now: 43.9,
        )
        #expect(marks == [SessionJournal.Hang(began: Self.date - 2.9, duration: 2.4, ended: true)])
    }

    @Test func `a stall the main thread has recorded isn't opened again before its stamp is replaced`() {
        var watch = HangWatchdog.Watch()
        let marks = Self.tick(
            &watch, stalls: [HangWatchdog.Stall(began: 50 * Self.second, length: 3 * Self.second)],
            stamp: Self.stamp(50), now: 53,
        )
        #expect(marks.map(\.ended) == [true])
        #expect(watch.open == nil)
    }

    final class Marks: Sendable {
        let hangs = Mutex<[SessionJournal.Hang]>([])
    }

    @MainActor
    @Test func `the main thread kept from its run loop is a hang`() async throws {
        let marks = Marks()
        let watchdog = HangWatchdog(threshold: .milliseconds(300), interval: .milliseconds(50)) { hang in
            marks.hangs.withLock { $0.append(hang) }
        }
        watchdog.start()
        defer { watchdog.stop() }
        try await Task.sleep(for: .milliseconds(200))
        usleep(800_000)
        try await Task.sleep(for: .milliseconds(400))

        let hangs = marks.hangs.withLock { $0 }
        let ended = try #require(hangs.last { $0.ended && $0.duration >= 0.75 }, "\(hangs)")
        #expect(ended.duration < 3)
        #expect(hangs.contains { !$0.ended && $0.began == ended.began }, "marked while it lasted: \(hangs)")
    }
}
