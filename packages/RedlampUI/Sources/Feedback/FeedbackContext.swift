import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary

/// The open photo, its edit, the editor's state and the session's activity, read once when a
/// report is started, so the sheet previews exactly what will be sent.
///
/// It reads only what Redlamp already shows. Location and serial numbers aren't in any of it:
/// Redlamp never reads them into its own types, and this never asks ImageIO for them.
public struct FeedbackContext: Sendable {
    public struct Photo: Codable, Sendable, Hashable {
        public var alias: String
        public var fileName: String
        /// "CR3 (raw, Bayer RGGB)".
        public var format: String
        public var camera: String?
        public var lens: String?
        public var exposure: String?
        public var size: String
        public var asShotWhiteBalance: String?
        public var embeddedLook: String?
        public var lensCorrection: String?
        /// "APFS, internal", "smbfs, network", "iCloud Drive".
        public var volume: String?
        public var protection: String?
    }

    public struct Edit: Codable, Sendable, Hashable {
        public struct Group: Codable, Sendable, Hashable {
            public var panel: String
            public var values: [String]
        }

        public var processVersion: Int
        public var treatment: String
        public var baseLook: String
        public var whiteBalance: String
        public var recipe: String?
        public var settings: [Group]
        public var pointCurve: Bool
        public var masks: [String]
        public var crop: String?
        public var orientation: String?
        public var spots: Int
        public var snapshots: Int
    }

    public struct State: Codable, Sendable, Hashable {
        public var tool: String
        public var panels: [String]
        public var zoom: String
        public var beforeAfter: String?
        public var selectedMask: String?
        public var focusedSlider: String?
        public var folderPhotos: Int?
        public var selectedPhotos: Int
        public var hidden: [String]
    }

    public var captured: Date
    public var photo: Photo?
    public var edit: Edit?
    public var state: State
    /// Messages on screen when the report was started.
    public var messages: [String]
    /// This session's steps, oldest first; a step after the current one has been undone.
    public var history: [String]
    public var historyIndex: Int
    public var activity: [ActivityLog.Event]
    /// Whether the activity log was on; off, a report holds no activity and says so.
    public var activityLog: Bool
    public var photos: [PhotoName]
    /// Folders the app knows about, for redaction.
    public var folders: [String]
    /// The titles of the albums kept in Apple Photos, and of Photos' folders holding them (LIB-62), for redaction.
    public var albums: [String]
    public var albumFolders: [String]
    /// Photos' identifiers of the photo the report is on (LIB-62), for redaction: its local and cloud identifiers, and
    /// its key in Redlamp's cache.
    public var identifiers: [String]
    /// The photo's edit in the sidecar format (`docs/recipes/sidecar-format.md`), to reproduce it.
    public var sidecar: Data?
    /// The feature the person was most likely using.
    public var suggestion: String?
    /// The photo kept in Apple Photos the report is on, whose row `readApplePhotos(from:)` reads.
    var applePhotosPhoto: URL?

    public var suggestedTopic: FeedbackTopic? {
        suggestion.flatMap(FeedbackArea.topic)
    }

    public init(
        captured: Date, photo: Photo? = nil, edit: Edit? = nil, state: State, messages: [String] = [],
        history: [String] = [], historyIndex: Int = 0, activity: [ActivityLog.Event] = [], activityLog: Bool = true,
        photos: [PhotoName] = [], folders: [String] = [], albums: [String] = [], albumFolders: [String] = [],
        identifiers: [String] = [], sidecar: Data? = nil, suggestion: String? = nil,
    ) {
        self.captured = captured
        self.photo = photo
        self.edit = edit
        self.state = state
        self.messages = messages
        self.history = history
        self.historyIndex = historyIndex
        self.activity = activityLog ? activity : []
        self.activityLog = activityLog
        self.photos = photos
        self.folders = folders
        self.albums = albums
        self.albumFolders = albumFolders
        self.identifiers = identifiers
        self.sidecar = sidecar
        self.suggestion = suggestion
    }

    func redactor(keepingFileNames: Bool) -> FeedbackRedactor {
        FeedbackRedactor(
            folders: folders, photos: photos, albums: albums, albumFolders: albumFolders, identifiers: identifiers,
            keepsFileNames: keepingFileNames,
        )
    }
}

// MARK: - Reading the editor

public extension FeedbackContext {
    @MainActor
    static func capture(from model: EditorModel, now: Date = Date()) -> FeedbackContext {
        let photo = model.info.map { photoSummary($0, model: model) } ?? awaitingOriginal(model)
        let kept = keptInApplePhotos(model)
        var context = FeedbackContext(
            captured: now,
            photo: photo,
            edit: model.info == nil ? nil : editSummary(model),
            state: state(model),
            messages: messages(model),
            history: model.history.map(\.name),
            historyIndex: model.historyIndex,
            activity: model.activity.events,
            activityLog: model.activity.isOn,
            photos: model.activity.photoNames.map { PhotoName(alias: $0.alias, fileName: $0.fileName) },
            folders: ([model.folder] + model.library.roots.map(\.url) + applePhotosFolders(model))
                .compactMap { $0?.path },
            albums: kept.albums,
            albumFolders: kept.folders,
            identifiers: applePhotosIdentifiers(model),
            sidecar: model.info == nil ? nil : try? sidecarEncoder.encode(model.sidecarToSave),
            suggestion: suggestion(model),
        )
        context.applePhotosPhoto = model.selection.flatMap { model.library.originals?.owns($0) == true ? $0 : nil }
        return context
    }

    /// What the index knows of the photo kept in Apple Photos the report is on (LIB-62): its local and cloud
    /// identifiers, for redaction, and, while its original isn't open, its size as Photos gives it. The albums kept
    /// are read again, for a crash or a hang's report, whose earlier session's activity may name them too.
    @MainActor
    mutating func readApplePhotos(from model: EditorModel) async {
        (albums, albumFolders) = Self.keptInApplePhotos(model)
        guard let url = applePhotosPhoto, let index = model.library.service?.core?.index,
              let id = model.library.photoID(of: url),
              let row = try? await index.read({ try $0.applePhotosRow(ofPhoto: id) })
        else { return }
        identifiers += [row.local, row.cloud].compactMap(\.self).filter { !$0.isEmpty && !identifiers.contains($0) }
        if photo?.size.isEmpty == true, let width = row.pixelWidth, let height = row.pixelHeight {
            photo?.size = String(
                format: "%d × %d (%.1f MP)", width, height, Double(width) * Double(height) / 1_000_000,
            )
        }
    }

    /// The feature the person was most likely using: a message on screen first, then an open
    /// workspace, then the tool and what's selected in it, then the last edit.
    @MainActor
    static func suggestion(_ model: EditorModel) -> String? {
        if model.saveError != nil || !model.failedSaves.isEmpty {
            return "saving.not-saved"
        }
        if model.errorMessage != nil {
            return model.formatNotSupportedYet ? "raw.unsupported" : "raw.wont-open"
        }
        if model.stackWorkspace != nil {
            return "focus-stacking.workspace"
        }
        if model.module == .library {
            return model.libraryView == .loupe ? "library.loupe" : "library.grid"
        }
        switch model.activeTool {
        case .masking:
            let component = model.selectedMask?.components.first { $0.id == model.selectedComponentID }
                ?? model.selectedMask?.components.first
            if let kind = component?.shape.kind ?? model.drawingKind ?? model.aiMaskProgress {
                return FeedbackArea.featureID(for: kind)
            }
            return model.maskMessage != nil ? "masking.models" : "masking.other"
        case .heal:
            return FeedbackArea.featureID(for: model.spotMode, pick: model.spotPick)
        case .crop, .redEye:
            return FeedbackArea.featureID(for: model.activeTool)
        case .edit:
            if let parameter = model.focusedParameter ?? model.editParameter,
               let id = FeedbackArea.featureID(for: parameter) {
                return id
            }
            guard model.history.indices.contains(model.historyIndex) else { return nil }
            let step = model.history[model.historyIndex]
            let action = step.action
            if case .baseLook = action, model.recipe.baseLook.isFirmwareModel {
                return "develop.firmware-model"
            }
            if case .baseLook = action, model.recipe.baseLook.isAdobeProfile {
                return "develop.adobe-profiles"
            }
            if step.id == model.baseLooksStep {
                return "recipes.base-looks"
            }
            return FeedbackArea.featureID(for: action)
        }
    }

    private static var sidecarEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    @MainActor
    private static func photoSummary(_ info: ImageInfo, model: EditorModel) -> Photo {
        let format = info.url.pathExtension.uppercased()
        let kind = info.isRaw ? "raw, \(info.sensorDescription)" : info.sensorDescription
        return Photo(
            alias: model.activity.alias(for: info.url),
            fileName: info.fileName,
            format: "\(format) (\(kind))",
            camera: info.cameraName,
            lens: info.lens,
            exposure: info.exposureSummary.isEmpty ? nil : info.exposureSummary.joined(separator: ", "),
            size: String(
                format: "%d × %d (%.1f MP)", info.pixelSize.width, info.pixelSize.height, info.pixelSize.megapixels,
            ),
            asShotWhiteBalance: info.asShotWhiteBalance.map { "\(Int($0.temperature)) K, tint \(Int($0.tint))" },
            embeddedLook: info.embeddedBaseLook?.name,
            lensCorrection: info.lensCorrection?.source.name,
            volume: volume(of: info.url, model: model),
            protection: model.notice,
        )
    }

    /// This photo for a photo kept in Apple Photos that Develop shows from its preview while its original downloads,
    /// or once it didn't (LIB-60): what's known of it before it opens, its size read from Photos by
    /// `readApplePhotos(from:)`.
    @MainActor
    private static func awaitingOriginal(_ model: EditorModel) -> Photo? {
        guard let url = model.download?.url, url == model.selection else { return nil }
        return Photo(
            alias: model.activity.alias(for: url),
            fileName: url.lastPathComponent,
            format: url.pathExtension.uppercased(),
            size: "",
            volume: volume(of: url, model: model),
            protection: model.notice,
        )
    }

    /// "Apple Photos, in iCloud only" for a photo kept in Apple Photos (LIB-62), with where its original is: on this
    /// Mac, in iCloud only, waiting to download or downloading. Any other photo's volume, as `volume(of:)` names it.
    @MainActor
    private static func volume(of url: URL, model: EditorModel) -> String? {
        guard let originals = model.library.originals, originals.owns(url) else { return volume(of: url) }
        let original = switch originals.status(of: url) {
        case let .downloading(progress) where progress.fraction > 0:
            "downloading, \(Int((progress.fraction * 100).rounded()))%"
        case .downloading: "downloading"
        case .queued: "waiting to download"
        case nil: originals.isLocal(url) ? "on this Mac" : "in iCloud only"
        }
        return "Apple Photos, \(original)"
    }

    /// The titles of the albums kept in Apple Photos and of Photos' folders holding them (LIB-62), but Photos Chosen
    /// for Redlamp, which is Redlamp's.
    @MainActor
    private static func keptInApplePhotos(_ model: EditorModel) -> (albums: [String], folders: [String]) {
        let kept = model.librarySources.applePhotos.collections
            .filter { $0.id != ApplePhotosCollection.chosenForRedlamp.id }
        return (kept.filter { $0.kind != .folder }.map(\.title), kept.filter { $0.kind == .folder }.map(\.title))
    }

    /// Where Redlamp keeps photos kept in Apple Photos (LIB-62), for redaction: their root in Redlamp's cache and their
    /// sidecars' on this Mac, and the active photo's folder in each, named for its key.
    @MainActor
    private static func applePhotosFolders(_ model: EditorModel) -> [URL] {
        guard let originals = model.library.originals else { return [] }
        let root = ApplePhotosPlace.root(in: originals.paths)
        let sidecars = originals.paths.sidecars.appending(path: ApplePhotosPlace.volume, directoryHint: .isDirectory)
            .appending(path: ApplePhotosPlace.library, directoryHint: .isDirectory)
        guard let url = model.selection, originals.owns(url) else { return [root, sidecars] }
        return [
            root, sidecars, url.deletingLastPathComponent(),
            model.library.sidecars.locator.url(for: url).deletingLastPathComponent(),
        ]
    }

    /// Photos' identifiers of the active photo, for redaction: a photo kept in Apple Photos' key in Redlamp's cache
    /// (LIB-62), whose local and cloud identifiers `readApplePhotos(from:)` reads, and the asset a photo copied from
    /// Photos came from, as its sidecar names it (LIB-54).
    @MainActor
    private static func applePhotosIdentifiers(_ model: EditorModel) -> [String] {
        var identifiers: [String] = []
        if let url = model.selection, model.library.originals?.owns(url) == true {
            identifiers.append(url.deletingLastPathComponent().lastPathComponent)
        }
        if model.info != nil, let origin = model.sidecarToSave.metadata?.applePhotos {
            identifiers += [origin.id, origin.cloud].compactMap(\.self)
        }
        return identifiers.filter { !$0.isEmpty }
    }

    private static func volume(of url: URL) -> String? {
        let keys: Set<URLResourceKey> = [
            .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRemovableKey, .isUbiquitousItemKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys.union([.volumeTypeNameKey])) else { return nil }
        if values.isUbiquitousItem == true {
            return "iCloud Drive"
        }
        let place = if values.volumeIsLocal == false {
            "network"
        } else if values.volumeIsInternal == true {
            "internal"
        } else if values.volumeIsRemovable == true {
            "removable"
        } else {
            "external"
        }
        return [values.volumeTypeName, place].compactMap(\.self).joined(separator: ", ")
    }

    @MainActor
    private static func editSummary(_ model: EditorModel) -> Edit {
        let recipe = model.recipe
        let settings = PanelID.allCases.compactMap { panel -> Edit.Group? in
            let values = panel.parameters.filter(model.isEdited)
                .map { "\($0.displayName) \($0.spec.formatted(recipe[$0]))" }
            return values.isEmpty ? nil : Edit.Group(panel: panel.title, values: values)
        }
        let crop = recipe.crop == .full ? nil : String(
            format: "%.0f%% × %.0f%% of the photo",
            (recipe.crop.right - recipe.crop.left) * 100, (recipe.crop.bottom - recipe.crop.top) * 100,
        )
        let orientation = recipe.orientation.isIdentity ? nil : [
            recipe.orientation.quarterTurns % 4 == 0 ? nil : "turned \(recipe.orientation.quarterTurns % 4 * 90)°",
            recipe.orientation.mirrored ? "flipped" : nil,
        ].compactMap(\.self).joined(separator: ", ")
        return Edit(
            processVersion: recipe.processVersion,
            treatment: recipe.treatment.name,
            baseLook: "\(recipe.baseLook.name) (\(Int(recipe.baseLook.amount.rounded())))",
            whiteBalance: recipe.whiteBalanceMode.name,
            recipe: recipe.appliedRecipe.map { "\($0.name) (\(Int($0.amount.rounded())))" },
            settings: settings,
            pointCurve: recipe.hasPointCurve,
            masks: recipe.masks.map(describe),
            crop: crop,
            orientation: orientation,
            spots: recipe.spots.count,
            snapshots: model.snapshots.count,
        )
    }

    /// "“Sky”: Sky, subtract Brush; Exposure −0.60, Dehaze +15; amount 100; Apple Vision r1".
    private static func describe(_ mask: MaskLayer) -> String {
        var parts = [ActivityRecorder.describe(MaskOutline(mask))]
        let adjustments = mask.adjustments.keys
            .sorted { $0.displayName < $1.displayName }
            .map { "\($0.displayName) \($0.spec.formatted(mask.adjustments[$0] ?? 0))" }
        if !adjustments.isEmpty {
            parts.append(adjustments.joined(separator: ", "))
        }
        parts.append("amount \(Int(mask.amount.rounded()))")
        let models = Set(mask.components.compactMap { component -> String? in
            guard case let .ai(ai) = component.shape else { return nil }
            return "\(ai.provider) r\(ai.revision)" + (ai.osBuild.map { " on \($0)" } ?? "")
        })
        if !models.isEmpty {
            parts.append(models.sorted().joined(separator: ", "))
        }
        return "“\(mask.name)”\(mask.isVisible ? "" : " (hidden)")\(mask.inverted ? " (inverted)" : ""): "
            + parts.joined(separator: "; ")
    }

    @MainActor
    private static func state(_ model: EditorModel) -> State {
        let mask = model.selectedMaskID.flatMap { id in model.maskOutlines.first { $0.id == id } }
        let hidden = [
            model.leftPanelVisible ? nil : "left panel",
            model.rightPanelVisible ? nil : "right panel",
            model.filmstripVisible ? nil : "filmstrip",
        ].compactMap(\.self)
        return State(
            tool: model.activeTool.title,
            panels: PanelID.allCases.filter(model.expandedPanels.contains).map(\.title),
            zoom: "\(model.canvas.zoomPercent)%",
            beforeAfter: model.showBefore ? model.compareLayout.title : nil,
            selectedMask: mask.map { "“\($0.name)”: \(ActivityRecorder.describe($0))" },
            focusedSlider: model.focusedParameter?.displayName,
            folderPhotos: model.folder == nil ? nil : model.library.count,
            selectedPhotos: model.selectedCount,
            hidden: hidden,
        )
    }

    @MainActor
    private static func messages(_ model: EditorModel) -> [String] {
        [
            model.errorMessage, model.saveError?.message, model.notice, model.download?.text, model.maskMessage,
            model.pickMessage, model.dustMessage, model.findMessage, model.exportStatus,
            model.stackWorkspace?.errorMessage,
            model.failedSaves.isEmpty ? nil : "\(model.failedSaves.count) photos have edits that couldn't be saved",
        ].compactMap(\.self)
    }
}
