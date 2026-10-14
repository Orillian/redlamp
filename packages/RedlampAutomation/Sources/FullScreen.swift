#if DEBUG || REDLAMP_PROFILING
    import AppKit
    @_spi(Harness) import RedlampUI

    /// The editor window's macOS full screen, which F takes it in and out of when the app is in front. Each change
    /// animates for about half a second, and AppKit drops a second toggle made during the animation, which leaves
    /// the window in full screen with its panels back and its toolbar hidden: steps wait for the animation to end,
    /// as a person would before pressing F again.
    @MainActor
    enum FullScreen {
        /// Whether the editor window is entering or leaving full screen now.
        private(set) static var changing = false
        private static var observers: [NSObjectProtocol] = []

        /// Follows the editor window's changes from now on. AppKit announces each as it starts, from inside
        /// `toggleFullScreen`, so a step that pressed F finds it under way, and again as its animation ends.
        static func watch() {
            guard observers.isEmpty else { return }
            let changes = [
                (NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, true),
                (NSWindow.didEnterFullScreenNotification, false), (NSWindow.didExitFullScreenNotification, false),
            ]
            for (name, starting) in changes {
                // Without a queue, the observer runs as AppKit posts, on the main thread.
                let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { note in
                    let posted = (note.object as AnyObject?).map(ObjectIdentifier.init)
                    MainActor.assumeIsolated {
                        let editor = NSApp.windows.contains {
                            ObjectIdentifier($0) == posted && $0.windowController is EditorWindowController
                        }
                        if editor {
                            changing = starting
                        }
                    }
                }
                observers.append(observer)
            }
        }
    }

    public extension RunningApp {
        /// Waits for the editor window to finish entering or leaving macOS full screen.
        func settleFullScreen() throws {
            try wait("the editor window's full screen to settle", timeout: 10) { _ in !FullScreen.changing }
        }

        /// Presses F, the full-screen preview, and waits for the window's full screen to settle.
        func pressFullScreenPreview() throws {
            try press(.fullScreenPreview)
            try settleFullScreen()
        }

        /// Takes the editor window out of macOS full screen if it's there, and waits until it's out. Returns whether
        /// it was there.
        @discardableResult
        func leaveFullScreen() throws -> Bool {
            try settleFullScreen()
            let left = try main { _ -> Bool in
                guard let window = Views.editorWindow, window.styleMask.contains(.fullScreen) else { return false }
                window.toggleFullScreen(nil)
                return true
            }
            if left {
                try settleFullScreen()
            }
            return left
        }
    }
#endif
