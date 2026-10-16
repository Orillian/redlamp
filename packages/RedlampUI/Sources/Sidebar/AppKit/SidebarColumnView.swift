import AppKit
import RedlampDesign
import RedlampRecipes
import SwiftUI

/// The left column in AppKit: the Navigator on top, then Recipes, Snapshots and History,
/// scrolling beneath it. All four are panels like the inspector's: click a header to collapse
/// it, Option-click to show only that one.
final class SidebarColumnView: NSView, ColumnHost {
    private let navigator: PanelSectionView
    private let lists: SidebarListView

    init(model: EditorModel) {
        navigator = PanelSectionView(navigator: model)
        lists = SidebarListView(model: model)
        super.init(frame: .zero)
        addSubview(navigator)
        addSubview(lists)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool {
        true
    }

    func columnContentDidChange() {
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = navigator.height(forWidth: bounds.width)
        navigator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        lists.frame = CGRect(x: 0, y: height, width: bounds.width, height: max(bounds.height - height, 0))
    }
}

extension PanelSectionView {
    /// A left-column panel bound to the editor: expanded or collapsed with
    /// `expandedSidebarSections`, and a header menu to expand or collapse them all, which in Base Looks and
    /// Recipes also shows each of the panel's hidden folders again (UX-55).
    convenience init(
        section: SidebarSection,
        model: EditorModel,
        accessory: NSView? = nil,
        insets: NSEdgeInsets = PanelSectionView.bodyInsets,
        rows: [NSView],
    ) {
        self.init(
            title: section.title,
            symbol: section.symbol,
            accessory: accessory,
            insets: insets,
            rows: rows,
            actions: Actions(
                isExpanded: { model.expandedSidebarSections.contains(section) },
                isEdited: { false },
                toggle: { solo in model.toggleSidebarSection(section, solo: solo) },
                reset: {},
            ),
        )
        identify(as: "sidebar.\(section.rawValue)")
        headerMenu = {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Expand All Panels") {
                model.expandedSidebarSections = Set(SidebarSection.allCases)
            })
            menu.addItem(NSMenuItem(title: "Collapse All Panels") { model.expandedSidebarSections = [] })
            let panel: RecipePanel? = switch section {
            case .baseLooks: .baseLooks
            case .recipes: .recipes
            default: nil
            }
            if let panel {
                let hidden = Self.hiddenFolders(in: panel, model: model)
                if !hidden.isEmpty {
                    menu.addItem(.separator())
                }
                for folder in hidden {
                    menu.addItem(NSMenuItem(title: "Show “\(folder)”") {
                        model.recipes.setHidden(folder, in: panel, false)
                    })
                }
            }
            return menu
        }
    }

    /// The folders hidden from `panel`, in the panel's order.
    private static func hiddenFolders(in panel: RecipePanel, model: EditorModel) -> [String] {
        let order = model.recipes.builtInFolders(in: panel)
        return model.recipes.hiddenFolders(in: panel).sorted {
            (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1)
        }
    }
}
