import Observation
import RedlampDesign
import RedlampLibrary
import SwiftUI

/// Settings › Library: the library's state, the metadata it shares with other apps (LIB-24, DEC-44), and whether the
/// new photos in the albums imports from Apple Photos follow are imported without asking (LIB-55).
/// Other apps' ratings, labels, keywords and captions are always read; standard `.xmp` sidecars are
/// written beside the photos only once it's turned on, with labels in the names the chosen app reads,
/// and kept in the library's index, where `redlamp library xmp` reads them too. Turning writing on or
/// off says what becomes of the photos already in the library first, and nothing is done to them
/// unless Write for All Photos is asked for.
struct LibrarySettings: View {
    @State private var model: LibrarySettingsModel
    @Bindable private var applePhotos = ApplePhotosPreferences.shared

    init(library: LibraryService) {
        _model = State(initialValue: LibrarySettingsModel(library: library))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Index") {
                    Text(model.status)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("settings.library.state")
                }
            } header: {
                Text("Library")
            }
            Section {
                Toggle("Write .xmp sidecars for other apps", isOn: Binding(
                    get: { model.settings.writes },
                    set: { model.ask(writes: $0) },
                ))
                .accessibilityIdentifier("settings.library.xmp.write")
                Picker("Label names", selection: Binding(
                    get: { model.settings.conventions.labels },
                    set: { model.set(labels: $0) },
                )) {
                    Text("Lightroom Classic").tag(XMPLabelNames.lightroom)
                    Text("Lightroom Classic’s Review Status").tag(XMPLabelNames.lightroomReviewStatus)
                    Text("Adobe Bridge").tag(XMPLabelNames.bridge)
                }
                .accessibilityIdentifier("settings.library.xmp.labels")
                Toggle("Also as Photo Mechanic’s color classes", isOn: Binding(
                    get: { model.settings.conventions.urgency },
                    set: { model.set(urgency: $0) },
                ))
                .help("Labels in photoshop:Urgency, which Capture One links to its color tags")
                .accessibilityIdentifier("settings.library.xmp.urgency")
                if model.settings.writes {
                    allPhotos
                }
            } header: {
                Text("Other Apps")
            } footer: {
                Text(model.footer)
                    .formFooter()
            }
            Section {
                Toggle("Import new photos from followed albums automatically", isOn: $applePhotos.importsAutomatically)
                    .accessibilityIdentifier("settings.library.apple-photos.automatic")
                Picker("Keep downloaded originals up to", selection: Binding(
                    get: { model.originals?.budget ?? ApplePhotosOriginals.defaultBudget },
                    set: { model.setOriginalsBudget($0) },
                )) {
                    ForEach(LibrarySettingsModel.originalsBudgets, id: \.self) { bytes in
                        Text(LibrarySettingsModel.size(bytes)).tag(bytes)
                    }
                }
                .accessibilityIdentifier("settings.library.apple-photos.budget")
                LabeledContent("Downloaded originals") {
                    HStack(spacing: 8) {
                        Text(model.originalsUsed)
                            .accessibilityIdentifier("settings.library.apple-photos.used")
                        Button("Empty Cache") { model.emptyOriginals() }
                            .disabled(model.originals.map { $0.files == 0 } ?? true)
                            .accessibilityIdentifier("settings.library.apple-photos.empty")
                    }
                }
            } header: {
                Text("Apple Photos")
            } footer: {
                Text(
                    "Each import from Apple Photos follows the albums it chose, and the Library panel’s From Apple "
                        + "Photos offers the new photos in them. Turned on, they’re imported with the last import’s "
                        + "settings a minute after Photos last changes, while Redlamp runs. Nothing is removed from "
                        + "Redlamp when a photo leaves Photos or an album. Photos kept in Apple Photos download their "
                        + "originals from iCloud to be edited, seen at full size or exported; Redlamp keeps them on "
                        + "this Mac up to the size chosen, the least recently opened removed first.",
                )
                .formFooter()
            }
            if let failure = model.failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                }
            }
        }
        .overlayScrollers()
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!model.isAvailable)
        .task(id: model.library.state) {
            await model.countPhotos()
            await model.readOriginals()
        }
        .alert(
            model.confirming.map(model.title) ?? "",
            isPresented: Binding(get: { model.confirming != nil }, set: {
                if !$0 {
                    model.cancel()
                }
            }),
            presenting: model.confirming,
        ) { confirmation in
            switch confirmation {
            case .turningOn:
                Button("Turn On") { model.confirm() }
                    .keyboardShortcut(.defaultAction)
                Button("Turn On and Write All Photos") { model.confirm(writingAll: true) }
            case .turningOff:
                Button("Turn Off") { model.confirm() }
                    .keyboardShortcut(.defaultAction)
            case .writingAll:
                Button("Write All") { model.confirm() }
                    .keyboardShortcut(.defaultAction)
            }
            Button("Cancel", role: .cancel) { model.cancel() }
        } message: { confirmation in
            Text(model.message(confirmation))
        }
    }

    @ViewBuilder private var allPhotos: some View {
        if model.library.isWritingAllXMP {
            LabeledContent {
                Button("Stop") { model.library.stopWritingXMPForAllPhotos() }
            } label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.library.xmpRemaining.map { "Writing .xmp: \(LibrarySettingsModel.photos($0)) left" }
                        ?? "Writing .xmp…")
                }
            }
        } else {
            Button("Write .xmp for All Photos…") { model.confirming = .writingAll }
                .accessibilityIdentifier("settings.library.xmp.all")
        }
    }
}

/// What Settings › Library shows and changes: the library's state, and its choices for other apps'
/// metadata, a change to writing confirmed before it's made.
@MainActor
@Observable
final class LibrarySettingsModel {
    enum Confirmation: Equatable {
        case turningOn, turningOff, writingAll
    }

    let library: LibraryService
    private(set) var photos: Int?
    /// The change waiting for its confirmation.
    var confirming: Confirmation?
    private(set) var failure: String?

    init(library: LibraryService) {
        self.library = library
    }

    var settings: XMPSettings {
        library.xmpSettings ?? XMPSettings()
    }

    /// The library is open, and its settings read.
    var isAvailable: Bool {
        library.xmpSettings != nil
    }

    func countPhotos() async {
        photos = await library.photoCount()
    }

    // MARK: - Originals from Apple Photos (LIB-60)

    /// The budgets Settings offers for the originals downloaded from iCloud: 20 GB unless another is chosen.
    static let originalsBudgets: [Int64] = [5, 10, 20, 50, 100, 200].map { $0 * 1_000_000_000 }

    /// The originals downloaded from iCloud the library keeps, and its budget, once read.
    private(set) var originals: ApplePhotosOriginals.Usage?

    /// What they take: 3.2 GB in 84 originals.
    var originalsUsed: String {
        guard let originals else { return "…" }
        guard originals.files > 0 else { return "None" }
        return "\(Self.size(originals.bytes)) in \(originals.files) \(originals.files == 1 ? "original" : "originals")"
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func readOriginals() async {
        originals = await library.originals?.usage()
    }

    func setOriginalsBudget(_ bytes: Int64) {
        guard let cache = library.originals else { return }
        Task {
            do {
                try await cache.setBudget(bytes)
            } catch {
                failure = "The budget for originals couldn't be kept: \(error.localizedDescription)"
            }
            originals = await cache.usage()
        }
    }

    /// Empty Cache: every downloaded original but the one open and those being read goes, downloaded again when it's
    /// next needed.
    func emptyOriginals() {
        guard let cache = library.originals else { return }
        Task {
            await cache.empty()
            originals = await cache.usage()
        }
    }

    /// Writing turned on or off, as the toggle asks: to be confirmed.
    func ask(writes: Bool) {
        guard isAvailable, writes != settings.writes else { return }
        confirming = writes ? .turningOn : .turningOff
    }

    func cancel() {
        confirming = nil
    }

    /// Makes the change waiting for its confirmation; with `writingAll`, writing turned on writes every
    /// photo's `.xmp` too.
    @discardableResult
    func confirm(writingAll: Bool = false) -> Task<Void, Never>? {
        guard let confirmation = confirming else { return nil }
        confirming = nil
        guard confirmation != .writingAll else {
            library.writeXMPForAllPhotos()
            return nil
        }
        var changed = settings
        changed.writes = confirmation == .turningOn
        return Task {
            if await save(changed), writingAll, changed.writes {
                library.writeXMPForAllPhotos()
            }
        }
    }

    @discardableResult
    func set(labels: XMPLabelNames) -> Task<Void, Never> {
        var changed = settings
        changed.conventions.labels = labels
        return Task { await save(changed) }
    }

    @discardableResult
    func set(urgency: Bool) -> Task<Void, Never> {
        var changed = settings
        changed.conventions.urgency = urgency
        return Task { await save(changed) }
    }

    @discardableResult
    private func save(_ changed: XMPSettings) async -> Bool {
        let saved = await library.setXMPSettings(changed)
        failure = saved ? nil : "The library’s settings couldn’t be saved: is its disk full?"
        return saved
    }

    // MARK: - What it says

    var status: String {
        switch library.state {
        case .opening where library.isUpdatingIndex:
            "Being updated for this version of Redlamp. Search waits until it’s done."
        case .opening:
            "Opening…"
        case .ready:
            photos.map(Self.photos) ?? "Open"
        case let .unavailable(reason):
            "Not available, so Folders lists folders itself: \(reason)"
        }
    }

    var footer: String {
        let reading = """
        Ratings, flags, labels, keywords, titles, captions and capture times other apps leave in .xmp \
        sidecars and in the photos themselves are always read, and their later changes taken in.
        """
        guard settings.writes else {
            return reading + """
             Turned on, each change Redlamp makes to them also writes a standard .xmp beside the photo, for \
            Lightroom Classic, Bridge, Capture One and Photo Mechanic. The photos themselves are never written.
            """
        }
        return reading + """
         Each change Redlamp makes to them writes the photo’s .xmp beside it, keeping what other apps wrote \
        there; a photo not changed since keeps the .xmp it has. Labels already written keep their names \
        until they change.
        """
    }

    func title(_ confirmation: Confirmation) -> String {
        switch confirmation {
        case .turningOn: "Write .xmp sidecars for other apps?"
        case .turningOff: "Stop writing .xmp sidecars?"
        case .writingAll: "Write .xmp sidecars for \(photos.map { "all \(Self.photos($0))" } ?? "every photo")?"
        }
    }

    /// What the change does to the photos already in the library.
    func message(_ confirmation: Confirmation) -> String {
        let existing = photos.map { "The \(Self.photos($0)) already in the library are" }
            ?? "The photos already in the library are"
        switch confirmation {
        case .turningOn:
            return """
            From now on, each change you make to a photo’s rating, flag, label, keywords, title, caption or \
            capture time writes a standard .xmp beside it, keeping what other apps wrote there. \(existing) left \
            as they are until they change, unless you write them all now.
            """
        case .turningOff:
            return """
            The .xmp sidecars Redlamp wrote stay beside your photos, and other apps go on reading them, without \
            the changes you make from now on. Other apps’ changes are still taken in.
            """
        case .writingAll:
            return """
            Each photo’s .xmp gets the metadata its .redlamp sidecar holds, keeping what other apps wrote there, \
            and changes other apps made since are taken into the .redlamp first. It runs in the background, \
            between your own changes.
            """
        }
    }

    /// `1 photo`, `12,345 photos`.
    static func photos(_ count: Int) -> String {
        count == 1 ? "1 photo" : "\(count.formatted()) photos"
    }
}
