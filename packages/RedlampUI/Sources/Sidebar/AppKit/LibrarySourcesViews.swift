import AppKit
import RedlampDesign

/// The Library module's Library and Collections sections on their own, for the performance harness to count a
/// library in a window of its own (LIB-23).
@_spi(Harness) public enum LibrarySourcesViews {
    @MainActor public static func make(model: EditorModel) -> NSView {
        PanelColumnScrollView(
            insets: SourcePanels.columnInsets,
            views: [SourcePanels.library(model: model), SourcePanels.collections(model: model)],
        )
    }

    /// The Library module's whole left column, for the harness's Apple Photos scene, where the Apple Photos section
    /// shows once an album is kept (LIB-62).
    @MainActor public static func column(model: EditorModel) -> NSView {
        LibraryFoldersColumn(model: model)
    }
}
