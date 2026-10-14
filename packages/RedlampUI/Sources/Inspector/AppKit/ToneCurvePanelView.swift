import AppKit
import Observation
import RedlampDesign
import RedlampEngineAPI
import SwiftUI

/// The Tone Curve panel: a parametric curve (region sliders and split handles) or a point
/// curve for RGB, red, green or blue (drag points, click to add, double-click to remove), over
/// the histogram of what it changes.
@MainActor
@_spi(Harness) public enum ToneCurvePanelView {
    public static func make(model: EditorModel) -> PanelSectionView {
        let state = ToneCurveState()
        let picker = PaddingView(
            ControlRowView(label: "Curve", controls: [HostedControl(model: model, ToneCurveModePicker(state: state))]),
            bottom: 6,
        )
        let channel = PaddingView(
            ControlRowView(
                label: "Channel", controls: [HostedControl(model: model, ToneCurveChannelPicker(state: state))],
            ),
            bottom: 6,
        )
        let graph = CurveGraphView(model: model, state: state)
        let parametric: [NSView] = [
            SplitHandlesView(model: model),
            SplitValuesView(model: model),
            SubsectionHeaderView(
                title: "Region",
                parameters: [.curveHighlights, .curveLights, .curveDarks, .curveShadows],
                editor: model,
            ),
        ] + [ParameterID.curveHighlights, .curveLights, .curveDarks, .curveShadows].map {
            SliderRowView(parameter: $0, editor: model)
        }
        let point: [NSView] = [
            PointValuesView(model: model, state: state),
            HostedControl(model: model, ToneCurvePresetsRow(state: state).padding(.top, 6)),
        ]

        let panel = PanelSectionView(panel: .toneCurve, model: model, rows: [picker, graph] + parametric)
        state.onModeChange = { [weak panel] mode in
            panel?.setRows(mode == .parametric ? [picker, graph] + parametric : [picker, channel, graph] + point)
        }
        return panel
    }
}

/// The panel's own view state (SwiftUI's `@State` in the original).
@MainActor @Observable
final class ToneCurveState {
    var mode = ToneCurvePanel.Mode.parametric {
        didSet {
            if mode != oldValue {
                onModeChange(mode)
            }
        }
    }

    /// The point curve shown in point mode: RGB's, or a channel's own.
    var channel = CurveChannel.rgb {
        didSet {
            if channel != oldValue {
                selectedPoint = nil
            }
        }
    }

    /// The point curve's point last pressed, by its place in x order; its Input and Output show
    /// under the graph.
    var selectedPoint: Int?

    @ObservationIgnored var onModeChange: (ToneCurvePanel.Mode) -> Void = { _ in }
}

private struct ToneCurveModePicker: View {
    @Bindable var state: ToneCurveState

    var body: some View {
        ChoiceMenu("Curve", selection: $state.mode)
            .controlSize(.small)
            .automationIdentifier("curve.mode")
    }
}

private struct ToneCurveChannelPicker: View {
    @Bindable var state: ToneCurveState

    var body: some View {
        ChoiceMenu("Channel", selection: $state.channel)
            .controlSize(.small)
            .automationIdentifier("curve.channel")
    }
}

/// The presets for the curve shown.
private struct ToneCurvePresetsRow: View {
    let state: ToneCurveState

    var body: some View {
        PointCurvePresets(channel: state.channel)
    }
}

/// The square curve graph: grid, the histogram of what the curve changes, and the curves.
final class CurveGraphView: LayerDrawnView, HeightProviding {
    private let model: EditorModel
    private let state: ToneCurveState
    private var tracker: Tracker?

    private var histogram: [UInt32] = []
    private var curve = EditRecipe()
    private var points: [CurvePoint] = []
    private var mode = ToneCurvePanel.Mode.parametric
    private var channel = CurveChannel.rgb
    private var selected: Int?
    private var dragIndex: Int? {
        didSet {
            if dragIndex != oldValue {
                setNeedsContentDisplay()
            }
        }
    }

    init(model: EditorModel, state: ToneCurveState) {
        self.model = model
        self.state = state
        super.init(frame: .zero)
        setAccessibilityIdentifier("curve.graph")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        width
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tracker?.cancel()
        tracker = nil
        guard window != nil else { return }
        tracker = Tracker { [weak self] in
            guard let self else { return }
            mode = state.mode
            channel = mode == .point ? state.channel : .rgb
            histogram = model.histogram.bins(channel)
            curve = model.toneCurve
            points = curve[curve: channel]
            selected = state.selectedPoint
            setNeedsContentDisplay()
        }
    }

    // MARK: - Drawing

    override func drawContent(in _: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        context.saveGState()
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()

        context.setFillColor(Palette.well.cgColor)
        context.fill(bounds)

        let grid = CGMutablePath()
        for step in 1 ..< 4 {
            let t = Double(step) / 4
            grid.move(to: CGPoint(x: t * size.width, y: 0))
            grid.addLine(to: CGPoint(x: t * size.width, y: size.height))
            grid.move(to: CGPoint(x: 0, y: t * size.height))
            grid.addLine(to: CGPoint(x: size.width, y: t * size.height))
        }
        stroke(grid, color: Palette.divider, width: 1, context: context)
        let diagonal = CGMutablePath()
        diagonal.move(to: CGPoint(x: 0, y: size.height))
        diagonal.addLine(to: CGPoint(x: size.width, y: 0))
        stroke(diagonal, color: Palette.divider, width: 1, dash: [3, 3], context: context)

        if mode == .parametric {
            let lines = CGMutablePath()
            for split in [curve[.curveSplitShadows], curve[.curveSplitMidtones], curve[.curveSplitHighlights]] {
                let x = split / 100 * size.width
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: size.height))
            }
            stroke(lines, color: RGBA(white: 1, alpha: 0.12), width: 1, context: context)
        }

        drawHistogram(size: size, context: context)

        let curves = CurveGraphCurves(curve, mode: mode, channel: channel)
        for faint in curves.faint {
            stroke(path(faint.samples, size: size), color: faint.color, width: 1, context: context)
        }
        stroke(path(curves.shown.samples, size: size), color: curves.shown.color, width: 1.5, context: context)
        context.restoreGState()

        if mode == .point {
            let scale = backingScale
            for (index, point) in points.sorted(by: { $0.x < $1.x }).enumerated() {
                let rect = PixelGrid.centered(
                    CGSize(width: 9, height: 9), at: CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height),
                    scale: scale,
                )
                let active = dragIndex == index || selected == index
                context.setFillColor((active ? RGBA(white: 1) : RGBA(white: 0.85)).cgColor)
                context.fillEllipse(in: rect)
                context.setStrokeColor(RGBA(white: 0, alpha: 0.5).cgColor)
                context.setLineWidth(0.5)
                context.strokeEllipse(in: rect.insetBy(dx: 0.25, dy: 0.25))
            }
        }
    }

    private func drawHistogram(size: CGSize, context: CGContext) {
        let peak = histogram.dropFirst().dropLast().max() ?? 0
        guard peak > 0 else { return }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, count) in histogram.enumerated() {
            let x = Double(index) / Double(histogram.count - 1) * size.width
            path.addLine(to: CGPoint(
                x: x,
                y: size.height - min(sqrt(Double(count) / Double(peak)), 1) * size.height * 0.9,
            ))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        context.addPath(path)
        context.setFillColor(channel.histogramFill.cgColor)
        context.fillPath()
    }

    private func path(_ samples: [Double], size: CGSize) -> CGPath {
        let path = CGMutablePath()
        for (index, value) in samples.enumerated() {
            let point = CGPoint(x: Double(index) / Double(samples.count - 1) * size.width, y: (1 - value) * size.height)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func stroke(_ path: CGPath, color: RGBA, width: CGFloat, dash: [CGFloat] = [], context: CGContext) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        if !dash.isEmpty {
            context.setLineDash(phase: 0, lengths: dash)
        }
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Point editing

    private func curvePoint(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x / bounds.width, y: 1 - location.y / bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        guard mode == .point else { return }
        let start = curvePoint(convert(event.locationInWindow, from: nil))
        var sorted = points.sorted { $0.x < $1.x }
        let nearest = sorted.indices.min { hypot(sorted[$0].x - start.x, sorted[$0].y - start.y) < hypot(
            sorted[$1].x - start.x,
            sorted[$1].y - start.y,
        ) }
        let hit = nearest.flatMap { hypot(sorted[$0].x - start.x, sorted[$0].y - start.y) < 0.05 ? $0 : nil }
        if event.clickCount == 2, let hit {
            guard hit > 0, hit < sorted.count - 1 else { return }
            sorted.remove(at: hit)
            state.selectedPoint = nil
            model.setPointCurve(sorted, channel: channel)
            return
        }
        model.beginEdit()
        if let hit {
            dragIndex = hit
        } else {
            let curve = ToneCurveMath.pointCurve(sorted)
            sorted.append(CurvePoint(x: start.x, y: curve(start.x)))
            sorted.sort { $0.x < $1.x }
            dragIndex = sorted.firstIndex { abs($0.x - start.x) < 1e-9 }
        }
        state.selectedPoint = dragIndex
        move(to: start, in: sorted)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .point, dragIndex != nil else { return }
        move(to: curvePoint(convert(event.locationInWindow, from: nil)), in: points.sorted { $0.x < $1.x })
    }

    override func mouseUp(with _: NSEvent) {
        guard dragIndex != nil else { return }
        dragIndex = nil
        model.endEdit(.toneCurve, channel.curveTitle)
    }

    private func move(to location: CGPoint, in sorted: [CurvePoint]) {
        guard let index = dragIndex, sorted.indices.contains(index) else { return }
        var points = sorted
        let location = CGPoint(x: min(max(location.x, 0), 1), y: min(max(location.y, 0), 1))
        let isEndpoint = index == 0 || index == points.count - 1
        let lower = index > 0 ? points[index - 1].x + 0.01 : 0
        let upper = index < points.count - 1 ? points[index + 1].x - 0.01 : 1
        let x = isEndpoint ? points[index].x : min(max(location.x, lower), upper)
        points[index] = CurvePoint(x: x, y: location.y)
        model.setPointCurve(points, channel: channel)
    }
}

/// The three draggable split points under the parametric curve.
final class SplitHandlesView: LayerDrawnView, NSViewToolTipOwner {
    private static let parameters: [ParameterID] = [.curveSplitShadows, .curveSplitMidtones, .curveSplitHighlights]
    private let model: EditorModel
    private var tracker: Tracker?
    private var values: [Double] = [25, 50, 75]
    private var dragging: ParameterID?
    private var editing = false

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// 12 for the handles, and the 4 SwiftUI pads below them.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 16)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tracker?.cancel()
        tracker = nil
        guard window != nil else { return }
        tracker = Tracker { [weak self] in
            guard let self else { return }
            values = Self.parameters.map { self.model.value($0) }
            setNeedsContentDisplay()
            updateToolTips()
        }
    }

    private func frame(for value: Double) -> CGRect {
        PixelGrid.centered(
            Symbol.layoutSize("arrowtriangle.up.fill", pointSize: 9, weight: .regular),
            at: CGPoint(x: value / 100 * bounds.width, y: 6), scale: backingScale,
        )
    }

    override func drawContent(in _: CGRect) {
        for value in values {
            Symbol.draw(
                "arrowtriangle.up.fill", pointSize: 9, color: Palette.label,
                centeredAt: CGPoint(x: value / 100 * bounds.width, y: 6), scale: backingScale,
            )
        }
    }

    private func parameter(at location: CGPoint) -> ParameterID? {
        zip(Self.parameters, values).first { frame(for: $0.1).insetBy(dx: -2, dy: -2).contains(location) }?.0
    }

    override func mouseDown(with event: NSEvent) {
        guard let parameter = parameter(at: convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount == 2 {
            model.reset(parameter)
            return
        }
        dragging = parameter
    }

    override func mouseDragged(with event: NSEvent) {
        guard let parameter = dragging else { return }
        if !editing {
            editing = true
            model.beginEdit(parameter)
        }
        model.setValue(parameter, convert(event.locationInWindow, from: nil).x / bounds.width * 100)
    }

    override func mouseUp(with _: NSEvent) {
        dragging = nil
        guard editing else { return }
        editing = false
        model.endEdit()
    }

    private func updateToolTips() {
        removeAllToolTips()
        for (index, value) in values.enumerated() {
            addToolTip(frame(for: value), owner: self, userData: UnsafeMutableRawPointer(bitPattern: index + 1))
        }
    }

    func view(
        _: NSView,
        stringForToolTip _: NSView.ToolTipTag,
        point _: NSPoint,
        userData: UnsafeMutableRawPointer?,
    ) -> String {
        let index = Int(bitPattern: userData) - 1
        let parameter = Self.parameters[max(0, min(index, Self.parameters.count - 1))]
        return "\(parameter.spec.label): drag to move, double-click to reset"
    }
}

/// The three split points as values, under their handles: drag or click one to move it.
final class SplitValuesView: NSView {
    private static let parameters: [ParameterID] = [.curveSplitShadows, .curveSplitMidtones, .curveSplitHighlights]
    private let model: EditorModel
    private let row: LabelledValuesView
    private var tracker: Tracker?

    init(model: EditorModel) {
        self.model = model
        row = LabelledValuesView(title: "Splits", Self.parameters.map { ("", .editing($0, in: model)) })
        super.init(frame: .zero)
        addSubview(row)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        row.intrinsicContentSize
    }

    override func layout() {
        super.layout()
        row.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tracker?.cancel()
        tracker = nil
        guard window != nil else { return }
        tracker = Tracker { [weak self] in
            guard let self else { return }
            for (field, parameter) in zip(row.fields, Self.parameters) {
                field.value = model.value(parameter)
            }
        }
    }
}

/// The selected point's Input and Output, 0 to 255: drag or click either to move the point.
final class PointValuesView: NSView {
    private static let spec = FieldSpec(range: 0 ... 255)
    private enum Axis {
        case input, output
    }

    private let model: EditorModel
    private let state: ToneCurveState
    private let row: LabelledValuesView
    private var tracker: Tracker?

    init(model: EditorModel, state: ToneCurveState) {
        self.model = model
        self.state = state
        let input = ValueFieldView(spec: Self.spec)
        let output = ValueFieldView(spec: Self.spec)
        input.setAccessibilityIdentifier("curve.point.input")
        output.setAccessibilityIdentifier("curve.point.output")
        row = LabelledValuesView([("Input", input), ("Output", output)])
        super.init(frame: .zero)
        addSubview(row)
        for (field, axis) in [(input, Axis.input), (output, .output)] {
            field.onBegin = { model.beginEdit() }
            field.onChange = { [weak self] in self?.move(axis, to: $0) }
            field.onEnd = { model.endEdit(.toneCurve, state.channel.curveTitle) }
            field.onCommit = { [weak self] in self?.move(axis, to: $0) }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        row.intrinsicContentSize
    }

    override func layout() {
        super.layout()
        row.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tracker?.cancel()
        tracker = nil
        guard window != nil else { return }
        tracker = Tracker { [weak self] in
            guard let self else { return }
            let points = model.pointCurve(state.channel).sorted { $0.x < $1.x }
            guard let index = state.selectedPoint, points.indices.contains(index) else {
                row.hint = "Click a point to type its Input and Output"
                return
            }
            row.hint = nil
            row.fields[0].value = points[index].x * 255
            row.fields[1].value = points[index].y * 255
        }
    }

    /// Moves the selected point, keeping it between its neighbours; the end points keep their Input.
    private func move(_ axis: Axis, to value: Double) {
        var points = model.pointCurve(state.channel).sorted { $0.x < $1.x }
        guard let index = state.selectedPoint, points.indices.contains(index) else { return }
        let t = min(max(value / 255, 0), 1)
        var point = points[index]
        switch axis {
        case .input:
            guard index > 0, index < points.count - 1 else { return }
            point = CurvePoint(x: min(max(t, points[index - 1].x + 0.01), points[index + 1].x - 0.01), y: point.y)
        case .output:
            point = CurvePoint(x: point.x, y: t)
        }
        points[index] = point
        model.setPointCurve(points, channel: state.channel)
    }
}
