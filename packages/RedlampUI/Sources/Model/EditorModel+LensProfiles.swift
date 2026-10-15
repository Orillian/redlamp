import Foundation
import RedlampEngineAPI

/// Choosing a lens profile by hand, as Lightroom's Lens Corrections panel does (LNS-15): the
/// profiles on this Mac the open photo can use, and the edit's choice among them.
public extension EditorModel {
    /// The lens correction the edit renders with, before Enable Profile Corrections and its amounts:
    /// the profile it names where that's on this Mac, else the photo's own. Of the edit it observes
    /// only the choice, the one part the engine reads, so a slider's change leaves the panel alone.
    internal var lensCorrection: LensCorrection? {
        info.flatMap { photo in
            var edit = unobservedRecipe
            edit.lensProfileChoice = lensProfileChoice
            return engine.lensCorrection(for: edit, of: photo)
        }
    }

    /// Finds the profiles the open photo can use, for the Lens Corrections panel's menus.
    internal func refreshLensProfileOptions() async {
        guard let info, let visit = currentVisit else { return }
        let options = await engine.lensProfileOptions(for: info)
        guard currentVisit == visit else { return }
        lensProfileOptions = options
    }

    /// The edit's Setup: Default where it has no choice.
    var lensProfileSetup: LensProfileChoice.Setup {
        lensProfileChoice?.setup ?? .defaults
    }

    /// The profile the menus show: the one the edit names, else the one its correction came from.
    var shownLensProfile: LensProfileOption? {
        let options = lensProfileOptions ?? []
        if let choice = lensProfileChoice, choice.namesProfile {
            return options.first { Self.option($0, isNamedBy: choice) }
        }
        return lensCorrection?.profileFileName.flatMap { fileName in options.first { $0.fileName == fileName } }
    }

    /// Sets the Setup, as Lightroom's menu does: Default and Auto forget a profile chosen by hand
    /// and match again; Custom keeps the profile shown, so the photo looks the same until another
    /// is chosen.
    func setLensProfileSetup(_ setup: LensProfileChoice.Setup) {
        switch setup {
        case .defaults: setLensProfileChoice(nil)
        case .auto: setLensProfileChoice(LensProfileChoice(setup: .auto))
        case .custom:
            guard lensProfileSetup != .custom else { return }
            let shown = shownLensProfile
            setLensProfileChoice(LensProfileChoice(setup: .custom, name: shown?.name, fileName: shown?.fileName))
        }
    }

    /// Chooses a profile by hand: Custom, naming it.
    func chooseLensProfile(_ option: LensProfileOption) {
        setLensProfileChoice(option.choice)
    }

    /// The first profile of a make, or of one of its models, as Lightroom's Make and Model menus
    /// choose one.
    func chooseLensProfile(make: String, model: String? = nil) {
        if let option = (lensProfileOptions ?? [])
            .first(where: { $0.make == make && (model == nil || $0.model == model) }) {
            chooseLensProfile(option)
        }
    }

    /// Sets the edit's choice as one step: an edit read or brought across names its profile so.
    func setLensProfileChoice(_ choice: LensProfileChoice?) {
        var next = recipe
        next.lensProfileChoice = choice
        commit(next, .adjustment(.lensProfile), "Lens Profile") { edit in
            edit.lensProfileChoice.map { $0.name ?? $0.setup.name } ?? LensProfileChoice.Setup.defaults.name
        }
    }

    /// What the panel says when the profile the edit names isn't on this Mac, and what stands in
    /// for it; nil when it's used, when Default or Auto passed it over for the photo's own lens's,
    /// or when the edit names none. Nothing is said until the photo's profiles have been found.
    internal var missingLensProfile: LensPanelText.Note? {
        guard let choice = lensProfileChoice, choice.namesProfile, info?.isRaw == true,
              let options = lensProfileOptions
        else { return nil }
        let correction = lensCorrection
        let used = options.contains { Self.option($0, isNamedBy: choice) && $0.fileName == correction?.profileFileName }
            || choice.fileName.map { correction?.profileFileName?.caseInsensitiveCompare($0) == .orderedSame } == true
        let onMac = options.contains { Self.option($0, isNamedBy: choice) }
        guard !used, choice.setup == .custom || !onMac else { return nil }
        return LensPanelText.missing(choice, onMac: onMac, standIn: correction)
    }

    /// What the panel says of a named profile it can't use, for the regression suite.
    @_spi(Harness) var missingLensProfileText: String? {
        missingLensProfile?.text
    }

    /// Whether `choice` names `option`: by file name, whatever its case, else by the profile's name.
    internal static func option(_ option: LensProfileOption, isNamedBy choice: LensProfileChoice) -> Bool {
        if let fileName = choice.fileName {
            return option.fileName.caseInsensitiveCompare(fileName) == .orderedSame
        }
        return option.name == choice.name
    }
}
