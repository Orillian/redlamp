import CoreGraphics
import Foundation
import RedlampRecipes

/// `redlamp recipe icons --styles`: three styles of icon for looks that aren't film stocks, a few
/// looks each, drawn for the owner to choose one (UX-45). Not used by the app: the chosen style
/// becomes a kind of `LookIcon`.
enum IconStyles {
    static func rows(renderer: RecipeRenderer, photo: String?) async throws -> [IconSheet.Row] {
        var rows: [IconSheet.Row] = []
        let marks: [(String, String, Mark)] = [
            ("Golden Leak", "portra-400-overexposed", .leak(warm: true)),
            ("Lost Roll", "gold-200", .dust),
            ("Summer '98", "ultramax-400", .border),
            ("Night Glow", "cinestill-800t", .glow),
        ]
        for (name, film, mark) in marks {
            guard let icon = FilmLookCatalog.look(film)?.icon else { continue }
            rows.append(("A · \(name): its film with the mood's mark", { pixels in
                draw(pixels) { context, size in
                    if let film = icon.image(pixels: pixels) {
                        context.draw(film, in: CGRect(x: 0, y: 0, width: size, height: size))
                    }
                    mark.draw(context, size)
                }
            }))
        }
        let scenes: [(String, Scene)] = [
            ("Golden Hour", .sun), ("Blue Hour", .lamp), ("Deep Blue Sky", .sky), ("Soft Skin", .portrait),
        ]
        for (name, scene) in scenes {
            rows.append(("B · \(name): an object for its scene", { pixels in
                draw(pixels) { context, size in scene.draw(context, size) }
            }))
        }
        let path = photo ?? Repository.root.appendingPathComponent("build/look-dev/Sony_ILCE-6700.ARW").path
        guard FileManager.default.fileExists(atPath: path) else {
            throw CLIError(description: "no photo for the chips at \(path) (mise run lookdev, or --photo <raw>)")
        }
        for slug in ["essentials/golden-hour", "night/blue-hour", "landscape/deep-sky", "portrait/soft-skin"] {
            guard let recipe = BuiltInRecipes.recipe(id: "\(RecipeNamespace.bundled)/\(slug)") else { continue }
            let rendered = try await renderer.render(recipe, image: URL(fileURLWithPath: path), maxLongEdge: 220)
            rows.append(("C · \(recipe.name): a chip of the look", { pixels in
                draw(pixels) { context, size in chip(rendered, context, size) }
            }))
        }
        return rows
    }

    /// A transparent square of `pixels`, drawn on a 64-unit grid as the film icons are.
    private static func draw(_ pixels: Int, _ body: (CGContext, CGFloat) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        body(context, CGFloat(pixels))
        return context.makeImage()
    }

    private static func colour(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    enum Mark {
        case leak(warm: Bool), dust, border, glow

        func draw(_ c: CGContext, _ size: CGFloat) {
            let u = size / 64
            switch self {
            case let .leak(warm):
                let tint = warm ? colour(1, 0.55, 0.15, 0.85) : colour(0.4, 0.6, 1, 0.85)
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [tint, colour(1, 0.55, 0.15, 0)] as CFArray, locations: [0, 1],
                ) {
                    c.drawRadialGradient(
                        gradient, startCenter: CGPoint(x: 60 * u, y: 60 * u), startRadius: 0,
                        endCenter: CGPoint(x: 60 * u, y: 60 * u), endRadius: 34 * u, options: [],
                    )
                }
            case .dust:
                c.setFillColor(colour(1, 1, 1, 0.9))
                for (x, y, r) in [(14.0, 48.0, 1.6), (30, 16, 1.2), (46, 52, 1.4), (22, 30, 1.0), (54, 24, 1.2)] {
                    c.fillEllipse(in: CGRect(x: x * u, y: y * u, width: r * 2 * u, height: r * 2 * u))
                }
                c.setStrokeColor(colour(1, 1, 1, 0.75))
                c.setLineWidth(max(u, 1))
                c.move(to: CGPoint(x: 20 * u, y: 62 * u))
                c.addLine(to: CGPoint(x: 28 * u, y: 2 * u))
                c.strokePath()
            case .border:
                c.setStrokeColor(colour(0.98, 0.97, 0.94))
                c.setLineWidth(5 * u)
                c.stroke(CGRect(x: 2.5 * u, y: 2.5 * u, width: 59 * u, height: 59 * u))
            case .glow:
                c.setStrokeColor(colour(1, 0.25, 0.15, 0.7))
                c.setLineWidth(4 * u)
                c.strokeEllipse(in: CGRect(x: 3 * u, y: 3 * u, width: 58 * u, height: 58 * u))
            }
        }
    }

    enum Scene {
        case sun, lamp, sky, portrait

        func draw(_ c: CGContext, _ size: CGFloat) {
            let u = size / 64
            let tile = CGPath(
                roundedRect: CGRect(x: 4 * u, y: 4 * u, width: 56 * u, height: 56 * u), cornerWidth: 10 * u,
                cornerHeight: 10 * u, transform: nil,
            )
            c.addPath(tile)
            c.clip()
            switch self {
            case .sun:
                c.setFillColor(colour(0.96, 0.62, 0.3))
                c.fill(CGRect(x: 0, y: 0, width: size, height: size))
                c.setFillColor(colour(1, 0.88, 0.55))
                c.fillEllipse(in: CGRect(x: 20 * u, y: 14 * u, width: 24 * u, height: 24 * u))
                c.setFillColor(colour(0.45, 0.25, 0.15))
                c.fill(CGRect(x: 0, y: 0, width: size, height: 24 * u))
            case .lamp:
                c.setFillColor(colour(0.12, 0.2, 0.42))
                c.fill(CGRect(x: 0, y: 0, width: size, height: size))
                c.setFillColor(colour(1, 0.8, 0.45, 0.35))
                c.fillEllipse(in: CGRect(x: 24 * u, y: 32 * u, width: 22 * u, height: 22 * u))
                c.setFillColor(colour(0.08, 0.1, 0.16))
                c.fill(CGRect(x: 32 * u, y: 4 * u, width: 3 * u, height: 40 * u))
                c.setFillColor(colour(1, 0.85, 0.55))
                c.fillEllipse(in: CGRect(x: 30 * u, y: 39 * u, width: 9 * u, height: 9 * u))
            case .sky:
                c.setFillColor(colour(0.2, 0.42, 0.78))
                c.fill(CGRect(x: 0, y: 0, width: size, height: size))
                c.setFillColor(colour(0.96, 0.97, 1))
                c.fillEllipse(in: CGRect(x: 14 * u, y: 38 * u, width: 18 * u, height: 9 * u))
                c.fillEllipse(in: CGRect(x: 24 * u, y: 40 * u, width: 16 * u, height: 10 * u))
                c.setFillColor(colour(0.25, 0.5, 0.28))
                c.move(to: CGPoint(x: 0, y: 22 * u))
                c.addLine(to: CGPoint(x: 22 * u, y: 32 * u))
                c.addLine(to: CGPoint(x: 40 * u, y: 24 * u))
                c.addLine(to: CGPoint(x: size, y: 30 * u))
                c.addLine(to: CGPoint(x: size, y: 0))
                c.addLine(to: CGPoint(x: 0, y: 0))
                c.fillPath()
            case .portrait:
                c.setFillColor(colour(0.93, 0.82, 0.74))
                c.fill(CGRect(x: 0, y: 0, width: size, height: size))
                c.setFillColor(colour(0.78, 0.58, 0.48))
                c.fillEllipse(in: CGRect(x: 23 * u, y: 28 * u, width: 18 * u, height: 20 * u))
                c.fillEllipse(in: CGRect(x: 12 * u, y: -10 * u, width: 40 * u, height: 34 * u))
            }
        }
    }

    /// The look rendered on a photo, cropped to a square with rounded corners.
    private static func chip(_ image: CGImage, _ c: CGContext, _ size: CGFloat) {
        let u = size / 64
        c.addPath(CGPath(
            roundedRect: CGRect(x: 4 * u, y: 4 * u, width: 56 * u, height: 56 * u), cornerWidth: 10 * u,
            cornerHeight: 10 * u, transform: nil,
        ))
        c.clip()
        let side = CGFloat(min(image.width, image.height))
        let crop = CGRect(
            x: (CGFloat(image.width) - side) / 2, y: (CGFloat(image.height) - side) / 2, width: side, height: side,
        )
        if let square = image.cropping(to: crop) {
            c.interpolationQuality = .high
            c.draw(square, in: CGRect(x: 4 * u, y: 4 * u, width: 56 * u, height: 56 * u))
        }
    }
}
