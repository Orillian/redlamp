import Foundation
import Synchronization

/// The file operations a bench follows while it's on (LIB-53): sidecars read and written, thumbnails read, and
/// the operations of a simulated volume, in the order they ran, so RedlampLibrary can replay them through a
/// simulated disk (`DiskReplay`). Off, as it is outside benches, an operation costs one relaxed atomic load.
public enum FileTrace {
    public enum Kind: String, Sendable, Hashable, CaseIterable, Comparable {
        /// A file's or folder's attributes, or whether something is there.
        case stat
        case read
        /// A folder's entries.
        case list
        /// A file made and its bytes written.
        case create
        case rename
        case makeFolder
        case remove
        /// The file coordinator asked for a file's conflicting versions.
        case versions

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }
    }

    public struct Operation: Sendable, Hashable {
        public let kind: Kind
        public let path: String
        public let bytes: Int

        public init(kind: Kind, path: String, bytes: Int = 0) {
            self.kind = kind
            self.path = path
            self.bytes = bytes
        }
    }

    private static let following = Atomic(false)
    private static let recorded = Mutex<[Operation]>([])

    /// Starts following operations, forgetting any followed before.
    public static func start() {
        recorded.withLock { $0 = [] }
        following.store(true, ordering: .sequentiallyConsistent)
    }

    /// Stops following them, and returns those followed since `start`.
    @discardableResult
    public static func stop() -> [Operation] {
        following.store(false, ordering: .sequentiallyConsistent)
        return recorded.withLock { operations in
            defer { operations = [] }
            return operations
        }
    }

    /// Whether operations are followed now, for a note whose size costs something to find.
    public static var isOn: Bool {
        following.load(ordering: .relaxed)
    }

    public static func note(_ kind: Kind, _ url: URL, bytes: Int = 0) {
        guard following.load(ordering: .relaxed) else { return }
        note(kind, path: url.path, bytes: bytes)
    }

    public static func note(_ kind: Kind, path: String, bytes: Int = 0) {
        guard following.load(ordering: .relaxed) else { return }
        recorded.withLock { $0.append(Operation(kind: kind, path: path, bytes: bytes)) }
    }
}
