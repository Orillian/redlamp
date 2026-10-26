import Foundation
import Observation
import RedlampLibrary

/// The albums imports from Apple Photos follow (LIB-55): their new photos, those the record doesn't name, counted at
/// launch and again whenever Photos changes, a moment after the last change and off the main thread. The Library
/// panel's From Apple Photos shows while there are some, with Import (`ApplePhotosActions.importNew`); with Settings ›
/// Library's Import new photos from followed albums automatically, they're imported without asking a minute after
/// Photos last changed, while Redlamp runs. Nothing is ever taken out of Redlamp because a photo left Photos or an
/// album: only what's new is counted.
@MainActor
@Observable
public final class ApplePhotosFollower {
    /// The new photos in the albums followed, as last counted: none while Photos can't be read.
    public private(set) var newPhotos = 0
    /// What they were counted with, which Import runs.
    @ObservationIgnored private(set) var news: (settings: ApplePhotosImport.Settings, census: ApplePhotosCensus)?
    /// An automatic import is running.
    @ObservationIgnored private(set) var isImporting = false

    /// How long after Photos' last change it counts.
    @ObservationIgnored static var settling = Duration.milliseconds(500)
    /// How long after Photos' last change, or the launch's count, an automatic import starts.
    @_spi(Harness) public static var automaticDelay = Duration.seconds(60)

    @ObservationIgnored private weak var model: EditorModel?
    @ObservationIgnored let preferences: ApplePhotosPreferences
    @ObservationIgnored private var importer: ApplePhotosImport?
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var counting: Task<Void, Never>?
    @ObservationIgnored private var importingSoon: Task<Void, Never>?
    @ObservationIgnored private var starting: Task<Void, Never>?

    init(model: EditorModel, preferences: ApplePhotosPreferences = .shared) {
        self.model = model
        self.preferences = preferences
        followPreference()
    }

    /// Once the library is open: counts, and follows Photos' changes while Redlamp may read it. Again when the
    /// library Photos is read from changes, as the regression suite's simulated one does.
    func start() {
        starting?.cancel()
        starting = Task { [weak self] in
            guard let model = self?.model else { return }
            let library = await ImportActions.library(of: model)
            guard let self, !Task.isCancelled else { return }
            importer = ApplePhotosImport(photos: ApplePhotosSource.library, library: library)
            watch()
        }
    }

    /// Stops following Photos.
    func stop() {
        starting?.cancel()
        watching?.cancel()
        counting?.cancel()
        importingSoon?.cancel()
        watching = nil
        importer = nil
        news = nil
        newPhotos = 0
    }

    /// Done once the library has started following Photos.
    var isStarted: Bool {
        importer != nil
    }

    private func watch() {
        watching?.cancel()
        guard let importer else { return }
        let photos = importer.photos
        guard photos.access() == .authorized else {
            news = nil
            newPhotos = 0
            return
        }
        recount(launching: true)
        watching = Task { [weak self] in
            for await _ in photos.changes() {
                self?.photosChanged()
            }
        }
    }

    /// Photos changed: counted once it settles, and imported a minute later when that's turned on.
    private func photosChanged() {
        counting?.cancel()
        counting = Task { [weak self] in
            try? await Task.sleep(for: Self.settling)
            guard !Task.isCancelled else { return }
            await self?.count()
            self?.importSoon()
        }
    }

    /// Counts the new photos again: after an import or its Undo, and when following starts.
    func recount(launching: Bool = false) {
        guard importer != nil else { return }
        counting?.cancel()
        counting = Task { [weak self] in
            await self?.count()
            if launching {
                self?.importSoon()
            }
        }
    }

    /// Returns once the count asked for last is done.
    func counted() async {
        await counting?.value
    }

    private func count() async {
        guard let importer else { return }
        let found = await Task.detached(priority: .utility) { try? await importer.followedNews() }.value
        guard !Task.isCancelled else { return }
        news = found
        let count = found?.census.report.photos ?? 0
        if count != newPhotos {
            newPhotos = count
        }
    }

    // MARK: - Importing without asking

    private func followPreference() {
        withObservationTracking {
            _ = preferences.importsAutomatically
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.followPreference()
                self?.importSoon()
            }
        }
    }

    /// An automatic import, `automaticDelay` from now, while it's turned on and there's something new; asked again,
    /// it starts its minute again.
    private func importSoon() {
        importingSoon?.cancel()
        guard preferences.importsAutomatically, newPhotos > 0 else { return }
        importingSoon = Task { [weak self] in
            try? await Task.sleep(for: Self.automaticDelay)
            guard !Task.isCancelled else { return }
            await self?.importAutomatically()
        }
    }

    private func importAutomatically() async {
        guard preferences.importsAutomatically, !isImporting, let importer, let model,
              ApplePhotosWindowController.current?.model.isRunning != true
        else { return }
        await count()
        guard let news, news.census.report.photos > 0 else { return }
        isImporting = true
        defer { isImporting = false }
        let titles = news.census.albums.map { "“\($0.title)”" }.joined(separator: ", ")
        model.activity.record(
            .action,
            "Import from Apple Photos, automatically: "
                + "\(ProgressText.count(news.census.report.photos, "new photo")) in \(titles)",
        )
        let result = await Task.detached(priority: .utility) { () -> Result<ApplePhotosImport.Outcome, any Error> in
            do {
                return try await .success(importer.run(news.settings, census: news.census))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case let .success(outcome):
            model.activity.record(
                .action,
                "Imported \(ProgressText.count(outcome.imported, "new photo")) from followed Apple Photos albums"
                    + (outcome.state == .stopped ? ", stopped before the end" : ""),
            )
        case let .failure(error):
            model.activity.record(.error, "The automatic import from Apple Photos stopped: \(error)")
        }
        model.libraryPanels.refresh()
        await count()
    }
}
