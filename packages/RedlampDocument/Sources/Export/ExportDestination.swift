import Foundation
import RedlampEngineAPI

/// Where an export of one photo goes, once its name is made (`ExportNames`, in RedlampLibrary,
/// makes names from the settings' template).
public enum ExportDestination {
    /// The folder `settings` export `source` to.
    public static func folder(for source: URL, settings: ExportSettings) -> URL {
        settings.destinationFolder ?? source.deletingLastPathComponent()
    }

    /// The file `base` names in the folder `settings` export `source` to, with the format's
    /// extension, before any file there is read.
    public static func named(_ base: String, for source: URL, settings: ExportSettings) -> URL {
        folder(for: source, settings: settings)
            .appending(path: base, directoryHint: .notDirectory)
            .appendingPathExtension(settings.format.fileExtension)
    }

    /// `named`'s file, or the first free number when a photo has that name (see `isPhoto`), so no
    /// rule for existing files can replace one.
    public static func url(
        _ base: String, for source: URL, settings: ExportSettings, reading files: any FileInspecting,
    ) -> URL {
        let named = named(base, for: source, settings: settings)
        return isPhoto(named, source: source, reading: files) ? firstFree(named) : named
    }

    /// Whether the file at `url` is a photo an export must never replace: anything there but an
    /// earlier export (see `ExportMetadata.isExport`), and always `source` itself (whatever the
    /// letter case of the name), a raw file, or a file with Redlamp edits. `files` reads its tags.
    public static func isPhoto(
        _ url: URL, source: URL?, reading files: any FileInspecting, fileManager: FileManager = .default,
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        if let source, isSameFile(url, source) {
            return true
        }
        return SupportedFormats.isRaw(url)
            || fileManager.fileExists(atPath: SidecarStore().url(for: url).path)
            || !ExportMetadata.isExport(url, reading: files)
    }

    /// Through symbolic links; by path, ignoring letter case and Unicode normalisation, when the
    /// volume gives no file identifiers.
    private static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        let first = first.resolvingSymlinksInPath()
        let second = second.resolvingSymlinksInPath()
        let key = URLResourceKey.fileResourceIdentifierKey
        if let one = try? first.resourceValues(forKeys: [key]).fileResourceIdentifier,
           let other = try? second.resourceValues(forKeys: [key]).fileResourceIdentifier {
            return one.isEqual(other)
        }
        return first.path.precomposedStringWithCanonicalMapping.lowercased()
            == second.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// `url`, or the first of `name-2`, `name-3`… that doesn't exist and isn't `taken`.
    public static func firstFree(
        _ url: URL, taken: (URL) -> Bool = { _ in false }, fileManager: FileManager = .default,
    ) -> URL {
        guard fileManager.fileExists(atPath: url.path) || taken(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = folder.appending(path: "\(name)-\(number)", directoryHint: .notDirectory)
                .appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path), !taken(candidate) {
                return candidate
            }
            number += 1
        }
    }
}

public enum ExportError: Error, LocalizedError, Equatable {
    case cannotEncode(ExportFormat)
    /// Even the lowest quality is over the limit; `smallestKB` is what it came to.
    case fileSizeLimitUnreachable(format: ExportFormat, limitKB: Int, smallestKB: Int)
    case folderMissing(URL)
    case writeFailed(URL)
    /// The file is a photo, not an earlier export (see `ExportDestination.isPhoto`).
    case wouldReplacePhoto(URL)

    public var errorDescription: String? {
        switch self {
        case let .cannotEncode(format):
            "The photo couldn't be encoded as \(format.name)."
        case let .fileSizeLimitUnreachable(format, limitKB, smallestKB):
            "At this size the smallest \(format.name) is \(smallestKB) KB, over the \(limitKB) KB limit. "
                + "Export it smaller, or raise the limit."
        case let .folderMissing(folder):
            "The folder “\(folder.lastPathComponent)” isn't there any more. Choose another in the Export dialog."
        case let .writeFailed(url):
            "“\(url.lastPathComponent)” couldn't be written."
        case let .wouldReplacePhoto(url):
            "“\(url.lastPathComponent)” is a photo, so the export wasn't written over it. Choose another name."
        }
    }
}
