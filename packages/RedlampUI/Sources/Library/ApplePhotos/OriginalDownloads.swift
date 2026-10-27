import Foundation
import Observation
import RedlampLibrary

/// The downloads of originals of photos kept in Apple Photos (LIB-60) as the app shows them: those queued or under way,
/// for the filmstrip's Downloading 3 originals from iCloud and Cancel All, and each original as it arrives, for what
/// waits for one (edit renders, the loupe at 1:1).
@MainActor
@Observable
public final class OriginalDownloads {
    /// The downloads queued or under way, by photo.
    public private(set) var statuses: [URL: ApplePhotosOriginals.Status] = [:]
    /// Hears each original that arrives.
    @ObservationIgnored var arrived: (URL) -> Void = { _ in }
    @ObservationIgnored private var cache: ApplePhotosOriginals?
    @ObservationIgnored private var listening: Task<Void, Never>?

    init() {}

    isolated deinit {
        listening?.cancel()
    }

    /// Follows `cache`'s downloads from now on: the library's, once it's open.
    func follow(_ cache: ApplePhotosOriginals) {
        guard self.cache !== cache else { return }
        listening?.cancel()
        self.cache = cache
        statuses = cache.downloads
        let events = cache.events()
        listening = Task { [weak self] in
            for await event in events {
                self?.receive(event)
            }
        }
    }

    private func receive(_ event: ApplePhotosOriginals.Event) {
        switch event {
        case let .status(url, status):
            statuses[url] = status
        case let .arrived(url):
            statuses[url] = nil
            arrived(url)
        case let .failed(url, _), let .cancelled(url):
            statuses[url] = nil
        case .evicted:
            break
        }
    }

    /// How far the downloads have come together, from 0 to 1, by the fractions Photos gives.
    public var fraction: Double {
        guard !statuses.isEmpty else { return 0 }
        return statuses.values.reduce(0) { sum, status in
            if case let .downloading(progress) = status {
                return sum + progress.fraction
            }
            return sum
        } / Double(statuses.count)
    }

    /// The filmstrip's Cancel All.
    public func cancelAll() {
        cache?.cancelAll()
    }
}
