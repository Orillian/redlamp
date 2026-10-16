import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes

public extension LightroomReport {
    /// The photos found that Lightroom edited, and what their edits become (EDT-23): how fully each converts,
    /// why settings are left out, by process version, and what stays behind.
    struct Edits: Sendable, Hashable, Codable {
        /// A reason settings are left out of photos' edits, the settings it covers and the photos it touches.
        public struct LeftOut: Sendable, Hashable, Codable {
            public var why: String
            /// The settings, by their Camera Raw names, those on most photos first.
            public var settings: [String]
            public var photos: Int
            /// The first `LightroomReport.listed` of them.
            public var paths: [String] = []
        }

        /// The photos found whose edits come across: Lightroom edited them. Those Redlamp has edited too (`kept`)
        /// get Lightroom's as a version.
        public var photos = 0
        public var full = 0
        public var approximated = 0
        public var leftOut = 0
        public var reasons: [LeftOut] = []
        /// The photos whose edits come across by Lightroom's process (`Process 2012` for 2012 and later).
        public var processes: [String: Int] = [:]
        /// Of them, those turned in Lightroom, whose turn stays behind: their rotation code differs from the one
        /// most of the photos found with the same EXIF orientation have.
        public var turned = 0
        /// Of them, raws rendered in the photographer's own copy of the Adobe profile Lightroom used, and raws
        /// whose Adobe profile isn't on this Mac, by the profile's name, Redlamp's look standing in (EDT-33).
        /// Neither counts a raw whose camera's profiles weren't listed.
        public var ownProfiles = 0
        public var standIns: [String: Int] = [:]
        /// Their snapshots, which come across beside their edits, and the steps of their histories, which don't.
        public var snapshots = 0
        public var historySteps = 0
        /// Of them, photos Redlamp has edited already: they keep their edit, and Lightroom's comes across as a
        /// version named “Lightroom Classic”, which takes the photo's metadata as a new virtual copy does.
        public var kept = 0
        public var keptPaths: [String] = []
        /// JPEGs Lightroom kept with their raws: the edit goes to the raw only.
        public var pairs = 0
        /// Photos and virtual copies found whose settings the catalog doesn't hold, or holds in a form that can't
        /// be read.
        public var unreadable = 0
        /// Virtual copies of the photos found, which come across as versions of their photos (EDT-09), each named
        /// as Lightroom named it, with its own edit, snapshots and fields.
        public var virtualCopies = 0
        /// Of them, those in collections: the versions name their collections, which list them once the library
        /// shows versions as photos (LIB-48).
        public var copiesInCollections = 0
        /// Edits of the photos found and of their virtual copies that came across from this catalog before, as a
        /// photo's edit or a version: they're left as they are.
        public var alreadyThere = 0
        /// Photos whose edits come across with an `.xmp` beside them changed since the catalog was last written:
        /// the catalog's settings win.
        public var newerXMP = 0

        public init() {}
    }
}

/// A photo's edit from the catalog, converted, which the import writes as the photo's Redlamp edit: its
/// snapshots beside it, by name.
struct LightroomEdit: Sendable {
    var photo: LightroomPhotoImport
    var snapshots: [(name: String, edit: LightroomPhotoImport)]

    /// The edit and the snapshots as the sidecar holds them, made now, `date` the snapshots'.
    func made(date: Date = Date()) -> (recipe: EditRecipe, snapshots: [Snapshot]) {
        (photo.recipe, snapshots.map { Snapshot(name: $0.name, created: date, recipe: $0.edit.recipe) })
    }
}

/// A virtual copy of a photo found, which the import writes as a version of the photo (EDT-23): its edit,
/// converted as its photo's is, and, from the plan, its name and its own fields.
struct LightroomCopy: Sendable {
    /// Its image in the catalog.
    var image: Int64
    /// Nil when its settings can't be read: the version is the photo as it was shot, with `provenance`.
    var edit: LightroomEdit?
    var provenance: LightroomProvenance
    /// As Lightroom named it; nil or empty takes the name Create Version would give.
    var name: String?
    var values = LightroomValues()

    /// The version as the sidecar holds it, made now with the ID `id`, `date` its and its snapshots'; named “”
    /// when it has no name, for the batch to name it.
    func version(id: UUID = UUID(), date: Date = Date()) -> PhotoVersion {
        var (recipe, snapshots) = edit?.made(date: date) ?? (EditRecipe(), [])
        if edit == nil {
            recipe.provenance = provenance.recorded
        }
        return PhotoVersion(
            id: id, name: name ?? "", created: date, recipe: recipe, metadata: values.metadata, snapshots: snapshots,
        )
    }
}

/// The catalog's Develop settings read again and converted for the photos the library has (EDT-23): each
/// part on every core while the next is read, only the compact conversions kept.
struct LightroomEditReading: Sendable {
    /// A photo of the catalog found in the index: its row, how many JPEGs Lightroom kept with it, and the images of
    /// the catalog (the photo's own and its virtual copies) whose edits its sidecar holds already.
    struct Target: Sendable {
        let row: PhotoRecord
        let pairs: Int
        var there: Set<Int64> = []
    }

    var edits: [Int64: LightroomEdit] = [:]
    /// The virtual copies of each photo found, by its ID in the index, in the catalog's order.
    var copies: [Int64: [LightroomCopy]] = [:]
    var report = LightroomReport.Edits()
    /// The photos of each reason, by their IDs in the index, in the report's order of the reasons.
    var reasonPhotos: [[Int64]] = []
    var keptPhotos: [Int64] = []

    private struct Part: Sendable {
        var edits: [(Int64, LightroomEdit)] = []
        var copies: [(Int64, LightroomCopy)] = []
        var report = LightroomReport.Edits()
        var reasons: [LightroomImportReport.Reason: (settings: [String: Int], photos: [Int64])] = [:]
        var reasonOrder: [LightroomImportReport.Reason] = []
        var kept: [Int64] = []
    }

    /// The settings of `targets` (by their images' IDs in the catalog) in the catalog at `url`, converted. A raw
    /// whose camera `adobeProfiles` lists, by its ID in the index, names the photographer's Adobe profile where
    /// it's among them (EDT-33).
    static func read(
        _ url: URL, targets: [Int64: Target], slotLooks: [FilmSlot: BaseLookReference],
        adobeProfiles: [Int64: [CameraProfileLook]]? = nil, partSize: Int = LightroomCatalogReader.developPart,
        date: Date = Date(),
    ) throws(LightroomCatalogError) -> LightroomEditReading {
        guard !targets.isEmpty else { return LightroomEditReading() }
        let written = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let parts = try LightroomCatalog.opened(url) { reader in
            let unturned = try unturnedCodes(reader.orientationCodes(), targets: targets)
            var notes: [String] = []
            return try reader.develop(partSize: partSize, notes: &notes) { records in
                convert(
                    records, targets: targets, unturned: unturned, catalog: url, written: written,
                    slotLooks: slotLooks, adobeProfiles: adobeProfiles, date: date,
                )
            }
        }
        var reading = LightroomEditReading()
        var reasons: [LightroomImportReport.Reason: (settings: [String: Int], photos: [Int64])] = [:]
        var order: [LightroomImportReport.Reason] = []
        for part in parts {
            for (id, edit) in part.edits {
                reading.edits[id] = edit
            }
            for (id, copy) in part.copies {
                reading.copies[id, default: []].append(copy)
            }
            reading.report.add(part.report)
            reading.keptPhotos += part.kept
            for reason in part.reasonOrder {
                guard let found = part.reasons[reason] else { continue }
                if reasons[reason] == nil {
                    order.append(reason)
                }
                reasons[reason, default: ([:], [])].settings.merge(found.settings, uniquingKeysWith: +)
                reasons[reason, default: ([:], [])].photos += found.photos
            }
        }
        for reason in order {
            guard let found = reasons[reason] else { continue }
            let settings = found.settings.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            reading.report.reasons.append(LightroomReport.Edits.LeftOut(
                why: LightroomReport.Edits.why(reason), settings: settings.map(\.key), photos: found.photos.count,
            ))
            reading.reasonPhotos.append(found.photos)
        }
        return reading
    }

    /// For each EXIF orientation of the photos found, the rotation code most of them have in the catalog, none
    /// when most have none: the code of a photo Lightroom didn't turn, whichever frame its codes use. A photo with
    /// another code was turned in Lightroom.
    static func unturnedCodes(_ codes: [Int64: String], targets: [Int64: Target]) -> [Int: String] {
        var counts: [Int: [String: Int]] = [:]
        for (image, target) in targets {
            counts[target.row.orientation ?? 1, default: [:]][codes[image] ?? "", default: 0] += 1
        }
        return counts.mapValues { tally in tally.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "" }
    }

    private static func convert(
        _ records: [LightroomCatalog.Develop], targets: [Int64: Target], unturned: [Int: String], catalog: URL,
        written: Date?, slotLooks: [FilmSlot: BaseLookReference], adobeProfiles: [Int64: [CameraProfileLook]]?,
        date: Date,
    ) -> Part {
        var part = Part()
        for develop in records {
            if let master = develop.master {
                guard let target = targets[master] else { continue }
                guard !target.there.contains(develop.image) else {
                    part.report.alreadyThere += 1
                    continue
                }
                let photo = context(
                    target.row, develop, slotLooks: slotLooks, unturned: unturned, adobeProfiles: adobeProfiles,
                )
                let source = LightroomProvenance.Source.catalog(catalog, photo: develop.image, digest: develop.digest)
                var copy = LightroomCopy(
                    image: develop.image, provenance: LightroomProvenance(source: source, date: date),
                )
                if let text = develop.text, let settings = try? CameraRawSettings(lua: text) {
                    copy.edit = converted(settings, develop, photo: photo, source: source, date: date).edit
                } else if develop.adjusted == true {
                    part.report.unreadable += 1
                }
                part.copies.append((target.row.id, copy))
                part.report.virtualCopies += 1
                part.report.snapshots += copy.edit?.snapshots.count ?? 0
                continue
            }
            guard let target = targets[develop.image], develop.adjusted != false else { continue }
            guard let text = develop.text, let settings = try? CameraRawSettings(lua: text) else {
                part.report.unreadable += develop.adjusted == true ? 1 : 0
                continue
            }
            guard LightroomPhoto.holdsEdit(settings) else { continue }
            guard !target.there.contains(develop.image) else {
                part.report.alreadyThere += 1
                continue
            }
            if target.row.edited {
                part.report.kept += 1
                part.kept.append(target.row.id)
            }
            let photo = context(
                target.row, develop, slotLooks: slotLooks, unturned: unturned, adobeProfiles: adobeProfiles,
            )
            let source = LightroomProvenance.Source.catalog(catalog, photo: develop.image, digest: develop.digest)
            let (edit, report) = converted(settings, develop, photo: photo, source: source, date: date)
            switch report.profile {
            case .onThisMac?: part.report.ownProfiles += 1
            case let .standIn(profile, _)?: part.report.standIns[profile, default: 0] += 1
            case nil: break
            }
            part.edits.append((target.row.id, edit))
            part.report.photos += 1
            switch report.conversion {
            case .full: part.report.full += 1
            case .approximated: part.report.approximated += 1
            case .leftOut: part.report.leftOut += 1
            }
            part.report.processes[
                LightroomPhoto.processName(report.processVersion ?? develop.processVersion),
                default: 0,
            ] += 1
            part.report.snapshots += edit.snapshots.count
            part.report.turned += photo.orientationCode == nil ? 0 : 1
            part.report.historySteps += develop.historySteps
            part.report.pairs += target.pairs
            if let xmp = target.row.xmpModified, let written, xmp > written {
                part.report.newerXMP += 1
            }
            for entry in report.entries(.ignored) {
                let reason = entry.reason ?? .unknown
                if part.reasons[reason] == nil {
                    part.reasonOrder.append(reason)
                }
                part.reasons[reason, default: ([:], [])].settings[entry.setting, default: 0] += 1
                if part.reasons[reason]?.photos.last != target.row.id {
                    part.reasons[reason, default: ([:], [])].photos.append(target.row.id)
                }
            }
        }
        return part
    }

    /// A photo's or virtual copy's `settings` and its snapshots in `develop`, converted for `photo`, the edits
    /// keeping only their process versions of their reports; and the edit's whole report.
    private static func converted(
        _ settings: CameraRawSettings, _ develop: LightroomCatalog.Develop, photo: LightroomPhotoContext,
        source: LightroomProvenance.Source, date: Date,
    ) -> (edit: LightroomEdit, report: LightroomImportReport) {
        var converted = LightroomPhoto.convert(settings, photo: photo, source: source, date: date)
        let report = converted.report
        converted.report = LightroomImportReport(processVersion: report.processVersion)
        var snapshots: [(name: String, edit: LightroomPhotoImport)] = []
        for snapshot in develop.snapshots {
            guard let text = snapshot.text, let settings = try? CameraRawSettings(lua: text) else { continue }
            var edit = LightroomPhoto.convert(settings, photo: photo, source: source, date: date)
            edit.report = LightroomImportReport(processVersion: edit.report.processVersion)
            snapshots.append((snapshot.name ?? "Snapshot", edit))
        }
        return (LightroomEdit(photo: converted, snapshots: snapshots), report)
    }

    /// What converting a photo's settings needs of it, from its row in the index and the catalog's record. Its
    /// rotation code is given only when it differs from `unturned`'s for its EXIF orientation, Lightroom having
    /// turned it; a raw's Adobe profiles are its camera's in `adobeProfiles`.
    static func context(
        _ row: PhotoRecord, _ develop: LightroomCatalog.Develop, slotLooks: [FilmSlot: BaseLookReference],
        unturned: [Int: String] = [:], adobeProfiles: [Int64: [CameraProfileLook]]? = nil,
    ) -> LightroomPhotoContext {
        let exif = row.orientation ?? 1
        let code = develop.orientation.flatMap { $0.isEmpty || $0 == unturned[exif] ? nil : $0 }
        let catalogSize = develop.fileWidth.flatMap { width in
            develop.fileHeight.map { PixelSize(width: width, height: $0) }
        }
        var size = catalogSize ?? PixelSize(width: 1, height: 1)
        if let width = row.width, let height = row.height, width > 0, height > 0 {
            size = (5 ... 8).contains(exif) ? PixelSize(width: height, height: width)
                : PixelSize(width: width, height: height)
        }
        return LightroomPhotoContext(
            size: size, cameraOrientation: orientation(exif: exif), isRaw: row.kind == .raw,
            orientationCode: code, catalogSize: catalogSize, slotLooks: slotLooks,
            adobeProfiles: row.kind == .raw ? row.camera.flatMap { adobeProfiles?[$0] } : nil,
        )
    }

    /// EXIF's orientation, 1 to 8, as a mirror then clockwise quarter turns.
    static func orientation(exif: Int) -> ImageOrientation {
        switch exif {
        case 2: ImageOrientation(quarterTurns: 0, mirrored: true)
        case 3: ImageOrientation(quarterTurns: 2)
        case 4: ImageOrientation(quarterTurns: 2, mirrored: true)
        case 5: ImageOrientation(quarterTurns: 3, mirrored: true)
        case 6: ImageOrientation(quarterTurns: 1)
        case 7: ImageOrientation(quarterTurns: 1, mirrored: true)
        case 8: ImageOrientation(quarterTurns: 3)
        default: .identity
        }
    }
}

extension LightroomReport.Edits {
    mutating func add(_ other: LightroomReport.Edits) {
        photos += other.photos
        full += other.full
        approximated += other.approximated
        leftOut += other.leftOut
        processes.merge(other.processes, uniquingKeysWith: +)
        turned += other.turned
        ownProfiles += other.ownProfiles
        standIns.merge(other.standIns, uniquingKeysWith: +)
        snapshots += other.snapshots
        historySteps += other.historySteps
        kept += other.kept
        pairs += other.pairs
        unreadable += other.unreadable
        virtualCopies += other.virtualCopies
        copiesInCollections += other.copiesInCollections
        alreadyThere += other.alreadyThere
        newerXMP += other.newerXMP
    }

    /// Why a reason's settings are left out, in words.
    static func why(_ reason: LightroomImportReport.Reason) -> String {
        switch reason {
        case .notYetChecked:
            "not yet checked against Lightroom: where masks and spots sit, Upright, panel switches, turns made in "
                + "Lightroom and Point Color wait on files Lightroom made"
        case .earlierProcess:
            "Process 2003's and 2010's tone, which EDT-31 is to convert as Lightroom's Update to Current Process "
                + "does: until then these photos keep Redlamp's default tone"
        case let .notInRedlamp(row):
            "Lightroom features Redlamp doesn't have" + (row.map { " yet (\($0))" } ?? "")
        case .unreadable: "values that can't be read"
        case .unknown: "settings Redlamp doesn't know"
        }
    }

    /// The section's lines, as `LightroomReport.lines` prints them.
    var lines: [String] {
        guard photos > 0 || virtualCopies > 0 || unreadable > 0 || alreadyThere > 0 else { return [] }
        let count = LightroomReport.count
        var lines = ["  edits, for the photos found:"]
        if photos > 0 {
            lines.append("    photos whose Lightroom edits come across: \(count(photos)) (\(count(full)) in full, "
                + "\(count(approximated)) with settings approximated, \(count(leftOut)) with settings left out)")
            let order = ["Process 2012", "Process 2010", "Process 2003"]
            let byProcess = processes.sorted { (order.firstIndex(of: $0.key) ?? 3, $0.key) < (
                order.firstIndex(of: $1.key) ?? 3,
                $1.key,
            ) }
            lines
                .append("      by process: " + byProcess.map { "\($0.key) \(count($0.value))" }.joined(separator: ", "))
            if turned > 0 {
                lines.append(
                    "      photos turned in Lightroom: \(count(turned)), which come across as the camera held them: a "
                        + "photo counts as turned when its rotation in the catalog isn't the one most of the photos the "
                        + "camera held the same way have",
                )
            }
            if ownProfiles > 0 {
                lines.append("      raws in the Adobe profile Lightroom used, the photographer's own copy on this Mac: "
                    + count(ownProfiles))
            }
            if !standIns.isEmpty {
                let byProfile = standIns.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                lines.append("      raws whose Adobe profile isn't on this Mac, Redlamp's look standing in: "
                    + "\(count(standIns.values.reduce(0, +))) ("
                    + byProfile.map { "\($0.key) \(count($0.value))" }.joined(separator: ", ") + ")")
            }
        }
        for reason in reasons {
            let shown = reason.settings.prefix(6).joined(separator: ", ")
                + (reason.settings.count > 6 ? " and \(count(reason.settings.count - 6)) more" : "")
            lines.append("      left out of \(count(reason.photos)) photos, \(reason.why): \(shown)")
        }
        if kept > 0 {
            lines.append("      photos Redlamp has edited already: \(count(kept)), which keep their edit; Lightroom's "
                + "comes across as a version named “Lightroom Classic”")
        }
        if virtualCopies > 0 {
            lines.append("    virtual copies: \(count(virtualCopies)), which come across as versions of their photos, "
                + "named as Lightroom named them, with their own edits, snapshots and fields")
        }
        if copiesInCollections > 0 {
            lines.append("      in collections: \(count(copiesInCollections)), which their versions name; the "
                + "collections list them once the library shows versions as photos (LIB-48)")
        }
        if snapshots > 0 {
            lines.append("    snapshots: \(count(snapshots)), converted as the edits are")
        }
        if pairs > 0 {
            lines.append("    JPEGs Lightroom kept with their raws: \(count(pairs)), the edit going to the raw only")
        }
        if newerXMP > 0 {
            lines.append(
                "    photos with an .xmp beside them changed since the catalog was written: \(count(newerXMP)), "
                    + "which take the catalog's settings",
            )
        }
        if alreadyThere > 0 {
            lines.append("    edits brought from this catalog before: \(count(alreadyThere)), as photos' edits or "
                + "versions, which are left as they are")
        }
        return lines
    }

    /// What stays behind, for the report's list of it.
    var left: [LightroomReport.Left] {
        var left: [LightroomReport.Left] = []
        if historySteps > 0 {
            left.append(LightroomReport.Left(
                what: "steps of the edited photos' histories", count: historySteps,
                why: "an edit comes across as it is now, without the steps that made it",
            ))
        }
        if unreadable > 0 {
            left.append(LightroomReport.Left(
                what: "photos and virtual copies edited in Lightroom whose settings can't be read", count: unreadable,
                why: "the catalog doesn't hold them in a form Redlamp reads; they show as they were shot",
            ))
        }
        return left
    }
}
