import CoreGraphics
import Foundation
import RedlampDocument
import RedlampLibrary

/// The grid's thumbnails, at the size its cells need (LIB-14): for a photo the library shows, the store's
/// grid tier up to its 384 pixels and its preview tier beyond, made there first when it has none; for any
/// other, the filmstrip's pack at the smallest size and the photo's embedded preview beyond. Each is
/// decoded off the main thread and drawn there in the window's colour space, so Core Animation shows it
/// as it is rather than converting it on the main thread as it commits. An edited photo's, once `renders`
/// has rendered its edit, is that render's tier (LIB-17). Kept in memory by the file and the edit they show,
/// which a file's photos with that edit, its own and its versions' (LIB-48), share, within a byte budget, the
/// photos on screen last to go. A photo left in Apple Photos has its tiers made from Photos' images (LIB-59), with
/// those on screen and a screen either side prepared by Photos ahead (`cache`).
@MainActor
final class GridThumbnails {
    /// The long edges thumbnails are decoded at; a cell takes the smallest at least as large as its image.
    nonisolated static let edges = [256, 384, 512, 768]

    static func edge(forPixels pixels: CGFloat) -> Int {
        edges.first { CGFloat($0) >= pixels } ?? edges[edges.count - 1]
    }

    /// A photo's thumbnail at `edge`, showing `edit`'s render, or with none its embedded preview.
    struct Key: Hashable {
        let url: URL
        let edge: Int
        let edit: EditDigest?
    }

    private struct Entry {
        let image: CGImage
        let cost: Int
        let size: Int64
        let modified: Date
        var used: UInt64
    }

    let budget: Int
    /// The photos on screen, which trimming keeps.
    var protected: Set<URL> = []
    /// The window's colour space; thumbnails drawn for another are dropped.
    var colorSpace: CGColorSpace? {
        didSet {
            if colorSpace != oldValue {
                removeAll()
            }
        }
    }

    private let scheduler: WorkScheduler
    private let decode: @Sendable (URL, Int) -> CGImage?
    private let store: @MainActor (LibraryItem) -> (StoreThumbnails, ContentKey)?
    private weak var renders: EditRenders?
    private let packs: ThumbnailPacks
    private var cache: [Key: Entry] = [:]
    private var used = 0
    private var tick: UInt64 = 0
    private var waiting: [Key: [UInt64: (CGImage?) -> Void]] = [:]
    private var requested: [UInt64: Key] = [:]
    private var lanes: [Key: WorkScheduler.Lane] = [:]
    private var nextID: UInt64 = 0
    /// Bumped when the cache is emptied: decodes started before then are dropped.
    private var generation = 0
    private var windowClosing: LibraryObservation?
    /// The photos left in Apple Photos whose thumbnails Photos had none of without iCloud when last asked: their
    /// cells show the cloud mark.
    private var inCloud: Set<URL> = []
    /// Photos prepares the pictures of what's on and near the screen: this grid's window of them, while it has one.
    private let photosWindow = "grid \(UUID().uuidString)"
    private var cachingIn: StoreThumbnails?

    init(
        scheduler: WorkScheduler, packs: ThumbnailPacks, budget: Int = 64 << 20,
        store: @escaping @MainActor (LibraryItem) -> (StoreThumbnails, ContentKey)?, renders: EditRenders? = nil,
        decode: @escaping @Sendable (URL, Int) -> CGImage?,
    ) {
        self.scheduler = scheduler
        self.packs = packs
        self.budget = budget
        self.store = store
        self.renders = renders
        self.decode = decode
        windowClosing = renders?.observeWindowClosing { [weak self] in self?.trim(to: 0) }
    }

    isolated deinit {
        if let cachingIn {
            let window = photosWindow
            scheduler.submit(.lookAhead) { cachingIn.photos?.cache([], tier: .grid, window: window) }
        }
    }

    var memoryUsed: Int {
        used
    }

    /// Whether Photos had none of `item`'s thumbnail without iCloud when last asked: a photo left in Apple Photos whose
    /// cell shows the cloud mark.
    func isInCloud(_ item: LibraryItem) -> Bool {
        inCloud.contains(item.url)
    }

    /// Has Photos prepare the thumbnails at `edge` of those of `items`, the photos on screen and a screen either side,
    /// left in Apple Photos with none in the store, for the requests their cells make (LIB-59); what the last call
    /// asked for and these leave out is let go.
    func cache(_ items: [LibraryItem], edge: Int) {
        var thumbnails: StoreThumbnails?
        var photos: [(url: URL, key: ContentKey, size: Int64, modified: Date)] = []
        for item in items {
            guard let (store, key) = store(item), store.isInApplePhotos(item.url) else { continue }
            thumbnails = store
            photos.append((item.url, key, item.size, item.modified))
        }
        guard let target = thumbnails ?? cachingIn else { return }
        cachingIn = photos.isEmpty ? nil : target
        let (window, tier, wanted) = (photosWindow, Self.tier(forEdge: edge), photos)
        scheduler
            .submit(.lookAhead, key: "\(window) cache") { target.photos?.cache(wanted, tier: tier, window: window) }
    }

    /// The store's tier a thumbnail at `edge` is decoded from: the grid's up to its size, the preview's beyond.
    nonisolated static func tier(forEdge edge: Int) -> PhotoStore.Tier {
        edge > PhotoStore.Tier.grid.pixelSize ? .preview : .grid
    }

    /// The edit `item`'s thumbnails show: its edit's digest once that's rendered, nil for its embedded
    /// preview.
    func edit(for item: LibraryItem) -> EditDigest? {
        renders?.shownEdit(for: item)
    }

    /// The thumbnail at `edge`, if it's in memory, still matches the file and shows the edit it's to show.
    func cached(_ item: LibraryItem, edge: Int) -> CGImage? {
        entry(Key(url: item.url, edge: edge, edit: edit(for: item)), item)
    }

    /// What's shown while the thumbnail at `edge` decodes, and the edit it shows: the largest in memory
    /// smaller than `edge`, else, until the edit's render is decoded, the embedded preview's at `edge` or
    /// smaller.
    func standIn(_ item: LibraryItem, below edge: Int) -> (image: CGImage, edit: EditDigest?)? {
        let wanted = edit(for: item)
        for smaller in Self.edges.reversed() where smaller < edge {
            if let image = entry(Key(url: item.url, edge: smaller, edit: wanted), item) {
                return (image, wanted)
            }
        }
        guard wanted != nil else { return nil }
        for candidate in Self.edges.reversed() where candidate <= edge {
            if let image = entry(Key(url: item.url, edge: candidate, edit: nil), item) {
                return (image, nil)
            }
        }
        return nil
    }

    private func entry(_ key: Key, _ item: LibraryItem) -> CGImage? {
        guard var entry = cache[key], entry.size == item.size, entry.modified == item.modified else { return nil }
        tick += 1
        entry.used = tick
        cache[key] = entry
        return entry.image
    }

    /// Asks for `item`'s thumbnail at `edge`; `completion` gets it on the main thread, or nil if it
    /// can't be made or the request is cancelled. Returns an id for `cancel`.
    @discardableResult
    func request(
        _ item: LibraryItem, edge: Int, lane: WorkScheduler.Lane = .onScreen,
        completion: @escaping (CGImage?) -> Void,
    ) -> UInt64 {
        nextID += 1
        let id = nextID
        if let image = cached(item, edge: edge) {
            completion(image)
            return id
        }
        let store = store(item)
        // A photo left in Apple Photos has its thumbnail from Photos, its original on this Mac or not.
        guard item.isLocal || store?.0.isInApplePhotos(item.url) == true, !item.isSettling else {
            completion(nil)
            return id
        }
        let key = Key(url: item.url, edge: edge, edit: edit(for: item))
        requested[id] = key
        if waiting[key] != nil {
            waiting[key]?[id] = completion
            promote(key, to: lane)
            return id
        }
        waiting[key] = [id: completion]
        lanes[key] = lane
        let (packs, decode, space, generation) = (packs, decode, colorSpace, generation)
        scheduler.submit(lane, key: Self.job(key)) {
            let loaded = Self.load(item, edge: edge, store: store, edit: key.edit, packs: packs, decode: decode)
            let image = loaded.image.flatMap { Self.drawn($0, in: space) }
            Task { @MainActor [weak self] in
                self?.finish(key, item, image, inCloud: loaded.inCloud, generation: generation)
            }
        }
        return id
    }

    /// Cancels one request, which completes with nil; the decode is dropped if nobody else waits for it.
    func cancel(_ id: UInt64) {
        guard let key = requested.removeValue(forKey: id),
              let completion = waiting[key]?.removeValue(forKey: id) else { return }
        if waiting[key]?.isEmpty == true {
            waiting[key] = nil
            lanes[key] = nil
            scheduler.cancel(Self.job(key))
        }
        completion(nil)
    }

    private func promote(_ key: Key, to lane: WorkScheduler.Lane) {
        guard let current = lanes[key], lane < current else { return }
        lanes[key] = lane
        scheduler.promote(Self.job(key), to: lane)
    }

    private static func job(_ key: Key) -> String {
        "grid:\(key.edge):" + (key.edit.map { "\($0):" } ?? "") + key.url.path
    }

    private func finish(_ key: Key, _ item: LibraryItem, _ image: CGImage?, inCloud: Bool, generation: Int) {
        lanes[key] = nil
        let completions = waiting.removeValue(forKey: key) ?? [:]
        for id in completions.keys {
            requested.removeValue(forKey: id)
        }
        if inCloud {
            self.inCloud.insert(item.url)
        } else if image != nil {
            self.inCloud.remove(item.url)
        }
        if let image, generation == self.generation {
            insert(image, for: key, item)
        } else if image == nil, let edit = key.edit {
            renders?.missing(item.address, edit)
        }
        for completion in completions.values {
            completion(generation == self.generation ? image : nil)
        }
    }

    private func insert(_ image: CGImage, for key: Key, _ item: LibraryItem) {
        if let old = cache[key] {
            used -= old.cost
        }
        tick += 1
        let cost = image.bytesPerRow * image.height
        cache[key] = Entry(image: image, cost: cost, size: item.size, modified: item.modified, used: tick)
        used += cost
        if used > budget {
            trim(to: budget * 3 / 4)
        }
    }

    /// Drops the least recently used thumbnails, except those on screen, until `bytes` are held.
    func trim(to bytes: Int) {
        guard used > bytes else { return }
        let candidates = cache.filter { !protected.contains($0.key.url) }.sorted { $0.value.used < $1.value.used }
        for (key, entry) in candidates {
            guard used > bytes else { break }
            cache.removeValue(forKey: key)
            used -= entry.cost
        }
    }

    func removeAll() {
        cache = [:]
        used = 0
        generation += 1
    }

    // MARK: - Decoding

    /// The photo's thumbnail at most `edge` pixels on its long edge; with `edit`, the store's render of it,
    /// or nil when it has none. For a photo left in Apple Photos, whether Photos had none without iCloud. It
    /// blocks: only ever off the main thread.
    nonisolated static func load(
        _ item: LibraryItem, edge: Int, store: (StoreThumbnails, ContentKey)?, edit: EditDigest? = nil,
        packs: ThumbnailPacks, decode: @escaping @Sendable (URL, Int) -> CGImage?,
    ) -> (image: CGImage?, inCloud: Bool) {
        if let edit {
            guard let (thumbnails, key) = store else { return (nil, false) }
            let tier = Self.tier(forEdge: edge)
            return (thumbnails.image(
                for: key, tier: tier, edit: edit, size: item.size, modified: item.modified,
                pixelSize: min(edge, tier.pixelSize),
            ), false)
        }
        if let (thumbnails, key) = store {
            let grid = PhotoStore.Tier.grid.pixelSize
            if thumbnails.isInApplePhotos(item.url) {
                return fromPhotos(item, edge: edge, thumbnails: thumbnails, key: key)
            }
            if edge > grid, let preview = preview(item, edge: edge, thumbnails: thumbnails, key: key, decode: decode) {
                return (preview, false)
            }
            return (thumbnails.image(
                for: item.url, key: key, size: item.size, modified: item.modified, pixelSize: min(edge, grid),
            ), false)
        }
        if edge <= edges[0] {
            if let jpeg = packs.jpeg(for: item.url, size: item.size, modified: item.modified),
               let image = StoreThumbnails.decode(jpeg, pixelSize: edge) {
                return (image, false)
            }
            return ThumbnailLoader.load(item, packs: packs, decode: decode)
        }
        return (decode(item.url, edge), false)
    }

    /// A photo left in Apple Photos (LIB-59): the store's grid tier up to its size and its preview tier beyond, made
    /// there from Photos' images first, the grid tier where Photos has no preview without iCloud.
    private nonisolated static func fromPhotos(
        _ item: LibraryItem, edge: Int, thumbnails: StoreThumbnails, key: ContentKey,
    ) -> (image: CGImage?, inCloud: Bool) {
        let grid = PhotoStore.Tier.grid.pixelSize
        if edge > grid, let preview = thumbnails.fromPhotos(
            item.url, key: key, tier: .preview, size: item.size, modified: item.modified, pixelSize: edge,
        ).image {
            return (preview, false)
        }
        return thumbnails.fromPhotos(
            item.url, key: key, tier: .grid, size: item.size, modified: item.modified, pixelSize: min(edge, grid),
        )
    }

    /// From the store's preview tier, made there first when it has none.
    private nonisolated static func preview(
        _ item: LibraryItem, edge: Int, thumbnails: StoreThumbnails, key: ContentKey,
        decode: @escaping @Sendable (URL, Int) -> CGImage?,
    ) -> CGImage? {
        let tier = PhotoStore.Tier.preview
        let stored = { thumbnails.store.data(for: key, tier: tier, size: item.size, modified: item.modified) }
        if let data = stored() {
            return StoreThumbnails.decode(data, pixelSize: edge)
        }
        let maker = StoreThumbnailMaker(store: thumbnails.store, tier: tier, image: StoreThumbnails.source(decode))
        guard maker.make(item.url, key: key, head: Data()), let data = stored() else { return nil }
        return StoreThumbnails.decode(data, pixelSize: edge)
    }

    /// `image` drawn in `space` as Core Animation takes it without converting it: 8-bit BGRA, opaque.
    nonisolated static func drawn(_ image: CGImage, in space: CGColorSpace?) -> CGImage? {
        guard let space, let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
        ) else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}
