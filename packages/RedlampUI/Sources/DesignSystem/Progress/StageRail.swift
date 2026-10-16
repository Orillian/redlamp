import RedlampDesign
import SwiftUI

/// A stage of long work, as the stage rail shows it.
@_spi(Harness) public struct ProgressStage: Sendable, Hashable, Identifiable {
    public enum State: String, Sendable, Hashable {
        case done, now, next
        /// Where the work stopped or failed.
        case stopped

        var word: String {
            switch self {
            case .done: "done"
            case .now: "under way"
            case .next: "to come"
            case .stopped: "stopped"
            }
        }
    }

    public var id: String
    public var title: String
    public var detail: String
    public var state: State

    public init(id: String, title: String, detail: String, state: State) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

/// The stages of long work left to right, each done, under way or to come, with a line of detail: where the work is,
/// at a glance.
struct StageRail: View {
    let stages: [ProgressStage]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(stages) { stage in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(color(stage.state))
                        .frame(height: 3)
                    HStack(spacing: 5) {
                        Image(systemName: glyph(stage.state))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(stage.state == .now ? Theme.accent : Theme.secondaryLabel)
                        Text(stage.title)
                            .font(stage.state == .now ? Typography.label.weight(.semibold).font : Typography.label.font)
                            .foregroundStyle(stage.state == .next ? Theme.secondaryLabel : Theme.value)
                            .lineLimit(1)
                    }
                    Text(stage.detail.isEmpty ? " " : stage.detail)
                        .font(Typography.caption.font)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stage.title)
                .accessibilityValue(stage.detail.isEmpty ? stage.state.word : "\(stage.state.word): \(stage.detail)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stages")
    }

    private func color(_ state: ProgressStage.State) -> Color {
        switch state {
        case .done: Theme.trackFill
        case .now: Theme.accent
        case .next: Theme.track
        case .stopped: Theme.secondaryLabel
        }
    }

    private func glyph(_ state: ProgressStage.State) -> String {
        switch state {
        case .done: "checkmark.circle.fill"
        case .now: "circle.inset.filled"
        case .next: "circle"
        case .stopped: "stop.circle.fill"
        }
    }
}
