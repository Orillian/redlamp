import Foundation
import RedlampEngineAPI

/// A `FileTrace` replayed through a disk of one head, as `profile` describes it (LIB-53): what the same
/// operations, in the same order, would cost there, worked out rather than waited for, so a bench of
/// thousands of photos takes seconds. It compares one way of working with another; it doesn't stand for
/// a real disk, whose file system flushes metadata when it chooses, whose drive caches and reorders,
/// and whose USB bridge adds its own delays.
///
/// - **Reading a file's bytes** reaches the disk: no seek when the head is on that file already, a near
///   seek within its folder, a seek otherwise, then the bytes at the profile's bandwidth.
/// - **Looking at metadata** (a file's attributes, a folder's entries, its conflicting versions) is
///   answered by the Mac's cache when the folder was touched within the last `cachedFolders` folders;
///   otherwise it reads a block of the folder's from the disk.
/// - **Changing metadata** (a file made, renamed or removed, a folder made) writes a block, and a made file's
///   bytes, on the disk: a photo's sidecar operations together, each photo's apart.
public struct DiskReplay: Sendable {
    public struct Report: Sendable, Hashable {
        /// What the operations would take on the disk.
        public var duration: Duration = .zero
        public var operations: [FileTrace.Kind: Int] = [:]
        /// Operations that reached the disk.
        public var reachedDisk = 0
        /// Times the head moved to another folder.
        public var folderMoves = 0
        public var bytes = 0

        public var total: Int {
            operations.values.reduce(0, +)
        }
    }

    public let profile: VolumeProfile
    /// Folders whose metadata the Mac keeps in memory, the most recently touched.
    public let cachedFolders: Int
    static let block = 4096

    public init(profile: VolumeProfile = .usb25, cachedFolders: Int = 64) {
        self.profile = profile
        self.cachedFolders = cachedFolders
    }

    public func replay(_ operations: [FileTrace.Operation]) -> Report {
        var report = Report()
        var lastFile: String?
        var lastFolder: String?
        var recent: [String] = []
        for operation in operations {
            report.operations[operation.kind, default: 0] += 1
            let folder = Self.folder(of: operation)
            let bytes: Int
            switch operation.kind {
            case .read:
                bytes = operation.bytes
            case .stat, .list, .versions:
                if recent.contains(folder) {
                    Self.touch(folder, in: &recent, keeping: cachedFolders)
                    continue
                }
                bytes = Self.block
            case .create:
                bytes = Self.block + operation.bytes
            case .rename, .makeFolder, .remove:
                bytes = Self.block
            }
            Self.touch(folder, in: &recent, keeping: cachedFolders)
            let file = operation.kind == .read ? operation.path : Self.item(of: operation)
            var cost = profile.latency
            if file != lastFile {
                cost += folder == lastFolder ? profile.nearSeek ?? profile.seek : profile.seek
            }
            if folder != lastFolder {
                report.folderMoves += 1
            }
            if let bandwidth = profile.bandwidth, bytes > 0 {
                cost += .seconds(Double(bytes) / bandwidth)
            }
            report.duration += cost
            report.reachedDisk += 1
            report.bytes += bytes
            lastFile = file
            lastFolder = folder
        }
        return report
    }

    /// The folder of the photo an operation is for: a sidecar package's own folders count as the photo's.
    static func folder(of operation: FileTrace.Operation) -> String {
        var parts = operation.path.split(separator: "/", omittingEmptySubsequences: false)
        if let package = parts.lastIndex(where: { $0.hasSuffix(".redlamp") || $0.contains(".redlamp.") }) {
            parts = Array(parts[..<package])
        } else if operation.kind == .list {
            return operation.path
        } else {
            parts.removeLast()
        }
        return parts.joined(separator: "/")
    }

    /// What a metadata operation changes on the disk: a sidecar package's own files count as their package, so
    /// a photo's sidecar operations are written together, and each photo's apart.
    static func item(of operation: FileTrace.Operation) -> String {
        let parts = operation.path.split(separator: "/", omittingEmptySubsequences: false)
        guard let package = parts.lastIndex(where: { $0.hasSuffix(".redlamp") || $0.contains(".redlamp.") })
        else { return operation.path }
        var name = parts[package]
        if name.hasPrefix("."), let end = name.range(of: ".redlamp.") {
            name = name[name.index(after: name.startIndex) ..< end.lowerBound] + ".redlamp"
        }
        return (parts[..<package] + [name]).joined(separator: "/")
    }

    private static func touch(_ folder: String, in recent: inout [String], keeping limit: Int) {
        recent.removeAll { $0 == folder }
        recent.append(folder)
        if recent.count > limit {
            recent.removeFirst(recent.count - limit)
        }
    }
}
