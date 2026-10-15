import Foundation

/// Camera Raw settings: a photo's develop settings or a preset's, by the names Adobe's `crs` namespace
/// gives them (ExifTool's table of `crs` tags lists them), read alike from XMP (`init?(xmp:)`) and from
/// the Lua a Lightroom Classic catalog keeps (`init(lua:)`). Simple values are kept as text, as XMP
/// writes them, and read as numbers and flags from it. A structure keeps all its fields, and an array of
/// structures each structure in its order, to whatever depth the settings go: a mask group's
/// corrections, each with its masks, each mask with its own fields, lists and masks. A structure's
/// fields are settings of their own, read with the same accessors, so a profile's own name or process
/// version never reads as the photo's.
public struct CameraRawSettings: Sendable, Hashable {
    public static let namespace = "http://ns.adobe.com/camera-raw-settings/1.0/"

    public enum Value: Sendable, Hashable {
        /// A simple value, or a language alternative's default text.
        case text(String)
        /// An array of simple values, such as a curve's `x, y` points.
        case list([String])
        /// A structure's fields, such as a profile's `Name`, `Amount` and `Parameters`.
        case structure(CameraRawSettings)
        /// An array of structures in its order, such as a mask group's corrections.
        case structures([CameraRawSettings])
    }

    /// The settings, or a structure's fields, by name.
    public internal(set) var values: [String: Value] = [:]
    /// Whether the packet also describes a photo: TIFF, Exif or Exif auxiliary properties, which a
    /// photo's sidecar carries and a preset never does.
    var describesPhoto = false

    public init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    public subscript(name: String) -> Value? {
        values[name]
    }

    public func text(_ name: String) -> String? {
        if case let .text(text) = values[name] {
            return text
        }
        return nil
    }

    public func number(_ name: String) -> Double? {
        guard let text = text(name), let value = Self.number(in: text[...]) else { return nil }
        return value.isFinite ? value : nil
    }

    /// A simple value with no text, as Lightroom writes a field it leaves unset
    /// (`crs:CameraModelRestriction=""`).
    public func isBlank(_ name: String) -> Bool {
        text(name)?.unicodeScalars.allSatisfy(\.properties.isWhitespace) == true
    }

    /// `True` and `False` in any case, or a number, which is on unless it is zero.
    public func flag(_ name: String) -> Bool? {
        guard let text = text(name) else { return nil }
        if Self.text(text, is: "true") {
            return true
        }
        return Self.text(text, is: "false") ? false : number(name).map { $0 != 0 }
    }

    /// Whether `text` is the lowercase ASCII `word` in any case.
    static func text(_ text: String, is word: String) -> Bool {
        text.utf8.elementsEqual(word.utf8) { $0 | 0x20 == $1 }
    }

    /// The number `text` holds, white space around it aside. Settings are read on every core at once, and
    /// Foundation's character sets serialise the threads that use them, so white space is told by Unicode's
    /// own properties.
    static func number(in text: Substring) -> Double? {
        if let value = Double(text) {
            return value
        }
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace })
        else { return nil }
        return Double(Substring(scalars[first ... last]))
    }

    /// An array of simple values in its order, such as a curve's points (`"0, 0"`) or a brush's dabs.
    public func list(_ name: String) -> [String]? {
        if case let .list(items) = values[name] {
            return items
        }
        return nil
    }

    /// A structure's fields, such as the profile's (`Look`) or its `Parameters`. An empty list reads as an
    /// empty structure, since Lua writes both as `{}`.
    public func structure(_ name: String) -> CameraRawSettings? {
        switch values[name] {
        case let .structure(fields): fields
        case let .list(items) where items.isEmpty: CameraRawSettings()
        default: nil
        }
    }

    /// An array of structures in its order, such as a mask group's corrections
    /// (`MaskGroupBasedCorrections`), a correction's masks (`CorrectionMasks`) or the spots
    /// (`RetouchAreas`). An empty list reads as no structures, since XMP and Lua write both alike.
    public func structures(_ name: String) -> [CameraRawSettings]? {
        switch values[name] {
        case let .structures(items): items
        case let .list(items) where items.isEmpty: []
        default: nil
        }
    }

    /// The simple values numbered from 0 under `name`, as Camera Raw writes Upright's guides
    /// (`UprightFourSegments_0` …) and its solved transform (`UprightTransform_0` …): no more than the
    /// count beside them says (`UprightFourSegmentsCount`), and up to the first that's missing.
    public func numbered(_ name: String) -> [String] {
        let count = number(name + "Count").map { Int(min(max($0, 0), Double(values.count))) }
        var items: [String] = []
        while count.map({ items.count < $0 }) ?? true, let item = text("\(name)_\(items.count)") {
            items.append(item)
        }
        return items
    }
}
