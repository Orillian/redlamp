import AppKit
import RedlampDesign
import RedlampEngineAPI
import SwiftUI

/// The Border panel's style menu.
struct BorderStylePicker: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Picker("Style", selection: Binding(
            get: { model.borderStyle.rawValue },
            set: { model.setBorderStyle(BorderStyle(rawValue: $0) ?? .none) },
        )) {
            ForEach(BorderStyle.allCases, id: \.rawValue) { style in
                Text(style.name).tag(style.rawValue)
                if style == .none || style == .plain || style == .mediumFormat || style == .instantWide
                    || style == .slideMountPlastic {
                    Divider()
                }
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .accessibilityIdentifier("border.style")
    }
}

/// The Border panel's controls below Style, as the style needs them: a plain border's shape, size,
/// position and keyline; a card's or mount's colour; film's edge print; Crop to Format.
struct BorderOptions: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let style = model.borderStyle
        let shape = BorderShape(rawValue: Int(model.value(.borderShape).rounded())) ?? .even
        VStack(alignment: .leading, spacing: Metrics.panelRowSpacing) {
            if style.isShaped {
                ControlRow(label: "Shape") { BorderShapePicker() }
                if shape != .even {
                    ControlRow(label: "Orientation") { BorderOrientationPicker() }
                }
                if shape == .custom {
                    ParameterSlider(parameter: .borderRatioWidth)
                    ParameterSlider(parameter: .borderRatioHeight)
                }
                ParameterSlider(parameter: .borderSize)
                ParameterSlider(parameter: .borderOffsetY)
                ParameterSlider(parameter: .borderOffsetX)
            }
            if style.usesColor {
                ControlRow(label: "Color") { BorderColorControl(keyline: false) }
            }
            if style.isShaped {
                SubsectionHeader(title: "Keyline", parameters: [
                    .borderKeylineWidth, .borderKeylineGap, .borderKeylineRed, .borderKeylineGreen, .borderKeylineBlue,
                ])
                ParameterSlider(parameter: .borderKeylineWidth)
                ParameterSlider(parameter: .borderKeylineGap)
                ControlRow(label: "Color") { BorderColorControl(keyline: true) }
            }
            if style.isFilm {
                ControlRow(label: "Edge Print") {
                    Toggle("Edge Print", isOn: Binding(
                        get: { model.value(.borderEdgePrint) > 0.5 },
                        set: { model.setValue(.borderEdgePrint, $0 ? 1 : 0) },
                    ))
                    .labelsHidden()
                    .controlSize(.small)
                    .help("The frame number, and the film's name when the Base Look is a film stock")
                }
                ParameterSlider(parameter: .borderFrameNumber)
            }
            if style.formatAspect != nil {
                ControlRow(label: "Crop") {
                    Button("Crop to Format") { model.cropToBorderFormat() }
                        .controlSize(.small)
                        .help("Crop the photo to the frame's own shape")
                        .accessibilityIdentifier("border.cropToFormat")
                }
            }
        }
    }
}

struct BorderShapePicker: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Picker("Shape", selection: Binding(
            get: { Int(model.value(.borderShape).rounded()) },
            set: { model.setBorderShape(BorderShape(rawValue: $0) ?? .even) },
        )) {
            ForEach(BorderShape.allCases, id: \.rawValue) { shape in
                Text(shape.name).tag(shape.rawValue)
                if shape == .even || shape == .nineBySixteen || shape == .aPaper {
                    Divider()
                }
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .help("The canvas's shape: Even adds the same margin on every side")
        .accessibilityIdentifier("border.shape")
    }
}

struct BorderOrientationPicker: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Picker("Orientation", selection: Binding(
            get: { Int(model.value(.borderOrientation).rounded()) },
            set: { model.setBorderOrientation(BorderOrientation(rawValue: $0) ?? .matchPhoto) },
        )) {
            Text("Photo").tag(BorderOrientation.matchPhoto.rawValue)
            Text("Portrait").tag(BorderOrientation.portrait.rawValue)
            Text("Landscape").tag(BorderOrientation.landscape.rawValue)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help("Photo turns the canvas with the photo; Portrait keeps every photo of a set on a tall canvas")
        .accessibilityIdentifier("border.orientation")
    }
}

/// White, Paper, Grey and Black, and a colour well; the colour panel's magnifier picks a colour from
/// the photo.
struct BorderColorControl: View {
    let keyline: Bool
    @Environment(EditorModel.self) private var model

    var body: some View {
        let current = model.borderColor(keyline: keyline)
        HStack(spacing: 5) {
            ForEach(BorderColor.swatches, id: \.0) { name, color in
                Button {
                    model.setBorderColor(color, keyline: keyline)
                } label: {
                    Circle()
                        .fill(Color(.sRGB, red: color.red / 255, green: color.green / 255, blue: color.blue / 255))
                        .overlay(Circle().strokeBorder(
                            current == color ? Theme.accent : Theme.secondaryLabel,
                            lineWidth: current == color ? 2 : 0.5,
                        ))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(name)
                .accessibilityLabel(name)
                .accessibilityIdentifier("border.\(keyline ? "keyline" : "color").\(name.lowercased())")
            }
            ColorPicker("Custom", selection: Binding(
                get: { Color(.sRGB, red: current.red / 255, green: current.green / 255, blue: current.blue / 255) },
                set: { color in
                    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    model.setBorderColor(
                        BorderColor(
                            red: srgb.redComponent * 255,
                            green: srgb.greenComponent * 255,
                            blue: srgb.blueComponent * 255,
                        ),
                        keyline: keyline,
                    )
                },
            ), supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
                .help("Any colour; the colour panel's magnifier picks one from the photo")
        }
    }
}

/// TON-25's frame, drawn over the photo's edges: shown only on the edits that have one, with Move
/// to Border to put the nearest border around the photo instead.
struct FrameOverPhotoSection: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if model.hasFrameOverPhoto {
            VStack(alignment: .leading, spacing: Metrics.panelRowSpacing) {
                SubsectionHeader(title: "Frame", parameters: [.frameStyle, .frameSize])
                ControlRow(label: "Style") { FrameStylePicker() }
                ParameterSlider(parameter: .frameSize)
                ControlRow(label: "") {
                    Button("Move to Border") { model.moveFrameToBorder() }
                        .controlSize(.small)
                        .help("This frame covers the photo's edges; a border goes around the photo instead")
                        .accessibilityIdentifier("effects.moveFrameToBorder")
                }
            }
        }
    }
}

@_spi(Harness) public struct BorderPanel: View {
    public init() {}

    public var body: some View {
        PanelSection(panel: .border) {
            ControlRow(label: "Style") { BorderStylePicker() }
            BorderOptions()
        }
    }
}
