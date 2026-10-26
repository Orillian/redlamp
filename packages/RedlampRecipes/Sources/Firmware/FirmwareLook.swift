#if !REDLAMP_APP_STORE
    import Foundation
    import RedlampColor
    import RedlampEngineAPI
    import simd

    /// The firmware model's simulations. Those Redlamp has a film slot for go by the slot's name;
    /// the others, which only the model offers, by the model's.
    public enum FirmwareSimulation: String, CaseIterable, Sendable, Hashable {
        case standard
        case vividSlide = "vivid-slide"
        case softSlide = "soft-slide"
        case chrome
        case negativeHigh = "negative-high"
        case negativeStandard = "negative-standard"
        case negativeClassic = "negative-classic"
        case negativeNostalgic = "negative-nostalgic"
        case cinema
        case bleach
        case monochrome
        case monochromeYellow = "monochrome-yellow"
        case monochromeRed = "monochrome-red"
        case monochromeGreen = "monochrome-green"
        case sepia
        case acros
        case acrosYellow = "acros-yellow"
        case acrosRed = "acros-red"
        case acrosGreen = "acros-green"
        case realaAce = "reala-ace"

        public init?(slot: FilmSlot) {
            self.init(rawValue: slot.rawValue)
        }

        /// The slot recipe cards name it by; nil for the model's own.
        public var slot: FilmSlot? {
            FilmSlot(rawValue: rawValue)
        }

        public var name: String {
            switch self {
            case .acros: "ACROS"
            case .acrosYellow: "ACROS + Yellow"
            case .acrosRed: "ACROS + Red"
            case .acrosGreen: "ACROS + Green"
            case .realaAce: "Reala Ace"
            default: slot?.name ?? rawValue
            }
        }

        /// How the model's files name it.
        public var modelName: String {
            switch self {
            case .standard: "PROVIA"
            case .vividSlide: "Velvia"
            case .softSlide: "ASTIA"
            case .chrome: "Classic Chrome"
            case .negativeHigh: "PRO Neg Hi"
            case .negativeStandard: "PRO Neg Std"
            case .negativeClassic: "Classic Neg"
            case .negativeNostalgic: "Nostalgic Neg"
            case .cinema: "ETERNA"
            case .bleach: "Bleach Bypass"
            case .monochrome: "Monochrome"
            case .monochromeYellow: "Monochrome+Ye"
            case .monochromeRed: "Monochrome+R"
            case .monochromeGreen: "Monochrome+G"
            case .sepia: "Sepia"
            case .acros: "ACROS"
            case .acrosYellow: "ACROS+Ye"
            case .acrosRed: "ACROS+R"
            case .acrosGreen: "ACROS+G"
            case .realaAce: "Reala Ace"
            }
        }

        public var isMonochrome: Bool {
            switch self {
            case .acros, .acrosYellow, .acrosRed, .acrosGreen: true
            default: slot?.isMonochrome ?? false
            }
        }
    }

    /// A firmware look's settings, in the camera's own steps. Its look's id spells them out, so
    /// the id alone bakes the same table.
    public struct FirmwareLookSettings: Sendable, Hashable {
        public static let dynamicRanges = [100, 200, 400]
        public static let toneRange: ClosedRange<Double> = -2 ... 4
        public static let colorRange: ClosedRange<Int> = -4 ... 4
        public static let toningRange: ClosedRange<Int> = -9 ... 9

        public var simulation: FirmwareSimulation
        public var dynamicRange: Int
        /// Highlight and Shadow Tone, in half steps.
        public var highlight: Double
        public var shadow: Double
        public var color: Int
        /// Monochromatic Color, for black-and-white simulations.
        public var warmCool: Int
        public var magentaGreen: Int
        /// Stops added to Redlamp's scene light before the model.
        public var exposure: Double

        public init(
            simulation: FirmwareSimulation,
            dynamicRange: Int = 100,
            highlight: Double = 0,
            shadow: Double = 0,
            color: Int = 0,
            warmCool: Int = 0,
            magentaGreen: Int = 0,
            exposure: Double = FirmwareLook.exposure,
        ) {
            self.simulation = simulation
            self.dynamicRange = dynamicRange
            self.highlight = highlight
            self.shadow = shadow
            self.color = color
            self.warmCool = warmCool
            self.magentaGreen = magentaGreen
            self.exposure = exposure
        }

        /// Within the camera's ranges and steps; toning only for black and white.
        public var clamped: FirmwareLookSettings {
            var settings = self
            func half(_ x: Double) -> Double {
                // Adding zero turns -0 into 0, so equal settings spell the same id.
                (min(max(x, Self.toneRange.lowerBound), Self.toneRange.upperBound) * 2).rounded() / 2 + 0
            }
            settings.dynamicRange = Self.dynamicRanges.min { abs($0 - dynamicRange) < abs($1 - dynamicRange) } ?? 100
            settings.highlight = half(highlight)
            settings.shadow = half(shadow)
            settings.color = min(max(color, Self.colorRange.lowerBound), Self.colorRange.upperBound)
            let toning = simulation.isMonochrome
            settings
                .warmCool = toning ? min(max(warmCool, Self.toningRange.lowerBound), Self.toningRange.upperBound) : 0
            settings.magentaGreen = toning
                ? min(max(magentaGreen, Self.toningRange.lowerBound), Self.toningRange.upperBound) : 0
            settings.exposure = (exposure * 100).rounded() / 100 + 0
            return settings
        }

        /// The settings part of the look's id: `dr100_h+0.0_s+0.0_c+0_wc+0_mg+0_ev+0.00`.
        var key: String {
            String(
                format: "dr%ld_h%+.1f_s%+.1f_c%+ld_wc%+ld_mg%+ld_ev%+.2f",
                dynamicRange, highlight, shadow, color, warmCool, magentaGreen, exposure,
            )
        }

        init?(simulation: FirmwareSimulation, key: some StringProtocol) {
            var values: [String: Double] = [:]
            for part in key.split(separator: "_") {
                guard let start = part.firstIndex(where: { $0 == "+" || $0 == "-" || $0.isNumber }),
                      let value = Double(part[start...]) else { return nil }
                values[String(part[..<start])] = value
            }
            guard let dr = values["dr"], let h = values["h"], let s = values["s"], let c = values["c"],
                  let wc = values["wc"], let mg = values["mg"], let ev = values["ev"] else { return nil }
            self.init(
                simulation: simulation, dynamicRange: Int(dr), highlight: h, shadow: s, color: Int(c),
                warmCool: Int(wc),
                magentaGreen: Int(mg), exposure: ev,
            )
        }
    }

    /// Base Looks baked from the firmware model: Redlamp's scene light through the model into a
    /// scene-referred table, which takes the place of Redlamp's tone curve.
    public enum FirmwareLook {
        /// Bumped when the bake changes: 2, black and white at DR200 and DR400 takes PROVIA's
        /// change in tone gain; 3, Redlamp's corrections (`black`, `corrections`).
        public static let bakeVersion = 3
        public static let tableSize = 33
        /// Stops added to Redlamp's scene light before the model: the model expects a raw
        /// developer's linear output, and Redlamp's scene light is scaled differently. Swept with
        /// `profile --evaluate --firmware-exposure` on the Standard pairs at process 19, it's where
        /// the median photo needs no more exposure to match the camera's midtones.
        public static let exposure = 0.6

        public static func id(_ settings: FirmwareLookSettings) -> String {
            let settings = settings.clamped
            return BaseLookReference.firmwareIDPrefix + "\(settings.simulation.rawValue)/\(settings.key)"
        }

        public static func name(_ settings: FirmwareLookSettings) -> String {
            "\(settings.simulation.name) · Firmware Model"
        }

        /// The settings a firmware look's reference was baked from.
        public static func settings(for reference: BaseLookReference) -> FirmwareLookSettings? {
            guard reference.isFirmwareModel else { return nil }
            let path = reference.id.dropFirst(BaseLookReference.firmwareIDPrefix.count).split(separator: "/")
            guard path.count == 2, let simulation = FirmwareSimulation(rawValue: String(path[0])) else { return nil }
            return FirmwareLookSettings(simulation: simulation, key: path[1])
        }

        /// The look, baked once per model and settings.
        public static func definition(_ settings: FirmwareLookSettings, model: FirmwareFilmModel) throws
            -> BaseLookDefinition {
            let settings = settings.clamped
            let key = "\(model.source)#\(id(settings))"
            if let cached = cache.value(key) {
                return cached
            }
            let definition = try BaseLookDefinition(
                id: id(settings), version: bakeVersion, name: name(settings), parameters: .identity,
                table: table(settings, model: model),
            )
            cache.store(definition, key)
            return definition
        }

        /// The look as recipes embed it, naming its slot when it has one.
        public static func package(
            _ settings: FirmwareLookSettings,
            model: FirmwareFilmModel,
        ) throws -> BaseLookPackage {
            let look = try definition(settings, model: model)
            return BaseLookPackage(
                id: look.id, version: look.version, name: look.name,
                summary: "Baked from the firmware model, an experiment; it stays on this Mac",
                slot: settings.simulation.slot?.rawValue, parameters: look.parameters, table: look.table,
            )
        }

        /// Each point's scene light in linear Rec.709, below zero clipped and the exposure added,
        /// through the model and Redlamp's corrections to it; its display sRGB back to display
        /// Rec.2020 with the sRGB transfer. `corrected: false` leaves the corrections out.
        static func table(
            _ settings: FirmwareLookSettings,
            model: FirmwareFilmModel,
            size: Int = tableSize,
            corrected: Bool = true,
        ) throws -> LookTable {
            let rendering = try model.rendering(
                settings.simulation.modelName, color: settings.color, dr: settings.dynamicRange,
                highlight: settings.highlight, shadow: settings.shadow, warmCool: Double(settings.warmCool),
                magentaGreen: Double(settings.magentaGreen),
            )
            let gain = exp2(settings.exposure)
            let correction = corrected ? corrections[settings.simulation] : nil
            let black = corrected ? Self.black : 0
            let slices = parallelMap(size) { b in
                var slice = [Float]()
                slice.reserveCapacity(size * size * 3)
                for g in 0 ..< size {
                    for r in 0 ..< size {
                        let encoded = SIMD3<Float>(Float(r), Float(g), Float(b)) / Float(size - 1)
                        let out = point(
                            SIMD3<Double>(SceneLogEncoding.decode(encoded)),
                            gain: gain,
                            black: black,
                            rendering: rendering,
                            correction: correction,
                        )
                        slice += [Float(out.x), Float(out.y), Float(out.z)]
                    }
                }
                return slice
            }
            return try LookTable(size: size, space: .sceneLog, floats: slices.flatMap(\.self))
        }

        static func point(
            _ scene: SIMD3<Double>,
            gain: Double,
            black: Double = 0,
            rendering: FirmwareFilmModel.Rendering,
            correction: OutputCorrection? = nil,
        ) -> SIMD3<Double> {
            var linear = simd_max(ColorMatrices.rec2020ToSRGB * scene, .zero) * gain
            let luminance = simd_dot(linear, OutputCorrection.luma)
            if black > 0, luminance > 0 {
                linear *= max(luminance - black, 0) / luminance
            }
            let display = rendering(linear)
            var light = SIMD3(SRGB.decode(display.x), SRGB.decode(display.y), SRGB.decode(display.z))
            if let correction {
                light = correction(light)
            }
            let wide = simd_max(ColorMatrices.sRGBToRec2020 * light, .zero)
            return SIMD3(SRGB.encode(wide.x), SRGB.encode(wide.y), SRGB.encode(wide.z))
        }

        /// Redlamp's correction to one simulation's output: OKLab lightness L shifted by the sum of
        /// `lightness[k - 1]` hundredths of sin(kπL) for k from 1 to 4, which leaves black and white
        /// and bends smoothly between, and chroma changed by `chroma` percent.
        struct OutputCorrection: Sendable {
            static let luma = SIMD3<Double>(Luma.rec709)

            var lightness: [Double]
            var chroma: Double

            /// Linear sRGB in and out, within 0...1.
            func callAsFunction(_ linear: SIMD3<Double>) -> SIMD3<Double> {
                var lab = OKLab.fromLinearSRGB(simd_max(linear, .zero))
                let l = min(max(lab.x, 0), 1)
                for (k, amount) in lightness.enumerated() {
                    lab.x += amount / 100 * sin(Double(k + 1) * .pi * l)
                }
                lab.y *= 1 + chroma / 100
                lab.z *= 1 + chroma / 100
                return simd_clamp(OKLab.toLinearSRGB(lab), .zero, SIMD3(repeating: 1))
            }
        }

        /// Subtracted from the model's input luminance, keeping its chromaticity: the cameras'
        /// shadows are deeper than the model's in every simulation. Fitted with `corrections`.
        static let black = 0.005

        /// Redlamp's corrections to the model's output, fitted per simulation on a donated set of
        /// 13 Fujifilm X-E5 raws with the camera's own JPEG of each in every simulation, at its
        /// own D-Range (DR100, 200 and 400) and 5500 K: least squares on the OKLab distance to the
        /// camera's JPEG at the profiler's flat points, each frame's exposure matched to the
        /// camera's midtones, with the input at `exposure` and `black` taken out, then rounded to
        /// two significant digits. Held out by leaving each frame out in turn, with `black` the
        /// mean over the simulations goes from 1.73 to 1.51 (OKLab × 100), and Nostalgic Neg's,
        /// whose shadows the camera renders deeper and whose colours less saturated, from 3.4 to 2.3.
        static let corrections: [FirmwareSimulation: OutputCorrection] = [
            .standard: .init(lightness: [-0.48, -0.79, -0.4, -1.2], chroma: -0.67),
            .vividSlide: .init(lightness: [0.34, 0.44, 0.32, -1.1], chroma: 2.7),
            .softSlide: .init(lightness: [-0.55, -0.85, -0.42, -1.2], chroma: 2.7),
            .chrome: .init(lightness: [-0.18, 0.27, 0.018, -1.4], chroma: 1),
            .negativeHigh: .init(lightness: [0.082, 0.18, 0.14, -1.3], chroma: -4.4),
            .negativeStandard: .init(lightness: [-0.11, 0.019, -0.042, -1.3], chroma: -4.5),
            .negativeClassic: .init(lightness: [-1.2, -0.34, -0.79, -0.73], chroma: 0.17),
            .negativeNostalgic: .init(lightness: [-2.9, -4.1, -1.1, -0.28], chroma: -23),
            .cinema: .init(lightness: [-0.51, -0.97, -0.44, -1.1], chroma: -2.8),
            .bleach: .init(lightness: [-1.2, -1, -0.21, -1.2], chroma: -2.6),
            .monochrome: .init(lightness: [-0.47, -0.87, -0.33, -1.3], chroma: 0),
            .monochromeYellow: .init(lightness: [-0.21, -0.64, -0.23, -1.2], chroma: 0),
            .monochromeRed: .init(lightness: [-0.071, -0.46, -0.34, -1.1], chroma: 0),
            .monochromeGreen: .init(lightness: [-0.63, -1, -0.31, -1.3], chroma: 0),
            .sepia: .init(lightness: [-0.41, -0.79, -0.31, -1.3], chroma: 25),
            .acros: .init(lightness: [-0.5, -0.88, -0.27, -1], chroma: 0),
            .acrosYellow: .init(lightness: [-0.34, -0.72, -0.24, -0.92], chroma: 0),
            .acrosRed: .init(lightness: [-0.094, -0.58, -0.38, -0.93], chroma: 0),
            .acrosGreen: .init(lightness: [-0.57, -1.1, -0.22, -0.97], chroma: 0),
            .realaAce: .init(lightness: [1.4, 0.52, 2.1, 0.86], chroma: -0.69),
        ]

        private static let cache = DefinitionCache()

        /// `body(0 ..< count)` on every core, results in order.
        private static func parallelMap<T>(_ count: Int, _ body: @Sendable (Int) -> T) -> [T] {
            let results = UnsafeMutableBufferPointer<T?>.allocate(capacity: count)
            results.initialize(repeating: nil)
            defer { results.deallocate() }
            // Each iteration writes only its own slot.
            nonisolated(unsafe) let slots = results
            DispatchQueue.concurrentPerform(iterations: count) { slots[$0] = body($0) }
            return results.map { $0! }
        }
    }

    /// The second of the inner key's three salt pieces (`FirmwareKeySaltA`).
    enum FirmwareKeySaltB {
        static let bytes: [UInt8] = [0x3E, 0xD7, 0x05, 0x8A, 0x61, 0xF9, 0x2B, 0x94, 0x0E, 0x77, 0xBC]
    }

    private final class DefinitionCache: @unchecked Sendable {
        private let lock = NSLock()
        private var definitions: [String: BaseLookDefinition] = [:]

        func value(_ key: String) -> BaseLookDefinition? {
            lock.lock()
            defer { lock.unlock() }
            return definitions[key]
        }

        func store(_ definition: BaseLookDefinition, _ key: String) {
            lock.lock()
            defer { lock.unlock() }
            definitions[key] = definition
        }
    }
#endif
