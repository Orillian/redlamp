import AppKit
import Foundation
import RedlampDocument
import RedlampEngineAPI

/// One of the open photo's versions, as the menus and the filmstrip list it (EDT-09).
public struct EditorVersion: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
}

/// Versions of the open photo's edit, as Lightroom Classic's virtual copies are (EDT-09): another edit of the same
/// file, each with its own history, snapshots and metadata, kept in the photo's one sidecar. Develop opens one at a
/// time in place of the photo's own edit; saving writes them all, the one open as it is now.
public extension EditorModel {
    /// What Develop calls the photo's own edit beside its versions.
    nonisolated static let originalName = "Original"

    /// The open photo's edit open, as its address: the file, and the version open, if one is.
    var openPhoto: PhotoAddress? {
        guard let info, opening == nil else { return nil }
        return PhotoAddress(url: info.url, version: openVersion)
    }

    /// The name of the edit open: "Original" for the photo's own, or the version's.
    var openEditName: String {
        openVersion.flatMap { id in versions.first { $0.id == id }?.name } ?? Self.originalName
    }

    /// Whether versions can be made, renamed or removed: Develop has a photo open whose edit it can save.
    var canChangeVersions: Bool {
        module == .develop && info != nil && opening == nil && info?.url == selection && !isReadOnly
            && !isModalDialogOpen
    }

    /// Whether another of the open photo's edits can be opened.
    var canOpenVersions: Bool {
        module == .develop && info != nil && opening == nil && info?.url == selection && !isModalDialogOpen
            && !versions.isEmpty
    }

    /// Create Version (⌘'): a version of the edit open, named Copy 1, Copy 2 and so on, opened in its place.
    func createVersion() {
        guard canChangeVersions, editStart == nil, let url = selection else { return }
        openSidecar[edit: openVersion] = currentEdit
        let source = openEditName
        guard let version = openSidecar.addVersion(of: openVersion) else { return }
        activity.record(.edit, "Created version “\(version.name)” of \(activity.alias(for: url)) from \(source)")
        switchEdit(to: version.id, title: "Created from \(source)")
    }

    /// Opens the photo's own edit (`version` nil) or one of its versions.
    func showVersion(_ version: UUID?) {
        guard canOpenVersions || version == nil && openVersion != nil, version != openVersion else { return }
        switchEdit(to: version)
        activity.record(.edit, "Opened \(openEditName)")
    }

    /// Gives version `id` the name `name`, without spaces at its ends; an empty name changes nothing.
    func renameVersion(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canChangeVersions, !name.isEmpty, let index = openSidecar.versions.firstIndex(where: { $0.id == id }),
              openSidecar.versions[index].name != name
        else { return }
        activity.record(.edit, "Renamed version “\(openSidecar.versions[index].name)” as “\(name)”")
        openSidecar.versions[index].name = name
        versions = Self.versions(of: openSidecar)
        saveNow()
    }

    /// Removes version `id`, with its snapshots and history; the photo's own edit opens in its place when it's open.
    func removeVersion(_ id: UUID) {
        guard canChangeVersions, let removed = openSidecar.version(id) else { return }
        if openVersion == id {
            switchEdit(to: nil)
        }
        openSidecar.versions.removeAll { $0.id == id }
        versions = Self.versions(of: openSidecar)
        activity.record(.edit, "Removed version “\(removed.name)”")
        saveNow()
    }

    /// Opens `url` in the version `version`, or in its own edit when it has no such version: a version as the
    /// library addresses it (`PhotoAddress`).
    func select(_ photo: PhotoAddress) {
        if photo.url == selection, info?.url == photo.url, opening == nil {
            showVersion(photo.version)
            return
        }
        openingVersion = photo.version
        select(photo.url)
    }

    // MARK: - Asking

    /// Rename Version…: asks for the version's new name in a sheet over the editor.
    func chooseVersionName(_ id: UUID) {
        guard canChangeVersions, let version = openSidecar.version(id),
              let window = EditorWindowController.frontWindow
        else { return }
        let alert = NSAlert()
        alert.messageText = "Rename “\(version.name)”"
        alert.informativeText = "The version's new name."
        let field = NSTextField(string: version.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.setAccessibilityIdentifier("versions.rename.name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        isModalDialogOpen = true
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isModalDialogOpen = false
                if response == .alertFirstButtonReturn {
                    self.renameVersion(id, to: field.stringValue)
                }
            }
        }
    }

    /// Remove Version…: asks before removing the version, which takes its edit, snapshots and history with it.
    func confirmRemovingVersion(_ id: UUID) {
        guard canChangeVersions, let version = openSidecar.version(id),
              let window = EditorWindowController.frontWindow
        else { return }
        let alert = NSAlert()
        alert.messageText = "Remove “\(version.name)”?"
        alert.informativeText = "Its edit, snapshots and history are removed. The photo and its other versions stay."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        isModalDialogOpen = true
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isModalDialogOpen = false
                if response == .alertFirstButtonReturn {
                    self.removeVersion(id)
                }
            }
        }
    }
}

extension EditorModel {
    /// `sidecar`'s versions as Develop lists them.
    static func versions(of sidecar: Sidecar) -> [EditorVersion] {
        sidecar.versions.map { EditorVersion(id: $0.id, name: $0.name) }
    }

    /// Changes the open photo's own metadata, as a change to its row in the library does: `photoMetadata` while its
    /// own edit is open, else the metadata saving writes beside the version open.
    func changeOwnMetadata(_ change: (inout PhotoMetadata) -> Void) {
        guard openVersion != nil else { return change(&photoMetadata) }
        var metadata = openSidecar.metadata ?? PhotoMetadata()
        change(&metadata)
        openSidecar.metadata = metadata.isEmpty ? nil : metadata
    }
}
