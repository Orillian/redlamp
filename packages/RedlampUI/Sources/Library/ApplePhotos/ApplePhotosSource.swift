import AppKit
import Observation
import RedlampLibrary
import Synchronization

/// Where the app reads Apple Photos (LIB-54): PhotoKit, or, for the harness and the regression suite, which
/// can't be given access to Photos, a simulated library over a manifest (`SimulatedPhotosLibrary`).
@MainActor
enum ApplePhotosSource {
    private nonisolated static let photoKit = PhotoKitLibrary()
    private nonisolated static let simulated = Mutex<(any ApplePhotosLibrary)?>(nil)
    private nonisolated static let simulatedImages = Mutex<(any ApplePhotosImages)?>(nil)

    static var library: any ApplePhotosLibrary {
        current
    }

    /// The library read now, from any thread: what the originals cache downloads from as each download starts
    /// (LIB-60).
    nonisolated static var current: any ApplePhotosLibrary {
        simulated.withLock { $0 } ?? photoKit
    }

    /// Photos' images of its pictures, which the store's of photos left in Photos are made from (LIB-59), read from
    /// any thread: PhotoKit's, or the simulated library's while one stands in.
    nonisolated static var images: any ApplePhotosImages {
        simulatedImages.withLock { $0 } ?? PhotoKitImages.shared
    }

    /// Reads `library` in place of Photos from now on; nil for Photos again.
    static func simulate(_ library: (any ApplePhotosLibrary)?) {
        simulated.withLock { $0 = library }
        simulatedImages.withLock { $0 = library as? any ApplePhotosImages }
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

/// Photos' images as `ApplePhotosSource` gives them as each is asked for, for the library, which outlives a simulated
/// library standing in (LIB-59).
struct ApplePhotosSourceImages: ApplePhotosImages {
    func image(of asset: String, version: ApplePhotosImageVersion, size: Int) -> ApplePhotosImage {
        ApplePhotosSource.images.image(of: asset, version: version, size: size)
    }

    func cache(_ pictures: Set<ApplePhotosPicture>, size: Int, window: String) {
        ApplePhotosSource.images.cache(pictures, size: size, window: window)
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
