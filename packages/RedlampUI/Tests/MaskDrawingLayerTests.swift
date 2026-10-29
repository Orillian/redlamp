import AppKit
import RedlampCanvas
import RedlampEngineAPI
import SwiftUI
import Testing
@_spi(Harness) @testable import RedlampUI

/// The layer over the canvas that a drag draws a gradient on (ARC-31). Its gesture ends the drawing, and SwiftUI
/// drops a gesture whose view goes without ending it, so the layer stays for as long as the model is drawing: from the
/// drag's first change, which makes the mask and disarms the tool before the overlay's own state has caught up, until
/// the drawing ends.
@MainActor
struct MaskDrawingLayerTests {
    /// Key without the test's process being active, so the overlay is hit-tested as in the app's front window.
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool {
            true
        }
    }

    private static func views<T: NSView>(_: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        return ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(T.self, in: $0) }
    }

    private func settle(_ window: NSWindow) async throws {
        for _ in 0 ..< 20 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func `the drawing layer takes the drag from its first change until the drawing ends`() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let engine = GatedEngine()
        engine.sendsFrames = true
        let model = EditorModel(engine: engine)
        let window = KeyWindow(
            contentRect: CGRect(x: 100, y: 100, width: 900, height: 560), styleMask: [.titled],
            backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: CanvasArea(onOpen: {}).environment(model).environment(ThemeSettings()),
        )
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: folder)
        }
        model.select(folder.appending(path: "IMG_0001.ARW"))
        for _ in 0 ..< 400 where !model.hasFrame {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(model.hasFrame)
        try await settle(window)
        let canvas = try #require(Self.views(CanvasMetalView.self, in: window.contentView).first)
        let root = try #require(window.contentView?.superview)
        let middle = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: nil)
        func pressGoesToCanvas() async throws -> Bool {
            try await settle(window)
            return root.hitTest(middle) === canvas
        }
        #expect(try await pressGoesToCanvas(), "nothing armed in the Edit tool, the canvas takes the press")

        model.startDrawing(.linear)
        #expect(try await !pressGoesToCanvas(), "armed, the drawing layer takes the press")
        model.beginDrawing(.linear(LinearMask(start: ImagePoint(x: 0.4, y: 0.3), end: ImagePoint(x: 0.4, y: 0.3))))
        try #require(model.drawingKind == nil && model.isDrawingShape)
        #expect(
            try await !pressGoesToCanvas(),
            "the drag's first change made the mask: the layer stays to take the rest of the drag, and its release",
        )

        model.finishDrawing()
        #expect(try await pressGoesToCanvas(), "the drawing ended, nothing is armed, and the layer has gone")
        #expect(model.masks.count == 1 && !model.isDrawingShape)
    }
}
