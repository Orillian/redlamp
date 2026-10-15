import AppKit

/// ⌘Q asks before Redlamp quits, so a key pressed by mistake doesn't close it (UX-53), while Settings › Shortcuts'
/// Ask before quitting with ⌘Q is on, as it is until turned off. Only the key asks: Quit chosen from the menu, the
/// Dock's Quit, logging out, an update's relaunch and the regression suite's own quits go straight to
/// `applicationShouldTerminate`.
@MainActor public enum QuitConfirmation {
    public static let defaultsKey = "app.redlamp.asksBeforeQuitting"

    /// While the question is up, ⌘Q pressed again or held down is taken without asking again.
    private static var isAsking = false

    public static var asks: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Takes `event` when it's the key that quits and asking is on: asks, and quits on Quit. Not while another dialog
    /// holds the app, where Quit doesn't run, nor while Settings › Shortcuts records a key, which takes ⌘Q as the key
    /// pressed.
    public static func handle(_ event: NSEvent) -> Bool {
        guard asks, isAsking || NSApp.modalWindow == nil, !KeyRecorderView.isRecording, let mainMenu = NSApp.mainMenu,
              isQuitKey(event, in: mainMenu)
        else { return false }
        guard !isAsking, !event.isARepeat else { return true }
        if ask() {
            NSApp.terminate(nil)
        }
        return true
    }

    /// Whether `event` reaches the menu item that quits, as AppKit gives a key to its item: ⌘Q, or the key System
    /// Settings › Keyboard gives Quit Redlamp in its place.
    @_spi(Harness) public static func isQuitKey(_ event: NSEvent, in mainMenu: NSMenu) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command),
              let (_, item) = MenuBarKeys.item(for: event, in: mainMenu)
        else { return false }
        return item.action == #selector(NSApplication.terminate(_:))
    }

    /// Quit (Return) or Cancel (Esc); Don't ask again turns the question off, whichever is chosen.
    private static func ask() -> Bool {
        isAsking = true
        defer { isAsking = false }
        let alert = NSAlert()
        alert.messageText = "Quit Redlamp?"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let quits = alert.runModal() == .alertFirstButtonReturn
        if alert.suppressionButton?.state == .on {
            asks = false
        }
        return quits
    }
}
