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

    /// Reads the switch and the model's folder, after launch and whenever they change.
    func refreshFirmwareModel() {
        let folder = FirmwareFilmModel.settingsFolder()
        guard folder != firmwareFolder || (folder != nil && library.firmwareModel == nil) else { return }
        firmwareFolder = folder
        if let folder {
            do {
                let model = try FirmwareFilmModel.shared(at: folder)
                library.firmwareModel = model
                firmwareStatus = "\(model.simulationNames.count) simulations read from \(folder.path)"
            } catch {
                library.firmwareModel = nil
                firmwareStatus = "\(error)"
            }
        } else {
            library.firmwareModel = nil
            firmwareStatus = nil
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
