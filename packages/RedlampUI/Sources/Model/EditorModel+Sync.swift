import Foundation
import RedlampDocument
import RedlampEngineAPI

/// Sync Settings, and Paste, Update AI Masks and mask presets across a selection: the active
/// photo's own change is a step in its history as usual; the others go through `SettingsSync`.
public extension EditorModel {
    /// The selection's photos other than the open one.
    var otherSelectedPhotos: [URL] {
        selectedPhotos.filter { $0 != selection }
    }

    /// The selection's photos other than the open one, for a batch on them all: a large source's taken by their IDs,
    /// their URLs read as the batch reaches them (`selectionForAction`).
    internal var otherSelectedForAction: SelectedPhotos {
        selectionForAction(excluding: openPhoto ?? selection.map { PhotoAddress(url: $0) })
    }

    var canSync: Bool {
        isMultiSelecting && info != nil && settingsSync.progress == nil
    }

    /// ⇧⌘S: the checklist, then the open photo's settings onto the rest of the selection.
    func chooseSettingsToSync() {
        guard canSync else { return }
        settingsChooser = SettingsChooser(purpose: .sync, source: recipe, selection: copySelection.remembered)
    }

    /// ⌥⇧⌘S: the same with the last choice, without the checklist.
    func syncSettings() {
        guard canSync else { return }
        sync(recipe, copySelection, title: "Sync Settings")
    }

    /// Update AI Masks on every selected photo.
    func updateAIMasksInSelection() async {
        if isMultiSelecting, settingsSync.progress == nil {
            saveNow()
            settingsSync.run(.updateAIMasks, on: otherSelectedForAction, title: "Update AI Masks", done: written)
        }
        await updateAIMasks()
    }

    /// Puts back the photos the last sync or paste changed, those not edited since.
    func undoSync() {
        lightroomConversionStep = nil
        settingsSync.undo(done: written)
    }

    /// ⌥⇧⌘A: Auto Sync on or off.
    func toggleAutoSync() {
        settingsSync.isAutoSyncing.toggle()
    }

    /// With Auto Sync on, what the step just recorded changed goes to the rest of the selection.
    internal func autoSync(from previous: EditRecipe) {
        guard settingsSync.isAutoSyncing, isMultiSelecting, info != nil,
              history.indices.contains(historyIndex) else { return }
        let step = history[historyIndex]
        let (current, run) = (recipe, SettingsSync.RunStep(
            session: historySessionID, id: step.id, title: step.title,
            carried: SettingsSelection.changes(from: previous, to: recipe),
        ))
        settingsSync.autoSync(current, step: run, on: otherSelectedForAction, done: written)
    }

    /// With Auto Sync on, Undo, Redo and history clicks take the rest of the selection with them:
    /// each photo gets back its edit at that step.
    internal func followHistory(back: Bool) {
        guard settingsSync.isAutoSyncing, isMultiSelecting, info != nil else { return }
        let (current, undone, session) = (recipe, Set(history[(historyIndex + 1)...].map(\.id)), historySessionID)
        settingsSync.follow(
            current, undone: undone, session: session, on: otherSelectedForAction,
            title: back ? "Undo Auto Sync" : "Redo Auto Sync", done: written,
        )
    }

    /// `selection` of `source` onto the rest of the selection. `step`, the open photo's step that
    /// pasted the same, makes it part of an Auto Sync run.
    internal func sync(_ source: EditRecipe, _ selection: SettingsSelection, title: String, step: UUID? = nil) {
        saveNow()
        var runStep: SettingsSync.RunStep?
        if let step {
            let pasted = EditRecipe.pastedMasks(from: source, selection)
            runStep = SettingsSync.RunStep(
                session: historySessionID,
                id: step,
                title: title,
                carried: SettingsSelection(
                    items: selection.items, masks: !pasted.isEmpty,
                    excludedMasks: Set(recipe.masks.map(\.id)).subtracting(pasted),
                    panelSwitches: selection.panelSwitches,
                ),
            )
        }
        settingsSync.run(
            .paste(source, selection),
            on: otherSelectedForAction,
            title: title,
            step: runStep,
            done: written,
        )
    }

    internal func written(_ photo: PhotoAddress, _ recipe: EditRecipe) {
        library.update(photo) { $0.hasEdits = !recipe.isPristine }
        library.sidecarSaved(photo.url)
    }
}

/// A batch reaching the open photo changes it here: the edit open as a step of its history its Undo takes back, and
/// another of its edits (LIB-48) in what saving writes for it, as `changeMetadata(of:)` changes its metadata.
extension EditorModel: SyncEditor {
    func apply(
        _ change: SettingsSync.EditorChange, to photo: PhotoAddress, title: String,
    ) async -> SettingsSync.EditorOutcome {
        let url = photo.url
        await finishOpening(url)
        guard let visit = currentVisit, visit.url == url else { return isOpen(url) ? .left : .notOpen }
        guard !isReadOnly else { return .left }
        guard photo.version == openVersion else { return applyBeside(change, to: photo.version, title: title) }
        let before = recipe
        switch change {
        case let .edit(next, over, _):
            guard recipe == over else { return .left }
            commit(next, .paste, title)
        case let .change(.paste(source, selection)):
            paste(source, selection, name: title)
        case .change(.updateAIMasks):
            await updateAIMasks()
            guard currentVisit == visit else { return isOpen(url) ? .left : .notOpen }
        case let .change(.applyMaskPreset(preset)):
            await addMaskPreset(preset, autoSyncs: false)
            guard currentVisit == visit else { return isOpen(url) ? .left : .notOpen }
        case let .change(.healDust(found)):
            guard await healDustInEditor(found[url] ?? [], on: url) else { return isOpen(url) ? .left : .notOpen }
        case .change(.follow):
            return .left
        case let .change(.convertLightroom(conversions)):
            // A photo edited in Redlamp keeps its edit, and so does one with versions.
            guard let imported = conversions[url], recipe.isPristine, openSidecar.versions.isEmpty, let info
            else { return .applied(nil) }
            commit(withPhotoAnchor(Self.asShot(imported.recipe, info), of: info, changed: true), .recipe, title)
        }
        return .applied(recipe == before ? nil : recipe)
    }

    /// `change` to the open photo's edit `version` (nil: its own) while another is open: `.edit` changes it in what
    /// saving writes, with its session; the batch works out any other change from what this gives back of it.
    private func applyBeside(
        _ change: SettingsSync.EditorChange, to version: UUID?, title: String,
    ) -> SettingsSync.EditorOutcome {
        // A version removed meanwhile.
        guard let held = openSidecar[edit: version]?.recipe else { return .left }
        switch change {
        case let .edit(next, over, session):
            guard held == over else { return .left }
            openSidecar[edit: version]?.recipe = next
            let recorded = session ?? HistorySession(steps: [
                HistoryStep(action: .open, title: "Opened", recipe: over),
                HistoryStep(action: .paste, title: title, recipe: next),
            ], versionID: version)
            unsavedSessions.removeAll { $0.id == recorded.id }
            unsavedSessions.append(recorded)
            scheduleSave()
            return .appliedBeside(next)
        case .change(.follow):
            return .left
        case .change(.convertLightroom):
            // Converted only where the photo has no versions.
            return .applied(nil)
        case .change:
            return .otherEdit(held)
        }
    }
}
