import Foundation

/// A folder the user added to the working set: remembered by bookmark, so a folder renamed or
/// moved is followed and, in the App Sandbox, reached again after a relaunch, and by its last
/// known path, shown while it is missing.
public struct WorkingFolder: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var bookmark: Data?
    /// `bookmark` is security-scoped, as bookmarks are wherever one can be made (`FolderAccess`).
    /// A plain one, as earlier versions made, finds the folder but doesn't reach it in the App
    /// Sandbox after a restart, so it's made again once the folder is found.
    public var isSecurityScoped: Bool

    public init(id: UUID = UUID(), path: String, bookmark: Data? = nil, isSecurityScoped: Bool = false) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.isSecurityScoped = isSecurityScoped
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    public var name: String {
        url.lastPathComponent
    }

    /// The folder at `url`, with a bookmark made now: security-scoped, or plain where none can be.
    /// Reads the file system: call it off the main thread.
    public static func make(for url: URL, id: UUID = UUID()) -> WorkingFolder {
        WorkingFolder(id: id, path: url.standardizedFileURL.path).bookmarked(at: url)
    }

    /// Where the folder is now, and the URL that reaches it: wherever its bookmark leads (a folder
    /// renamed or moved), else its last known path while a folder is there. The URL is the one the
    /// bookmark resolved to, whose access the App Sandbox needs started. A bookmark that's plain,
    /// stale, missing or leads nowhere is made again. Nil when the folder can't be found, as when
    /// its volume isn't mounted. Never mounts a volume or asks the user. Reads the file system:
    /// call it off the main thread.
    public func resolve() -> (folder: WorkingFolder, url: URL)? {
        if let bookmark,
           let found = isSecurityScoped ? FolderAccess.resolve(bookmark) : FolderAccess.resolvePlain(bookmark) {
            let started = FolderAccess.start(found.url)
            defer {
                if started {
                    FolderAccess.stop(found.url)
                }
            }
            if Self.isDirectory(found.url.path) {
                var moved = self
                // A bookmark resolves to the folder's real path; one added through a symbolic link keeps its own.
                if !Self.isSame(path, as: found.url) {
                    moved.path = found.url.standardizedFileURL.path
                }
                let folder = found.isStale || !isSecurityScoped
                    ? moved.bookmarked(at: found.url, stale: found.isStale) : moved
                return (folder, found.url)
            }
        }
        guard Self.isDirectory(path) else { return nil }
        return (bookmarked(at: url), url)
    }

    /// This folder with a security-scoped bookmark to `url` made now. Where none can be made, it
    /// keeps the bookmark it has, unless that's `stale` or missing: then it gets a plain one.
    private func bookmarked(at url: URL, stale: Bool = true) -> WorkingFolder {
        var folder = self
        if let scoped = FolderAccess.bookmark(for: url) {
            folder.bookmark = scoped
            folder.isSecurityScoped = true
        } else if stale || bookmark == nil {
            folder.bookmark = FolderAccess.plainBookmark(for: url) ?? bookmark
            folder.isSecurityScoped = false
        }
        return folder
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Whether `path` leads to the folder at `url`.
    private static func isSame(_ path: String, as url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        let followed = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard let here = try? followed.resourceValues(forKeys: keys).fileResourceIdentifier,
              let there = try? url.resolvingSymlinksInPath().resourceValues(forKeys: keys).fileResourceIdentifier
        else { return false }
        return here.isEqual(there)
    }

    /// Whether `url` is this folder or inside it.
    public func contains(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        return candidate == path || candidate.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }
}

extension WorkingFolder: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, path, bookmark, isSecurityScoped = "securityScoped"
    }

    /// An earlier version's folder has no `securityScoped`: its bookmark is plain.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark)
        isSecurityScoped = try container.decodeIfPresent(Bool.self, forKey: .isSecurityScoped) ?? false
    }
}

/// Access to folders outside the app's container (ARC-17). Bookmarks are security-scoped wherever
/// one can be made: the unsandboxed app makes them for any folder it can read, so that once it's
/// sandboxed it reaches every folder it remembers without asking again, and a sandboxed one for the
/// folders it was given (by a panel, a drop, or a bookmark whose access is started). A process in a
/// sandbox of another kind can't make them at all: macOS asks it for an entitlement it can't have.
/// There, and in what earlier versions remembered, bookmarks are plain: they find a folder again,
/// but the App Sandbox doesn't reach it through one after a restart.
public enum FolderAccess {
    public static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// A security-scoped bookmark to `url`, which only reads it with `readOnly`; nil where none can
    /// be made.
    public static func bookmark(for url: URL, readOnly: Bool = false) -> Data? {
        #if os(macOS)
            var options: URL.BookmarkCreationOptions = [.withSecurityScope]
            if readOnly {
                options.insert(.securityScopeAllowOnlyReadAccess)
            }
        #else
            let options: URL.BookmarkCreationOptions = []
        #endif
        return try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// A plain bookmark to `url`: it finds the folder again, but doesn't reach it in the App Sandbox.
    public static func plainBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Where a security-scoped bookmark leads now.
    public static func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        #if os(macOS)
            resolve(bookmark, options: [.withoutUI, .withoutMounting, .withSecurityScope])
        #else
            resolve(bookmark, options: [.withoutUI])
        #endif
    }

    /// Where a plain bookmark leads now: resolved as a security-scoped one, it's refused.
    public static func resolvePlain(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        #if os(macOS)
            resolve(bookmark, options: [.withoutUI, .withoutMounting])
        #else
            resolve(bookmark, options: [.withoutUI])
        #endif
    }

    private static func resolve(
        _ bookmark: Data, options: URL.BookmarkResolutionOptions,
    ) -> (url: URL, isStale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: options, bookmarkDataIsStale: &stale)
        else { return nil }
        return (url, stale)
    }

    /// Whether the folder at a path can be listed.
    public enum Reach: Sendable, Hashable {
        case listable
        /// There, but refused: the App Sandbox wasn't given it, or its permissions don't let it be
        /// read. Choosing it in a panel gives the sandboxed app access.
        case refused
        case absent
    }

    /// Whether the folder at `path` can be listed now. Reads the file system.
    public static func reach(_ path: String) -> Reach {
        guard let folder = opendir(path) else { return errno == EPERM || errno == EACCES ? .refused : .absent }
        closedir(folder)
        return .listable
    }

    /// Starts access to a folder, through the URL its security-scoped bookmark resolved to. Each
    /// start is matched by a `stop`: the App Sandbox stops adding folders to an app that leaks them.
    @discardableResult
    public static func start(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public static func stop(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
