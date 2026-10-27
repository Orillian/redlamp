import Foundation
import RedlampLibrary

/// Develop's photo while its original downloads from iCloud (LIB-60): a photo kept in Apple Photos, shown from its
/// preview with the download's ring and Cancel, Download Again once cancelled, or what went wrong with Try Again.
public struct OriginalDownload: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// How far it has come; nil before it has started.
        case downloading(ApplePhotosOriginals.Progress?)
        /// Cancel was chosen.
        case cancelled
        case failed(ApplePhotosOriginals.Failure)
    }

    public let url: URL
    public var state: State

    public var isDownloading: Bool {
        if case .downloading = state {
            true
        } else {
            false
        }
    }

    /// From 0 to 1, once Photos says how far it has come.
    public var fraction: Double? {
        guard case let .downloading(progress?) = state, progress.fraction > 0 else { return nil }
        return progress.fraction
    }

    /// What Develop says of it: Downloading from iCloud, 18 of 42 MB.
    public var text: String {
        switch state {
        case let .downloading(progress):
            guard let progress, progress.fraction > 0 else { return "Downloading from iCloud" }
            guard let total = progress.total, let received = progress.received, total > 0 else {
                return "Downloading from iCloud, \(Int((progress.fraction * 100).rounded()))%"
            }
            return "Downloading from iCloud, \(Self.megabytes(received, of: total)) of \(Self.megabytes(total, of: total)) MB"
        case .cancelled:
            return "Not downloaded: this photo's original is only in iCloud"
        case let .failed(failure):
            return failure.description
        }
    }

    /// `bytes` in megabytes, to a tenth below 10 MB of `total`.
    static func megabytes(_ bytes: Int64, of total: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        return total < 10_000_000 ? String(format: "%.1f", megabytes) : String(Int(megabytes.rounded()))
    }
}

extension EditorModel {
    /// The library's cache of originals (LIB-60), its downloads followed for the filmstrip and edit renders from the
    /// first time it's asked for.
    var originals: ApplePhotosOriginals? {
        guard let cache = library.originals else { return nil }
        downloads.follow(cache)
        return cache
    }

    /// The photo after `url` in the grid's order, the filmstrip's, in the direction of travel from `previous`: where →
    /// goes when coming from the left, ← from the right.
    func photoAhead(of url: URL, comingFrom previous: URL?) -> URL? {
        guard let id = library.photoID(of: url) else { return nil }
        let order = gridOrder
        let place = order.place(of: id) ?? .max
        let backward = previous.flatMap(library.photoID(of:)).flatMap(order.place(of:)).map { $0 > place } ?? false
        return order.cell(backward ? -1 : 1, from: id).flatMap(library.url(ofPhoto:))
    }
}
