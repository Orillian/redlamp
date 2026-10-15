import AppKit
import SwiftUI

/// Stays until a save goes through: what wasn't saved, why, and a way to try again. Develop shows it over the canvas,
/// above a crash or a hang to report; the Library, whose view covers the canvas, over the top of its photos, above a
/// culling problem, where a crash or a hang waits until it's gone.
struct SaveErrorBanner: View {
    let module: AppModule
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let error = Self.shown(model, in: module) {
            HStack(spacing: 10) {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                if error.canRetry {
                    Button("Retry") { model.retrySave() }
                        .buttonStyle(.borderless)
                        .automationIdentifier("saving.banner.retry")
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([error.url]) }
                    .buttonStyle(.borderless)
                Button("Report…") {
                    model.sendFeedback(FeedbackPrefill(featureID: "saving.not-saved", message: error.message))
                }
                .buttonStyle(.borderless)
                .help("Report a Bug about edits not saving")
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .contain)
            .automationIdentifier("saving.banner")
        }
    }

    /// The failed save the banner shows in `module`, the one shown.
    static func shown(_ model: EditorModel, in module: AppModule) -> SaveError? {
        model.module == module ? model.saveError : nil
    }
}

/// The banner in the Library module, in a view of its own over the top of the photos.
struct LibrarySaveErrorBanner: View {
    let model: EditorModel
    let theme: ThemeSettings

    var body: some View {
        SaveErrorBanner(module: .library)
            .id(theme.selection)
            .environment(model)
            .environment(theme)
            .tint(Theme.nativeTint)
    }

    /// The view the Library module lays out. On a small stage it's narrower than it would like to be, and its message
    /// shortens.
    @MainActor static func view(model: EditorModel, theme: ThemeSettings) -> NSView {
        let view = NSHostingView(rootView: LibrarySaveErrorBanner(model: model, theme: theme).focusEffectDisabled())
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }
}
