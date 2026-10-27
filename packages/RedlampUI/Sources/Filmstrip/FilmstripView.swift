import RedlampDocument
import RedlampEngineAPI
import SwiftUI

/// The filmstrip: its line of text (Show Info Line, UX-42) above its photos, at the size its thumbnails are, which
/// dragging its top edge changes. Where it floats, the line ends in its pin (UX-43).
struct FilmstripView: View {
    /// Develop's filmstrip, which hides automatically unless it's pinned; Library's is docked.
    let floating: Bool
    @Environment(EditorModel.self) private var model

    var body: some View {
        let preference = FilmstripPreference.shared
        let strip = FilmstripStripView.height(forCellHeight: preference.cellHeight)
        VStack(spacing: 0) {
            if preference.showsInfoLine {
                // Parts of their own, each reading only what it shows: a step of a held arrow key changes the active
                // photo, which only the last two read.
                HStack(spacing: 8) {
                    FilmstripFolder()
                    FilmstripCount()
                    FilmstripExport()
                    FilmstripDownloads()
                    FilmstripSync()
                    FilmstripSuggestion()
                    Spacer()
                    FilmstripStackButton()
                    FilmstripVersions()
                    FilmstripPhotoInfo()
                    if floating {
                        FilmstripPin()
                    }
                }
                .font(Theme.captionFont)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.horizontal, 12)
                .frame(height: FilmstripPreference.infoLineHeight - 6)
                .padding(.top, 6)
            }

            if model.library.isOpenFolderUnavailable {
                Label(
                    "This folder isn't available. Is its disk connected?",
                    systemImage: "externaldrive.badge.questionmark",
                )
                .font(Theme.captionFont)
                .foregroundStyle(Theme.secondaryLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: strip)
            } else {
                FilmstripStripHost(model: model, cellHeight: preference.cellHeight)
                    .frame(height: strip)
            }
        }
        .frame(height: preference.height)
        .overlay(alignment: .top) {
            FilmstripTopEdge()
        }
    }
}

/// The filmstrip's top edge, dragged up or down to make its thumbnails larger or smaller, as Lightroom Classic's
/// is: the filmstrip grows from the window's bottom edge, so the edge stays under the pointer.
private struct FilmstripTopEdge: View {
    @State private var start: CGFloat?

    var body: some View {
        Color.clear
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .automationIdentifier("filmstrip.top-edge")
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .top))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let preference = FilmstripPreference.shared
                        let start = start ?? preference.cellHeight
                        self.start = start
                        preference.resize(to: start - drag.translation.height)
                    }
                    .onEnded { _ in start = nil },
            )
            .accessibilityHidden(true)
    }
}

/// The filmstrip's own menu items, on its right-click menu everywhere but on its photos, and in View › Filmstrip:
/// Hide Automatically where it floats (UX-19), Show Info Line and its thumbnails' sizes (UX-42).
struct FilmstripMenuItems: View {
    let floating: Bool
    @Environment(EditorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if floating {
            Toggle("Hide Automatically", isOn: $model.filmstripHidesAutomatically)
        }
        Toggle("Show Info Line", isOn: $model.filmstripShowsInfoLine)
        Divider()
        ForEach(FilmstripSize.allCases, id: \.self) { size in
            Toggle(size.title, isOn: Binding(
                get: { model.filmstripSize == size },
                set: {
                    if $0 {
                        model.filmstripSize = size
                    }
                },
            ))
        }
    }
}

/// What only the line of text shows, in a capsule of its own while the line is hidden (UX-42): the selection with
/// Sync… and Auto Sync, a sync's progress and report, the focus stack found, and Stack…, while there's any of them.
/// It floats over the photos at the filmstrip's top edge, so the filmstrip and the photo fitted above it keep their
/// place as it comes and goes.
struct FilmstripStatus: View {
    @Environment(EditorModel.self) private var model
    @Environment(ThemeSettings.self) private var theme
    @Environment(\.themeTokens) private var themeTokens

    var body: some View {
        if !FilmstripPreference.shared.showsInfoLine, hasAny {
            HStack(spacing: 8) {
                FilmstripExport()
                FilmstripDownloads()
                FilmstripSync()
                FilmstripSuggestion()
                FilmstripStackButton()
                FilmstripVersions()
            }
            .font(Theme.captionFont)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(ThemeColors(themeTokens).panelBackground.opacity(theme.panelOpacity), in: Capsule())
            .glassEffect(.regular, in: Capsule())
            .accessibilityElement(children: .contain)
            .automationIdentifier("filmstrip.status")
        }
    }

    private var hasAny: Bool {
        model.batchExport.progress != nil || model.batchExport.summary != nil || !model.downloads.statuses.isEmpty
            || model.settingsSync.progress != nil || model.isMultiSelecting || model.settingsSync.report != nil
            || !model.stackSuggestions.isEmpty || model.selection.map(SupportedFormats.isStack) == true
            || model.module == .develop && !model.versions.isEmpty
    }
}

/// The folder shown.
private struct FilmstripFolder: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let folder = model.folder {
            Label(folder.lastPathComponent, systemImage: "folder")
        }
    }
}

/// How many photos are shown, and of how many while a filter leaves some out.
private struct FilmstripCount: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        Text(photoCount)
            .foregroundStyle(Theme.tertiaryLabel)
            .help(filteredTotal == nil ? "" :
                "A filter hides some photos: \\ shows the filter bar in Library, ⌘L turns it off")
    }

    private var photoCount: String {
        let subfolders = model.library.includesSubfolders ? ", with subfolders" : ""
        guard let total = filteredTotal else { return "\(model.library.count) photos\(subfolders)" }
        return "\(model.library.count) of \(total) photos\(subfolders)"
    }

    /// The source's photos while a filter leaves some out.
    private var filteredTotal: Int? {
        guard model.library.isFiltered, let listed = model.libraryFilters?.listed, listed.shown < listed.total
        else { return nil }
        return listed.total
    }
}

/// A batch export's progress with Cancel, and for a moment after it ends, how it went (EDT-16).
private struct FilmstripExport: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let progress = model.batchExport.progress {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .frame(width: 80)
            Text("Exporting: \(progress.done) of \(progress.total)")
            if let downloads = model.batchExport.downloads, downloads.done < downloads.total {
                Text("Downloading \(downloads.done + 1) of \(downloads.total) from iCloud")
                    .automationIdentifier("filmstrip.export.downloads")
            }
            Button("Cancel") { model.batchExport.cancel() }
                .buttonStyle(.link)
                .help("Stop after the photo being written; the files written stay")
                .automationIdentifier("filmstrip.export.cancel")
        } else if let summary = model.batchExport.summary {
            Text(summary)
                .foregroundStyle(Theme.tertiaryLabel)
                .lineLimit(1)
        }
    }
}

/// The originals of photos kept in Apple Photos downloading from iCloud, with Cancel All (LIB-60).
private struct FilmstripDownloads: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let count = model.downloads.statuses.count
        if count > 0 {
            ProgressView(value: model.downloads.fraction)
                .frame(width: 80)
            Text(count == 1 ? "Downloading 1 original from iCloud" : "Downloading \(count) originals from iCloud")
                .automationIdentifier("filmstrip.downloads")
            Button("Cancel All") { model.downloads.cancelAll() }
                .buttonStyle(.link)
                .help("Stop downloading originals from iCloud; those downloaded stay")
                .automationIdentifier("filmstrip.downloads.cancel")
        }
    }
}

/// A sync's progress, or with several photos selected, how many and Sync.
private struct FilmstripSync: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let progress = model.settingsSync.progress {
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .frame(width: 80)
            Text("\(progress.title): \(progress.done) of \(progress.total)")
            Button("Cancel") { model.settingsSync.cancel() }
                .buttonStyle(.link)
        } else if model.isMultiSelecting {
            Text("\(model.photoSelection.count) selected")
                .help("⌘-click adds or removes a photo, ⇧-click selects a range; ⌥⌘D keeps only this one")
            Button("Sync…") { model.chooseSettingsToSync() }
                .buttonStyle(.link)
                .help("This photo's settings onto the other selected photos (⇧⌘S)")
                .automationIdentifier("filmstrip.sync")
            Toggle("Auto Sync", isOn: Bindable(model.settingsSync).isAutoSyncing)
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .help("Every change to this photo repeats on the other selected photos (⌥⇧⌘A)")
        }
        if let report = model.settingsSync.report {
            Text(report)
                .foregroundStyle(Theme.tertiaryLabel)
                .lineLimit(1)
                .help(report)
        }
    }
}

/// The first focus stack found, to merge or dismiss.
private struct FilmstripSuggestion: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let suggestion = model.stackSuggestions.first {
            StackSuggestionBanner(suggestion: suggestion)
        }
    }
}

/// Stack… while the active photo is a stack document.
private struct FilmstripStackButton: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let selection = model.selection, SupportedFormats.isStack(selection) {
            Button("Stack…") { model.openStackWorkspace(selection) }
                .buttonStyle(.link)
                .help("Change the stack's frames or method")
        }
    }
}

/// In Develop, the edit open of a photo with versions (EDT-09): its own, "Original", or a version's name. Its menu
/// opens another, makes a version of the one open, and renames or removes the version open.
private struct FilmstripVersions: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if model.module == .develop, !model.versions.isEmpty {
            Menu {
                Toggle(EditorModel.originalName, isOn: shown(nil))
                ForEach(model.versions) { version in
                    Toggle(version.name, isOn: shown(version.id))
                }
                Divider()
                Button("Create Version") { model.createVersion() }
                    .disabled(!model.canChangeVersions)
                if let open = model.openVersion {
                    Button("Rename Version…") { model.chooseVersionName(open) }
                        .disabled(!model.canChangeVersions)
                    Button("Remove Version…") { model.confirmRemovingVersion(open) }
                        .disabled(!model.canChangeVersions)
                }
            } label: {
                Label(model.openEditName, systemImage: "square.on.square")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!model.canOpenVersions)
            .help("The photo's versions: each is another edit of it, with its own history and snapshots")
            .automationIdentifier("filmstrip.versions")
        }
    }

    private func shown(_ version: UUID?) -> Binding<Bool> {
        Binding(get: { model.openVersion == version }, set: {
            if $0 {
                model.showVersion(version)
            }
        })
    }
}

/// The open photo's name, size and sensor.
private struct FilmstripPhotoInfo: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        if let info = model.info {
            Text(info.fileName)
            Text("\(info.pixelSize.width) × \(info.pixelSize.height)  ·  \(info.sensorDescription)")
                .foregroundStyle(Theme.tertiaryLabel)
        }
    }
}

/// The pin that keeps the floating filmstrip shown (UX-43), filled while it does: a click turns Hide Automatically off
/// or on, as the menus' item and Settings' switch do.
private struct FilmstripPin: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        let pinned = !model.filmstripHidesAutomatically
        Toggle(isOn: Binding(
            get: { !model.filmstripHidesAutomatically },
            set: { model.filmstripHidesAutomatically = !$0 },
        )) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .frame(width: 26, height: 22)
                .foregroundStyle(Theme.secondaryLabel)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .help(pinned ? "Hide the filmstrip automatically, once the pointer leaves it"
            : "Keep the filmstrip shown, with the photo fitted above it")
        .accessibilityLabel("Pin Filmstrip")
        .automationIdentifier("filmstrip.pin")
    }
}

/// "Focus stack detected: 25 frames" with Merge and dismiss; the frame range shows as help.
private struct StackSuggestionBanner: View {
    let suggestion: StackSuggestion
    @Environment(EditorModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.down.right")
            Text("Focus stack detected: \(suggestion.frames.count) frames")
                .foregroundStyle(Theme.secondaryLabel)
                .help(range)
            Button("Merge") { model.mergeStack(suggestion) }
                .buttonStyle(.link)
            Button {
                model.dismissStack(suggestion)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var range: String {
        let names = suggestion.frames.map { $0.deletingPathExtension().lastPathComponent }
        return "\(names.first ?? "") – \(names.last ?? "")"
    }
}
