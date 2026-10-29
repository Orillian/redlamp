import AppKit
import Foundation
import RedlampLibrary

/// The file operations on photos kept in Apple Photos (LIB-62), whose files are Photos' and whose folders are
/// Redlamp's cache: Redlamp doesn't move, rename or delete photos in Photos.
///
/// - **Refused, with the reason:** Rename Photos… and Move to Folder… for the whole selection when a photo kept in
///   Photos is in it, an alert saying so and that the other photos weren't changed either. A drop onto one of Folders'
///   folders copies them instead (`dropKeptInApplePhotos`), and the Apple Photos section's albums take no drop.
///   Locate… isn't offered for them in Library Health's Missing, nor Move Edits for their root, and the `.xmp` sync
///   leaves them alone (`LibraryXMP`).
/// - **Adapted:** Show in Finder opens Photos for them; Copy to Folder… copies them with their edits (LIB-63); Move to
///   Trash, ⌫ and ⌘⌫ move the other photos to the Trash and say why these didn't go, offering Remove from Library. A
///   version of one is removed from its sidecar as any version is (LIB-48).
/// - **Remove from Library** takes them out of Redlamp's lists, every row of their assets, their edits kept on this
///   Mac and Photos unchanged, until Add Albums keeps an album holding them again; Photos' changes don't bring them
///   back. It's one batch of the file operations' journal, on Library's ⌘Z with Library Health's changes.
public extension EditorModel {
    /// Remove from Library… for `photo`, or the selection it's in, kept in Apple Photos: asked first, then taken out
    /// of the library as one batch. False when it can't run now.
    @discardableResult
    func removeKeptInApplePhotos(_ photo: URL? = nil) -> Bool {
        guard canRemoveKeptInApplePhotos(photo), let core = library.service?.core else { return false }
        let alone = photo
            .flatMap { photo in library.photoID(of: photo).map(photoSelection.contains) == true ? nil : photo }
        Task { [self] in
            let ids: [Int64] = if let alone {
                await LibraryService.indexIDs(of: [alone], in: core.index)[alone].map { [$0] } ?? []
            } else {
                await selectedIndexIDs()
            }
            let kept = await keptInApplePhotos(ids)
            guard !kept.isEmpty, await confirmRemoval(of: kept) else { return }
            removeFromLibrary(keptInApplePhotos: kept)
        }
        return true
    }

    /// Whether Remove from Library… is offered for `photo`, or for the selection: it's kept in Apple Photos.
    func canRemoveKeptInApplePhotos(_ photo: URL? = nil) -> Bool {
        guard module == .library, !isModalDialogOpen, library.service?.isReady == true else { return false }
        return photo.map { library.originals?.owns($0) == true } ?? selectionKeptInApplePhotos
    }
}

extension EditorModel {
    /// The reason, wherever an operation is refused for photos kept in Apple Photos.
    static let keptInPhotosReason = "Redlamp doesn't move, rename or delete photos in Photos."

    /// The photos of `ids` kept in Apple Photos, by ID, in order: their files' rows, not their versions, which are
    /// their sidecars'.
    func keptInApplePhotos(_ ids: [Int64]) async -> [Int64] {
        guard let originals = library.originals, let service = library.service, !ids.isEmpty else { return [] }
        let addresses = await service.addresses(of: ids)
        return ids.filter { id in addresses[id].map { $0.version == nil && originals.owns($0.url) } == true }
    }

    /// Refuses an operation on the selection, `done` saying what it would have done to them ("renamed") and `verb`
    /// what it does ("rename"), when a photo kept in Apple Photos is among them: nothing is changed, and an alert says
    /// why. False when none is.
    func refuseSelectionKeptInApplePhotos(can done: String, verb: String) -> Bool {
        guard let originals = library.originals else { return false }
        let kept = selectedPhotos.filter(originals.owns)
        guard let first = kept.first else { return false }
        let others = max(selectedCount - kept.count, 0)
        let title = kept.count == 1 ? "“\(first.lastPathComponent)” can't be \(done)" : "\(kept.count) photos can't be \(done)"
        let them = others == 1 ? "it" : "them"
        let rest = others == 0 ? nil
            : "The other \(others == 1 ? "photo" : "\(others) photos") \(others == 1 ? "wasn't" : "weren't") \(done) "
            + "either: select \(them) alone to \(verb) \(them)."
        refuse(title, Self.inPhotos(kept.count), rest)
        return true
    }

    /// Says why the photos `ids` kept in Apple Photos weren't moved to the Trash, offering Remove from Library, which
    /// takes them out once it's chosen.
    func refuseTrash(keptInApplePhotos ids: [Int64]) async {
        let name = ids.count == 1 ? await library.service?.addresses(of: ids)[ids[0]]?.url.lastPathComponent : nil
        let title = name.map { "“\($0)” can't be moved to the Trash" } ?? "\(ids.count) photos can't be moved to the Trash"
        let offer = "Remove from Library takes \(ids.count == 1 ? "it" : "them") out of Redlamp's lists and leaves Photos "
            + "as it is."
        let text = [Self.inPhotos(ids.count), offer].joined(separator: " ")
        activity.record(.error, "\(title): \(text)")
        let removes: Bool
        if let answer = ApplePhotosRemoval.answer {
            removes = answer
        } else {
            guard let window = EditorWindowController.frontWindow, window.attachedSheet == nil else { return }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Remove from Library").setAccessibilityIdentifier("apple-photos.removePhotos")
            isModalDialogOpen = true
            removes = await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
            isModalDialogOpen = false
        }
        if removes {
            removeFromLibrary(keptInApplePhotos: ids)
        }
    }

    /// Takes the photos `ids` kept in Apple Photos out of the library as one batch in the library's changes' turn,
    /// every row of their assets with it, on Library's Undo with Library Health's changes, whose batches it shares.
    func removeFromLibrary(keptInApplePhotos ids: [Int64]) {
        guard let core = library.service?.core else { return }
        healthSteps.enqueue { [weak self] in
            guard let self else { return }
            let result = await core.change { () -> Result<FileOutcome, any Error> in
                do {
                    return try await .success(core.files.run(core.files.planRemoval(ofApplePhotos: ids)))
                } catch {
                    return .failure(error)
                }
            }
            switch result {
            case let .success(outcome):
                let step = HealthStep(.removeKeptInPhotos(ids), title: outcome.title)
                step.batch = outcome.batch
                pushHealthStep(step)
                activity.record(.action, outcome.title)
            case let .failure(error):
                activity.record(.error, "Remove from Library wasn't done: \(HealthWords.failure(error))")
            }
        }
    }

    /// "This photo is in Apple Photos." and the reason, for `count` photos.
    private static func inPhotos(_ count: Int) -> String {
        "\(count == 1 ? "This photo is" : "They're") in Apple Photos. \(keptInPhotosReason)"
    }

    /// `title` and `text`, with `rest` after it, in the activity log and an alert on the editor window.
    private func refuse(_ title: String, _ text: String, _ rest: String?) {
        let text = [text, rest].compactMap(\.self).joined(separator: " ")
        activity.record(.error, "\(title): \(text)")
        guard ApplePhotosRemoval.answer == nil, let window = EditorWindowController.frontWindow,
              window.attachedSheet == nil
        else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.beginSheetModal(for: window) { _ in }
    }

    /// Whether to take the photos `ids` kept in Apple Photos out of the library, asked in a sheet on the editor window.
    private func confirmRemoval(of ids: [Int64]) async -> Bool {
        if let answer = ApplePhotosRemoval.answer {
            return answer
        }
        guard let window = EditorWindowController.frontWindow, window.attachedSheet == nil else { return false }
        let name = ids.count == 1 ? await library.service?.addresses(of: ids)[ids[0]]?.url.lastPathComponent : nil
        let alert = NSAlert()
        alert.messageText = name.map { "Remove “\($0)” from the library?" } ?? "Remove \(ids.count) photos from the library?"
        let (it, its) = ids.count == 1 ? ("It leaves", "its") : ("They leave", "their")
        let holding = ids.count == 1 ? "it" : "them"
        alert.informativeText = "\(it) Redlamp's lists, with \(its) edits kept on this Mac, until Add Albums from Apple "
            + "Photos… chooses an album holding \(holding) again. Apple Photos isn't changed."
        alert.addButton(withTitle: "Remove from Library").setAccessibilityIdentifier("apple-photos.remove")
        alert.addButton(withTitle: "Cancel")
        isModalDialogOpen = true
        defer { isModalDialogOpen = false }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }
}
