import Foundation
import RedlampLibrary
import Synchronization

extension LibraryCommand {
    static let photosUsage = """
    usage: redlamp library photos --albums [--simulated <manifest>] [--json]
           redlamp library photos --census [--album <title or id>]… [--include-hidden] [--index <path>]
                                  [--simulated <manifest>] [--json]
           redlamp library photos --apply --destination <folder> [--album <title or id>]… [--include-hidden]
                                  [--folders <template>] [--names <template>] [--index <path>]
                                  [--simulated <manifest>] [--json]
           redlamp library photos --undo [--index <path>] [--simulated <manifest>] [--json]
      photos   reads Apple Photos through PhotoKit, only ever reading it, asking for access the first time.
               --albums lists its albums, folders, smart albums and shared albums, each folder's indented below
               it, with Photos' estimate of the photos in each and its ID. --census reports what importing the
               albums --album names (a title, a path of titles such as Trips/Lisbon, or an ID; a folder for its
               albums; every album without one, but smart and shared albums) would bring into the library at
               --index, the app's own without it: photos and RAW+JPEG pairs, photos edited in Photos, Live
               Photos, bursts, the videos and hidden photos it leaves, photos earlier imports brought, and the
               fields this Mac's PhotoKit gives and those macOS 27 would add. It names no album, photo or place,
               so it can be shared, and writes nothing. --apply imports them: each photo's files written into a
               hidden staging folder at --destination, then copied below it in folders and names from the
               templates (--folders {album} puts each in a folder named after its first album), checked, and
               indexed, each photo's .redlamp sidecar holding its favourite as a pick, its albums as
               collections and where it came from; an edit's rendering stacked over its original. --undo takes
               the last import back, its copies to the Trash. --include-hidden brings hidden photos.
               --simulated reads a simulated library's manifest (tests/fixtures/apple-photos/manifest.json)
               instead of Photos. --json prints JSON.
    """

    /// `redlamp library photos` (LIB-54): Apple Photos' albums, the census of an import from them, the import
    /// with `--apply` and the last import taken back with `--undo`. Exits 1 when Redlamp may not read Photos,
    /// or when an import or Undo left a photo out.
    static func photos(_ arguments: [String]) async throws {
        guard !arguments.contains("--help") else {
            print(photosUsage)
            return
        }
        let options = try Arguments(
            arguments, valued: ["--album", "--destination", "--folders", "--names", "--index", "--simulated"],
        )
        let modes = ["--albums", "--census", "--apply", "--undo"].filter(options.has)
        guard modes.count == 1 else {
            throw CLIError(description: "photos takes one of --albums, --census, --apply and --undo\n\n\(photosUsage)")
        }
        let json = options.has("--json")
        let source: any ApplePhotosLibrary = try options.value("--simulated").map {
            try SimulatedPhotosLibrary(manifest: URL(fileURLWithPath: $0).standardizedFileURL)
        } ?? PhotoKitLibrary()
        let indexURL = options.value("--index").map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? LibraryPaths.standard.index
        let paths = LibraryPaths(root: indexURL.deletingLastPathComponent())
        if modes[0] == "--undo" {
            return try await undoPhotos(source, index: indexURL, json: json)
        }
        var access = source.access()
        if access == .notDetermined {
            access = await source.requestAccess()
        }
        guard access.canRead else {
            FileHandle.standardError.write(Data("\(ApplePhotosError.noAccess(access))\n".utf8))
            throw ExitCode(1)
        }
        let tree = try await ApplePhotosTree(source.collections())
        if modes[0] == "--albums" {
            return try printAlbums(tree, json: json)
        }
        let settings = try ApplePhotosImport.Settings(
            collections: chosen(options.values("--album"), in: tree), includesHidden: options.has("--include-hidden"),
            copying: ImportSettings(
                destination: URL(fileURLWithPath: options.value("--destination") ?? paths.root.path, isDirectory: true)
                    .standardizedFileURL,
                folders: template(options.value("--folders"), or: ImportSettings.standardFolders),
                names: template(options.value("--names"), or: ImportSettings.standardNames),
            ),
        )
        if modes[0] == "--census" {
            let census = try await ApplePhotosImport(photos: source, library: ImportLibrary(paths: paths))
                .census(settings)
            if json {
                try print(String(decoding: census.report.json(), as: UTF8.self))
            } else {
                census.report.lines().forEach { print($0) }
            }
            return
        }
        guard options.value("--destination") != nil else {
            throw CLIError(description: "--apply needs --destination, the folder the photos go in")
        }
        let index = try await LibraryIndex.open(at: indexURL)
        let library = ImportLibrary.around(index)
        let result = await Result { try await applyPhotos(source, settings: settings, library: library, json: json) }
        library.store?.close()
        await index.close()
        try result.get()
    }

    /// The collections `named` names, by ID; nil for the standard choice.
    private static func chosen(_ named: [String], in tree: ApplePhotosTree) throws -> [String]? {
        guard !named.isEmpty else { return nil }
        return try named.map { name in
            guard let found = tree.resolve(name) else {
                throw CLIError(description: "Photos has no album \(name): --albums lists them")
            }
            return found.id
        }
    }

    private static func printAlbums(_ tree: ApplePhotosTree, json: Bool) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try print(String(decoding: encoder.encode(tree.collections), as: UTF8.self))
        }
        let kinds: [ApplePhotosCollection.Kind: String] = [
            .album: "album", .smartAlbum: "smart album", .sharedAlbum: "shared album, reduced copies",
            .folder: "folder",
        ]
        func walk(_ parent: String?, depth: Int) {
            for collection in tree.children(of: parent) {
                let count = collection.estimatedCount.map { ", \($0)" } ?? ""
                print(String(repeating: "  ", count: depth) + "\(collection.title) (\(kinds[collection.kind] ?? "")"
                    + "\(count))  \(collection.id)")
                walk(collection.id, depth: depth + 1)
            }
        }
        walk(nil, depth: 0)
    }

    private static func applyPhotos(
        _ source: any ApplePhotosLibrary, settings: ApplePhotosImport.Settings, library: ImportLibrary, json: Bool,
    ) async throws {
        let importing = ApplePhotosImport(photos: source, library: library)
        let reported = Mutex((stage: ApplePhotosImport.Stage.census, at: ContinuousClock.now))
        let outcome = try await importing.run(settings) { progress in
            let due = reported.withLock { last in
                guard progress.stage != last.stage || ContinuousClock.now - last.at >= .seconds(1) else { return false }
                last = (progress.stage, ContinuousClock.now)
                return true
            }
            if due, progress.photos > 0 {
                let downloading = progress.downloading > 0 ? ", \(progress.downloading) downloading from iCloud" : ""
                FileHandle.standardError.write(Data(
                    "  \(progress.stage.rawValue): \(progress.done) of \(progress.photos)\(downloading)\n".utf8,
                ))
            }
        }
        let failures = outcome.stagingFailures.count + (outcome.copy?.failures.count ?? 0)
        if json {
            let object: [String: Any] = try [
                "report": JSONSerialization.jsonObject(with: outcome.report.json()),
                "import": [
                    "id": outcome.id.uuidString, "state": outcome.state.rawValue, "staged": outcome.staged,
                    "imported": outcome.imported, "photos": outcome.copy?.verified ?? 0,
                    "sidecars": outcome.copy?.sidecars ?? 0, "indexed": outcome.copy?.indexed ?? 0,
                    "placesOnlyInPhotos": outcome.placesOnlyInPhotos,
                    "failures": outcome.stagingFailures.merging(
                        (outcome.copy?.failures ?? []).map { ($0.photo, $0.message) },
                    ) { first, _ in first },
                ],
            ]
            try print(String(decoding: JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
            ), as: UTF8.self))
        } else {
            outcome.report.lines().forEach { print($0) }
            print("Imported \(outcome.imported) from Apple Photos as \(outcome.copy?.verified ?? 0) photos, "
                + "checked, to \(settings.copying.destination.path): \(outcome.state.rawValue); "
                + "redlamp library photos --undo takes it back")
            for (asset, message) in outcome.stagingFailures.sorted(by: { $0.key < $1.key }) {
                print("  not imported: \(asset): \(message)")
            }
            for failure in outcome.copy?.failures ?? [] {
                print("  not copied: \(failure.photo): \(failure.message)")
            }
        }
        if failures > 0 || outcome.state != .finished {
            throw ExitCode(1)
        }
    }

    private static func undoPhotos(_ source: any ApplePhotosLibrary, index url: URL, json: Bool) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError(description: "no index at \(url.path)")
        }
        let index = try await LibraryIndex.open(at: url)
        let library = ImportLibrary.around(index)
        let result = await Result { try await ApplePhotosImport(photos: source, library: library).undo() }
        library.store?.close()
        await index.close()
        let undone: ApplePhotosImport.Undone
        switch result {
        case let .success(made): undone = made
        case let .failure(error as ApplePhotosImportError):
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            throw ExitCode(1)
        case let .failure(error): throw error
        }
        let trashed = undone.rollbacks.flatMap(\.trashed)
        let left = undone.rollbacks.flatMap(\.left)
        if json {
            try print(String(decoding: JSONSerialization.data(withJSONObject: [
                "undone": undone.record.id.uuidString, "photos": undone.record.photos,
                "trashed": trashed.map(\.to), "left": left.map(\.path),
            ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
        } else {
            print("Took back the import from Apple Photos of \(undone.record.photos) photos: \(trashed.count) files "
                + "moved to the Trash")
            for photo in left {
                print("  left where it was copied to: \(photo.path): \(photo.message)")
            }
        }
        if !left.isEmpty {
            throw ExitCode(1)
        }
    }
}

private extension Result where Failure == any Error {
    init(_ body: () async throws -> Success) async {
        do {
            self = try await .success(body())
        } catch {
            self = .failure(error)
        }
    }
}
