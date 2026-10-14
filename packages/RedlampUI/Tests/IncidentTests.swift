import Foundation
import Testing
@testable import RedlampUI

/// Crashes as macOS's crash report and MetricKit describe them (both fixtures are from one crash of
/// a probe app, renamed Redlamp, with a made-up home folder and photo added), what an incident
/// keeps of them, and what it leaves on the Mac.
struct IncidentTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Incidents")

    static func crashReport() throws -> Incident {
        let data = try Data(contentsOf: folder.appending(path: "crash.ips"))
        return try #require(MacCrashReport.read(data)).incident
    }

    static func metricKit() throws -> Incident {
        let data = try Data(contentsOf: folder.appending(path: "metrickit-crash.json"))
        return try #require(Incident(
            metricKit: data,
            kind: .crash, time: Date(timeIntervalSince1970: 1_791_968_880), appBinaries: ["Redlamp"],
        ))
    }

    @Test func `macOS's crash report gives the exception, the threads and the binaries`() throws {
        let incident = try Self.crashReport()
        #expect(incident.kind == .crash)
        #expect(incident.pid == 4242)
        #expect(incident.version == "0.3.2-alpha (431)")
        #expect(incident.exception == "EXC_BAD_ACCESS (SIGSEGV)")
        #expect(incident.reasons.contains("SIGNAL: Segmentation fault: 11"))
        #expect(incident.threads.count == 4)
        let crashedThread = incident.threads.first(where: \.crashed)
        let crashed = try #require(crashedThread)
        #expect(crashed.queue == "com.apple.main-thread")
        let top = try #require(crashed.frames.first)
        #expect(incident.binaries[top.binary].name == "Redlamp")
        #expect(incident.binaries[top.binary].inApp)
        #expect(top.offset == 0x4448)
        let dispatch = incident.binaries.first { $0.name == "libdispatch.dylib" }
        #expect(dispatch?.inApp == false)
        #expect(incident.suggestedTitle == "Crash: EXC_BAD_ACCESS (SIGSEGV) in Redlamp")
    }

    @Test func `nothing that identifies the Mac or maps its memory is kept`() throws {
        let json = try String(decoding: JSONEncoder().encode(Self.crashReport()), as: UTF8.self)
        for kept in [
            "AAAAAAAA-BBBB",
            "99999999-8888",
            "11111111-2222",
            "ARM_THREAD_STATE64",
            "beforePC",
            "MALLOC 1.2G",
            "/Applications/Redlamp.app",
            "mapped file",
        ] {
            #expect(!json.contains(kept), "\(kept)")
        }
    }

    @Test func `what the app said as it ended is kept for the redactor to clean`() throws {
        let incident = try Self.crashReport()
        #expect(incident.reasons.contains("while reading /Users/someone/Pictures/Holiday/IMG_0001.CR3"))
        let redactor = FeedbackRedactor(
            home: "/Users/someone",
            photos: [PhotoName(alias: "Photo A", fileName: "IMG_0001.CR3")],
        )
        let redacted = try redactor.redact(String(decoding: JSONEncoder().encode(incident), as: UTF8.self))
        #expect(!redacted.contains("someone"))
        #expect(!redacted.contains("IMG_0001"))
        #expect(redacted.contains("Photo A"))
    }

    @Test func `only the asked-for app's process is found`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "incident-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(contentsOf: Self.folder.appending(path: "crash.ips"))
            .write(to: folder.appending(path: "Redlamp-2026-10-14-100811.ips"))
        let since = Date(timeIntervalSinceNow: -60)
        #expect(MacCrashReport.find(pid: 4242, bundleID: "app.redlamp.mac", since: since, in: folder)?.pid == 4242)
        #expect(MacCrashReport.find(pid: 4243, bundleID: "app.redlamp.mac", since: since, in: folder) == nil)
        #expect(MacCrashReport.find(pid: 4242, bundleID: "app.redlamp.mac.e2e", since: since, in: folder) == nil)
        #expect(MacCrashReport.find(
            pid: 4242,
            bundleID: "app.redlamp.mac",
            since: Date(timeIntervalSinceNow: 60),
            in: folder,
        ) == nil)
    }

    @Test func `MetricKit's diagnostic gives the same crash, without names`() throws {
        let incident = try Self.metricKit()
        let report = try Self.crashReport()
        #expect(incident.pid == report.pid)
        #expect(incident.exception == report.exception)
        #expect(incident.version == "0.3.2-alpha (431)")
        #expect(incident.reasons == ["0x10 is not in any region."])
        let first = incident.threads.first(where: \.crashed)?.frames.first
        let reportFirst = report.threads.first(where: \.crashed)?.frames.first
        let top = try #require(first)
        let reportTop = try #require(reportFirst)
        #expect(top.offset == reportTop.offset)
        #expect(top.symbol == nil)
        #expect(incident.binaries[top.binary].uuid == report.binaries[reportTop.binary].uuid)
        #expect(incident.binaries[top.binary].base == report.binaries[reportTop.binary].base)
        #expect(incident.binaries[top.binary].inApp)
    }

    @Test func `the crash report comes first when both have the crash`() throws {
        let merged = try Self.crashReport().merged(with: Self.metricKit())
        #expect(merged.sources == [.crashReport, .metricKit])
        #expect(merged.threads.count == 4)
        let top = merged.threads.first(where: \.crashed)?.frames.first
        #expect(top?.symbol != nil)
        #expect(merged.reasons.contains("0x10 is not in any region."))
        let metricKit = try Self.metricKit()
        #expect(try metricKit.merged(with: Self.crashReport()).threads.count == metricKit.threads.count)
    }

    @Test func `a hang's title says how long, and whether Redlamp was closed during it`() {
        var hang = Incident(kind: .hang, time: Date(), pid: 1, sources: [.watchdog])
        hang.duration = 14.2
        #expect(hang.suggestedTitle == "Hang: 14 s")
        hang.duration = 125
        hang.endedSession = true
        #expect(hang.suggestedTitle == "Hang: 2 min 5 s, then Redlamp was closed")
        #expect(hang.headline == "Redlamp stopped responding")
    }
}
