import Foundation
import RedlampLibrary

/// What the Apple Photos window shows (LIB-54), worked out from its model: one page at a time, the buttons in its
/// bottom bar, and the line beside them.
struct ApplePhotosScreen: Equatable {
    enum Page: Equatable {
        /// Asking for access, or why there's none.
        case access
        /// Reading albums, or counting them, with a line saying which.
        case working
        /// The albums, and To.
        case setup
        case review
        case progress
        case result
    }

    struct Button: Equatable {
        enum Kind: String, CaseIterable {
            case back, allow, openSettings, review, importPhotos, stop, resume, undo, showInLibrary, done
        }

        var kind: Kind
        var title: String
        var isEnabled = true
        var isDefault = false
    }

    /// An album's or a folder's row in the setup's lists.
    struct Album: Equatable, Identifiable {
        var id: String
        var title: String
        var depth: Int
        var isFolder: Bool
        var count: Int?
        var check: ApplePhotosImportModel.Check
    }

    struct Group: Equatable, Identifiable {
        var id: String
        var title: String
        var note: String?
        var albums: [Album]
    }

    /// A titled card of lines.
    struct Section: Equatable, Identifiable {
        var id: String
        var title: String
        var lines: [String]
    }

    struct Progress: Equatable {
        var title: String
        var done: Int
        var total: Int
        var fraction: Double
        var lines: [String]
    }

    var page: Page
    var heading = ""
    var message: [String] = []
    var groups: [Group] = []
    var chosenLine = ""
    var includesHidden = false
    var follows = true
    var options = true
    var sections: [Section] = []
    var stages: [ProgressStage] = []
    var progress: Progress?
    var problem: String?
    var buttons: [Button] = []
    var barNote = ""
}

extension ApplePhotosImportModel {
    var screen: ApplePhotosScreen {
        var screen: ApplePhotosScreen = switch phase {
        case .checking:
            ApplePhotosScreen(page: .working, heading: "Checking access to Photos…")
        case .access:
            accessScreen
        case .loading:
            ApplePhotosScreen(page: .working, heading: "Reading Photos’ albums…")
        case .choosing:
            setupScreen
        case .counting:
            ApplePhotosScreen(
                page: .working, heading: "Counting what the albums chosen hold…",
                message: ["Nothing is copied until you import."],
            )
        case .reviewing:
            reviewScreen
        case .importing, .stopping:
            progressScreen
        case .imported, .undoing, .undone:
            resultScreen
        }
        screen.problem = problem
        return screen
    }

    // MARK: - Access

    private var accessScreen: ApplePhotosScreen {
        let settings = "System Settings › Privacy & Security › Photos"
        let open = ApplePhotosScreen.Button(kind: .openSettings, title: "Open System Settings", isDefault: true)
        switch access {
        case .notDetermined:
            return ApplePhotosScreen(
                page: .access, heading: "Allow Redlamp to read Photos",
                message: [
                    "Redlamp copies the photos in the albums you choose into your folders, with their favourites, "
                        + "dates and albums. It only reads your Photos library and never changes it.",
                    "macOS asks you once. You can change your answer in \(settings).",
                ],
                buttons: [.init(kind: .allow, title: "Continue", isDefault: true)],
                barNote: "Continue asks macOS for access to Photos.",
            )
        case .denied:
            return ApplePhotosScreen(
                page: .access, heading: "Redlamp isn’t allowed to read Photos",
                message: [
                    "Access to Photos was turned off for Redlamp, so it can’t see your albums.",
                    "To import from Photos, turn Redlamp on in \(settings), then come back to this window.",
                ],
                buttons: [open],
            )
        case .restricted:
            return ApplePhotosScreen(
                page: .access, heading: "Photos is restricted on this Mac",
                message: [
                    "A profile or Screen Time on this Mac keeps apps from reading Photos, so Redlamp can’t import "
                        + "from it.",
                    "Whoever manages this Mac can allow it in \(settings).",
                ],
                buttons: [open],
            )
        case .limited, .authorized:
            return ApplePhotosScreen(
                page: .access, heading: "Redlamp can read only some of your photos",
                message: [
                    "Access to Photos is limited for Redlamp: it can read only the photos chosen for it, and none of "
                        + "your albums, so there are no albums to import.",
                    "To import albums, choose Full Access for Redlamp in \(settings), then come back to this window.",
                ],
                buttons: [open],
            )
        }
    }

    // MARK: - Setup

    private var setupScreen: ApplePhotosScreen {
        let albums = chosenAlbums
        let estimate = albums.reduce(0) { $0 + ($1.estimatedCount ?? 0) }
        let chosenLine = albums.isEmpty
            ? "No albums chosen."
            : "\(Self.count(albums.count, "album")) chosen, about \(Self.count(estimate, "photo"))."
        return ApplePhotosScreen(
            page: .setup, groups: groups, chosenLine: chosenLine, includesHidden: includesHidden, follows: follows,
            buttons: [.init(kind: .review, title: "Review", isEnabled: !albums.isEmpty, isDefault: true)],
            barNote: albums.isEmpty
                ? "Choose the albums to import."
                : "Review counts what comes across before anything is copied. Photos is only read.",
        )
    }

    /// The albums in Photos' folders, then smart albums, then shared albums, each group as Photos orders it.
    private var groups: [ApplePhotosScreen.Group] {
        guard let tree else { return [] }
        func row(_ collection: ApplePhotosCollection, depth: Int) -> ApplePhotosScreen.Album {
            let count = collection.kind == .folder
                ? albums(in: collection.id).reduce(0) { $0 + ($1.estimatedCount ?? 0) }
                : collection.estimatedCount
            return ApplePhotosScreen.Album(
                id: collection.id, title: collection.title, depth: depth, isFolder: collection.kind == .folder,
                count: count, check: check(of: collection.id),
            )
        }
        func rows(under parent: String?, depth: Int) -> [ApplePhotosScreen.Album] {
            tree.children(of: parent).flatMap { collection -> [ApplePhotosScreen.Album] in
                switch collection.kind {
                case .album: return [row(collection, depth: depth)]
                case .folder:
                    let inside = rows(under: collection.id, depth: depth + 1)
                    return inside.isEmpty ? [] : [row(collection, depth: depth)] + inside
                case .smartAlbum, .sharedAlbum: return []
                }
            }
        }
        let smart = tree.collections.filter { $0.kind == .smartAlbum }.map { row($0, depth: 0) }
        let shared = tree.collections.filter { $0.kind == .sharedAlbum }.map { row($0, depth: 0) }
        var groups = [ApplePhotosScreen.Group(id: "albums", title: "Albums", albums: rows(under: nil, depth: 0))]
        if !smart.isEmpty {
            groups.append(.init(
                id: "smart", title: "Smart Albums",
                note: "Each becomes a collection of the photos it holds now.", albums: smart,
            ))
        }
        if !shared.isEmpty {
            groups.append(.init(
                id: "shared", title: "Shared Albums",
                note: "Reduced copies, not the originals: Photos keeps shared albums’ photos smaller.", albums: shared,
            ))
        }
        return groups
    }

    // MARK: - Review

    private var reviewScreen: ApplePhotosScreen {
        guard let census else { return ApplePhotosScreen(page: .review) }
        let report = census.report
        let photos = report.photos
        return ApplePhotosScreen(
            page: .review,
            heading: photos == 0
                ? "Nothing new to import"
                : "\(Self.count(photos, "photo")) from \(Self.count(census.albums.count, "album"))",
            sections: Self.reviewSections(report),
            buttons: [
                .init(kind: .back, title: "Back"),
                .init(
                    kind: .importPhotos, title: photos == 0 ? "Import" : "Import \(Self.count(photos, "Photo"))",
                    isEnabled: canImport, isDefault: true,
                ),
            ],
            barNote: photos == 0
                ? "Every photo in these albums is in the library already, or left out."
                : "Photos is only read: nothing in it changes. Undo Import takes the import back.",
        )
    }

    /// The report as Review shows it: what comes across, what stays in Photos and why, and the fields this Mac's
    /// PhotoKit gives, with those macOS 27 would add.
    static func reviewSections(_ report: ApplePhotosReport) -> [ApplePhotosScreen.Section] {
        var across: [String] = []
        let size = report.bytes.map { ", " + ImportFormat.size($0) } ?? ""
        across.append(
            "\(count(report.photos, "photo")) copied as \(count(report.files, "file"))\(size), "
                + "\(count(report.libraryPhotos, "photo")) in the library",
        )
        if report.pairs > 0 {
            across.append("\(count(report.pairs, "RAW+JPEG pair")), each kept together under one name")
        }
        if report.raws > 0 {
            across.append(
                "\(count(report.raws, "raw")) on \(report.raws == 1 ? "its" : "their") own"
                    + (report.dngs > 0 ? ", \(report.dngs) of them DNG (ProRAW)" : ""),
            )
        }
        if report.edited > 0 {
            across.append(
                "\(count(report.edited, "photo")) edited in Photos: each original, with Photos’ version stacked "
                    + "over it",
            )
        }
        if report.editedWithoutRendering > 0 {
            across.append(
                "\(count(report.editedWithoutRendering, "edited photo")) without Photos’ version: only the original",
            )
        }
        if report.livePhotos > 0 {
            across
                .append(
                    "\(count(report.livePhotos, "Live Photo")), as \(report.livePhotos == 1 ? "its" : "their") still",
                )
        }
        if report.bursts > 0 {
            across.append(
                "\(count(report.bursts, "burst")): \(count(report.burstFrames, "frame")) shown or picked in "
                    + "Photos, stacked",
            )
        }
        if report.favorites > 0 {
            across.append("\(count(report.favorites, "favourite")), flagged as picks")
        }
        if report.fields.contains(.rating) {
            across.append(
                "\(count(report.rated, "rating")), \(count(report.captioned, "caption")) and keywords on "
                    + "\(count(report.withKeywords, "photo"))",
            )
        }
        if report.inSeveralAlbums > 0 {
            across.append("\(count(report.inSeveralAlbums, "photo")) in more than one album: copied once")
        }
        if report.sharedCopies > 0 {
            across.append("\(count(report.sharedCopies, "photo")) from shared albums: reduced copies, not originals")
        }
        if report.hiddenIncluded > 0 {
            across.append("\(count(report.hiddenIncluded, "hidden photo")), as you chose")
        }
        across.append("Each album becomes a collection, and Photos’ folders collection sets.")

        var left: [String] = []
        if report.videosLeft > 0 {
            left.append("\(count(report.videosLeft, "video")): Redlamp edits photos")
        }
        if report.hiddenLeft > 0 {
            left.append("\(count(report.hiddenLeft, "hidden photo")): Include hidden photos brings them")
        }
        if report.burstFramesLeft > 0 {
            left.append("\(count(report.burstFramesLeft, "burst frame")) not picked in Photos")
        }
        if report.alreadyImported > 0 {
            left.append("\(count(report.alreadyImported, "photo")) an earlier import brought")
        }
        if report.otherLeft > 0 {
            left
                .append(
                    "\(count(report.otherLeft, "item")) that \(report.otherLeft == 1 ? "isn’t a photo" : "aren’t photos")",
                )
        }
        left.append("Titles, people and pets, memories and Recently Deleted: PhotoKit doesn’t give them")
        if report.withLocation > 0 {
            left.append(
                "Places: \(count(report.withLocation, "photo")) placed in Photos keep the GPS their files hold; a "
                    + "place set only in Photos stays there",
            )
        }

        var fields = ["This Mac gives " + list(report.fields.map(word)) + "."]
        if !report.fromMacOS27.isEmpty {
            fields.append("macOS 27 would add " + list(report.fromMacOS27.map(word)) + ".")
        }
        return [
            .init(id: "across", title: "Comes across", lines: across),
            .init(id: "left", title: "Stays in Photos", lines: left),
            .init(id: "fields", title: "Fields", lines: fields),
        ]
    }

    private static func word(_ field: ApplePhotosField) -> String {
        switch field {
        case .favorite: "favourites"
        case .date: "dates"
        case .originalName: "original names"
        case .albums: "albums"
        case .location: "places"
        case .rating: "ratings"
        case .caption: "captions"
        case .keywords: "keywords"
        }
    }

    static func list(_ words: [String]) -> String {
        guard let last = words.last else { return "none" }
        return words.count == 1 ? last : words.dropLast().joined(separator: ", ") + " and " + last
    }

    // MARK: - Progress

    private var progressScreen: ApplePhotosScreen {
        let stage = progress?.stage ?? .census
        var screen = ApplePhotosScreen(
            page: .progress, heading: isFollowUp ? "Importing the new photos in the albums followed" : "Importing",
            stages: stages(now: stage, stopped: false),
            buttons: [.init(
                kind: .stop,
                title: phase == .stopping ? "Stopping…" : "Stop",
                isEnabled: phase == .importing,
            )],
        )
        let photos = progress?.photos ?? total
        let done = progress.map { $0.done + $0.failed } ?? 0
        var lines: [String] = []
        if let progress, progress.stage == .staging || progress.stage == .copying {
            if let bytes = progress.bytes, bytes > 0 {
                lines.append("\(ImportFormat.size(progress.written)) of \(ImportFormat.size(bytes))")
            }
            if progress.downloading > 0 {
                lines.append("Downloading \(Self.count(progress.downloading, "photo")) from iCloud")
            }
            if progress.failed > 0 {
                lines.append("\(Self.count(progress.failed, "photo")) Photos couldn’t give")
            }
        }
        screen.progress = ApplePhotosScreen.Progress(
            title: Self.title(of: stage), done: done, total: photos,
            fraction: photos > 0 ? min(Double(done) / Double(photos), 1) : 0, lines: lines,
        )
        screen.barNote = phase == .stopping
            ? "Stopping: the photos being copied finish, and Resume takes up where it stopped."
            : "Stop ends it once the photos being copied are done. Closing the window lets it carry on."
        return screen
    }

    private static func title(of stage: ApplePhotosImport.Stage) -> String {
        switch stage {
        case .census: "Reading albums"
        case .staging: "From Photos"
        case .copying: "Copying"
        case .finishing: "Finishing"
        }
    }

    private func stages(now stage: ApplePhotosImport.Stage, stopped: Bool) -> [ProgressStage] {
        let order: [ApplePhotosImport.Stage] = [.census, .staging, .copying, .finishing]
        let place = order.firstIndex(of: stage) ?? 0
        return order.enumerated().map { index, each in
            let state: ProgressStage.State = index < place ? .done : index > place ? .next : stopped ? .stopped : .now
            let detail: String = switch (each, state) {
            case (.census, .done): Self.count(total, "photo")
            case (.staging, .now), (.copying, .now):
                progress.map { "\($0.done + $0.failed) of \($0.photos)" } ?? ""
            case (_, .done): "done"
            default: ""
            }
            return ProgressStage(id: each.rawValue, title: Self.title(of: each), detail: detail, state: state)
        }
    }

    // MARK: - Result

    private var resultScreen: ApplePhotosScreen {
        if phase == .undoing {
            return ApplePhotosScreen(page: .result, heading: "Taking the import back…", barNote: "")
        }
        if phase == .undone, let undone {
            let taken = Set(undone.rollbacks.flatMap(\.rolledBack)).count
            return ApplePhotosScreen(
                page: .result, heading: "The import is taken back",
                sections: [.init(id: "undone", title: "Taken back", lines: [
                    "The copies of \(Self.count(taken, "photo")) are in the Trash and out of the library.",
                    "Photos is as it was: nothing in it changed.",
                ])],
                buttons: [.init(kind: .done, title: "Done", isDefault: true)],
                barNote: "Done shows the albums again.",
            )
        }
        guard let outcome else {
            return ApplePhotosScreen(
                page: .result, heading: "The import didn’t finish",
                buttons: [.init(kind: .done, title: "Done", isDefault: true)],
            )
        }
        let stopped = outcome.state == .stopped
        let imported = outcome.imported
        let time = elapsed.map { " in " + ProgressText.duration($0 / .seconds(1)) } ?? ""
        var screen = ApplePhotosScreen(
            page: .result,
            heading: stopped
                ? "Stopped with \(Self.count(imported, "photo")) imported"
                : "Imported \(Self.count(imported, "photo")) from Apple Photos\(time)",
            stages: stopped ? stages(now: outcome.copy == nil ? .staging : .copying, stopped: true) : [],
        )
        var lines: [String] = []
        if let copy = outcome.copy {
            let edits = copy.verified - imported
            lines.append(
                "\(Self.count(copy.verified, "photo")) in the library"
                    +
                    (edits > 0 ? ", \(Self.count(edits, "version")) edited in Photos stacked over the originals" :
                        ""),
            )
        }
        let albums = outcome.report.albums.values.reduce(0, +)
        if albums > 0 {
            lines.append("In \(Self.count(albums, "collection")), one for each album")
        }
        if let destination = counted?.copying.destination {
            lines.append("Copied to \(destination.path)")
        }
        if counted?.follows == true, !stopped {
            lines.append("Their albums are followed: new photos in them show in the Library panel’s From Apple Photos")
        }
        var left: [String] = []
        for (_, message) in outcome.stagingFailures.sorted(by: { $0.key < $1.key }).prefix(5) {
            left.append("Photos couldn’t give a photo: \(message)")
        }
        if outcome.stagingFailures.count > 5 {
            left.append("Photos couldn’t give \(Self.count(outcome.stagingFailures.count - 5, "more photo"))")
        }
        for failure in outcome.copy?.failures.prefix(5) ?? [] {
            left.append("\((failure.photo as NSString).lastPathComponent) couldn’t be copied: \(failure.message)")
        }
        if outcome.placesOnlyInPhotos > 0 {
            left.append(
                "\(Self.count(outcome.placesOnlyInPhotos, "photo")) placed only in Photos: the place stays there",
            )
        }
        let report = outcome.report
        let skipped = report.videosLeft + report.hiddenLeft + report.burstFramesLeft + report.otherLeft
        if skipped > 0 {
            left.append("\(Self.count(skipped, "item")) left in Photos, as Review said")
        }
        if stopped {
            left.append("The rest are still in Photos: Resume takes up where it stopped")
        }
        screen.sections = [.init(id: "imported", title: stopped ? "Stopped" : "Imported", lines: lines)]
        if !left.isEmpty {
            screen.sections.append(.init(id: "left", title: "Left in Photos", lines: left))
        }
        var buttons: [ApplePhotosScreen.Button] = []
        if imported > 0 {
            buttons.append(.init(kind: .undo, title: "Undo Import", isEnabled: canUndo))
            buttons.append(.init(kind: .showInLibrary, title: "Show in Library"))
        }
        if stopped {
            buttons.append(.init(kind: .resume, title: "Resume"))
        }
        buttons.append(.init(kind: .done, title: "Done", isDefault: true))
        screen.buttons = buttons
        screen
            .barNote = imported > 0 ? "Undo Import moves the copies to the Trash and takes them out of the library." : ""
        return screen
    }
}
