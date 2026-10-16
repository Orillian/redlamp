import AppKit
import RedlampRecipes

/// What the regression suite reads and sets on the Lightroom Classic window's first screen (EDT-34): where it
/// looks, which a run points at a home of its own, what it found and shows, and what its open panels would give.
@_spi(Harness) public extension LightroomWindowController {
    /// Where the first screen looks, in place of this Mac's folders, while it's set.
    static var setupLocations: LightroomSetup.Locations? {
        get { LightroomSetupScreen.locations }
        set { LightroomSetupScreen.locations = newValue }
    }

    /// The first screen is the one shown.
    var isShowingSetup: Bool {
        setup.screen == .setup && window?.contentView === setup.view
    }

    /// What the first screen found the last time it looked; nil until it has.
    var setupFound: LightroomSetup? {
        setup.found
    }

    /// The text of the first screen's line carrying `identifier` (`lightroom.setup.presets.found`), and whether
    /// it's shown.
    func setupLine(_ identifier: String) -> (text: String, shown: Bool)? {
        guard let label = Self.setupView(identifier, in: setup.view) as? NSTextField else { return nil }
        return (label.stringValue, !label.isHiddenOrHasHiddenAncestor)
    }

    /// What the presets' import brought in, once it's done.
    var presetsImported: RecipeImportSummary? {
        if case let .imported(summary, _) = setup.presetsImport {
            return summary
        }
        return nil
    }

    /// The catalog the first screen's Choose… would give.
    func chooseSetupCatalog(_ url: URL) {
        setup.chooseCatalog(url)
    }

    private static func setupView(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = setupView(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
