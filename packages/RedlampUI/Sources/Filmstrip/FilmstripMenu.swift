import AppKit
import RedlampDesign
import RedlampDocument

/// A filmstrip photo's context menu (`docs/plans/2026-10-02-copy-paste-sync-design.md`), as in
/// Lightroom and Finder: on a selected photo, the Photo menu's copy, paste and sync items, in
/// Library renaming and moving, and in either module Move to Trash (LIB-46), acting on the selection as they do
/// there; on any other photo, copying from it, pasting onto it or moving it to the Trash alone, without opening it.
/// Items that don't apply are left out. In Library, its rating, flag,
/// labels and mark come first (`LibraryGridMenu.culling`), then Stacking (`LibraryGridMenu.stacking`);
/// the grid's menu has its own. A photo in Recently Trashed has Put Back's instead (`TrashMenu`).
@MainActor
enum FilmstripMenu {
    static func menu(for photo: URL, model: EditorModel, culling: Bool = false) -> NSMenu? {
        menu(for: PhotoAddress(url: photo), model: model, culling: culling)
    }

    /// `address` is the cell's photo, a file's own edit or one of its versions (LIB-48): culling reaches it, and what
    /// acts on files reaches its file.
    static func menu(for address: PhotoAddress, model: EditorModel, culling: Bool = false) -> NSMenu? {
        let photo = address.url
        if let trashed = TrashMenu.menu(for: photo, model: model) {
            return trashed
        }
        let menu = NSMenu()
        if culling {
            add(LibraryGridMenu.culling(for: address, model: model), to: menu)
            if model.module == .library, !model.isModalDialogOpen {
                add([LibraryGridMenu.stacking(for: photo, model: model)], to: menu)
            }
        }
        if address == model.activeAddress || model.library.photoID(of: address)
            .map(model.photoSelection.contains) == true {
            let groups: [[ShortcutAction]] = [
                [.copySettings, .copySettingsAgain, .pasteSettings, .pastePrevious],
                [.syncSettings, .syncSettingsAgain, .undoSync, .toggleAutoSync],
                [.renamePhotos, .moveToFolder, .copyToFolder, .moveToTrash],
            ]
            for group in groups {
                let actions = group.filter { action in
                    model.canPerform(action) && (action != .toggleAutoSync || model.isMultiSelecting)
                }
                add(actions.map { item(for: $0, model: model) }, to: menu)
            }
        } else if !model.isModalDialogOpen {
            var items = [
                NSMenuItem(title: ShortcutAction.copySettings.title) {
                    Task { await model.chooseSettingsToCopy(from: photo) }
                },
                NSMenuItem(title: ShortcutAction.copySettingsAgain.title) {
                    Task { await model.copySettings(from: photo) }
                },
            ]
            if model.hasClipboard {
                items.append(NSMenuItem(title: ShortcutAction.pasteSettings.title) {
                    model.pasteSettings(onto: photo)
                })
            }
            add(items, to: menu)
            if model.canPerform(.undoSync) {
                add([NSMenuItem(title: ShortcutAction.undoSync.title) { model.perform(.undoSync) }], to: menu)
            }
            if model.canMoveToTrash {
                add([trash(photo, model: model)], to: menu)
            }
        }
        return menu.items.isEmpty ? nil : menu
    }

    /// An action as the Photo menu has it, with its keys: here they do the same.
    private static func item(for action: ShortcutAction, model: EditorModel) -> NSMenuItem {
        let state: NSControl.StateValue = action == .toggleAutoSync && model.settingsSync.isAutoSyncing ? .on : .off
        let item = NSMenuItem(title: action.title, state: state) { model.perform(action) }
        if let (key, modifiers) = action.combos.first?.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    /// Move to Trash for `photo` alone, which isn't selected.
    private static func trash(_ photo: URL, model: EditorModel) -> NSMenuItem {
        let item = NSMenuItem(title: ShortcutAction.moveToTrash.title) {
            model.moveToTrash(photo)
            model.activity.record(.action, ShortcutAction.moveToTrash.title)
        }
        if let (key, modifiers) = ShortcutAction.moveToTrash.combos.first?.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private static func add(_ items: [NSMenuItem], to menu: NSMenu) {
        guard !items.isEmpty else { return }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        items.forEach(menu.addItem)
    }
}
