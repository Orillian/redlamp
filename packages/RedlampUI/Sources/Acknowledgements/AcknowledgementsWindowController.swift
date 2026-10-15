import AppKit
import RedlampEngineAPI
import SwiftUI

/// What the Acknowledgements window shows: the entry chosen in its sidebar, and the downloadable
/// models, which the engine lists once the window opens.
@MainActor @Observable
public final class AcknowledgementsModel {
    public enum Entry: Hashable {
        case redlamp
        case trademarks
        case component(String)
        case model(String)
    }

    public var selection: Entry? = .redlamp
    public internal(set) var models: [ModelInfo]?
    public let components = Acknowledgements.components
    /// "Version 1.4 (812)", from the app's Info.plist.
    let version: String
    let source: URL

    public init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "–"
        version = (info["CFBundleVersion"] as? String).map { "Version \(short) (\($0))" } ?? "Version \(short)"
        source = Acknowledgements.source(commit: info["RedlampCommit"] as? String)
    }
}

/// Help › Acknowledgements… (ARC-25): one window, with Redlamp's licence and source, the
/// components and models it's made with and their licences, and the trademark notices.
@MainActor
public final class AcknowledgementsWindowController: NSWindowController, NSWindowDelegate {
    public static let title = "Acknowledgements"
    public static let menuTitle = "Acknowledgements…"
    private static var current: AcknowledgementsWindowController?

    public let model = AcknowledgementsModel()

    /// Brings the window forward, opening it first if it isn't open.
    public static func show(engine: any EditingEngine) {
        if let current {
            current.showWindow(nil)
            return
        }
        let controller = AcknowledgementsWindowController(engine: engine)
        current = controller
        controller.showWindow(nil)
    }

    init(engine: any EditingEngine) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false,
        )
        window.title = Self.title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 640, height: 400)
        super.init(window: window)
        window.contentView = NSHostingView(rootView: AcknowledgementsView(model: model, engine: engine)
            .tint(Theme.nativeTint)
            .focusEffectDisabled())
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func cancelOperation(_: Any?) {
        close()
    }

    public func windowWillClose(_: Notification) {
        Self.current = nil
    }
}
