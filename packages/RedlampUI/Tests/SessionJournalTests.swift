import Foundation
import Testing
@testable import RedlampUI

/// What a session's journal keeps on disk for the next launch: its activity as the log has it,
/// the photos and folders to redact with, its hangs, and whether it quit.
@MainActor
struct SessionJournalTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_791_960_100)
    }

    /// A session whose process has ended: no process has its ID and start.
    nonisolated static let header = SessionJournal.Header(
        pid: 4242, started: Date(timeIntervalSince1970: 1_791_960_000), bundleID: "app.redlamp.mac",
        version: "0.3.2-alpha (431)", development: false, booted: Date(timeIntervalSince1970: 1_791_950_000),
    )

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func `the activity is read back as the log has it`() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = Clock()
        let log = ActivityLog { clock.now }
        log.record(.system, "Redlamp started")
        let journal = try SessionJournal(header: Self.header, folder: folder)
        log.journal = journal
        let alias = log.alias(for: URL(fileURLWithPath: "/Users/someone/Pictures/Holiday/IMG_0001.CR3"))
        log.record(.photo, "Opened \(alias)")
        log.record(.action, "Auto")
        log.record(.action, "Auto")
        for percent in [50, 75, 100] {
            clock.now += 0.1
            log.record(.view, "Zoom: \(percent)%", replacing: "zoom")
        }
        log.folders = ["/Users/someone/Pictures/Holiday"]

        let session = try #require(PreviousSession.read(journal.url))
        #expect(session.header == Self.header)
        #expect(session.events.map(\.text) == ["Redlamp started", "Opened Photo A", "Auto", "Zoom: 100%"])
        #expect(session.events.map(\.text) == log.events.map(\.text))
        #expect(session.events.map(\.count) == log.events.map(\.count))
        #expect(session.events.map(\.time) == log.events.map(\.time))
        #expect(session.photos == [PhotoName(alias: "Photo A", fileName: "IMG_0001.CR3")])
        #expect(session.folders == ["/Users/someone/Pictures/Holiday"])
        #expect(session.quit == nil)
    }

    @Test func `a hang's last mark says how it went, and quitting is the last line`() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = try SessionJournal(header: Self.header, folder: folder)
        let began = Date(timeIntervalSince1970: 1_791_960_200)
        journal.hang(SessionJournal.Hang(began: began - 60, duration: 3.5, ended: true))
        journal.hang(SessionJournal.Hang(began: began, duration: 2.1, ended: false))
        journal.hang(SessionJournal.Hang(began: began, duration: 7, ended: false))

        let stuck = try #require(PreviousSession.read(journal.url))
        #expect(stuck.hangs.map(\.duration) == [3.5, 7])
        #expect(stuck.openHang?.duration == 7)
        #expect(stuck.quit == nil)

        journal.hang(SessionJournal.Hang(began: began, duration: 12.4, ended: true))
        journal.quit()
        let quit = try #require(PreviousSession.read(journal.url))
        #expect(quit.openHang == nil)
        #expect(quit.hangs.last?.duration == 12.4)
        #expect(quit.quit != nil)
    }

    @Test func `a line a crash cut short is left out`() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ActivityLog()
        let journal = try SessionJournal(header: Self.header, folder: folder)
        log.journal = journal
        log.record(.action, "Auto")
        let handle = try FileHandle(forWritingTo: journal.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"event":{"kind":"action","te"#.utf8))
        try handle.close()

        let session = try #require(PreviousSession.read(journal.url))
        #expect(session.events.map(\.text) == ["Auto"])
    }

    @Test func `a long session's journal is rewritten with what it keeps`() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ActivityLog()
        let journal = try SessionJournal(header: Self.header, folder: folder)
        log.journal = journal
        _ = log.alias(for: URL(fileURLWithPath: "/Volumes/Photos/2026/IMG_0001.CR3"))
        log.folders = ["/Volumes/Photos/2026"]
        journal.hang(SessionJournal.Hang(began: Date(timeIntervalSince1970: 1_791_960_200), duration: 4, ended: true))
        for index in 0 ..< 2 * SessionJournal.rewriteAfter {
            log.record(.action, "Action \(index)")
        }

        let lines = try String(contentsOf: journal.url, encoding: .utf8).split(separator: "\n").count
        #expect(lines <= SessionJournal.rewriteAfter + 1)
        let session = try #require(PreviousSession.read(journal.url))
        #expect(session.header == Self.header)
        #expect(session.events.map(\.text) == log.events.map(\.text))
        #expect(session.events.count == ActivityLog.defaultCapacity)
        #expect(session.photos.map(\.fileName) == ["IMG_0001.CR3"])
        #expect(session.folders == ["/Volumes/Photos/2026"])
        #expect(session.hangs.map(\.duration) == [4])
        let others = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(others == [journal.url.lastPathComponent])
    }

    @Test func `only sessions that have ended are read at launch`() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let current = try #require(SessionJournal.Header.current(
            bundleID: "app.redlamp.mac", version: "0.3.2-alpha (431)", development: true,
        ))
        #expect(current.isRunning)
        #expect(current.booted < current.started)
        var later = current
        later.started += 30
        #expect(!later.isRunning, "a later process with the same ID isn't this one")

        let running = try SessionJournal(header: current, folder: folder)
        let ended = try SessionJournal(header: Self.header, folder: folder)
        let sessions = PreviousSession.ended(in: folder)
        #expect(sessions.map(\.url.lastPathComponent) == [ended.url.lastPathComponent])
        sessions.first?.remove()
        #expect(PreviousSession.ended(in: folder).isEmpty)
        #expect(FileManager.default.fileExists(atPath: running.url.path))
    }
}
