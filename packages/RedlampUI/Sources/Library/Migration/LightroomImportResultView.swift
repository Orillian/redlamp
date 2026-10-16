import RedlampDesign
import SwiftUI

/// How the import ended (done, stopped or failed) or is being taken back, each saying what the library now holds.
struct LightroomImportResultView: View {
    let screen: LightroomImportScreen
    let actions: LightroomImportActions

    var body: some View {
        if screen.run != nil, screen.phase != .undoing, screen.phase != .undone {
            StageRail(stages: screen.stages)
                .accessibilityIdentifier("lightroom.stages")
        }
        LightroomSection(screen.resultLabel) {
            Text(screen.resultTitle)
                .font(Typography.panelTitle.font)
                .foregroundStyle(Theme.value)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lightroom.result")
            if screen.phase == .undoing, let undoing = screen.result?.undoing {
                PartsBar(fraction: undoing.fraction, height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Taking back the import")
                    .accessibilityValue(
                        "\(ProgressText.count(undoing.done)) of \(ProgressText.count(undoing.total, "photo"))",
                    )
            }
            VStack(alignment: .leading, spacing: 3) {
                let marked = screen.resultLines.contains { $0.kind != .note }
                ForEach(screen.resultLines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if marked {
                            Image(systemName: line.kind == .unwritten ? "exclamationmark.triangle" : "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(line.kind == .unwritten ? Theme.secondaryLabel : Theme.label)
                                .frame(width: 12)
                                .opacity(line.kind == .note ? 0 : 1)
                                .accessibilityHidden(true)
                        }
                        Text(line.text)
                            .font(Typography.label.font)
                            .foregroundStyle(Theme.label)
                            .fixedSize(horizontal: false, vertical: true)
                        if line.kind == .unwritten {
                            Button("Show") { actions.showUnwritten() }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        if let notices = screen.run?.notices.filter({
            if case .disconnected = $0 {
                true
            } else {
                false
            }
        }),
            screen.phase == .failed, !notices.isEmpty {
            ForEach(notices, id: \.self) { notice in
                NoticeCard(notice.text, tone: .caution, symbol: "externaldrive.badge.xmark")
            }
        }
    }
}
