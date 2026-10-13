import Foundation
import simd
import Testing
@testable import RedlampRecipes

/// The firmware model's port against the reference renderer's test vectors, read at runtime
/// from the model's folder; skipped on a Mac without it. None of its numbers are committed.
@Suite(.enabled(if: FirmwareTestModel.isAvailable))
struct FirmwareFilmModelTests {
    /// The reference's tolerance for a port in floating point.
    static let tolerance = 1e-4

    struct Vectors: Decodable {
        struct Case: Decodable {
            struct Settings: Decodable {
                var sim: String
                var color: Int?
                var dr: Int?
                var highlight: Double?
                var shadow: Double?
                var wc: Double?
                var mg: Double?
            }

            var `case`: Settings
            var outputSrgb: [[Double]]
        }

        var inputsLinearRec709: [[Double]]
        var cases: [Case]
        var toneGainExamples: [String: [Double]]
    }

    static func vectors() throws -> Vectors {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Vectors.self, from: Data(contentsOf: FirmwareTestModel.vectorsURL))
    }

    static func vector(_ values: [Double]) -> SIMD3<Double> {
        SIMD3(values[0], values[1], values[2])
    }

    @Test func `every test vector renders as the reference does`() throws {
        let model = try FirmwareTestModel.model()
        let vectors = try Self.vectors()
        #expect(vectors.cases.count > 0)
        var worst = 0.0
        for test in vectors.cases {
            let settings = test.case
            let rendering = try model.rendering(
                settings.sim, color: settings.color ?? 0, dr: settings.dr ?? 100, highlight: settings.highlight ?? 0,
                shadow: settings.shadow ?? 0, warmCool: settings.wc ?? 0, magentaGreen: settings.mg ?? 0,
            )
            #expect(test.outputSrgb.count == vectors.inputsLinearRec709.count)
            for (input, expected) in zip(vectors.inputsLinearRec709, test.outputSrgb) {
                let difference = simd_reduce_max(simd_abs(rendering(Self.vector(input)) - Self.vector(expected)))
                worst = max(worst, difference)
                #expect(difference <= Self.tolerance, "\(settings.sim) at \(input)")
            }
        }
        print("firmware model: largest difference from the reference \(worst)")
    }

    @Test func `the tone stage's gain curves match the reference's`() throws {
        let model = try FirmwareTestModel.model()
        for (name, expected) in try Self.vectors().toneGainExamples {
            let parts = name.components(separatedBy: "_dr")
            let settings = parts[1].split(separator: "_")
            let gain = try model.toneGain(
                parts[0], dr: #require(Int(settings[0])), highlight: #require(Double(settings[1].dropFirst())),
                shadow: #require(Double(settings[2].dropFirst())),
            )
            #expect(gain.count == expected.count)
            for (a, b) in zip(gain, expected) {
                #expect(abs(a - b) <= Self.tolerance, "\(name)")
            }
        }
    }

    @Test func `the model reads every simulation its files hold`() throws {
        let model = try FirmwareTestModel.model()
        #expect(model.simulationNames.count == 20)
        #expect(model.isMonochrome("ACROS") && !model.isMonochrome("PROVIA"))
    }

    @Test func `a folder missing a file names it`() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: FirmwareFilmModel.LoadError.missing("fujisim_constants.json")) {
            try FirmwareFilmModel(folder: empty)
        }
    }
}
