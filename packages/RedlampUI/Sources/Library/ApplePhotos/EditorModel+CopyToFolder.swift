import Foundation
import RedlampLibrary

/// Copy to Folder… for photos kept in Apple Photos (LIB-63): the photos chosen, or an album's, copied into a folder
/// with Import's destination and templates, or into the folder they were dropped on, each carrying what Redlamp keeps
/// of it, the copy then standing in for it (`ApplePhotosCopyWindowController`). Photo › Copy to Folder… and a drop
/// onto one of Folders' folders come here when photos kept in Photos are among those chosen; LIB-26's copy is for
/// photos in folders.
public extension EditorModel {
    /// Copy to Folder… for the photos `ids` names, by the index's IDs, a version as its file: those kept in Apple
    /// Photos
    /// copied into a folder with Import's destination and templates, or into `folder` when it's given (a drop onto one
    /// of Folders' folders); photos in folders among them stay where they are. Opens the Copy to Folder window, or
    /// brings forward the one copying; false while the library isn't open.
    @discardableResult
    func copyApplePhotos(_ ids: [Int64], to folder: URL? = nil) -> Bool {
        guard let service = library.service, service.isReady, let core = service.core, !ids.isEmpty else {
            return false
        }
        Task {
            let assets = await (try? core.index.read { try $0.applePhotosAssets(ofPhotos: ids) }) ?? [:]
            var seen = Set<String>()
            let chosen = ids.compactMap { assets[$0] }.filter { seen.insert($0).inserted }
            guard !chosen.isEmpty else { return }
            ApplePhotosCopyWindowController.show(
                editor: self, request: .init(assets: chosen, folder: folder, inFolders: ids.count - assets.count),
            )
        }
        return true
    }

    /// Copy to Folder… on album `id`, kept in place: the photos the library lists of it, `{album}` giving the copies
    /// its
    /// title before their other albums'. False while the library isn't open.
    @discardableResult
    func copyApplePhotosAlbum(_ id: String) -> Bool {
        guard let service = library.service, service.isReady, let core = service.core else { return false }
        let photos = ApplePhotosSource.library
        Task {
            let assets = await (try? core.index.read { try $0.applePhotosAssets(inAlbum: id) }) ?? []
            guard !assets.isEmpty else { return }
            let title = await Task.detached(priority: .userInitiated) {
                try? await photos.collections().first { $0.id == id }?.title
            }.value
            ApplePhotosCopyWindowController.show(
                editor: self, request: .init(assets: assets, album: id, albumTitle: title ?? nil),
            )
        }
        return true
    }
}

extension EditorModel {
    /// Whether a photo selected whose row is read is kept in Apple Photos: Copy to Folder copies it as LIB-63 does.
    var selectionKeptInApplePhotos: Bool {
        guard let originals = library.originals else { return false }
        return selectedPhotos.contains { originals.owns($0) }
    }

    /// Whether any of `urls` is a photo kept in Apple Photos.
    func keptInApplePhotos(_ urls: [URL]) -> Bool {
        guard let originals = library.originals else { return false }
        return urls.contains { originals.owns($0) }
    }

    /// Copy to Folder… for the photos selected, as `copyApplePhotos` takes them.
    func copySelectionKeptInApplePhotos() -> Bool {
        guard canRenamePhotos else { return false }
        Task { await copyApplePhotos(selectedIndexIDs()) }
        return true
    }

    /// The photos dropped on `folder`, some of them kept in Apple Photos, as `copyApplePhotos` takes them, into it.
    func dropKeptInApplePhotos(_ photos: DraggedPhotos, onFolder folder: URL) async {
        guard let core = library.service?.core else { return }
        let urls = await photos.urls()
        let found = await LibraryService.indexIDs(of: urls, in: core.index)
        copyApplePhotos(urls.compactMap { found[$0] }, to: folder)
    }
}
