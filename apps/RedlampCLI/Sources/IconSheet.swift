import CoreGraphics
import CoreText
import Foundation
import RedlampRecipes

/// `redlamp recipe icons`: every look icon at the sizes the app shows it, on the panels' dark and light
/// greys, in one image to review (`.cursor/skills/redlamp-look-icons/SKILL.md`). `--readme` also writes
/// the film icons the README and the site show, `docs/images/film/icon-<id>.png`.
enum IconSheet {
    /// Points: the Recipes panel's rows, the Base Look menu, the browser's tiles and the Film Looks
    /// window's cards. The smallest three are drawn at 1x too, as a display without Retina shows them.
    static let sizes: [CGFloat] = [16, 18, 22, 36]
    static let oneX: [CGFloat] = [16, 18, 22]
    /// `Palette.panelBackground` in the dark and light themes.
    static let backgrounds: [(grey: CGFloat, text: CGFloat)] = [(0.115, 0.9), (0.925, 0.12)]
    static let nameWidth: CGFloat = 230
    static let gap: CGFloat = 12
    static let rowHeight: CGFloat = 36 * 2 + gap

    static func run(_ context: RecipeCommands.Context) async throws {
        if context.arguments.has("--readme") {
            let folder = Repository.root.appendingPathComponent("docs/images/film")
            for look in FilmLookCatalog.looks {
                if let image = look.icon.image(pixels: 256) {
                    try ImageFile.write(image, to: folder.appendingPathComponent("icon-\(look.id).png"))
                }
            }
            print("wrote \(FilmLookCatalog.looks.count) icons into \(folder.path)")
        }
        let styles = context.arguments.has("--styles")
        let rows: [Row] = if styles {
            try await IconStyles.rows(renderer: context.renderer(), photo: context.arguments.value("--photo"))
        } else {
            LookIcons.all.map { entry in (entry.name, { entry.icon.image(pixels: $0) }) }
        }
        let name = styles ? "look-icon-styles.png" : "look-icons.png"
        let output = URL(fileURLWithPath: context.arguments.value("--output") ?? "build/icons/\(name)")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try ImageFile.write(sheet(rows), to: output)
        print("wrote \(output.path)")
    }

    /// A row's name, and its icon drawn at a number of pixels square.
    typealias Row = (name: String, image: (Int) -> CGImage?)

    /// One row per icon: its name, then for each background its 1x sizes and its 2x sizes, each drawn
    /// at its size in pixels.
    static func sheet(_ icons: [Row]) throws -> CGImage {
        let block = oneX.reduce(0, +) + sizes.map { $0 * 2 }.reduce(0, +) + CGFloat(oneX.count + sizes.count + 1) * gap
        let width = nameWidth + CGFloat(backgrounds.count) * block
        let height = CGFloat(icons.count) * rowHeight + gap
        guard let context = CGContext(
            data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ) else { throw CLIError(description: "couldn't make the icon sheet") }
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: nameWidth, height: height))
        for (b, background) in backgrounds.enumerated() {
            context.setFillColor(CGColor(gray: background.grey, alpha: 1))
            context.fill(CGRect(x: nameWidth + CGFloat(b) * block, y: 0, width: block, height: height))
        }
        context.interpolationQuality = .none
        for (r, entry) in icons.enumerated() {
            let top = height - CGFloat(r + 1) * rowHeight
            text(entry.name, at: CGPoint(x: gap, y: top + rowHeight / 2 - 5), grey: 0.9, context)
            for b in backgrounds.indices {
                var x = nameWidth + CGFloat(b) * block + gap
                for pixels in oneX + sizes.map({ $0 * 2 }) {
                    if let image = entry.image(Int(pixels)) {
                        context.draw(
                            image,
                            in: CGRect(x: x, y: top + (rowHeight - pixels) / 2, width: pixels, height: pixels),
                        )
                    }
                    x += pixels + gap
                }
            }
        }
        guard let image = context.makeImage() else { throw CLIError(description: "couldn't draw the icon sheet") }
        return image
    }

    private static func text(_ string: String, at point: CGPoint, grey: CGFloat, _ context: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, 13, nil) ?? CTFontCreateWithName(
            "Helvetica" as CFString,
            13,
            nil,
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: grey, alpha: 1),
        ]
        context.textPosition = point
        CTLineDraw(
            CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes)),
            context,
        )
    }
}
