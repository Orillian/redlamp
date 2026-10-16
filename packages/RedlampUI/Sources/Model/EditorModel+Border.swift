import Foundation
import RedlampEngineAPI

/// A colour of the Border panel, sRGB 0...255.
public struct BorderColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = BorderColor(red: 255, green: 255, blue: 255)
    /// A warm photographic paper.
    public static let paper = BorderColor(red: 245, green: 242, blue: 234)
    public static let grey = BorderColor(red: 128, green: 128, blue: 128)
    public static let black = BorderColor(red: 18, green: 18, blue: 18)
    public static let plastic = BorderColor(red: 58, green: 58, blue: 62)

    public static let swatches: [(String, BorderColor)] = [
        ("White", .white),
        ("Paper", .paper),
        ("Grey", .grey),
        ("Black", .black),
    ]
}

/// The Border panel (TON-53, TON-54): a border around the photo, the canvas growing to hold it.
public extension EditorModel {
    var borderStyle: BorderStyle {
        BorderStyle(rawValue: Int(value(.borderStyle).rounded())) ?? .none
    }

    /// The red, green and blue parameters of the border's colour, or of its keyline's.
    static func borderColorParameters(keyline: Bool) -> (ParameterID, ParameterID, ParameterID) {
        keyline ? (.borderKeylineRed, .borderKeylineGreen, .borderKeylineBlue) : (.borderRed, .borderGreen, .borderBlue)
    }

    func borderColor(keyline: Bool) -> BorderColor {
        let (red, green, blue) = Self.borderColorParameters(keyline: keyline)
        return BorderColor(red: value(red), green: value(green), blue: value(blue))
    }

    /// Chooses a style, as one step. A plastic slide mount starts dark grey when the colour is still
    /// the white every border starts with.
    func setBorderStyle(_ style: BorderStyle) {
        var next = recipe
        next[.borderStyle] = Double(style.rawValue)
        if style == .slideMountPlastic, borderColor(keyline: false) == .white {
            Self.write(.plastic, keyline: false, into: &next)
        }
        next.setPanel(.border, on: true)
        commit(next, .adjustment(.borderStyle), "Border: \(style.name)")
    }

    func setBorderShape(_ shape: BorderShape) {
        var next = recipe
        next[.borderShape] = Double(shape.rawValue)
        next.setPanel(.border, on: true)
        commit(next, .adjustment(.borderShape), "Border Shape: \(shape.name)")
    }

    func setBorderOrientation(_ orientation: BorderOrientation) {
        var next = recipe
        next[.borderOrientation] = Double(orientation.rawValue)
        next.setPanel(.border, on: true)
        commit(next, .adjustment(.borderOrientation), "Border Orientation: \(orientation.name)")
    }

    /// Sets the border's colour, or its keyline's, as one step.
    func setBorderColor(_ color: BorderColor, keyline: Bool) {
        var next = recipe
        Self.write(color, keyline: keyline, into: &next)
        next.setPanel(.border, on: true)
        let (red, _, _) = Self.borderColorParameters(keyline: keyline)
        commit(next, .adjustment(red), keyline ? "Keyline Color" : "Border Color")
    }

    private static func write(_ color: BorderColor, keyline: Bool, into edit: inout EditRecipe) {
        let (red, green, blue) = borderColorParameters(keyline: keyline)
        edit[red] = min(max(color.red.rounded(), 0), 255)
        edit[green] = min(max(color.green.rounded(), 0), 255)
        edit[blue] = min(max(color.blue.rounded(), 0), 255)
    }

    /// Crops to the frame's format (2:3 for 35 mm, square for an instant square), turned as the
    /// photo is, but for the instant mini, whose window is always upright.
    func cropToBorderFormat() {
        guard let aspect = borderStyle.formatAspect, let info else { return }
        let size = recipe.developedSize(imageSize: info.pixelSize)
        let portrait = borderStyle.formatIsPortrait || size.height > size.width
        guard let crop = portrait ? CustomCropAspect(width: aspect, height: 1) : CustomCropAspect(
            width: 1,
            height: aspect,
        )
        else { return }
        setCropAspect(.custom(crop))
    }

    /// Whether the edit has a frame drawn over the photo's edges (TON-25), which the Effects panel
    /// keeps showing for it.
    var hasFrameOverPhoto: Bool {
        value(.frameStyle) > 0.5
    }

    /// Takes the frame drawn over the photo's edges away and puts the nearest border around the
    /// photo in its place, as one step.
    func moveFrameToBorder() {
        guard let frame = FrameStyle(rawValue: Int(value(.frameStyle).rounded())), frame != .none else { return }
        var next = recipe
        next[.frameStyle] = 0
        next[.frameSize] = ParameterID.frameSize.spec.defaultValue
        for parameter in EditRecipe.borderParameters {
            next[parameter] = parameter.spec.defaultValue
        }
        switch frame {
        case .keyline:
            next[.borderStyle] = Double(BorderStyle.plain.rawValue)
            next[.borderSize] = 0.6
            Self.write(.black, keyline: false, into: &next)
        case .printBorder:
            next[.borderStyle] = Double(BorderStyle.plain.rawValue)
            next[.borderSize] = 3.5
            Self.write(.paper, keyline: false, into: &next)
        case .filmRebate:
            next[.borderStyle] = Double(BorderStyle.film35.rawValue)
        case .slideMount:
            next[.borderStyle] = Double(BorderStyle.slideMount.rawValue)
            Self.write(.paper, keyline: false, into: &next)
        case .none:
            break
        }
        next.setPanel(.border, on: true)
        commit(next, .adjustment(.borderStyle), "Move Frame to Border")
    }
}
