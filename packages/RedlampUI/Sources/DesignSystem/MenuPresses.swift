import AppKit

/// On macOS 27, SwiftUI draws the pickers and menu buttons in a grouped form itself, and follows a press on one with
/// gesture recognizers of its own, which no view lists. The press opens the menu, and the menu's tracking takes the
/// press's release, so those recognizers never see one: they hold the press, and take the window's next click as
/// part of it, so that click does nothing (#486). Installed at launch, this gives the window the release once the
/// menu has closed, where the pointer is then, as the menu took it.
@MainActor
public enum MenuPresses {
    private static var observers: [any NSObjectProtocol] = []
    /// The menu tracking now, and the press that opened it.
    private static var opened: (menu: ObjectIdentifier, press: NSEvent)?

    /// From now on, a press that opens a menu ends when the menu closes. The app calls it once, at launch.
    public static func releaseAfterMenus() {
        if #available(macOS 27, *) {
            install()
        }
    }

    static func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
                nonisolated(unsafe) let menu = notification.object as? NSMenu
                MainActor.assumeIsolated { menu.map(began) }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { notification in
                nonisolated(unsafe) let menu = notification.object as? NSMenu
                MainActor.assumeIsolated { menu.map(ended) }
            },
        ]
    }

    /// A menu that begins tracking while the app's current event is still a press, its release not yet taken from
    /// the queue, opened inside that press. A Control-click's context menu is left alone: AppKit gives the view no
    /// press for it.
    private static func began(_ menu: NSMenu) {
        guard menu.supermenu == nil, let press = NSApp.currentEvent, press.type == .leftMouseDown,
              !press.modifierFlags.contains(.control)
        else { return }
        opened = (ObjectIdentifier(menu), press)
    }

    private static func ended(_ menu: NSMenu) {
        guard let opened, opened.menu == ObjectIdentifier(menu) else { return }
        self.opened = nil
        guard let window = NSApp.window(withWindowNumber: opened.press.windowNumber), window.isVisible,
              let release = NSEvent.mouseEvent(
                  with: .leftMouseUp, location: window.convertPoint(fromScreen: NSEvent.mouseLocation),
                  modifierFlags: NSEvent.modifierFlags, timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber, context: nil, eventNumber: opened.press.eventNumber,
                  clickCount: opened.press.clickCount, pressure: 0,
              )
        else { return }
        NSApp.postEvent(release, atStart: true)
    }
}
