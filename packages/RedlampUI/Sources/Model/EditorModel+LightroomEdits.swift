import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary
import RedlampRecipes

/// Convert Lightroom Edits…, while its sheet is open (EDT-12): the photos it looks at, what it found in them
/// before anything is written, the batch, and its outcome with Undo.
public struct LightroomConversion: Identifiable {
    public enum Stage {
        case reading
        case report(LightroomXMPScan)
        case converting
        /// Done: the photos converted, and how the batch went when there's something to say.
        case done(converted: Int, report: String?)
    }

    public let id = UUID()
    /// "the 12 selected photos", "the 240 photos in Shoot".
    public var subject: String
    public var stage: Stage = .reading

    /// What was found, once the photos are read.
    public var scan: LightroomXMPScan? {
        if case let .report(scan) = stage {
            return scan
        }
        return nil
    }
}

/// Develop's notice on an edit converted from Lightroom (`EditRecipe.provenance`): where it came from and how
/// fully it converted, with the settings approximated and left out by their Camera Raw names.
public struct ProvenanceNotice: Equatable {
    public var title: String
    public var leftOut: [String]
    public var approximated: [String]
    /// The edit came from XMP, which can be converted again.
    public var canConvertAgain: Bool

    init(_ provenance: EditProvenance) {
        let origin = switch provenance.source {
        case .lightroomCatalog: "From Lightroom Classic"
        case .xmpSidecar: "From Lightroom’s XMP sidecar"
        case .embeddedXMP: "From Lightroom’s XMP in the photo"
        default: "From another app"
        }
        func settings(_ count: Int) -> String {
            "\(count) setting\(count == 1 ? "" : "s")"
        }
        let parts = [
            provenance.leftOut.isEmpty ? nil : "\(settings(provenance.leftOut.count)) left out",
            provenance.approximated.isEmpty ? nil : "\(settings(provenance.approximated.count)) approximated",
        ].compactMap(\.self)
        title = "\(origin): \(parts.isEmpty ? "every setting converted" : parts.joined(separator: ", "))"
        leftOut = provenance.leftOut
        approximated = provenance.approximated
        canConvertAgain = [.xmpSidecar, .embeddedXMP].contains(provenance.source)
    }
}

public extension EditorModel {
    /// The open photo's provenance notice, for an edit converted from Lightroom.
    var provenanceNotice: ProvenanceNotice? {
        info == nil ? nil : recipe.provenance.map(ProvenanceNotice.init)
    }

    var canConvertLightroomEdits: Bool {
        lightroomConversion == nil && settingsSync
            .progress == nil && (isMultiSelecting || !library.items.allRows.isEmpty)
    }

    /// Library › Convert Lightroom Edits…: the selection's photos, or with one photo selected, the folder's or
    /// source's, read off the main thread for the report, which nothing is written before.
    func convertLightroomEdits() {
        guard canConvertLightroomEdits else { return }
        let photos: SelectedPhotos
        let subject: String
        if isMultiSelecting {
            photos = selectionForAction()
            subject = "the \(photos.count) selected photos"
        } else {
            photos = SelectedPhotos(library.items.allRows.map(\.url))
            let place = folder.map { " in \($0.lastPathComponent)" } ?? ""
            subject = photos.count == 1 ? "the photo\(place)" : "the \(photos.count) photos\(place)"
        }
        saveNow()
        let conversion = LightroomConversion(subject: subject)
        lightroomConversion = conversion
        activity.record(.action, "Convert Lightroom Edits…: reading \(subject)")
        let placement = library.sidecars
        Task {
            let urls = await photos.all()
            let scan = await Task.detached(priority: .userInitiated) {
                LightroomXMPScan.scan(urls) { LightroomPhotoXMP.redlampEdit(of: $0, in: placement.store(for: $0)) }
            }.value
            guard lightroomConversion?.id == conversion.id else { return }
            lightroomConversion?.stage = .report(scan)
        }
    }

    /// The report's Convert: the photos it found with a Lightroom edit and none in Redlamp, as a batch whose Undo
    /// puts them back. The photo open in Develop is converted there, as a step of its history.
    func confirmLightroomConversion() {
        guard let scan = lightroomConversion?.scan, !scan.conversions.isEmpty else { return }
        let conversions = Dictionary(scan.conversions.map { ($0.photo, $0.imported) }) { first, _ in first }
        lightroomConversion?.stage = .converting
        activity.record(.action, "Convert Lightroom Edits: \(scan.conversions.count) photos")
        saveNow()
        settingsSync.run(
            .convertLightroom(conversions), on: scan.conversions.map(\.photo), title: Self.conversionTitle,
            done: written,
        )
        let id = lightroomConversion?.id
        Task {
            await settingsSync.idle()
            guard lightroomConversion?.id == id else { return }
            lightroomConversion?.stage = .done(converted: scan.conversions.count, report: settingsSync.report)
        }
    }

    /// The sheet's Undo, once the batch is done: every photo it converted not edited since put back.
    func undoLightroomConversion() {
        undoSync()
        lightroomConversion = nil
    }

    func closeLightroomConversion() {
        lightroomConversion = nil
    }

    /// Develop's Convert Again: the open photo's Lightroom edit converted from its XMP again, replacing its edit
    /// as a step of its history, and the edit it replaces kept as a snapshot.
    func convertLightroomEditAgain() {
        guard let url = selection, info != nil, !isReadOnly, provenanceNotice?.canConvertAgain == true else { return }
        let visit = currentVisit
        Task {
            let read = await Task.detached {
                LightroomPhotoXMP.edit(for: url, rawBeside: { LightroomPhotoXMP.rawBeside(url) })
                    .map { ($0, LightroomPhotoXMP.context(of: url)) }
            }.value
            guard currentVisit == visit, let info else { return }
            guard let (edit, photo) = read else { return }
            let converted = Self.converting(edit, photo: photo, info)
            keepSnapshot(of: recipe, named: "Before Convert Again")
            commit(withPhotoAnchor(Self.asShot(converted, info), of: info, changed: true), .recipe, "Convert Again")
            activity.record(.edit, "\(activity.alias(for: url)): its Lightroom edit converted again")
        }
    }
}

extension EditorModel {
    static let conversionTitle = "Convert Lightroom Edits"
    /// The first step of a photo whose Lightroom edit was converted as it opened.
    static let convertedStepTitle = "Converted from Lightroom"

    /// `edit` converted for the photo `opened` describes: its size as stored and its camera's orientation as
    /// ImageIO read them (`photo`), else as the engine decoded it, with what only the engine knows of the file.
    static func converting(_ edit: LightroomXMPEdit, photo: LightroomPhotoContext?, _ opened: ImageInfo) -> EditRecipe {
        var context = photo ?? LightroomPhotoContext(size: opened.pixelSize)
        context.isRaw = opened.isRaw
        context.hasLensCorrection = opened.lensCorrection != nil
        context.embeddedLook = opened.embeddedBaseLook
        return LightroomPhoto.convert(edit.settings, photo: context, source: edit.source).recipe
    }
}

public extension LightroomXMPScan {
    /// What the report says of each reason settings are left out.
    static func title(of reason: LightroomImportReport.Reason) -> String {
        switch reason {
        case .notYetChecked: "Not yet checked against Lightroom: masks, spots, Upright, panel switches, Point Color"
        case .earlierProcess: "Process 2003 or 2010 tone, kept at Redlamp’s defaults until EDT-31"
        case let .notInRedlamp(row): "Not in Redlamp yet" + (row.map { " (\($0))" } ?? "")
        case .unreadable: "Values that can’t be read"
        case .unknown: "Settings Redlamp doesn’t know"
        }
    }

    /// The report's lines, as the sheet shows them.
    var lines: [String] {
        func number(_ count: Int) -> String {
            "\(count) photo\(count == 1 ? "" : "s")"
        }
        var lines = [
            "\(number(found)) with a Lightroom edit; \(number(conversions.count)) to convert",
            "Convert fully: \(number(photos(.full).count))",
            "With approximations: \(number(photos(.approximated).count))",
            "With settings left out: \(number(photos(.leftOut).count))",
        ]
        lines += reasons.map { "  \(Self.title(of: $0.reason)): \(number($0.photos.count))" }
        if !edited.isEmpty {
            lines.append("Already edited in Redlamp, keeping their edit: \(number(edited.count))")
        }
        if !converted.isEmpty {
            lines.append("Converted before, not converted again: \(number(converted.count))")
        }
        if !unsized.isEmpty {
            lines.append("Converted when opened, as their size can’t be read before: \(number(unsized.count))")
        }
        if !unreadable.isEmpty {
            lines.append("Left alone, as their edit can’t be read: \(number(unreadable.count))")
        }
        return lines
    }
}
