import AppKit
import Foundation
import RedlampLibrary

/// The Apple Photos section (LIB-62): the albums of Apple Photos kept in place in Photos' folders and order, as the
/// index has them, never asked of Photos, so the section shows as the library opens. An album is a source of the grid
/// and the filmstrip, and a folder the photos of every album kept in it, as a collection set is. An album's menu shows
/// Photos, downloads its originals (LIB-60), copies it into a folder (LIB-63) and takes it out of the library, which
/// leaves Photos as it is.
public extension LibrarySources {
    /// The part of Photos' tree kept in place, as last counted.
    var applePhotos: ApplePhotosTree {
        _ = rows
        return counts.applePhotos
    }

    /// Whether any album is kept in place: the Apple Photos section shows only then.
    var keepsApplePhotos: Bool {
        !applePhotos.collections.isEmpty
    }

    /// What `source` is called: an album's or a folder's title as Photos has it, each other source's own.
    func title(of source: LibrarySource) -> String {
        if case let .applePhotos(id) = source, let album = counts.applePhotos[id] {
            return album.title
        }
        return source.title
    }

    /// Opens or closes the Apple Photos section, kept between launches.
    func setApplePhotosOpen(_ open: Bool) {
        guard open == isApplePhotosClosed else { return }
        isApplePhotosClosed = !open
        model?.library.defaults?.set(!open, forKey: Self.applePhotosClosedKey)
    }

    /// Whether the folder of Apple Photos `id` shows the albums kept in it.
    func isApplePhotosFolderOpen(_ id: String) -> Bool {
        !collapsedApplePhotos.contains(id)
    }

    /// Opens or closes the folder of Apple Photos `id` in its section, kept between launches.
    func setApplePhotosFolderOpen(_ id: String, _ open: Bool) {
        guard open == collapsedApplePhotos.contains(id) else { return }
        if open {
            collapsedApplePhotos.remove(id)
        } else {
            collapsedApplePhotos.insert(id)
        }
        model?.library.defaults?.set(collapsedApplePhotos.sorted(), forKey: Self.collapsedApplePhotosKey)
    }

    // MARK: - An album's menu

    /// Download Originals on album or folder `id`: the originals of its photos that aren't on this Mac downloaded from
    /// iCloud, the filmstrip showing how far they've come (LIB-60). False while the library isn't open.
    @discardableResult
    func downloadOriginals(ofApplePhotos id: String) -> Bool {
        guard let core = model?.library.service?.core, let originals = model?.library.originals else { return false }
        Task {
            let photos = await (try? core.index.read { try $0.applePhotosPhotoIDs(in: id) }) ?? []
            originals.request(photos: photos)
        }
        return true
    }

    /// Remove from Library… on album or folder `id`: once confirmed, it's no longer kept in place, its photos leaving
    /// every list with what Redlamp keeps of them on this Mac, until Add Albums chooses it again. Photos isn't changed.
    /// The source shown, if it's the album or in the folder, gives way to All Photographs. False while the library
    /// isn't following Photos.
    @discardableResult
    func removeApplePhotos(_ id: String) -> Bool {
        guard let model, let service = model.library.service, service.applePhotosIndexer != nil,
              let album = counts.applePhotos[id]
        else { return false }
        let photos = count(of: .applePhotos(id))
        Task {
            guard await ApplePhotosRemoval.confirm(album, photos: photos, model: model) else { return }
            if case let .applePhotos(shownID) = shown,
               sequence(first: shownID, next: { self.counts.applePhotos[$0]?.parent }).contains(id) {
                show(.allPhotographs)
            }
            do {
                try await service.stopKeepingApplePhotos([id])
                model.activity.record(.action, "Removed “\(album.title)” from the library")
            } catch {
                model.activity.record(
                    .error, "“\(album.title)” wasn't removed from the library: \(LibraryService.describe(error))",
                )
            }
        }
        return true
    }
}

/// Remove from Library…'s question for an album or a folder of Apple Photos (LIB-62).
@_spi(Harness) @MainActor
public enum ApplePhotosRemoval {
    /// The answer the regression suite gives, in place of the alert's buttons.
    public static var answer: Bool?

    /// Whether to remove `album`, of `photos` photos, asked in a sheet on the editor window.
    static func confirm(_ album: ApplePhotosCollection, photos: Int?, model: EditorModel) async -> Bool {
        if let answer {
            return answer
        }
        guard let window = EditorWindowController.frontWindow, window.attachedSheet == nil else { return false }
        let alert = NSAlert()
        alert.messageText = "Remove “\(album.title)” from the library?"
        let again = "until Add Albums from Apple Photos… chooses"
        let leaving = switch (album.kind, photos) {
        case (.folder, _):
            "The albums kept in it leave Redlamp's lists, with their photos' edits kept on this Mac, \(again) them again."
        case (_, 1?):
            "Its photo leaves Redlamp's lists, with its edits kept on this Mac, \(again) the album again."
        case let (_, count?) where count > 1:
            "Its \(count.formatted()) photos leave Redlamp's lists, with their edits kept on this Mac, \(again) it again."
        default:
            "Its photos leave Redlamp's lists, with their edits kept on this Mac, \(again) it again."
        }
        alert.informativeText = leaving + " Apple Photos isn't changed."
        alert.addButton(withTitle: "Remove from Library").setAccessibilityIdentifier("apple-photos.remove")
        alert.addButton(withTitle: "Cancel")
        model.isModalDialogOpen = true
        defer { model.isModalDialogOpen = false }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }
}
