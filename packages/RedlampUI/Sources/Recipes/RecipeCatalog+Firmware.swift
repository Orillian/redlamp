import Foundation
import RedlampEngineAPI
import RedlampRecipes

/// The firmware model's prototype (local fujisim-prototype branch only), switched in Settings'
/// Prototype tab.
public extension RecipeCatalog {
    var firmwareModel: FirmwareFilmModel? {
        _ = revision
        return library.firmwareModel
    }

    /// A card recipe resolved as the switch stands; see `RecipeLibrary.resolvingCard`.
    func resolved(_ recipe: Recipe) -> Recipe {
        library.resolvingCard(recipe)
    }

    /// The look for `settings`, renderable now and kept on this Mac, so an edit that uses it
    /// renders after a relaunch and with the switch off.
    func firmwareLook(_ settings: FirmwareLookSettings) -> BaseLookDefinition? {
        guard let model = library.firmwareModel,
              let look = try? FirmwareLook.definition(settings, model: model) else { return nil }
        engine.registerBaseLook(look)
        keepFirmwareLook(look)
        return look
    }

    /// Keeps a firmware look an edit uses among the stored ones.
    func keepFirmwareLook(_ look: BaseLookDefinition) {
        guard look.reference.isFirmwareModel,
              !library.storedLooks.contains(where: { $0.matches(look.reference) }) else { return }
        do {
            try library.lookStore.save(BaseLookPackage(
                id: look.id, version: look.version, name: look.name, parameters: look.parameters, table: look.table,
            ))
            library.reload()
        } catch {
            return
        }
    }

    /// Reads the switch and where the model comes from, after launch and whenever the settings
    /// change. A folder that failed is read again at the next change; the hosted file is opened
    /// once per launch or turn of the switch, so a failure stays off rather than refetching.
    func refreshFirmwareModel() {
        let source = FirmwareFilmModel.source()
        var retry = false
        if case .folder? = source {
            retry = library.firmwareModel == nil
        }
        guard source != firmwareSource || retry else { return }
        firmwareSource = source
        firmwareTask?.cancel()
        firmwareTask = nil
        library.firmwareModel = nil
        switch source {
        case nil:
            firmwareStatus = nil
        case .unavailable?:
            firmwareStatus = "This build has no hosted model, and the folder doesn't hold the model's files."
        case let .folder(folder)?:
            do {
                let model = try FirmwareFilmModel.shared(at: folder)
                library.firmwareModel = model
                firmwareStatus = "\(model.simulationNames.count) simulations read from \(folder.path)"
            } catch {
                firmwareStatus = "\(error)"
            }
        case let .hosted(addresses)?:
            firmwareStatus = "Fetching the model…"
            let host = FirmwareModelHost(addresses: addresses)
            firmwareTask = Task { [weak self] in
                let result = await host.open()
                guard let self, !Task.isCancelled, firmwareSource == source else { return }
                switch result {
                case let .success(model):
                    library.firmwareModel = model
                    firmwareStatus = "\(model.simulationNames.count) simulations from the hosted file"
                case let .failure(failure):
                    firmwareStatus = failure.description
                }
                changed()
            }
        }
        changed()
    }
}

extension RecipeCatalog {
    func observeFirmwareSwitch() {
        refreshFirmwareModel()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFirmwareModel() }
        }
    }
}
