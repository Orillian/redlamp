import AppKit
import Testing
@_spi(Harness) @testable import RedlampUI

/// ⌘Q's question before quitting (UX-53): asked for the key that reaches the menu item that quits, and no other.
@MainActor
struct QuitConfirmationTests {
    private func menuBar(quitModifiers: NSEvent.ModifierFlags = .command) -> NSMenu {
        let quit = NSMenuItem(title: "Quit Redlamp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = quitModifiers
        let bar = NSMenu()
        bar.addItem(menu("Redlamp", [
            NSMenuItem(title: "Hide Redlamp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            quit,
        ]))
        bar.addItem(menu("File", [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        return bar
    }

    private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        holder.submenu = submenu
        return holder
    }

    private func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0,
        ))
    }

    @Test func `⌘Q reaches Quit Redlamp, and Q with other modifiers or none, or another ⌘ key, doesn't`() throws {
        let bar = menuBar()
        #expect(try QuitConfirmation.isQuitKey(key("q"), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("Q", [.command, .shift]), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("q", [.command, .option]), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("q", [.command, .control]), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("q", []), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("w"), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("h"), in: bar))
    }

    @Test func `the key System Settings gives Quit Redlamp in place of ⌘Q is the one that asks`() throws {
        let bar = menuBar(quitModifiers: [.command, .option])
        #expect(try QuitConfirmation.isQuitKey(key("q", [.command, .option]), in: bar))
        #expect(try !QuitConfirmation.isQuitKey(key("q"), in: bar))
    }
}
