import AppKit
import RedlampDesign
import RedlampLibrary
import SwiftUI

/// File › Import from Apple Photos… (LIB-54): a window of its own that asks, the first time, whether Redlamp may read
/// Photos, then shows Photos' albums beside To (the card import's own column, `ImportDestinationViewController`), the
/// report Review makes before anything is copied, the import's progress with Stop, and how it ended, with Show in
/// Library and Undo Import. Its pages are drawn from the model (`ApplePhotosScreen`); their buttons stay AppKit
/// buttons in the window's bottom bar. There's one at a time: asking again brings it forward. Closing it while it
/// imports lets the import carry on.
@MainActor
public final class ApplePhotosWindowController: NSWindowController, NSWindowDelegate {
    public nonisolated static let title = "Import from Apple Photos"
    /// The window open now.
    @_spi(Harness) public private(set) static var current: ApplePhotosWindowController?
    /// The window as it opens, and at its smallest: within the 700 points of height CI's screen leaves.
    static let openingSize = NSSize(width: 900, height: 600)
    static let minimumSize = NSSize(width: 720, height: 480)

    let model: ApplePhotosImportModel
    let destinationView: ImportDestinationViewController
    private let shown: ApplePhotosScreenBox
    private let pages = NSView()
    private var pageView: NSView?
    private var setupView: NSView?
    private let status = NSTextField(wrappingLabelWithString: "")
    private var buttons: [(kind: ApplePhotosScreen.Button.Kind, button: NSButton)] = []
    /// Closed while it imported, which carries on: the window goes once it's done.
    private var closedWhileBusy = false

    init(model: ApplePhotosImportModel) {
        self.model = model
        destinationView = ImportDestinationViewController(
            model: model.destination, showsCard: false, noExample: "Choose an album to see where its photos go.",
        )
        shown = ApplePhotosScreenBox(screen: model.screen)
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
        window.contentView = makeContent()
        window.center()
        window.setFrameAutosaveName("ApplePhotosImportWindow")
        if window.frame.width < Self.minimumSize.width || window.frame.height < Self.minimumSize.height {
            window.setFrame(NSRect(origin: window.frame.origin, size: Self.minimumSize), display: false)
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
        page.setAccessibilityIdentifier("photos.page")
        pageView = page

        let actions = ApplePhotosChoices(
            choose: { [weak self] id, on in self?.model.choose(id, on) },
            includeHidden: { [weak self] in self?.model.setIncludesHidden($0) },
            follow: { [weak self] in self?.model.setFollows($0) },
        )
        let albums = NSHostingView(rootView: ApplePhotosAlbumsView(shown: shown, actions: actions)
            .focusEffectDisabled())
        albums.sizingOptions = []
        albums.setAccessibilityIdentifier("photos.albums")
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(albums)
        split.addArrangedSubview(destinationView.view)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        albums.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
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
        status.setAccessibilityIdentifier("photos.status")
        status.setContentHuggingPriority(.init(1), for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttons = ApplePhotosScreen.Button.Kind.allCases.map { kind in
            let button = NSButton(title: "", target: self, action: #selector(pressed(_:)))
            button.setAccessibilityIdentifier("photos." + kind.rawValue)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.isHidden = true
            return (kind, button)
        }
        buttons.first { $0.kind == .stop }?.button.toolTip = "Ends once the photos being copied are done"
        buttons.first { $0.kind == .undo }?.button.toolTip =
            "Moves the import's copies to the Trash and takes them out of the library"
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

    /// Brings the window forward, making it first for `editor` when there's none; `then` runs with it once it shows.
    static func show(
        editor: EditorModel, importing news: (settings: ApplePhotosImport.Settings, census: ApplePhotosCensus)? = nil,
    ) {
        if let current {
            current.closedWhileBusy = false
            if let news {
                current.model.importNew(news.settings, census: news.census)
            }
            current.showWindow(nil)
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        Task {
            let library = await ImportActions.library(of: editor)
            guard current == nil else {
                show(editor: editor, importing: news)
                return
            }
            let model = ApplePhotosImportModel(photos: ApplePhotosSource.library, library: library, editor: editor)
            let controller = ApplePhotosWindowController(model: model)
            current = controller
            model.start(importing: news)
            controller.changed()
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Access may have been given in System Settings meanwhile, and presets made in Library's Metadata panel.
    public func windowDidBecomeKey(_: Notification) {
        model.checkAccess()
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
        if shown.screen != screen {
            shown.screen = screen
        }
        let setup = screen.page == .setup
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
        if model.phase == .choosing || model.phase == .reviewing {
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
    func press(_ kind: ApplePhotosScreen.Button.Kind) {
        switch kind {
        case .back: model.back()
        case .allow: model.askForAccess()
        case .openSettings: ApplePhotosSource.openPrivacySettings()
        case .review:
            guard model.destination.hasDestination else {
                askForFolder(backup: false) { [weak self] in self?.model.review() }
                return
            }
            model.review()
        case .importPhotos: model.startImport()
        case .stop: model.stop()
        case .resume: model.resume()
        case .undo: model.undo()
        case .showInLibrary: model.showInLibrary()
        case .done: model.done()
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

/// File › Import from Apple Photos…, and the Library panel's From Apple Photos (LIB-55).
@MainActor
public enum ApplePhotosActions {
    /// Opens the window, or brings it forward; false while the library isn't open.
    @discardableResult
    static func open(model: EditorModel) -> Bool {
        guard model.library.service?.isReady == true else { return false }
        ApplePhotosWindowController.show(editor: model)
        return true
    }

    /// From Apple Photos' Import: the new photos in the albums followed, imported with the last import's settings in
    /// the window, which shows its progress.
    static func importNew(model: EditorModel) {
        guard let news = model.applePhotosFollower.news, news.census.report.photos > 0 else { return }
        ApplePhotosWindowController.show(editor: model, importing: news)
    }

    /// From launch: counts the albums followed, and follows Photos' changes to them and to the albums kept in place.
    public static func start(model: EditorModel) {
        model.applePhotosFollower.start()
        model.library.service?.followApplePhotos(ApplePhotosSource.library)
    }

    /// Show in Photos, for an album or a photo kept in place (LIB-62): it opens Photos, which PhotoKit can't ask to
    /// show one album or one photo.
    static func showInPhotos() {
        openPhotos()
    }

    /// Opens Photos: the regression suite and the tests count the openings instead.
    @_spi(Harness) public static var openPhotos: @MainActor () -> Void = {
        guard let photos = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos")
        else { return }
        NSWorkspace.shared.openApplication(
            at: photos, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil,
        )
    }
}
