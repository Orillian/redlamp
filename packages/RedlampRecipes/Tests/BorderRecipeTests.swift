import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// Borders kept apart from looks (TON-53): a Borders recipe holds only a border, a mood leaves the
/// border alone, and Amount never blends one choice into another.
struct BorderRecipeTests {
    private var bordered: EditRecipe {
        var edit = EditRecipe()
        edit[.borderStyle] = Double(BorderStyle.plain.rawValue)
        edit[.borderShape] = Double(BorderShape.fourByFive.rawValue)
        edit[.borderSize] = 3
        return edit
    }

    @Test func `the Borders folder's recipes hold only a border`() {
        let recipes = BorderRecipes.recipes
        #expect(recipes.count >= 15)
        for recipe in recipes {
            #expect(recipe.includes == [.border], "\(recipe.id) includes \(recipe.includes)")
            #expect(recipe.group == "Borders")
            #expect(recipe.isBorderOnly)
            #expect(recipe.settings[.borderStyle] > 0.5, "\(recipe.id) has no border")
        }
        #expect(Set(recipes.map(\.id)).count == recipes.count)
    }

    @Test func `no mood carries a frame or a border any more`() {
        for recipe in MoodLooks.recipes {
            #expect(recipe.settings[.frameStyle] < 0.5, "\(recipe.id) draws a frame")
            #expect(!recipe.includes.contains(.border), "\(recipe.id) includes the border")
        }
    }

    @Test func `applying a mood leaves the photo's border as it was`() throws {
        let mood = try #require(MoodLooks.recipes.first { $0.id.hasSuffix("summer-98") })
        let edit = mood.apply(to: bordered)
        for parameter in EditRecipe.borderParameters {
            #expect(edit[parameter] == bordered[parameter], "\(parameter)")
        }
    }

    @Test func `a Borders recipe leaves the look and its provenance alone`() throws {
        let mood = try #require(MoodLooks.recipes.first { $0.id.hasSuffix("lost-roll") })
        let looked = mood.apply(to: EditRecipe())
        let border = try #require(BorderRecipes.recipes.first { $0.id.hasSuffix("white-4x5") })
        let edit = border.apply(to: looked)
        #expect(edit[.borderStyle] == Double(BorderStyle.plain.rawValue))
        #expect(edit.baseLook == looked.baseLook)
        #expect(edit.appliedRecipe == looked.appliedRecipe)
        for parameter in ParameterID.allCases where !parameter.rawValue.hasPrefix("border.") {
            #expect(edit[parameter] == looked[parameter], "\(parameter)")
        }
    }

    @Test func `a border is the recipe's at any amount`() throws {
        let border = try #require(BorderRecipes.recipes.first { $0.id.hasSuffix("gallery-mat") })
        let edit = border.apply(to: EditRecipe(), amount: 30)
        #expect(edit[.borderSize] == border.settings[.borderSize])
        #expect(edit[.borderOffsetY] == border.settings[.borderOffsetY])
    }

    @Test func `a choice switches at half the amount instead of blending into another`() {
        let recipe = Recipe(
            id: "local/frame", name: "Frame", group: "My Recipes", includes: [.effects],
            settings: RecipeSettings(values: [.frameStyle: Double(FrameStyle.filmRebate.rawValue)]),
        )
        #expect(recipe.apply(to: EditRecipe(), amount: 50)[.frameStyle] == Double(FrameStyle.filmRebate.rawValue))
        #expect(recipe.apply(to: EditRecipe(), amount: 40)[.frameStyle] == 0)
    }

    @Test func `a new recipe leaves the border out unless it's ticked`() {
        #expect(!RecipeSettingGroup.captureDefaults.contains(.border))
        #expect(RecipeSettingGroup(parameter: .borderStyle) == .border)
        #expect(RecipeSettingGroup(parameter: .frameStyle) == .effects)
    }
}
