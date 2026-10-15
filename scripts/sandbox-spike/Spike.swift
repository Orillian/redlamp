import AppKit
import CoreServices
import Foundation

// ARC-17's spike: what the App Sandbox allows Redlamp (`run.sh` builds and runs it). Built twice
// from this file, sandboxed and not, signed with one identity under one bundle ID, and opened by
// Launch Services, which grants it the documents it's given. Its mode is the name of the `out-<mode>`
// folder among them; in `out-docs`, photos get the related-item tests and folders a bookmark.

setvbuf(stdout, nil, _IONBF, 0)

/// The log, in the `out-<mode>` folder the spike is opened with: `open` from an agent's shell
/// passes neither `--args` nor `--stdout`, and Launch Services grants the folder.
nonisolated(unsafe) var logFile: FileHandle?

func say(_ line: String) {
    print(line)
    logFile?.write(Data((line + "\n").utf8))
}

let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

func describe(_ error: Error) -> String {
    let ns = error as NSError
    var text = "\(ns.domain) \(ns.code)"
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
        text += " (\(underlying.domain) \(underlying.code))"
    }
    return text
}

func list(_ url: URL) -> String {
    do {
        let items = try FileManager.default.contentsOfDirectory(atPath: url.path)
        return "ok, \(items.count) items"
    } catch {
        return "refused: \(describe(error))"
    }
}

func tryWrite(in folder: URL) -> String {
    let file = folder.appending(path: "spike-write-\(UUID().uuidString.prefix(4)).txt")
    do {
        try Data("x".utf8).write(to: file)
        try FileManager.default.removeItem(at: file)
        return "ok"
    } catch {
        return "refused: \(describe(error))"
    }
}

func inode(_ url: URL) -> String {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let number = attributes[.systemFileNumber] else { return "none" }
    return "\(number)"
}

// MARK: - Related items

final class RelatedPresenter: NSObject, NSFilePresenter {
    let primaryPresentedItemURL: URL?
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()

    init(primary: URL, related: URL) {
        primaryPresentedItemURL = primary
        presentedItemURL = related
    }
}

func coordinated(
    _ related: URL, primary: URL?, writing options: NSFileCoordinator.WritingOptions?,
    _ body: (URL) throws -> String,
) -> String {
    var presenter: RelatedPresenter?
    if let primary {
        let made = RelatedPresenter(primary: primary, related: related)
        NSFileCoordinator.addFilePresenter(made)
        presenter = made
    }
    defer {
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
        }
    }
    var outcome = "not run"
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator(filePresenter: presenter)
    let run: (URL) -> Void = { url in
        do {
            outcome = try body(url)
        } catch {
            outcome = "refused: \(describe(error))"
        }
    }
    if let options {
        coordinator.coordinate(writingItemAt: related, options: options, error: &coordinationError, byAccessor: run)
    } else {
        coordinator.coordinate(readingItemAt: related, options: [], error: &coordinationError, byAccessor: run)
    }
    if let coordinationError {
        outcome = "coordination refused: \(describe(coordinationError))"
    }
    return outcome
}

func writePackage(at url: URL) throws -> String {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    try Data("{\"spike\":1}".utf8).write(to: url.appending(path: "edit.json"), options: .atomic)
    let masks = url.appending(path: "masks")
    try FileManager.default.createDirectory(at: masks, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: masks.appending(path: "a.png"), options: .atomic)
    return "ok"
}

func related(photo: URL) {
    let folder = photo.deletingLastPathComponent()
    let name = photo.lastPathComponent
    let base = photo.deletingPathExtension().lastPathComponent
    switch base {
    case "A":
        let sidecar = folder.appending(path: name + ".redlamp")
        say("R1 \(sidecar.lastPathComponent), a package written in place: "
            + coordinated(sidecar, primary: photo, writing: []) { try writePackage(at: $0) })
        say("R1b then rewriting its edit.json atomically: "
            + coordinated(sidecar, primary: photo, writing: []) { url in
                try Data("{\"spike\":2}".utf8).write(to: url.appending(path: "edit.json"), options: .atomic)
                return "ok"
            })
    case "B":
        let sidecar = folder.appending(path: name + ".redlamp")
        say("R2 \(sidecar.lastPathComponent), built in a hidden sibling and moved in, as Redlamp does: "
            + coordinated(sidecar, primary: photo, writing: []) { url in
                let staging = url.deletingLastPathComponent()
                    .appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
                _ = try writePackage(at: staging)
                try FileManager.default.moveItem(at: staging, to: url)
                return "ok"
            })
    case "C":
        let sidecar = folder.appending(path: base + ".redlamp")
        say("R3 \(sidecar.lastPathComponent), the documented naming, a package in place: "
            + coordinated(sidecar, primary: photo, writing: []) { try writePackage(at: $0) })
        let xmp = folder.appending(path: base + ".xmp")
        say("R4 \(xmp.lastPathComponent), written atomically: "
            + coordinated(xmp, primary: photo, writing: .forReplacing) { url in
                try Data("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"/>".utf8).write(to: url, options: .atomic)
                return "ok"
            })
    case "D":
        let sidecar = folder.appending(path: name + ".redlamp")
        say("R5 reading \(sidecar.lastPathComponent)/edit.json, already there: "
            + coordinated(sidecar, primary: photo, writing: nil) { url in
                try "ok, \(Data(contentsOf: url.appending(path: "edit.json")).count) bytes"
            })
        let darktable = folder.appending(path: name + ".xmp")
        say("R6 reading \(darktable.lastPathComponent), darktable's naming: "
            + coordinated(darktable, primary: photo, writing: nil) { url in
                try "ok, \(Data(contentsOf: url).count) bytes"
            })
        let xmp = folder.appending(path: base + ".xmp")
        say("R7 reading \(xmp.lastPathComponent): "
            + coordinated(xmp, primary: photo, writing: nil) { url in
                try "ok, \(Data(contentsOf: url).count) bytes"
            })
    case "E":
        let sidecar = folder.appending(path: name + ".redlamp")
        say("R0a \(sidecar.lastPathComponent) with no presenter: "
            + coordinated(sidecar, primary: nil, writing: []) { try writePackage(at: $0) })
        let other = folder.appending(path: "E-unrelated.txt")
        say("R0b \(other.lastPathComponent), a name that isn't related, with a presenter: "
            + coordinated(other, primary: photo, writing: .forReplacing) { url in
                try Data("x".utf8).write(to: url)
                return "ok"
            })
        say("R0c reading the photo itself: " +
            ((try? Data(contentsOf: photo)).map { "ok, \($0.count) bytes" } ?? "refused"))
    default:
        say("photo \(name): no test")
    }
}

// MARK: - Bookmarks

func makeBookmark(folder: URL) {
    say("B1 listing the folder just opened: " + list(folder))
    do {
        let scoped = try folder.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil,
        )
        UserDefaults.standard.set(scoped, forKey: "folderBookmark")
        UserDefaults.standard.set(folder.path, forKey: "folderPath")
        say("B1 security-scoped bookmark, without the app-scope entitlement: ok, \(scoped.count) bytes")
    } catch {
        say("B1 security-scoped bookmark refused: \(describe(error))")
    }
}

func fsevents(_ folder: URL) -> String {
    final class Box: @unchecked Sendable {
        var paths: [String] = []
    }
    let box = Box()
    var context = FSEventStreamContext(
        version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil,
        copyDescription: nil,
    )
    let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        let names = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
        box.paths += names
    }
    let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
    guard let stream = FSEventStreamCreate(
        nil, callback, &context, [folder.path] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags,
    ) else { return "stream not made" }
    let queue = DispatchQueue(label: "fsevents")
    FSEventStreamSetDispatchQueue(stream, queue)
    FSEventStreamStart(stream)
    Thread.sleep(forTimeInterval: 0.5)
    let file = folder.appending(path: "spike-fsevents.txt")
    try? Data("y".utf8).write(to: file)
    Thread.sleep(forTimeInterval: 2)
    FSEventStreamStop(stream)
    FSEventStreamInvalidate(stream)
    FSEventStreamRelease(stream)
    try? FileManager.default.removeItem(at: file)
    return queue
        .sync {
            "\(box.paths.count) events, \(Set(box.paths.map { URL(fileURLWithPath: $0).lastPathComponent }).sorted())"
        }
}

func resolveSaved() {
    guard let data = UserDefaults.standard.data(forKey: "folderBookmark"),
          let path = UserDefaults.standard.string(forKey: "folderPath")
    else {
        say("B2 no saved bookmark")
        return
    }
    say("B2 listing by its path alone, before resolving: " + list(URL(fileURLWithPath: path)))
    var stale = false
    do {
        let url = try URL(
            resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale,
        )
        let started = url.startAccessingSecurityScopedResource()
        say("B2 resolved, stale \(stale), access started \(started)")
        say("B2 list: " + list(url))
        say("B2 list a subfolder: " + list(url.appending(path: "sub")))
        let file = url.appending(path: "spike-trash.txt")
        do {
            try Data("x".utf8).write(to: file)
            say("B2 write a file: ok")
            var trashed: NSURL?
            try FileManager.default.trashItem(at: file, resultingItemURL: &trashed)
            say("B2 move it to the Trash: ok, to \(trashed?.path ?? "?")")
            if let trashed {
                try? FileManager.default.removeItem(at: trashed as URL)
            }
        } catch {
            say("B2 write or trash refused: \(describe(error))")
        }
        let renamed = url.appending(path: "sub-renamed")
        do {
            try FileManager.default.moveItem(at: url.appending(path: "sub"), to: renamed)
            try FileManager.default.moveItem(at: renamed, to: url.appending(path: "sub"))
            say("B2 rename a subfolder and back: ok")
        } catch {
            say("B2 rename refused: \(describe(error))")
        }
        do {
            let target = url.appending(path: "file.txt")
            let staging = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true,
            )
            let staged = staging.appending(path: "file.txt")
            try Data("replaced".utf8).write(to: staged)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
            try? FileManager.default.removeItem(at: staging)
            say("B2 an export staged in the item-replacement folder, \(staging.path), then moved in: ok")
        } catch {
            say("B2 staging in the item-replacement folder refused: \(describe(error))")
        }
        say("B2 FSEvents on the folder: " + fsevents(url))
        url.stopAccessingSecurityScopedResource()
        say("B2 list after access stopped: " + list(url))
    } catch {
        say("B2 resolve refused: \(describe(error))")
    }
}

func mint(folder: String, out: String) {
    let url = URL(fileURLWithPath: folder, isDirectory: true)
    var lines: [String] = []
    let kinds: [(String, URL.BookmarkCreationOptions)] = [
        ("plain", []), ("scoped", [.withSecurityScope]),
        ("readonly", [.withSecurityScope, .securityScopeAllowOnlyReadAccess]),
    ]
    for (kind, options) in kinds {
        do {
            let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
            lines.append("\(kind)=\(data.base64EncodedString())")
            say("M1 \(kind) bookmark made unsandboxed: ok, \(data.count) bytes")
        } catch {
            say("M1 \(kind) bookmark refused: \(describe(error))")
        }
    }
    try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
}

func useMinted(_ arguments: [String]) {
    for argument in arguments {
        let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let data = Data(base64Encoded: parts[1]) else { continue }
        for scoped in [true, false] {
            var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
            if scoped {
                options.insert(.withSecurityScope)
            }
            var stale = false
            let how = "\(parts[0]) bookmark resolved \(scoped ? "with" : "without") security scope"
            do {
                let url = try URL(
                    resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale,
                )
                let started = url.startAccessingSecurityScopedResource()
                say("M2 \(how): started \(started), stale \(stale), list \(list(url)), write \(tryWrite(in: url))")
                if started {
                    url.stopAccessingSecurityScopedResource()
                }
            } catch {
                say("M2 \(how): refused: \(describe(error))")
            }
        }
    }
}

// MARK: - The container

func seed() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "SandboxSpike/Models", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let big = support.appending(path: "big.bin")
    FileManager.default.createFile(atPath: big.path, contents: Data(repeating: 7, count: 64 << 20))
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.bundleIdentifier ?? "app.redlamp.sandbox-spike", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: caches.appending(path: "thumb.bin").path, contents: Data(count: 1024))
    UserDefaults.standard.set("seeded unsandboxed", forKey: "seed")
    UserDefaults.standard.set(Data("plain bookmark stand-in".utf8), forKey: "folders.roots")
    UserDefaults.standard.synchronize()
    say("C1 seeded \(big.path), inode \(inode(big)), and a preference")
}

func report() {
    say("C2 NSHomeDirectory \(NSHomeDirectory())")
    say("C2 HOME \(ProcessInfo.processInfo.environment["HOME"] ?? "unset")")
    say("C2 CFFIXED_USER_HOME \(ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? "unset")")
    say("C2 NSTemporaryDirectory \(NSTemporaryDirectory())")
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let big = support.appending(path: "SandboxSpike/Models/big.bin")
    say("C2 Application Support \(support.path)")
    say("C2 big.bin there: \(FileManager.default.fileExists(atPath: big.path)), inode \(inode(big))")
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let thumb = caches.appending(path: "\(Bundle.main.bundleIdentifier ?? "")/thumb.bin")
    say("C2 Caches \(caches.path), thumb.bin there: \(FileManager.default.fileExists(atPath: thumb.path))")
    say("C2 preference seed: \(UserDefaults.standard.string(forKey: "seed") ?? "missing")")
    say("C2 preference fromSandbox, before: \(UserDefaults.standard.string(forKey: "fromSandbox") ?? "missing")")
    if isSandboxed {
        UserDefaults.standard.set("written sandboxed \(Date())", forKey: "fromSandbox")
        UserDefaults.standard.synchronize()
    }
    say(
        "C2 preference folders.roots: \(UserDefaults.standard.data(forKey: "folders.roots").map { "\($0.count) bytes" } ?? "missing")",
    )
    if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
        let home = String(cString: directory)
        say("C2 the real home \(home); its Application Support: "
            + list(URL(fileURLWithPath: home + "/Library/Application Support")))
        say("C2 its ~/Library/Logs/DiagnosticReports: "
            + list(URL(fileURLWithPath: home + "/Library/Logs/DiagnosticReports")))
    }
}

func cleanup() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    try? FileManager.default.removeItem(at: support.appending(path: "SandboxSpike"))
    try? FileManager.default
        .removeItem(at: caches.appending(path: Bundle.main.bundleIdentifier ?? "app.redlamp.sandbox-spike"))
    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    say("cleanup: removed what the spike kept")
}

// MARK: - Volumes

final class VolumeWatch: NSObject {
    var seen = false

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(mounted(_:)), name: NSWorkspace.didMountNotification, object: nil,
        )
    }

    @objc func mounted(_ note: Notification) {
        guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        say("V2 mount notification for \(url.path)")
        say("V2 list the new volume: " + list(url))
        say("V2 list its DCIM: " + list(url.appending(path: "DCIM")))
        let keys: Set<URLResourceKey> = [.volumeIsEjectableKey, .volumeUUIDStringKey, .volumeNameKey]
        let values = try? url.resourceValues(forKeys: keys)
        say(
            "V2 its name \(values?.volumeName ?? "?"), ejectable \(values?.volumeIsEjectable.map(String.init) ?? "?"), UUID \(values?.volumeUUIDString ?? "?")",
        )
        seen = true
    }
}

func volumes(wait seconds: TimeInterval) {
    say("V1 list /Volumes: " + list(URL(fileURLWithPath: "/Volumes")))
    let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeUUIDStringKey]
    let mounted = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: keys,
        options: [.skipHiddenVolumes],
    ) ?? []
    for volume in mounted {
        let values = try? volume.resourceValues(forKeys: Set(keys))
        say(
            "V1 mountedVolumeURLs: \(volume.path), ejectable \(values?.volumeIsEjectable.map(String.init) ?? "?"), UUID known \(values?.volumeUUIDString != nil), list \(list(volume))",
        )
    }
    let watch = VolumeWatch()
    watch.start()
    let deadline = Date().addingTimeInterval(seconds)
    while !watch.seen, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    }
    if !watch.seen {
        say("V2 no mount notification in \(Int(seconds)) s")
    }
}

// MARK: - The app

final class Delegate: NSObject, NSApplicationDelegate {
    var opened: [URL] = []

    func application(_: NSApplication, open urls: [URL]) {
        opened += urls
    }

    func applicationDidFinishLaunching(_: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.run()
            exit(0)
        }
    }

    func run() {
        let out = opened.first { $0.lastPathComponent.hasPrefix("out-") }
        let subjects = opened.filter { $0 != out }
        if let out {
            let file = out.appending(path: "log.txt")
            FileManager.default.createFile(atPath: file.path, contents: nil)
            logFile = FileHandle(forWritingAtPath: file.path)
            if logFile == nil {
                print("couldn't open the log in \(out.path)")
            }
        }
        let mode = out.map { String($0.lastPathComponent.dropFirst(4)) } ?? "docs"
        say(
            "SandboxSpike, \(isSandboxed ? "sandboxed" : "not sandboxed"), mode \(mode), opened \(opened.map(\.lastPathComponent))",
        )
        switch mode {
        case "seed": seed()
        case "mint":
            if let out {
                mint(
                    folder: out.deletingLastPathComponent().appending(path: "folderG").path,
                    out: out.appending(path: "minted.txt").path,
                )
            }
        case let mode where mode.hasPrefix("report"): report()
        case let mode where mode.hasPrefix("resolve"): resolveSaved()
        case let mode where mode.hasPrefix("useminted"):
            let minted = out.flatMap { try? String(
                contentsOf: $0.appending(path: "minted.txt"),
                encoding: .utf8,
            ) } ?? ""
            useMinted(minted.split(separator: "\n").map(String.init))
        case "volumes": volumes(wait: 25)
        case "cleanup": cleanup()
        default:
            for url in subjects {
                var isDirectory: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    makeBookmark(folder: url)
                } else {
                    related(photo: url)
                }
            }
        }
        say("done")
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
