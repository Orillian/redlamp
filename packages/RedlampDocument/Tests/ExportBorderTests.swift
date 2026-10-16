import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampDocument

/// Borders at export (EDT-35): as edited, none, or a Borders recipe's on every photo, with sizes
/// that include the border.
struct ExportBorderTests {
    private let photo = PixelSize(width: 6000, height: 4000)
    private let url = URL(fileURLWithPath: "/photos/IMG_0001.ARW")

    private var white4x5: ExportBorder {
        ExportBorder(recipeID: "redlamp/border/white-4x5", name: "White 4:5", values: [
            .borderStyle: Double(BorderStyle.plain.rawValue), .borderShape: Double(BorderShape.fourByFive.rawValue),
            .borderOrientation: Double(BorderOrientation.portrait.rawValue), .borderSize: 0,
            .grainAmount: 40,
        ])
    }

    @Test func `a long edge is the bordered file's`() {
        var settings = ExportSettings()
        settings.sizing = ExportSizing(mode: .longEdge)
        settings.sizing.longEdge = 1350
        settings.border = white4x5
        let request = settings.stillRequest(recipe: EditRecipe(), source: url, size: photo)
        #expect(request.recipe[.borderStyle] == Double(BorderStyle.plain.rawValue))
        // 6000 × 7500 on a 4:5 canvas, fitted to a 1350 long edge: 1080 × 1350.
        let canvas = request.recipe.borderedSize(imageSize: photo)
        #expect(canvas == PixelSize(width: 6000, height: 7500))
        #expect(settings.sizing.resolve(settings.sizingSource(recipe: EditRecipe(), size: photo)) == PixelSize(
            width: 1080,
            height: 1350,
        ))
    }

    @Test func `a recipe's border takes the place of the photo's own, and nothing else`() {
        var edit = EditRecipe()
        edit[.borderStyle] = Double(BorderStyle.film35.rawValue)
        edit[.grainAmount] = 10
        let exported = white4x5.apply(to: edit)
        #expect(exported[.borderStyle] == Double(BorderStyle.plain.rawValue))
        #expect(exported[.grainAmount] == 10, "the recipe's other settings aren't the border's")
    }

    @Test func `none leaves the border out`() {
        var edit = EditRecipe()
        edit[.borderStyle] = Double(BorderStyle.plain.rawValue)
        var settings = ExportSettings()
        settings.border = .none
        let request = settings.stillRequest(recipe: edit, source: url, size: photo)
        #expect(!request.recipe.borderLayout(imageSize: photo).hasBorder)
    }

    @Test func `presets keep their border, and older presets export as edited`() throws {
        var settings = ExportSettings()
        settings.border = white4x5
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(ExportSettings.self, from: data).border == white4x5)
        let older = try JSONDecoder().decode(ExportSettings.self, from: Data(#"{"format":"jpeg"}"#.utf8))
        #expect(older.border == .asEdited)
    }
}
