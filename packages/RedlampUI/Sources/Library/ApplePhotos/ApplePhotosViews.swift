import AppKit
import RedlampDesign
import SwiftUI

/// What the Apple Photos window's pages ask of the window: the setup's boxes. Its buttons are AppKit's, in the bottom
/// bar.
struct ApplePhotosChoices {
    var choose: @MainActor (String, Bool) -> Void = { _, _ in }
    var includeHidden: @MainActor (Bool) -> Void = { _ in }
    var follow: @MainActor (Bool) -> Void = { _ in }
}

/// The screen the model last described, which the hosted views draw.
@MainActor @Observable
final class ApplePhotosScreenBox {
    var screen: ApplePhotosScreen

    init(screen: ApplePhotosScreen) {
        self.screen = screen
    }
}

/// The window's pages but the setup (LIB-54): access, a line while it reads or counts, the review, the import's
/// progress and how it ended.
struct ApplePhotosPageView: View {
    let shown: ApplePhotosScreenBox

    var body: some View {
        let screen = shown.screen
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                switch screen.page {
                case .access: ApplePhotosAccessView(screen: screen)
                case .working: working(screen)
                case .setup: EmptyView()
                case .review: ApplePhotosReviewView(screen: screen)
                case .progress: ApplePhotosProgressView(screen: screen)
                case .result: ApplePhotosResultView(screen: screen)
                }
                if let problem = screen.problem {
                    NoticeCard(problem, tone: .caution) { EmptyView() }
                        .accessibilityIdentifier("photos.problem")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    private func working(_ screen: ApplePhotosScreen) -> some View {
        LightroomSection("Apple Photos") {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(screen.heading)
                    .font(Typography.label.font)
                    .foregroundStyle(Theme.value)
            }
            ForEach(screen.message, id: \.self) { line in
                Text(line).font(Typography.caption.font).foregroundStyle(Theme.secondaryLabel)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The page's title, large, as the Lightroom window's result has it.
private struct ApplePhotosHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.panelTitle.font)
            .foregroundStyle(Theme.value)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("photos.heading")
            .accessibilityAddTraits(.isHeader)
    }
}

/// A card of lines, each on its own.
private struct ApplePhotosLines: View {
    let section: ApplePhotosScreen.Section

    var body: some View {
        LightroomSection(section.title) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(section.lines, id: \.self) { line in
                    Text(line)
                        .font(Typography.label.font)
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photos.section.\(section.id)")
    }
}

/// Before Redlamp may read Photos: what asking is for, or why there's no access and where it's given.
struct ApplePhotosAccessView: View {
    let screen: ApplePhotosScreen

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.secondaryLabel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                ApplePhotosHeading(text: screen.heading)
                ForEach(screen.message, id: \.self) { line in
                    Text(line)
                        .font(Typography.label.font)
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photos.access")
    }
}

/// The albums in their groups, each with its count and box, those kept in place In Library, and the import's own
/// choices below them while copying.
struct ApplePhotosAlbumsView: View {
    let shown: ApplePhotosScreenBox
    let actions: ApplePhotosChoices

    var body: some View {
        let screen = shown.screen
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                Text("From")
                    .font(.system(size: NSFont.smallSystemFontSize, weight: .semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                ForEach(screen.groups) { group in
                    LightroomSection(group.title) {
                        if let note = group.note {
                            Text(note)
                                .font(Typography.caption.font)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if group.albums.isEmpty {
                            Text("None in Photos")
                                .font(Typography.caption.font)
                                .foregroundStyle(Theme.tertiaryLabel)
                        }
                        ForEach(group.albums) { album in
                            HStack(spacing: 6) {
                                ApplePhotosCheckbox(
                                    title: album.title, check: album.check, identifier: "photos.album.\(album.id)",
                                    help: album.help, isEnabled: !album.isKept,
                                ) { actions.choose(album.id, $0) }
                                    .padding(.leading, CGFloat(album.depth) * 18)
                                Spacer(minLength: 8)
                                if album.isKept {
                                    Text("In Library")
                                        .font(Typography.caption.font)
                                        .foregroundStyle(Theme.tertiaryLabel)
                                }
                                if let count = album.count {
                                    Text(ProgressText.count(count))
                                        .font(Typography.value.font)
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text(screen.chosenLine)
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityIdentifier("photos.chosen")
                if screen.options {
                    ApplePhotosCheckbox(
                        title: "Include hidden photos", check: screen.includesHidden ? .on : .off,
                        identifier: "photos.hidden", help: "Photos’ Hidden album’s photos come too",
                    ) { actions.includeHidden($0) }
                    ApplePhotosCheckbox(
                        title: "Follow these albums", check: screen.follows ? .on : .off, identifier: "photos.follow",
                        help: "The Library panel’s From Apple Photos offers the new photos that arrive in them",
                    ) { actions.follow($0) }
                    Text("The Library panel offers the new photos that arrive in albums you follow.")
                        .font(Typography.caption.font)
                        .foregroundStyle(Theme.tertiaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

/// The report, before anything is copied.
struct ApplePhotosReviewView: View {
    let screen: ApplePhotosScreen

    var body: some View {
        ApplePhotosHeading(text: screen.heading)
        ForEach(screen.sections) { section in
            ApplePhotosLines(section: section)
        }
    }
}

/// The import while it runs: its stages, the photos done of those it takes, and iCloud's downloads.
struct ApplePhotosProgressView: View {
    let screen: ApplePhotosScreen

    var body: some View {
        StageRail(stages: screen.stages)
            .accessibilityIdentifier("photos.stages")
        if let progress = screen.progress {
            LightroomSection(progress.title) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ProgressText.count(progress.done))
                        .font(ProgressTypography.figure.font)
                        .foregroundStyle(Theme.value)
                    Text("of \(ProgressText.count(progress.total, "photo"))")
                        .font(Typography.label.font)
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer(minLength: 4)
                    Text("\(Int((progress.fraction * 100).rounded(.down)))%")
                        .font(ProgressTypography.figure.font)
                        .foregroundStyle(Theme.value)
                }
                .accessibilityHidden(true)
                PartsBar(fraction: progress.fraction, height: 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(progress.title)
                    .accessibilityValue("\(progress.done) of \(progress.total) photos")
                    .accessibilityIdentifier("photos.progress")
                ForEach(progress.lines, id: \.self) { line in
                    Text(line)
                        .font(Typography.label.font)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// How the import ended, or that it's taken back.
struct ApplePhotosResultView: View {
    let screen: ApplePhotosScreen

    var body: some View {
        if !screen.stages.isEmpty {
            StageRail(stages: screen.stages)
        }
        HStack(spacing: 8) {
            if screen.sections.isEmpty, screen.buttons.isEmpty {
                ProgressView().controlSize(.small)
            }
            ApplePhotosHeading(text: screen.heading)
        }
        ForEach(screen.sections) { section in
            ApplePhotosLines(section: section)
        }
    }
}

/// A checkbox that's AppKit's, carrying an identifier, which the window's tests and the regression suite find and
/// click through the window, as they do the bottom bar's buttons; a folder's shows a dash while some of its albums
/// are chosen, and an album kept in place already is dimmed.
struct ApplePhotosCheckbox: NSViewRepresentable {
    let title: String
    let check: ApplePhotosImportModel.Check
    let identifier: String
    var help: String?
    var isEnabled = true
    let action: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: title,
            target: context.coordinator,
            action: #selector(Coordinator.press),
        )
        button.allowsMixedState = true
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.state = switch check {
        case .on: .on
        case .off: .off
        case .mixed: .mixed
        }
        button.toolTip = help
        button.isEnabled = isEnabled
        button.setAccessibilityIdentifier(identifier)
        context.coordinator.action = action
        context.coordinator.check = check
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action, check: check)
    }

    final class Coordinator: NSObject {
        var action: @MainActor (Bool) -> Void
        var check: ApplePhotosImportModel.Check

        init(action: @escaping @MainActor (Bool) -> Void, check: ApplePhotosImportModel.Check) {
            self.action = action
            self.check = check
        }

        /// A box clicked while it's mixed or off chooses, and while it's on lets go, whatever state AppKit moved it to.
        @MainActor @objc func press(_: NSButton) {
            action(check != .on)
        }
    }
}
