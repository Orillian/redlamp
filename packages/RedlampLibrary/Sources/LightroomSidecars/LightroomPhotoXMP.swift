import Foundation
import ImageIO
import RedlampEngineAPI
import RedlampRecipes

/// A photo's develop settings from Lightroom Classic, Camera Raw or Bridge, and where they were read.
public struct LightroomXMPEdit: Sendable {
    public var settings: CameraRawSettings
    public var source: LightroomProvenance.Source

    public init(settings: CameraRawSettings, source: LightroomProvenance.Source) {
        self.settings = settings
        self.source = source
    }
}

/// Lightroom's edits in XMP (EDT-12), read as metadata, never by decoding the photo: a raw's from the `.xmp`
/// beside it, where the library's XMP sync looks (`XMPMetadata.sidecarURLs`), and any other photo's (a DNG,
/// JPEG, TIFF, HEIC or PNG) from the XMP its own file holds, where Lightroom saves it, else from an `.xmp`
/// beside it. An `.xmp` named after a raw and the JPEG beside it is the raw's, as Lightroom reads it.
public enum LightroomPhotoXMP {
    /// `photo`'s settings, if they hold an edit (`LightroomPhoto.holdsEdit`). `rawBeside` says whether a raw
    /// shares the photo's name in its folder; it's asked only of a photo that isn't a raw, and only when the
    /// `.xmp` of that name holds an edit and doesn't say which file it was written for.
    public static func edit(for photo: URL, rawBeside: () -> Bool = { false }) -> LightroomXMPEdit? {
        let isCameraRaw = Self.isCameraRaw(photo)
        if !isCameraRaw, let settings = embeddedSettings(in: photo), LightroomPhoto.holdsEdit(settings) {
            return LightroomXMPEdit(settings: settings, source: .embedded(photo))
        }
        for (index, url) in XMPMetadata.sidecarURLs(for: photo).enumerated() {
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let settings = CameraRawSettings(xmp: data), LightroomPhoto.holdsEdit(settings)
            else { continue }
            switch writtenFor(settings, photo: photo) {
            case false?: continue
            case nil where index == 0 && !isCameraRaw && rawBeside(): continue
            default: return LightroomXMPEdit(settings: settings, source: .sidecar(url))
            }
        }
        return nil
    }

    /// A raw whose edits Lightroom keeps in an `.xmp` beside it, as it does for every raw but a DNG.
    public static func isCameraRaw(_ photo: URL) -> Bool {
        let ext = photo.pathExtension.lowercased()
        return ext != "dng" && PhotoRecord.Kind(pathExtension: ext) == .raw
    }

    /// Whether a raw shares `photo`'s name, whatever its case, in its folder.
    public static func rawBeside(_ photo: URL) -> Bool {
        let stem = photo.deletingPathExtension().lastPathComponent.lowercased()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: photo.deletingLastPathComponent().path)) ?? []
        return names.contains { name in
            (name as NSString).deletingPathExtension.lowercased() == stem && isCameraRaw(URL(fileURLWithPath: name))
        }
    }

    /// Whether settings read from the `.xmp` named after `photo` were written for it, by the file Camera Raw
    /// records them for (`crs:RawFileName`): nil when that names no file of the photo's name, as after the
    /// photo and its `.xmp` were renamed together.
    static func writtenFor(_ settings: CameraRawSettings, photo: URL) -> Bool? {
        guard let name = settings.text("RawFileName"), !settings.isBlank("RawFileName") else { return nil }
        if name.caseInsensitiveCompare(photo.lastPathComponent) == .orderedSame {
            return true
        }
        let stem = photo.deletingPathExtension().lastPathComponent
        return (name as NSString).deletingPathExtension.caseInsensitiveCompare(stem) == .orderedSame ? false : nil
    }

    /// The Camera Raw settings in `photo`'s own XMP, from ImageIO's metadata, which reads no pixels.
    static func embeddedSettings(in photo: URL) -> CameraRawSettings? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(photo as CFURL, options),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag],
              tags.contains(where: { CGImageMetadataTagCopyNamespace($0) as String? == CameraRawSettings.namespace }),
              let xmp = CGImageMetadataCreateXMPData(metadata, nil) as Data?
        else { return nil }
        return CameraRawSettings(xmp: xmp)
    }

    /// What converting a photo's settings needs to know of it, from what the library indexes: its size after
    /// the camera's orientation (`PhotoRecord.width`, `height`) and that orientation, as EXIF numbers it.
    public static func context(size: PixelSize, exifOrientation: Int?, isRaw: Bool) -> LightroomPhotoContext {
        let camera = ImageOrientation(exif: exifOrientation ?? 1)
        let stored = camera.swapsAxes ? PixelSize(width: size.height, height: size.width) : size
        return LightroomPhotoContext(size: stored, cameraOrientation: camera, isRaw: isRaw)
    }
}

extension ImageOrientation {
    /// EXIF's orientation, 1 to 8, as a mirror and then clockwise quarter turns; 1 for any other number.
    init(exif: Int) {
        switch exif {
        case 2: self.init(quarterTurns: 0, mirrored: true)
        case 3: self.init(quarterTurns: 2)
        case 4: self.init(quarterTurns: 2, mirrored: true)
        case 5: self.init(quarterTurns: 3, mirrored: true)
        case 6: self.init(quarterTurns: 1)
        case 7: self.init(quarterTurns: 1, mirrored: true)
        case 8: self.init(quarterTurns: 3)
        default: self.init()
        }
    }
}
