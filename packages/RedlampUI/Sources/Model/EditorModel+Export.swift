import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampLibrary

extension EditorModel {
    /// Renders the open photo as `settings` describe and writes it to `url`, replacing any
    /// file there that isn't a photo. The photo and its edit are taken before the first
    /// suspension, and the render fails rather than export another photo opened in the meantime.
    /// The library's fields for the photo go with it under `settings.metadata`, when the library has it.
    public func export(_ settings: ExportSettings, to url: URL) async throws {
        guard let info else { throw EngineError.noImageOpen }
        let source = info.url
        let request = settings.stillRequest(recipe: unobservedRecipe, source: source, size: info.pixelSize)
        let core = settings.metadata == .none ? nil : library.service?.core
        let files = engine.files
        setExportStatus("Exporting \(info.fileName)…", clearAfter: nil)
        do {
            let image = try await engine.renderStill(request)
            try await Task.detached(priority: .userInitiated) {
                let fields = await Self.exportFields(of: source, core: core)
                let metadata = ExportMetadata.properties(
                    from: source,
                    reading: files,
                    policy: settings.metadata,
                    recipe: request.recipe,
                    fields: fields,
                )
                try ImageExporter.write(
                    image, to: url, settings: settings, metadata: metadata, source: source, reading: files,
                )
            }.value
        } catch {
            setExportStatus(nil, clearAfter: nil)
            throw error
        }
        setExportStatus("Exported \(url.lastPathComponent)", clearAfter: .seconds(3))
    }

    /// The library's fields for `source`, which its export carries; nil when the library doesn't have it.
    nonisolated static func exportFields(of source: URL, core: LibraryCore?) async -> ExportMetadata.Fields? {
        guard let core, let id = await LibraryService.indexIDs(of: [source], in: core.index)[source] else { return nil }
        return try? await LibraryMetadata(index: core.index, paths: core.paths).exportFields(ofPhoto: id)
    }

    /// Wires the batch exporter to the editor's engine factory, sidecars, saves and looks.
    func connectBatchExport() {
        batchExport.makeEngine = { [weak self] in self?.makeWorkerEngine?() }
        batchExport.sidecars = library.sidecars
        batchExport.saved = { [weak self] url in
            guard let self else { return }
            await saves.wait(for: url)
            await settingsSync.wait(for: url)
        }
        batchExport.baseLook = { [weak self] reference in self?.recipes.library.definition(for: reference) }
        batchExport.fields = { [weak self] url in
            await Self.exportFields(of: url, core: self?.library.service?.core)
        }
        settingsSync.beforeWriting = { [weak self] url in await self?.batchExport.wait(for: url) }
    }

    private func setExportStatus(_ status: String?, clearAfter delay: Duration?) {
        exportStatusTask?.cancel()
        exportStatus = status
        guard let delay else { return }
        exportStatusTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.exportStatus = nil
        }
    }
}
