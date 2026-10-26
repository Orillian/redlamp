import AppKit
import Foundation
import Observation
import RedlampDocument

/// A version renamed from Library (LIB-48), as Lightroom Classic renames a virtual copy in its Metadata panel's Copy
/// Name: under EDT-09's rules for a version's name, written through the editor when it has the photo open, else in the
/// photo's sidecar on the save queue, the version's row following its sidecar (`library.sidecarSaved`). Each rename is
/// a step on Library's Undo (`EditorModel+LibraryUndo`), in the turn it was asked for.
extension EditorModel {
    var versionNameSteps: VersionNameSteps {
        if let steps = Self.versionNameSteps.object(forKey: self) {
            return steps
        }
        let steps = VersionNameSteps()
        Self.versionNameSteps.setObject(steps, forKey: self)
        return steps
    }

    private static let versionNameSteps = NSMapTable<EditorModel, VersionNameSteps>.weakToStrongObjects()

    /// The name of version `photo` as Library shows it: the one asked for last until its row has it, else its row's.
    /// Nil for a file's own photo, or a version the library doesn't list by its name.
    func versionName(of photo: PhotoAddress) -> String? {
        guard photo.version != nil, let index = library.index(of: photo), let row = library.items.row(index),
              row.version == photo.version, let name = row.versionName
        else { return nil }
        return versionNameSteps.asked[photo] ?? name
    }

    /// The active photo when it's a version the library lists: what Copy Name and, in Library, Rename Version… rename.
    var activeVersion: PhotoAddress? {
        guard library.service?.isReady == true, let active = activeAddress, versionName(of: active) != nil else {
            return nil
        }
        return active
    }

    /// Whether Photo › Versions › Rename Version… renames a version now: in Develop the version open, in Library the
    /// active photo when it's a version.
    var canRenameVersion: Bool {
        module == .library ? !isModalDialogOpen && activeVersion != nil : canChangeVersions && openVersion != nil
    }

    /// Rename Version…: asks for the new name of the version open in Develop, or in Library of the active photo when
    /// it's a version, in a sheet over the editor.
    public func chooseVersionName() {
        guard module == .library else {
            if let open = openVersion {
                chooseVersionName(open)
            }
            return
        }
        guard canRenameVersion, let photo = activeVersion, let name = versionName(of: photo) else { return }
        askForVersionName(name) { [weak self] typed in
            self?.renameVersion(photo, to: typed)
        }
    }

    /// Gives version `photo` the name `name`, as Library's Copy Name and Rename Version… do, under EDT-09's rules: no
    /// spaces at its ends, an empty name or the one it has changing nothing. False when it changes nothing.
    @discardableResult
    func renameVersion(_ photo: PhotoAddress, to name: String) -> Bool {
        guard library.service?.isReady == true, let name = Self.versionName(name), let old = versionName(of: photo),
              old != name
        else { return false }
        let step = VersionNameStep(photo: photo, from: old, to: name)
        step.turn = nextLibraryTurn()
        versionNameSteps.undo.append(step)
        endLibraryRedo()
        activity.record(.action, step.title)
        write(name, for: step)
        return true
    }

    /// ⌘Z: the version renamed last given back the name it had, in either module.
    @discardableResult
    func undoVersionName() -> Bool {
        let steps = versionNameSteps
        guard let step = steps.undo.popLast() else { return false }
        step.turn = nextLibraryTurn()
        steps.redo.append(step)
        activity.record(.action, "Undo \(step.title)")
        write(step.from, for: step)
        return true
    }

    /// ⇧⌘Z: the rename Undo took back last made again, in either module.
    @discardableResult
    func redoVersionName() -> Bool {
        let steps = versionNameSteps
        guard let step = steps.redo.popLast() else { return false }
        step.turn = nextLibraryTurn()
        steps.undo.append(step)
        activity.record(.action, "Redo \(step.title)")
        write(step.to, for: step)
        return true
    }

    /// Asks for a version's new name in a sheet over the editor, `current` the name it has; `rename` is given the name
    /// typed when Rename is clicked.
    func askForVersionName(_ current: String, then rename: @escaping @MainActor (String) -> Void) {
        guard let window = EditorWindowController.frontWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Rename “\(current)”"
        alert.informativeText = "The version's new name."
        let field = NSTextField(string: current)
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
                    rename(field.stringValue)
                }
            }
        }
    }

    /// Writes `name` for `step`'s version, after the renames asked for before it, Copy Name showing it until the
    /// version's row has it. One that can't be written leaves Undo and Redo: there's nothing to take back.
    private func write(_ name: String, for step: VersionNameStep) {
        let steps = versionNameSteps
        steps.ask(name, for: step.photo, in: library)
        steps.enqueue { [weak self] in
            guard let self, await !writeVersionName(name, of: step.photo) else { return }
            steps.forget(name, for: step.photo)
            steps.undo.removeAll { $0 === step }
            steps.redo.removeAll { $0 === step }
            activity.record(.error, "\(step.title) wasn't saved: its sidecar is protected, or can't be read or written")
        }
    }

    /// Gives version `photo` the name `name`: through the editor when it has the photo open, else in the photo's
    /// sidecar as it is on disk, on the save queue after the saves asked for before. False when the photo has no such
    /// version, or its sidecar is protected or can't be read or written.
    private func writeVersionName(_ name: String, of photo: PhotoAddress) async -> Bool {
        guard let id = photo.version else { return false }
        let url = photo.url
        if isOpen(url) {
            await finishOpening(url)
        }
        if info?.url == url, opening == nil {
            return renameOpenPhotosVersion(id, to: name) || !isReadOnly && openSidecar.version(id)?.name == name
        }
        await saves.wait(for: url)
        let store = SidecarStore(locator: saves.sidecars.locator)
        let naming = await saves.read { Self.naming(id, name, of: url, in: store) }
        if naming == .written {
            library.sidecarSaved(url)
        }
        return naming != .failed
    }

    private enum Naming {
        case written, unchanged, failed
    }

    /// Gives version `id` of the photo at `url` the name `name` in its sidecar as it is on disk; failed for one that's
    /// protected, can't be read or written, or doesn't have the version.
    private nonisolated static func naming(_ id: UUID, _ name: String, of url: URL, in store: SidecarStore) -> Naming {
        guard store.protection(for: url) == nil,
              case var .success(sidecar?) = Result(catching: { try store.loadThrowing(for: url) }),
              let index = sidecar.versions.firstIndex(where: { $0.id == id })
        else { return .failed }
        guard sidecar.versions[index].name != name else { return .unchanged }
        sidecar.versions[index].name = name
        sidecar.modified = Date()
        return (try? store.save(sidecar, for: url)) == nil ? .failed : .written
    }
}

/// A version renamed from Library: Undo gives it the name it had, Redo the one it was given.
@MainActor
final class VersionNameStep {
    let photo: PhotoAddress
    let from: String
    let to: String
    var turn = 0

    init(photo: PhotoAddress, from: String, to: String) {
        self.photo = photo
        self.from = from
        self.to = to
    }

    var title: String {
        "Rename version “\(from)” as “\(to)”"
    }
}

/// The versions renamed from Library that Undo and Redo take back and make again, written one at a time in the order
/// they're asked for; and the names asked for, which Library shows until the versions' rows have them.
@MainActor
@Observable
final class VersionNameSteps {
    var undo: [VersionNameStep] = []
    var redo: [VersionNameStep] = []
    /// The names asked for, by version, that its row may not have yet.
    private(set) var asked: [PhotoAddress: String] = [:]
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var observation: LibraryObservation?

    /// Shows `name` for version `photo` until its row in `library` has it.
    func ask(_ name: String, for photo: PhotoAddress, in library: FolderLibrary) {
        asked[photo] = name
        guard observation == nil else { return }
        observation = library.observe { [weak self, weak library] _ in
            guard let self, let library, !asked.isEmpty else { return }
            for (photo, name) in asked
                where library.index(of: photo).flatMap({ library.items.row($0)?.versionName }) == name {
                asked[photo] = nil
            }
        }
    }

    /// Stops showing `name` for version `photo`, which wasn't written.
    func forget(_ name: String, for photo: PhotoAddress) {
        if asked[photo] == name {
            asked[photo] = nil
        }
    }

    /// Runs `body` once those asked for before it are done.
    func enqueue(_ body: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await body()
        }
    }

    /// Returns once every rename, Undo and Redo asked for is written.
    func written() async {
        while let tail {
            await tail.value
            if self.tail == tail {
                break
            }
        }
    }
}
