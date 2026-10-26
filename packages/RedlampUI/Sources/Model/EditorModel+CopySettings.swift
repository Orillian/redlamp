import Foundation
import RedlampDocument
import RedlampEngineAPI

/// The Copy Settings checklist, open for an edit.
public struct SettingsChooser: Identifiable {
    public enum Purpose {
        case copy
        /// Sync Settings: onto the rest of the selection.
        case sync
    }

    public let id = UUID()
    public let purpose: Purpose
    /// The edit whose settings are chosen from: its masks are listed by name.
    public let source: EditRecipe
    public var selection: SettingsSelection
    /// The photo `source` is from, when it isn't the open one (the filmstrip's menu).
    public var sourceURL: URL?
}

/// Copy Settings, Paste and Previous, by Lightroom's checklist (`SettingsSelection`): the choice is
/// made when copying, remembered for next time, and a paste takes only what was ticked
/// (`docs/plans/2026-10-02-copy-paste-sync-design.md`).
public extension EditorModel {
    /// ⇧⌘C: the checklist, for the open photo's settings, or in Library for those of the edit of it active there.
    func chooseSettingsToCopy() {
        guard info != nil else { return }
        if let active = activeEditBeside {
            Task { await chooseSettingsToCopy(from: active) }
            return
        }
        settingsChooser = SettingsChooser(purpose: .copy, source: recipe, selection: copySelection.remembered)
    }

    /// The checklist's choice: copied, and remembered for next time. (The checklist is modal: the
    /// open photo is still the one it was opened for.)
    func confirmSettingsChoice(_ chosen: SettingsSelection) {
        guard let chooser = settingsChooser else { return }
        settingsChooser = nil
        copySelection = chosen.remembered
        switch chooser.purpose {
        case .copy:
            clipboard = CopiedSettings(
                source: chooser.source,
                selection: chosen,
                sourceURL: chooser.sourceURL ?? selection,
            )
            hasClipboard = true
        case .sync:
            sync(chooser.source, chosen, title: "Sync Settings")
        }
    }

    /// ⌥⇧⌘C: copies the open photo's settings with the last choice, without the checklist, or in Library those of the
    /// edit of it active there.
    func copySettings() {
        guard info != nil else { return }
        if let active = activeEditBeside {
            Task { await copySettings(from: active) }
            return
        }
        clipboard = CopiedSettings(source: recipe, selection: copySelection, sourceURL: selection)
        hasClipboard = true
    }

    /// ⇧⌘V: what was copied, onto the open photo, and onto the rest of the selection; in Library with another of the
    /// open photo's edits active, onto each photo selected in the background.
    func pasteSettings() {
        guard let clipboard else { return }
        if activeEditBeside != nil {
            settingsSync.run(
                .paste(clipboard.source, clipboard.selection), on: selectionForAction(), title: "Paste Settings",
                done: written,
            )
            return
        }
        let step = paste(clipboard.source, clipboard.selection, name: "Paste Settings")
        if isMultiSelecting {
            sync(clipboard.source, clipboard.selection, title: "Paste Settings", step: step)
        }
    }

    /// ⌥⌘V: the previously viewed photo's settings, with the last choice (Lightroom's "Previous"),
    /// onto the open photo and the rest of the selection. The previous photo's edit is the one open on it then,
    /// its own or a version's, as is the edit open before Develop opened another of the photo's (EDT-09).
    func pasteFromPrevious() {
        guard let previous = previousSelection, info != nil, let visit = currentVisit else { return }
        Task { await pasteFromPrevious(previous, version: previousVersion, during: visit) }
    }

    /// Nothing when `previous` has no sidecar or it can't be read, when it no longer has `version`, or another
    /// photo has opened since.
    private func pasteFromPrevious(_ previous: URL, version: UUID?, during visit: PhotoVisit) async {
        await saves.wait(for: previous)
        let store = library.sidecars.store(for: previous)
        let read = try? await library.scheduler.run(.onScreen) { () -> EditRecipe? in
            (try? store.loadThrowing(for: previous))?[edit: version]?.recipe
        }
        guard let source = read ?? nil, currentVisit == visit else { return }
        let step = paste(source, copySelection, name: "Paste from Previous")
        if isMultiSelecting {
            sync(source, copySelection, title: "Paste from Previous", step: step)
        }
    }

    // MARK: - A photo in the filmstrip

    /// In Library, the photo active there when it's another edit of the photo open than the edit open in the editor
    /// (LIB-48): Copy and Paste take it.
    private var activeEditBeside: PhotoAddress? {
        guard module == .library, let id = photoSelection.active, let active = library.address(ofPhoto: id),
              active.url == info?.url, opening == nil, active != openPhoto
        else { return nil }
        return active
    }

    /// The checklist for `photo`'s settings: the open photo's, or another's read from its sidecar
    /// without opening it.
    func chooseSettingsToCopy(from photo: URL) async {
        await chooseSettingsToCopy(from: PhotoAddress(url: photo))
    }

    /// The checklist for the settings of the edit `photo` names: the edit open, or another read without opening it, a
    /// version's included (LIB-48).
    func chooseSettingsToCopy(from photo: PhotoAddress) async {
        guard photo != openPhoto else { return chooseSettingsToCopy() }
        guard !isModalDialogOpen, let edit = await edit(of: photo), !isModalDialogOpen else { return }
        settingsChooser = SettingsChooser(
            purpose: .copy, source: edit, selection: copySelection.remembered, sourceURL: photo.url,
        )
    }

    /// `photo`'s settings with the last choice, without the checklist.
    func copySettings(from photo: URL) async {
        await copySettings(from: PhotoAddress(url: photo))
    }

    /// The settings of the edit `photo` names with the last choice, without the checklist: a version's own when it's a
    /// version (LIB-48).
    func copySettings(from photo: PhotoAddress) async {
        guard photo != openPhoto else { return copySettings() }
        guard !isModalDialogOpen, let edit = await edit(of: photo) else { return }
        clipboard = CopiedSettings(source: edit, selection: copySelection, sourceURL: photo.url)
        hasClipboard = true
        let version = library.index(of: photo).flatMap { library.items.row($0)?.versionName }
        activity.record(
            .action,
            "Copied settings from \(activity.alias(for: photo.url))\(version.map { " (\($0))" } ?? "")",
        )
    }

    /// What was copied, onto `photo`: with the selection when it is in it, otherwise onto it
    /// alone, in the background, leaving the open photo as it is.
    func pasteSettings(onto photo: URL) {
        pasteSettings(onto: PhotoAddress(url: photo))
    }

    /// What was copied, onto the edit `photo` names, a version's included (LIB-48): with the selection when it is in
    /// it, otherwise onto it alone, in the background, leaving the open photo as it is.
    func pasteSettings(onto photo: PhotoAddress) {
        guard !isModalDialogOpen else { return }
        guard photo != openPhoto, library.photoID(of: photo).map(photoSelection.contains) != true else {
            return pasteSettings()
        }
        guard let clipboard else { return }
        settingsSync.run(
            .paste(clipboard.source, clipboard.selection),
            on: [photo],
            title: "Paste Settings",
            done: written,
        )
        activity.record(.action, "Pasted settings onto \(activity.alias(for: photo.url))")
    }

    /// An edit as saved, or as the editor holds it for the photo open: the default edit if the photo has none, nil if
    /// it
    /// can't be read or the photo has no such version.
    private func edit(of photo: PhotoAddress) async -> EditRecipe? {
        if photo.url == info?.url, opening == nil {
            return photo == openPhoto ? recipe : openSidecar[edit: photo.version]?.recipe
        }
        await saves.wait(for: photo.url)
        let store = library.sidecars.store(for: photo.url)
        let read = try? await library.scheduler.run(.onScreen) { () -> EditRecipe? in
            try? store.loadThrowing(for: photo.url).map { $0[edit: photo.version]?.recipe }
                ?? (photo.version == nil ? EditRecipe() : nil)
        }
        return read ?? nil
    }

    /// Pastes onto the open photo as one step, then recomputes the AI masks it brought for this
    /// photo. White balance As Shot reads this photo's own; Auto is measured again for it. Returns
    /// the step it recorded, if it changed anything.
    @discardableResult
    internal func paste(_ source: EditRecipe, _ selection: SettingsSelection, name: String) -> UUID? {
        guard info != nil else { return nil }
        let previous = history.indices.contains(historyIndex) ? history[historyIndex].id : nil
        let pasted = recipe.pasting(source, selection)
            .reusingAIMasks(from: recipe, in: EditRecipe.pastedMasks(from: source, selection))
        var next = anchored(pasted.recipe)
        let pastesWhiteBalance = selection.items.contains("whiteBalance")
        if pastesWhiteBalance, next.whiteBalanceMode == .asShot, let wb = info?.asShotWhiteBalance {
            next[.temperature] = wb.temperature
            next[.tint] = wb.tint
        }
        commit(next, .paste, name)
        let step = history.indices.contains(historyIndex) ? history[historyIndex].id : nil
        if pastesWhiteBalance, next.whiteBalanceMode == .auto {
            setWhiteBalanceMode(.auto)
        }
        updatePastedAIMasks(pasted.recompute)
        return step == previous ? nil : step
    }
}

extension SettingsSelection {
    private static let defaultsKey = "app.redlamp.copySettings"

    static func saved(in defaults: UserDefaults = .standard) -> SettingsSelection {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(SettingsSelection.self, from: $0) }
            ?? .default
    }

    func save(in defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(remembered) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
