import RedlampDesign
import RedlampEngineAPI
import SwiftUI

/// Lightroom's Setup menu for lens profiles (LNS-15): Default and Auto match a profile to the
/// photo's lens; Custom keeps the one chosen in the menus below.
struct LensProfileSetupPicker: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Picker("Setup", selection: Binding(
            get: { model.lensProfileSetup },
            set: { model.setLensProfileSetup($0) },
        )) {
            ForEach(LensProfileChoice.Setup.allCases, id: \.self) { Text($0.name).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
        .disabled(model.info?.isRaw != true)
        .help("Default and Auto use the lens profile matched to the photo's lens; Custom, the one chosen below")
    }
}

/// Lightroom's Make, Model and Profile menus (LNS-15), over the lens profiles on this Mac the photo
/// can use. Choosing in any of them chooses a profile, and makes the Setup Custom.
struct LensProfilePicker: View {
    enum Level {
        case make, model, profile
    }

    @Environment(EditorModel.self) private var model
    let level: Level

    /// "" stands for no profile.
    static func items(_ level: Level, in model: EditorModel) -> [(tag: String, title: String)] {
        let options = model.lensProfileOptions ?? []
        let shown = model.shownLensProfile
        func unique(_ names: [String]) -> [(tag: String, title: String)] {
            var seen = Set<String>()
            return names.filter { seen.insert($0).inserted }.map { ($0, $0) }
        }
        let items: [(tag: String, title: String)] = switch level {
        case .make: unique(options.map(\.make))
        case .model: unique(options.filter { $0.make == shown?.make }.map(\.model))
        case .profile:
            options.filter { $0.make == shown?.make && $0.model == shown?.model }.map { option in
                let sameName = options.filter { $0.name == option.name && $0.model == option.model }.count > 1
                return (option.fileName, option.name + (sameName ? " (\(option.folder.shortName))" : ""))
            }
        }
        return shown == nil ? [("", "None")] + items : items
    }

    static func selection(_ level: Level, in model: EditorModel) -> String {
        guard let shown = model.shownLensProfile else { return "" }
        return switch level {
        case .make: shown.make
        case .model: shown.model
        case .profile: shown.fileName
        }
    }

    var body: some View {
        let items = Self.items(level, in: model)
        Picker(Self.label(level), selection: Binding(
            get: { Self.selection(level, in: model) },
            set: { choose($0) },
        )) {
            ForEach(items, id: \.tag) { Text($0.title).tag($0.tag) }
        }
        .labelsHidden()
        .controlSize(.small)
        .disabled(model.info?.isRaw != true || (model.lensProfileOptions ?? []).isEmpty)
        .help(Self.help(level, in: model))
    }

    private func choose(_ tag: String) {
        guard !tag.isEmpty, tag != Self.selection(level, in: model) else { return }
        switch level {
        case .make: model.chooseLensProfile(make: tag)
        case .model: model.chooseLensProfile(make: model.shownLensProfile?.make ?? "", model: tag)
        case .profile:
            if let option = model.lensProfileOptions?.first(where: { $0.fileName == tag }) {
                model.chooseLensProfile(option)
            }
        }
    }

    static func label(_ level: Level) -> String {
        switch level {
        case .make: "Make"
        case .model: "Model"
        case .profile: "Profile"
        }
    }

    static func help(_ level: Level, in model: EditorModel) -> String {
        guard !(model.lensProfileOptions ?? []).isEmpty else {
            return "No lens profile on this Mac fits this photo. Put LCP files in your Lens Profiles folder, or "
                + "install Lightroom Classic or Camera Raw"
        }
        return switch level {
        case .make: "The lens's maker"
        case .model: "The lens"
        case .profile: model.shownLensProfile.map { "\($0.fileName), in \($0.folder.name)" } ?? "The lens profile"
        }
    }
}
