import Foundation
import IOKit
import RedlampEngineAPI
import Synchronization

/// The Mac's own file system: a listing carries its entries' attributes (asked for up front, so
/// they come back with the listing itself), and a read is one `pread` on a descriptor opened for
/// it.
public struct LocalFileSystem: LibraryFileSystem {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .fileIdentifierKey,
    ]
    private static let keySet = Set(keys)
    private static let volumeKeys: Set<URLResourceKey> = [
        .volumeUUIDStringKey, .volumeNameKey, .volumeIsLocalKey, .volumeIsInternalKey,
    ]

    public init() {}

    public func contentsOfDirectory(at url: URL) throws -> [FileEntry] {
        FileTrace.note(.list, url)
        let entries = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles],
        )
        return entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: Self.keySet) else { return nil }
            return FileEntry(entry.lastPathComponent, values)
        }
    }

    public func attributes(of url: URL) throws -> FileEntry {
        FileTrace.note(.stat, url)
        // A new URL: the caller's caches the values it was first asked for.
        let fresh = URL(fileURLWithPath: url.path)
        return try FileEntry(url.lastPathComponent, fresh.resourceValues(forKeys: Self.keySet))
    }

    public func read(_ url: URL, range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0 else { throw POSIXError(.EINVAL) }
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            var fd: Int32
            repeat {
                fd = open(path, O_RDONLY | O_CLOEXEC)
            } while fd < 0 && errno == EINTR
            return fd
        }
        guard fd >= 0 else { throw POSIXError.current }
        defer { close(fd) }
        var data = Data(count: range.count)
        let count = try data.withUnsafeMutableBytes { buffer -> Int in
            var total = 0
            while total < range.count {
                let read = pread(fd, buffer.baseAddress! + total, range.count - total, off_t(range.lowerBound + total))
                if read > 0 {
                    total += read
                } else if read == 0 {
                    break
                } else if errno != EINTR {
                    throw POSIXError.current
                }
            }
            return total
        }
        data.count = count
        FileTrace.note(.read, url, bytes: count)
        return data
    }

    public func volume(of url: URL) throws -> VolumeInfo {
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: Self.volumeKeys)
        let isLocal = values.volumeIsLocal ?? false
        return VolumeInfo(
            uuid: values.volumeUUIDString,
            name: values.volumeName,
            isLocal: isLocal,
            isInternal: values.volumeIsInternal ?? false,
            isRotational: isLocal ? Self.isRotational(url) : nil,
        )
    }

    /// Whether the device the volume holding `url` is on spins: what the "Medium Type" of its "Device
    /// Characteristics" says, "Rotational" or "Solid State", found from the volume's BSD device (statfs's
    /// `f_mntfromname`) up the I/O Registry's parents. Nil when it says neither, or the registry can't be asked.
    static func isRotational(_ url: URL) -> Bool? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }
        let device = withUnsafeBytes(of: info.f_mntfromname) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        guard device.hasPrefix("/dev/") else { return nil }
        // A BSD name can be another disk's once its own is unplugged; a mount's file system ID is its own.
        let mount = "\(device) \(info.f_fsid.val.0) \(info.f_fsid.val.1)"
        if let known = rotational.withLock({ $0[mount] }) {
            return known
        }
        let found = mediumType(ofBSDName: String(device.dropFirst(5))).flatMap { medium -> Bool? in
            switch medium {
            case "Rotational": true
            case "Solid State": false
            default: nil
            }
        }
        rotational.withLock { $0[mount] = .some(found) }
        return found
    }

    /// What each mount's device said, by its device and file system ID.
    private static let rotational = Mutex<[String: Bool?]>([:])

    private static func mediumType(ofBSDName name: String) -> String? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, name) else { return nil }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else { return nil }
        defer { IOObjectRelease(media) }
        let found = IORegistryEntrySearchCFProperty(
            media, kIOServicePlane, "Device Characteristics" as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
        )
        return (found as? [String: Any])?["Medium Type"] as? String
    }
}

extension FileEntry {
    init(_ name: String, _ values: URLResourceValues) {
        var name = name
        name.makeContiguousUTF8()
        self.init(
            name: name,
            isDirectory: values.isDirectory ?? false,
            isPackage: values.isPackage ?? false,
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate ?? .distantPast,
            fileIdentifier: values.fileIdentifier,
        )
    }
}

extension POSIXError {
    /// The error `errno` holds now.
    static var current: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
