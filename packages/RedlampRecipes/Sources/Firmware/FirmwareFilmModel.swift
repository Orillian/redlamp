import Foundation
import simd

/// The film-simulation model derived from a camera's firmware, an experiment behind a switch
/// that's off by default (TON-49): a CPU port of the reference renderer's `render()`.
///
/// Every number the model uses is read at runtime from its folder (`fsim_params.json`,
/// `tone_gain_curves.json`, `calibration.json` and `fujisim_constants.json`); this file holds
/// only the stages and their order. None of the folder's files or numbers may be committed,
/// which `scripts/check-firmware-numbers.py` checks.
///
/// Input is linear light in Rec.709 primaries with the white balance applied, middle grey at
/// 0.18; output is display sRGB in 0...1.
public struct FirmwareFilmModel: Sendable {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case unsupported(String)
        case invalid(String)

        public var description: String {
            switch self {
            case let .missing(file): "the model folder has no \(file)"
            case let .unsupported(what): "the port doesn't apply \(what)"
            case let .invalid(what): "the model's \(what) can't be read"
            }
        }
    }

    /// Where the model was read from, which keys its baked looks: the folder's path, or the
    /// hosted file's digest.
    public let source: String
    /// The model's simulation names, as its files key them.
    public let simulationNames: [String]
    private let simulations: [String: Simulation]
    private let constants: Constants
    private let preMatrix: simd_double3x3
    private let chromaScale: SIMD2<Double>
    private let chromaSwap: Bool
    private let ycbcr: simd_double3x3
    private let ycbcrInverse: simd_double3x3

    /// The model's four files as bytes, read from the folder or opened from the hosted pack. The
    /// field names match the files `FirmwareFilmModel.fileNames` lists, in that order.
    public struct Files: Sendable {
        /// `fsim_params.json`.
        public var parameters: Data
        /// `tone_gain_curves.json`.
        public var toneGains: Data
        /// `calibration.json`.
        public var calibration: Data
        /// `fujisim_constants.json`.
        public var constants: Data

        public init(parameters: Data, toneGains: Data, calibration: Data, constants: Data) {
            self.parameters = parameters
            self.toneGains = toneGains
            self.calibration = calibration
            self.constants = constants
        }

        /// The four files in a model folder.
        public init(folder: URL) throws {
            func read(_ name: String) throws -> Data {
                let url = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { throw LoadError.missing(name) }
                do {
                    return try Data(contentsOf: url)
                } catch {
                    throw LoadError.invalid("\(name) (\(error))")
                }
            }
            let constants = try read("fujisim_constants.json")
            let calibration = try read("calibration.json")
            let parameters = try read("fsim_params.json")
            try self.init(
                parameters: parameters, toneGains: read("tone_gain_curves.json"), calibration: calibration,
                constants: constants,
            )
        }
    }

    /// The four files the model reads, in the order `Files` and the pack store them.
    public static let fileNames = [
        "fsim_params.json", "tone_gain_curves.json", "calibration.json", "fujisim_constants.json",
    ]

    public init(folder: URL) throws {
        try self.init(files: Files(folder: folder), source: folder.standardizedFileURL.path)
    }

    /// Parses the model from the four files in memory, from the folder or the hosted pack.
    public init(files: Files, source: String) throws {
        self.source = source
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ name: String) throws -> T {
            do {
                return try decoder.decode(type, from: data)
            } catch {
                throw LoadError.invalid("\(name) (\(error))")
            }
        }
        let constants = try decode(Constants.self, files.constants, "fujisim_constants.json")
        let calibration = try decode(Calibration.self, files.calibration, "calibration.json")
        let parameters = try decode([String: SimulationParameters].self, files.parameters, "fsim_params.json")
        let gains = try decode(
            [String: [String: [String: [String: [Double]]]]].self, files.toneGains, "tone_gain_curves.json",
        )
        guard !calibration.gamut else { throw LoadError.unsupported("the gamut table, which its calibration turns on") }
        self.constants = constants
        preMatrix = try Self.matrix(calibration.preMatrix, "pre-matrix")
        guard calibration.chromaScale.count == 2 else { throw LoadError.invalid("chroma scale") }
        chromaScale = SIMD2(calibration.chromaScale[0], calibration.chromaScale[1])
        chromaSwap = calibration.chromaSwap
        ycbcr = try Self.matrix(constants.ycbcrMatrix, "YCbCr matrix")
        ycbcrInverse = ycbcr.inverse
        var simulations: [String: Simulation] = [:]
        for (name, raw) in parameters {
            guard let gain = gains[name] else { throw LoadError.invalid("tone gains for \(name)") }
            simulations[name] = try Simulation(raw, gains: gain, constants: constants)
        }
        self.simulations = simulations
        simulationNames = parameters.keys.sorted()
    }

    /// Whether `folder` holds the four files the model reads.
    public static func isAvailable(at folder: URL) -> Bool {
        fileNames.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    public func isMonochrome(_ simulation: String) -> Bool {
        simulations[simulation]?.isMonochrome ?? false
    }

    /// The tone stage's gain curve for a dynamic range and Highlight and Shadow Tone: the
    /// highlight and shadow curves combined relative to the neutral one, in units of 1.
    public func toneGain(_ simulation: String, dr: Int = 100, highlight: Double = 0, shadow: Double = 0) throws
        -> [Double] {
        guard let curves = simulations[simulation] else { throw LoadError.invalid("simulation \(simulation)") }
        guard let index = constants.drIndex[String(dr)], let set = curves.gains[String(index)] else {
            throw LoadError.invalid("dynamic range \(dr)")
        }
        let neutral = try curve(set, "H", tone: 0)
        let high = try curve(set, "H", tone: highlight)
        let low = try curve(set, "S", tone: shadow)
        return (0 ..< neutral.count).map { high[$0] * low[$0] / max(neutral[$0], 1) / constants.gainUnit }
    }

    private func curve(_ set: [String: [String: [Double]]], _ side: String, tone: Double) throws -> [Double] {
        let key = (Double(constants.toneKeyNeutral) + Double(constants.toneKeyStepsPerUnit) * tone)
            .rounded(.toNearestOrEven)
        guard let curve = set[side]?[String(Int(key))] else { throw LoadError.invalid("tone \(side) \(tone)") }
        return curve
    }

    /// The model for one simulation and its settings, ready to render pixels.
    public func rendering(
        _ simulation: String,
        color: Int = 0,
        dr: Int = 100,
        highlight: Double = 0,
        shadow: Double = 0,
        warmCool: Double = 0,
        magentaGreen: Double = 0,
    ) throws -> Rendering {
        guard let parameters = simulations[simulation] else { throw LoadError.invalid("simulation \(simulation)") }
        guard let factor = constants.colorFactor[String(color)] else { throw LoadError.invalid("Color \(color)") }
        let gain = try toneGain(simulation, dr: dr, highlight: highlight, shadow: shadow)
        // Row-major (Cb from Cb, Cb from Cr, Cr from Cb, Cr from Cr).
        var chroma = parameters.chroma * (factor / constants.colorFactorUnit)
        if chromaSwap {
            chroma = SIMD4(chroma.w, chroma.z, chroma.y, chroma.x)
        }
        chroma *= SIMD4(chromaScale.x, chromaScale.x, chromaScale.y, chromaScale.y)
        return Rendering(
            parameters: parameters, constants: constants, gain: gain,
            exposure: constants.exposureK / (Double(dr) / 100),
            preMatrix: preMatrix, chroma: chroma, ycbcr: ycbcr, ycbcrInverse: ycbcrInverse,
            toning: parameters
                .isMonochrome ? toning(parameters, warmCool: warmCool, magentaGreen: magentaGreen) : .zero,
        )
    }

    /// The monochrome toning offset on (Cb, Cr) at full strength.
    private func toning(_ parameters: Simulation, warmCool: Double, magentaGreen: Double) -> SIMD2<Double> {
        let wc = constants.toningPerStep["wc"] ?? [0, 0]
        let mg = constants.toningPerStep["mg"] ?? [0, 0]
        var offset = (SIMD2(wc[0], wc[1]) * warmCool + SIMD2(mg[0], mg[1]) * magentaGreen) / constants.toningUnit
        if let raw = parameters.toning {
            offset += SIMD2(raw.y, raw.x) / constants.sepiaUnit
        }
        return offset
    }

    /// `render()` for one pixel; see `rendering(_:…)` to render many with the same settings.
    public func render(
        _ linear: SIMD3<Double>,
        _ simulation: String,
        color: Int = 0,
        dr: Int = 100,
        highlight: Double = 0,
        shadow: Double = 0,
        warmCool: Double = 0,
        magentaGreen: Double = 0,
    ) throws -> SIMD3<Double> {
        try rendering(
            simulation, color: color, dr: dr, highlight: highlight, shadow: shadow, warmCool: warmCool,
            magentaGreen: magentaGreen,
        )(linear)
    }

    private static func matrix(_ rows: [[Double]], _ what: String) throws -> simd_double3x3 {
        guard rows.count == 3, rows.allSatisfy({ $0.count == 3 }) else { throw LoadError.invalid(what) }
        return simd_double3x3(rows: rows.map { SIMD3($0[0], $0[1], $0[2]) })
    }
}

/// One of the three pieces the inner key is salted with (`FirmwareModelKey`), kept apart so no
/// single source file holds the salt (TON-50). These bytes are public and carry nothing of the
/// model; the secret the key also needs is not in the sources.
enum FirmwareKeySaltA {
    static let bytes: [UInt8] = [0x9B, 0x1C, 0x7F, 0x30, 0xE2, 0xA4, 0x58, 0x6D, 0xC1, 0x0A]
}

// MARK: - Rendering

public extension FirmwareFilmModel {
    /// One simulation at one set of settings, with everything that doesn't depend on the pixel
    /// worked out.
    struct Rendering: Sendable {
        fileprivate let parameters: Simulation
        fileprivate let constants: Constants
        fileprivate let gain: [Double]
        /// The tone stage's exposure constant over the dynamic range.
        fileprivate let exposure: Double
        fileprivate let preMatrix: simd_double3x3
        fileprivate let chroma: SIMD4<Double>
        fileprivate let ycbcr: simd_double3x3
        fileprivate let ycbcrInverse: simd_double3x3
        fileprivate let toning: SIMD2<Double>

        /// Linear Rec.709 in, display sRGB out.
        public func callAsFunction(_ linear: SIMD3<Double>) -> SIMD3<Double> {
            let toned = tone(preMatrix * linear)
            let rgb = parameters.matrix * toned
            let curved = SIMD3(curve(rgb.x, 0), curve(rgb.y, 1), curve(rgb.z, 2))
            var ycc = ycbcr * curved
            let (cb, cr) = (ycc.y, ycc.z)
            ycc.y = chroma.x * cb + chroma.y * cr
            ycc.z = chroma.z * cb + chroma.w * cr
            if toning != .zero {
                let weight = Interpolation.linear(
                    ycc.x * constants.toningTaperLumaScale, constants.toningTaperY, constants.toningTaperW,
                )
                ycc.y += toning.x * weight
                ycc.z += toning.y * weight
            }
            return simd_clamp(ycbcrInverse * ycc, .zero, SIMD3(repeating: 1))
        }

        /// The tone stage: one gain for all three channels, looked up on the pixel's luminance.
        private func tone(_ linear: SIMD3<Double>) -> SIMD3<Double> {
            let weights = SIMD3(constants.lumaWeights[0], constants.lumaWeights[1], constants.lumaWeights[2])
            let level = max(simd_dot(linear, weights) * exposure, constants.lumaFloor)
            let position = Double(constants.gainClipBin) + constants.binsPerStop * log2(level)
            let gain = Interpolation.linear(position, overIndicesOf: gain)
            return linear * (exposure * gain)
        }

        private func curve(_ value: Double, _ channel: Int) -> Double {
            Interpolation.linear(min(max(value, 0), 1), parameters.knots, parameters.curves[channel])
        }
    }
}

// MARK: - The files

private extension FirmwareFilmModel {
    struct Constants: Decodable, Sendable {
        var binsPerStop: Double
        var exposureK: Double
        var gainUnit: Double
        var gainClipBin: Int
        var toneKeyNeutral: Int
        var toneKeyStepsPerUnit: Int
        var drIndex: [String: Int]
        var lumaWeights: [Double]
        var lumaFloor: Double
        var matrixUnit: Double
        var knotIntervalsPerHeader: Int
        var curveInputMax: Double
        var curveOutputMax: Double
        var ycbcrMatrix: [[Double]]
        var chromaUnit: Double
        var colorFactor: [String: Double]
        var colorFactorUnit: Double
        var toningPerStep: [String: [Double]]
        var toningUnit: Double
        var toningTaperLumaScale: Double
        var toningTaperY: [Double]
        var toningTaperW: [Double]
        var sepiaUnit: Double
    }

    struct Calibration: Decodable {
        var preMatrix: [[Double]]
        var chromaScale: [Double]
        var chromaSwap: Bool
        var gamut: Bool
    }

    struct SimulationParameters: Decodable {
        var matrix: [Double]
        var hdr: [Int]
        var curves: [[Double]]
        var chroma: [[Double]]
        var monochrome: Bool?
        var toningRaw: [Double]?
    }
}

/// A simulation's stages, in units of 1.
private struct Simulation: Sendable {
    var matrix: simd_double3x3
    /// The tone curves' knots over 0...1 input.
    var knots: [Double]
    /// Each channel's curve at the knots, display-encoded.
    var curves: [[Double]]
    /// Row-major, as the file has it.
    var chroma: SIMD4<Double>
    var isMonochrome: Bool
    /// The fixed toning offset, as the file orders it.
    var toning: SIMD2<Double>?
    /// The tone gain curves by dynamic range index, then side, then tone key.
    var gains: [String: [String: [String: [Double]]]]

    init(
        _ raw: FirmwareFilmModel.SimulationParameters,
        gains: [String: [String: [String: [Double]]]],
        constants: FirmwareFilmModel.Constants,
    ) throws {
        guard raw.matrix.count == 9, raw.chroma.count == 2, raw.chroma.allSatisfy({ $0.count == 2 }),
              raw.curves.count == 3
        else { throw FirmwareFilmModel.LoadError.invalid("simulation parameters") }
        let m = raw.matrix.map { $0 / constants.matrixUnit }
        matrix = simd_double3x3(rows: [SIMD3(m[0], m[1], m[2]), SIMD3(m[3], m[4], m[5]), SIMD3(m[6], m[7], m[8])])
        var x: [Double] = [0]
        for step in raw.hdr {
            for _ in 0 ..< constants.knotIntervalsPerHeader {
                x.append(x[x.count - 1] + Double(1 << step))
            }
        }
        guard raw.curves.allSatisfy({ $0.count == x.count }) else {
            throw FirmwareFilmModel.LoadError.invalid("tone curve knots")
        }
        knots = x.map { $0 / constants.curveInputMax }
        curves = raw.curves.map { $0.map { $0 / constants.curveOutputMax } }
        chroma = SIMD4(raw.chroma[0][0], raw.chroma[0][1], raw.chroma[1][0], raw.chroma[1][1]) / constants.chromaUnit
        isMonochrome = raw.monochrome ?? false
        toning = raw.toningRaw.flatMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil }
        self.gains = gains
    }
}

/// numpy's `interp`: piecewise linear, holding the end values outside the knots.
enum Interpolation {
    static func linear(_ x: Double, _ xs: [Double], _ ys: [Double]) -> Double {
        guard let first = xs.first, let last = xs.last else { return 0 }
        if x <= first {
            return ys[0]
        }
        if x >= last {
            return ys[ys.count - 1]
        }
        var low = 0, high = xs.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if xs[middle] <= x {
                low = middle
            } else {
                high = middle
            }
        }
        let t = (x - xs[low]) / (xs[high] - xs[low])
        return ys[low] + t * (ys[high] - ys[low])
    }

    /// Over knots at 0, 1, 2, …
    static func linear(_ x: Double, overIndicesOf ys: [Double]) -> Double {
        if x <= 0 {
            return ys[0]
        }
        let last = Double(ys.count - 1)
        if x >= last {
            return ys[ys.count - 1]
        }
        let i = Int(x)
        let t = x - Double(i)
        return ys[i] + t * (ys[i + 1] - ys[i])
    }
}
