import AppKit
import Observation
import RedlampLibrary

/// Where the app reads Apple Photos (LIB-54): PhotoKit, or, for the harness and the regression suite, which
/// can't be given access to Photos, a simulated library over a manifest (`SimulatedPhotosLibrary`).
@MainActor
enum ApplePhotosSource {
    private static let photoKit = PhotoKitLibrary()
    private static var simulated: (any ApplePhotosLibrary)?

    static var library: any ApplePhotosLibrary {
        simulated ?? photoKit
    }

    /// Reads `library` in place of Photos from now on; nil for Photos again.
    static func simulate(_ library: (any ApplePhotosLibrary)?) {
        simulated = library
    }

    /// System Settings › Privacy & Security › Photos, where Redlamp's access is given.
    static let privacySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos",
    )

    /// Opens System Settings on Photos' access: what the window's Open System Settings does.
    static var openPrivacySettings: @MainActor () -> Void = {
        if let url = privacySettings {
            NSWorkspace.shared.open(url)
        }
    }
}

/// What the app keeps about the albums imports from Apple Photos follow (LIB-55), in its defaults: whether their new
/// photos are imported without asking. Off until it's turned on in Settings › Library.
@MainActor
@Observable
public final class ApplePhotosPreferences {
    public static let shared = ApplePhotosPreferences(defaults: .standard)
    static let automaticKey = "applePhotos.importsAutomatically"

    @ObservationIgnored private let defaults: UserDefaults

    /// Settings › Library's Import new photos from followed albums automatically.
    public var importsAutomatically: Bool {
        didSet { defaults.set(importsAutomatically, forKey: Self.automaticKey) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        importsAutomatically = defaults.bool(forKey: Self.automaticKey)
    }
}
