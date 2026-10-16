import Foundation
import RedlampEngineAPI
import RedlampRecipes

public extension EditorModel {
    /// Applies a recipe. Its Amount stays adjustable until the edit changes some other way.
    func applyRecipe(_ recipe: Recipe, amount: Double = 100) {
        let recipe = recipes.resolved(recipe)
        previewingRecipe = nil
        recipes.prepare(recipe)
        keepFirmwareLook(of: recipe)
        let base = recipe.id == recipeApplication?.recipe.id && recipeAmount != nil
            ? recipeApplication!.base
            : self.recipe
        recipeApplication = (recipe, base)
        let apply = { [self] in
            commit(
                anchored(recipe.apply(to: base, amount: amount, whiteBalance: resolveWhiteBalance)),
                .recipe,
                "Recipe",
            ) { _ in
                recipe.name
            }
        }
        if needsAutoWhiteBalance(recipe), autoWhiteBalance == nil, let visit = currentVisit {
            Task {
                let wb = await engine.autoWhiteBalance()
                guard currentVisit == visit else { return }
                autoWhiteBalance = wb
                apply()
            }
        } else {
            apply()
        }
    }

    /// Chooses a look as one History step, as every place a look is chosen does (DEC-104).
    func chooseLook(_ choice: LookChoice) {
        previewingRecipe = nil
        previewingLook = nil
        if let embedded = engine.embeddedBaseLook(), embedded.reference.isSameLook(as: choice.look) {
            recipes.remember(embedded)
        }
        if choice.look.isFirmwareModel, let definition = try? recipes.package(for: choice.look)?.definition() {
            recipes.keepFirmwareLook(definition)
        }
        commit(applying(choice, to: recipe), .baseLook, "Base Look") { $0.baseLook.name }
    }

    /// `edit` with `choice` applied, as choosing it applies it: a colour look chosen in place of a
    /// monochrome one sets Color.
    func applying(_ choice: LookChoice, to edit: EditRecipe) -> EditRecipe {
        anchored(choice.apply(to: edit, replacingMonochrome: isMonochrome(edit.baseLook)))
    }

    /// Choosing `look`: Black & White for a monochrome look, and for a film stock its grain, halation
    /// and bloom unless `withFilmEffects` is false.
    func lookChoice(for look: BaseLookReference, withFilmEffects: Bool = true) -> LookChoice {
        LookChoice(look, monochrome: isMonochrome(look), withFilmEffects: withFilmEffects)
    }

    /// Whether `look` renders in black and white: Redlamp Monochrome, a monochrome film stock, camera
    /// profile or installed look.
    func isMonochrome(_ look: BaseLookReference) -> Bool {
        look.isSameLook(as: BuiltInBaseLook.monochrome.reference)
            || FilmLookCatalog.look(forBaseLookID: look.id)?.isMonochrome == true
            || recipes.package(for: look)?.parameters.isMonochrome == true
            || cameraProfileLooks.contains { $0.isMonochrome && $0.reference.isSameLook(as: look) }
    }

    /// Hover preview of a look, rendered as choosing it would apply it; nil ends any hover preview.
    func previewLook(_ choice: LookChoice?) {
        guard previewingLook != choice || previewingRecipe != nil else { return }
        previewingRecipe = nil
        previewingLook = choice
        requestRender()
    }

    /// Hover preview: renders a recipe without applying it; nil ends any hover preview.
    func previewRecipe(_ recipe: Recipe?) {
        let recipe = recipe.map(recipes.resolved)
        guard previewingRecipe != recipe || previewingLook != nil else { return }
        previewingLook = nil
        if let recipe {
            recipes.prepare(recipe)
            if needsAutoWhiteBalance(recipe), autoWhiteBalance == nil, let visit = currentVisit {
                Task {
                    let wb = await engine.autoWhiteBalance()
                    guard currentVisit == visit else { return }
                    autoWhiteBalance = wb
                    requestRender()
                }
            }
        }
        previewingRecipe = recipe
        requestRender()
    }

    /// The last applied recipe's Amount, while the edit is still exactly what it produced.
    /// Observes only `recipeApplication`, never the edit, so lists can read it without
    /// reloading on every slider event.
    var recipeAmount: Double? {
        guard let application = recipeApplication, let applied = unobservedRecipe.appliedRecipe,
              applied.id == application.recipe.id,
              anchored(application.recipe.apply(
                  to: application.base,
                  amount: applied.amount,
                  whiteBalance: resolveWhiteBalance,
              ))
              == unobservedRecipe
        else { return nil }
        return applied.amount
    }

    var recipeAmountTitle: String? {
        guard recipeAmount != nil else { return nil }
        return recipeApplication?.recipe.name
    }

    /// Re-applies the last recipe at another strength. During a drag (between `beginEdit`
    /// and `endEdit`) history records one step.
    func setRecipeAmount(_ amount: Double) {
        guard let application = recipeApplication else { return }
        let next = anchored(application.recipe.apply(
            to: application.base, amount: amount.rounded(), whiteBalance: resolveWhiteBalance,
        ))
        guard next != recipe else { return }
        if editStart == nil {
            commit(next, .recipe, "Recipe Amount", value: Self.recipeAmountText)
        } else {
            applyLive(next)
        }
    }

    /// The Base Look's strength, 0...200.
    func setBaseLookAmount(_ amount: Double) {
        var next = recipe
        next.baseLook = recipe.baseLook.withAmount(amount.rounded())
        guard next != recipe else { return }
        if editStart == nil {
            commit(next, .baseLook, "Base Look Amount", value: Self.baseLookAmountText)
        } else {
            applyLive(next)
        }
    }

    /// The Recipe Amount and Base Look Amount as history shows them.
    internal static func recipeAmountText(_ recipe: EditRecipe) -> String {
        recipe.appliedRecipe.map { "\(Int($0.amount.rounded()))" } ?? "–"
    }

    internal static func baseLookAmountText(_ recipe: EditRecipe) -> String {
        "\(Int(recipe.baseLook.amount.rounded()))"
    }

    /// The edit's Base Look isn't installed here, so the photo renders without it; for an Adobe
    /// profile, Redlamp's look of the same name stands in. Not known for an Adobe profile until the
    /// photo's profiles are listed.
    var isBaseLookMissing: Bool {
        _ = recipes.revision
        if baseLook.isAdobeProfile {
            return cameraProfilesPhoto == info?.url
                && !cameraProfileLooks.contains { $0.reference.isSameAdobeLook(as: baseLook) }
        }
        return !recipes.isAvailable(baseLook)
    }

    /// Captures the current edit as a recipe in My Recipes.
    @discardableResult
    func saveRecipe(name: String, group: String = "My Recipes", includes: Set<RecipeSettingGroup>) -> Recipe? {
        let looks = recipes.package(for: recipe.baseLook).map { [$0] } ?? []
        let captured = Recipe.capture(recipe, name: name, group: group, includes: includes, embedding: looks)
        return recipes.save(captured)
    }

    internal func previewEdit(for recipe: Recipe) -> EditRecipe {
        anchored(recipe.apply(to: self.recipe, whiteBalance: resolveWhiteBalance))
    }

    internal func resolveWhiteBalance(_ mode: WhiteBalanceMode) -> WhiteBalanceValue? {
        switch mode {
        case .asShot: info?.asShotWhiteBalance
        case .auto: autoWhiteBalance
        case .custom: nil
        default: mode.presetValue
        }
    }

    /// A firmware look the recipe brings, kept so the edit renders after a relaunch.
    private func keepFirmwareLook(of recipe: Recipe) {
        guard let look = recipe.baseLook, look.isFirmwareModel,
              let definition = try? recipe.embeddedBaseLooks.first(where: { $0.matches(look) })?.definition()
        else { return }
        recipes.keepFirmwareLook(definition)
    }

    private func needsAutoWhiteBalance(_ recipe: Recipe) -> Bool {
        recipe.includes.contains(.whiteBalance) && recipe.settings.whiteBalanceMode == .auto
    }
}
