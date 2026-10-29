import Foundation
import RedlampLibrary

/// The left panel's counts (LIB-23): each Library and Library Health entry's photos and each collection's,
/// as their lists show them, so photos that can't be read count only where a check finds them (LIB-40); the
/// collection list, with the target collection; and the albums of Apple Photos kept in place, with each album's
/// photos (LIB-62). They're read off the main thread from the query engine and the index: a list per entry, the
/// index's counts of the collections less their photos that can't be read, a list per smart collection, and the
/// index's counts of the albums, which hold every photo Photos puts in them, as a folder holds its files.
struct LibraryCounts: Sendable, Equatable {
    /// Each entry with photos, by its source; an entry without any isn't offered.
    var entries: [LibrarySource: Int] = [:]
    /// Every set, collection and smart collection, by path.
    var collections: [CollectionPath: CollectionList.Collection] = [:]
    /// The collection Add to Target Collection puts photos in; nil for the quick collection (Marked).
    var target: CollectionPath?
    /// Each collection's and smart collection's photos, by path; sets have none.
    var collectionPhotos: [CollectionPath: Int] = [:]
    /// The index's IDs of the previous import's photos it has and can read.
    var previousImport: [Int64] = []
    /// Duplicate candidates no recorded hash confirms yet, which Exact Duplicates lists once they're read whole.
    var unconfirmedDuplicates = 0
    /// The part of Photos' tree kept in place, which the Apple Photos section lists (LIB-62).
    var applePhotos = ApplePhotosTree([])
    /// Each album's photos kept in place, by Photos' local identifier; folders have none.
    var applePhotosPhotos: [String: Int] = [:]

    /// The photos `source` holds; nil for a set and a folder of Apple Photos, and for an entry that isn't offered.
    func count(of source: LibrarySource) -> Int? {
        switch source {
        case let .collection(path):
            collections[path].map { $0.kind == .set ? nil : collectionPhotos[path] ?? 0 } ?? nil
        case let .applePhotos(id):
            applePhotos[id].map { $0.kind == .folder ? nil : applePhotosPhotos[id] ?? 0 } ?? nil
        default:
            entries[source]
        }
    }

    /// Whether the panels' rows are the same as `other`'s: the entries offered, the collection list's places,
    /// kinds and target, and the albums of Apple Photos kept with their titles. Counts aside.
    func hasSameRows(as other: LibraryCounts) -> Bool {
        Set(entries.keys) == Set(other.entries.keys) && target == other.target
            && collections.count == other.collections.count
            && collections.allSatisfy { other.collections[$0.key]?.kind == $0.value.kind }
            && applePhotos == other.applePhotos
    }

    /// The sources whose counts differ from `other`'s.
    func changed(from other: LibraryCounts) -> Set<LibrarySource> {
        var changed = Set<LibrarySource>()
        for source in Set(entries.keys).union(other.entries.keys) where entries[source] != other.entries[source] {
            changed.insert(source)
        }
        for path in Set(collectionPhotos.keys).union(other.collectionPhotos.keys)
            where collectionPhotos[path] != other.collectionPhotos[path] {
            changed.insert(.collection(path))
        }
        for album in Set(applePhotosPhotos.keys).union(other.applePhotosPhotos.keys)
            where applePhotosPhotos[album] != other.applePhotosPhotos[album] {
            changed.insert(.applePhotos(album))
        }
        return changed
    }

    /// The counts as the library has them now, Library Health's pairs under `rule`, with `previous`'s photos
    /// for Previous Import.
    static func read(core: LibraryCore, pairs rule: PairRule, previous: PreviousImport?) async throws
        -> LibraryCounts {
        let engine = core.engine
        var counts = LibraryCounts()
        let unreadable = try await Set(engine.list(.query(Self.unreadable)).ids)
        for source in LibrarySource.library + LibrarySource.healthChecks {
            if case .health(.pairs) = source, rule == .keepBoth {
                continue
            }
            guard let photos = source.photoSource(pairs: rule) else { continue }
            let count = try await engine.list(photos).count
            if count > 0 {
                counts.entries[source] = count
            }
        }
        counts.unconfirmedDuplicates = try await engine.healthFindings(.duplicates).unconfirmed
        if let previous {
            counts.previousImport = try await photos(of: previous, core: core)
            if !counts.previousImport.isEmpty {
                counts.entries[.previousImport] = counts.previousImport.count
            }
        }
        let list = try await LibraryMetadata(index: core.index, paths: core.paths).collections.list()
        counts.collections = list.collections
        counts.target = list.target
        for collection in list.collections.values where collection.kind == .collection {
            counts.collectionPhotos[collection.path] = collection.photos
        }
        if !unreadable.isEmpty {
            let kept = try await core.index.read { try $0.collectionPaths(ofPhotos: Array(unreadable)) }
            for path in kept.values.joined() where counts.collectionPhotos[path] != nil {
                counts.collectionPhotos[path, default: 0] -= 1
            }
        }
        for collection in list.collections.values where collection.kind == .smart {
            counts.collectionPhotos[collection.path] = try await engine.list(.collection(collection.path)).count
        }
        (counts.applePhotos, counts.applePhotosPhotos) = try await core.index.read { reader in
            try (reader.applePhotosKeptTree(), reader.applePhotosAlbumCounts())
        }
        return counts
    }

    /// The index's IDs of `previous`'s photos, in order, as its list has them: of the photos the index still has,
    /// those the store holds and can read.
    static func photos(of previous: PreviousImport, core: LibraryCore) async throws -> [Int64] {
        let urls = previous.photos.map { URL(fileURLWithPath: $0, isDirectory: false) }
        let found = await Set(LibraryService.indexIDs(of: urls, in: core.index).values)
        return try await core.engine.list(.photos(found)).ids.sorted()
    }

    private static let unreadable = LibraryQuery.filter(LibraryQuery.Filter(.unreadable, .equal, [.bool(true)]))
}
