import AppKit
import RedlampEngineAPI
import RedlampLibrary
import RedlampRecipes
import UniformTypeIdentifiers

/// The Lightroom Classic window's first screen (EDT-34): what was found of Lightroom Classic on this Mac, the catalog,
/// the presets in Camera Raw's Settings folder and the Adobe camera and lens profiles, each with how many and where,
/// and each brought across on its own. The catalog goes on to its report and import (`LightroomImportModel`), the
/// presets through EDT-11's import, and the profiles, which Redlamp reads where they are, are said to be in use, with
/// TON-51's Choose Camera Profiles… and Redlamp's Lens Profiles folder for more. Finding runs again whenever the
/// screen is shown or the window comes forward.
@MainActor
final class LightroomSetupScreen: NSObject {
    enum Screen {
        case setup, catalog
    }

    enum Part: String, CaseIterable {
        case catalog, presets
        case cameraProfiles = "camera-profiles"
        case lensProfiles = "lens-profiles"

        var title: String {
            switch self {
            case .catalog: "Catalog"
            case .presets: "Presets"
            case .cameraProfiles: "Camera Profiles"
            case .lensProfiles: "Lens Profiles"
            }
        }
    }

    enum PresetsImport {
        case importing
        /// `fromSettings` when the presets were those found in Camera Raw's Settings folder.
        case imported(RecipeImportSummary, fromSettings: Bool)
    }

    /// A part's lines: what was found, where, and what it's doing or how it's used.
    struct Lines: Equatable {
        var found: String
        var place = ""
        var state = ""
        /// The state is a problem, shown in red.
        var isProblem = false
    }

    private struct Section {
        var found: NSTextField
        var place: NSTextField
        var state: NSTextField
        var buttons: [String: NSButton]
    }

    private weak var editor: EditorModel?
    private weak var controller: LightroomWindowController?
    private(set) var screen = Screen.setup
    /// What was found the last time, nil until it's first found.
    private(set) var found: LightroomSetup?
    /// The catalog chosen on this screen, or the one the report reads, in place of the one found.
    private var chosenCatalog: LightroomSetup.Catalog?
    private(set) var presetsImport: PresetsImport?
    private var finding: Task<Void, Never>?
    private var findsAgain = false
    private var lastLooked: ContinuousClock.Instant?
    private var sections: [Part: Section] = [:]
    /// The catalog's report and import, the window's other screen.
    private(set) var catalogScreen: NSView?
    /// On the catalog's screen, before its Catalog:, back to this one.
    let backButton: NSButton
    private(set) lazy var view: NSView = makeView()

    init(editor: EditorModel?) {
        self.editor = editor
        backButton = NSButton(
            image: NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back") ?? NSImage(),
            target: nil, action: nil,
        )
        super.init()
        backButton.toolTip = "Back to what Redlamp found of Lightroom Classic"
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.setAccessibilityIdentifier("lightroom.back")
    }

    /// Where finding looks in place of this Mac's folders while it's set, as tests and the regression suite set it.
    static var locations: LightroomSetup.Locations?

    private var looksIn: LightroomSetup.Locations {
        Self.locations
            ?? .standard(chosenCameraProfiles: EditorModel.chosenCameraProfiles(in: editor?.library.defaults))
    }

    var shownCatalog: LightroomSetup.Catalog? {
        chosenCatalog ?? found?.catalog
    }

    var isImportingPresets: Bool {
        if case .importing = presetsImport {
            return true
        }
        return false
    }

    // MARK: - Screens

    /// Shows this screen in `controller`'s window, with `catalog`, the report's, to go on to.
    func install(in controller: LightroomWindowController, catalog: NSView) {
        self.controller = controller
        catalogScreen = catalog
        show(.setup)
    }

    func show(_ screen: Screen) {
        guard let window = controller?.window, let catalogScreen else { return }
        self.screen = screen
        let shown = screen == .setup ? view : catalogScreen
        if window.contentView !== shown {
            window.contentView = shown
        }
        if screen == .setup {
            followReport()
            refresh()
            find()
        }
    }

    /// Goes on to the catalog's report with `url`, read again unless it's the one the report has.
    func goOn(with url: URL) {
        guard let model = controller?.model else { return }
        show(.catalog)
        if model.catalogURL != url || model.phase == .choosing {
            model.choose(url)
        }
    }

    /// The report's catalog in place of the one found, once the report has one.
    private func followReport() {
        guard let url = controller?.model.catalogURL, url != shownCatalog?.url else { return }
        chosenCatalog = .at(url, source: .chosen)
    }

    @objc private func goBack() {
        show(.setup)
    }

    // MARK: - Finding

    /// Looks again, off the main thread; while it looks, another call looks once more after it.
    func find() {
        guard finding == nil else {
            findsAgain = true
            return
        }
        let locations = looksIn
        lastLooked = .now
        finding = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { LightroomSetup.find(locations) }.value
            guard let self else { return }
            finding = nil
            if self.found != found {
                self.found = found
                refresh()
            }
            if findsAgain {
                findsAgain = false
                find()
            }
        }
    }

    /// Looks again unless it looked under a second ago, as when the window opens and then becomes key.
    func findUnlessJustFound() {
        guard finding == nil, lastLooked.map({ .now - $0 > .seconds(1) }) ?? true else { return }
        find()
    }

    /// What the report's model says of the catalog shown here while it reads, imports or takes an import back, and
    /// whether it's a problem.
    private func reportStatus(of catalog: LightroomSetup.Catalog?) -> (text: String, isProblem: Bool)? {
        guard let model = controller?.model, let catalog, model.catalogURL == catalog.url,
              model.phase != .reported, model.phase != .choosing || model.problem != nil
        else { return nil }
        return (model.status, model.problem != nil)
    }

    /// Shows what was found and what's going on.
    func refresh() {
        guard !sections.isEmpty, let model = controller?.model else { return }
        let catalog = shownCatalog
        let lines: [Part: Lines] = [
            .catalog: Self.catalogLines(
                catalog, looking: found == nil && chosenCatalog == nil, status: reportStatus(of: catalog),
            ),
            .presets: Self.presetsLines(found, presetsImport),
            .cameraProfiles: Self.cameraProfileLines(found),
            .lensProfiles: Self.lensProfileLines(found),
        ]
        for (part, lines) in lines {
            guard let section = sections[part] else { continue }
            for (label, text) in [
                (section.found, lines.found),
                (section.place, lines.place),
                (section.state, lines.state),
            ] {
                label.stringValue = text
                label.toolTip = text.isEmpty ? nil : text
                label.isHidden = text.isEmpty
            }
            section.state.textColor = lines.isProblem ? .systemRed : .secondaryLabelColor
        }
        let catalogButtons = sections[.catalog]?.buttons
        catalogButtons?["choose"]?.isEnabled = !model.isBusy
        catalogButtons?["import"]?.isEnabled = catalog.map { !$0.isOpenInLightroom } ?? false
        let presetButtons = sections[.presets]?.buttons
        presetButtons?["choose"]?.isEnabled = editor != nil && !isImportingPresets
        presetButtons?["import"]?.isEnabled = editor != nil && !isImportingPresets && found?.presets.isEmpty == false
        if case .imported(_, fromSettings: true) = presetsImport {
            presetButtons?["import"]?.title = "Import Again"
        } else {
            presetButtons?["import"]?.title = "Import"
        }
        sections[.cameraProfiles]?.buttons["choose"]?.isEnabled = editor != nil
    }

    // MARK: - Actions

    @objc private func askForCatalog() {
        guard let window = controller?.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrcat") ?? .data]
        panel.prompt = "Choose"
        panel.message = "Choose a Lightroom Classic catalog, or a copy of one. It's read, never changed."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.chooseCatalog(url)
        }
    }

    /// Shows `url` in place of the catalog found, for Import… to go on with.
    func chooseCatalog(_ url: URL) {
        chosenCatalog = .at(url, source: .chosen)
        refresh()
    }

    @objc private func importCatalog() {
        guard let catalog = shownCatalog, !catalog.isOpenInLightroom else { return }
        goOn(with: catalog.url)
    }

    @objc private func importFoundPresets() {
        importPresets(found?.presets ?? [], fromSettings: true)
    }

    @objc private func choosePresets() {
        guard let window = controller?.window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [RecipeActions.presetType, .folder]
        panel.prompt = "Import"
        panel.message = "Choose Lightroom presets, or folders of them, to bring in as recipes."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.importPresets(panel.urls, fromSettings: false)
        }
    }

    /// Brings presets in as recipes through EDT-11's import, then shows its report over the window.
    func importPresets(_ urls: [URL], fromSettings: Bool) {
        guard let editor, !isImportingPresets, !urls.isEmpty else { return }
        presetsImport = .importing
        refresh()
        let files = editor.engine.files
        Task { [weak self] in
            let read = await RecipeActions.read(urls, tableSpace: .sRGB, files: files)
            guard let self, let editor = self.editor else { return }
            let summary = editor.recipes.install(read)
            editor.activity.record(.action, "Import from Lightroom Classic: \(summary.headline)")
            presetsImport = .imported(summary, fromSettings: fromSettings)
            refresh()
            RecipeActions.tell(summary, over: controller?.window)
        }
    }

    @objc private func chooseCameraProfiles() {
        guard let editor else { return }
        CameraProfileChooser.choose(model: editor, over: controller?.window) { [weak self] in self?.find() }
    }

    @objc private func openLensProfiles() {
        let folder = looksIn.lensProfiles
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Words

    static func catalogLines(
        _ catalog: LightroomSetup.Catalog?, looking: Bool, status: (text: String, isProblem: Bool)?,
    ) -> Lines {
        guard let catalog else {
            return Lines(found: looking ? "Looking…" : "No catalog found in Lightroom Classic's preferences or in "
                + "Pictures › Lightroom")
        }
        let name = catalog.url.lastPathComponent
        let found = switch catalog.source {
        case .lastUsed: "\(name), the catalog Lightroom Classic last used"
        case .pictures: "\(name), in Pictures › Lightroom"
        case .chosen: name
        }
        let place = [catalog.url.deletingLastPathComponent().path]
            + [catalog.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap(\.self)
            + [catalog.modified.map { "changed \($0.formatted(date: .abbreviated, time: .omitted))" }]
            .compactMap(\.self)
        if let status {
            return Lines(
                found: found, place: place.joined(separator: " · "), state: status.text, isProblem: status.isProblem,
            )
        }
        if catalog.isOpenInLightroom {
            let why = LightroomCatalogError.openInLightroom(catalog.url.path).description
            return Lines(
                found: found, place: place.joined(separator: " · "),
                state: why.prefix(1).uppercased() + why.dropFirst(), isProblem: true,
            )
        }
        return Lines(
            found: found, place: place.joined(separator: " · "),
            state: "Import… reports what would come across before anything is written. The catalog is read, never "
                + "changed.",
        )
    }

    static func presetsLines(_ found: LightroomSetup?, _ presetsImport: PresetsImport?) -> Lines {
        guard let found else { return Lines(found: "Looking…") }
        let folder = found.presetsFolder.path
        var lines = if !found.presetsReadable {
            Lines(found: "Redlamp can't read Camera Raw's Settings folder", place: folder)
        } else if found.presets.isEmpty {
            Lines(found: "No presets in Camera Raw's Settings folder")
        } else {
            Lines(
                found: "\(LightroomImportModel.count(found.presets.count, "preset")) in Camera Raw's Settings folder",
                place: folder,
                state: "Each becomes a recipe in the Recipes panel, with a report of how its settings came across.",
            )
        }
        switch presetsImport {
        case .importing:
            lines.state = "Importing the presets…"
        case let .imported(summary, _):
            let failed = summary.failures.count
            lines.state = summary.headline + (summary.placement.map { ". \($0)" } ?? "")
                + (failed == 0 ? "." : "; \(LightroomImportModel.count(failed, "file")) couldn't be imported.")
            lines.isProblem = summary.imported.isEmpty
        case nil:
            break
        }
        return lines
    }

    static func cameraProfileLines(_ found: LightroomSetup?) -> Lines {
        guard let found else { return Lines(found: "Looking…") }
        return profileLines(
            found.cameraProfiles,
            noun: "camera profile",
            none: "No Adobe camera profiles on this Mac",
        ) {
            switch $0 {
            case .cameraRaw: "where Lightroom Classic and Camera Raw install them"
            case .userCameraRaw: "in your Camera Raw folder"
            case .chosen, .redlamp: "in the files and folders you chose"
            }
        } inUse: { _ in
            "In use: Redlamp reads them where they are, on this Mac only, and lists each camera's in its photos' "
                + "Base Look menu."
        }
    }

    static func lensProfileLines(_ found: LightroomSetup?) -> Lines {
        guard let found else { return Lines(found: "Looking…") }
        return profileLines(found.lensProfiles, noun: "lens profile", none: "No lens profiles on this Mac") {
            switch $0 {
            case .cameraRaw: "in \(LensProfileFolder.cameraRaw.name)"
            case .userCameraRaw: "in \(LensProfileFolder.cameraRawUser.name)"
            case .redlamp, .chosen: "in \(LensProfileFolder.redlamp.name)"
            }
        } inUse: { places in
            "In use: Redlamp reads them where they are, on this Mac only."
                + (places.contains { $0.kind != .redlamp && $0.count > 0 }
                    ? " Edits from process 17 on use those in Camera Raw's folders too." : "")
        }
    }

    /// "1,310 camera profiles: 1,300 where … and 10 in …", the folders, and whether they're in use.
    private static func profileLines(
        _ places: [LightroomSetup.Place], noun: String, none: String,
        where phrase: (LightroomSetup.Place.Kind) -> String, inUse: ([LightroomSetup.Place]) -> String,
    ) -> Lines {
        let readable = places.filter { $0.isReadable && $0.count > 0 }
        let unreadable = places.filter { !$0.isReadable }.compactMap(\.folder)
        let total = readable.reduce(0) { $0 + $1.count }
        var lines = switch readable.count {
        case 0: Lines(found: none)
        case 1: Lines(found: "\(LightroomImportModel.count(total, noun)) \(phrase(readable[0].kind))")
        default: Lines(found: "\(LightroomImportModel.count(total, noun)): " + joined(readable.map {
                "\(LightroomImportModel.number($0.count)) \(phrase($0.kind))"
            }))
        }
        lines.place = readable.compactMap(\.folder?.path).joined(separator: " · ")
        if !unreadable.isEmpty {
            lines.state = "Redlamp can't read " + joined(unreadable.map(\.path))
            lines.isProblem = true
        } else if total > 0 {
            lines.state = inUse(readable)
        }
        return lines
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ words: [String]) -> String {
        guard let last = words.last, words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: - Views

    private func makeView() -> NSView {
        let intro = NSTextField(wrappingLabelWithString: "Redlamp looked for Lightroom Classic's catalog, presets and "
            + "Adobe profiles on this Mac. Each comes across on its own, and nothing of Lightroom's is changed.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        intro.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [intro]
        for part in Part.allCases {
            let line = NSBox()
            line.boxType = .separator
            views += [line, section(part)]
        }
        let content = NSStackView(views: views)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 12, right: 16)
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -32).isActive = true
        }
        content.setAccessibilityIdentifier("lightroom.setup")
        return content
    }

    /// A part's heading and lines beside its buttons.
    private func section(_ part: Part) -> NSView {
        let heading = NSTextField(labelWithString: part.title)
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let found = Self.label(NSFont.systemFontSize, .labelColor)
        let place = Self.label(NSFont.smallSystemFontSize, .secondaryLabelColor)
        place.lineBreakMode = .byTruncatingMiddle
        let state = NSTextField(wrappingLabelWithString: "")
        state.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        state.maximumNumberOfLines = 2
        state.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (label, line) in [(found, "found"), (place, "place"), (state, "state")] {
            label.setAccessibilityIdentifier("lightroom.setup.\(part.rawValue).\(line)")
        }
        let text = NSStackView(views: [heading, found, place, state])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(5, after: heading)
        text.setContentHuggingPriority(.init(1), for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [found, place, state] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(lessThanOrEqualTo: text.widthAnchor).isActive = true
        }

        let actions: [(String, String, Selector, String)] = switch part {
        case .catalog: [
                ("choose", "Choose…", #selector(askForCatalog), "Choose another Lightroom Classic catalog"),
                (
                    "import",
                    "Import…",
                    #selector(importCatalog),
                    "Shows what the catalog would bring across, then "
                        + "imports it",
                ),
            ]
        case .presets: [
                ("choose", "Choose…", #selector(choosePresets), "Choose other Lightroom presets to bring in"),
                ("import", "Import", #selector(importFoundPresets), "Brings these presets in as recipes"),
            ]
        case .cameraProfiles: [
                (
                    "choose",
                    "Choose Camera Profiles…",
                    #selector(chooseCameraProfiles),
                    "Adobe camera profiles "
                        + "(.dcp) and profiles (.xmp) from anywhere on this Mac, read where they are",
                ),
            ]
        case .lensProfiles: [
                (
                    "open",
                    "Open Lens Profiles Folder",
                    #selector(openLensProfiles),
                    "Lens profiles you put in Redlamp's "
                        + "Lens Profiles folder are used on this Mac",
                ),
            ]
        }
        var buttons: [String: NSButton] = [:]
        for (identifier, title, action, help) in actions {
            let button = NSButton(title: title, target: self, action: action)
            button.toolTip = help
            button.setAccessibilityIdentifier("lightroom.setup.\(part.rawValue).\(identifier)")
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            buttons[identifier] = button
        }
        let row = NSStackView(views: [text] + actions.compactMap { buttons[$0.0] })
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.setCustomSpacing(16, after: text)
        row.setAccessibilityIdentifier("lightroom.setup.\(part.rawValue)")
        sections[part] = Section(found: found, place: place, state: state, buttons: buttons)
        return row
    }

    private static func label(_ size: CGFloat, _ color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

public extension LightroomWindowController {
    /// The first screen finds again as the window comes forward: the photographer may have installed Lightroom,
    /// or put lens profiles in the folder it opened.
    @objc func windowDidBecomeKey(_: Notification) {
        if setup.screen == .setup {
            setup.findUnlessJustFound()
        }
    }
}
