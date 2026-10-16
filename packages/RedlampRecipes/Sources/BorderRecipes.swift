import Foundation
import RedlampEngineAPI

/// The Borders folder (TON-53, TON-54): recipes that hold only a border, so they leave the look
/// alone and any look or mood leaves them alone.
public enum BorderRecipes {
    static let group = "Borders"

    private static func plain(
        _ shape: BorderShape, orientation: BorderOrientation = .portrait, size: Double,
        color: BorderColorValue = .white,
        _ extra: [ParameterID: Double] = [:],
    ) -> [ParameterID: Double] {
        var values: [ParameterID: Double] = [
            .borderStyle: Double(BorderStyle.plain.rawValue),
            .borderShape: Double(shape.rawValue),
            .borderOrientation: Double(orientation.rawValue),
            .borderSize: size,
        ]
        values.merge(color.values) { $1 }
        return values.merging(extra) { $1 }
    }

    private static func frame(_ style: BorderStyle, color: BorderColorValue = .white) -> [ParameterID: Double] {
        var values: [ParameterID: Double] = [.borderStyle: Double(style.rawValue)]
        if style.usesColor {
            values.merge(color.values) { $1 }
        }
        return values
    }

    /// The recipes, in the folder's order: shapes for posting, then mats, then film and instant frames.
    public static var recipes: [Recipe] {
        let entries: [(String, String, String, [ParameterID: Double])] = [
            (
                "white-4x5",
                "White 4:5",
                "A white border that fits any photo to a 4:5 portrait post",
                plain(.fourByFive, size: 3),
            ),
            (
                "black-4x5",
                "Black 4:5",
                "A black border that fits any photo to a 4:5 portrait post",
                plain(.fourByFive, size: 3, color: .black),
            ),
            (
                "white-3x4",
                "White 3:4",
                "A white border for a 3:4 portrait post, as the profile grid shows it",
                plain(.threeByFour, size: 3),
            ),
            (
                "white-square",
                "White Square",
                "A white border that fits any photo to a square",
                plain(.square, size: 3),
            ),
            (
                "black-square",
                "Black Square",
                "A black border that fits any photo to a square",
                plain(.square, size: 3, color: .black),
            ),
            (
                "story-9x16",
                "Story 9:16",
                "A white border for a full-screen story",
                plain(.nineBySixteen, size: 4),
            ),
            (
                "thin-white",
                "Thin White",
                "A thin white border, the same all round",
                plain(.even, size: 1.5),
            ),
            (
                "thin-black",
                "Thin Black",
                "A thin black border, the same all round",
                plain(.even, size: 1.5, color: .black),
            ),
            (
                "gallery-mat",
                "Gallery Mat",
                "A wide paper mat with a heavier bottom, as a framer cuts one",
                plain(.even, size: 9, color: .paper, [.borderOffsetY: 25]),
            ),
            (
                "gallery-mat-keyline",
                "Gallery Mat with Keyline",
                "A paper mat with a fine black line around the photo",
                plain(.even, size: 9, color: .paper, [
                    .borderOffsetY: 25, .borderKeylineWidth: 0.15, .borderKeylineGap: 1.2,
                ]),
            ),
            (
                "print-8x10",
                "Print 8×10",
                "A white margin around the photo on 8 × 10 paper, turned with the photo",
                plain(.fourByFive, orientation: .matchPhoto, size: 2),
            ),
            (
                "film-35",
                "35 mm Film",
                "The 35 mm frame with its rebate, sprocket holes and edge print",
                frame(.film35),
            ),
            (
                "medium-format",
                "Medium Format",
                "The 120 frame with its narrow rebate and edge print",
                frame(.mediumFormat),
            ),
            (
                "instant-square",
                "Instant Square",
                "An instant square card with its wide bottom",
                frame(.instantSquare, color: .card),
            ),
            ("instant-mini", "Instant Mini", "An instant mini card", frame(.instantMini, color: .card)),
            ("instant-wide", "Instant Wide", "An instant wide card", frame(.instantWide, color: .card)),
            ("slide-mount", "Slide Mount", "A card slide mount around the photo", frame(.slideMount, color: .paper)),
            (
                "filed-carrier",
                "Filed Carrier",
                "The rough black edge of a filed-out negative carrier, on white paper",
                frame(.filedCarrier),
            ),
        ]
        return entries.map { slug, name, summary, values in
            BuiltInRecipes.make(
                "border/\(slug)",
                name,
                group: group,
                summary: summary,
                tags: ["border"],
                values: values,
            )
        }
    }
}

/// A border recipe's colour, sRGB 0...255.
struct BorderColorValue {
    var red: Double
    var green: Double
    var blue: Double

    static let white = BorderColorValue(red: 255, green: 255, blue: 255)
    static let black = BorderColorValue(red: 18, green: 18, blue: 18)
    /// A warm photographic paper.
    static let paper = BorderColorValue(red: 245, green: 242, blue: 234)
    /// An instant print's card.
    static let card = BorderColorValue(red: 250, green: 250, blue: 246)

    var values: [ParameterID: Double] {
        [.borderRed: red, .borderGreen: green, .borderBlue: blue]
    }
}
