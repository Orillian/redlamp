import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes

/// The photographer's Adobe camera profiles in the Base Look menu (TON-51, TON-52): those Camera
/// Raw installs, and files they choose, read where they are and never copied (DEC-85).
public extension EditorModel {
    /// The files and folders chosen with Choose Camera Profiles…, as bookmarks.
    static let chosenCameraProfilesKey = "app.redlamp.chosenCameraProfiles"

    /// The chosen files and folders where they are now; those that can't be found are left out.
    static func chosenCameraProfiles(in defaults: UserDefaults?) -> [URL] {
        (defaults?.array(forKey: chosenCameraProfilesKey) as? [Data] ?? []).compactMap { bookmark in
            guard let url = FolderAccess.resolve(bookmark)?.url else { return nil }
            FolderAccess.start(url)
            return url
        }
    }

    /// Lists the open photo's camera's profiles again: when it opens, and after files are chosen.
    func refreshCameraProfiles() async {
        guard let url = info?.url else { return }
        let looks = await engine.cameraProfileLooks()
        guard info?.url == url else { return }
        cameraProfileLooks = looks
        cameraProfilesPhoto = url
    }

    /// Adds `.dcp` and `.xmp` files, or folders of them, the photographer chose, and lists the
    /// photo's profiles again. Files that can't be used are named in `cameraProfileIssues`.
    func chooseCameraProfiles(_ urls: [URL]) async {
        var accepted: [URL] = []
        var issues: [String] = []
        for url in urls {
            if url.hasDirectoryPath {
                accepted.append(url)
            } else if let issue = await engine.cameraProfileIssue(url) {
                issues.append("“\(url.lastPathComponent)” \(issue).")
            } else {
                accepted.append(url)
            }
        }
        // A library kept in memory only (in tests) remembers nothing across launches.
        let defaults = library.defaults
        let kept = Self.chosenCameraProfiles(in: defaults)
        let added = accepted.filter { url in !kept.contains { $0.standardizedFileURL == url.standardizedFileURL } }
        if !added.isEmpty {
            defaults?.set((kept + added).compactMap(FolderAccess.bookmark(for:)), forKey: Self.chosenCameraProfilesKey)
            engine.setChosenCameraProfiles(defaults == nil ? kept + added : Self.chosenCameraProfiles(in: defaults))
        }
        cameraProfileIssues = issues
        await refreshCameraProfiles()
    }

    /// The photographer's profiles for the open photo, in the menu's sections: Adobe Raw, Camera
    /// Matching, each creative group, and their own.
    var cameraProfileSections: [(name: String, looks: [CameraProfileLook])] {
        var sections: [(name: String, looks: [CameraProfileLook])] = []
        for look in cameraProfileLooks {
            let name = switch look.group {
            case .adobeRaw: "Adobe Raw"
            case .cameraMatching: "Camera Matching"
            case let .creative(group): group
            case let .own(group): group ?? "Your Profiles"
            }
            if let index = sections.firstIndex(where: { $0.name == name }) {
                sections[index].looks.append(look)
            } else {
                sections.append((name, [look]))
            }
        }
        return sections
    }

    /// The Redlamp look that renders in place of the edit's Adobe profile, when it isn't on this Mac.
    var cameraProfileStandIn: BuiltInBaseLook? {
        guard baseLook.isAdobeProfile, isBaseLookMissing else { return nil }
        return baseLook.adobeStandIn
    }
}

extension CameraProfileLook {
    /// As the browser and the palette list looks: without a table, which the engine bakes.
    var package: BaseLookPackage {
        BaseLookPackage(
            id: reference.id, version: reference.version, name: reference.name, summary: summary,
            parameters: isMonochrome ? BaseLookParameters(contrast: 1, saturation: 1, warmth: 0, isMonochrome: true)
                : .identity,
        )
    }
}
