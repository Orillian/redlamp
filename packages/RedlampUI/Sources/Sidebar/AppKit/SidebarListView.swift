import AppKit
import RedlampDesign
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes

/// Base Looks, Recipes, Snapshots and History in AppKit: panels with the inspector's headers and
/// dividers, scrolling together under the Navigator as the inspector's panels do.
///
/// Each panel's list is an outline view as tall as its rows. It reloads only when what it shows
/// changes (once per finished edit), never while a slider moves, and the column keeps its scroll
/// position when it does. The search fields are rows of their own, so the looks and recipes reload
/// as you type without taking their focus.
final class SidebarListView: PanelColumnScrollView, NSSearchFieldDelegate {
    private let model: EditorModel
    let searchField: NSSearchField
    let lookSearchField: NSSearchField
    let folders: FolderOutlineView
    let baseLooks: SidebarOutlineView
    let recipes: SidebarOutlineView
    let snapshots: SidebarOutlineView
    let history: SidebarOutlineView
    private let panels: [SidebarSection: PanelSectionView]
    private let createSnapshot: SymbolImageView
    private let clearHistory: SymbolImageView
    private var tracker: Tracker?
    private var lookTracker: Tracker?
    private var expandedGroups: Set<String> = ["Favorites", "My Recipes", "Essentials"]
    /// Favorites and Redlamp, and the folder holding the photo's look when a photo opens.
    private(set) var expandedLookFolders: Set<String> = [BaseLookFolders.favorites, BaseLookGroups.redlamp]
    private var expandedSessions: Set<UUID> = []
    private var query = ""
    private var lookQuery = ""
    /// The photo's look as Base Looks last listed it, and the photo it last opened that look's folder for.
    private var listedLook: BaseLookReference?
    private var listedPhoto: URL?

    /// Lists pad their own rows, so a row's highlight can reach past its text.
    private static let listInsets = NSEdgeInsets(top: 0, left: 0, bottom: Metrics.panelBottomPadding, right: 0)

    init(model: EditorModel) {
        self.model = model
        let searchField = NSSearchField()
        let lookSearchField = NSSearchField()
        let folders = FolderOutlineView(model: model)
        let baseLooks = SidebarOutlineView(model: model)
        let recipes = SidebarOutlineView(model: model)
        let snapshots = SidebarOutlineView(model: model)
        let history = SidebarOutlineView(model: model)
        let addFolder = Self.headerButton("plus", help: "Add Folder…") { FolderActions.add(model: model) }
        let createSnapshot = Self.headerButton("plus", help: "Create Snapshot (⌘N)") { model.createSnapshot() }
        let clearHistory = Self.headerButton("xmark", help: "Clear History") { model.clearHistory() }
        let panels: [SidebarSection: PanelSectionView] = [
            .folders: PanelSectionView(
                section: .folders, model: model, accessory: addFolder, insets: Self.listInsets, rows: [folders],
            ),
            .baseLooks: PanelSectionView(
                section: .baseLooks, model: model, accessory: Self.baseLooksButton(model: model),
                insets: Self.listInsets, rows: [SearchFieldRow(field: lookSearchField), baseLooks],
            ),
            .recipes: PanelSectionView(
                section: .recipes, model: model, accessory: Self.recipesButton(model: model), insets: Self.listInsets,
                rows: [SearchFieldRow(field: searchField), recipes],
            ),
            .snapshots: PanelSectionView(
                section: .snapshots, model: model, accessory: createSnapshot, insets: Self.listInsets,
                rows: [snapshots],
            ),
            .history: PanelSectionView(
                section: .history, model: model, accessory: clearHistory, insets: Self.listInsets, rows: [history],
            ),
        ]
        self.searchField = searchField
        self.lookSearchField = lookSearchField
        self.folders = folders
        self.baseLooks = baseLooks
        self.recipes = recipes
        self.snapshots = snapshots
        self.history = history
        self.createSnapshot = createSnapshot
        self.clearHistory = clearHistory
        self.panels = panels
        super.init(
            views: [SidebarSection.folders, .baseLooks, .recipes, .snapshots, .history].compactMap { panels[$0] },
        )

        Self.setUp(
            searchField, placeholder: "Search recipes", identifier: "recipes.search",
            help: "Search recipes by name or tag. Lightroom's words work too: preset, profile, LUT.",
        )
        Self.setUp(
            lookSearchField, placeholder: "Search Base Looks", identifier: "baseLooks.search",
            help: "Search Base Looks by name, maker or kind: kodak, slide, black and white. "
                + "Profile, film, simulation and LUT list a whole kind.",
        )
        searchField.delegate = self
        lookSearchField.delegate = self

        baseLooks.content = { [weak self] in self?.lookRows() ?? [] }
        baseLooks.isExpanded = { [weak self] node in
            guard case let .group(name, _, _) = node.kind else { return false }
            return self?.expandedLookFolders.contains(name) ?? false
        }
        baseLooks.expansionChanged = { [weak self] node, expanded in
            guard case let .group(name, _, _) = node.kind else { return }
            if expanded {
                self?.expandedLookFolders.insert(name)
            } else {
                self?.expandedLookFolders.remove(name)
            }
        }
        // A drop on either panel imports each file into the panel it belongs in, which opens its folders.
        for list in [baseLooks, recipes] {
            list.acceptsFiles = RecipeActions.droppableFiles
            list.dropFiles = { [model] urls in RecipeActions.importFiles(urls, model: model) }
        }
        recipes.content = { [weak self] in self?.recipeRows() ?? [] }
        snapshots.content = { [model] in
            model.snapshots.isEmpty
                ? [SidebarNode(.placeholder("No snapshots"))]
                : model.snapshots.map { SidebarNode(.snapshot($0)) }
        }
        history.content = { [weak self] in self?.historyRows() ?? [] }
        for list in [recipes, history] {
            list.isExpanded = { [weak self] node in self?.isExpanded(node) ?? false }
            list.expansionChanged = { [weak self] node, expanded in self?.setExpanded(node, expanded) }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tracker?.cancel()
        tracker = nil
        lookTracker?.cancel()
        lookTracker = nil
        guard window != nil else { return }
        tracker = Tracker { [weak self] in
            guard let self else { return }
            createSnapshot.isEnabled = model.info != nil
            clearHistory.isEnabled = model.history.count > 1 || !model.earlierSessions.isEmpty
        }
        // The photo's look is read without observing it, so Base Looks doesn't reload while a slider
        // moves: this lists it again when it's another look, to highlight that look's row.
        lookTracker = Tracker { [weak self] in
            guard let self else { return }
            let look = model.baseLook
            guard let listed = listedLook, baseLooks.window != nil else { return }
            if !look.isSameLook(as: listed) || look.name != listed.name {
                baseLooks.refresh()
            }
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === lookSearchField {
            lookQuery = lookSearchField.stringValue
            baseLooks.refresh()
        } else {
            query = searchField.stringValue
            recipes.refresh()
        }
    }

    // MARK: - Rows

    /// The folders, the photo's look highlighted in its folder, or what a search found as one list.
    private func lookRows() -> [SidebarNode] {
        _ = model.recipes.revision
        _ = model.cameraProfileLooks
        let photo = model.info?.url
        let look = model.unobservedRecipe.baseLook
        listedLook = look
        expandedLookFolders.formUnion(model.recipes.takeImportedLookFolders())
        let folders = BaseLookFolders.folders(model)
        if photo != listedPhoto {
            listedPhoto = photo
            if photo != nil {
                expandedLookFolders.formUnion(BaseLookFolders.path(to: look, in: folders))
            }
        }
        let trimmed = lookQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return folders.map { lookNode($0, look: look) }
        }
        let found = BaseLookFolders.search(trimmed, in: folders)
        guard !found.isEmpty else {
            return [SidebarNode(.placeholder("No matching Base Looks"))]
        }
        return found.map { SidebarNode(.look($0, current: $0.isLook(of: look), showsFolder: true)) }
    }

    private func lookNode(_ folder: LookFolder, look: BaseLookReference) -> SidebarNode {
        SidebarNode(
            .group(folder.name, count: folder.count, panel: .baseLooks),
            children: folder.subfolders.map { lookNode($0, look: look) }
                + folder.entries.map { SidebarNode(.look($0, current: $0.isLook(of: look), showsFolder: false)) },
        )
    }

    private func recipeRows() -> [SidebarNode] {
        _ = model.recipes.revision
        _ = model.recipeApplication?.recipe.id
        expandedGroups.formUnion(model.recipes.takeImportedLists())
        var rows: [SidebarNode] = []
        if let amount = model.recipeAmount, let title = model.recipeAmountTitle {
            rows.append(SidebarNode(.recipeAmount(title, amount)))
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            rows += model.recipes.sections.map { section in
                SidebarNode(
                    .group(section.name, count: section.recipes.count, panel: .recipes),
                    children: section.recipes.map { SidebarNode(.recipe($0)) },
                )
            }
        } else {
            let found = model.recipes.searchPresets(trimmed)
            rows += found.map { SidebarNode(.recipe($0)) }
            if found.isEmpty {
                rows.append(SidebarNode(.placeholder("No matching recipes")))
                rows.append(SidebarNode(.placeholder("Looks and film stocks are in Base Looks")))
            }
        }
        return rows
    }

    private func historyRows() -> [SidebarNode] {
        let current = model.historyIndex
        let steps = model.history.enumerated().reversed().map { index, step in
            SidebarNode(.history(step, index: index, current: index == current, future: index > current))
        }
        let sessions = model.earlierSessions.map { session in
            SidebarNode(
                .session(session),
                children: session.steps.reversed().map { SidebarNode(.earlierStep($0, session: session)) },
            )
        }
        return steps + sessions
    }

    private func isExpanded(_ node: SidebarNode) -> Bool {
        switch node.kind {
        case let .group(name, _, _): expandedGroups.contains(name)
        case let .session(session): expandedSessions.contains(session.id)
        default: false
        }
    }

    private func setExpanded(_ node: SidebarNode, _ expanded: Bool) {
        switch node.kind {
        case let .group(name, _, _):
            if expanded {
                expandedGroups.insert(name)
            } else {
                expandedGroups.remove(name)
            }
        case let .session(session):
            if expanded {
                expandedSessions.insert(session.id)
            } else {
                expandedSessions.remove(session.id)
            }
        default:
            break
        }
    }

    // MARK: - Headers

    private static func headerButton(_ symbol: String, help: String, action: @escaping @MainActor () -> Void)
        -> SymbolImageView {
        let control = SymbolImageView(symbol, pointSize: 11, color: Palette.secondaryLabel.nsColor)
        control.toolTip = help
        control.setAccessibilityRole(.button)
        control.setAccessibilityLabel(help)
        control.onClick = action
        return control
    }

    /// Importing works without a photo; creating a recipe is disabled in the menu instead. LUTs import
    /// from Base Looks.
    private static func recipesButton(model: EditorModel) -> SymbolImageView {
        let control = headerButton("plus", help: "Create or Import a Recipe") {}
        control.onClick = { [weak control] in
            guard let control else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let create = NSMenuItem(title: "Create Recipe from Current Edit…") {
                RecipeActions.createRecipe(model: model)
            }
            create.keyEquivalent = "n"
            create.keyEquivalentModifierMask = [.command, .shift]
            create.isEnabled = model.info != nil
            menu.addItem(create)
            menu.addItem(NSMenuItem(title: "Import Recipe or Lightroom Preset…") {
                RecipeActions.importRecipes(model: model)
            })
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: control.bounds.height + 4), in: control)
        }
        return control
    }

    /// LUTs, the photographer's Adobe camera profiles and Fujifilm's LUTs, none of which needs a photo.
    private static func baseLooksButton(model: EditorModel) -> SymbolImageView {
        let control = headerButton("plus", help: "Import a LUT or Choose Camera Profiles") {}
        control.onClick = { [weak control] in
            guard let control else { return }
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Import LUT (.cube, .3dl or HaldCLUT)…") {
                RecipeActions.importLooks(model: model)
            })
            menu.addItem(NSMenuItem(title: "Choose Camera Profiles…") { CameraProfileChooser.choose(model: model) })
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Get Fujifilm's LUTs…") {
                NSWorkspace.shared.open(FujifilmLUT.downloadPage)
            })
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: control.bounds.height + 4), in: control)
        }
        return control
    }

    private static func setUp(_ field: NSSearchField, placeholder: String, identifier: String, help: String) {
        field.placeholderString = placeholder
        field.controlSize = .small
        field.font = .systemFont(ofSize: 11)
        field.sendsSearchStringImmediately = true
        field.toolTip = help
        field.setAccessibilityLabel(placeholder)
        field.setAccessibilityIdentifier(identifier)
    }

    // MARK: - Harness

    func expandEarlierSessions() {
        for row in (0 ..< history.numberOfRows).reversed() {
            if let node = history.item(atRow: row) as? SidebarNode, case .session = node.kind {
                history.expandItem(node)
            }
        }
    }

    /// Scrolls the column so a panel's header is at the top.
    func reveal(_ title: String) {
        guard let section = SidebarSection.allCases.first(where: { $0.title == title }), let panel = panels[section]
        else { return }
        layoutSubtreeIfNeeded()
        let clip = scrollView.contentView
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: panel.frame.origin, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }
}

/// The recipe search field, padded as a panel's rows are.
private final class SearchFieldRow: NSView {
    private let field: NSSearchField

    init(field: NSSearchField) {
        self.field = field
        super.init(frame: .zero)
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: field.intrinsicContentSize.height + 6)
    }

    override func layout() {
        super.layout()
        let height = field.intrinsicContentSize.height
        field.frame = CGRect(
            x: Metrics.panelPadding, y: 0, width: max(bounds.width - Metrics.panelPadding * 2, 0), height: height,
        )
    }
}

@_spi(Harness) public enum SidebarListViews {
    @MainActor public static func make(model: EditorModel) -> NSView {
        SidebarListView(model: model)
    }

    /// Scrolls a list made by `make` so the panel ("History") is at the top.
    @MainActor public static func reveal(_ section: String, in view: NSView) {
        (view as? SidebarListView)?.reveal(section)
    }

    @MainActor public static func expandEarlierSessions(in view: NSView) {
        (view as? SidebarListView)?.expandEarlierSessions()
    }
}
