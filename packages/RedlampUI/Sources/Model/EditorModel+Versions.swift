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
        guard canChangeVersions else { return }
        renameOpenPhotosVersion(id, to: name)
    }

    /// Gives the open photo's version `id` the name `name`, without spaces at its ends, in either module, as Library
    /// renames a version (LIB-48); false when that changes nothing: an empty name, the name it has, or a version the
    /// photo doesn't have.
    @discardableResult
    internal func renameOpenPhotosVersion(_ id: UUID, to name: String) -> Bool {
        guard info != nil, opening == nil, !isReadOnly, let name = Self.versionName(name),
              let index = openSidecar.versions.firstIndex(where: { $0.id == id }),
              openSidecar.versions[index].name != name
        else { return false }
        activity.record(.edit, "Renamed version “\(openSidecar.versions[index].name)” as “\(name)”")
        openSidecar.versions[index].name = name
        versions = Self.versions(of: openSidecar)
        saveNow()
        return true
    }

    /// `typed` as a version's name, without spaces at its ends; nil for an empty one, which names nothing.
    nonisolated static func versionName(_ typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
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

    /// Takes the open photo's versions `ids` out of its sidecar, in either module, as Move to Trash does (LIB-48); the
    /// photo's own edit opens in place of one of them that's open. Returns each with its place, for Undo.
    internal func removeVersions(_ ids: Set<UUID>) -> [RemovedVersion] {
        guard let url = info?.url, opening == nil, !isReadOnly,
              openSidecar.versions.contains(where: { ids.contains($0.id) })
        else { return [] }
        if let open = openVersion, ids.contains(open) {
            switchEdit(to: nil)
        }
        let removed = openSidecar.takeVersions(ids, of: url)
        versions = Self.versions(of: openSidecar)
        saveNow()
        return removed
    }

    /// Puts `removed` back among the open photo's versions, each under its ID at its place, as Undo of Move to Trash
    /// does.
    internal func putBackVersions(_ removed: [RemovedVersion]) {
        guard info != nil, opening == nil, !isReadOnly else { return }
        openSidecar.putBack(removed)
        versions = Self.versions(of: openSidecar)
        saveNow()
    }

    /// Opens `url` in the version `version`, or in its own edit when it has no such version: a version as the
    /// library addresses it (`PhotoAddress`). A version the library lists is a photo of its own, selected alone
    /// unless `keepingSelection` (LIB-48).
    func select(_ photo: PhotoAddress, keepingSelection: Bool = false) {
        let switching = module == .develop && photo.url == selection && info?.url == photo.url && opening == nil
        if switching {
            showVersion(photo.version)
        } else {
            select(photo.url, keepingSelection: keepingSelection)
            openingVersion = photo.version
        }
        if !keepingSelection, photo.version != nil || switching, library.photoID(of: photo) != nil {
            selectOnly(photo)
            selectionAnchor = photo
        }
    }

    /// Makes the edit Develop has open the active photo where the library lists its row, a version's or its file's
    /// own (LIB-48), as its filmstrip marks it; that row is then the one Develop matched its edit to.
    internal func activateOpenEdit() {
        guard let info, opening == nil, info.url == selection else { return }
        let open = PhotoAddress(url: info.url, version: openVersion)
        if let id = library.photoID(of: open), let active = activeID, active != id {
            let list = library.photoList
            if photoSelection.count > 1 {
                if !photoSelection.contains(id) {
                    photoSelection.toggle(id, in: list)
                }
                photoSelection.activate(id)
                if photoSelection.contains(active), library.address(ofPhoto: active)?.url == info.url {
                    photoSelection.toggle(active, in: list)
                }
            } else {
                selectOnly(open)
            }
            selectionAnchor = open
        }
        matchedPhoto = activeID.flatMap(library.address(ofPhoto:))
    }

    /// Develop is shown with the active photo's file open: when another of the file's rows was made active since
    /// Develop matched its edit to one (`activateOpenEdit`), the edit that row names opens in its place.
    internal func openChosenEdit() {
        guard let info, let chosen = activeID.flatMap(library.address(ofPhoto:)), chosen != matchedPhoto,
              chosen.url == info.url
        else { return }
        guard chosen.version != openVersion else {
            matchedPhoto = chosen
            return
        }
        showVersion(chosen.version)
    }

    // MARK: - Asking

    /// Rename Version…: asks for the version's new name in a sheet over the editor.
    func chooseVersionName(_ id: UUID) {
        guard canChangeVersions, let version = openSidecar.version(id) else { return }
        askForVersionName(version.name) { [weak self] name in
            self?.renameVersion(id, to: name)
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
        changeMetadata(of: nil, change)
    }

    /// Changes the metadata of the open photo's edit `version` (nil: its own), as a change to that edit's row in the
    /// library does (LIB-48): `photoMetadata` for the edit open, else what saving writes for the other.
    func changeMetadata(of version: UUID?, _ change: (inout PhotoMetadata) -> Void) {
        guard version != openVersion else { return change(&photoMetadata) }
        openSidecar.changeMetadata(of: version, change)
    }
}

extension Sidecar {
    /// Changes the metadata of edit `version`, or the photo's own for nil; a version the photo doesn't have changes
    /// nothing.
    mutating func changeMetadata(of version: UUID?, _ change: (inout PhotoMetadata) -> Void) {
        guard var edit = self[edit: version] else { return }
        var metadata = edit.metadata ?? PhotoMetadata()
        change(&metadata)
        edit.metadata = metadata.isEmpty ? nil : metadata
        self[edit: version] = edit
    }
}
