#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import CoreGraphics

    /// Whether the Mac is showing windows at all. While every display is asleep or the screen is
    /// locked, a click on a SwiftUI button doesn't arrive, though AppKit's controls, menus and keys
    /// still work, so the scenarios and tests that click one can't pass then.
    enum Displays {
        /// Why a click on a SwiftUI button won't arrive now, or nil when it can.
        static var whyClicksWontArrive: String? {
            if screenLocked {
                return "the screen was locked"
            }
            if allAsleep {
                return "the displays were asleep"
            }
            return nil
        }

        /// What keeps the app from coming to the front, in words for the report.
        @MainActor static var whatHoldsTheFront: String {
            if let why = whyClicksWontArrive {
                return why
            }
            guard let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current else {
                return "no other app is in front, yet the editor window didn't become key"
            }
            let name = front.localizedName ?? front.bundleIdentifier ?? "another app"
            return switch front.bundleIdentifier {
            case "com.apple.UserNotificationCenter": "\(name) holds it: an alert is open, such as a crash dialog"
            case "com.apple.loginwindow": "\(name) holds it: the Mac is at its login window"
            default: "\(name) holds it"
            }
        }

        static var screenLocked: Bool {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            return session?["CGSSessionScreenIsLocked"] as? Bool == true
        }

        static var allAsleep: Bool {
            var count: UInt32 = 0
            guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
            var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
            return displays.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
        }
    }
#endif
