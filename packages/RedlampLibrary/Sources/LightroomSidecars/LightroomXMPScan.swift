import Foundation
import ImageIO
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes

/// What Convert Lightroom Edits… finds in a set of photos before anything is written (EDT-12): the photos whose
/// Lightroom edits convert, each with its conversion, and those with a Lightroom edit that keep the edit they
/// have.
public struct LightroomXMPScan: Sendable {
    public struct Conversion: Sendable {
        public var photo: URL
        public var imported: LightroomPhotoImport

        public init(photo: URL, imported: LightroomPhotoImport) {
            self.photo = photo
            self.imported = imported
        }
    }

    /// A photo's edit in Redlamp, which decides whether its Lightroom edit is converted.
    public enum Edit: Sendable, Equatable {
        /// None yet: its Lightroom edit is converted.
        case none
        /// Edited in Redlamp, which it keeps (the Lightroom edits design's decision 6), though it may be back at
        /// the defaults since.
        case edited
        /// Converted from Lightroom before, as its provenance says, and not converted again however its XMP
        /// changed since.
        case converted
        /// Its sidecar can't be read now, or a newer Redlamp wrote it.
        case unreadable
    }

    /// The photos to convert, in the order they were given.
    public var conversions: [Conversion] = []
    /// Photos with a Lightroom edit that keep their Redlamp edit.
    public var edited: [URL] = []
    public var converted: [URL] = []
    public var unreadable: [URL] = []
    /// Photos with a Lightroom edit whose size can't be read without decoding them; opening one converts it.
    public var unsized: [URL] = []

    public init() {}

    /// The photos with a Lightroom edit, of every kind.
    public var found: Int {
        conversions.count + edited.count + converted.count + unreadable.count + unsized.count
    }

    /// The photos converting fully, with approximations, or with settings left out.
    public func photos(_ conversion: LightroomImportReport.Conversion) -> [URL] {
        conversions.filter { $0.imported.report.conversion == conversion }.map(\.photo)
    }

    /// Each reason settings were left out, with the photos it applies to, in the order first met.
    public var reasons: [(reason: LightroomImportReport.Reason, photos: [URL])] {
        var order: [LightroomImportReport.Reason] = []
        var photos: [LightroomImportReport.Reason: [URL]] = [:]
        for conversion in conversions {
            for reason in conversion.imported.report.reasons {
                if photos[reason] == nil {
                    order.append(reason)
                }
                photos[reason, default: []].append(conversion.photo)
            }
        }
        return order.map { ($0, photos[$0] ?? []) }
    }

    /// A camera, by the make and model the library's index has for its photos (`Canon`, `Canon EOS R5`).
    public struct Camera: Sendable, Hashable {
        public var make: String
        public var model: String

        public init(make: String, model: String) {
            self.make = make
            self.model = model
        }
    }

    /// What the library's index holds of a photo that converting its Lightroom edit needs, so its file isn't read
    /// for it: its size as stored and the camera's orientation, whether it's a raw, and its camera.
    public struct Indexed: Sendable, Hashable {
        public var context: LightroomPhotoContext
        public var camera: Camera?

        public init(context: LightroomPhotoContext, camera: Camera? = nil) {
            self.context = context
            self.camera = camera
        }
    }

    /// Reads each of `photos`' Lightroom edits on every core, and converts those `edit` says have none in Redlamp
    /// yet, dated `date`. `edit` is asked only of photos with a Lightroom edit, from several threads at once. A photo
    /// in `indexed` is converted for what the index holds of it, any other for what ImageIO reads. `slotLooks` are
    /// the looks that fill film slots on this Mac (`RecipeLibrary.filledSlots`), which Fujifilm's simulations take
    /// first; a raw whose camera `adobeProfiles` lists names the photographer's Adobe profile where it's among them
    /// (EDT-33).
    public static func scan(
        _ photos: [URL], date: Date = Date(), indexed: [URL: Indexed] = [:],
        slotLooks: [FilmSlot: BaseLookReference] = [:], adobeProfiles: [Camera: [CameraProfileLook]]? = nil,
        edit: @Sendable (URL) -> Edit,
    ) -> LightroomXMPScan {
        let rawsBeside = rawStems(beside: photos.filter { !LightroomPhotoXMP.isCameraRaw($0) })
        var found = [Found?](repeating: nil, count: photos.count)
        found.withUnsafeMutableBufferPointer { found in
            let slots = UncheckedSlots(base: found.baseAddress)
            DispatchQueue.concurrentPerform(iterations: photos.count) { index in
                let photo = photos[index]
                let stem = photo.deletingPathExtension().lastPathComponent.lowercased()
                guard let read = LightroomPhotoXMP.edit(for: photo, rawBeside: {
                    rawsBeside[photo.deletingLastPathComponent().path]?.contains(stem) == true
                }) else { return }
                slots.base?[index] = switch edit(photo) {
                case .none:
                    context(of: photo, indexed[photo], slotLooks: slotLooks, adobeProfiles: adobeProfiles).map {
                        .convert(LightroomPhoto.convert(read.settings, photo: $0, source: read.source, date: date))
                    } ?? .unsized
                case .edited: .edited
                case .converted: .converted
                case .unreadable: .unreadable
                }
            }
        }
        var scan = LightroomXMPScan()
        for (photo, found) in zip(photos, found) {
            switch found {
            case let .convert(imported)?: scan.conversions.append(Conversion(photo: photo, imported: imported))
            case .edited?: scan.edited.append(photo)
            case .converted?: scan.converted.append(photo)
            case .unreadable?: scan.unreadable.append(photo)
            case .unsized?: scan.unsized.append(photo)
            case nil: break
            }
        }
        return scan
    }

    /// What converting `photo`'s settings needs of it: what the index holds of it (`indexed`), else what ImageIO
    /// reads, with the looks filling film slots and the Adobe profiles for a raw's camera where `adobeProfiles` lists
    /// them.
    static func context(
        of photo: URL, _ indexed: Indexed?, slotLooks: [FilmSlot: BaseLookReference],
        adobeProfiles: [Camera: [CameraProfileLook]]?,
    ) -> LightroomPhotoContext? {
        guard var context = indexed?.context ?? LightroomPhotoXMP.context(of: photo) else { return nil }
        context.slotLooks = slotLooks
        if context.isRaw, let camera = indexed?.camera, let profiles = adobeProfiles?[camera] {
            context.adobeProfiles = profiles
        }
        return context
    }

    /// What `index` holds of each of `photos` its indexing has read, by photo. The index keeps a photo's size once
    /// the camera's orientation is applied (`PhotoMetadataReader`), which an orientation of 5 to 8 turns back.
    public static func indexed(_ photos: [URL], in index: LibraryIndex) async throws -> [URL: Indexed] {
        let folders = Dictionary(grouping: photos) { LibraryIndexer.path($0.deletingLastPathComponent()) }
        return try await index.read { reader in
            var cameras: [Int64: Camera] = [:]
            try reader.database.cached("SELECT id, make, model FROM cameras").forEachRow { row in
                if let make = row.string(at: 1), let model = row.string(at: 2) {
                    cameras[row.int64(at: 0)] = Camera(make: make, model: model)
                }
            }
            var indexed: [URL: Indexed] = [:]
            for (path, urls) in folders {
                guard let folder = try reader.folder(path: path) else { continue }
                let records = try Dictionary(reader.photos(inFolder: folder.id).map { ($0.name, $0) }) { first, _ in
                    first
                }
                for url in urls {
                    guard let record = records[url.lastPathComponent], let width = record.width,
                          let height = record.height, width > 0, height > 0 else { continue }
                    let exif = record.orientation ?? 1
                    let size = (5 ... 8).contains(exif)
                        ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
                    indexed[url] = Indexed(
                        context: LightroomPhotoContext(
                            size: size, cameraOrientation: ImageOrientation(exif: exif), isRaw: record.kind == .raw,
                        ),
                        camera: record.camera.flatMap { cameras[$0] },
                    )
                }
            }
            return indexed
        }
    }

    private enum Found {
        case convert(LightroomPhotoImport)
        case edited, converted, unreadable, unsized
    }

    /// Each slot is written by one iteration only.
    private struct UncheckedSlots: @unchecked Sendable {
        let base: UnsafeMutablePointer<Found?>?
    }

    /// The names of the raws in the folders of `photos`, lowercased and without their extensions, by folder.
    private static func rawStems(beside photos: [URL]) -> [String: Set<String>] {
        var stems: [String: Set<String>] = [:]
        for folder in Set(photos.map { $0.deletingLastPathComponent().path }) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            stems[folder] = Set(names.filter { LightroomPhotoXMP.isCameraRaw(URL(fileURLWithPath: $0)) }.map {
                ($0 as NSString).deletingPathExtension.lowercased()
            })
        }
        return stems
    }
}

public extension LightroomPhotoXMP {
    /// What converting `photo`'s settings needs to know of it, from ImageIO's properties, which read no pixels:
    /// its size as stored and the camera's orientation. Nil when ImageIO can't read them.
    static func context(of photo: URL) -> LightroomPhotoContext? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(photo as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source, CGImageSourceGetPrimaryImageIndex(source), options,
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        return LightroomPhotoContext(
            size: PixelSize(width: width, height: height),
            cameraOrientation: ImageOrientation(exif: properties[kCGImagePropertyOrientation] as? Int ?? 1),
            isRaw: PhotoRecord.Kind(pathExtension: photo.pathExtension) == .raw,
        )
    }

    /// `photo`'s edit in Redlamp as `store` reads it, to Convert Lightroom Edits….
    static func redlampEdit(of photo: URL, in store: SidecarStore) -> LightroomXMPScan.Edit {
        guard store.protection(for: photo) == nil,
              case let .success(sidecar) = Result(catching: { try store.loadThrowing(for: photo) })
        else { return .unreadable }
        if sidecar?.recipe.provenance != nil {
            return .converted
        }
        return hasRedlampEdit(sidecar, of: photo, in: store) ? .edited : .none
    }

    /// Whether `photo` has had an edit in Redlamp, as its sidecar, `sidecar` as read through `store`, records it:
    /// one converted from Lightroom, one that isn't the defaults, snapshots, or the history a photo reset to the
    /// defaults keeps. Only a photo that has had none converts its Lightroom edit (EDT-12).
    static func hasRedlampEdit(_ sidecar: Sidecar?, of photo: URL, in store: SidecarStore) -> Bool {
        guard let sidecar else { return false }
        return sidecar.recipe.provenance != nil || !sidecar.recipe.isPristine || !sidecar.snapshots.isEmpty
            || store.hasHistory(for: photo)
    }
}
