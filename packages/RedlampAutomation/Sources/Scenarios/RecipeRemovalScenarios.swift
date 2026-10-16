#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampEngineAPI
    import RedlampRecipes
    @_spi(Harness) import RedlampUI

    /// Removing and hiding recipes and looks (UX-55), through the rows' and the panels' right-click menus. What
    /// Show in Finder shows is noted rather than opened in Finder, and Move to Trash moves the files to a folder of
    /// the scenario's own, which it removes, rather than to the Trash.
    extension RecipeScenarios {
        /// An installed recipe shown in Finder and moved to the Trash from its row in Recipes, then a LUT imported
        /// and chosen for the photo, moved to the Trash from its row in Base Looks: the photo keeps its look, and no
        /// list shows it again. Each row is found by its panel's search, which the scenario empties again.
        static let showAndTrash = Scenario(
            "recipes.show-and-trash",
            "An installed recipe's and an imported LUT's rows show them in Finder and move them to the Trash, the "
                + "photo keeping the LUT's look, which no list shows again",
            claims: [
                .feature("recipes.base-looks"),
                .feature("recipes.importing"),
                .section(.recipes),
                .section(.baseLooks),
            ],
        ) { app in
            try app.openWorking()
            let token = UUID().uuidString.prefix(8).lowercased()
            let trash = app.runDirectory.appending(path: "Recipe Trash \(token)", directoryHint: .isDirectory)
            let (sections, reveal) = try app.main { model in (model.expandedSidebarSections, RecipeActions.reveal) }
            try app.main { model in
                RevealedRecipeFiles.files = []
                RecipeActions.reveal = { RevealedRecipeFiles.files += $0 }
                model.recipes.library.trash = { url in
                    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                    let moved = trash.appending(path: url.lastPathComponent)
                    try FileManager.default.moveItem(at: url, to: moved)
                    return moved
                }
                RevealedRecipeFiles.emptySearches()
            }
            defer {
                try? app.main { model in
                    RecipeActions.reveal = reveal
                    model.recipes.library.trash = RecipeLibrary.moveToSystemTrash
                    RevealedRecipeFiles.emptySearches()
                    model.expandedSidebarSections = sections
                }
                try? FileManager.default.removeItem(at: trash)
            }

            // An installed recipe, in Recipes: Show in Finder selects its file in Recipes/Installed.
            let recipe = Recipe(
                id: "regression/warm-\(token)", name: "Regression Warm \(token)", group: "Regression",
                includes: [.tone], settings: RecipeSettings(values: [.exposure: 0.2]),
            )
            let file = app.runDirectory.appending(path: "warm-\(token).redrecipe")
            try RecipeFile.write(recipe, to: file)
            try app.main { model in
                model.expandedSidebarSections = [.recipes]
                RecipeActions.importFiles([file], model: model)
            }
            try app.wait("the installed recipe", timeout: 20) { $0.recipes.recipe(id: recipe.id) != nil }
            try app.click(.identifier("recipes.search"))
            try app.type(recipe.name)
            let row = Target.identifier("recipes.recipe.\(recipe.id)")
            try app.waitUntilClickable(row.identifier)
            let items = try app.rightClick(row, choosing: "Show in Finder").map(\.title)
            try app.expect(
                !items.contains("Delete Recipe") && items.suffix(2) == ["Show in Finder", "Move to Trash"],
                "An installed recipe's menu is \(items)",
            )
            let kept = try app.main { model in model.recipes.file(of: recipe) }
            try app.expect(
                kept?.deletingLastPathComponent().lastPathComponent == "Installed",
                "The installed recipe is kept at \(kept?.path ?? "nowhere")",
            )
            try app.wait("Show in Finder to show \(kept?.lastPathComponent ?? "its file")") { _ in
                RevealedRecipeFiles.files == [kept].compactMap(\.self)
            }
            try app.rightClick(row, choosing: "Move to Trash")
            try app.wait("the recipe in the Trash", timeout: 10) { model in
                model.recipes.recipe(id: recipe.id) == nil
                    && FileManager.default.fileExists(atPath: trash.appending(path: kept?.lastPathComponent ?? "").path)
            }
            app.covered([.section(.recipes), .feature("recipes.importing")], via: .mouse)

            // An imported LUT, chosen for the photo: Move to Trash from its row in Base Looks leaves the photo
            // rendering with its look, which Base Looks and Basic's menu don't list again.
            let cube = app.runDirectory.appending(path: "Regression Teal \(token).cube")
            var lines = ["TITLE \"Regression Teal \(token)\"", "LUT_3D_SIZE 2"]
            for b in 0 ... 1 {
                for g in 0 ... 1 {
                    for r in 0 ... 1 {
                        lines.append("\(Double(r) * 0.85) \(Double(g) * 0.95) \(Double(b))")
                    }
                }
            }
            try lines.joined(separator: "\n").write(to: cube, atomically: true, encoding: .utf8)
            try app.main { model in
                model.expandedSidebarSections = [.baseLooks]
                RecipeActions.importFiles([cube], model: model)
            }
            try app.wait("the imported LUT", timeout: 20) { model in
                model.recipes.all.contains { $0.name == "Regression Teal \(token)" }
            }
            let lut = try app.main { model in model.recipes.all.first { $0.name == "Regression Teal \(token)" } }
            guard let lut, let look = lut.baseLook else { throw ScenarioFailure("The LUT came in without its look") }
            try app.expectRenders("the photo with the imported LUT's look") {
                try app
                    .main { model in BaseLookPreviews.choice(id: look.id, model: model).map { model.chooseLook($0) } }
            }
            try app.wait("the LUT's look chosen") { $0.baseLook.id == look.id }
            try app.click(.identifier("baseLooks.search"))
            try app.type("regression teal \(token)")
            let lookRow = Target.identifier("baseLooks.look.\(look.id)")
            try app.waitUntilClickable(lookRow.identifier)
            let lutFile = try app.main { model in model.recipes.file(of: lut) }
            try app.main { _ in RevealedRecipeFiles.files = [] }
            try app.rightClick(lookRow, choosing: "Show in Finder")
            try app.wait("Show in Finder to show the recipe holding the LUT") { _ in
                RevealedRecipeFiles.files == [lutFile].compactMap(\.self)
            }
            try app.rightClick(lookRow, choosing: "Move to Trash")
            try app.wait("the LUT's recipe in the Trash", timeout: 10) { model in
                model.recipes.recipe(id: lut.id) == nil
            }
            let (keepsLook, available, listed, inMenu) = try app.main { model in
                (
                    model.baseLook.id == look.id,
                    model.recipes.isAvailable(model.baseLook),
                    BaseLookPreviews.panelFolders(model).contains { $0.ids.contains(look.id) },
                    BaseLookPreviews.menuSections(model).contains { $0.name != "In Use" && $0.ids.contains(look.id) },
                )
            }
            try app.expect(keepsLook && available, "The photo lost the LUT's look when its recipe went to the Trash")
            try app.expect(!listed, "Base Looks still lists the LUT's look")
            try app.expect(!inMenu, "Basic's Base Look menu lists the LUT's look again")
            try app.choose(.resetAll)
            app.covered([.section(.baseLooks), .feature("recipes.base-looks")], via: .mouse)
        }

        /// Base Looks' Film Stocks and Recipes' Essentials hidden from their rows' menus, the photo keeping its film
        /// stock, then shown again from their panels' header menus.
        static let hideFolders = Scenario(
            "recipes.hide-folders",
            "Film Stocks and Essentials hidden from their folders' menus leave their panels and searches, the photo "
                + "keeping its film stock, and come back from the panels' header menus",
            claims: [
                .feature("recipes.base-looks"),
                .feature("workspace.panels"),
                .section(.baseLooks),
                .section(.recipes),
            ],
        ) { app in
            try app.openWorking()
            let portra = try portra(app)
            guard let look = portra.baseLook else { throw ScenarioFailure("Portra 400 has no look") }
            let sections = try app.main { $0.expandedSidebarSections }
            defer {
                try? app.main { model in
                    model.recipes.setHidden(FilmLookCatalog.group, in: .baseLooks, false)
                    model.recipes.setHidden("Essentials", in: .recipes, false)
                    model.expandedSidebarSections = sections
                }
            }
            try app.main { model in
                RevealedRecipeFiles.emptySearches()
                model.expandedSidebarSections = [.baseLooks]
                BaseLookPreviews.choice(id: look.id, model: model).map { model.chooseLook($0) }
            }
            try app.wait("Portra 400 chosen") { $0.baseLook.id == look.id }

            let folder = Target.identifier("baseLooks.folder.\(FilmLookCatalog.group)")
            try app.waitUntilClickable(folder.identifier)
            let items = try app.rightClick(folder, choosing: "Hide “Film Stocks”").map(\.title)
            try app.expect(items == ["Open Film Looks", "Hide “Film Stocks”"], "Film Stocks' menu is \(items)")
            try app.wait("Film Stocks hidden") { model in
                !BaseLookPreviews.panelFolders(model).contains { $0.name == FilmLookCatalog.group }
            }
            let (found, keeps, named) = try app.main { model in
                (
                    BaseLookPreviews.search("portra", model: model).filter { $0.folder == FilmLookCatalog.group },
                    model.baseLook.id == look.id && model.recipes.isAvailable(model.baseLook),
                    BaseLookPreviews.menuSections(model).contains { $0.ids.contains(look.id) },
                )
            }
            try app.expect(found.isEmpty, "Base Looks' search still finds \(found.map(\.name))")
            try app.expect(keeps, "The photo lost its film stock when Film Stocks was hidden")
            try app.expect(named, "Basic's Base Look menu no longer names Portra 400")
            let header = try app.rightClick(.sidebarHeader(.baseLooks), choosing: "Show “Film Stocks”").map(\.title)
            try app.expect(header.contains("Expand All Panels"), "Base Looks' header menu is \(header)")
            try app.wait("Film Stocks shown again") { model in
                BaseLookPreviews.panelFolders(model).contains { $0.name == FilmLookCatalog.group }
                    && !model.recipes.hiddenFolders(in: .baseLooks).contains(FilmLookCatalog.group)
            }
            app.covered([.section(.baseLooks), .feature("recipes.base-looks")], via: .mouse)

            try app.main { $0.expandedSidebarSections = [.recipes] }
            try app.waitUntilClickable("recipes.folder.Essentials")
            try app.rightClick(.identifier("recipes.folder.Essentials"), choosing: "Hide “Essentials”")
            try app.wait("Essentials hidden") { model in
                !model.recipes.sections.contains { $0.name == "Essentials" }
                    && !model.recipes.presets.contains { $0.isBundled && $0.group == "Essentials" }
            }
            try app.rightClick(.sidebarHeader(.recipes), choosing: "Show “Essentials”")
            try app
                .wait("Essentials shown again") { model in model.recipes.sections.contains { $0.name == "Essentials" } }
            try app.choose(.resetAll)
            app.covered([.section(.recipes), .feature("workspace.panels")], via: .mouse)
        }
    }

    extension RunningApp {
        /// Waits until a click at the middle of the left panel's row carrying `identifier` lands on that row: the
        /// panels open and close with an animation, and a list lists its rows again as what it shows changes, so a
        /// row found a moment ago may not be where it was.
        func waitUntilClickable(_ identifier: String) throws {
            pause(0.4)
            try wait("\(identifier) where a click lands on it") { _ in
                guard let window = Views.editorWindow, let frame = Views.find(identifier, in: window),
                      let hit = window.contentView?.superview?.hitTest(NSPoint(x: frame.midX, y: frame.midY))
                else { return false }
                return sequence(first: hit) { $0.superview }.contains { $0.accessibilityIdentifier() == identifier }
            }
        }
    }

    /// The files Show in Finder showed while a scenario noted them, rather than opening Finder.
    @MainActor
    enum RevealedRecipeFiles {
        static var files: [URL] = []

        /// Empties Base Looks' and Recipes' search fields, as deleting their text does, so their panels list their
        /// folders: a scenario before may have searched one.
        static func emptySearches() {
            guard let root = Views.editorWindow?.contentView?.superview else { return }
            for field in Views.all(NSSearchField.self, in: root)
                where ["baseLooks.search", "recipes.search"].contains(field.accessibilityIdentifier())
                && !field.stringValue.isEmpty {
                field.stringValue = ""
                field.delegate?.controlTextDidChange?(Notification(
                    name: NSControl.textDidChangeNotification,
                    object: field,
                ))
            }
        }
    }
#endif
