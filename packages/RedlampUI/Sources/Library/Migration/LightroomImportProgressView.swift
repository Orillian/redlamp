import RedlampDesign
import SwiftUI

/// The import while it runs: the stages, how far, how fast and how long; photos a second; done, now and next; each
/// root folder's progress on its disk; and why when it's slow or paused.
struct LightroomImportProgressView: View {
    let screen: LightroomImportScreen

    var body: some View {
        StageRail(stages: screen.stages)
            .accessibilityIdentifier("lightroom.stages")
        if let run = screen.run {
            HStack(alignment: .top, spacing: 10) {
                progress
                LightroomSection("Photos a second") {
                    ThroughputChart(bins: run.throughput)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Photos a second")
                        .accessibilityValue(screen.throughputAccessibilityValue)
                    Text(screen.throughputCaption)
                        .font(Typography.caption.font)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 30)
                }
                .frame(width: 230)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let lines = screen.doneNowNext {
                LightroomSection("Done · now · next") {
                    HStack(alignment: .top, spacing: 10) {
                        column("Done", lines.done)
                        column("Now", lines.now)
                        column("Next", lines.next)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                if !run.roots.isEmpty {
                    folders(run)
                }
                if !run.notices.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(run.notices, id: \.self) { notice in
                            NoticeCard(notice.text, tone: notice.isCaution ? .caution : .info, symbol: symbol(notice))
                        }
                    }
                    .frame(maxWidth: run.roots.isEmpty ? .infinity : 230)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progress: some View {
        LightroomSection(screen.progressTitle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let figure = screen.progressFigure {
                    Text(figure.figure)
                        .font(ProgressTypography.figure.font)
                        .foregroundStyle(Theme.value)
                    Text(figure.label)
                        .font(Typography.label.font)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(screen.progressPercent)
                    .font(ProgressTypography.figure.font)
                    .foregroundStyle(Theme.value)
            }
            .accessibilityHidden(true)
            PartsBar(fraction: screen.progressFraction, parts: screen.progressParts, height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(screen.progressTitle)
                .accessibilityValue(screen.progressAccessibilityValue)
                .accessibilityIdentifier("lightroom.progress")
            HStack(spacing: 12) {
                ForEach(Array(screen.paceLine.enumerated()), id: \.offset) { index, part in
                    Text(part)
                        .font(Typography.label.font)
                        .foregroundStyle(index == screen.paceLine.count - 1 ? Theme.secondaryLabel : Theme.value)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func column(_ title: String, _ line: LightroomImportScreen.Line) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.label.weight(.semibold).font)
                .foregroundStyle(Theme.label)
            Text(line.title)
                .font(Typography.label.font)
                .foregroundStyle(Theme.value)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = line.detail {
                Text(detail)
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func folders(_ run: LightroomImportScreen.Run) -> some View {
        LightroomSection("Folders") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach(run.roots) { root in
                    GridRow {
                        Text(root.name)
                            .font(Typography.label.font)
                            .foregroundStyle(root.state == .waiting ? Theme.secondaryLabel : Theme.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PartsBar(
                            fraction: root.count.fraction, height: 4,
                            fill: root.state == .done ? Theme.trackFill : Theme.accent,
                        )
                        .frame(width: 80)
                        HStack(spacing: 4) {
                            Text(root.label)
                                .font(Typography.value.font)
                                .foregroundStyle(Theme.secondaryLabel)
                                .lineLimit(1)
                            if root.state == .done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(root.name)
                    .accessibilityValue(root.accessibilityValue)
                }
            }
            let disks = Array(Set(run.roots.compactMap(\.disk))).sorted { $0.name < $1.name }
            if !disks.isEmpty {
                Text(disks.map(\.described).joined(separator: " · "))
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private func symbol(_ notice: LightroomImportScreen.Notice) -> String? {
        switch notice {
        case .paused(.lowPower): "battery.25percent"
        case .paused(.heat): "thermometer.medium"
        case .spinning: "internaldrive"
        case .disconnected: "externaldrive.badge.xmark"
        case .unwritten: nil
        }
    }
}
