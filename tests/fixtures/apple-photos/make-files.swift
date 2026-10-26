// Makes the small photos `manifest.json` points at: `swift make-files.swift` in this folder.
// Each is 64 by 48 pixels of its own colour, so no two share a content key, with the EXIF an
// iPhone writes: when it was taken and in which zone, and for some where.
import CoreGraphics
import Foundation
import ImageIO

struct Shot {
    var name: String
    var type: String
    var taken: String
    var offset = "+01:00"
    var colour: (CGFloat, CGFloat, CGFloat)
    var gps: (latitude: Double, longitude: Double)?
}

let shots = [
    Shot(
        name: "IMG_0001.HEIC",
        type: "public.heic",
        taken: "2026:10:05 09:00:00",
        colour: (0.9, 0.2, 0.2),
        gps: (38.7139, -9.1334),
    ),
    Shot(name: "IMG_0002.JPG", type: "public.jpeg", taken: "2026:10:05 10:00:00", colour: (0.2, 0.6, 0.9)),
    Shot(name: "FullSizeRender.jpeg", type: "public.jpeg", taken: "2026:10:05 10:00:00", colour: (0.1, 0.3, 0.5)),
    Shot(name: "IMG_0003.HEIC", type: "public.heic", taken: "2026:10:05 10:30:00", colour: (0.3, 0.8, 0.3)),
    Shot(name: "IMG_0004.JPG", type: "public.jpeg", taken: "2026:10:06 11:00:00", colour: (0.8, 0.8, 0.2)),
    Shot(name: "IMG_0010.JPG", type: "public.jpeg", taken: "2026:10:05 12:00:00", colour: (0.6, 0.2, 0.6)),
    Shot(name: "IMG_0011.JPG", type: "public.jpeg", taken: "2026:10:05 12:00:01", colour: (0.6, 0.3, 0.6)),
    Shot(name: "IMG_0012.JPG", type: "public.jpeg", taken: "2026:10:05 12:00:02", colour: (0.6, 0.4, 0.6)),
    Shot(name: "IMG_0030.JPG", type: "public.jpeg", taken: "2026:10:05 13:00:00", colour: (0.2, 0.2, 0.2)),
    Shot(name: "IMG_0040.JPG", type: "public.jpeg", taken: "2026:10:07 18:00:00", colour: (0.9, 0.6, 0.3)),
]

let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "files")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
for shot in shots {
    let context = CGContext(
        data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 256, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
    )!
    context.setFillColor(CGColor(red: shot.colour.0, green: shot.colour.1, blue: shot.colour.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    let url = folder.appending(path: shot.name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, shot.type as CFString, 1, nil)!
    var properties: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 16 Pro"],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: shot.taken, kCGImagePropertyExifOffsetTimeOriginal: shot.offset,
        ],
        kCGImageDestinationLossyCompressionQuality: 0.8,
    ]
    if let gps = shot.gps {
        properties[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude: abs(gps.latitude),
            kCGImagePropertyGPSLatitudeRef: gps.latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude: abs(gps.longitude),
            kCGImagePropertyGPSLongitudeRef: gps.longitude < 0 ? "W" : "E",
        ]
    }
    CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(shot.name)") }
}
