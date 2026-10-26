import Foundation
import Metal
import RedlampEngineAPI
import RedlampKernels
import RedlampServices
import simd
import Testing
@testable import RedlampEngine

/// Linear raws the camera white-balanced already, as LibRaw says of Sony's YCbCr ARWs and Nikon's
/// small raws. Balanced again, every one of them opened pink (#480). From process 18 (raw
/// revision 4) they're balanced once, and edits made before render as they did.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct InCameraBalanceTests {
    /// The as-shot multipliers of an A7 IV's lossless compressed M raw, shot in daylight.
    static let asShot = SIMD3<Double>(2.368, 1, 1.773)
    /// Adobe's colour matrix for a typical Sony body (XYZ to camera), scaled.
    static let sony = [0.7374, -0.2389, -0.0551, -0.5435, 1.3162, 0.2519, -0.1006, 0.1795, 0.6552]
    /// A grey card in camera RGB, before white balance.
    static let card = SIMD3<Float>(repeating: 0.25) / SIMD3<Float>(asShot)
    /// The black and white levels LibRaw gives Sony's YCbCr ARWs.
    static let black: Float = 1024
    static let white: Float = 17536

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

    // MARK: - Edits made before process 18

    /// The photo opens at the current revision and keeps its raw source, so an edit at process 17
    /// renders from a variant built at the third, balanced twice, pixel for pixel as the raw renders
    /// without the camera's mark, which is how Redlamp took it then.
    @Test func `an edit at process 17 renders the raw balanced twice, as it did`() throws {
        let engine = try RedlampEngine()
        let grey = Self.card * SIMD3<Float>(Self.asShot)
        let photo = try session(grey, balancedInCamera: true)
        let unmarked = try session(grey, balancedInCamera: false)
        #expect(photo.rawSource != nil && unmarked.rawSource == nil)
        var recipe = EditRecipe()
        recipe.processVersion = 17
        let twice = try engine.revisions.session(for: recipe, base: photo).analysis.pixel(x: 8, y: 8)
        #expect(simd_reduce_max(simd_abs(twice - 0.25 * SIMD3<Float>(Self.asShot))) < 0.002, "balanced twice: \(twice)")
        let request = RenderRequest(recipe: recipe, targetSize: photo.orientedSize, generation: 0)
        let older = try HighlightReconstructionTests.pixels(engine.renderFrame(request, session: photo))
        let before = try HighlightReconstructionTests.pixels(engine.renderFrame(request, session: unmarked))
        #expect(older == before)
        #expect(engine.revisions.variantsBuilt == 1)
        recipe.processVersion = 18
        #expect(try engine.revisions.session(for: recipe, base: photo) === photo)
    }

    /// A photo opened for an edit made before process 18 is built as Redlamp built it then, its
    /// noise measured on the balanced samples. Moved to 18, the edit renders from a variant
    /// balanced once, its noise measured before the camera's balance, as the photo opened at 18
    /// renders it.
    @Test func `an edit moved to process 18 renders balanced once from a photo opened for 17`() throws {
        let engine = try RedlampEngine()
        let photo = try session(noisyCard(balancedInCamera: true), revision: .third)
        let unmarked = try session(noisyCard(balancedInCamera: false), revision: .third)
        let current = try session(noisyCard(balancedInCamera: true))
        #expect(photo.rawSource != nil)
        #expect(photo.noise == unmarked.noise && photo.noise != current.noise, "\(photo.noise), \(current.noise)")
        var recipe = EditRecipe()
        recipe.processVersion = 17
        #expect(try engine.revisions.session(for: recipe, base: photo) === photo)
        recipe.processVersion = 18
        let variant = try engine.revisions.session(for: recipe, base: photo)
        #expect(variant !== photo && variant.noise == current.noise)
        let request = RenderRequest(recipe: recipe, targetSize: current.orientedSize, generation: 0)
        let moved = try HighlightReconstructionTests.pixels(engine.renderFrame(request, session: photo))
        let opened = try HighlightReconstructionTests.pixels(engine.renderFrame(request, session: current))
        #expect(moved == opened)
        #expect(engine.revisions.variantsBuilt == 1)
    }

    // MARK: - Helpers

    /// A flat 32 x 32 linear raw of `color`.
    func session(_ color: SIMD3<Float>, balancedInCamera: Bool) throws -> ImageSession {
        let pixel = (0 ..< 3).map { UInt16((Self.black + color[$0] * (Self.white - Self.black)).rounded()) }
        return try session(raw(
            width: 32, height: 32, samples: (0 ..< 32 * 32).flatMap { _ in pixel }, balancedInCamera: balancedInCamera,
        ))
    }

    /// Flat 16 x 16 patches of random greys as the camera balanced them, with Poisson–Gaussian
    /// noise from before its balance, which scales each channel's noise with its multiplier.
    func noisyCard(balancedInCamera: Bool) -> DecodedImage {
        let (width, height, a, b): (Int, Int, Float, Float) = (512, 512, 4e-4, 4e-6)
        var random = SeededRandom(seed: 480)
        let patches = (0 ..< (width / 16) * (height / 16)).map { _ in 0.05 + 0.75 * random.uniform() }
        let multipliers = SIMD3<Float>(Self.asShot)
        var samples = [UInt16](repeating: 0, count: width * height * 3)
        for y in 0 ..< height {
            for x in 0 ..< width {
                for channel in 0 ..< 3 {
                    let signal = patches[(y / 16) * (width / 16) + x / 16] / multipliers[channel]
                    let value = (signal + (a * signal + b).squareRoot() * random.gaussian()) * multipliers[channel]
                    let level = Self.black + value * (Self.white - Self.black)
                    samples[(y * width + x) * 3 + channel] = UInt16(min(max(level, 0), 65535).rounded())
                }
            }
        }
        return raw(width: width, height: height, samples: samples, balancedInCamera: balancedInCamera)
    }

    func raw(width: Int, height: Int, samples: [UInt16], balancedInCamera: Bool) -> DecodedImage {
        var decoded = DecodedImage(
            width: width, height: height, layout: .linearRGB, samples: samples,
            blackLevels: [Self.black, Self.black, Self.black], whiteLevel: Self.white, asShotMultipliers: Self.asShot,
            cameraToSRGB: [1, 0, 0, 0, 1, 0, 0, 0, 1], xyzToCamera: Self.sony, orientation: 0, baselineExposure: 0,
            info: ImageInfo(
                url: URL(fileURLWithPath: "/ILCE-7M4.ARW"), pixelSize: PixelSize(width: width, height: height),
                isRaw: true, sensorDescription: "synthetic",
            ),
        )
        decoded.balancedInCamera = balancedInCamera
        return decoded
    }

    func session(_ decoded: DecodedImage, revision: RawRevision = .current) throws -> ImageSession {
        try SessionBuilder(device: device, queue: queue, kernels: kernels).build(decoded, revision: revision)
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

/// xorshift64* with Box–Muller, so tests are reproducible.
private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    mutating func uniform() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func gaussian() -> Float {
        let u1 = max(uniform(), 1e-7)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * uniform())
    }
}
