import AppKit
import Testing
@testable import RedlampUI

/// A menu opened by a press takes the press's release, so its window gets one once the menu closes (`MenuPresses`,
/// #486). The press goes to a view that opens a menu inside it, as SwiftUI's pickers do on macOS 27.
@MainActor @Suite(.serialized)
struct MenuPressesTests {
    /// Tracks `opens` inside its press.
    private final class MenuButton: NSView {
        let opens = NSMenu()
        var pressed = false

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with _: NSEvent) {
            pressed = true
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: opens)
            NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: opens)
        }
    }

    private func window() -> (NSWindow, MenuButton) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false,
        )
        let button = MenuButton(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = button
        window.orderFront(nil)
        return (window, button)
    }

    private func mouse(
        _ type: NSEvent.EventType, in window: NSWindow, flags: NSEvent.ModifierFlags = [],
    ) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: CGPoint(x: 200, y: 150), modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 486, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0,
        ))
    }

    /// `event` as the app's run loop handles one: taken from the queue, which makes it the current event, then sent.
    /// AppKit takes a queued event back rebuilt from its place on the screen, and macOS 26 can read that place from
    /// the window server's frame of a window still appearing, far outside it, where the press reaches no view: one
    /// read elsewhere is taken again, for up to 2 s, as the run loop turns.
    private func handle(_ event: NSEvent) throws {
        let deadline = Date().addingTimeInterval(2)
        while true {
            NSApp.postEvent(event, atStart: true)
            let taken = try #require(NSApp.nextEvent(
                matching: NSEvent.EventTypeMask(type: event.type), until: .distantPast, inMode: .default, dequeue: true,
            ))
            let read = taken.locationInWindow
            if hypot(read.x - event.locationInWindow.x, read.y - event.locationInWindow.y) < 0.5 {
                NSApp.sendEvent(taken)
                return
            }
            try #require(Date() < deadline, "an event queued at \(event.locationInWindow) is read at \(read) after 2 s")
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    /// The releases queued for the app, taken from the queue.
    private func queuedReleases() -> [NSEvent] {
        var releases: [NSEvent] = []
        while let release = NSApp.nextEvent(
            matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true,
        ) {
            releases.append(release)
        }
        return releases
    }

    @Test func `the release a menu opened by a press took goes to the press's window once the menu closes`() throws {
        MenuPresses.install()
        let (window, button) = window()
        defer { window.orderOut(nil) }
        _ = queuedReleases()
        try handle(mouse(.leftMouseDown, in: window))
        try #require(button.pressed, "the press didn't reach the view")
        let releases = queuedReleases()
        #expect(releases.count == 1)
        #expect(releases.first?.windowNumber == window.windowNumber)
        #expect(releases.first?.eventNumber == 486)
    }

    @Test func `a Control-click's context menu, or a menu opened after the press ended, gets no release`() throws {
        MenuPresses.install()
        let (window, button) = window()
        defer { window.orderOut(nil) }
        _ = queuedReleases()
        try handle(mouse(.leftMouseDown, in: window, flags: .control))
        try #require(button.pressed, "the press didn't reach the view")
        #expect(queuedReleases().isEmpty, "a Control-click")
        try handle(mouse(.leftMouseUp, in: window))
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: button.opens)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: button.opens)
        #expect(queuedReleases().isEmpty, "a menu opened after the press ended")
    }
}
