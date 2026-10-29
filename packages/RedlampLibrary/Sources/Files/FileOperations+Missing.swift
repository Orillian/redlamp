import Foundation
import RedlampDocument

/// A missing photo (DEC-59) and the file it's found as, in one of the library's folders: what a relink takes.
public struct PhotoRelink: Sendable, Hashable {
    public var id: Int64
    public var path: String

    public init(id: Int64, path: String) {
        self.id = id
        self.path = path
    }
}

public extension FileOperations {
    /// The batch that takes missing photos `ids` out of the library (DEC-59) with nothing moved, their rows as they are
    /// kept in the journal for Undo; those that aren't missing are left out. A version of a photo's edit stands for its
    /// file (LIB-48), which goes with its versions' rows, all in one step.
    func planRemoval(ofMissing ids: [Int64]) async throws -> FileBatch {
        let files = try await index.read { reader in
            try reader.photosWithPaths(reader.fileRows(of: ids)).filter { $0.photo.state.contains(.missing) }
                .map { photo, folder in
                    try ([photo] + reader.versions(folder: photo.folder, name: photo.name)).map { row in
                        try Self.removed(row, folder: folder, reader)
                    }
                }
        }
        var steps: [FileStep] = []
        for rows in files {
            if let last = steps.last, last.removed.count + rows.count <= Self.removalStep {
                steps[steps.count - 1].removed += rows
            } else {
                steps.append(FileStep(kind: .removeFromLibrary, removed: rows))
            }
        }
        let count = files.count
        return FileBatch(kind: .remove, title: "Remove \(count) missing photo\(count == 1 ? "" : "s")", steps: steps)
    }

    /// Remove from Library for photos kept in Apple Photos (LIB-62): the batch that takes every row of the assets of
    /// photos `ids` out of the library, their versions with them, nothing moved and nothing changed in Photos; their
    /// rows are kept in the journal for Undo, and their sidecars stay. No pass gives the assets rows again until Add
    /// Albums keeps an album holding them (`ApplePhotosIndexer.removed`). Photos in folders are left out.
    func planRemoval(ofApplePhotos ids: [Int64]) async throws -> FileBatch {
        let assets = try await index.read { reader -> [[RemovedPhoto]] in
            var seen = Set<String>()
            var assets: [[RemovedPhoto]] = []
            for id in try reader.fileRows(of: ids) {
                guard let local = try reader.applePhotosRow(ofPhoto: id)?.local, seen.insert(local).inserted
                else { continue }
                try assets
                    .append(reader.photosWithPaths(reader.applePhotosRowIDs(ofAsset: local)).flatMap { photo, folder in
                        try ([photo] + reader.versions(folder: photo.folder, name: photo.name)).map { row in
                            try Self.removed(row, folder: folder, reader)
                        }
                    })
            }
            return assets
        }
        var steps: [FileStep] = []
        for rows in assets {
            if let last = steps.last, last.removed.count + rows.count <= Self.removalStep {
                steps[steps.count - 1].removed += rows
            } else {
                steps.append(FileStep(kind: .removeFromLibrary, removed: rows))
            }
        }
        let count = assets.count
        return FileBatch(
            kind: .remove, title: "Remove \(count) photo\(count == 1 ? "" : "s") from the library", steps: steps,
        )
    }

    /// The batch that relinks each missing photo of `relinks` to the file it's found as (DEC-59): its row moved there,
    /// keeping its ID, everything decided about it and its collections, and read again from the file; the row the file
    /// had, indexed as a new photo meanwhile, taken out. When the file has no `.redlamp` sidecar, the one the photo
    /// left
    /// behind comes beside it, or, with none left behind, one is written with what the photo's row holds. Photos that
    /// aren't missing, files gone or outside the library's folders, files another missing photo had, and a second photo
    /// for one file are left out.
    func planRelink(_ relinks: [PhotoRelink]) async throws -> FileBatch {
        let found = try await index.read { reader in
            var found: [(relink: PhotoRelink, photo: [RemovedPhoto], holder: [RemovedPhoto])] = []
            var files = Set<String>()
            func removed(_ photo: PhotoRecord, folder: String) throws -> [RemovedPhoto] {
                try ([photo] + reader.versions(folder: photo.folder, name: photo.name)).map { row in
                    try Self.removed(row, folder: folder, reader)
                }
            }
            for relink in relinks {
                let path = relink.path
                guard try reader.root(containing: path) != nil, files.insert(NamingJob.fold(path)).inserted,
                      let id = try reader.fileRow(of: relink.id),
                      let (photo, folder) = try reader.photosWithPaths([id]).first, photo.state.contains(.missing)
                else { continue }
                var holder: [RemovedPhoto] = []
                if let held = try reader.photo(path: path), held.id != photo.id {
                    guard !held.state.contains(.missing) else { continue }
                    holder = try removed(held, folder: FilePlanner.split(path).folder)
                }
                try found.append((relink, removed(photo, folder: folder), holder))
            }
            return found
        }
        let locator = try await locator()
        let fileSystem = fileSystem
        let steps = try await LibraryIndex.offCaller {
            let planner = FilePlanner(fileSystem: fileSystem, locator: locator)
            var holders: [RemovedPhoto] = []
            var relinked: [FileStep] = []
            for (relink, rows, holder) in found {
                guard let file = planner.entry(relink.path), !file.isDirectory else { continue }
                let photo = rows[0]
                let was = photo.folder + "/" + photo.photo.name
                var step = FileStep(
                    kind: .relink, items: [Self.item(.photo, relink.path, to: nil, file)],
                    photos: [PhotoMove(id: photo.photo.id, from: was, to: relink.path)], removed: rows,
                )
                let (at, from) = (URL(fileURLWithPath: relink.path), URL(fileURLWithPath: was))
                let beside = SidecarLocator.besidePhoto(at).path
                let onThisMac = locator.onThisMac(at)?.path
                if planner.entry(beside) == nil, onThisMac.flatMap(planner.entry) == nil {
                    let leftBeside = SidecarLocator.besidePhoto(from).path
                    if let left = planner.entry(leftBeside) {
                        step.items.append(Self.item(.sidecar, leftBeside, to: beside, left))
                    } else if let leftOnThisMac = locator.onThisMac(from)?.path, let onThisMac,
                              let left = planner.entry(leftOnThisMac) {
                        step.items.append(Self.item(.sidecarOnThisMac, leftOnThisMac, to: onThisMac, left))
                    } else {
                        step.writesDecisions = photo.photo.sidecarModified != nil
                    }
                }
                holders += holder
                relinked.append(step)
            }
            return (holders.isEmpty ? [] : [FileStep(kind: .removeFromLibrary, removed: holders)]) + relinked
        }
        let count = steps.count { $0.kind == .relink }
        return FileBatch(kind: .relink, title: "Relink \(count) missing photo\(count == 1 ? "" : "s")", steps: steps)
    }

    /// Missing photos a removal takes out a step at a time.
    internal static let removalStep = 500

    private static func removed(_ photo: PhotoRecord, folder: String, _ reader: some IndexQueries) throws
        -> RemovedPhoto {
        let asset = try reader.applePhotosRow(ofPhoto: photo.id)
        return try RemovedPhoto(
            photo: IndexedPhoto(photo), folder: folder, keywords: reader.keywords(forPhoto: photo.id),
            collections: reader.collectionPlaces(ofPhoto: photo.id), asset: asset,
            albums: asset == nil ? nil : reader.applePhotosAlbums(ofPhoto: photo.id),
        )
    }

    private static func item(_ role: FileItem.Role, _ path: String, to destination: String?, _ entry: FileEntry)
        -> FileItem {
        FileItem(
            role: role, source: path, destination: destination, fileID: entry.fileIdentifier,
            size: entry.isDirectory ? nil : entry.size, modified: entry.isDirectory ? nil : entry.modified,
            isDirectory: entry.isDirectory,
        )
    }
}
