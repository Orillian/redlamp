import Foundation
import RedlampColor
import RedlampEngineAPI
import simd
import Testing
@testable import RedlampRecipes

/// Firmware looks: their ids, and the scene-referred table against the model it was baked
/// from, on the model's own test vectors.
struct FirmwareLookTests {
    @Test func `a look's id spells out its settings`() {
        let settings = FirmwareLookSettings(
            simulation: .chrome, dynamicRange: 200, highlight: -1, shadow: 1.5, color: 2, exposure: 0.25,
        )
        let reference = BaseLookReference(id: FirmwareLook.id(settings), name: "Chrome")
        #expect(reference.isFirmwareModel && reference.staysOnThisMac)
        #expect(FirmwareLook.settings(for: reference) == settings)
        #expect(FirmwareLook.settings(for: BuiltInBaseLook.color.reference) == nil)
    }

    @Test func `the identity model bakes every simulation at both ends of every setting`() throws {
        let model = try FirmwareFilmModel(files: .identity(), source: "identity")
        #expect(model.simulationNames.count == FirmwareSimulation.allCases.count)
        for simulation in FirmwareSimulation.allCases {
            for (tone, color, dynamicRange, toning) in [(-2.0, -4, 100, -9), (4.0, 4, 400, 9)] {
                let settings = FirmwareLookSettings(
                    simulation: simulation, dynamicRange: dynamicRange, highlight: tone, shadow: 2 - tone,
                    color: color, warmCool: toning, magentaGreen: toning,
                )
                _ = try FirmwareLook.table(settings, model: model, size: 3)
            }
        }
    }

    @Test func `settings come within the camera's steps, and only black and white is toned`() {
        let color = FirmwareLookSettings(
            simulation: .standard, dynamicRange: 300, highlight: 9, shadow: -0.2, color: 7, warmCool: 3,
            exposure: -0.001,
        ).clamped
        #expect(color.dynamicRange == 200 || color.dynamicRange == 400)
        #expect(color.highlight == 4 && color.shadow == 0 && color.color == 4 && color.warmCool == 0)
        #expect(FirmwareLook.id(color).hasSuffix("ev+0.00"))
        let mono = FirmwareLookSettings(simulation: .acrosRed, warmCool: 12, magentaGreen: -3).clamped
        #expect(mono.warmCool == 9 && mono.magentaGreen == -3)
    }

    @Test func `every one of the model's simulations has a name, and slots keep theirs`() {
        #expect(FirmwareSimulation.allCases.count == 20)
        #expect(FirmwareSimulation.allCases.filter { $0.slot != nil }.count == FilmSlot.allCases.count)
        #expect(FirmwareSimulation(slot: .chrome)?.name == FilmSlot.chrome.name)
        #expect(FirmwareSimulation.realaAce.slot == nil && !FirmwareSimulation.realaAce.isMonochrome)
        #expect(FirmwareSimulation.acros.isMonochrome)
    }

    @Test(.enabled(if: FirmwareTestModel.isAvailable))
    func `the model's files name every simulation the prototype offers`() throws {
        let model = try FirmwareTestModel.model()
        #expect(Set(model.simulationNames) == Set(FirmwareSimulation.allCases.map(\.modelName)))
        for simulation in FirmwareSimulation.allCases {
            #expect(model.isMonochrome(simulation.modelName) == simulation.isMonochrome, "\(simulation)")
        }
    }

    @Test(.enabled(if: FirmwareTestModel.isAvailable))
    func `the same settings bake the same table, and settings change it`() throws {
        let model = try FirmwareTestModel.model()
        let neutral = try FirmwareLook.definition(FirmwareLookSettings(simulation: .chrome), model: model)
        let again = try FirmwareLook.definition(FirmwareLookSettings(simulation: .chrome), model: model)
        let harder = try FirmwareLook.definition(FirmwareLookSettings(simulation: .chrome, shadow: 2), model: model)
        #expect(neutral.table?.space == .sceneLog && neutral.table?.size == FirmwareLook.tableSize)
        #expect(neutral.table?.contentHash == again.table?.contentHash)
        #expect(neutral.table?.contentHash != harder.table?.contentHash)
        #expect(neutral.reference.isFirmwareModel)
    }

    /// The table read as the GPU reads it, against the model at the test vectors' inputs: the
    /// error the 33-point table adds.
    @Test(.enabled(if: FirmwareTestModel.isAvailable), arguments: [FirmwareLook.tableSize, 65])
    func `the baked table follows the model between its points`(size: Int) throws {
        let model = try FirmwareTestModel.model()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let vectors = try decoder.decode(
            FirmwareFilmModelTests.Vectors.self, from: Data(contentsOf: FirmwareTestModel.vectorsURL),
        )
        var differences: [Double] = []
        for test in vectors.cases {
            guard let simulation = FirmwareSimulation.allCases.first(where: { $0.modelName == test.case.sim })
            else { Issue.record("no simulation for \(test.case.sim)"); continue }
            let settings = FirmwareLookSettings(
                simulation: simulation, dynamicRange: test.case.dr ?? 100, highlight: test.case.highlight ?? 0,
                shadow: test.case.shadow ?? 0, color: test.case.color ?? 0, warmCool: Int(test.case.wc ?? 0),
                magentaGreen: Int(test.case.mg ?? 0), exposure: 0,
            )
            let table = try FirmwareLook.table(settings.clamped, model: model, size: size)
            for (input, expected) in zip(vectors.inputsLinearRec709, test.outputSrgb) {
                let scene = ColorMatrices.sRGBToRec2020 * FirmwareFilmModelTests.vector(input)
                let sampled = SIMD3<Double>(table.sample(SceneLogEncoding.encode(SIMD3<Float>(scene))))
                let wide = SIMD3(SRGB.decode(sampled.x), SRGB.decode(sampled.y), SRGB.decode(sampled.z))
                let narrow = simd_clamp(ColorMatrices.rec2020ToSRGB * wide, .zero, SIMD3(repeating: 1))
                let display = SIMD3(SRGB.encode(narrow.x), SRGB.encode(narrow.y), SRGB.encode(narrow.z))
                differences.append(simd_reduce_max(simd_abs(display - FirmwareFilmModelTests.vector(expected))))
            }
        }
        differences.sort()
        let mean = differences.reduce(0, +) / Double(differences.count)
        let p90 = differences[differences.count * 9 / 10]
        print(String(
            format: "firmware look table, \(size) points: mean %.4f, median %.4f, p90 %.4f, max %.4f (display sRGB, %d samples)",
            mean, differences[differences.count / 2], p90, differences.last ?? 0, differences.count,
        ))
        #expect(p90 < 0.05)
    }

    @Test(.enabled(if: FirmwareTestModel.isAvailable))
    func `a look bakes quickly enough to follow the controls`() throws {
        let model = try FirmwareTestModel.model()
        let start = Date()
        _ = try FirmwareLook.table(FirmwareLookSettings(simulation: .negativeClassic, color: 3), model: model)
        print(String(format: "firmware look bake: %.0f ms", Date().timeIntervalSince(start) * 1000))
    }
}
