import Foundation
import Metal
import RedlampColor
import RedlampEngineAPI
import RedlampServices
import simd
import Testing
@testable import RedlampEngine

/// The Fujifilm X-E5, which LibRaw had no colour matrix for until Redlamp's fork gave it the X-T5's
/// (CAM-21). Its raws opened without one: LibRaw left `rgb_cam` the identity and `cam_xyz` empty, so
/// its camera RGB was taken for linear sRGB and white balance had no colour model. From process 19
/// (raw revision 5) they develop with the matrix, and edits made before render as they did.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct LaterColorMatrixTests {
    /// LibRaw's matrices for the X-T5, which the fork gives the X-E5: camera RGB to linear sRGB
    /// (`rgb_cam`) and XYZ to camera RGB (`cam_xyz`), row-major.
    static let cameraToSRGB = [
        1.25605, -0.042125, -0.213923, -0.149639, 1.54978, -0.400142, 0.00458682, -0.361771, 1.35718,
    ]
    static let xyzToCamera = [1.1809, -0.5358, -0.1141, -0.4248, 1.2164, 0.2343, -0.0514, 0.1097, 0.5848]
    static let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    /// The CC0 X-E5 sample's as-shot multipliers.
    static let asShot = SIMD3<Double>(1.9636, 1, 1.8179)
    static let size = 96
    /// The camera coverage set's X-E5 and X-T5 samples, both 40 MP X-Trans 5 HR.
    static let samples = ["Fujifilm_X-E5.RAF", "Fujifilm_X-T5.RAF"].map {
        CameraGoldenTests.root.appending(path: "tests/fixtures/cameras/\($0)")
    }

    let detail: DetailStageTests

    init() throws {
        detail = try DetailStageTests()
    }

    @Test func `an X-E5 edit before process 19 renders as the photo did without a colour matrix`() throws {
        let engine = try RedlampEngine()
        let photo = try session(Self.xE5())
        let then = try session(Self.xE5(matrix: false), revision: .fourth)
        #expect(photo.rawChanges == [.fifth] && photo.rawSource != nil)
        let recipe = Self.warmer(process: 18)
        let variant = try engine.revisions.session(for: recipe, base: photo)
        #expect(variant !== photo && variant.rawRevision == .fourth)
        #expect(variant.cameraToWorking == then.cameraToWorking)
        #expect(variant.whiteBalanceRatio(for: recipe) == SIMD3(1, 1, 1), "no colour model, as then")
        let level = try detail.readLevel(variant, level: 0)
        #expect(try level == detail.readLevel(then, level: 0), "demosaiced as without a matrix")
        #expect(try detail.readLevel(photo, level: 0) != level, "the matrix guides the demosaic")
        let request = RenderRequest(recipe: recipe, targetSize: photo.orientedSize, generation: 0)
        #expect(try render(request, engine, photo) == render(request, engine, then))
        #expect(engine.revisions.variantsBuilt == 1)
    }

    @Test func `from process 19 an X-E5 develops with its colour matrix`() throws {
        let engine = try RedlampEngine()
        let photo = try session(Self.xE5())
        let then = try session(Self.xE5(matrix: false), revision: .fourth)
        let recipe = Self.warmer(process: 19)
        #expect(try engine.revisions.session(for: recipe, base: photo) === photo)
        let matrix = (ColorMatrices.sRGBToRec2020 * simd_double3x3(rowMajor: Self.cameraToSRGB)).floatMatrix
        #expect(photo.cameraToWorking == matrix)
        #expect(photo.whiteBalanceRatio(for: recipe) != SIMD3(1, 1, 1))
        #expect(photo.info.asShotWhiteBalance != nil && then.info.asShotWhiteBalance == nil)
        let request = RenderRequest(recipe: recipe, targetSize: photo.orientedSize, generation: 0)
        #expect(try render(request, engine, photo) != render(request, engine, then))
        #expect(engine.revisions.variantsBuilt == 0)
    }

    /// A photo opened for an edit made before process 19 is built as Redlamp built it then. Moved to
    /// 19, the edit renders from a variant with the matrix, as the photo opened at 19 renders it.
    @Test func `an X-E5 edit moved to process 19 renders with its matrix from a photo opened for 18`() throws {
        let engine = try RedlampEngine()
        let photo = try session(Self.xE5(), revision: .fourth)
        let then = try session(Self.xE5(matrix: false), revision: .fourth)
        let current = try session(Self.xE5())
        #expect(photo.cameraToWorking == then.cameraToWorking)
        var recipe = Self.warmer(process: 18)
        #expect(try engine.revisions.session(for: recipe, base: photo) === photo)
        recipe.processVersion = 19
        let variant = try engine.revisions.session(for: recipe, base: photo)
        #expect(variant !== photo && variant.cameraToWorking == current.cameraToWorking)
        let request = RenderRequest(recipe: recipe, targetSize: current.orientedSize, generation: 0)
        #expect(try render(request, engine, photo) == render(request, engine, current))
        #expect(engine.revisions.variantsBuilt == 1)
    }

    @Test func `a camera LibRaw always had a matrix for renders from one photo at every process`() throws {
        let engine = try RedlampEngine()
        let photo = try session(Self.xE5(revision: .first))
        #expect(photo.rawChanges.isEmpty && photo.rawSource == nil)
        for process in [14, 18, 19] {
            #expect(try engine.revisions.session(for: Self.warmer(process: process), base: photo) === photo)
        }
        #expect(photo.whiteBalanceRatio(for: Self.warmer(process: 18)) != SIMD3(1, 1, 1))
        let size = photo.orientedSize
        let at18 = try render(
            RenderRequest(recipe: Self.warmer(process: 18), targetSize: size, generation: 0),
            engine,
            photo,
        )
        let at19 = try render(
            RenderRequest(recipe: Self.warmer(process: 19), targetSize: size, generation: 0),
            engine,
            photo,
        )
        #expect(at18 == at19)
        #expect(engine.revisions.variantsBuilt == 0)
    }

    @Test func `the decode service hands the app the revision that brings the matrix`() throws {
        #expect(try DecodedImage(archive: Self.xE5().archived()).colorMatrixRevision == .fifth)
    }

    /// The real files, as the decoder gives them; neither is among the process-stability fixtures.
    @Test(.enabled(if: samples.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }))
    func `the X-E5's sample takes the X-T5's matrix from process 19, and the X-T5's at every process`() throws {
        let xE5 = try ImageDecoder.decode(Self.samples[0])
        let xT5 = try ImageDecoder.decode(Self.samples[1])
        #expect(xE5.colorMatrixRevision == .fifth && xT5.colorMatrixRevision == .first)
        #expect(xE5.cameraToSRGB == xT5.cameraToSRGB && xE5.xyzToCamera == xT5.xyzToCamera)
        let before = SessionBuilder.taken(xE5, at: RawRevision(processVersion: 18))
        #expect(before.cameraToSRGB == Self.identity && before.xyzToCamera == nil, "as LibRaw opened it before")
        let from = SessionBuilder.taken(xE5, at: RawRevision(processVersion: 19))
        #expect(from.cameraToSRGB == xE5.cameraToSRGB && from.xyzToCamera == xE5.xyzToCamera)
        let other = SessionBuilder.taken(xT5, at: RawRevision(processVersion: 18))
        #expect(other.cameraToSRGB == xT5.cameraToSRGB && other.xyzToCamera == xT5.xyzToCamera)
    }

    // MARK: - Helpers

    /// An edit with its own white balance, which a photo without a colour model can't render.
    static func warmer(process: Int) -> EditRecipe {
        var recipe = EditRecipe()
        recipe.processVersion = process
        recipe.whiteBalanceMode = .custom
        recipe[.temperature] = 7500
        recipe[.tint] = 12
        return recipe
    }

    /// A 96 x 96 X-Trans raw of saturated patches with edges at two angles: an X-E5's as the decoder
    /// gives it with the fork's matrix (`revision`, the fifth), or without one (`matrix` false), as
    /// LibRaw opened it before. With `revision` the first, it's an X-T5's, which always had one.
    static func xE5(matrix: Bool = true, revision: RawRevision = .fifth) -> DecodedImage {
        let pattern = XTransDemosaicTests.shifted(0, 0)
        let patches: [SIMD3<Float>] = [
            SIMD3(0.42, 0.12, 0.05), SIMD3(0.06, 0.4, 0.12), SIMD3(0.1, 0.16, 0.45), SIMD3(0.4, 0.36, 0.06),
        ]
        let (black, white): (Float, Float) = (1023, 16383)
        let samples = (0 ..< size * size).map { index in
            let (x, y) = (index % size, index / size)
            let color = Int(pattern.color(x: x, y: y))
            let patch = patches[((x + y) / 9 + (3 * x - y + 4 * size) / 13) % patches.count]
            return UInt16((black + patch[color] / Float(asShot[color]) * (white - black)).rounded())
        }
        var decoded = DecodedImage(
            width: size, height: size, layout: .mosaic(pattern), samples: samples,
            blackLevels: [Float](repeating: black, count: 36), whiteLevel: white, asShotMultipliers: asShot,
            cameraToSRGB: matrix ? cameraToSRGB : identity, xyzToCamera: matrix ? xyzToCamera : nil,
            orientation: 0, baselineExposure: 0,
            info: ImageInfo(
                url: URL(fileURLWithPath: "/DSCF0001.RAF"), pixelSize: PixelSize(width: size, height: size),
                isRaw: true, sensorDescription: "synthetic X-Trans", make: "Fujifilm",
                model: revision == .first ? "X-T5" : "X-E5",
            ),
        )
        decoded.noiseProfile = DetailStageTests.noise
        decoded.colorMatrixRevision = matrix ? revision : .first
        return decoded
    }

    func session(_ decoded: DecodedImage, revision: RawRevision = .current) throws -> ImageSession {
        try SessionBuilder(device: detail.device, queue: detail.queue, kernels: detail.kernels)
            .build(decoded, revision: revision)
    }

    func render(_ request: RenderRequest, _ engine: RedlampEngine, _ session: ImageSession) throws -> [SIMD3<Float>] {
        try HighlightReconstructionTests.pixels(engine.renderFrame(request, session: session))
    }
}
