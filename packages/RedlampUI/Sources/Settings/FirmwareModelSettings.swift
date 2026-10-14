import RedlampRecipes
import SwiftUI

/// The firmware model's switch, off by default (TON-49), and what reading the model found.
struct FirmwareModelSettings: View {
    /// The editor's recipes, whose status says where the model stands.
    let recipes: RecipeCatalog?
    @AppStorage(FirmwareFilmModel.enabledKey) private var enabled = false
    @AppStorage(FirmwareFilmModel.folderKey) private var folder = ""
    /// Release builds carry the hosted file's addresses; other builds read the model from a folder.
    private let hosted = FirmwareModelHost.Addresses(bundle: .main) != nil

    var body: some View {
        Form {
            Section {
                Toggle("Firmware film model", isOn: $enabled)
                    .accessibilityIdentifier("settings.firmware-model")
                if !hosted {
                    TextField("Folder", text: $folder, prompt: Text(FirmwareFilmModel.defaultFolder.path))
                }
                if enabled, let status = recipes?.firmwareStatus {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Film Simulations")
            } footer: {
                Text(footer)
                    .formFooter()
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: String {
        let what = """
        An experiment: 20 film simulations from a model of a camera's own processing. The Camera \
        Recipe group in Develop's Effects gains a Simulation menu with Highlight and Shadow, Color, \
        D-Range and, for black and white, toning, and recipe cards render through the model.
        """
        let source = hosted
            ? """
            Redlamp downloads the model when you turn this on. It may be withdrawn, but the looks \
            your photos use stay on this Mac, so their edits still render.
            """
            : """
            This build reads the model's four files from the folder. The looks your photos use \
            stay on this Mac, so their edits render with it off.
            """
        return "\(what) \(source)"
    }
}
