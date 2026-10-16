import AppKit
import RedlampDesign
import SwiftUI

/// What the Lightroom import window's screens ask the window to do. Import, Stop and Undo Import aren't here: they
/// stay AppKit buttons in the window's bottom bar.
@_spi(Harness) public struct LightroomImportActions {
    /// Locate… or Allow Access… on a root folder, by its id in the report.
    public var root: @MainActor (Int64, LightroomImportScreen.Root.Action) -> Void
    /// Copy, with the text to put on the pasteboard.
    public var copy: @MainActor (String) -> Void
    /// Show beside the sidecars that couldn't be written, with their reason: the Finder shows their photos.
    public var showUnwritten: @MainActor (String) -> Void

    public init(
        root: @escaping @MainActor (Int64, LightroomImportScreen.Root.Action) -> Void = { _, _ in },
        copy: @escaping @MainActor (String) -> Void = { _ in },
        showUnwritten: @escaping @MainActor (String) -> Void = { _ in },
    ) {
        self.root = root
        self.copy = copy
        self.showUnwritten = showUnwritten
    }
}

/// The Lightroom import window's content above its bottom bar (LIB-52), drawn from `LightroomImportScreen`: Review
/// once the catalog is read, the import's progress while it runs, and how it ended, each with its Details.
@_spi(Harness) public struct LightroomImportView: View {
    /// Whether Details was left open, which it opens as from then on.
    public static let detailsOpenKey = "LightroomImportDetailsOpen"
    /// The content's size at the window's smallest, and as it opens; within the 700 points of CI's screen, with the
    /// title bar and the bottom bar.
    public static let minimumSize = CGSize(width: 600, height: 400)
    public static let idealSize = CGSize(width: 760, height: 560)

    let screen: LightroomImportScreen
    let actions: LightroomImportActions
    private let detailsOpen: Binding<Bool>?
    @AppStorage(LightroomImportView.detailsOpenKey) private var storedOpen = false

    public init(screen: LightroomImportScreen, actions: LightroomImportActions = LightroomImportActions()) {
        self.screen = screen
        self.actions = actions
        detailsOpen = nil
    }

    /// With Details open or closed as `detailsOpen` says, rather than as it was left: for the harness.
    public init(screen: LightroomImportScreen, actions: LightroomImportActions, detailsOpen: Binding<Bool>) {
        self.screen = screen
        self.actions = actions
        self.detailsOpen = detailsOpen
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                switch screen.screen {
                case .reading: LightroomImportReadingView(screen: screen)
                case .review: LightroomImportReviewView(screen: screen, actions: actions)
                case .importing: LightroomImportProgressView(screen: screen)
                case .result: LightroomImportResultView(screen: screen, actions: actions)
                }
                if screen.screen != .reading {
                    LightroomImportDetailsView(screen: screen, isOpen: detailsOpen ?? $storedOpen, copy: actions.copy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

/// While the catalog is read: the rail, and what reading does.
struct LightroomImportReadingView: View {
    let screen: LightroomImportScreen

    var body: some View {
        StageRail(stages: screen.stages)
        if let problem = screen.problem {
            LightroomSection("Couldn't read it") {
                Text("“\(screen.catalog)” couldn't be read: \(problem)")
                    .font(Typography.label.font)
                    .foregroundStyle(Theme.value)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lightroom.problem")
                Text("Choose… reads another catalog, or a copy of this one.")
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        } else {
            LightroomSection("Reading") {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading “\(screen.catalog)”: its photos, folders, keywords and collections.")
                        .font(Typography.label.font)
                        .foregroundStyle(Theme.value)
                }
                Text("It's read from a copy and never changed. Nothing is written until you import.")
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }
}

/// A small AppKit button in the screens, carrying an identifier: the window's tests and the regression suite find it
/// and click it through the window's views, as they do the bottom bar's buttons, which SwiftUI's own don't let them.
struct LightroomButton: NSViewRepresentable {
    let title: String
    let identifier: String
    var help: String?
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.toolTip = help
        button.setAccessibilityIdentifier(identifier)
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    final class Coordinator: NSObject {
        var action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        @MainActor @objc func press() {
            action()
        }
    }
}

/// A titled region of the screen, on a card.
struct LightroomSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Typography.section.font)
                .tracking(Typography.section.tracking)
                .foregroundStyle(Theme.tertiaryLabel)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(Metrics.panelCardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Metrics.panelCardRadius).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Metrics.panelCardRadius).strokeBorder(Theme.divider))
    }
}

/// A large figure with what it counts beneath it.
struct LightroomFigure: View {
    let figure: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(figure)
                .font(ProgressTypography.figure.font)
                .foregroundStyle(Theme.value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Typography.caption.font)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The log behind the picture, closed to its last line until opened, which it stays as from then on; Copy for a
/// report or a bug, and Report Text for the report's lines as the CLI prints them.
struct LightroomImportDetailsView: View {
    let screen: LightroomImportScreen
    @Binding var isOpen: Bool
    let copy: @MainActor (String) -> Void
    @State private var showsReport = false

    private var rows: [(time: String, text: String)] {
        if showsReport || screen.log.isEmpty {
            return screen.reportText.map { ("", $0) }
        }
        return screen.log.map { ($0.clockTime, $0.text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(Theme.secondaryLabel)
                    Text("Details")
                        .font(Typography.label.weight(.semibold).font)
                        .foregroundStyle(Theme.label)
                    if !isOpen, let last = screen.log.last {
                        Text("\(last.clockTime)  \(last.text)")
                            .font(Typography.caption.font)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
            .accessibilityValue(isOpen ? "open" : "closed")
            .accessibilityIdentifier("lightroom.details")
            if isOpen {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if !row.time.isEmpty {
                                    Text(row.time)
                                        .font(Typography.value.font)
                                        .foregroundStyle(Theme.tertiaryLabel)
                                }
                                Text(row.text)
                                    .font(Typography.caption.font)
                                    .foregroundStyle(Theme.label)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(minHeight: 70, maxHeight: 150)
                .background(RoundedRectangle(cornerRadius: Metrics.cardRadius).fill(Theme.well))
                HStack(spacing: 8) {
                    Button("Copy") {
                        copy(showsReport || screen.log.isEmpty
                            ? screen.reportText.joined(separator: "\n") : screen.logText)
                    }
                    if !screen.log.isEmpty, !screen.reportText.isEmpty {
                        Button(showsReport ? "Log" : "Report Text") { showsReport.toggle() }
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
