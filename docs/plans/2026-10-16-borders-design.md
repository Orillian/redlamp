# Borders around the photo (TON-53, TON-54, EDT-35)

A photographer pointed out that Redlamp mixes moods with borders. Today's Frame (TON-25) sits in the Effects panel and the recipes' Effects group, is drawn over the photo's edges, and comes and goes with whichever mood is applied. This design makes borders a feature of their own: drawn around the photo, chosen in a Border panel and a Borders folder in Recipes, kept apart from looks and moods, and handled at export.

## Decisions (the owner, 2026-10-16; DEC-105)

1. **A border goes around the photo.** The canvas grows to the chosen shape and nothing of the photo is hidden, as borders made with Lightroom Classic's Print to JPEG or with export plug-ins are. Lightroom has no border in Develop; the one trick there, the post-crop vignette set to paint white, covers the photo as TON-25's frame does.
2. **In scope:** plain borders and mats, film and instant frames (TON-54), and borders at export (EDT-35).
3. **Left out:** text in the border (an EXIF line, a caption, a signature; EDT-25's watermarks are where text goes later) and a blurred copy of the photo as the border.

## What's wrong with the frame today

- At its default size the 35 mm rebate hides 13% of the photo's height along each long side, and the print border 3.5% on every side (`frameBorder` in `Develop.metal`).
- `effects.frame.*` belongs to the recipes' `effects` group, so applying a mood resets the frame, and a frame can't be a recipe without resetting grain, glow and leaks. Five moods carry one.
- Amount blends the frame's style as a slider: Lost Roll (the rebate, 3) at 50% blends to 1.5, which rounds to the print border.
- The histogram and clipping warnings count the frame's pixels.

## The model

A border is described by `border.*` parameters in the edit, each defaulting to no border, so no process version changes and every existing edit renders as it did. `BorderLayout` (RedlampEngineAPI) turns them and the developed photo's size into the canvas size and the photo's rect within it; `GeometryMap` carries both, so the canvas, stills, thumbnails and exports read the bordered size from one place, while `developedSize` stays the photo's own.

| Key | Range | Default | Meaning |
| --- | --- | --- | --- |
| `border.style` | 0…9 | 0 | `BorderStyle`: None, Plain, 35 mm Film, Medium Format, Instant Square, Instant Mini, Instant Wide, Slide Mount, Slide Mount (Plastic), Filed Carrier. Raw values never change |
| `border.shape` | 0…9 | 0 | `BorderShape` for Plain: Even, 1:1, 4:5, 3:4, 2:3, 9:16, 5:7, 11:14, A paper (1:√2), Custom. Raw values never change |
| `border.orientation` | 0…2 | 0 | Match Photo, Portrait, Landscape |
| `border.ratioWidth`, `border.ratioHeight` | 1…100 | 4, 5 | The Custom shape |
| `border.size` | 0…20 | 4 | The margin on the narrowest sides, in percent of the photo's long side |
| `border.offsetX`, `border.offsetY` | −100…100 | 0 | Where the photo sits in the spare margin: +100 vertical puts all of it below the photo, +100 horizontal all of it to the left |
| `border.red`, `border.green`, `border.blue` | 0…255 | 255 | The border's colour, in sRGB |
| `border.keylineWidth` | 0…2 | 0 | A line around the photo, in percent of its long side |
| `border.keylineGap` | 0…5 | 0 | The keyline's distance from the photo, in percent of its long side |
| `border.keylineRed`, `…Green`, `…Blue` | 0…255 | 0 | The keyline's colour, in sRGB |
| `border.edgePrint` | 0…1 | 1 | Edge print on 35 mm and medium format |
| `border.frameNumber` | 0…36 | 0 | The edge print's frame number; 0 follows the file's number |

Shapes are short side to long side; Orientation decides which way round. Match Photo turns the shape with the photo, as a print on paper does; Portrait keeps a landscape photo on a 4:5 canvas, as Instagram's feed wants, and gives a carousel of mixed photos one shape. With a shape, the photo is scaled into the canvas leaving at least Size on its narrowest sides, so the canvas is the photo plus margins, never a crop. Sizes are relative to the photo, so a border looks the same at any export size.

Film and instant styles take their format's proportions around the photo, following its shape; Size, Shape and Position apply to Plain. Colour sets the instant card's and the slide mount's colour.

## The Border panel

In Develop's right column, after Effects (Calibration stays last, as in Lightroom), symbol `photo.artframe`, with the on/off switch every panel has. The switch also takes the border away while judging tone, since a white mat makes a photo look darker and a black one lighter.

- **Style** menu.
- **Shape** menu and **Orientation** (Plain), with the Custom ratio's two fields.
- **Size**, **Vertical** and **Horizontal** sliders (Plain).
- **Colour:** White, Paper, Grey and Black swatches and a colour well; the system colour panel's magnifier picks a colour from the photo.
- **Keyline:** Width, Gap and its colour (Black, White, Grey swatches and a colour well).
- **Edge Print** and **Frame** (35 mm and medium format), **Crop to Format** (film and instant styles: sets the crop's aspect to the format's).

## Recipes: a Borders folder

`RecipeSettingGroup.border` holds the `border.*` keys. A recipe that doesn't include it leaves the photo's border alone; a Borders recipe includes only it and leaves the look alone. The legacy `effects.frame.*` keys stay in `effects`, so recipes already written behave as before and the recipe format needs no new version; an older Redlamp keeps the unknown group and warns that the recipe needs a newer version.

The built-in Borders folder sits after Mood: White 4:5, Black 4:5, White 3:4, White Square, Black Square, Story 9:16, Thin White, Thin Black, Gallery Mat (Even, generous, raised for a heavier bottom), Gallery Mat with Keyline, Print 8×10 (4:5, Match Photo), then 35 mm Film, Medium Format, Instant Square, Instant Mini, Instant Wide, Slide Mount and Filed Carrier. Built-in folders can be hidden (UX-55).

- **Moods** get new versions without frames: Lost Roll, Summer '98, Home Movie, Slide Show and Contact Sheet. Edits made with the old versions keep their frames, which were written into them.
- **Create Recipe** leaves Border unticked by default, so saving a look never captures its border; with only Border ticked, the sheet suggests the Borders list.
- **Copy Settings:** the Border item is unticked by default, as Crop is: syncing a look across a shoot doesn't spread a border. Tick it to give a carousel the same border.
- **Amount** never blends the border group, and the Amount row is hidden for a recipe that holds only a border. Settings that are choices (styles, shapes, the treatment already) switch at 50% instead of blending, which also fixes legacy recipes with frames.

## On the canvas

- The develop pipeline renders the photo as before; a border pass then composites it into the canvas and fills the pixels around it. The histogram and clipping warnings are taken from the photo, before the pass, so a white border never reads as clipped.
- Zoomed in, the region asked for is in canvas coordinates; the photo's part of it is rendered at the same scale, and a region that is all border skips the develop work.
- Masks, spots, and the white balance and Point Color samplers ignore points in the border: canvas points map through the photo's rect, and outside it a tool gets no point.
- The crop tool and the colour-assessment view (⇧L) show the photo without its border.
- Thumbnails and the library grid show it, as exports do.

## Film and instant frames (TON-54)

From the formats' published dimensions, scaled to the photo's short side:

| Style | Proportions |
| --- | --- |
| 35 mm Film | 35 mm film around a 24 mm frame: 5.5 mm of rebate on each long side with the sprocket holes (eight per frame, KS pitch 4.75 mm), 2 mm of the neighbouring gap on each short side |
| Medium Format | 120 film, 61 mm around a 56 mm frame: 2.5 mm of rebate on each long side, no holes, the gap between frames 4 mm |
| Instant Square | A 62 × 62 mm window on a 72 × 86 mm card: 5 mm sides and top, 19 mm below |
| Instant Mini | A 46 × 62 mm window on a 54 × 86 mm card: 4 mm sides, 7 mm top, 17 mm below |
| Instant Wide | A 99 × 62 mm window on a 108 × 86 mm card: 4.5 mm sides, 7 mm top, 17 mm below |
| Slide Mount | A 50 × 50 mm card mount around a 24 × 36 mm window with rounded corners and a bevel |
| Slide Mount (Plastic) | The same in dark grey plastic with a moulded rim |
| Filed Carrier | A rough-edged black border, as a filed-out negative carrier prints it, on a white paper margin |

Edge print on 35 mm and 120 is drawn in a dot-matrix face of Redlamp's own: the frame number with its arrow and half-frame mark (`12 → 12A`), and the film look's name as Redlamp names it when the photo's Base Look is a film stock, never a maker's name or logo. Frame 0 follows the file's number (its last digits, 1 to 36), so a set exported together reads as one roll.

TON-25's over-the-photo frames keep rendering in the edits that have them. Effects shows its Frame section only on such an edit, with **Move to Border**, which removes it and sets the nearest border around the photo: Keyline as Thin Black, Print Border as White, 35 mm Rebate as 35 mm Film, Slide Mount as Slide Mount.

## Export (EDT-35)

- A **Border** menu: As Edited (the default), None, then the Borders recipes, built in and the photographer's own, applied to every photo exported over its own edit. Saved with export presets and Export with Previous.
- Sizes are the bordered canvas's: Long Edge 1350 with White 4:5 writes 1080 × 1350, and the size readout says so.
- `redlamp export --border as-edited|none|<recipe id>`.

## Compatibility

- Sidecars gain the `border.*` keys only when a border is set. An older Redlamp keeps them and renders the photo without its border.
- `effects.frame.*` and `FrameStyle` stay as they are; `FrameStyle`'s raw values never change.
- Recipes written before keep their behaviour: their `effects` group still covers the legacy frame.

## Tests

- RedlampEngineAPI: `BorderLayout` for every shape, orientation, size and position; film and instant proportions.
- RedlampEngine: a golden render per style; the histogram of a photo with a white border equals the photo's without; a 1:1 region crossing the photo's edge; still sizes with and without the border; legacy frames unchanged (`FilmEffectsTests`).
- RedlampRecipes: a mood leaves the border; a Borders recipe leaves the look; Amount on choice settings; the Borders folder's golden renders and the moods' new versions.
- RedlampDocument: the sidecar schema; export sizes include the border.
- RedlampUI: the Border panel, the Copy Settings item, pointer mapping, the crop tool without the border.
- Scenarios `develop.border` and `export.border`, and a Report a Bug feature for Border.

## Open questions (on the wireframes)

1. Where the panel sits: after Effects (the lean) or last, after Calibration.
2. What Size is measured against: the photo's long side (the lean, so a border reads the same on portrait and landscape photos of a set) or its short side.
3. The moods that lose their frames keep their names (the lean), or Contact Sheet and Slide Show are renamed.
4. Edge print: the film look's name (the lean) or frame numbers only.
