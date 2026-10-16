import AppKit
import RedlampEngineAPI
import RedlampLibrary
import RedlampRecipes
import UniformTypeIdentifiers

/// The Lightroom Classic window's first screen (EDT-34), as LIB-52's wireframes draw it: a card each for what was
/// found of Lightroom Classic on this Mac, the catalog, the presets in Camera Raw's Settings folder and the Adobe
/// camera and lens profiles, each with how many and where, and each brought across on its own. The catalog's
/// Review… goes on to its report and import (`LightroomImportModel`), Import Presets brings the presets in through
/// EDT-11's import, and the profiles, which Redlamp reads where they are, are said to be used on this Mac only, with
/// TON-51's Choose Camera Profiles… and Redlamp's Lens Profiles folder for more. Finding runs again whenever the
/// screen is shown or the window comes forward, and the catalog shown is then read, never changed, for its photos
/// and root folders.
@MainActor
final class LightroomSetupScreen: NSObject {
    enum Screen {
        case setup, catalog
    }

    enum Part: String, CaseIterable {
        case catalog, presets, profiles

        var title: String {
            switch self {
            case .catalog: "Catalog"
            case .presets: "Presets"
            case .profiles: "Profiles"
            }
        }
    }

    enum PresetsImport {
        case importing
        case imported(RecipeImportSummary)
    }

    /// What the catalog shown holds, as its card counts it.
    enum Contents: Equatable {
        case reading
        case read(photos: Int, roots: Int)
        /// Why it couldn't be read.
        case unreadable(String)
    }

    /// A card's lines: how many, what was found, where, and what it's doing or how it's used.
    struct Lines: Equatable {
        /// Shown large; empty when there's nothing to count.
        var count = ""
        var found: String
        var place = ""
        var state = ""
        /// The state is a problem, shown in red.
        var isProblem = false
        /// Where each was found and how it's used, in full: the help of the lines above the state.
        var detail = ""
    }

    private struct Section {
        var count: NSTextField
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
    /// What was read of a catalog, and that catalog as it was found when it was read.
    private var contents: (catalog: LightroomSetup.Catalog, contents: Contents)?
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

    /// What was read of `catalog` as it is now: by this screen, or by the report's model for its report.
    private func contents(of catalog: LightroomSetup.Catalog?) -> Contents? {
        guard let catalog else { return nil }
        if let contents, contents.catalog == catalog {
            return contents.contents
        }
        if let read = controller?.model.catalog, read.url == catalog.url {
            return .read(photos: read.photos.count, roots: read.roots.count)
        }
        return nil
    }

    /// Reads the catalog shown for its photos and root folders, off the main thread, unless it was read as it is
    /// now; one Lightroom Classic has open isn't read.
    private func readCatalog() {
        guard let catalog = shownCatalog, !catalog.isOpenInLightroom, contents(of: catalog) == nil else { return }
        contents = (catalog, .reading)
        let url = catalog.url
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> Contents in
                do {
                    let read = try LightroomCatalog.read(url)
                    return .read(photos: read.photos.count, roots: read.roots.count)
                } catch {
                    return .unreadable(String(describing: error))
                }
            }.value
            guard let self, contents?.catalog == catalog else { return }
            contents = (catalog, read)
            refresh()
        }
    }

    /// Shows what was found and what's going on.
    func refresh() {
        guard !sections.isEmpty, let model = controller?.model else { return }
        readCatalog()
        let catalog = shownCatalog
        let lines: [Part: Lines] = [
            .catalog: Self.catalogLines(
                catalog, looking: found == nil && chosenCatalog == nil, contents: contents(of: catalog),
                status: reportStatus(of: catalog),
            ),
            .presets: Self.presetsLines(found, presetsImport),
            .profiles: Self.profilesLines(found),
        ]
        for (part, lines) in lines {
            guard let section = sections[part] else { continue }
            for (label, text) in [
                (section.count, lines.count),
                (section.found, lines.found),
                (section.place, lines.place),
                (section.state, lines.state),
            ] {
                let help = label === section.state || lines.detail.isEmpty ? text : lines.detail
                label.stringValue = text
                label.toolTip = text.isEmpty ? nil : help
                label.isHidden = text.isEmpty
            }
            section.state.textColor = lines.isProblem ? .systemRed : .secondaryLabelColor
        }
        let catalogButtons = sections[.catalog]?.buttons
        catalogButtons?["choose"]?.isEnabled = !model.isBusy
        catalogButtons?["review"]?.isEnabled = catalog.map { !$0.isOpenInLightroom } ?? false
        let presetsButton = sections[.presets]?.buttons["import"]
        presetsButton?.isEnabled = editor != nil && !isImportingPresets && found?.presets.isEmpty == false
        if case .imported = presetsImport {
            presetsButton?.title = "Import Again"
        } else {
            presetsButton?.title = "Import Presets"
        }
        sections[.profiles]?.buttons["choose"]?.isEnabled = editor != nil
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

    @objc private func reviewCatalog() {
        guard let catalog = shownCatalog, !catalog.isOpenInLightroom else { return }
        goOn(with: catalog.url)
    }

    @objc private func importFoundPresets() {
        importPresets(found?.presets ?? [])
    }

    /// Brings presets in as recipes through EDT-11's import, then shows its report over the window.
    func importPresets(_ urls: [URL]) {
        guard let editor, !isImportingPresets, !urls.isEmpty else { return }
        presetsImport = .importing
        refresh()
        let files = editor.engine.files
        Task { [weak self] in
            let read = await RecipeActions.read(urls, tableSpace: .sRGB, files: files)
            guard let self, let editor = self.editor else { return }
            let summary = editor.recipes.install(read)
            editor.activity.record(.action, "Import from Lightroom Classic: \(summary.headline)")
            presetsImport = .imported(summary)
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
        _ catalog: LightroomSetup.Catalog?, looking: Bool, contents: Contents?,
        status: (text: String, isProblem: Bool)?,
    ) -> Lines {
        guard let catalog else {
            return Lines(found: looking ? "Looking…" : "No catalog found in Lightroom Classic's preferences or in "
                + "Pictures › Lightroom")
        }
        let folder = catalog.url.deletingLastPathComponent().path
        let place = [catalog.url.lastPathComponent, (folder as NSString).abbreviatingWithTildeInPath]
            + [catalog.modified.map { "changed \(day($0))" }].compactMap(\.self)
        let source = switch catalog.source {
        case .lastUsed: "The catalog Lightroom Classic last used"
        case .pictures: "The newest catalog in Pictures › Lightroom"
        case .chosen: "The catalog chosen"
        }
        let size = catalog.size.map { ", \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))" }
        var lines = Lines(
            found: "", place: place.joined(separator: " · "),
            detail: "\(source): \(catalog.url.path)\(size ?? ""). It's read, never changed.",
        )
        switch contents {
        case let .read(photos, roots):
            lines.count = LightroomImportModel.number(photos)
            lines.found = "\(photos == 1 ? "photo" : "photos") in \(LightroomImportModel.count(roots, "root folder"))"
        case .reading:
            lines.found = "Reading the catalog…"
        case let .unreadable(why):
            lines.state = sentence(why)
            lines.isProblem = true
        case nil:
            break
        }
        if let status {
            lines.state = status.text
            lines.isProblem = status.isProblem
        } else if catalog.isOpenInLightroom {
            lines.state = sentence(LightroomCatalogError.openInLightroom(catalog.url.path).description)
            lines.isProblem = true
        }
        return lines
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
                count: LightroomImportModel.number(found.presets.count),
                found: "\(found.presets.count == 1 ? "preset" : "presets") in "
                    + LightroomImportModel.count(found.presetGroups, "group"),
                place: "Camera Raw's Settings folder", detail: folder,
            )
        }
        switch presetsImport {
        case .importing:
            lines.state = "Importing the presets…"
        case let .imported(summary):
            let failed = summary.failures.count
            lines.state = summary.headline + (summary.placement.map { ". \($0)" } ?? "")
                + (failed == 0 ? "." : "; \(LightroomImportModel.count(failed, "file")) couldn't be imported.")
            lines.isProblem = summary.imported.isEmpty
        case nil:
            break
        }
        return lines
    }

    /// The camera and lens profiles together, as many as there are of each, where each was found in the help.
    static func profilesLines(_ found: LightroomSetup?) -> Lines {
        guard let found else { return Lines(found: "Looking…") }
        let kinds = [
            (found.cameraProfiles, "camera profile", cameraProfileLines(found)),
            (found.lensProfiles, "lens profile", lensProfileLines(found)),
        ].map { places, noun, lines in
            (count: places.filter(\.isReadable).reduce(0) { $0 + $1.count }, noun: noun, lines: lines)
        }
        let counted = kinds.filter { $0.count > 0 }
        var lines = if counted.isEmpty {
            Lines(found: "No camera or lens profiles on this Mac")
        } else {
            Lines(
                count: LightroomImportModel.number(counted.reduce(0) { $0 + $1.count }),
                found: counted.map { LightroomImportModel.count($0.count, $0.noun) }.joined(separator: ", "),
                place: "Used on this Mac only",
                detail: counted.map { "\($0.lines.found). \($0.lines.state)" }.joined(separator: "\n"),
            )
        }
        let unreadable = (found.cameraProfiles + found.lensProfiles).filter { !$0.isReadable }.compactMap(\.folder)
        if !unreadable.isEmpty {
            lines.state = "Redlamp can't read " + joined(unreadable.map(\.path))
            lines.isProblem = true
        }
        return lines
    }

    static func cameraProfileLines(_ found: LightroomSetup) -> Lines {
        profileLines(
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
            "Redlamp reads them where they are, on this Mac only, and lists each camera's in its photos' Base Look menu."
        }
    }

    static func lensProfileLines(_ found: LightroomSetup) -> Lines {
        profileLines(found.lensProfiles, noun: "lens profile", none: "No lens profiles on this Mac") {
            switch $0 {
            case .cameraRaw: "in \(LensProfileFolder.cameraRaw.name)"
            case .userCameraRaw: "in \(LensProfileFolder.cameraRawUser.name)"
            case .redlamp, .chosen: "in \(LensProfileFolder.redlamp.name)"
            }
        } inUse: { places in
            "Redlamp reads them where they are, on this Mac only."
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

    /// "12 October", and the year when it isn't this one's.
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        return calendar.component(.year, from: date) == calendar.component(.year, from: .now)
            ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
    }

    /// An error's description as a sentence's start.
    private static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "A", "A and B", "A, B and C".
    static func joined(_ words: [String]) -> String {
        guard let last = words.last, words.count > 1 else { return words.first ?? "" }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: - Views

    private func makeView() -> NSView {
        let cards = NSStackView(views: Part.allCases.map(card))
        cards.orientation = .horizontal
        cards.alignment = .top
        cards.distribution = .fillEqually
        cards.spacing = 10
        cards.setHuggingPriority(.defaultHigh, for: .vertical)
        for card in cards.arrangedSubviews {
            card.heightAnchor.constraint(equalTo: cards.heightAnchor).isActive = true
        }
        let content = NSView()
        cards.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(cards)
        NSLayoutConstraint.activate([
            cards.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            cards.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            cards.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            cards.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12),
        ])
        content.setAccessibilityIdentifier("lightroom.setup")
        return content
    }

    /// A part's card: its title, how many, what and where, what it's doing, and its buttons at the foot.
    private func card(_ part: Part) -> NSView {
        let title = NSTextField(labelWithString: part.title)
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor
        let count = Self.label(.monospacedDigitSystemFont(ofSize: 20, weight: .semibold), .labelColor)
        let found = Self.wrappingLabel(NSFont.smallSystemFontSize, .secondaryLabelColor)
        let place = Self.wrappingLabel(NSFont.smallSystemFontSize, .tertiaryLabelColor)
        let state = Self.wrappingLabel(NSFont.smallSystemFontSize, .secondaryLabelColor)
        state.maximumNumberOfLines = 4
        for (label, line) in [(count, "count"), (found, "found"), (place, "place"), (state, "state")] {
            label.setAccessibilityIdentifier("lightroom.setup.\(part.rawValue).\(line)")
        }
        let text = NSStackView(views: [title, count, found, place, state])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setCustomSpacing(6, after: title)
        text.setCustomSpacing(6, after: place)
        for label in [found, place, state] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(lessThanOrEqualTo: text.widthAnchor).isActive = true
        }

        let actions: [(String, String, Selector, String)] = switch part {
        case .catalog: [
                (
                    "review", "Review…", #selector(reviewCatalog),
                    "Shows what the catalog would bring across before anything is written, then imports it",
                ),
                ("choose", "Choose…", #selector(askForCatalog), "Choose another Lightroom Classic catalog, or a copy"),
            ]
        case .presets: [
                (
                    "import", "Import Presets", #selector(importFoundPresets),
                    "Brings these presets in as recipes in the Recipes panel, with a report of how their settings "
                        + "came across",
                ),
            ]
        case .profiles: [
                (
                    "choose", "Choose Camera Profiles…", #selector(chooseCameraProfiles),
                    "Adobe camera profiles (.dcp) and profiles (.xmp) from anywhere on this Mac, read where they are",
                ),
                (
                    "open", "Open Lens Profiles Folder", #selector(openLensProfiles),
                    "Lens profiles you put in Redlamp's Lens Profiles folder are used on this Mac",
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
        buttons["review"]?.keyEquivalent = "\r"
        let row = NSStackView(views: actions.compactMap { buttons[$0.0] })
        row.orientation = part == .profiles ? .vertical : .horizontal
        row.alignment = part == .profiles ? .leading : .centerY
        row.spacing = part == .profiles ? 6 : 8

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        stack.setViews([text], in: .top)
        stack.setViews([row], in: .bottom)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true

        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.cornerRadius = 8
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .clear
        box.contentViewMargins = .zero
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView?.addSubview(stack)
        if let inside = box.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: inside.topAnchor),
                stack.leadingAnchor.constraint(equalTo: inside.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: inside.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: inside.bottomAnchor),
            ])
        }
        box.setAccessibilityIdentifier("lightroom.setup.\(part.rawValue)")
        sections[part] = Section(count: count, found: found, place: place, state: state, buttons: buttons)
        return box
    }

    /// A label of up to two lines.
    private static func wrappingLabel(_ size: CGFloat, _ color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private static func label(_ font: NSFont, _ color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
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
