import AppKit
import UniformTypeIdentifiers

/// Choose Camera Profiles… in the Base Look menu and in the Lightroom Classic window: Adobe `.dcp` and `.xmp`
/// profiles, or folders of them, which Redlamp reads where they are on this Mac and never copies (TON-51, DEC-85).
enum CameraProfileChooser {
    /// Opens the panel, over `window` when there's one; `chosen` runs once the files chosen are added.
    @MainActor static func choose(
        model: EditorModel, over window: NSWindow? = nil, then chosen: (@MainActor () -> Void)? = nil,
    ) {
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
        if let window {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK else { return }
                add(panel.urls, model: model, then: chosen)
            }
        } else {
            panel.begin { response in
                guard response == .OK else { return }
                add(panel.urls, model: model, then: chosen)
            }
        }
    }

    @MainActor private static func add(_ urls: [URL], model: EditorModel, then chosen: (@MainActor () -> Void)?) {
        Task {
            await model.chooseCameraProfiles(urls)
            chosen?()
        }
    }
}
