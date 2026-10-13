import RedlampRecipes
import SwiftUI

/// The firmware model's switch, off by default (local fujisim-prototype branch only).
struct FirmwareModelSettings: View {
    @AppStorage(FirmwareFilmModel.enabledKey) private var enabled = false
    @AppStorage(FirmwareFilmModel.folderKey) private var folder = ""

    private var folderURL: URL {
        folder.isEmpty ? FirmwareFilmModel
            .defaultFolder : URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Firmware film model", isOn: $enabled)
                    .accessibilityIdentifier("settings.firmware-model")
                TextField("Folder", text: $folder, prompt: Text(FirmwareFilmModel.defaultFolder.path))
                if enabled {
                    Text(FirmwareFilmModel.isAvailable(at: folderURL)
                        ? "The model's files are in this folder."
                        : "This folder doesn't hold the model's four files.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Prototype")
            } footer: {
                Text("""
                Renders the firmware-derived model's 20 film simulations as Base Looks, read from the \
                folder when it's turned on. The Effects panel's Camera Recipe group sets the simulation \
                and its tone, Color, dynamic range and toning, and recipe cards resolve through the model. \
                Its looks stay on this Mac. This branch is never pushed.
                """)
                .formFooter()
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
