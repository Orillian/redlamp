import Foundation

/// Security-scoped bookmarks to folders that settings name by path (ARC-17): the import's destination
/// and backup, the export's destinations. Each is made while the folder is reachable, as a panel
/// chooses it or, for a folder remembered before bookmarks were kept, at launch, and is what
/// reaches the folder in the App Sandbox after a relaunch. Only security-scoped bookmarks are kept:
/// where none can be made (`FolderAccess`), a folder has none until one can be.
public struct FolderBookmarks: Sendable, Hashable, Codable {
    private var bookmarks: [String: Data] = [:]

    public init() {}

    public var paths: Set<String> {
        Set(bookmarks.keys)
    }

    public func bookmark(for path: String) -> Data? {
        bookmarks[Self.key(path)]
    }

    /// Makes a bookmark for `url` now, as a panel chooses it, unless it has one: a panel's access lasts
    /// until the app quits. True when it made one.
    @discardableResult
    public mutating func remember(_ url: URL) -> Bool {
        let path = Self.key(url.path)
        guard bookmarks[path] == nil, let bookmark = FolderAccess.bookmark(for: url) else { return false }
        bookmarks[path] = bookmark
        return true
    }

    /// Those of `paths` without a bookmark.
    public func lacking(_ paths: some Sequence<String>) -> [String] {
        Set(paths.map(Self.key)).subtracting(bookmarks.keys).sorted()
    }

    /// Bookmarks made now for those of `paths` it can make them for. Reads the file system: call it off
    /// the main thread.
    public static func make(for paths: [String]) -> [String: Data] {
        var made: [String: Data] = [:]
        for path in paths {
            made[key(path)] = FolderAccess.bookmark(for: URL(fileURLWithPath: path, isDirectory: true))
        }
        return made
    }

    /// Keeps the bookmarks of `paths` only, with those of `made` added; true when that changed any.
    @discardableResult
    public mutating func keep(_ paths: some Sequence<String>, adding made: [String: Data] = [:]) -> Bool {
        let kept = Set(paths.map(Self.key))
        var next = bookmarks.filter { kept.contains($0.key) }
        for (path, bookmark) in made where kept.contains(path) && next[path] == nil {
            next[path] = bookmark
        }
        guard next != bookmarks else { return false }
        bookmarks = next
        return true
    }

    private static func key(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }
}
