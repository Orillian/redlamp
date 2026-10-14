import AppKit
import RedlampDesign
import RedlampEngineAPI
import Testing
@_spi(Harness) @testable import RedlampUI

/// Red's, green's and blue's own point curves in the Tone Curve panel (TON-40).
@MainActor
struct ToneCurveChannelTests {
    private static let lifted = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.65), CurvePoint(x: 1, y: 1)]

    @Test func `each channel's curve is a step of its own, named for it`() {
        let model = EditorModel(engine: StubEngine())
        #expect(!model.isEdited(.toneCurve))
        model.setPointCurve(Self.lifted, channel: .red)
        model.setPointCurve(Self.lifted, channel: .blue)
        #expect(model.history.map(\.name) == ["Red Curve", "Blue Curve"])
        #expect(model.pointCurve(.blue) == Self.lifted && model.pointCurve == EditRecipe.linearPointCurve)
        #expect(model.isEdited(.toneCurve) && model.editedItems(.toneCurve).map(\.name) == ["Point Curve"])
        model.undo()
        #expect(model.pointCurve(.blue) == EditRecipe.linearPointCurve && model.pointCurve(.red) == Self.lifted)
    }

    @Test func `Linear straightens the chosen channel's curve alone`() {
        let model = EditorModel(engine: StubEngine())
        model.setPointCurve(Self.lifted, channel: .red)
        model.setPointCurve(Self.lifted, channel: .green)
        model.resetPointCurve(.red)
        #expect(model.history.last?.name == "Reset Red Curve")
        #expect(model.pointCurve(.red) == EditRecipe.linearPointCurve && model.pointCurve(.green) == Self.lifted)
    }

    @Test func `Reset Tone Curve straightens every channel's curve, in one step`() {
        let model = EditorModel(engine: StubEngine())
        model.setPointCurve(Self.lifted)
        model.setPointCurve(Self.lifted, channel: .green)
        let steps = model.history.count
        model.resetPanel(.toneCurve)
        #expect(CurveChannel.allCases.allSatisfy { model.pointCurve($0) == EditRecipe.linearPointCurve })
        #expect(model.history.count == steps + 1)
        model.undo()
        #expect(model.pointCurve == Self.lifted && model.pointCurve(.green) == Self.lifted)
    }

    @Test func `with a channel chosen, a typed Output moves that channel's point`() throws {
        let model = EditorModel(engine: StubEngine())
        model.setPointCurve(Self.lifted)
        let state = ToneCurveState()
        let view = PointValuesView(model: model, state: state)
        defer { withExtendedLifetime(view) {} }
        let output = try #require(allSubviews(of: view).compactMap { $0 as? ValueFieldView }.last)
        state.selectedPoint = 1
        state.channel = .red
        #expect(state.selectedPoint == nil, "another curve's point isn't selected")
        model.setPointCurve(
            [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.5), CurvePoint(x: 1, y: 1)], channel: .red,
        )
        state.selectedPoint = 1
        output.onCommit(204)
        #expect(abs(model.pointCurve(.red)[1].y - 0.8) < 1e-9)
        #expect(model.pointCurve == Self.lifted, "the RGB curve stays")
    }

    @Test func `the graph draws the chosen curve in its colour, and the other bent ones faint`() {
        var recipe = EditRecipe()
        recipe[curve: .red] = Self.lifted
        recipe[curve: .blue] = [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 1, y: 0.9)]
        let red = CurveGraphCurves(recipe, mode: .point, channel: .red)
        #expect(red.shown.color == CurveChannel.red.tint)
        #expect(abs(red.shown.samples[0] - 0) < 1e-9 && abs(red.shown.samples[255] - 1) < 1e-9)
        #expect(red.shown.samples[128] > 0.6, "red's own curve, lifted in the middle")
        #expect(red.faint.map(\.color) == [CurveChannel.blue.tint.opacity(0.4)], "blue's; green and RGB are straight")

        #expect(CurveGraphCurves(recipe, mode: .point, channel: .rgb).faint.count == 2)
        let parametric = CurveGraphCurves(recipe, mode: .parametric, channel: .red)
        #expect(parametric.shown.color == CurveChannel.rgb.tint && parametric.faint.isEmpty)
        recipe.pointCurve = Self.lifted
        let green = CurveGraphCurves(recipe, mode: .point, channel: .green)
        #expect(green.faint.map(\.color) == [CurveChannel.rgb, .red, .blue].map { $0.tint.opacity(0.4) })
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }
}
