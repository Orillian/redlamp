import AppKit
import RedlampRecipes

/// Looks' icons as images for lists, menus and cards, drawn once per size.
@MainActor
enum LookIconImage {
    private struct Key: Hashable {
        var icon: LookIcon
        var points: CGFloat
    }

    private static var cache: [Key: NSImage] = [:]

    /// The icon of a bundled recipe or Base Look, by id.
    static func image(for id: String, points: CGFloat) -> NSImage? {
        LookIcons.icon(forID: id).flatMap { image($0, points: points) }
    }

    /// A recipe's icon, or its Base Look's.
    static func image(for recipe: Recipe, points: CGFloat) -> NSImage? {
        LookIcons.icon(for: recipe).flatMap { image($0, points: points) }
    }

    static func image(for look: FilmLookDefinition, points: CGFloat) -> NSImage? {
        image(.film(look.icon), points: points)
    }

    static func image(_ icon: LookIcon, points: CGFloat) -> NSImage? {
        let key = Key(icon: icon, points: points)
        if let cached = cache[key] {
            return cached
        }
        guard let drawn = icon.image(pixels: Int(points * 2)) else { return nil }
        let image = NSImage(cgImage: drawn, size: NSSize(width: points, height: points))
        cache[key] = image
        return image
    }
}
