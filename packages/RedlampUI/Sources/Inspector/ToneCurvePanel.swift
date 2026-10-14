import RedlampDesign
import RedlampEngineAPI
import SwiftUI

@_spi(Harness) public struct ToneCurvePanel: View {
    public init() {}

    enum Mode: String, CaseIterable {
        case parametric = "Parametric"
        case point = "Point"
    }

    @State private var mode: Mode = .parametric
    @State private var channel = CurveChannel.rgb

    public var body: some View {
        PanelSection(panel: .toneCurve) {
            ControlRow(label: "Curve") {
                ChoiceMenu("Curve", selection: $mode)
                    .controlSize(.small)
            }
            .padding(.bottom, 6)

            if mode == .point {
                ControlRow(label: "Channel") {
                    ChoiceMenu("Channel", selection: $channel)
                        .controlSize(.small)
                }
                .padding(.bottom, 6)
            }

            CurveEditor(mode: mode, channel: channel)
                .aspectRatio(1, contentMode: .fit)

            if mode == .parametric {
                SplitHandles()
                    .frame(height: 12)
                    .padding(.bottom, 4)
                SubsectionHeader(
                    title: "Region",
                    parameters: [.curveHighlights, .curveLights, .curveDarks, .curveShadows],
                )
                ParameterSlider(parameter: .curveHighlights)
                ParameterSlider(parameter: .curveLights)
                ParameterSlider(parameter: .curveDarks)
                ParameterSlider(parameter: .curveShadows)
            } else {
                PointCurvePresets(channel: channel).padding(.top, 6)
            }
        }
    }
}

/// The curve graph. In point mode, drag points of the chosen channel's curve, click to add,
/// double-click to remove.
struct CurveEditor: View {
    let mode: ToneCurvePanel.Mode
    let channel: CurveChannel

    @Environment(EditorModel.self) private var model
    @State private var dragIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, canvasSize in
                    drawBackground(context, size: canvasSize)
                    drawHistogram(context, size: canvasSize)
                    drawCurves(context, size: canvasSize)
                }
                if mode == .point {
                    ForEach(Array(model.pointCurve(channel).enumerated()), id: \.offset) { index, point in
                        CurveHandle(selected: dragIndex == index)
                            .position(point.location(in: size))
                            .onTapGesture(count: 2) { removePoint(index) }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(mode == .point ? pointGesture(size: size) : nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func pointGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let location = CGPoint(
                    x: min(max(gesture.location.x / size.width, 0), 1),
                    y: min(max(1 - gesture.location.y / size.height, 0), 1),
                )
                var points = model.pointCurve(channel).sorted { $0.x < $1.x }
                if dragIndex == nil {
                    model.beginEdit()
                    let start = CGPoint(
                        x: gesture.startLocation.x / size.width,
                        y: 1 - gesture.startLocation.y / size.height,
                    )
                    if let nearest = points.indices.min(by: {
                        hypot(points[$0].x - start.x, points[$0].y - start.y) < hypot(
                            points[$1].x - start.x,
                            points[$1].y - start.y,
                        )
                    }), hypot(points[nearest].x - start.x, points[nearest].y - start.y) < 0.05 {
                        dragIndex = nearest
                    } else {
                        let curve = ToneCurveMath.pointCurve(points)
                        points.append(CurvePoint(x: start.x, y: curve(start.x)))
                        points.sort { $0.x < $1.x }
                        dragIndex = points.firstIndex { abs($0.x - start.x) < 1e-9 }
                    }
                }
                guard let index = dragIndex else { return }
                let isEndpoint = index == 0 || index == points.count - 1
                let lower = index > 0 ? points[index - 1].x + 0.01 : 0
                let upper = index < points.count - 1 ? points[index + 1].x - 0.01 : 1
                let x = isEndpoint ? points[index].x : min(max(location.x, lower), upper)
                points[index] = CurvePoint(x: x, y: location.y)
                model.setPointCurve(points, channel: channel)
            }
            .onEnded { _ in
                dragIndex = nil
                model.endEdit(.toneCurve, channel.curveTitle)
            }
    }

    private func removePoint(_ index: Int) {
        var points = model.pointCurve(channel).sorted { $0.x < $1.x }
        guard index > 0, index < points.count - 1 else { return }
        points.remove(at: index)
        model.setPointCurve(points, channel: channel)
    }

    private func drawBackground(_ context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.well))
        var grid = Path()
        for step in 1 ..< 4 {
            let t = Double(step) / 4
            grid.move(to: CGPoint(x: t * size.width, y: 0))
            grid.addLine(to: CGPoint(x: t * size.width, y: size.height))
            grid.move(to: CGPoint(x: 0, y: t * size.height))
            grid.addLine(to: CGPoint(x: size.width, y: t * size.height))
        }
        context.stroke(grid, with: .color(Theme.divider), lineWidth: 1)
        var diagonal = Path()
        diagonal.move(to: CGPoint(x: 0, y: size.height))
        diagonal.addLine(to: CGPoint(x: size.width, y: 0))
        context.stroke(diagonal, with: .color(Theme.divider), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        if mode == .parametric {
            let splits = [
                model.value(.curveSplitShadows),
                model.value(.curveSplitMidtones),
                model.value(.curveSplitHighlights),
            ]
            var lines = Path()
            for split in splits {
                let x = split / 100 * size.width
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(lines, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
        }
    }

    private func drawHistogram(_ context: GraphicsContext, size: CGSize) {
        let shown = mode == .point ? channel : .rgb
        let bins = model.histogram.bins(shown)
        let peak = bins.dropFirst().dropLast().max() ?? 0
        guard peak > 0 else { return }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, count) in bins.enumerated() {
            let x = Double(index) / Double(bins.count - 1) * size.width
            path.addLine(to: CGPoint(
                x: x,
                y: size.height - min(sqrt(Double(count) / Double(peak)), 1) * size.height * 0.9,
            ))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        context.fill(path, with: .color(shown.histogramFill.color))
    }

    private func drawCurves(_ context: GraphicsContext, size: CGSize) {
        let curves = CurveGraphCurves(model.toneCurve, mode: mode, channel: channel)
        for curve in curves.faint {
            context.stroke(path(curve.samples, size: size), with: .color(curve.color.color), lineWidth: 1)
        }
        context.stroke(path(curves.shown.samples, size: size), with: .color(curves.shown.color.color), lineWidth: 1.5)
    }

    private func path(_ samples: [Double], size: CGSize) -> Path {
        var path = Path()
        for (index, value) in samples.enumerated() {
            let point = CGPoint(
                x: Double(index) / Double(samples.count - 1) * size.width, y: (1 - value) * size.height,
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// The curves a Tone Curve graph draws, the same in both panels: the one being edited (the RGB
/// curve with the parametric one in it, or a channel's own), and in point mode the other bent
/// curves, faint and without points.
struct CurveGraphCurves {
    struct Curve {
        let samples: [Double]
        let color: RGBA
    }

    let shown: Curve
    let faint: [Curve]

    init(_ recipe: EditRecipe, mode: ToneCurvePanel.Mode, channel: CurveChannel, count: Int = 256) {
        func samples(_ channel: CurveChannel) -> [Double] {
            if channel == .rgb {
                return ToneCurveMath.lut(for: recipe, count: count).map { Double($0) }
            }
            return ToneCurveMath.risingSamples(recipe[curve: channel], count: count)
        }
        let channel = mode == .point ? channel : .rgb
        shown = Curve(samples: samples(channel), color: channel.tint)
        var plain = recipe
        for color in CurveChannel.colors {
            plain[curve: color] = EditRecipe.linearPointCurve
        }
        var faint: [Curve] = []
        for other in CurveChannel.allCases where mode == .point && other != channel {
            let bent = other == .rgb
                ? !ToneCurveMath.isIdentity(plain) : recipe[curve: other] != EditRecipe.linearPointCurve
            if bent {
                faint.append(Curve(samples: samples(other), color: other.tint.opacity(0.4)))
            }
        }
        self.faint = faint
    }
}

extension CurveChannel {
    /// The curve's name in history and on its reset: the point curve, or a channel's own.
    var curveTitle: String {
        self == .rgb ? "Point Curve" : "\(name) Curve"
    }

    /// The colour a graph draws the curve in.
    var tint: RGBA {
        switch self {
        case .rgb: RGBA(white: 0.9)
        case .red: RGBA(red: 0.95, green: 0.35, blue: 0.35)
        case .green: RGBA(red: 0.4, green: 0.85, blue: 0.4)
        case .blue: RGBA(red: 0.4, green: 0.6, blue: 1)
        }
    }

    /// The histogram's fill behind the curve: the photo's luminance in white, a channel's own in its colour.
    var histogramFill: RGBA {
        self == .rgb ? RGBA(white: 1, alpha: 0.07) : tint.opacity(0.12)
    }
}

extension Histogram {
    /// The bins a graph draws behind `channel`'s curve: the luminance behind the RGB curve.
    func bins(_ channel: CurveChannel) -> [UInt32] {
        switch channel {
        case .rgb: luminance
        case .red: red
        case .green: green
        case .blue: blue
        }
    }
}

extension ToneCurveMath {
    /// `points` on their own at `count` evenly spaced inputs over 0...1, kept rising as the tables
    /// the kernel reads are.
    static func risingSamples(_ points: [CurvePoint], count: Int) -> [Double] {
        let curve = pointCurve(points)
        var previous = 0.0
        return (0 ..< count).map { index in
            previous = max(previous, min(max(curve(Double(index) / Double(count - 1)), 0), 1))
            return previous
        }
    }
}

/// A point curve to edit: drag a point, click to add one, double-click one to remove it. The ends
/// move only up and down.
struct PointCurveGraph: View {
    let points: [CurvePoint]
    let tint: Color
    let begin: () -> Void
    let change: ([CurvePoint]) -> Void
    let end: () -> Void
    @State private var dragIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let sorted = points.sorted { $0.x < $1.x }
            ZStack {
                Canvas { context, size in draw(context, size: size, sorted: sorted) }
                handles(sorted, size: size)
            }
            .contentShape(Rectangle())
            .gesture(drag(sorted, size: size))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// The grid and the curve. They, the handles and their arithmetic stay out of `body`, with CGFloat
    /// spelled out, so each part type-checks within the Debug build's limit (typeCheckGuard in
    /// Module.swift) on CI's slower runners.
    private func draw(_ context: GraphicsContext, size: CGSize, sorted: [CurvePoint]) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.well))
        var grid = Path()
        for step in 1 ..< 4 {
            let t = CGFloat(step) / 4
            grid.move(to: CGPoint(x: t * size.width, y: 0))
            grid.addLine(to: CGPoint(x: t * size.width, y: size.height))
            grid.move(to: CGPoint(x: 0, y: t * size.height))
            grid.addLine(to: CGPoint(x: size.width, y: t * size.height))
        }
        context.stroke(grid, with: .color(Theme.divider), lineWidth: 1)
        let curve = ToneCurveMath.pointCurve(sorted)
        var path = Path()
        for index in 0 ... 128 {
            let x = Double(index) / 128
            let y: Double = 1 - min(max(curve(x), 0), 1)
            let point = CGPoint(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(tint), lineWidth: 1.5)
    }

    private func handles(_ sorted: [CurvePoint], size: CGSize) -> some View {
        ForEach(Array(sorted.enumerated()), id: \.offset) { index, point in
            CurveHandle(selected: dragIndex == index)
                .position(point.location(in: size))
                .onTapGesture(count: 2) { remove(index, from: sorted) }
        }
    }

    private func remove(_ index: Int, from sorted: [CurvePoint]) {
        guard index > 0, index < sorted.count - 1 else { return }
        change(sorted.enumerated().filter { $0.offset != index }.map(\.element))
    }

    private func drag(_ sorted: [CurvePoint], size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let location = CGPoint(
                    x: min(max(gesture.location.x / size.width, 0), 1),
                    y: min(max(1 - gesture.location.y / size.height, 0), 1),
                )
                var points = sorted
                if dragIndex == nil {
                    begin()
                    let start = CGPoint(
                        x: gesture.startLocation.x / size.width,
                        y: 1 - gesture.startLocation.y / size.height,
                    )
                    if let nearest = points.indices.min(by: {
                        hypot(points[$0].x - start.x, points[$0].y - start.y)
                            < hypot(points[$1].x - start.x, points[$1].y - start.y)
                    }), hypot(points[nearest].x - start.x, points[nearest].y - start.y) < 0.05 {
                        dragIndex = nearest
                    } else {
                        let curve = ToneCurveMath.pointCurve(points)
                        points.append(CurvePoint(x: start.x, y: curve(start.x)))
                        points.sort { $0.x < $1.x }
                        dragIndex = points.firstIndex { abs($0.x - start.x) < 1e-9 }
                    }
                }
                guard let index = dragIndex, points.indices.contains(index) else { return }
                let isEnd = index == 0 || index == points.count - 1
                let lower = index > 0 ? points[index - 1].x + 0.01 : 0
                let upper = index < points.count - 1 ? points[index + 1].x - 0.01 : 1
                points[index] = CurvePoint(
                    x: isEnd ? points[index].x : min(max(location.x, lower), upper),
                    y: location.y,
                )
                change(points)
            }
            .onEnded { _ in
                dragIndex = nil
                end()
            }
    }
}

/// A point on a curve graph, white while it's dragged.
private struct CurveHandle: View {
    let selected: Bool

    var body: some View {
        Circle()
            .fill(selected ? Color.white : Color(white: 0.85))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
            .frame(width: 9, height: 9)
    }
}

private extension CurvePoint {
    /// Where the point sits in a graph of this size, whose y runs up from the bottom.
    func location(in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(x) * size.width, y: (1 - CGFloat(y)) * size.height)
    }
}

/// The three draggable split points under the parametric curve.
struct SplitHandles: View {
    @Environment(EditorModel.self) private var model
    @State private var dragging: ParameterID?

    var body: some View {
        GeometryReader { geometry in
            ForEach(
                [ParameterID.curveSplitShadows, .curveSplitMidtones, .curveSplitHighlights],
                id: \.self,
            ) { parameter in
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.label)
                    .position(x: model.value(parameter) / 100 * geometry.size.width, y: 6)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if dragging == nil {
                                    dragging = parameter
                                    model.beginEdit(parameter)
                                }
                                model.setValue(parameter, gesture.location.x / geometry.size.width * 100)
                            }
                            .onEnded { _ in
                                dragging = nil
                                model.endEdit()
                            },
                    )
                    .onTapGesture(count: 2) { model.reset(parameter) }
                    .help("\(parameter.spec.label): drag to move, double-click to reset")
            }
        }
    }
}

/// The point curve's preset menu and hint, shared with the AppKit panel.
struct PointCurvePresets: View {
    /// The curve the presets set: RGB's, or a channel's own.
    let channel: CurveChannel
    @Environment(EditorModel.self) private var model

    var body: some View {
        HStack {
            Menu("Curve Presets") {
                Button("Linear") { model.resetPointCurve(channel) }
                Button("Medium Contrast") {
                    model.setPointCurve([
                        .init(x: 0, y: 0),
                        .init(x: 0.25, y: 0.21),
                        .init(x: 0.75, y: 0.8),
                        .init(x: 1, y: 1),
                    ], channel: channel)
                }
                Button("Strong Contrast") {
                    model.setPointCurve([
                        .init(x: 0, y: 0),
                        .init(x: 0.25, y: 0.17),
                        .init(x: 0.75, y: 0.84),
                        .init(x: 1, y: 1),
                    ], channel: channel)
                }
                Button("Matte Fade") {
                    model.setPointCurve(
                        [.init(x: 0, y: 0.08), .init(x: 0.3, y: 0.28), .init(x: 1, y: 0.96)], channel: channel,
                    )
                }
            }
            .controlSize(.small)
            .fixedSize()
            Spacer()
            Text("Click to add · double-click a point to remove")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.tertiaryLabel)
        }
    }
}
