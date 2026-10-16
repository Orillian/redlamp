import Foundation
import Testing
@testable @_spi(Harness) import RedlampUI

/// The rate and time left a progress screen shows, and its chart, on made-up clocks (LIB-52).
struct ProgressPaceTests {
    /// A stage of `total` started at 0 that does `rate` a second, recorded every `every` seconds until `until`.
    private func meter(rate: Double, until: TimeInterval, every: TimeInterval = 5) -> RateMeter {
        var meter = RateMeter(start: 0)
        for time in stride(from: every, through: until, by: every) {
            meter.record(Int(rate * time), at: time)
        }
        return meter
    }

    @Test func `nothing is shown in a stage's first 10 seconds`() {
        var meter = RateMeter(start: 100)
        meter.record(500, at: 105)
        meter.record(900, at: 109)
        #expect(meter.pace(total: 10000, now: 109.9, pausedBy: nil) == .measuring)
        meter.record(1000, at: 110)
        guard case let .steady(rate, _) = meter.pace(total: 10000, now: 110, pausedBy: nil) else {
            Issue.record("the rate isn't shown once the stage has run 10 seconds")
            return
        }
        #expect(rate == 100)
    }

    @Test func `nothing is shown before 1% of the stage is done`() {
        let meter = meter(rate: 20, until: 45)
        #expect(meter.pace(total: 100_000, now: 45, pausedBy: nil) == .measuring)
        #expect(meter.pace(total: 90000, now: 45, pausedBy: nil) == .steady(perSecond: 20, secondsLeft: 4455))
    }

    @Test func `the rate comes from the last minute`() {
        var meter = RateMeter(start: 0)
        for time in stride(from: 10.0, through: 120, by: 10) {
            meter.record(Int(10 * time), at: time)
        }
        for time in stride(from: 130.0, through: 180, by: 10) {
            meter.record(1200 + Int(30 * (time - 120)), at: time)
        }
        // 1,200 at 120 s, then 30 a second: the last minute's rate, not the stage's average of 16.7.
        #expect(meter.pace(total: 10000, now: 180, pausedBy: nil) == .steady(perSecond: 30, secondsLeft: 7000.0 / 30))
    }

    @Test func `the rate falls while nothing is recorded`() {
        var meter = meter(rate: 10, until: 120)
        meter.record(1200, at: 120)
        // Thirty seconds without a sample: half the last minute did nothing.
        #expect(meter.pace(total: 3000, now: 150, pausedBy: nil) == .steady(perSecond: 5, secondsLeft: 360))
    }

    @Test func `a minute with nothing done and no reason is idle, not paused`() {
        var meter = meter(rate: 10, until: 60)
        meter.record(600, at: 90)
        meter.record(600, at: 125)
        #expect(meter.pace(total: 3000, now: 125, pausedBy: nil) == .idle)
    }

    @Test func `Paused shows once nothing has moved for 10 seconds while the Mac pauses the work`() {
        var meter = meter(rate: 10, until: 100)
        meter.record(1000, at: 104, pausedBy: .lowPower)
        guard case .steady = meter.pace(total: 5000, now: 104, pausedBy: .lowPower) else {
            Issue.record("Paused shows before 10 seconds without progress")
            return
        }
        #expect(meter.pace(total: 5000, now: 109.9, pausedBy: .lowPower) != .paused(.lowPower))
        #expect(meter.pace(total: 5000, now: 110, pausedBy: .lowPower) == .paused(.lowPower))
        #expect(meter.pace(total: 5000, now: 140, pausedBy: .heat) == .paused(.heat))
    }

    @Test func `a stage paused from its start shows Paused after 10 seconds`() {
        let meter = RateMeter(start: 50)
        #expect(meter.pace(total: 12400, now: 55, pausedBy: .lowPower) == .measuring)
        #expect(meter.pace(total: 12400, now: 60, pausedBy: .lowPower) == .paused(.lowPower))
    }

    @Test func `the progress line shows nothing while measuring and Paused with why`() {
        #expect(Pace.measuring.parts.isEmpty)
        #expect(Pace.steady(perSecond: 42, secondsLeft: 720).parts == ["42 a second", "about 12 minutes left"])
        #expect(Pace.paused(.lowPower).parts == ["Paused", "Low Power Mode is on"])
        #expect(Pace.paused(.heat).parts == ["Paused", "The Mac is cooling down"])
    }

    @Test(arguments: [
        (0.0, "less than a minute"), (59, "less than a minute"), (60, "about a minute"), (89, "about a minute"),
        (90, "about 2 minutes"), (720, "about 12 minutes"), (3569, "about 59 minutes"), (3575, "about 1 h"),
        (6240, "about 1 h 45 min"), (6363, "about 1 h 45 min"), (6420, "about 1 h 45 min"), (10680, "about 3 h"),
    ])
    func `time left is rounded to less than a minute, minutes, then hours and minutes`(
        seconds: Double, text: String,
    ) {
        #expect(ProgressText.timeLeft(seconds) == text)
    }

    @Test(arguments: [
        (2.4, "2.4 s"), (12.0, "12 s"), (60, "1 min"), (432, "7 min 12 s"), (665, "11 min 5 s"),
        (4320, "1 h 12 min"), (7200, "2 h"),
    ])
    func `measured times read as the log writes them`(seconds: Double, text: String) {
        #expect(ProgressText.duration(seconds) == text)
    }

    @Test func `rates and counts read the same whatever the locale`() {
        #expect(ProgressText.rate(42.4) == "42 a second")
        #expect(ProgressText.rate(6.14) == "6.1 a second")
        #expect(ProgressText.rate(0.02) == "less than 1 a second")
        #expect(ProgressText.count(48212, "photo") == "48,212 photos")
        #expect(ProgressText.count(1, "photo") == "1 photo")
        #expect(ProgressText.spoken(2460) == "41 minutes")
    }

    @Test func `the chart shows the last ten minutes, empty before the stage started`() {
        var meter = RateMeter(start: 300)
        for time in stride(from: 310.0, through: 600, by: 10) {
            meter.record(Int(20 * (time - 300)), at: time)
        }
        let bins = meter.throughput(now: 600, bins: 60)
        #expect(bins.count == 60)
        #expect(bins.prefix(30).allSatisfy { $0.perSecond == nil })
        #expect(bins.suffix(30).allSatisfy { $0.perSecond.map { abs($0 - 20) < 0.001 } == true })
    }

    @Test func `the chart shades where the Mac paused the work`() {
        var meter = RateMeter(start: 0)
        for time in stride(from: 10.0, through: 300, by: 10) {
            meter.record(Int(10 * time), at: time)
        }
        for time in stride(from: 310.0, through: 420, by: 10) {
            meter.record(3000, at: time, pausedBy: .lowPower)
        }
        for time in stride(from: 430.0, through: 600, by: 10) {
            meter.record(3000 + Int(10 * (time - 420)), at: time)
        }
        let bins = meter.throughput(now: 600, bins: 60)
        let paused = bins.indices.filter { bins[$0].paused != nil }
        #expect(paused == Array(31 ... 42))
        #expect(bins[35].perSecond == 0 && bins[35].paused == .lowPower)
        #expect(bins[10].paused == nil && bins[10].perSecond == 10)
    }

    @Test func `samples older than the chart and its minute are let go`() {
        let meter = meter(rate: 10, until: 3600, every: 1)
        #expect(meter.samples.count <= Int(RateMeter.history + RateMeter.window) + 2)
        #expect(meter.pace(total: 100_000, now: 3600, pausedBy: nil) == .steady(perSecond: 10, secondsLeft: 6400))
    }

    @Test func `a sample from before the last is ignored`() {
        var meter = meter(rate: 10, until: 60)
        meter.record(10, at: 30)
        #expect(meter.samples.last?.time == 60)
    }
}
