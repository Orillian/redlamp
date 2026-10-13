import Foundation
import RedlampColor
import RedlampEngineAPI
import simd

/// The firmware model's simulations. Those Redlamp has a film slot for go by the slot's name;
/// the others, which only the prototype offers, by the model's.
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

    /// The slot recipe cards name it by; nil for the prototype's own.
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
        settings.warmCool = toning ? min(max(warmCool, Self.toningRange.lowerBound), Self.toningRange.upperBound) : 0
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
            simulation: simulation, dynamicRange: Int(dr), highlight: h, shadow: s, color: Int(c), warmCool: Int(wc),
            magentaGreen: Int(mg), exposure: ev,
        )
    }
}

/// Base Looks baked from the firmware model: Redlamp's scene light through the model into a
/// scene-referred table, which takes the place of Redlamp's tone curve.
public enum FirmwareLook {
    /// Bumped when the bake changes.
    public static let bakeVersion = 1
    public static let tableSize = 33
    /// Stops added to Redlamp's scene light before the model: the model expects a raw
    /// developer's linear output, and Redlamp's scene light is scaled differently.
    public static let exposure = 0.0

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
        let key = "\(model.folder.path)#\(id(settings))"
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
    public static func package(_ settings: FirmwareLookSettings, model: FirmwareFilmModel) throws -> BaseLookPackage {
        let look = try definition(settings, model: model)
        return BaseLookPackage(
            id: look.id, version: look.version, name: look.name,
            summary: "Baked from the firmware-derived model (prototype); it stays on this Mac",
            slot: settings.simulation.slot?.rawValue, parameters: look.parameters, table: look.table,
        )
    }

    /// Each point's scene light in linear Rec.709, below zero clipped and the exposure added,
    /// through the model; its display sRGB back to display Rec.2020 with the sRGB transfer.
    static func table(_ settings: FirmwareLookSettings, model: FirmwareFilmModel, size: Int = tableSize) throws
        -> LookTable {
        let rendering = try model.rendering(
            settings.simulation.modelName, color: settings.color, dr: settings.dynamicRange,
            highlight: settings.highlight, shadow: settings.shadow, warmCool: Double(settings.warmCool),
            magentaGreen: Double(settings.magentaGreen),
        )
        let gain = exp2(settings.exposure)
        let slices = parallelMap(size) { b in
            var slice = [Float]()
            slice.reserveCapacity(size * size * 3)
            for g in 0 ..< size {
                for r in 0 ..< size {
                    let encoded = SIMD3<Float>(Float(r), Float(g), Float(b)) / Float(size - 1)
                    let out = point(SIMD3<Double>(SceneLogEncoding.decode(encoded)), gain: gain, rendering: rendering)
                    slice += [Float(out.x), Float(out.y), Float(out.z)]
                }
            }
            return slice
        }
        return try LookTable(size: size, space: .sceneLog, floats: slices.flatMap(\.self))
    }

    static func point(_ scene: SIMD3<Double>, gain: Double, rendering: FirmwareFilmModel.Rendering) -> SIMD3<Double> {
        let linear = simd_max(ColorMatrices.rec2020ToSRGB * scene, .zero) * gain
        let display = rendering(linear)
        let light = SIMD3(SRGB.decode(display.x), SRGB.decode(display.y), SRGB.decode(display.z))
        let wide = simd_max(ColorMatrices.sRGBToRec2020 * light, .zero)
        return SIMD3(SRGB.encode(wide.x), SRGB.encode(wide.y), SRGB.encode(wide.z))
    }

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
