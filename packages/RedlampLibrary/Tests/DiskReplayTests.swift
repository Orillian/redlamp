import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampLibrary

/// A trace replayed through a disk of one head (LIB-53).
struct DiskReplayTests {
    static let disk = VolumeProfile(
        name: "test",
        bandwidth: 1_000_000,
        maxInFlight: 1,
        seek: .milliseconds(10),
        nearSeek: .milliseconds(2),
    )

    static func operation(_ kind: FileTrace.Kind, _ path: String, bytes: Int = 0) -> FileTrace.Operation {
        FileTrace.Operation(kind: kind, path: path, bytes: bytes)
    }

    @Test func `reading on in the same file costs no seek, and another file in its folder a near one`() {
        let report = DiskReplay(profile: Self.disk).replay([
            Self.operation(.read, "/Disk/A/1.CR3", bytes: 1000),
            Self.operation(.read, "/Disk/A/1.CR3", bytes: 1000),
            Self.operation(.read, "/Disk/A/2.CR3", bytes: 1000),
            Self.operation(.read, "/Disk/B/3.CR3", bytes: 1000),
        ])
        // 10 ms + 1 ms, 1 ms, 2 ms + 1 ms, 10 ms + 1 ms.
        #expect(report.duration == .milliseconds(26))
        #expect(report.reachedDisk == 4 && report.folderMoves == 2)
    }

    @Test func `looking at metadata in a folder touched lately is answered from the cache`() {
        let report = DiskReplay(profile: Self.disk, cachedFolders: 1).replay([
            Self.operation(.stat, "/Disk/A/1.CR3.redlamp"),
            Self.operation(.stat, "/Disk/A/2.CR3.redlamp"),
            Self.operation(.stat, "/Disk/B/3.CR3.redlamp"),
            Self.operation(.stat, "/Disk/A/4.CR3.redlamp"),
        ])
        #expect(report.total == 4 && report.reachedDisk == 3)
    }

    @Test func `a sidecar package's own files count as its photo's folder`() {
        #expect(DiskReplay.folder(of: Self.operation(.rename, "/Disk/A/1.CR3.redlamp/edit.json")) == "/Disk/A")
        #expect(DiskReplay.folder(of: Self.operation(.makeFolder, "/Disk/A/.1.CR3.redlamp.\(UUID())")) == "/Disk/A")
        #expect(DiskReplay.folder(of: Self.operation(.list, "/Disk/A/1.CR3.redlamp/history")) == "/Disk/A")
        #expect(DiskReplay.folder(of: Self.operation(.list, "/Disk/A")) == "/Disk/A")
    }

    @Test func `the same writes taken one folder at a time move the head less`() {
        let interleaved = (0 ..< 8).flatMap { number in
            ["A", "B"].map { Self.operation(.create, "/Disk/\($0)/\(number).CR3.redlamp/edit.json", bytes: 100) }
        }
        let disk = DiskReplay(profile: Self.disk)
        let asRun = disk.replay(interleaved)
        let ordered = disk.replay(LightroomDiskBenchTests.folderByFolder(interleaved))
        #expect(asRun.folderMoves == 16 && ordered.folderMoves == 2)
        #expect(ordered.duration < asRun.duration)
    }
}
