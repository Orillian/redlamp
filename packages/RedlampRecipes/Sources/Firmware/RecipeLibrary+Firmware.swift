import Foundation
import RedlampEngineAPI

public extension RecipeLibrary {
    static let firmwareGroup = "Firmware Model"

    /// One recipe for each of the model's simulations at its neutral settings.
    static func firmwareRecipes(model: FirmwareFilmModel) -> [Recipe] {
        FirmwareSimulation.allCases.compactMap { simulation in
            guard let look = try? FirmwareLook.package(FirmwareLookSettings(simulation: simulation), model: model)
            else { return nil }
            return Recipe(
                id: "\(RecipeNamespace.local)/firmware-model/\(simulation.rawValue)",
                name: simulation.name,
                group: firmwareGroup,
                summary: "The firmware model's \(simulation.name) at its neutral settings.",
                tags: ["firmware-model"] + (simulation.slot.map { [$0.rawValue] } ?? []),
                includes: [.baseLook, .treatment],
                settings: RecipeSettings(treatment: .color),
                baseLook: look.reference,
                embeddedBaseLooks: [look],
                lintWaivers: simulation.isMonochrome ? ["neutral-axis", "skin-hue"] : [],
            )
        }
    }

    /// A card recipe resolved as the firmware model's switch stands: through the model while
    /// it's on, and back to Redlamp's looks once it's off. Other recipes are as they are.
    func resolvingCard(_ recipe: Recipe) -> Recipe {
        guard let card = recipe.cameraCard else { return recipe }
        if let firmwareModel {
            return recipe.updatingCard(card, slotLooks: filledSlots, firmware: firmwareModel)
        }
        if recipe.baseLook?.isFirmwareModel == true {
            return recipe.updatingCard(card, slotLooks: filledSlots)
        }
        return recipe
    }
}
