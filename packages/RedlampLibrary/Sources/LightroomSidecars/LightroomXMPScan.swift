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
        /// Edited in Redlamp, which it keeps (the Lightroom edits design's decision 6).
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

    /// Reads each of `photos`' Lightroom edits on every core, and converts those `edit` says have none in Redlamp
    /// yet, dated `date`. `edit` is asked only of photos with a Lightroom edit, from several threads at once.
    public static func scan(
        _ photos: [URL], date: Date = Date(), edit: @Sendable (URL) -> Edit,
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
                case .none: LightroomPhotoXMP.context(of: photo).map { context in
                        .convert(LightroomPhoto.convert(read.settings, photo: context, source: read.source, date: date))
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
        guard let recipe = sidecar?.recipe else { return .none }
        return recipe.isPristine ? .none : .edited
    }
}
