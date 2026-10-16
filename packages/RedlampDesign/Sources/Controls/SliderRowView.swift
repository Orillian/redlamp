import AppKit
import RedlampEngineAPI

/// A number a slider row edits that isn't one of the edit's parameters, such as a recipe's Amount.
/// A drag or a scrub is `begin`, each `change` and `end`, one gesture, and a typed value, an arrow
/// key's step or a double-click's reset to `defaultValue` is one `set`. The row shows `current` after
/// each, and as what it reads changes while the row is in a window: a row built while a list reloads
/// adds what it reads to what the list follows.
public struct SliderValue {
    public var label: String
    public var spec: FieldSpec
    public var defaultValue: Double
    public var current: () -> Double
    public var begin: () -> Void
    public var change: (Double) -> Void
    public var end: () -> Void
    public var set: (Double) -> Void

    public init(
        label: String,
        spec: FieldSpec,
        defaultValue: Double,
        current: @escaping () -> Double,
        begin: @escaping () -> Void,
        change: @escaping (Double) -> Void,
        end: @escaping () -> Void,
        set: @escaping (Double) -> Void,
    ) {
        self.label = label
        self.spec = spec
        self.defaultValue = defaultValue
        self.current = current
        self.begin = begin
        self.change = change
        self.end = end
        self.set = set
    }
}

/// A Lightroom-style parameter row: label, precision slider, editable value.
///
/// - Drag the thumb for relative changes, or click the track to jump.
/// - Shift-drag for fine control.
/// - Double-click the label or thumb to reset.
/// - Option-drag on tone sliders previews clipping.
/// - Drag the value to scrub it (Shift for fine control), or click it to type; arrow keys step
///   (Shift for ×10).
/// - ⌘-scroll adjusts the slider under the pointer (Shift ×10, Option ×0.1); plain scrolling
///   still scrolls the panels.
///
/// While it is in a window, the row keeps itself in step with `editor`: a drag redraws
/// the track and the readout, and nothing else. A row for a number that isn't one of the edit's
/// parameters (`SliderValue`) keeps itself in step with its value the same way.
public final class SliderRowView: NSView {
    /// The parameter the row edits; nil for a `SliderValue`'s row.
    public let parameter: ParameterID?
    private let edits: Edits

    private let labelView: RowLabelView
    private let trackView: SliderTrackView
    private let valueView: ValueFieldView
    private let focusMarker = FocusMarkerView()
    private var trackers: [Tracker] = []
    private var hoverArea: NSTrackingArea?
    /// Scroll distance not yet turned into steps, the pending end of the scroll's edit, and that edit.
    private var scrollRemainder: CGFloat = 0
    private var scrollEnd: Task<Void, Never>?
    private var scrollEdit: Int?

    private static let clippingParameters: Set<ParameterID> = [
        .exposure, .highlights, .shadows, .whites, .blacks,
        .localExposure, .localHighlights, .localShadows, .localWhites, .localBlacks,
    ]

    /// What the row reads and changes: one of the edit's parameters through its editor, or a
    /// number of its own.
    private enum Edits {
        case parameter(ParameterID, ParameterSpec, ParameterEditing, enabled: @MainActor () -> Bool)
        case value(SliderValue)
    }

    public init(
        parameter: ParameterID,
        label: String? = nil,
        editor: ParameterEditing,
        enabled: @escaping @MainActor () -> Bool = { true },
    ) {
        self.parameter = parameter
        let spec = parameter.spec
        edits = .parameter(parameter, spec, editor, enabled: enabled)
        labelView = RowLabelView(text: label ?? spec.label)
        trackView = SliderTrackView(spec: spec)
        valueView = ValueFieldView(spec: spec)
        super.init(frame: CGRect(x: 0, y: 0, width: 280, height: Metrics.rowHeight))
        addParts()
        // Named from the parameter's key, for VoiceOver and the regression suite.
        identify(as: "slider.\(parameter.rawValue)")
        toolTip = spec.availability.isLive
            ? "Double-click to reset. Shift-drag for fine control. ⌘-scroll to adjust. Drag or click the number."
            : "\(spec.label) is laid out for reference and renders in \(Self.phase(spec))."
        wireActions(parameter, editor)
    }

    /// A row for `value`, a number that isn't one of the edit's parameters, named `identifier` for
    /// VoiceOver and the regression suite. ⌘-scrolling over it scrolls the panels.
    public init(_ value: SliderValue, identifier: String) {
        parameter = nil
        edits = .value(value)
        labelView = RowLabelView(text: value.label)
        trackView = SliderTrackView(spec: value.spec, value: value.current())
        valueView = ValueFieldView(spec: value.spec, value: value.current())
        super.init(frame: CGRect(x: 0, y: 0, width: 280, height: Metrics.rowHeight))
        addParts()
        identify(as: identifier)
        toolTip = "Double-click to reset. Shift-drag for fine control. Drag or click the number."
        wireActions(value)
    }

    private func addParts() {
        valueView.trailingInset = ValueFieldView.wellPadding
        wantsLayer = true
        clipsToBounds = false
        for view in [focusMarker, labelView, trackView, valueView] as [NSView] {
            addSubview(view)
        }
        focusMarker.isHidden = true
    }

    private func identify(as identifier: String) {
        setAccessibilityIdentifier(identifier)
        labelView.setAccessibilityIdentifier("\(identifier).label")
        trackView.setAccessibilityIdentifier("\(identifier).track")
        valueView.setAccessibilityIdentifier("\(identifier).value")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func phase(_ spec: ParameterSpec) -> String {
        if case let .planned(phase) = spec.availability {
            return phase
        }
        return ""
    }

    override public var isFlipped: Bool {
        true
    }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.rowHeight)
    }

    /// The width this row's number needs at its widest.
    public var widestValueWidth: CGFloat {
        valueView.widestText
    }

    /// The value column's width its panel gives every row (`PanelSectionView`), so their wells
    /// are one width and their tracks end at one x, clear of the well; nil keeps the panels'
    /// standard value column.
    public var valueColumnWidth: CGFloat? {
        didSet {
            if valueColumnWidth != oldValue {
                valueView.columnTextWidth = valueColumnWidth
                needsLayout = true
            }
        }
    }

    // MARK: - Layout

    override public func layout() {
        super.layout()
        let height = bounds.height
        labelView.frame = CGRect(x: 0, y: 0, width: Metrics.labelWidth, height: height)
        let column = valueColumnWidth ?? Metrics.valueWidth
        let valueX = bounds.width - column
        valueView.frame = CGRect(x: valueX, y: 0, width: column + ValueFieldView.wellPadding, height: height)
        let trackX = Metrics.labelWidth + Metrics.rowSpacing
        let trackEnd = valueX - Metrics.rowSpacing - (valueColumnWidth == nil ? 0 : ValueFieldView.wellPadding)
        trackView.frame = CGRect(
            x: trackX,
            y: (height - Metrics.trackHeight) / 2,
            width: max(trackEnd - trackX, 0),
            height: Metrics.trackHeight,
        )
        focusMarker.frame = CGRect(x: -8, y: (height - 12) / 2, width: 2, height: 12)
    }

    // MARK: - State

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trackers.forEach { $0.cancel() }
        trackers = []
        guard window != nil else { return }
        if case let .value(value) = edits {
            trackers = [Tracker { [weak self] in self?.show(value.current()) }]
            return
        }
        guard case let .parameter(parameter, spec, editor, enabled) = edits else { return }
        trackers = [
            Tracker { [weak self] in
                guard let self else { return }
                let value = editor.sliderValue(parameter)
                trackView.value = value
                valueView.value = value
            },
            Tracker { [weak self] in
                guard let self else { return }
                let focused = editor.focusedParameter == parameter
                let live = spec.availability.isLive && enabled()
                labelView.isFocused = focused
                focusMarker.isHidden = !focused
                let opacity: CGFloat = live ? 1 : 0.35
                trackView.isEnabled = live
                valueView.isEnabled = live
                labelView.isEnabled = live
                trackView.opacity = opacity
                valueView.opacity = opacity
                labelView.opacity = opacity
                focusMarker.alphaValue = opacity
            },
            Tracker { [weak self] in
                guard let self, editor.revealedParameter == parameter else { return }
                // After the panel has expanded and laid out.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    scrollToVisible(bounds.insetBy(dx: 0, dy: -Metrics.rowHeight))
                    editor.revealedParameter = nil
                }
            },
        ]
    }

    private func wireActions(_ parameter: ParameterID, _ editor: ParameterEditing) {
        labelView.onClick = { [weak editor] in editor?.focusedParameter = parameter }
        labelView.onDoubleClick = { [weak editor] in editor?.resetSlider(parameter) }
        let begin: () -> Void = { [weak editor] in
            guard let editor else { return }
            editor.focusedParameter = parameter
            editor.beginEdit(parameter)
            if Self.clippingParameters.contains(parameter), NSEvent.modifierFlags.contains(.option) {
                editor.setTemporaryClipping(true)
            }
        }
        let change: (Double) -> Void = { [weak editor] in editor?.setSliderValue(parameter, $0) }
        let end: () -> Void = { [weak editor] in
            editor?.setTemporaryClipping(false)
            editor?.endEdit(name: nil)
        }
        trackView.onBegin = begin
        trackView.onChange = change
        trackView.onEnd = end
        trackView.onReset = { [weak editor] in editor?.resetSlider(parameter) }
        valueView.onBegin = begin
        valueView.onChange = change
        valueView.onEnd = end
        valueView.onCommit = change
    }

    private func wireActions(_ value: SliderValue) {
        let change: (Double) -> Void = { [weak self] in
            value.change(value.spec.quantize($0))
            self?.show(value.current())
        }
        let set: (Double) -> Void = { [weak self] in
            value.set($0)
            self?.show(value.current())
        }
        labelView.onDoubleClick = { set(value.defaultValue) }
        trackView.onBegin = value.begin
        trackView.onChange = change
        trackView.onEnd = value.end
        trackView.onReset = { set(value.defaultValue) }
        valueView.onBegin = value.begin
        valueView.onChange = change
        valueView.onEnd = value.end
        valueView.onCommit = set
    }

    private func show(_ value: Double) {
        trackView.value = value
        valueView.value = value
    }

    // MARK: - Scroll

    override public func scrollWheel(with event: NSEvent) {
        guard case let .parameter(parameter, spec, editor, enabled) = edits, event.modifierFlags.contains(.command),
              spec.availability.isLive, enabled()
        else {
            super.scrollWheel(with: event)
            return
        }
        // Shift turns vertical scrolling horizontal; the device's own direction means up is more.
        var delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        if event.isDirectionInvertedFromDevice {
            delta = -delta
        }
        scrollRemainder += event.hasPreciseScrollingDeltas ? delta / 8 : delta
        let steps = scrollRemainder.rounded(.towardZero)
        guard steps != 0 else { return }
        scrollRemainder -= steps
        if scrollEnd == nil {
            editor.focusedParameter = parameter
            editor.beginEdit(parameter)
            scrollEdit = editor.openEdit
        }
        let flags = event.modifierFlags
        let multiplier = flags.contains(.shift) ? 10.0 : flags.contains(.option) ? 0.1 : 1.0
        let value = editor.sliderValue(parameter) + Double(steps) * spec.step * multiplier
        editor.setSliderValue(parameter, spec.clamp(value))
        // One history step per gesture: it ends once scrolling pauses.
        scrollEnd?.cancel()
        scrollEnd = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            scrollEnd = nil
            scrollRemainder = 0
            // An edit begun since (a slider drag) has taken the scroll's place.
            if editor.openEdit == scrollEdit {
                editor.endEdit(name: nil)
            }
        }
    }

    // MARK: - Hover

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override public func mouseEntered(with _: NSEvent) {
        labelView.isHovering = true
    }

    override public func mouseExited(with _: NSEvent) {
        labelView.isHovering = false
    }
}

/// The row's label: hover brightens it, focus makes it semibold in the accent color.
final class RowLabelView: LayerDrawnView {
    let text: String
    var isHovering = false {
        didSet {
            if isHovering != oldValue {
                setNeedsContentDisplay()
            }
        }
    }

    var isFocused = false {
        didSet {
            if isFocused != oldValue {
                setNeedsContentDisplay()
            }
        }
    }

    var isEnabled = true {
        didSet {
            if isEnabled != oldValue {
                setNeedsContentDisplay()
            }
        }
    }

    var opacity: CGFloat = 1 {
        didSet {
            if opacity != oldValue {
                setNeedsContentDisplay()
            }
        }
    }

    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func drawContent(in _: CGRect) {
        let color: NSColor = if isFocused {
            Palette.accent.withAlphaComponent(Palette.accent.alphaComponent * opacity)
        } else {
            (isHovering && isEnabled ? Palette.labelHover : Palette.label).opacity(opacity).nsColor
        }
        TextLine.draw(
            text, font: isFocused ? Typography.label.weight(.semibold) : Typography.label,
            color: color, in: bounds, scale: backingScale,
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.clickCount >= 2 {
            onDoubleClick()
        } else {
            onClick()
        }
    }
}

/// Lightroom-style marker beside the slider `,` `.` select and `-` `=` nudge.
final class FocusMarkerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_: NSRect) {
        Palette.accent.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.width / 2, yRadius: bounds.width / 2).fill()
    }
}
