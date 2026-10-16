import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampUI

/// Borders on the canvas (TON-53): tools see the photo, not its border, and the views that judge
/// the photo alone leave the border out.
@MainActor
struct BorderEditorTests {
    private func openModel() async throws -> EditorModel {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let engine = StubEngine()
        engine.pixelSize = PixelSize(width: 600, height: 400)
        let model = EditorModel(engine: engine)
        model.select(folder.appending(path: "IMG_0001.ARW"))
        for _ in 0 ..< 200 where model.info == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(model.info != nil)
        return model
    }

    /// An even white border of 10% of the long side: a 720 × 520 canvas around the 600 × 400 photo.
    private func addBorder(_ model: EditorModel) {
        model.setValue(.borderStyle, Double(BorderStyle.plain.rawValue))
        model.setValue(.borderSize, 10)
    }

    @Test func `a point in the border is on no photo point, one inside maps through the border`() async throws {
        let model = try await openModel()
        addBorder(model)
        #expect(model.imagePoint(forCanvas: CGPoint(x: 0.02, y: 0.5)) == nil)
        #expect(model.framePoint(forCanvas: CGPoint(x: 0.5, y: 0.98)) == nil)
        let centre = try #require(model.imagePoint(forCanvas: CGPoint(x: 0.5, y: 0.5)))
        #expect(abs(centre.x - 0.5) < 1e-9 && abs(centre.y - 0.5) < 1e-9)
        // The photo's left edge, 60 of 720 pixels in.
        let edge = try #require(model.framePoint(forCanvas: CGPoint(x: 60.0 / 720, y: 0.5)))
        #expect(abs(edge.x) < 1e-9)
    }

    @Test func `the overlays draw on the photo's rect inside the border`() async throws {
        let model = try await openModel()
        addBorder(model)
        let border = try #require(model.canvasBorder)
        #expect(border.canvasSize == PixelSize(width: 720, height: 520))
        model.canvas.imageSize = border.canvasSize
        let canvasRect = model.canvas.imageRect(in: CGSize(width: 720, height: 520))
        let photo = model.photoRect(in: CGSize(width: 720, height: 520))
        #expect(abs(photo.width / canvasRect.width - 600.0 / 720) < 1e-6)
        #expect(abs((photo.minX - canvasRect.minX) / canvasRect.width - 60.0 / 720) < 1e-6)
    }

    @Test func `the crop tool and the colour-assessment view show the photo without its border`() async throws {
        let model = try await openModel()
        addBorder(model)
        #expect(model.canvasBorder?.hasBorder == true)
        model.activeTool = .crop
        #expect(model.canvasBorder?.hasBorder == false)
        model.activeTool = .edit
        model.colorAssessment = true
        #expect(model.canvasBorder?.hasBorder == false)
        #expect(model.framePoint(forCanvas: CGPoint(x: 0.01, y: 0.5)) != nil)
    }

    @Test func `the Before view carries the After's border, so both panes are the same size`() {
        var after = EditRecipe()
        after[.borderStyle] = Double(BorderStyle.plain.rawValue)
        after[.borderShape] = Double(BorderShape.square.rawValue)
        let before = EditRecipe().withGeometry(of: after)
        let size = PixelSize(width: 600, height: 400)
        #expect(before.borderedSize(imageSize: size) == after.borderedSize(imageSize: size))
    }
}
