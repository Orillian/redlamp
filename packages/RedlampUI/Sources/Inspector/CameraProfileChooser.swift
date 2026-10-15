import AppKit
import UniformTypeIdentifiers

/// Choose Camera Profiles… in the Base Look menu: Adobe `.dcp` and `.xmp` profiles, or folders of
/// them, which Redlamp reads where they are on this Mac and never copies (TON-51, DEC-85).
enum CameraProfileChooser {
    @MainActor static func choose(model: EditorModel) {
        let panel = NSOpenPanel()
        panel.title = "Choose Camera Profiles"
        panel.message = "Choose Adobe camera profiles (.dcp) and profiles (.xmp), or folders of them. Redlamp reads "
            + "them where they are, on this Mac only."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "dcp") ?? .data, UTType(filenameExtension: "xmp") ?? .xml, .folder,
        ]
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { await model.chooseCameraProfiles(urls) }
        }
    }
}
