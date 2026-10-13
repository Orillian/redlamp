import RedlampEngineAPI
import RedlampRecipes
import SwiftUI

/// The firmware model's simulation and settings in the Camera Recipe group, shown only while
/// the prototype's switch is on (local fujisim-prototype branch only).
struct FirmwareModelControls: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if model.usesFirmwareModel {
            VStack(alignment: .leading, spacing: 0) {
                ControlRow(label: "Simulation") { simulationPicker }
                if let settings = model.firmwareSettings {
                    ControlRow(label: "Highlight") {
                        picker(settings.highlight, tones) { $0.highlight = $1 }
                    }
                    ControlRow(label: "Shadow") {
                        picker(settings.shadow, tones) { $0.shadow = $1 }
                    }
                    ControlRow(label: "Color") {
                        picker(settings.color, Array(FirmwareLookSettings.colorRange)) { $0.color = $1 }
                    }
                    ControlRow(label: "D-Range") {
                        picker(settings.dynamicRange, FirmwareLookSettings.dynamicRanges, format: { "DR\($0)" }) {
                            $0.dynamicRange = $1
                        }
                    }
                    if settings.simulation.isMonochrome {
                        ControlRow(label: "Warm/Cool") {
                            picker(settings.warmCool, Array(FirmwareLookSettings.toningRange)) { $0.warmCool = $1 }
                        }
                        ControlRow(label: "Magenta/Green") {
                            picker(settings.magentaGreen, Array(FirmwareLookSettings.toningRange)) {
                                $0.magentaGreen = $1
                            }
                        }
                    }
                }
            }
        }
    }

    private var tones: [Double] {
        stride(
            from: FirmwareLookSettings.toneRange.lowerBound,
            through: FirmwareLookSettings.toneRange.upperBound,
            by: 0.5,
        )
        .map(\.self)
    }

    private var simulationPicker: some View {
        Picker("Simulation", selection: Binding(
            get: { model.firmwareSettings?.simulation },
            set: { simulation in
                if let simulation {
                    var settings = model.firmwareSettings ?? FirmwareLookSettings(simulation: simulation)
                    settings.simulation = simulation
                    model.setFirmwareLook(settings)
                } else {
                    model.setFirmwareLook(nil)
                }
            },
        )) {
            Text("None").tag(FirmwareSimulation?.none)
            Divider()
            ForEach(FirmwareSimulation.allCases.filter { $0.slot != nil }, id: \.self) {
                Text($0.name).tag(FirmwareSimulation?.some($0))
            }
            Section("Prototype only") {
                ForEach(FirmwareSimulation.allCases.filter { $0.slot == nil }, id: \.self) {
                    Text($0.name).tag(FirmwareSimulation?.some($0))
                }
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .accessibilityIdentifier("develop.firmware-model.simulation")
    }

    private func picker<Value: Hashable & Comparable & SignedNumeric>(
        _ value: Value,
        _ values: [Value],
        format: @escaping (Value) -> String = { "\($0 > 0 ? "+" : "")\($0)" },
        _ update: @escaping (inout FirmwareLookSettings, Value) -> Void,
    ) -> some View {
        Picker("", selection: Binding(
            get: { value },
            set: { new in model.updateFirmwareLook { update(&$0, new) } },
        )) {
            ForEach(values, id: \.self) { Text(format($0)).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
    }
}
