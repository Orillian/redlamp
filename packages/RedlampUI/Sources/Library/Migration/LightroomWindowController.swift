import AppKit
import Observation
import RedlampDesign
import RedlampLibrary
import SwiftUI
import UniformTypeIdentifiers

/// File › Import from Lightroom Classic… (LIB-29): a window of its own that opens on what was found of Lightroom
/// Classic on this Mac (`LightroomSetupScreen`, EDT-34), then, for the catalog, shows the screens LIB-52 drew from the
/// model (`LightroomImportView`, from `LightroomImportModel.screen`): Review, with each root folder and Locate… for one
/// that moved, the import's progress with Stop, and how it ended, with Undo Import. Import, Stop, Undo Import, Import
/// Again and Done stay AppKit buttons in the window's bottom bar. There's one at a time: asking again brings it
/// forward. Closing it while it imports lets the import carry on.
@MainActor
public final class LightroomWindowController: NSWindowController, NSWindowDelegate {
    public nonisolated static let title = "Import from Lightroom Classic"
    /// The window open now.
    @_spi(Harness) public private(set) static var current: LightroomWindowController?
    /// The window's content as it opens, 628 points high with the title bar, and the window at its smallest: within
    /// the 700 points of height CI's screen leaves.
    static let openingSize = NSSize(width: 760, height: 600)
    static let minimumSize = NSSize(width: 600, height: 480)

    let model: LightroomImportModel
    let setup: LightroomSetupScreen
    private let catalogLabel = NSTextField(labelWithString: "No catalog chosen")
    private let chooseButton = NSButton(title: "Choose…", target: nil, action: nil)
    private let shown: LightroomImportScreenBox
    private let status = NSTextField(wrappingLabelWithString: "")
    /// The bottom bar's buttons by what they do, left to right as every screen lists them.
    private var buttons: [(kind: LightroomImportScreen.Button.Kind, button: NSButton)] = []
    /// Closed while it imported, which carries on: the window goes once it's done.
    private var closedWhileBusy = false

    init(model: LightroomImportModel, editor: EditorModel? = nil) {
        self.model = model
        setup = LightroomSetupScreen(editor: editor)
        shown = LightroomImportScreenBox(screen: model.screen)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.openingSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false,
        )
        window.title = Self.title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.minSize = Self.minimumSize
        window.delegate = self
        setup.install(in: self, catalog: makeContent())
        window.center()
        window.setFrameAutosaveName("LightroomImportWindow")
        if window.frame.width < Self.minimumSize.width || window.frame.height < Self.minimumSize.height {
            window.setFrame(NSRect(origin: window.frame.origin, size: Self.minimumSize), display: false)
        }
        model.onChange = { [weak self] in self?.changed() }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        let heading = NSTextField(labelWithString: "Catalog:")
        catalogLabel.lineBreakMode = .byTruncatingMiddle
        catalogLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        catalogLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        catalogLabel.setAccessibilityIdentifier("lightroom.catalog")
        chooseButton.target = self
        chooseButton.action = #selector(chooseCatalog)
        chooseButton.setAccessibilityIdentifier("lightroom.choose")
        let header = Self.row([setup.backButton, heading, catalogLabel, chooseButton], spacing: 8)

        let actions = LightroomImportActions(
            root: { [weak self] id, action in self?.root(id, action) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            showUnwritten: { [weak self] reason in self?.showUnwritten(reason) },
        )
        let hosting = NSHostingView(rootView: LightroomImportHost(shown: shown, actions: actions).focusEffectDisabled())
        hosting.sizingOptions = []
        hosting.setAccessibilityIdentifier("lightroom.screen")

        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.cell?.truncatesLastVisibleLine = true
        status.setAccessibilityIdentifier("lightroom.status")
        status.setContentHuggingPriority(.init(1), for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let kinds: [(LightroomImportScreen.Button.Kind, Selector, String)] = [
            (.undo, #selector(undoImport), "lightroom.undo"),
            (.stop, #selector(stopImport), "lightroom.stop"),
            (.importAgain, #selector(startImport), "lightroom.importAgain"),
            (.done, #selector(finish), "lightroom.done"),
            (.importPhotos, #selector(startImport), "lightroom.import"),
        ]
        buttons = kinds.map { kind, action, identifier in
            let button = NSButton(title: "", target: self, action: action)
            button.setAccessibilityIdentifier(identifier)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.isHidden = true
            return (kind, button)
        }
        buttons.first { $0.kind == .stop }?.button.toolTip = "Ends once the part being written is done"
        buttons.first { $0.kind == .done }?.button.toolTip = "Back to what Redlamp found of Lightroom Classic"
        let bar = Self.row([status] + buttons.map(\.button), spacing: 10)

        let line = NSBox()
        line.boxType = .separator
        let content = NSView()
        for view in [header, hosting, line, bar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            hosting.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.topAnchor.constraint(equalTo: hosting.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])
        return content
    }

    /// A row of views across its width, centred on one line, the one that hugs least taking what's left and
    /// truncating.
    private static func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = spacing
        return row
    }

    // MARK: - Showing

    /// Brings the window forward, making it first for `editor` when there's none.
    static func show(editor: EditorModel) {
        if let current {
            current.closedWhileBusy = false
            current.showWindow(nil)
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = LightroomWindowController(model: LightroomImportModel(editor: editor), editor: editor)
        current = controller
        controller.changed()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_: Notification) {
        guard Self.current === self else { return }
        if model.isBusy {
            closedWhileBusy = true
        } else {
            Self.current = nil
        }
    }

    // MARK: - The model

    private func changed() {
        catalogLabel.stringValue = model.catalogURL?.path ?? "No catalog chosen"
        chooseButton.isEnabled = !model.isBusy
        let screen = model.screen
        if shown.screen != screen {
            shown.screen = screen
        }
        status.stringValue = screen.barNote ?? ""
        for (kind, button) in buttons {
            guard let wanted = screen.buttons.first(where: { $0.kind == kind }) else {
                button.isHidden = true
                button.keyEquivalent = ""
                continue
            }
            button.title = wanted.title
            button.isEnabled = wanted.isEnabled
            button.keyEquivalent = wanted.isDefault ? "\r" : ""
            button.isHidden = false
        }
        buttons.first { $0.kind == .undo }?.button.toolTip = model.lastImport.map { record in
            "Takes back the import of \(LightroomImportModel.count(record.photos, "photo")) from "
                + "“\(URL(fileURLWithPath: record.catalog).deletingPathExtension().lastPathComponent)”, "
                + LightroomSetupScreen.day(record.date)
        }
        if closedWhileBusy, !model.isBusy, Self.current === self {
            Self.current = nil
        }
        if setup.screen == .setup {
            setup.refresh()
        }
    }

    // MARK: - Actions

    @objc private func chooseCatalog() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrcat") ?? .data]
        panel.prompt = "Choose"
        panel.message = "Choose a Lightroom Classic catalog, or a copy of one. It's read, never changed."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.choose(url)
        }
    }

    /// Locate… or Allow Access… on the root folder the report gives `id`.
    private func root(_ id: Int64, _ action: LightroomImportScreen.Root.Action) {
        guard let path = model.report?.roots.first(where: { $0.id == id })?.lightroomPath else { return }
        switch action {
        case .locate: locateRoot(path)
        case .allowAccess: allowAccess(path)
        }
    }

    private func locateRoot(_ path: String) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Locate"
        panel.message = "Where is this folder now? Lightroom Classic had it at \(path)."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.locate(path, at: url)
        }
    }

    /// A root Redlamp can't read, as each the App Sandbox wasn't given: its panel opens on it, and choosing it gives
    /// access to it, one root at a time.
    private func allowAccess(_ path: String) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Allow Access"
        panel.message = "Lightroom Classic's photos are in this folder. Choose it to let Redlamp read it."
        panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.locate(path, at: url)
        }
    }

    /// Show beside sidecars that couldn't be written: the Finder shows their photos, the first hundred of them.
    private func showUnwritten(_ reason: String) {
        let photos = model.unwrittenPhotos(reason)
        guard !photos.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(Array(photos.prefix(100)))
    }

    @objc private func startImport() {
        model.startImport()
    }

    @objc private func stopImport() {
        model.stop()
    }

    @objc private func undoImport() {
        model.undo()
    }

    /// Done: back to what was found of Lightroom Classic, whose cards now say what came across.
    @objc private func finish() {
        model.dismissResult()
        setup.show(.setup)
    }
}

/// The screen the model last described, which the hosted view draws.
@MainActor @Observable
final class LightroomImportScreenBox {
    var screen: LightroomImportScreen

    init(screen: LightroomImportScreen) {
        self.screen = screen
    }
}

/// The catalog's screens in the window, redrawn as the model changes.
struct LightroomImportHost: View {
    let shown: LightroomImportScreenBox
    let actions: LightroomImportActions

    var body: some View {
        LightroomImportView(screen: shown.screen, actions: actions)
    }
}

/// The File menu's Import from Lightroom Classic….
@MainActor
enum LightroomActions {
    /// Opens the window, or brings it forward; false while the library isn't open.
    @discardableResult
    static func open(model: EditorModel) -> Bool {
        guard model.library.service?.isReady == true else { return false }
        LightroomWindowController.show(editor: model)
        return true
    }
}
