# Base Looks panel, and Recipes as presets: design

**Rows:** DEC-104 (the decision), UX-54 (the Base Looks panel), UX-55 (removing and hiding recipes and looks). **Revises:** DEC-74's placement of looks (UX-45, 13 October 2026). **Approved:** the owner's decisions of 16 October 2026, below, and his answers to the wireframes' questions the same day.

## Why

A photographer gave the owner feedback on a call (16 October 2026). Base looks and film simulations are the starting point of an edit, and far more useful to them as such than presets; they want them in a section of their own, before Recipes, and searchable. Recipes would then hold only what are presets, which they'd like to show in Finder or remove.

The way a photographer works, as they put it: open a photo, establish its base look, perhaps a film stock, and then edit, starting from a preset and adjusting it, or with their own adjustments.

Today Redlamp lists every film stock, the firmware model's simulations and imported LUTs as recipes, in the Recipes panel (DEC-74), and the README's first goal calls "presets, profiles and LUTs are all Recipes" a deliberate exception to Lightroom. This design keeps what DEC-74 was after (looks found on the left, with search and hover preview, each listed once) and gives looks their own panel.

## The owner's decisions (16 October 2026)

1. **The panel is called Base Looks,** the name Basic, the browser, ⌘K and the docs already use.
2. **A recipe that carries a Base Look still sets it,** as today and as a Lightroom preset that includes a profile. Its row is marked, so the photographer sees it before applying it. (24 of the 39 starter recipes and all 20 moods carry one.)
3. **A film stock brings its look and its own grain, halation and bloom,** and Black & White for a monochrome stock, wherever it's chosen. Every other setting stays as it was, the rest of Effects included. Today a film stock is applied as a recipe that includes the whole Effects group, so choosing another film after editing resets the vignette, light leak, dust and frame.
4. **Basic's Base Look menu stays as it is for now.**
5. **Show in Finder and Move to Trash** for the photographer's own and installed recipes and imported looks, and **hiding whole built-in groups** in either panel.
6. **Leaving a film stock for a look that isn't one takes the film's grain, halation and bloom away** (answered later the same day). Going from Portra 400 to Redlamp Color leaves no film grain behind.
7. **A colour look chosen in place of a monochrome one sets Color** (answered with the wireframes' questions, the same day), as Lightroom's colour profiles do: Portra 400 after Tri-X 400 renders in colour. Black & White the photographer chose on a colour look stays.

## The left column

Navigator, Folders, **Base Looks**, Recipes, Snapshots, History: from top to bottom in the order of the work. Base Looks is a `SidebarSection` with the same panel component, header, collapse and Expand All Panels as the others, symbol `camera.filters`.

## The Base Looks panel

From the top:

1. **The header's + menu:** Import LUT (`.cube`, `.3dl` or HaldCLUT)…, with the input space accessory the Recipes panel uses today; Choose Camera Profiles…, the chooser Basic's menu has (TON-51); and Get Fujifilm's LUTs…, the link the browser has.
2. **Search,** "Search Base Looks": names, summaries, makers and kinds ("kodak", "slide", "negative", "cinema", "black and white"). The words profile, film, simulation and LUT list a whole kind, as Lightroom's words do in recipe search. Results are one list, as in Recipes; nothing found shows "No matching Base Looks". Each result shows its folder at the end of its row.
3. **The photo's look, with its Amount** (0 to 200), as the Recipes panel shows the applied recipe's Amount. It sets the same value as Basic's Base Look Amount.
4. **The looks, in folders,** in this order, each shown only when it has looks:
   - **Favorites**
   - **In This Photo:** the camera profile look a DNG embeds.
   - **The photo's camera profiles** (TON-51, TON-52): Adobe Raw, Camera Matching, the photographer's own and the creative groups inside one Creative folder, as Basic's menu lists them, where those profiles are on this Mac.
   - **Redlamp:** Color, Neutral, Vivid, Landscape, Portrait and Monochrome.
   - **Film Styles:** the 15.
   - **Film Stocks:** the 36, with their icons, by kind, each variant beside its stock, as Recipes › Film Stocks lists them today. Its right-click menu opens the Film Looks window.
   - **Firmware Model:** the 20 simulations, while Settings' Experimental switch is on; not in the App Store build.
   - **Fujifilm LUTs,** then **Imported:** the LUTs the photographer imported, and installed looks no recipe uses.
   - **Reproduction:** Redlamp Reproduction.

Hovering a look previews it as a click applies it; a click applies it as one History step. Favorites, previews and icons come from what exists: film stocks keep the favourites the Film Looks window gave them. Favorites, Redlamp and the folder holding the photo's look start open, that folder opening again for each photo, and the photo's look is highlighted in it, as History highlights the current step.

**Right-click a look:** Add to Favorites or Remove from Favorites. A film stock also has Apply Without Grain, Halation and Bloom (today's Apply Base Look Only, previewing while highlighted). An imported look also has Show in Finder and Move to Trash (UX-55). **Right-click a folder:** Hide (built-in folders, UX-55); Film Stocks also has Open Film Looks.

## What choosing a look applies

A look that isn't a film stock sets the Base Look, as `EditorModel.setBaseLook` does today, Black & White included for a monochrome look.

A film stock sets its Base Look, Black & White for a monochrome stock, and the film's eight parameters: Grain Amount, Size, Roughness and Color, Halation Amount and Size, Bloom Amount and Size. The ones the stock doesn't list take their defaults, so moving from CineStill 800T to Portra 400 takes the bloom away. Nothing else changes.

A look that isn't a film stock, chosen while the photo's look is one, also returns those eight to their defaults (decision 6), whatever they were set to since, so going from Portra 400 to Redlamp Color leaves no grain. Its Apply Without Grain, Halation and Bloom does the same. Chosen while the photo's look isn't a film stock, it leaves them as they are, so grain the photographer added on Redlamp Color stays when they try Vivid. The photo's look counts as a film stock whether a choice or a recipe (a mood) set it. Recipes apply as they do today (decision 2). A colour look chosen while the photo's look is monochrome sets Color (decision 7); one chosen while it's a colour look leaves the treatment as it is.

One choice in RedlampRecipes does this wherever a look is chosen: the Base Looks panel, Basic's Base Look menu and browser, the Film Looks window (whose header Amount becomes the Base Look's) and ⌘K. Hovering a look previews it as that choice would apply it. Edits made before keep their settings, and the edit's applied recipe stays recorded; nothing renders differently, so there's no new process version. The CLI and the MCP server keep applying the bundled film recipes as they do today.

## The Recipes panel

- **Presets only:** Favorites, My Recipes and the photographer's lists, Essentials, Portrait, Landscape, Street, Film-inspired, Camera Recipes, Black & White, Night, Mood and Installed. Film Stocks, Firmware Model, Imported and Fujifilm LUTs move to Base Looks.
- **Which recipes are looks** is decided in one place: the bundled film stocks (`FilmLookCatalog`), the firmware model's recipes, and imported LUTs, which are recipes tagged `lut` that set only a Base Look. An imported LUT the photographer has made into a fuller recipe stays in Recipes.
- **A recipe that sets a Base Look is marked** (decision 2): its row shows its look's icon where the look has one, as the moods show their film's today, and the Base Looks symbol otherwise; the tooltip names the look ("Also sets the Base Look: Chrome").
- **The + menu:** Create Recipe from Current Edit… (⇧⌘N) and Import Recipe or Lightroom Preset…. LUTs import from Base Looks. A drop on either panel imports each file into the panel it belongs in and opens the folders it went to, as EDT-11's drop does.
- **Search** finds recipes only; Base Looks are no longer listed after them (UX-45). Lightroom's words keep working. When nothing matches, the placeholder says that looks and film stocks are searched in Base Looks.
- **Right-click a recipe:** Add to Favorites, Apply Base Look Only (for a recipe with a look), Export…, Duplicate to My Recipes; for the photographer's own and installed recipes, Show in Finder and Move to Trash (UX-55), which replaces Delete Recipe.

## Removing and hiding (UX-55)

- **Show in Finder** selects the file Redlamp keeps: the recipe in `Application Support/Redlamp/Recipes` (or `Recipes/Installed`), which for an imported look is the recipe that holds it, and for a Lightroom preset the recipe made from it.
- **Move to Trash** moves that file to the Trash, recoverable from there; today's Delete Recipe removes it at once, without asking. The look stays in `Looks/`, so edits that use it keep rendering, but it's listed nowhere afterwards: today a deleted LUT's look comes back under Installed in Basic's menu, and that must stop. An installed look no recipe uses (one today's Delete Recipe left, listed under Imported) has Remove from Base Looks instead: it's listed nowhere afterwards and its file stays for its edits, with no Show in Finder, since its file is named by its content.
- **Hiding a built-in folder** removes it and its items from its panel, its search and ⌘K; the photo keeps rendering with a hidden look, and the panel's Amount row still names it. Each panel's header menu lists the hidden folders to show again. Hidden folders are one preference, as Lightroom Classic's Manage Presets hides preset groups. The photographer's own lists aren't hidden; their recipes can be moved to the Trash. Adobe Raw, Camera Matching and Creative are built-in folders here, and the photographer's own profiles aren't.

## Elsewhere in Develop

- **Basic's Base Look menu** keeps its entries (decision 4). Its tooltip, which sends film looks and LUTs to the Recipes panel, points to Base Looks instead.
- **⌘K:** the Recipes page lists the presets the Recipes panel lists, and the Base Looks page every look the Base Looks panel lists, a film stock applying as decision 3 has it. Otherwise film stocks would be on neither page.
- **Browse Base Looks…** and the **Film Looks window** stay; the window opens from Base Looks › Film Stocks, the Window menu and ⇧⌘L.

## Later, not in this work

One visual browser for every look, the Film Looks window grown to cover them all, in place of Basic's Browse Base Looks popover. A shorter Basic menu, if the panel makes it redundant.

## Tests, scenarios and docs

- **RedlampRecipes:** which recipes are looks; a film stock's choice keeps vignette, light leak, dust and frame, sets its eight parameters, sets Black & White for a monochrome stock and takes bloom away when the next stock has none; a look that isn't a film stock, chosen over one, returns the eight to their defaults, and chosen over a look that isn't one, keeps the photographer's own grain; hidden folders are saved and read; Move to Trash leaves the look renderable and unlisted.
- **RedlampUI:** the column's order; Base Looks' folders, search, favourites and Amount row; recipe rows' marks; which menus show Show in Finder, Move to Trash and Hide; Recipes search without Base Looks; ⌘K's two pages.
- **Regression scenarios** (`RedlampAutomation`), each through the user's own input: search Base Looks and apply a film stock over an edit with a vignette, which stays; Show in Finder and Move to Trash on an imported recipe; hide and show a built-in folder. The scenarios that used Recipes › Film Stocks or Base Looks in recipe search move to the panel. A Report a Bug feature for Base Looks.
- **Docs:** the README's first goal, its Develop and Recipes bullets, and Film simulations; the Lightroom comparison's Profiles, Presets and Each look in one place rows; the manual's Recipes and Base Look pages; the site's features; the redlamp-look-icons skill, which places icons in the Recipes panel.

## Slices

1. **The model:** which recipes are looks, the film stock's choice, hidden folders, Move to Trash, with their tests (RedlampRecipes, `EditorModel`).
2. **The panel:** Base Looks in the left column, Recipes as presets with marked rows, imports and drops, ⌘K's pages, the Film Looks window choosing as the panel does (RedlampUI).
3. **Removing and hiding:** Show in Finder, Move to Trash, Hide and the hidden folders in both panels (UX-55).
4. **Scenarios and docs,** then the app tried by the owner.
