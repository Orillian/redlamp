#if !REDLAMP_APP_STORE
    import Foundation
    import RedlampEngineAPI
    import RedlampRecipes

    /// The firmware model's looks as the photo's Base Look (TON-49).
    public extension EditorModel {
        /// Whether the model's switch is on and the model read.
        var usesFirmwareModel: Bool {
            recipes.firmwareModel != nil
        }

        /// The settings of the photo's firmware look, if it has one.
        var firmwareSettings: FirmwareLookSettings? {
            FirmwareLook.settings(for: recipe.baseLook)
        }

        /// Bakes the firmware look for `settings` and makes it the photo's Base Look, keeping its
        /// Amount; nil goes back to Redlamp Color. The treatment becomes colour, so a black-and-white
        /// simulation's toning isn't greyed out.
        func setFirmwareLook(_ settings: FirmwareLookSettings?) {
            guard let settings else {
                setBaseLook(BuiltInBaseLook.color.reference)
                return
            }
            guard let look = recipes.firmwareLook(settings) else { return }
            var next = recipe
            let amount = recipe.baseLook.isFirmwareModel ? recipe.baseLook.amount : 100
            next.baseLook = look.reference.withAmount(amount)
            next.treatment = .color
            commit(anchored(next), .baseLook, "Firmware Model") { $0.baseLook.name }
        }

        /// Changes one of the photo's firmware look settings.
        func updateFirmwareLook(_ change: (inout FirmwareLookSettings) -> Void) {
            guard var settings = firmwareSettings else { return }
            change(&settings)
            setFirmwareLook(settings)
        }
    }
#endif
