import AppKit
import RedlampDesign

/// The Library section's From Apple Photos (LIB-55): the new photos in the albums imports from Apple Photos follow,
/// with their count and Import. A click on the row opens Import from Apple Photos….
extension SidebarCellView {
    static func applePhotosDecoration(_ count: Int) -> FolderDecoration {
        let photos = ProgressText.count(count, "new photo")
        return FolderDecoration(
            name: "From Apple Photos", nameTone: .primary,
            help: "\(photos) in the Apple Photos albums Redlamp follows. Import brings them with the last import’s "
                + "settings; a click on the row opens Import from Apple Photos.",
            accessibilityLabel: "From Apple Photos, \(photos)", symbol: "photo.on.rectangle.angled", iconTone: .primary,
        )
    }

    static func applePhotosMenu(_ count: Int, model: EditorModel) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Import \(ProgressText.count(count, "New Photo"))") {
            ApplePhotosActions.importNew(model: model)
        })
        menu.addItem(NSMenuItem(title: ShortcutAction.importFromApplePhotos.title) {
            ApplePhotosActions.open(model: model)
        })
        return menu
    }
}

/// The end of From Apple Photos' row: how many photos are new, and Import.
final class ApplePhotosOfferAccessory: NSView {
    private let stack: NSStackView
    let button: NSButton

    init(count: Int, rowSize: NSTableView.RowSizeStyle, look: SidebarOutlineView.Look, action: @escaping () -> Void) {
        let size = look == .sourceList ? SidebarCellView.SourceListLayout.textSize(rowSize) : NSFont.smallSystemFontSize
        let label = NSTextField(labelWithString: ProgressText.count(count))
        label.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
        label.textColor = Palette.secondaryLabel.nsColor
        let button = ImportButton(title: "Import", action: action)
        button.controlSize = .mini
        button.bezelStyle = .push
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        button.toolTip = "Imports the new photos with the last import’s settings"
        button.setAccessibilityIdentifier("sources.apple-photos.import")
        self.button = button
        stack = NSStackView(views: [label, button])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        super.init(frame: .zero)
        addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        stack.fittingSize
    }

    override func layout() {
        super.layout()
        stack.frame = bounds
    }

    /// A button that runs a closure.
    private final class ImportButton: NSButton {
        private let run: () -> Void

        init(title: String, action: @escaping () -> Void) {
            run = action
            super.init(frame: .zero)
            self.title = title
            target = self
            self.action = #selector(pressed)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        @objc private func pressed() {
            run()
        }
    }
}
