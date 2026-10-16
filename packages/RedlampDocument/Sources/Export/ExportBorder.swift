import Foundation
import RedlampEngineAPI

/// The border an export draws around each photo (EDT-35): the one its edit has, none for a lab or
/// a client, or a Borders recipe's on every photo, as an export plug-in adds one. A recipe's border
/// is kept in the settings, so a preset keeps drawing it when the recipe is gone.
public enum ExportBorder: Codable, Sendable, Hashable {
    case asEdited
    case none
    /// A border recipe's `border.…` settings, by key, in place of each photo's own.
    case recipe(id: String, name: String, values: [String: Double])

    public init(recipeID: String, name: String, values: [ParameterID: Double]) {
        self = .recipe(
            id: recipeID, name: name,
            values: Dictionary(uniqueKeysWithValues: values.filter { $0.key.rawValue.hasPrefix("border.") }
                .map { ($0.key.rawValue, $0.value) }),
        )
    }

    public var title: String {
        switch self {
        case .asEdited: "As Edited"
        case .none: "None"
        case let .recipe(_, name, _): name
        }
    }

    /// `edit` with this border in place of its own.
    public func apply(to edit: EditRecipe) -> EditRecipe {
        switch self {
        case .asEdited:
            return edit
        case .none:
            return edit.withoutBorder()
        case let .recipe(_, _, values):
            var bordered = edit
            for parameter in EditRecipe.borderParameters {
                bordered[parameter] = values[parameter.rawValue] ?? parameter.spec.defaultValue
            }
            bordered.setPanel(.border, on: true)
            return bordered
        }
    }
}
