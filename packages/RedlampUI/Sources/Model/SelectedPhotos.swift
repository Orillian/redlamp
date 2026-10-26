import Foundation
import RedlampDocument

/// The photos an action on the whole of a selection works through, in the filmstrip's order, as they were when it
/// began (LIB-10): their addresses at once, or for a large source's, the addresses of those whose rows aren't read
/// found in the index off the main thread as the action reaches them, a batch at a time, and no row kept for them. An
/// action on a million photos, which waited 3 s for every row, starts at once. A version of a photo's edit is a photo
/// of its own (LIB-48): actions on edits and metadata take each address, actions on files each file once (`files()`).
struct SelectedPhotos: Sendable {
    /// How many there are.
    let count: Int
    /// Every address, when all are known.
    let addresses: [PhotoAddress]?
    private let ids: ContiguousArray<Int64>
    private let read: [Int64: PhotoAddress]
    private let source: LargeListRows?

    init(_ addresses: [PhotoAddress]) {
        count = addresses.count
        self.addresses = addresses
        ids = []
        read = [:]
        source = nil
    }

    /// A large source's photos `ids`, the addresses of those whose rows are read in `read`, the others read from
    /// `source`.
    init(ids: ContiguousArray<Int64>, read: [Int64: PhotoAddress], source: LargeListRows) {
        count = ids.count
        addresses = nil
        self.ids = ids
        self.read = read
        self.source = source
    }

    /// The addresses of the photos at `range` of them, in order; photos the index no longer has are left out.
    func addresses(_ range: Range<Int>) async -> [PhotoAddress] {
        if let addresses {
            return Array(addresses[range])
        }
        let wanted = ids[range]
        let missing = Array(wanted.lazy.filter { read[$0] == nil })
        let found = missing.isEmpty ? [:] : await (try? source?.addresses(of: missing)) ?? [:]
        return wanted.compactMap { read[$0] ?? found[$0] }
    }

    /// Every one's address, in order.
    func all() async -> [PhotoAddress] {
        await addresses(0 ..< count)
    }

    /// Each file's URL once, in order, for an action on files: a version stands for its file.
    func files() async -> [URL] {
        await Self.files(of: all())
    }

    /// The files of `photos`, each once, in the order of each one's first photo.
    static func files(of photos: [PhotoAddress]) -> [URL] {
        var seen = Set<URL>()
        return photos.compactMap { seen.insert($0.url).inserted ? $0.url : nil }
    }

    /// Their addresses `size` at a time, in order, each batch read while the one before is worked through.
    func batches(of size: Int) -> Batches {
        Batches(photos: self, size: max(size, 1))
    }

    struct Batches {
        fileprivate let photos: SelectedPhotos
        fileprivate let size: Int
        private var start = 0
        private var coming: Task<[PhotoAddress], Never>?

        fileprivate init(photos: SelectedPhotos, size: Int) {
            self.photos = photos
            self.size = size
        }

        /// The next batch; nil after the last.
        mutating func next() async -> [PhotoAddress]? {
            guard start < photos.count else { return nil }
            let batch = await (coming ?? reading(from: start)).value
            start = min(start + size, photos.count)
            coming = start < photos.count ? reading(from: start) : nil
            return batch
        }

        private func reading(from first: Int) -> Task<[PhotoAddress], Never> {
            let (photos, range) = (photos, first ..< min(first + size, photos.count))
            return Task { await photos.addresses(range) }
        }
    }
}
