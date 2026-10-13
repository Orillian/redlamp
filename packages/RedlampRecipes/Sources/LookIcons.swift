import CoreGraphics
import Foundation

/// A look's small icon, as lists, menus and cards show it beside the look's name. Each kind is
/// Redlamp's own drawing on a 64-unit grid (`.cursor/skills/redlamp-look-icons/SKILL.md`).
public enum LookIcon: Sendable, Hashable {
    /// A film look's canister, slide mount, reel or print.
    case film(FilmIcon)

    /// The icon at `pixels` square, transparent around the shape.
    public func image(pixels: Int) -> CGImage? {
        switch self {
        case let .film(icon): icon.image(pixels: pixels)
        }
    }
}

/// Which icon a recipe or Base Look shows.
public enum LookIcons {
    /// The icon of a bundled recipe or Base Look, by id.
    public static func icon(forID id: String) -> LookIcon? {
        FilmLookCatalog.look(forBundledID: id).map { .film($0.icon) }
    }

    /// A recipe's own icon, or else its Base Look's: a mood, or a recipe of your own, built on a film
    /// look shows that film's icon.
    public static func icon(for recipe: Recipe) -> LookIcon? {
        icon(forID: recipe.id) ?? recipe.baseLook.flatMap { icon(forID: $0.id) }
    }

    /// Every icon there is, with the id of what shows it, for a review sheet.
    public static var all: [(id: String, name: String, icon: LookIcon)] {
        FilmLookCatalog.looks.map { ($0.id, $0.name, .film($0.icon)) }
    }
}
