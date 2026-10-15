import Foundation

/// Which build this is, from Info.plist's `RedlampDistribution` (ARC-22): the Mac App Store's, the
/// direct download's (signed with Developer ID by `mise run release`), or a build from source, whose
/// key is empty.
public enum AppDistribution: String, Sendable {
    case appStore = "app-store"
    case developerID = "developer-id"
    case source = ""

    /// A value it doesn't know is a build from source's, which does nothing a release does.
    public init(bundle: Bundle) {
        self.init(value: bundle.object(forInfoDictionaryKey: "RedlampDistribution"))
    }

    init(value: Any?) {
        self = (value as? String).flatMap(AppDistribution.init(rawValue:)) ?? .source
    }

    /// The running app's.
    public static let current = AppDistribution(bundle: .main)

    /// Either release build, which is updated as a whole, by Sparkle or by the App Store, rather than
    /// rebuilt from whatever the checkout holds.
    public var isRelease: Bool {
        self != .source
    }
}
