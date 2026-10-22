import Foundation
import Metal
import RedlampEngineAPI
import RedlampKernels
import RedlampServices
import simd
import Testing
@testable import RedlampEngine

/// Linear raws the camera white-balanced already, as LibRaw says of Sony's YCbCr ARWs and Nikon's
/// small raws. Balanced again, every one of them opened pink (#480).
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct InCameraBalanceTests {
    /// The as-shot multipliers of an A7 IV's lossless compressed M raw, shot in daylight.
    static let asShot = SIMD3<Double>(2.368, 1, 1.773)
    /// Adobe's colour matrix for a typical Sony body (XYZ to camera), scaled.
    static let sony = [0.7374, -0.2389, -0.0551, -0.5435, 1.3162, 0.2519, -0.1006, 0.1795, 0.6552]
    /// A grey card in camera RGB, before white balance.
    static let card = SIMD3<Float>(repeating: 0.25) / SIMD3<Float>(asShot)

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let kernels: KernelLibrary

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        queue = try #require(device.makeCommandQueue())
        kernels = try KernelLibrary(device: device)
    }

    @Test func `a raw the camera balanced opens as the same raw unbalanced`() throws {
        let balanced = try session(Self.card * SIMD3<Float>(Self.asShot), balancedInCamera: true)
        let unbalanced = try session(Self.card, balancedInCamera: false)
        let pixel = balanced.analysis.pixel(x: 8, y: 8)
        #expect(simd_reduce_max(simd_abs(pixel - SIMD3(repeating: 0.25))) < 0.001, "the card is grey: \(pixel)")
        #expect(simd_reduce_max(simd_abs(pixel - unbalanced.analysis.pixel(x: 8, y: 8))) < 0.001)
        let rendered = try render(balanced), expected = try render(unbalanced)
        #expect(simd_reduce_max(simd_abs(rendered - expected)) < 0.002, "\(rendered), unbalanced \(expected)")
    }

    @Test func `Auto white balance keeps a grey card's as-shot balance`() throws {
        let session = try session(Self.card * SIMD3<Float>(Self.asShot), balancedInCamera: true)
        let model = try #require(session.colorModel)
        let auto = ImageAnalysis.autoWhiteBalance(session: session, model: model)
        let asShot = model.whiteBalance(forMultipliers: Self.asShot)
        #expect(abs(auto.temperature - asShot.temperature) < 30, "\(auto), as shot \(asShot)")
        #expect(abs(auto.tint - asShot.tint) < 1, "\(auto), as shot \(asShot)")
    }

    /// A flat 32 x 32 linear raw of `color`, with the black and white levels LibRaw gives Sony's
    /// YCbCr ARWs.
    func session(_ color: SIMD3<Float>, balancedInCamera: Bool) throws -> ImageSession {
        let (black, white): (Float, Float) = (1024, 17536)
        let pixel = (0 ..< 3).map { UInt16((black + color[$0] * (white - black)).rounded()) }
        var decoded = DecodedImage(
            width: 32, height: 32, layout: .linearRGB, samples: (0 ..< 32 * 32).flatMap { _ in pixel },
            blackLevels: [black, black, black], whiteLevel: white, asShotMultipliers: Self.asShot,
            cameraToSRGB: [1, 0, 0, 0, 1, 0, 0, 0, 1], xyzToCamera: Self.sony, orientation: 0, baselineExposure: 0,
            info: ImageInfo(
                url: URL(fileURLWithPath: "/ILCE-7M4.ARW"), pixelSize: PixelSize(width: 32, height: 32),
                isRaw: true, sensorDescription: "synthetic",
            ),
        )
        decoded.balancedInCamera = balancedInCamera
        return try SessionBuilder(device: device, queue: queue, kernels: kernels).build(decoded)
    }

    /// The centre of `session` rendered at As Shot.
    func render(_ session: ImageSession) throws -> SIMD3<Float> {
        let frame = try RedlampEngine().renderFrame(
            RenderRequest(recipe: EditRecipe(), targetSize: session.orientedSize, generation: 0), session: session,
        )
        IOSurfaceLock(frame.surface, .readOnly, nil)
        defer { IOSurfaceUnlock(frame.surface, .readOnly, nil) }
        let row = (IOSurfaceGetBaseAddress(frame.surface) + 16 * IOSurfaceGetBytesPerRow(frame.surface))
            .assumingMemoryBound(to: Float16.self)
        return SIMD3(Float(row[16 * 4]), Float(row[16 * 4 + 1]), Float(row[16 * 4 + 2]))
    }
}
