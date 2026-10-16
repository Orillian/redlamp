import Foundation
import RedlampDocument
import Testing
@testable import RedlampLibrary

/// Disks that spin (LIB-53): told from what their device says, read one operation at a time in folder order,
/// and recorded as spinning in the index.
struct SpinningDiskTests {
    @Test func `this Mac's own disk says it's solid state, or nothing`() throws {
        let folder = try TemporaryFolder()
        let said = LocalFileSystem.isRotational(folder.url)
        print("SPINNING-DISK-LOOKUP \(folder.url.path): \(said.map { $0 ? "rotational" : "solid state" } ?? "nil")")
        #expect(said != true)
        #expect(try LocalFileSystem().volume(of: folder.url).isRotational == said)
        #expect(LocalFileSystem.isRotational(URL(fileURLWithPath: "/no/such/folder")) == nil)
    }

    @Test func `simulated disks that spin say so, and the others say what the disk beneath says`() throws {
        let folder = try TemporaryFolder()
        let beneath = try LocalFileSystem().volume(of: folder.url).isRotational
        for profile in [VolumeProfile.spinning, .usb25] {
            #expect(try SimulatedFileSystem(profile: profile, clock: ManualClock()).volume(of: folder.url)
                .isRotational == true)
        }
        #expect(try SimulatedFileSystem(profile: .ssd, clock: ManualClock()).volume(of: folder.url)
            .isRotational == beneath)
    }

    @Test func `a disk that spins is read one operation at a time, and its readers never widen`() async throws {
        let rotational = VolumeInfo(uuid: "R", name: nil, isLocal: true, isInternal: false, isRotational: true)
        #expect(VolumeIO.initialWidth(for: rotational) == 1)
        #expect(VolumeIO.initialWidth(for: VolumeInfo(
            uuid: "I", name: nil, isLocal: true, isInternal: true, isRotational: true,
        )) == 1)
        #expect(VolumeIO.initialWidth(for: VolumeInfo(
            uuid: "S", name: nil, isLocal: true, isInternal: false, isRotational: false,
        )) == 2)
        #expect(VolumeIO.initialWidth(for: VolumeInfo(
            uuid: "N", name: nil, isLocal: false, isInternal: false, isRotational: true,
        )) == 4)
        let fileSystem = VolumeIOTests.SlowFileSystem(delay: .milliseconds(1))
        let probe = URL(fileURLWithPath: "/Volumes/Spinning")
        let io = VolumeIO(volume: rotational, fileSystem: fileSystem, probe: probe, maximumWidth: 8)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0 ..< 300 {
                group.addTask {
                    try await io.read(probe.appending(path: "IMG_\(index).ARW"), range: 0 ..< 1000).count
                }
            }
            for try await _ in group {
                #expect(io.width == 1)
            }
        }
        #expect(io.statistics.operations == 300 && io.width == 1)
    }

    @Test func `an external disk that doesn't say whether it spins is read as one that does, and recorded as unknown`(
    ) async throws {
        #expect(VolumeIO.initialWidth(for: VolumeInfo(uuid: "U", name: nil, isLocal: true, isInternal: false)) == 1)
        #expect(VolumeIO.initialWidth(for: VolumeInfo(uuid: "I", name: nil, isLocal: true, isInternal: true))
            == CoreCounts.performance)
        let sandbox = try await IndexerSandbox.make(.init(photos: 60, seed: 34, shapes: []))
        defer { sandbox.remove() }
        let indexer = LibraryIndexer(
            index: sandbox.index,
            fileSystem: SimulatedFileSystem(base: UnsaidFileSystem(), profile: VolumeProfile(
                name: "unsaid", isInternal: false,
            )),
            configuration: .testing(),
        )
        let run = await IndexerRun.collect(indexer.index([sandbox.root]))
        #expect(run.failures.isEmpty && run.summary?.photosInserted == 60)
        let volumes = try await sandbox.index.read { try $0.volumes() }
        #expect(volumes.map(\.kind) == [.unknown])
        #expect(indexer.volumes.all.map(\.width) == [1])
    }

    /// The Mac's file system, whose volumes' devices don't say whether they spin.
    struct UnsaidFileSystem: LibraryFileSystem {
        let base = LocalFileSystem()

        func contentsOfDirectory(at url: URL) throws -> [FileEntry] {
            try base.contentsOfDirectory(at: url)
        }

        func attributes(of url: URL) throws -> FileEntry {
            try base.attributes(of: url)
        }

        func read(_ url: URL, range: Range<Int>) throws -> Data {
            try base.read(url, range: range)
        }

        func volume(of url: URL) throws -> VolumeInfo {
            let info = try base.volume(of: url)
            return VolumeInfo(uuid: info.uuid, name: info.name, isLocal: info.isLocal, isInternal: info.isInternal)
        }
    }

    @Test func `the index records a volume that spins as spinning, and indexes it through one reader`() async throws {
        let sandbox = try await IndexerSandbox.make(.init(photos: 60, seed: 33, shapes: []))
        defer { sandbox.remove() }
        let profile = VolumeProfile(name: "rotational", isInternal: false, isRotational: true)
        let indexer = LibraryIndexer(
            index: sandbox.index, fileSystem: SimulatedFileSystem(profile: profile), configuration: .testing(),
        )
        let run = await IndexerRun.collect(indexer.index([sandbox.root]))
        #expect(run.failures.isEmpty && run.summary?.photosInserted == 60)
        let volumes = try await sandbox.index.read { try $0.volumes() }
        #expect(volumes.map(\.kind) == [.spinning])
        #expect(indexer.volumes.all.map(\.width) == [1])
    }
}
