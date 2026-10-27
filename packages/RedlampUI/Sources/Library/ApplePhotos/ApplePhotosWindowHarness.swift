import AppKit
import RedlampLibrary

/// What the harness, the tests and the regression suite set and read in the Apple Photos window (LIB-54): the
/// library it reads in place of Photos, which nothing they run can be given access to; what its open panels would
/// give; and what it shows.
@_spi(Harness) public extension ApplePhotosWindowController {
    /// Reads `library` in place of Photos, in the window opened next and in the albums followed; nil for Photos.
    static func simulate(_ library: (any ApplePhotosLibrary)?) {
        ApplePhotosSource.simulate(library)
    }

    /// System Settings isn't opened: `opened` hears of each time it would be.
    static func catchOpeningSettings(_ opened: @escaping @MainActor () -> Void) {
        ApplePhotosSource.openPrivacySettings = opened
    }

    /// To's destination and backup, as their panels give them, and the templates as they're typed.
    func prepare(destination: URL, backup: URL? = nil, folders: String, names: String) {
        let to = model.destination
        to.setDestination(destination)
        to.setBackup(backup)
        to.setFolders(folders)
        to.setNames(names)
    }

    /// Shows the import's progress as `progress` says, with nothing running, for the harness's states.
    func show(_ progress: ApplePhotosImport.Progress, stopping: Bool = false) {
        model.show(progress, stopping: stopping)
    }

    /// What the bottom bar's button `kind` does, as a click on it does: `review`, `importPhotos`, `undo`, `done`…
    func press(named kind: String) {
        if let kind = ApplePhotosScreen.Button.Kind(rawValue: kind) {
            press(kind)
        }
    }

    /// Where the window is: `access`, `choosing`, `reviewing`, `importing`, `imported`, `undone` and the rest.
    var phase: String {
        "\(model.phase)"
    }

    var access: ApplePhotosAccess {
        model.access
    }

    /// The albums chosen, by ID.
    var chosen: Set<String> {
        model.chosen
    }

    /// The report Review shows.
    var report: ApplePhotosReport? {
        model.census?.report
    }

    var outcome: ApplePhotosImport.Outcome? {
        model.outcome
    }

    /// Where Undo Import moved the import's copies in the Trash.
    var trashed: [String] {
        model.undone?.rollbacks.flatMap(\.trashed).map(\.to) ?? []
    }

    /// What went wrong last, in words.
    var problem: String? {
        model.problem
    }

    /// The page's title, the lines on it, and the line beside the bottom bar's buttons.
    var heading: String {
        model.screen.heading
    }

    var lines: [String] {
        let screen = model.screen
        return screen.message + screen.sections.flatMap(\.lines) + (screen.progress?.lines ?? [])
    }

    var statusText: String {
        model.screen.barNote
    }

    /// To's example.
    var example: String? {
        model.destination.example
    }

    /// Returns once To's example is named.
    func exampled() async {
        await model.destination.exampled()
    }

    /// The text of the button or box carrying `identifier`, whether it's shown and enabled, and a box's state.
    func control(_ identifier: String) -> (title: String, shown: Bool, enabled: Bool, on: NSControl.StateValue)? {
        guard let content = window?.contentView, let button = Self.view(identifier, in: content) as? NSButton else {
            return nil
        }
        return (
            button.title, button.window != nil && !button.isHiddenOrHasHiddenAncestor, button.isEnabled, button.state,
        )
    }

    private static func view(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = Self.view(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}

@_spi(Harness) public extension EditorModel {
    /// Reads `library` in place of Photos, in the window, in the albums followed, which are counted afresh, and in the
    /// albums kept in place.
    func simulateApplePhotos(_ library: (any ApplePhotosLibrary)?) {
        ApplePhotosSource.simulate(library)
        applePhotosFollower.stop()
        applePhotosFollower.start()
        self.library.service?.followApplePhotos(ApplePhotosSource.library)
    }

    /// The new photos the Library panel's From Apple Photos offers.
    var applePhotosNewPhotos: Int {
        applePhotosFollower.newPhotos
    }

    /// Returns once the albums followed are counted, after a simulated change too.
    func applePhotosCounted() async {
        for _ in 0 ..< 100 where !applePhotosFollower.isStarted {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await applePhotosFollower.counted()
    }
}
