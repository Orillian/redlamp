import Foundation
import RedlampDocument

/// A version Move to Trash took out of its file's sidecar (LIB-48), as Lightroom Classic's Remove takes a virtual copy
/// and EDT-09's Remove Version a version: its edit, snapshots, history and metadata, the file and its other versions
/// staying. Undo puts it back under its ID at its place among the file's versions.
struct RemovedVersion: Sendable {
    let url: URL
    let version: PhotoVersion
    /// Its index among the file's versions before it went.
    let place: Int

    var address: PhotoAddress {
        PhotoAddress(url: url, version: version.id)
    }
}

extension Sidecar {
    /// Takes versions `ids` out, each with its place, as versions of the photo at `url`.
    mutating func takeVersions(_ ids: Set<UUID>, of url: URL) -> [RemovedVersion] {
        let removed = versions.enumerated().filter { ids.contains($0.element.id) }.map {
            RemovedVersion(url: url, version: $0.element, place: $0.offset)
        }
        versions.removeAll { ids.contains($0.id) }
        return removed
    }

    /// Puts `removed` back, each at its place, but for one it has again.
    mutating func putBack(_ removed: [RemovedVersion]) {
        for removed in removed.sorted(by: { $0.place < $1.place }) where version(removed.version.id) == nil {
            versions.insert(removed.version, at: min(removed.place, versions.count))
        }
    }
}

extension EditorModel {
    /// Takes versions `photos` out of their files' sidecars, each file's sidecar written once: through the editor for
    /// the photo it has open, else on the save queue after the saves asked for before. Returns those taken, for Undo;
    /// a sidecar that's protected or can't be read keeps its versions.
    func removeVersions(of photos: [PhotoAddress]) async -> [RemovedVersion] {
        var removed: [RemovedVersion] = []
        for url in photos.map(\.url).uniqued() {
            let ids = Set(photos.lazy.filter { $0.url == url }.compactMap(\.version))
            if isOpen(url) {
                await finishOpening(url)
            }
            if info?.url == url, opening == nil {
                removed += removeVersions(ids)
                continue
            }
            await saves.wait(for: url)
            let store = SidecarStore(locator: saves.sidecars.locator)
            let taken = await saves.read { Self.changingVersions(of: url, in: store) { $0.takeVersions(ids, of: url) } }
            if !taken.isEmpty {
                library.sidecarSaved(url)
            }
            removed += taken
        }
        return removed
    }

    /// Puts `removed` back in their files' sidecars, as `removeVersions(of:)` took them out.
    func putBack(_ removed: [RemovedVersion]) async {
        for url in removed.map(\.url).uniqued() {
            let versions = removed.filter { $0.url == url }
            if isOpen(url) {
                await finishOpening(url)
            }
            if info?.url == url, opening == nil {
                putBackVersions(versions)
                continue
            }
            await saves.wait(for: url)
            let store = SidecarStore(locator: saves.sidecars.locator)
            let back = await saves.read {
                Self.changingVersions(of: url, in: store) { sidecar -> [RemovedVersion] in
                    sidecar.putBack(versions)
                    return versions
                }
            }
            if !back.isEmpty {
                library.sidecarSaved(url)
            }
        }
    }

    /// `change` made to the sidecar of `url` as it is on disk, which is written again when `change` returns any; none
    /// for one that's protected, can't be read or isn't there.
    private nonisolated static func changingVersions(
        of url: URL, in store: SidecarStore, _ change: (inout Sidecar) -> [RemovedVersion],
    ) -> [RemovedVersion] {
        guard store.protection(for: url) == nil,
              case var .success(sidecar?) = Result(catching: { try store.loadThrowing(for: url) })
        else { return [] }
        let changed = change(&sidecar)
        guard !changed.isEmpty else { return [] }
        sidecar.modified = Date()
        return (try? store.save(sidecar, for: url)) == nil ? [] : changed
    }
}

private extension Sequence where Element: Hashable {
    /// Each element once, in order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
