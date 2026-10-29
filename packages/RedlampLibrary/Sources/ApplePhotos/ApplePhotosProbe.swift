import Foundation

/// Whether Photos has one of an asset's files on this Mac, as reading it without the network tells.
public enum ApplePhotosLocality: Sendable, Hashable {
    case local
    /// Only in iCloud: reading it needs the network.
    case inCloud
    /// Photos couldn't say: why, as the census names an error (`PhotoKitCensus.name(of:)`).
    case unknown(String)
}

/// What the census of a Photos library (LIB-57) asks of Photos beyond what the library reads through
/// `ApplePhotosLibrary` and `ApplePhotosImages`: where Apple's documentation leaves open what Photos keeps on this Mac
/// under Optimize Mac Storage and how its history reads. PhotoKit's is the app's (`PhotoKitProbe`), as its images need
/// AppKit; a simulated library's answers from its manifest.
public protocol ApplePhotosProbe: Sendable {
    /// The collection that holds every photo of the library, Photos' Library smart album; nil where there's none.
    func libraryCollection() async throws -> String?
    /// Whether Photos has `resource` of asset `asset` on this Mac, read without the network and nothing kept.
    func locality(of resource: ApplePhotosResource, of asset: String) async -> ApplePhotosLocality
    /// The long side, in pixels, of the largest image of the picture Photos gives without the network, at the size it
    /// keeps it; nil when it keeps none on this Mac. It blocks: only ever off the main thread.
    func largestImage(of asset: String, version: ApplePhotosImageVersion) -> Int?
    /// The picture's data as Photos gives it without the network (`requestImageDataAndOrientation`), its metadata
    /// with it; nil when it would need iCloud. It blocks: only ever off the main thread.
    func imageData(of asset: String, version: ApplePhotosImageVersion) -> Data?
    /// What changed since `token`, change by change, as Photos' persistent history keeps it, where
    /// `ApplePhotosLibrary.changes(since:)` gives it all at once; throws `ApplePhotosError.expiredToken` once Photos no
    /// longer has the history.
    func changeSets(since token: Data) async throws -> [ApplePhotosChanges]
}
