import Foundation

/// The App Store build has no updater of its own: the App Store updates it (guideline 2.4.5(vii)).
/// So there's never one, and Check for Updates… and Settings' checkbox, shown only with one, aren't.
@MainActor
@Observable
final class Updates {
    private(set) var canCheck = false
    private(set) var checksAutomatically = false

    init?() {
        nil
    }

    func check() {}

    func setChecksAutomatically(_: Bool) {}
}
