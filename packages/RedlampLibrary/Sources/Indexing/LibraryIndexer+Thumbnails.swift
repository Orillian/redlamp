import Foundation
import RedlampDocument
import RedlampEngineAPI
import Synchronization

extension LibraryIndexer {
    /// The thumbnails of the photos written, each volume's in the order they came, made by readers of their own
    /// (LIB-09). A reader asks whether a photo needs one, reads what it's made from through the volume's readers at
    /// `VolumeIO.Priority.background`, below every operation of the indexer's, and makes it on the scheduler's
    /// background lane once its place on the volume is free again, from what the read left in memory. On a disk
    /// with one head the photos the indexing reads go first and thumbnails follow (LIB-53); a volume that serves
    /// many reads at once has twice as many readers as its width, so its thumbnails keep the background lane busy.
    final class ThumbnailQueue: Sendable {
        private struct Volume {
            let io: VolumeIO
            var waiting: [Thumbnail] = []
            var next = 0
            var readers = 0
            /// Readers reading, at most the volume's width, so that on a disk with one head each photo's reads
            /// follow one another; and those waiting to.
            var reading = 0
            var turns: [CheckedContinuation<Void, Never>] = []
        }

        /// Read whole when the file isn't a raw with a preview: what ImageIO decodes a JPEG or a HEIF from. A larger
        /// file is left to the decode to read.
        static let wholeFileLimit = 32 << 20

        let thumbnails: Thumbnails
        private let scheduler: WorkScheduler
        private let volumes = Mutex<[ObjectIdentifier: Volume]>([:])

        init(thumbnails: Thumbnails, scheduler: WorkScheduler) {
            self.thumbnails = thumbnails
            self.scheduler = scheduler
        }

        func add(_ items: [Thumbnail]) {
            guard !items.isEmpty else { return }
            let starting = volumes.withLock { volumes -> [(VolumeIO, Int)] in
                for item in items {
                    volumes[ObjectIdentifier(item.io), default: Volume(io: item.io)].waiting.append(item)
                }
                var starting: [(VolumeIO, Int)] = []
                for (key, volume) in volumes {
                    let more = min(2 * volume.io.width - volume.readers, volume.waiting.count - volume.next)
                    guard more > 0 else { continue }
                    volumes[key]?.readers += more
                    starting.append((volume.io, more))
                }
                return starting
            }
            for (io, readers) in starting {
                for _ in 0 ..< readers {
                    Task { await self.read(on: io) }
                }
            }
        }

        private func read(on io: VolumeIO) async {
            while let thumbnail = take(from: io) {
                try? await make(thumbnail)
            }
        }

        /// The volume's next thumbnail; nil once none waits, the reader asking having stopped.
        private func take(from io: VolumeIO) -> Thumbnail? {
            volumes.withLock { volumes in
                let key = ObjectIdentifier(io)
                guard var volume = volumes[key] else { return nil }
                guard volume.next < volume.waiting.count else {
                    volume.readers -= 1
                    volumes[key] = volume.readers > 0 ? volume : nil
                    return nil
                }
                let thumbnail = volume.waiting[volume.next]
                volume.next += 1
                if volume.next == volume.waiting.count {
                    volume.waiting = []
                    volume.next = 0
                } else if volume.next > 1024, volume.next * 2 > volume.waiting.count {
                    volume.waiting.removeFirst(volume.next)
                    volume.next = 0
                }
                volumes[key] = volume
                return thumbnail
            }
        }

        /// Makes the photo's thumbnail unless it has one; a photo gone, or whose volume went, has none until it's
        /// shown.
        private func make(_ thumbnail: Thumbnail) async throws {
            let thumbnails = thumbnails
            let needed = try await scheduler.run(.background) {
                FileTrace.marking(FileTrace.thumbnail) { thumbnails.isNeeded(thumbnail.url, thumbnail.key) }
            }
            guard needed else { return }
            if thumbnail.file == nil {
                await turn(on: thumbnail.io)
                defer { turnDone(on: thumbnail.io) }
                try await Self.read(thumbnail, edge: thumbnails.edge)
            }
            try await scheduler.run(.background) {
                FileTrace.marking(FileTrace.thumbnail) {
                    thumbnails.make(thumbnail.url, thumbnail.key, thumbnail.file ?? Data())
                }
            }
        }

        /// Waits for a turn to read on the volume.
        private func turn(on io: VolumeIO) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let now = volumes.withLock { volumes -> Bool in
                    let key = ObjectIdentifier(io)
                    guard let volume = volumes[key], volume.reading >= io.width else {
                        volumes[key]?.reading += 1
                        return true
                    }
                    volumes[key]?.turns.append(continuation)
                    return false
                }
                if now {
                    continuation.resume()
                }
            }
        }

        /// Hands the turn to the reader waiting longest for one, if any.
        private func turnDone(on io: VolumeIO) {
            let next = volumes.withLock { volumes -> CheckedContinuation<Void, Never>? in
                let key = ObjectIdentifier(io)
                guard volumes[key]?.turns.isEmpty == false else {
                    volumes[key]?.reading -= 1
                    return nil
                }
                return volumes[key]?.turns.removeFirst()
            }
            next?.resume()
        }

        /// Reads what the photo's thumbnail is made from, through its volume's readers, so that the decode finds it
        /// in memory: its head and the embedded preview that reaches `edge`, as `EmbeddedPreviews` finds it, or the
        /// file whole when there's none. What's read beyond the head is read a part at a time and let go, for the
        /// Mac's cache to keep.
        static func read(_ thumbnail: Thumbnail, edge: Int) async throws {
            let io = thumbnail.io
            let url = thumbnail.url
            let size = thumbnail.size
            let fetch: @Sendable (Range<Int>) async throws -> Data = { range in
                try await io.perform(url, priority: .background, bytes: \.count) { fileSystem in
                    try FileTrace.marking(FileTrace.thumbnail) { try fileSystem.read(url, range: range) }
                }
            }
            let head = try await fetch(0 ..< min(size, PhotoMetadataReader.headLength))
            guard head.count < size else { return }
            var bytes = PreviewBytes(head: head, size: size, fetch: fetch)
            let rest: Range<Int> = if let preview = try await EmbeddedPreviews.best(in: &bytes, reaching: edge) {
                max(preview.offset, head.count) ..< max(preview.range.upperBound, head.count)
            } else {
                head.count ..< (size <= wholeFileLimit ? size : head.count)
            }
            guard !rest.isEmpty else { return }
            _ = try await io.perform(url, priority: .background, bytes: { $0 }) { fileSystem in
                try FileTrace.marking(FileTrace.thumbnail) {
                    var offset = rest.lowerBound
                    while offset < rest.upperBound {
                        let part = try fileSystem.read(
                            url,
                            range: offset ..< min(offset + FileDigest.part, rest.upperBound),
                        )
                        guard !part.isEmpty else { break }
                        offset += part.count
                    }
                    return offset - rest.lowerBound
                }
            }
        }
    }
}
