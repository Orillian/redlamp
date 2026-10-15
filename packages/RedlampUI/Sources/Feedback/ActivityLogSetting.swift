import Foundation

/// Whether Redlamp keeps an activity log (Settings › Privacy, UX-52): on unless turned off. Off, the
/// log records nothing, the session's journal keeps only what tells a crash or a hang (the process,
/// its hangs and whether it quit), and what was kept before is deleted: the log's events, the
/// activity, photos and folders in this session's journal, the journals of sessions that have ended,
/// and the activity of crashes and hangs not reported yet.
@MainActor
@Observable
public final class ActivityLogSetting {
    public static let shared = ActivityLogSetting()
    public static let defaultsKey = "feedback.activityLog"

    public var isOn: Bool {
        didSet {
            guard isOn != oldValue else { return }
            defaults.set(isOn, forKey: Self.defaultsKey)
            for handler in handlers {
                handler(isOn)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var handlers: [@MainActor (Bool) -> Void] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    /// Calls `handler` each time it's turned on or off.
    public func onChange(_ handler: @escaping @MainActor (Bool) -> Void) {
        handlers.append(handler)
    }
}
