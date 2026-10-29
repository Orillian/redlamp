import AppKit
import RedlampDesign
import RedlampLibrary
import SwiftUI

/// Copy to Folder… for photos kept in Apple Photos (LIB-63): a window of its own, drawn from the Apple Photos
/// window's parts, that shows what's chosen beside To (the card import's own column,
/// `ImportDestinationViewController`), then the copy's progress with Stop, and how it ended, with Show in Library and
/// Undo Copy. Its buttons are AppKit buttons in the bottom bar. There's one at a time: asking again while it copies
/// brings it forward, and otherwise it shows what was asked for now. Closing it while it copies lets the copy carry
/// on.
@MainActor
public final class ApplePhotosCopyWindowController: NSWindowController, NSWindowDelegate {
    public nonisolated static let title = "Copy to Folder"
    /// The window open now.
    @_spi(Harness) public private(set) static var current: ApplePhotosCopyWindowController?
    /// Where To's settings are kept: Import's, but in tests, which keep their own.
    @_spi(Harness) public static var preferences = ImportPreferences.shared

    let model: ApplePhotosCopyModel
    let destinationView: ImportDestinationViewController
    private let shown: ApplePhotosScreenBox
    private let chosen: ApplePhotosScreenBox
    private let pages = NSView()
    private var pageView: NSView?
    private var setupView: NSView?
    private let status = NSTextField(wrappingLabelWithString: "")
    private var buttons: [(kind: ApplePhotosCopyScreen.Button.Kind, button: NSButton)] = []
    /// Closed while it copied, which carries on: the window goes once it's done.
    private var closedWhileBusy = false

    init(model: ApplePhotosCopyModel) {
        self.model = model
        destinationView = ImportDestinationViewController(
            model: model.destination, showsCard: false, noExample: "Counting what’s chosen…",
        )
        let screen = model.screen
        shown = ApplePhotosScreenBox(screen: screen.page)
        chosen = ApplePhotosScreenBox(screen: screen.chosen)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ApplePhotosWindowController.openingSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false,
        )
        window.title = Self.title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.minSize = ApplePhotosWindowController.minimumSize
        window.delegate = self
        window.contentView = makeContent()
        window.center()
        window.setFrameAutosaveName("ApplePhotosCopyWindow")
        let smallest = ApplePhotosWindowController.minimumSize
        if window.frame.width < smallest.width || window.frame.height < smallest.height {
            window.setFrame(NSRect(origin: window.frame.origin, size: smallest), display: false)
        }
        model.onChange = { [weak self] in self?.changed() }
        model.destination.onChange = { [weak self] change in self?.destinationView.modelChanged(change) }
        destinationView.onChooseFolder = { [weak self] backup in self?.askForFolder(backup: backup) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        let page = NSHostingView(rootView: ApplePhotosPageView(shown: shown).focusEffectDisabled())
        page.sizingOptions = []
        page.setAccessibilityIdentifier("copy.page")
        pageView = page

        let what = NSHostingView(rootView: ApplePhotosPageView(shown: chosen).focusEffectDisabled())
        what.sizingOptions = []
        what.setAccessibilityIdentifier("copy.chosen")
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(what)
        split.addArrangedSubview(destinationView.view)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        what.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        destinationView.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        setupView = split

        for view in [page, split] {
            view.translatesAutoresizingMaskIntoConstraints = false
            pages.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: pages.topAnchor),
                view.bottomAnchor.constraint(equalTo: pages.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: pages.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: pages.trailingAnchor),
            ])
        }

        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.cell?.truncatesLastVisibleLine = true
        status.setAccessibilityIdentifier("copy.status")
        status.setContentHuggingPriority(.init(1), for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttons = ApplePhotosCopyScreen.Button.Kind.allCases.map { kind in
            let button = NSButton(title: "", target: self, action: #selector(pressed(_:)))
            button.setAccessibilityIdentifier("copy." + kind.rawValue)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.isHidden = true
            return (kind, button)
        }
        buttons.first { $0.kind == .stop }?.button.toolTip = "Ends once the photos being copied are done"
        buttons.first { $0.kind == .undo }?.button.toolTip =
            "Moves the copies to the Trash, and lists the photos kept in Apple Photos again"
        let bar = NSStackView(views: [status] + buttons.map(\.button))
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 10

        let line = NSBox()
        line.boxType = .separator
        let content = NSView()
        for view in [pages, line, bar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            pages.topAnchor.constraint(equalTo: content.topAnchor),
            pages.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.topAnchor.constraint(equalTo: pages.bottomAnchor),
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

    // MARK: - Showing

    /// Shows the window copying what `request` asks, for `editor`; one copying already is brought forward instead.
    static func show(editor: EditorModel, request: ApplePhotosCopyModel.Request) {
        if let current {
            guard !current.model.isRunning else {
                current.closedWhileBusy = false
                current.showWindow(nil)
                current.window?.makeKeyAndOrderFront(nil)
                return
            }
            current.close()
        }
        Task {
            let library = await ImportActions.library(of: editor)
            let service = editor.library.service
            let model = ApplePhotosCopyModel(
                photos: ApplePhotosSource.library, library: library, originals: service?.originals,
                indexer: service?.applePhotosIndexer, request: request, editor: editor, preferences: preferences,
            )
            let controller = ApplePhotosCopyWindowController(model: model)
            current?.close()
            current = controller
            model.start()
            controller.changed()
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Presets made in Library's Metadata panel meanwhile.
    public func windowDidBecomeKey(_: Notification) {
        Task { await model.destination.readPresets() }
    }

    public func windowWillClose(_: Notification) {
        guard Self.current === self else { return }
        if model.isRunning {
            closedWhileBusy = true
        } else {
            model.close()
            Self.current = nil
        }
    }

    // MARK: - The model

    private func changed() {
        let screen = model.screen
        if shown.screen != screen.page {
            shown.screen = screen.page
        }
        if chosen.screen != screen.chosen {
            chosen.screen = screen.chosen
        }
        let setup = screen.page.page == .setup
        pageView?.isHidden = setup
        setupView?.isHidden = !setup
        status.stringValue = screen.barNote
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
        if setup {
            destinationView.modelChanged(.settings)
        }
        if closedWhileBusy, !model.isRunning, Self.current === self {
            model.close()
            Self.current = nil
        }
    }

    // MARK: - Actions

    @objc private func pressed(_ sender: NSButton) {
        guard let kind = buttons.first(where: { $0.button === sender })?.kind else { return }
        press(kind)
    }

    /// What the bottom bar's button `kind` does.
    func press(_ kind: ApplePhotosCopyScreen.Button.Kind) {
        switch kind {
        case .copy:
            guard model.destination.hasDestination else {
                askForFolder(backup: false) { [weak self] in self?.model.copy() }
                return
            }
            model.copy()
        case .stop: model.stop()
        case .resume: model.resume()
        case .undo: model.undo()
        case .showInLibrary: model.showInLibrary()
        case .done: close()
        }
    }

    /// The destination's or the backup's panel; `chosen` runs once one is chosen.
    private func askForFolder(backup: Bool, then chosen: @escaping @MainActor () -> Void = {}) {
        guard let window else { return }
        let destination = model.destination
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = backup ? "Choose where the backup copies go." : "Choose where the photos are copied to."
        panel.directoryURL = backup ? destination.settings.backup : destination.settings.destination
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                self?.destinationView.modelChanged(.settings)
                return
            }
            if backup {
                destination.setBackup(url)
            } else {
                destination.setDestination(url)
            }
            chosen()
        }
    }
}

/// What the harness, the tests and the regression suite set and read in the Copy to Folder window (LIB-63).
@_spi(Harness) public extension ApplePhotosCopyWindowController {
    /// To's destination and backup, as their panels give them, and the templates as they're typed.
    func prepare(destination: URL, backup: URL? = nil, folders: String, names: String) {
        let to = model.destination
        to.setDestination(destination)
        to.setBackup(backup)
        to.setFolders(folders)
        to.setNames(names)
    }

    /// What the bottom bar's button `kind` does, as a click on it does: `copy`, `undo`, `done`…
    func press(named kind: String) {
        if let kind = ApplePhotosCopyScreen.Button.Kind(rawValue: kind) {
            press(kind)
        }
    }

    /// Where the window is: `counting`, `choosing`, `copying`, `copied`, `undone` and the rest.
    var phase: String {
        "\(model.phase)"
    }

    /// The photos Copy copies, by their assets' local identifiers.
    var assets: [String] {
        model.request.assets
    }

    /// What's chosen, as the census counted it.
    var report: ApplePhotosReport? {
        model.census?.report
    }

    var outcome: ApplePhotosImport.Outcome? {
        model.outcome
    }

    /// Where Undo Copy moved the copies in the Trash.
    var trashed: [String] {
        model.undone?.rollbacks.flatMap(\.trashed).map(\.to) ?? []
    }

    /// What went wrong last, in words.
    var problem: String? {
        model.problem
    }

    /// The folder Copy copies to.
    var destination: URL {
        model.destination.settings.destination
    }

    /// The bottom bar's line, and the page's heading.
    var barNote: String {
        model.screen.barNote
    }

    var heading: String {
        let screen = model.screen
        return screen.page.page == .setup ? screen.chosen.heading : screen.page.heading
    }

    /// The title of the bottom bar's button carrying `identifier` (`copy.copy`, `copy.undo`…), and whether it's shown
    /// and enabled.
    func control(_ identifier: String) -> (title: String, shown: Bool, enabled: Bool)? {
        guard let button = buttons.first(where: { $0.button.accessibilityIdentifier() == identifier })?.button else {
            return nil
        }
        return (button.title, button.window != nil && !button.isHiddenOrHasHiddenAncestor, button.isEnabled)
    }
}
