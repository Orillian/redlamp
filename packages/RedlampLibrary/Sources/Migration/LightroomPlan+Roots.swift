import Foundation

public extension LightroomPlan {
    /// The root folder each photo the import writes is in, by the root's ID in the report, in the order the import
    /// takes them, part by part; nil for a photo the index no longer has. The window counts each root folder's
    /// progress from it (LIB-52).
    func photoRoots(in index: LibraryIndex) async throws -> [Int64?] {
        let ids = photos.map(\.id)
        let paths = try await index.read { try $0.photoPaths(ids) }
        let roots = report.roots.compactMap { root in root.path.map { (id: root.id, path: $0) } }
            .sorted { $0.path.count > $1.path.count }
        return ids.map { id in
            guard let path = paths[id] else { return nil }
            return roots.first { path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }?.id
        }
    }
}
