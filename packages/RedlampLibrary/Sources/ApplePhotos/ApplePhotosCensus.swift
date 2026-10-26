import Foundation

/// What an import from Apple Photos would bring and leave (LIB-54), worked out before anything is copied, as
/// the import window's report and `redlamp library photos --census` show it. It names no album, photo or
/// place, so it can be shared.
public struct ApplePhotosReport: Sendable, Hashable, Codable {
    public var access: ApplePhotosAccess
    /// The collections chosen, folders' albums included, by kind; each becomes a collection.
    public var albums: [String: Int]
    /// Assets in them, each once.
    public var assets: Int
    /// Assets the import takes, each copied once whatever the albums it's in.
    public var photos: Int
    /// Photos the library gets: those taken, and an edit's rendering beside each edited one.
    public var libraryPhotos: Int
    /// Files copied: a pair's two, an edit's rendering.
    public var files: Int
    /// Their size, when Photos says.
    public var bytes: Int64?
    /// RAW+JPEG photos, each copied as a pair with one name.
    public var pairs: Int
    /// Raws alone, a camera's or ProRAW's; and of those, DNGs.
    public var raws: Int
    public var dngs: Int
    /// Edited in Photos: each comes as its original, with Photos' rendering stacked over it.
    public var edited: Int
    /// Edited, but without a rendering Photos gives: only the original comes.
    public var editedWithoutRendering: Int
    /// Live Photos, which come as their stills.
    public var livePhotos: Int
    /// Bursts, each its key photo and the frames picked, stacked; and the frames taken and left.
    public var bursts: Int
    public var burstFrames: Int
    public var burstFramesLeft: Int
    public var videosLeft: Int
    public var hiddenLeft: Int
    public var hiddenIncluded: Int
    /// Assets that aren't a photo or a video, or have no photo Photos gives.
    public var otherLeft: Int
    /// Photos from shared albums: reduced copies, not originals.
    public var sharedCopies: Int
    /// Photos earlier imports brought, which aren't copied again.
    public var alreadyImported: Int
    /// Photos in more than one album chosen, joining each album's collection.
    public var inSeveralAlbums: Int
    public var favorites: Int
    /// From macOS 27.
    public var rated: Int
    public var captioned: Int
    public var withKeywords: Int
    /// Photos Photos places: their files keep their own GPS, and sidecars have no field for a place set
    /// only in Photos.
    public var withLocation: Int
    /// The originals' types, by uniform type identifier; a pair's raws apart.
    public var types: [String: Int]
    public var pairRawTypes: [String: Int]
    /// Each edited original's type with its rendering's: `public.heic → public.heic`.
    public var editTypes: [String: Int]
    /// The kinds of files assets have, over every asset: `photo+alternatePhoto`.
    public var resources: [String: Int]
    /// The fields this Mac's PhotoKit gives, and those macOS 27 would add.
    public var fields: [ApplePhotosField]
    public var fromMacOS27: [ApplePhotosField]
    /// What stays in Photos whatever the import: PhotoKit gives none of it.
    public var leftInPhotos: [String]

    public static let stayingInPhotos = [
        "titles", "people and pets", "memories", "Recently Deleted", "places set only in Photos",
    ]

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The report as `redlamp library photos --census` prints it.
    public func lines() -> [String] {
        func count(_ value: Int, _ noun: String) -> String {
            "\(value) \(noun)\(value == 1 ? "" : "s")"
        }
        let kinds: [(ApplePhotosCollection.Kind, String)] = [
            (.album, "album"), (.smartAlbum, "smart album"), (.sharedAlbum, "shared album"),
        ]
        let chosen = kinds.compactMap { kind, noun in albums[kind.rawValue].map { count($0, noun) } }
        var lines = [
            "From \(chosen.isEmpty ? "no albums" : chosen.joined(separator: ", ")): \(count(assets, "asset"))",
            "  photos to import: \(photos), \(count(libraryPhotos, "photo")) in the library, "
                +
                "\(count(files, "file"))\(bytes.map { ", \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))" } ?? "")",
            "  RAW+JPEG pairs: \(pairs); raws alone: \(raws), of them DNGs: \(dngs)",
            "  edited in Photos: \(edited), each with Photos' rendering stacked over it"
                + (editedWithoutRendering > 0 ? "; \(editedWithoutRendering) without a rendering" : ""),
            "  Live Photos: \(livePhotos), as their stills",
            "  bursts: \(bursts), \(count(burstFrames, "frame")) taken and \(burstFramesLeft) left",
            "  in several albums: \(inSeveralAlbums), copied once",
            "  favourites: \(favorites), as picks",
        ]
        if fields.contains(.rating) {
            lines.append("  rated: \(rated); captioned: \(captioned); with keywords: \(withKeywords)")
        }
        if sharedCopies > 0 {
            lines.append("  from shared albums: \(sharedCopies), reduced copies rather than originals")
        }
        lines.append("Left out: \(videosLeft) videos, \(hiddenLeft) hidden, \(alreadyImported) already imported"
            + (otherLeft > 0 ? ", \(otherLeft) neither photo nor video" : "")
            + (hiddenIncluded > 0 ? "; \(hiddenIncluded) hidden included" : ""))
        lines.append("Fields Photos gives on this Mac: " + fields.map(\.rawValue).joined(separator: ", ")
            + (fromMacOS27.isEmpty ? "" : "; macOS 27 adds " + fromMacOS27.map(\.rawValue).joined(separator: ", ")))
        lines.append("Staying in Photos: " + leftInPhotos.joined(separator: ", ")
            + (withLocation > 0 ? " (\(withLocation) placed in Photos keep the GPS their files hold)" : ""))
        for (title, counts) in [
            ("Originals", types),
            ("Pairs' raws", pairRawTypes),
            ("Edits", editTypes),
            ("Files", resources),
        ] where !counts.isEmpty {
            lines.append("  \(title): " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                .joined(separator: ", "))
        }
        return lines
    }
}

/// The census of the albums chosen for an import from Apple Photos (LIB-54): their assets, read without
/// copying anything, each taken or left and why, and the report.
///
/// A photo is taken once whatever the albums it's in. Videos are left, a Live Photo is its still, a burst its
/// key photo and the frames the photographer picked; hidden photos are left unless they're included, and
/// photos an earlier import brought (by local identifier) are left.
public struct ApplePhotosCensus: Sendable {
    public enum Left: String, Sendable, Hashable, Codable, CaseIterable {
        case video, burstFrame, hidden, imported
        /// Neither a photo nor a video, or no photo Photos gives.
        case other
    }

    public let tree: ApplePhotosTree
    /// The albums, smart and shared albums chosen, folders' albums included.
    public let albums: [ApplePhotosCollection]
    /// The assets taken, oldest first.
    public let taken: [ApplePhotosAsset]
    /// Those left, by local identifier.
    public let left: [String: Left]
    public let report: ApplePhotosReport

    /// The census of the collections `chosen` names (folders' albums included), `tree.standardChoice` when
    /// nil, leaving the assets `imported` names. Throws while Redlamp may not read Photos.
    public static func make(
        _ library: any ApplePhotosLibrary, choosing chosen: [String]? = nil, includesHidden: Bool = false,
        imported: Set<String> = [],
    ) async throws -> ApplePhotosCensus {
        let access = library.access()
        guard access.canRead else { throw ApplePhotosError.noAccess(access) }
        let tree = try await ApplePhotosTree(library.collections())
        let albums = tree.albums(in: chosen ?? tree.standardChoice)
        let assets = albums.isEmpty ? [] : try await library.assets(in: albums.map(\.id))
        return ApplePhotosCensus(
            tree: tree, albums: albums, assets: assets, fields: library.fields, access: access,
            includesHidden: includesHidden, imported: imported,
        )
    }

    init(
        tree: ApplePhotosTree, albums: [ApplePhotosCollection], assets: [ApplePhotosAsset],
        fields: Set<ApplePhotosField>, access: ApplePhotosAccess, includesHidden: Bool, imported: Set<String>,
    ) {
        self.tree = tree
        self.albums = albums
        var taken: [ApplePhotosAsset] = []
        var left: [String: Left] = [:]
        for asset in assets {
            if let reason = Self.reason(asset, includesHidden: includesHidden, imported: imported) {
                left[asset.id] = reason
            } else {
                taken.append(asset)
            }
        }
        taken.sort { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        self.taken = taken
        self.left = left
        report = Self.report(
            albums: albums, assets: assets, taken: taken, left: left, fields: fields, access: access,
        )
    }

    private static func reason(_ asset: ApplePhotosAsset, includesHidden: Bool, imported: Set<String>) -> Left? {
        if asset.mediaType == .video {
            return .video
        }
        if asset.mediaType != .image || asset.resource(.photo) == nil {
            return .other
        }
        if let burst = asset.burst, !burst.isKey, !burst.isUserPick {
            return .burstFrame
        }
        if asset.isHidden, !includesHidden {
            return .hidden
        }
        return imported.contains(asset.id) ? .imported : nil
    }

    private static func report(
        albums: [ApplePhotosCollection], assets: [ApplePhotosAsset], taken: [ApplePhotosAsset],
        left: [String: Left], fields: Set<ApplePhotosField>, access: ApplePhotosAccess,
    ) -> ApplePhotosReport {
        func tally(_ values: some Sequence<String>) -> [String: Int] {
            values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        }
        let files = taken.flatMap { $0.originals + ($0.edit.map { [$0] } ?? []) }
        let sizes = files.map(\.size)
        let raws = taken.filter(\.isRaw)
        let leftCounts = tally(left.values.map(\.rawValue))
        return ApplePhotosReport(
            access: access,
            albums: Dictionary(grouping: albums, by: \.kind.rawValue).mapValues(\.count),
            assets: assets.count,
            photos: taken.count,
            libraryPhotos: taken.count + taken.count { $0.edit != nil },
            files: files.count,
            bytes: sizes.contains(nil) ? nil : sizes.reduce(0) { $0 + ($1 ?? 0) },
            pairs: taken.count(where: \.isPair),
            raws: raws.count,
            dngs: raws.count { $0.resource(.photo)?.type == "com.adobe.raw-image" },
            edited: taken.count { $0.edit != nil },
            editedWithoutRendering: taken.count { $0.hasAdjustments && $0.edit == nil },
            livePhotos: taken.count { $0.subtypes.contains(.live) },
            bursts: Set(taken.compactMap(\.burst?.id)).count,
            burstFrames: taken.count { $0.burst != nil },
            burstFramesLeft: leftCounts[Left.burstFrame.rawValue] ?? 0,
            videosLeft: leftCounts[Left.video.rawValue] ?? 0,
            hiddenLeft: leftCounts[Left.hidden.rawValue] ?? 0,
            hiddenIncluded: taken.count(where: \.isHidden),
            otherLeft: leftCounts[Left.other.rawValue] ?? 0,
            sharedCopies: taken.count { $0.source == .cloudShared },
            alreadyImported: leftCounts[Left.imported.rawValue] ?? 0,
            inSeveralAlbums: taken.count { $0.albums.count > 1 },
            favorites: taken.count(where: \.isFavorite),
            rated: taken.count { ($0.rating ?? 0) > 0 },
            captioned: taken.count { !($0.caption ?? "").isEmpty },
            withKeywords: taken.count { !($0.keywords ?? []).isEmpty },
            withLocation: taken.count { $0.location != nil },
            types: tally(taken.compactMap { $0.resource(.photo)?.type }),
            pairRawTypes: tally(taken.filter(\.isPair).compactMap { $0.resource(.alternatePhoto)?.type }),
            editTypes: tally(taken.compactMap { asset in
                asset.edit.map { "\(asset.resource(.photo)?.type ?? "none") → \($0.type)" }
            }),
            resources: tally(assets.map { asset in
                asset.resources.map(\.kind.rawValue).sorted().joined(separator: "+")
            }),
            fields: ApplePhotosField.allCases.filter(fields.contains),
            fromMacOS27: ApplePhotosField.fromMacOS27.filter { !fields.contains($0) },
            leftInPhotos: ApplePhotosReport.stayingInPhotos,
        )
    }
}
