import Foundation
import RedlampDocument
import RedlampEngineAPI

/// Copy to Folder over photos kept in Apple Photos (LIB-63, decision 7): LIB-54's import run over photos the library
/// keeps in place, chosen or an album's, each copy carrying what Redlamp keeps of its photo on this Mac (its edit,
/// versions, history, snapshots and metadata, its collections included), and then standing in for it (decision 9).
///
/// - **Their files** come from Redlamp's cache of originals (LIB-60): what isn't on this Mac is downloaded first, at an
///   export's priority, each held while it's staged so the cache's budget doesn't take it out meanwhile.
/// - **Their sidecars** are staged beside their files, read under coordination, so the card import copies each with
///   its photo; each is given what its photo's row shows where it holds nothing of its own (the rating, flag and
///   label, and Photos' caption and keywords from macOS 27), and the shift it gave the capture time is taken out, to
///   be given again over the time Photos has (`ApplePhotosCopy`).
/// - **No album becomes a collection,** and none is followed: the albums stay kept in place, where the copies stand in
///   for their photos (LIB-64).
struct ApplePhotosKept: Sendable {
    /// One of an asset's rows: where it is in the Apple Photos root, and the culling it shows.
    struct Row: Sendable, Hashable {
        /// Its address: where its original is in Redlamp's cache, or lands once it's downloaded.
        var url: URL
        var rating: Int
        var flag: PhotoFlag?
        var label: ColorLabel?
    }

    /// What the plan needs of the sidecars `prepare` staged.
    struct Prepared: Sendable {
        /// The shift and zone each staged photo's sidecar gave its capture time, taken out of it, by its path.
        var captureTimes: [String: (shift: Int, offset: Int?)] = [:]
        /// The staged photos whose sidecars hold a stack of Redlamp's, which stands over the stack Photos makes.
        var stacked: Set<String> = []
        /// The assets whose original has a Redlamp edit, which goes on top of Photos' edit, by local identifier.
        var editedOriginals: Set<String> = []
    }

    /// Each asset's rows by their names, the names its files are staged under, by local identifier.
    let rows: [String: [String: Row]]
    let originals: ApplePhotosOriginals?
    let locator: SidecarLocator

    /// The rows the index has of the assets `ids` names, and where their sidecars are.
    static func read(
        _ ids: [String], library: ImportLibrary, originals: ApplePhotosOriginals?,
    ) async throws -> ApplePhotosKept {
        guard let index = library.index else {
            return ApplePhotosKept(rows: [:], originals: originals, locator: .besidePhotos)
        }
        let rows = try await index.read { try $0.applePhotosKeptRows(ofAssets: ids) }
        let locator = try await LibrarySidecars(index: index, paths: library.paths).locator()
        return ApplePhotosKept(rows: rows, originals: originals, locator: locator)
    }

    /// The addresses of the rows of the assets `ids` names.
    func urls(of ids: Set<String>) -> [URL] {
        ids.sorted().flatMap { rows[$0]?.values.map(\.url).sorted { $0.path < $1.path } ?? [] }
    }

    // MARK: - Staging

    /// Writes `name`, one of the files of asset `asset`, to `partial` from Redlamp's cache, downloading it first when
    /// it isn't on this Mac, `downloading` hearing how far the download has come. False when it isn't a row the library
    /// keeps, or there's no cache, for Photos to write it.
    func write(
        _ name: String, of asset: String, to partial: URL, downloading: @escaping @Sendable (Double) -> Void,
    ) async throws -> Bool {
        guard let originals, let row = rows[asset]?[name] else { return false }
        originals.hold(row.url)
        defer { originals.release(row.url) }
        let local = try await originals.local(row.url, priority: .export) { downloading($0.fraction) }
        try FileManager.default.copyItem(at: local, to: partial)
        return true
    }

    /// Stages the sidecar on this Mac of row `name` of asset `asset` beside its file at `target`, in place of one
    /// staged before: what Redlamp keeps of the photo now. Nothing is staged for a row without one.
    func stageSidecar(of name: String, of asset: String, beside target: URL) throws {
        let staged = SidecarLocator.besidePhoto(target)
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        guard let row = rows[asset]?[name], let source = locator.onThisMac(row.url),
              FileManager.default.fileExists(atPath: source.path)
        else { return }
        var copied: Result<Void, any Error> = .success(())
        var coordination: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], error: &coordination) {
            source in
            copied = Result { try FileManager.default.copyItem(at: source, to: staged) }
        }
        if let coordination {
            throw coordination
        }
        try copied.get()
    }

    /// Gives each staged file's sidecar what its row shows of Photos' fields where the sidecar holds nothing of its
    /// own, making one where none was staged, and takes out the shift it gave the capture time; returns what the plan
    /// needs of them.
    func prepare(_ staged: [ApplePhotosStager.Staged], assets: [String: ApplePhotosAsset]) throws -> Prepared {
        var prepared = Prepared()
        let store = SidecarStore()
        for item in staged {
            guard let asset = assets[item.asset] else { continue }
            let folder = LibraryIndexer.path(item.folder)
            for name in item.originals + (item.edit.map { [$0] } ?? []) {
                let path = folder + "/" + name
                let photo = URL(fileURLWithPath: path, isDirectory: false)
                var sidecar = try store.loadThrowing(for: photo) ?? Sidecar(recipe: EditRecipe())
                var metadata = sidecar.metadata ?? PhotoMetadata()
                if let row = rows[asset.id]?[name] {
                    metadata.rating = row.rating
                    metadata.flag = row.flag
                    metadata.label = row.label
                } else if sidecar.metadata == nil {
                    metadata.rating = asset.rating ?? 0
                    metadata.flag = asset.isFavorite ? .pick : nil
                }
                if metadata.caption == nil {
                    metadata.caption = XMPFields.text(asset.caption)
                }
                if metadata.keywords == nil, let keywords = asset.keywords, !keywords.isEmpty {
                    metadata.keywords = keywords.compactMap { KeywordPath(names: [$0])?.text }
                }
                if metadata.captureShift != 0 || metadata.captureOffset != nil {
                    prepared.captureTimes[path] = (metadata.captureShift, metadata.captureOffset)
                    metadata.captureShift = 0
                }
                if metadata.stack != nil {
                    prepared.stacked.insert(path)
                }
                if name == item.originals.first, !sidecar.recipe.isPristine {
                    prepared.editedOriginals.insert(asset.id)
                }
                sidecar.metadata = metadata.isEmpty ? nil : metadata
                try store.save(sidecar, for: photo)
            }
        }
        return prepared
    }
}

extension IndexQueries {
    /// The rows of the Apple Photos root of the assets `ids` names, by their local identifiers and the rows' names:
    /// where each is and the culling it shows. Rows marked missing are left out, and so are versions, which their
    /// file's sidecar holds.
    func applePhotosKeptRows(ofAssets ids: [String]) throws -> [String: [String: ApplePhotosKept.Row]] {
        let statement = try database.cached("""
        SELECT f.path, p.name, p.id FROM photo_assets a JOIN photos p ON p.id = a.photo JOIN folders f ON f.id = p.folder
          WHERE a.local_id = ? AND p.version = '' AND p.state & \(PhotoRecord.State.missing.rawValue) = 0
        """)
        var rows: [String: [String: ApplePhotosKept.Row]] = [:]
        for id in ids {
            try statement.bind(id, at: 1)
            var found: [(folder: String, name: String, photo: Int64)] = []
            try statement.forEachRow { row in
                found.append((row.string(at: 0) ?? "", row.string(at: 1) ?? "", row.int64(at: 2)))
            }
            for (folder, name, photo) in found {
                guard let record = try self.photo(id: photo) else { continue }
                rows[id, default: [:]][name] = ApplePhotosKept.Row(
                    url: URL(fileURLWithPath: folder + "/" + name, isDirectory: false), rating: record.rating,
                    flag: record.flag, label: record.label,
                )
            }
        }
        return rows
    }
}
