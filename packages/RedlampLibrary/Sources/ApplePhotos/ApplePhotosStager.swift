import Foundation
import Synchronization

/// Writes the files of the assets an import from Apple Photos takes (LIB-54) into a hidden staging folder on
/// the destination's volume, `<destination>/.Redlamp Photos Import/<import ID>/`, a folder for each asset so
/// no two names meet: the original as Photos has it (a RAW+JPEG pair's raw named after its JPEG, so the two
/// stay a pair) and, for a photo edited in Photos, its rendering as `<name> (Photos edit).<ext>`. Each file is
/// written under a hidden name and renamed once it's whole, so a file already staged is kept and a stopped
/// import takes up where it was. A file without a capture time of its own is dated when Photos says it was
/// taken. The card import then copies the staging folder as a folder (`ApplePhotosImport`).
public struct ApplePhotosStager: Sendable {
    /// The hidden folder at a destination that holds each import's staging folder.
    public static let folderName = ".Redlamp Photos Import"
    /// Assets written at once: Photos downloads several from iCloud at a time.
    static let atOnce = 4

    public let library: any ApplePhotosLibrary
    /// This import's staging folder.
    public let folder: URL

    public init(library: any ApplePhotosLibrary, destination: URL, id: UUID) {
        self.library = library
        folder = Self.root(for: destination).appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// The hidden folder at `destination` that holds the staging folders.
    public static func root(for destination: URL) -> URL {
        URL(fileURLWithPath: LibraryIndexer.path(destination), isDirectory: true)
            .appending(path: folderName, directoryHint: .isDirectory)
    }

    /// An asset's files as they're staged.
    public struct Staged: Sendable, Hashable {
        public var asset: String
        public var folder: URL
        /// The original's files' names: its photo, and a pair's raw.
        public var originals: [String]
        /// Its edit's rendering's name.
        public var edit: String?
    }

    public struct Progress: Sendable, Hashable {
        public var assets: Int
        public var done = 0
        public var failed = 0
        /// The bytes to write, when Photos says, and those written.
        public var bytes: Int64?
        public var written: Int64 = 0
        /// Files Photos is downloading from iCloud now.
        public var downloading = 0
    }

    public struct Outcome: Sendable, Hashable {
        public var staged: [Staged]
        /// Assets whose files Photos couldn't give, with why, by local identifier.
        public var failures: [String: String]
        /// Cancelled before every asset was staged.
        public var stopped: Bool
    }

    /// Stages `assets`' files, a few at a time, `progress` hearing of each file. Cancelling the task stops it
    /// once the files being written are let go, leaving those already whole.
    public func stage(_ assets: [ApplePhotosAsset], progress: (@Sendable (Progress) -> Void)? = nil) async -> Outcome {
        let sizes = assets.flatMap { asset in Self.files(of: asset).map(\.resource.size) }
        let tally = Tally(Progress(
            assets: assets.count, bytes: sizes.contains(nil) ? nil : sizes.reduce(0) { $0 + ($1 ?? 0) },
        ))
        let results = Tally<(staged: [Int: Staged], failures: [String: String])>(([:], [:]))
        let report: @Sendable () -> Void = { progress?(tally.value) }
        let queue = ImportQueue(assets.indices)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< Self.atOnce {
                group.addTask {
                    while !Task.isCancelled, let index = queue.next() {
                        let asset = assets[index]
                        do {
                            let staged = try await stageFiles(of: asset, tally: tally, report: report)
                            results.withLock { $0.staged[index] = staged }
                            tally.withLock { $0.done += 1 }
                        } catch is CancellationError {
                            break
                        } catch {
                            results.withLock { $0.failures[asset.id] = Self.message(error) }
                            tally.withLock { $0.failed += 1 }
                        }
                        report()
                    }
                }
            }
        }
        let (staged, failures) = results.value
        return Outcome(
            staged: staged.sorted { $0.key < $1.key }.map(\.value), failures: failures,
            stopped: staged.count + failures.count < assets.count,
        )
    }

    /// Removes this import's staging folder, and the hidden folder holding it once it's empty.
    public func remove() {
        try? FileManager.default.removeItem(at: folder)
        let root = folder.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// The files an asset is staged as, with their names.
    static func files(of asset: ApplePhotosAsset) -> [(resource: ApplePhotosResource, name: String)] {
        ApplePhotosNames.originals(of: asset) + (ApplePhotosNames.edit(of: asset).map { [$0] } ?? [])
    }

    private func stageFiles(
        of asset: ApplePhotosAsset, tally: Tally<Progress>, report: @escaping @Sendable () -> Void,
    ) async throws -> Staged {
        let place = folder.appending(path: ApplePhotosNames.folder(of: asset.id), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        for (resource, name) in Self.files(of: asset) {
            let target = place.appending(path: name)
            if !FileManager.default.fileExists(atPath: target.path) {
                try await write(resource, of: asset, to: target, tally: tally, report: report)
            }
            let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            tally.withLock { $0.written += size }
        }
        return Staged(
            asset: asset.id, folder: place, originals: ApplePhotosNames.originals(of: asset).map(\.name),
            edit: ApplePhotosNames.edit(of: asset)?.name,
        )
    }

    private func write(
        _ resource: ApplePhotosResource, of asset: ApplePhotosAsset, to target: URL, tally: Tally<Progress>,
        report: @escaping @Sendable () -> Void,
    ) async throws {
        let partial = target.deletingLastPathComponent().appending(path: "." + target.lastPathComponent + ".partial")
        try? FileManager.default.removeItem(at: partial)
        let downloading = Atomic(false)
        defer {
            if downloading.load(ordering: .acquiring) {
                tally.withLock { $0.downloading -= 1 }
                report()
            }
        }
        do {
            try await library.write(resource, of: asset.id, to: partial) { _ in
                if !downloading.exchange(true, ordering: .acquiringAndReleasing) {
                    tally.withLock { $0.downloading += 1 }
                    report()
                }
            }
            try Task.checkCancellation()
            if let created = asset.created {
                try? FileManager.default.setAttributes([.modificationDate: created], ofItemAtPath: partial.path)
            }
            try FileManager.default.moveItem(at: partial, to: target)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    /// A value several tasks change.
    final class Tally<Value: Sendable>: Sendable {
        private let state: Mutex<Value>

        init(_ value: Value) {
            state = Mutex(value)
        }

        var value: Value {
            state.withLock { $0 }
        }

        func withLock<T: Sendable>(_ body: (inout Value) -> T) -> T {
            state.withLock { body(&$0) }
        }
    }

    static func message(_ error: any Error) -> String {
        (error as? ApplePhotosError)?.description ?? error.localizedDescription
    }
}
