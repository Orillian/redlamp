---
name: redlamp-look-icons
description: Designs and produces the small icons that identify Redlamp's looks beside their names, in the Base Looks panel, on the rows of recipes that set a look, in the Base Look menu and browser, and in the Film Looks window. Covers film stock icons (FilmIcon, a canister, slide mount, cinema reel or paper print in the stock's colours with its speed) and new kinds of icon that convey a look's mood where it isn't a film stock. Renders a review sheet at the sizes the app shows them, in the dark and light themes, and regenerates the icons the README and redlamp.app show. Use when adding or re-tuning a film stock, giving a recipe or look an icon, designing a new kind of look icon, or when the user mentions film icons, look icons, recipe icons or the icon sheet.
---

# Look icons

A look's icon sits beside its name so it can be found by eye in a long list. Each kind of icon is Redlamp's own drawing in CoreGraphics on a 64-unit grid, made to read at 16 points.

## Where icons show

| Where | Size | Code |
| --- | --- | --- |
| Base Looks panel rows, in its folders and its search | 16 pt, the row's symbol slot | `SidebarCellView`, `Layout.lookIconSize` |
| Recipes panel rows of recipes that set a Base Look: the look's icon, or the Base Looks symbol for a look without one | 16 pt, the row's symbol slot | `SidebarCellView` and its `lookSet(by:model:)`, `Layout.lookIconSize` |
| Base Look menu | 18 pt | `BaseLookMenu` in `BasicPanel.swift` |
| Browse Base Looks… tiles, top left | 22 pt | `BaseLookBrowser` |
| Film Looks window cards | 36 pt, and 96 pt with no photo open | `FilmCatalogView` |
| README catalogue and redlamp.app/film | 256 px PNG | `docs/images/film/icon-<id>.png` |

Every place asks `LookIcons` (`packages/RedlampRecipes/Sources/LookIcons.swift`) which icon a recipe or Base Look shows, and draws it through `LookIconImage`, which caches one image per icon and size. A recipe with no icon of its own shows its Base Look's: a mood, or a recipe of your own built on Portra 400, shows Portra's canister. The film stocks themselves are looks, listed in Base Looks rather than with the recipes (DEC-104).

## The film icon

`FilmIcon` (`packages/RedlampRecipes/Sources/Film/FilmIcon.swift`) is set on each look in `FilmLookCatalog`:

- **shape:** `.canister` for 35 mm negative film, `.slide` for slide film (its band is the transparency in the mount), `.reel` for cinema film printed on 2383, `.paper` for a darkroom print.
- **body, band, text:** the stock's familiar colours, as sRGB values from 0 to 1. The body is the canister, mount, reel or paper; the band is the label band, the transparency, the reel's label or the print's image.
- **label:** the speed, or a variant's mark: `400`, `800T`, `E100`, `K64`, `+2` (overexposed), `1600` (pushed), `G1` and `G4` (paper grades), `BB` (bleach bypass), `XPRO` (cross-processed). Four characters at most; it shrinks to fit.
- **leader:** orange-brown (the default) for colour negative, `(0.3, 0.3, 0.3)` for black and white.

A variant keeps its stock's body and band and changes the label, so Portra 400 · +2 sits beside Portra 400 and reads as its sibling.

**The existing film icons don't change** (the owner, 13 October 2026). Add icons for new stocks; never redraw, recolour or relabel a published one, at any size, without the owner asking.

## Rules every icon follows

- **Redlamp's own drawing.** Use the stock's colours, never a maker's logo, lettering, typeface or packaging artwork, and never anything taken from another app. The film names are trademarks of their owners (`web/content/films.ts`).
- **Lit from above left**, as the brand sheet says (`docs/brand/README.md`): a highlight down the left, a shade down the right.
- **Colour stays inside the shape.** The editor's surfaces stay neutral grey so nothing tints the photographer's judgement; an icon is transparent around its shape, with no background plate.
- **Reads at 16 pt.** A single silhouette that tells the kind at a glance (canister, mount, reel, print), and colours that tell the stocks apart. Check the 1x and 2x columns of the sheet before anything else.

## The review sheet

```bash
redlamp recipe icons                 # build/icons/look-icons.png
redlamp recipe icons --readme        # and docs/images/film/icon-<id>.png
redlamp recipe icons --styles --photo build/look-dev/Sony_ILCE-6700.ARW   # the styles proposed for other looks
```

Build the CLI first: `xcodebuild build -workspace Redlamp.xcworkspace -scheme redlamp -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData-<key>`, then run `build/DerivedData-<key>/Build/Products/Debug/redlamp`.

Each row is one icon: its name, then on the dark panel grey and on the light one, 16, 18 and 22 pixels (1x), then 32, 36, 44 and 72 pixels (2x). Read the image back and look at it before calling an icon done; crop it with PIL when it's long.

## Adding a film stock's icon

1. Add the look to `FilmLookCatalog` with its `icon:` (the film looks design, `docs/plans/2026-09-30-film-looks-design.md`, covers the rest of a look).
2. Run the sheet; compare the new row with its neighbours of the same kind, and with the stocks whose colours are close.
3. `redlamp recipe icons --readme` writes its PNG; the test `every film icon draws` (`FilmModelTests`) checks every icon draws.
4. Add the stock to `web/content/films.ts` with its icon, as `.cursor/rules/landing-page.mdc` says.

## A new kind of icon

For looks that aren't film stocks: the moods, the starter recipes, the Film Styles, Redlamp's own looks.

1. Draw two or three styles on a few looks each, as `IconStyles` in `apps/RedlampCLI/Sources/` does, and run `redlamp recipe icons --styles`. Say what each style shows and how it reads at 16 pt.
2. Put the sheet to the owner as a question on the looks wireframes canvas (`.cursor/skills/screen-wireframes/SKILL.md`), with your recommendation. Nothing ships before the owner picks a style; the pick becomes a tracker row.
3. Build the chosen style as a type beside `FilmIcon` in `packages/RedlampRecipes/Sources/`, on the same 64-unit grid, with its fields stored where the looks are defined (`MoodLooks`, `StarterPack`, `StarterPackLooks`).
4. Add a case to `LookIcon` and resolve it in `LookIcons.icon(forID:)`; add its rows to `LookIcons.all` so the sheet shows them. Move `IconStyles`' drawing for the chosen style into the new type and delete the rest.
5. Add a test beside `every film icon draws` that every icon of the new kind draws and isn't mostly empty.

The first sheet (13 October 2026) found that scene objects read at every size, that mood marks read when the mark is a frame or a halo but a light leak barely shows, and that chips rendered from one photo look alike at list sizes, since the photo outweighs the look.
