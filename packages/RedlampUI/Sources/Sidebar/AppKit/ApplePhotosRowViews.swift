import AppKit
import RedlampDesign
import RedlampLibrary

/// The Apple Photos section's albums and folders (LIB-62): what each holds, for its row's help, and its menu after
/// Show and Show Summary….
extension SidebarCellView {
    static func applePhotosHelp(_ album: ApplePhotosCollection) -> String {
        switch album.kind {
        case .album:
            "An album of Apple Photos kept in place: its photos stay in Photos, shown from Photos' own thumbnails, "
                + "and Redlamp keeps its changes to them on this Mac"
        case .smartAlbum: "A smart album of Apple Photos kept in place: its photos are those Photos puts in it"
        case .sharedAlbum:
            "A shared album of Apple Photos kept in place: Photos keeps its photos as reduced copies, not the originals"
        case .folder: "A folder of Apple Photos: a click shows the photos of every album kept in it"
        }
    }

    /// Show in Photos, Download Originals, an album's Copy to Folder… (LIB-63), and Remove from Library….
    static func applePhotosItems(_ id: String, album: ApplePhotosCollection?, model: EditorModel) -> [NSMenuItem] {
        let sources = model.librarySources
        var items: [NSMenuItem] = [
            .separator(),
            NSMenuItem(title: "Show in Photos") { ApplePhotosActions.showInPhotos() },
        ]
        items.append(NSMenuItem(title: ShortcutAction.downloadOriginals.title) {
            sources.downloadOriginals(ofApplePhotos: id)
        })
        if album?.kind != .folder {
            items.append(afterMenu(ShortcutAction.copyToFolder.title) { model.copyApplePhotosAlbum(id) })
        }
        items.append(.separator())
        items.append(afterMenu("Remove from Library…") { sources.removeApplePhotos(id) })
        return items
    }
}

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

    /// From Apple Photos' Import, in its row.
    var applePhotosImport: NSButton? {
        subviews.lazy.compactMap { ($0 as? ApplePhotosOfferAccessory)?.button }.first
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
