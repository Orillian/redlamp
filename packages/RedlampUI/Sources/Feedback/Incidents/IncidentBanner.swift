import AppKit
import SwiftUI

/// Over the photo, a crash or a hang in an earlier session that the launch found and that hasn't been reported: what
/// happened and when, with Review Report…, which opens the report to be read before anything is sent, and Not Now,
/// after which it stays in Your Reports for 30 days. Develop shows it over the canvas, below a failed save's banner;
/// the Library, whose view covers the canvas, over the top of its photos, while no failed save or culling problem is
/// shown there.
struct IncidentBanner: View {
    let module: AppModule
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let history = model.incidentHistory, let pending = Self.offered(model, in: module) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.incident.headline)
                        .font(.system(size: 12, weight: .semibold))
                    Text(Self.detail(pending.incident))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Button("Review Report…") { model.sendFeedback(FeedbackPrefill(incident: pending)) }
                    .buttonStyle(.borderless)
                    .help("Opens the report, to read before you send it")
                    .automationIdentifier("incident.banner.review")
                Button("Not Now") { history.dismiss(pending.id) }
                    .buttonStyle(.borderless)
                    .help("Keeps it in Help › Your Reports for 30 days")
                    .automationIdentifier("incident.banner.notNow")
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .automationIdentifier("incident.banner")
        }
    }

    /// The crash or hang the banner offers in `module`, the one shown: in the Library, only while no failed save or
    /// culling problem is shown in its place.
    static func offered(_ model: EditorModel, in module: AppModule) -> PendingIncident? {
        guard model.module == module, module == .develop || model.saveError == nil && model.cullingProblem == nil
        else { return nil }
        return model.incidentHistory?.offeredIncident
    }

    /// "Today at 10:08. You can read the report before you send it."; a hang's says how long it lasted.
    static func detail(_ incident: Incident) -> String {
        let length = incident.kind == .hang ? incident.duration.map { ", for \(Incident.seconds($0))" } : nil
        return "\(when(incident.time))\(length ?? ""). You can read the report before you send it."
    }

    /// "Today at 10:08", "Yesterday at 22:14", "12 Oct 2026 at 09:30".
    static func when(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}

/// The banner in the Library module, in a view of its own over the top of the photos.
struct LibraryIncidentBanner: View {
    let model: EditorModel
    let theme: ThemeSettings

    var body: some View {
        IncidentBanner(module: .library)
            .id(theme.selection)
            .environment(model)
            .environment(theme)
            .tint(Theme.nativeTint)
    }

    /// The view the Library module lays out. On a small stage it's narrower than it would like to be, and its lines
    /// shorten.
    @MainActor static func view(model: EditorModel, theme: ThemeSettings) -> NSView {
        let view = NSHostingView(rootView: LibraryIncidentBanner(model: model, theme: theme).focusEffectDisabled())
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }
}
