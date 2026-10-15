import Foundation
import RedlampEngineAPI
import simd
import Testing
@testable import RedlampRecipes

/// A photo's crop and rotation converted, checked against Redlamp's own geometry: for every orientation the
/// camera recorded and every rotation and flip the catalog gives, the developed frame's corners land on the
/// corners Lightroom's crop describes.
struct LightroomPhotoGeometryTests {
    private typealias PhotoNote = LightroomPhoto.Note

    private static let stored = PixelSize(width: 6000, height: 4000)
    private static let orientations = (0 ..< 4).flatMap { turns in
        [false, true].map { ImageOrientation(quarterTurns: turns, mirrored: $0) }
    }

    private static let crop = """
    s = { HasCrop = true, CropLeft = 0.1, CropTop = 0.15, CropRight = 0.85, CropBottom = 0.9, CropAngle = 5,
    	CropConstrainToWarp = 1 }
    """

    private static func convert(_ lua: String, _ photo: LightroomPhotoContext) throws -> LightroomPhotoImport {
        try LightroomPhoto.convert(
            CameraRawSettings(lua: lua), photo: photo, source: .sidecar(URL(filePath: "/Photos/IMG_0001.xmp")),
            date: Date(timeIntervalSince1970: 0),
        )
    }

    /// `vector` turned clockwise on screen (y down) by `degrees`.
    private static func turned(_ vector: SIMD2<Double>, _ degrees: Double) -> SIMD2<Double> {
        let radians = degrees * .pi / 180
        return SIMD2(
            cos(radians) * vector.x - sin(radians) * vector.y,
            sin(radians) * vector.x + cos(radians) * vector.y,
        )
    }

    /// The crop's four corners, 0...1 across the stored pixels, as Lightroom defines them: the upper-left and
    /// lower-right are given, and the crop turns clockwise about its centre.
    private static func lightroomCorners(_ crop: LightroomCrop) -> [SIMD2<Double>] {
        let scale = SIMD2(Double(stored.width), Double(stored.height))
        let upperLeft = SIMD2(crop.left, crop.top) * scale
        let lowerRight = SIMD2(crop.right, crop.bottom) * scale
        let centre = (upperLeft + lowerRight) / 2
        let half = turned(lowerRight - upperLeft, -crop.angle) / 2
        return [SIMD2(-1, -1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1)].map { corner in
            (centre + turned(half * corner, crop.angle)) / scale
        }
    }

    @Test func `a crop's corners land on Lightroom's for every camera and catalog orientation`() throws {
        let crop = LightroomCrop(left: 0.1, top: 0.15, right: 0.85, bottom: 0.9, angle: 5)
        for camera in Self.orientations {
            for edit in Self.orientations {
                let photo = LightroomPhotoContext(size: Self.stored, cameraOrientation: camera, orientation: edit)
                let imported = try Self.convert(Self.crop, photo)
                #expect(imported.recipe.orientation == edit)
                let imageSize = camera.swapsAxes
                    ? PixelSize(width: Self.stored.height, height: Self.stored.width) : Self.stored
                let map = GeometryMap(recipe: imported.recipe, imageSize: imageSize, lens: nil)
                let developed = try [SIMD2(0.0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)].map { corner in
                    try #require(map.imagePoint(corner))
                }
                for point in Self.lightroomCorners(crop) {
                    let oriented = camera.matrix * SIMD3(point.x, point.y, 1)
                    let corner = SIMD2(oriented.x, oriented.y)
                    #expect(
                        developed.contains { simd_distance($0, corner) < 1e-9 },
                        "camera \(camera), edit \(edit): \(corner) isn't a corner of \(developed)",
                    )
                }
            }
        }
    }

    @Test func `the crop maps when the catalog's frame is the file's, turned or not`() throws {
        for catalog in [Self.stored, PixelSize(width: Self.stored.height, height: Self.stored.width), nil] {
            let imported = try Self.convert(Self.crop, LightroomPhotoContext(size: Self.stored, catalogSize: catalog))
            let crop = ["HasCrop", "CropLeft", "CropTop", "CropRight", "CropBottom", "CropAngle"]
            #expect(imported.report.entries.map(\.setting) == [
                "HasCrop",
                "CropTop",
                "CropLeft",
                "CropBottom",
                "CropRight",
                "CropAngle",
            ])
            #expect(crop.allSatisfy { imported.report.outcome($0) == .mapped })
            #expect(abs(imported.recipe[.cropAngle] + 5) < 1e-12)
        }
    }

    @Test func `a crop on a frame other than the file's is approximated, saying how far it can be off`() throws {
        let catalog = PixelSize(width: 6024, height: 4024)
        let imported = try Self.convert(Self.crop, LightroomPhotoContext(size: Self.stored, catalogSize: catalog))
        #expect(imported.report.outcome("CropLeft") == .approximated)
        #expect(imported.report.note("CropLeft") == PhotoNote.frame(catalog, file: Self.stored, offset: 24))
        #expect(!imported.recipe.crop.isFull)
    }

    @Test func `no crop, or corners that don't make one, leave the frame whole`() throws {
        let none = try Self.convert(
            "s = { HasCrop = false, CropLeft = 0, CropRight = 1, CropTop = 0, CropBottom = 1, CropAngle = 0 }",
            LightroomPhotoContext(size: Self.stored),
        )
        #expect(none.recipe.crop.isFull && none.report.conversion == .full)
        let crossed = try Self.convert(
            "s = { HasCrop = true, CropLeft = 0.8, CropRight = 0.1, CropTop = 0.2, CropBottom = 0.9 }",
            LightroomPhotoContext(size: Self.stored),
        )
        #expect(crossed.recipe.crop.isFull)
        #expect(crossed.report.entries(.ignored).map(\.setting) == [
            "HasCrop",
            "CropTop",
            "CropLeft",
            "CropBottom",
            "CropRight",
        ])
        #expect(crossed.report.reasons == [.unreadable])
    }

    @Test func `the catalog's rotation applies once known, and is reported until then`() throws {
        let turned = ImageOrientation(quarterTurns: 1)
        let known = try Self.convert(
            "s = { Exposure2012 = 0.2 }",
            LightroomPhotoContext(size: Self.stored, orientation: turned, orientationCode: "BC"),
        )
        #expect(known.recipe.orientation == turned && known.report.outcome("orientation") == .mapped)
        let unknown = try Self.convert(
            "s = { Exposure2012 = 0.2 }", LightroomPhotoContext(size: Self.stored, orientationCode: "BC"),
        )
        #expect(unknown.recipe.orientation.isIdentity)
        #expect(unknown.report.outcome("orientation") == .ignored)
        #expect(unknown.report.note("orientation") == PhotoNote.rotation("BC"))
        #expect(unknown.report.reasons == [.notYetChecked])
        let upright = try Self.convert(
            "s = { Exposure2012 = 0.2 }",
            LightroomPhotoContext(size: Self.stored, orientation: .identity, orientationCode: "AB"),
        )
        #expect(upright.report.outcome("orientation") == nil && upright.report.conversion == .full)
    }
}
