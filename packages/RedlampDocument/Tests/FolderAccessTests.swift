import Foundation
import RedlampDocument
import Testing

/// Bookmarks to the folders Redlamp remembers (ARC-17): security-scoped wherever one can be made, so the App Sandbox
/// reaches them after a relaunch, and plain where it can't, as in a process inside a sandbox of another kind.
struct FolderAccessTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "folder-access-\(UUID().uuidString)")

    /// Whether this process can make security-scoped bookmarks: an app outside any sandbox, or in the App Sandbox
    /// for a folder it was given, can; a test run from a shell inside another sandbox can't.
    static let makesSecurityScoped: Bool = {
        let folder = FileManager.default.temporaryDirectory.appending(path: "folder-access-probe-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return FolderAccess.bookmark(for: folder) != nil
    }()

    private func folder(_ name: String) throws -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func `an earlier version's folder reads as having a plain bookmark, and keeps its scope once saved`(
    ) throws {
        defer { cleanUp() }
        let url = try folder("Trip")
        let plain = try #require(FolderAccess.plainBookmark(for: url))
        let id = UUID()
        let earlier = """
        {"id":"\(id.uuidString)","path":"\(url.path)","bookmark":"\(plain.base64EncodedString())"}
        """
        let read = try JSONDecoder().decode(WorkingFolder.self, from: Data(earlier.utf8))
        #expect(read == WorkingFolder(id: id, path: url.path, bookmark: plain, isSecurityScoped: false))

        let scoped = WorkingFolder(id: id, path: url.path, bookmark: plain, isSecurityScoped: true)
        let saved = try JSONEncoder().encode(scoped)
        #expect(try JSONDecoder().decode(WorkingFolder.self, from: saved) == scoped)
    }

    @Test func `a folder renamed is found through its bookmark`() throws {
        defer { cleanUp() }
        let url = try folder("Trip")
        let made = WorkingFolder.make(for: url)
        #expect(made.bookmark != nil && made.isSecurityScoped == Self.makesSecurityScoped)
        try FileManager.default.moveItem(at: url, to: root.appending(path: "Trip 2026"))

        let found = try #require(made.resolve())
        let renamed = Self.real(root.appending(path: "Trip 2026").path)
        #expect(Self.real(found.folder.path) == renamed && found.folder.id == made.id)
        #expect(Self.real(found.url.path) == renamed)
    }

    @Test func `a folder added through a symbolic link keeps the path it was added by`() throws {
        defer { cleanUp() }
        let url = try folder("Photos")
        let link = root.appending(path: "Linked", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let made = WorkingFolder.make(for: link)

        let found = try #require(made.resolve())
        #expect(found.folder.path == link.standardizedFileURL.path)
        #expect(Self.real(found.url.path) == Self.real(url.path))
    }

    /// `path` with its symbolic links resolved, as a temporary folder's `/var` is `/private/var`.
    private static func real(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    @Test func `an earlier version's plain bookmark is made again security-scoped, where one can be made`() throws {
        defer { cleanUp() }
        let url = try folder("Trip")
        let plain = try #require(FolderAccess.plainBookmark(for: url))
        let earlier = WorkingFolder(path: url.path, bookmark: plain)

        let found = try #require(earlier.resolve())
        #expect(found.folder.path == url.standardizedFileURL.path)
        #expect(found.folder.isSecurityScoped == Self.makesSecurityScoped)
        if Self.makesSecurityScoped {
            #expect(found.folder.bookmark != plain)
            #expect(try FolderAccess.resolve(#require(found.folder.bookmark))?.url.standardizedFileURL.path == url.path)
        } else {
            #expect(found.folder.bookmark == plain, "kept: it still finds the folder")
        }
    }

    @Test func `a bookmark that leads nowhere is made again from the folder at the path`() throws {
        defer { cleanUp() }
        let url = try folder("Trip")
        let broken = WorkingFolder(path: url.path, bookmark: Data([1, 2, 3]), isSecurityScoped: true)

        let found = try #require(broken.resolve())
        #expect(found.folder.bookmark != nil && found.folder.bookmark != Data([1, 2, 3]))
        #expect(found.folder.isSecurityScoped == Self.makesSecurityScoped)
    }

    @Test func `a folder neither its bookmark nor its path leads to isn't found`() throws {
        defer { cleanUp() }
        let url = try folder("Trip")
        let made = WorkingFolder.make(for: url)
        try FileManager.default.removeItem(at: url)
        #expect(made.resolve() == nil)
        #expect(WorkingFolder(path: url.path).resolve() == nil)
    }

    @Test func `a folder whose permissions keep it from being read is refused, unlike one that isn't there`() throws {
        defer { cleanUp() }
        let url = try folder("Shut")
        #expect(FolderAccess.reach(url.path) == .listable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        #expect(FolderAccess.reach(url.path) == .refused)
        #expect(FolderAccess.reach(root.appending(path: "Nothing").path) == .absent)
    }

    @Test func `bookmarks by path keep only the folders still named, and say which lack one`() {
        var bookmarks = FolderBookmarks()
        #expect(bookmarks.lacking(["/Photos/A", "/Photos/B/"]) == ["/Photos/A", "/Photos/B"])
        let added = bookmarks.keep(["/Photos/A", "/Photos/B"], adding: ["/Photos/A": Data([1]), "/Photos/C": Data([3])])
        #expect(added && bookmarks.paths == ["/Photos/A"], "a folder not named isn't kept")
        #expect(bookmarks.lacking(["/Photos/A", "/Photos/B"]) == ["/Photos/B"])
        let again = bookmarks.keep(["/Photos/A", "/Photos/B"], adding: ["/Photos/A": Data([2])])
        #expect(!again && bookmarks.bookmark(for: "/Photos/A/") == Data([1]), "kept as it was")
        let dropped = bookmarks.keep(["/Photos/B"])
        #expect(dropped && bookmarks.paths.isEmpty)
    }

    @Test func `a folder chosen gets its bookmark where one can be made`() throws {
        defer { cleanUp() }
        let url = try folder("Exports")
        var bookmarks = FolderBookmarks()
        let first = bookmarks.remember(url)
        let second = bookmarks.remember(url)
        #expect(first == Self.makesSecurityScoped)
        #expect(!second, "made once")
        #expect((bookmarks.bookmark(for: url.path) != nil) == Self.makesSecurityScoped)
        let made = FolderBookmarks.make(for: [url.path, root.appending(path: "Nothing").path])
        #expect(made.keys.sorted() == (Self.makesSecurityScoped ? [url.standardizedFileURL.path] : []))
    }
}
