# Adobe's camera profiles (TON-51, TON-52)

Started 2026-10-15, on DEC-85's terms. TON-09's [DCP design](2026-10-02-dcp-profiles-design.md) is the base: it split a profile into a calibration (matrices and HueSatMap), applied in the develop kernel, and a look (LookTable and tone curve), baked into a scene-referred Base Look. This note covers its third slice, the photographer's own `.dcp` files (TON-51, #432), and Adobe's XMP looks over them (TON-52, #433). EDT-33 (#434) builds on both.

## What the photographer gets

The Base Look menu lists, for the open photo's camera, the Adobe profiles on the Mac: Adobe Standard and the six Adobe Raw looks (Adobe Color, Portrait, Landscape, Neutral, Vivid and Monochrome), the camera's Camera Matching profiles, the photographer's own profiles, and the creative looks, grouped as Lightroom groups them. Choosing one sets the edit's Base Look, so existing edits render as before. Choose Camera Profiles… adds `.dcp` and `.xmp` files from anywhere on the Mac.

Where an edit's profile isn't on the Mac (another Mac, a photo someone shared, a profile Adobe has since updated), Redlamp's look of the same name renders in its place, and the photo says so: "Adobe Color isn't on this Mac · Redlamp Color stands in".

## Where profiles come from

- **Camera Raw's folder**, `/Library/Application Support/Adobe/CameraRaw`, which Lightroom Classic and Photoshop's Camera Raw install: `CameraProfiles/Adobe Standard/<camera> Adobe Standard.dcp`, `CameraProfiles/Camera/<camera>/*.dcp` (Camera Matching), and the XMP looks under `Settings/Adobe/Profiles`.
- **The photographer's Camera Raw folder**, `~/Library/Application Support/Adobe/CameraRaw`: `CameraProfiles` (their own DCPs, and those Lightroom imported) and `Settings` (XMP profiles Lightroom imported).
- **Files the photographer chooses**, remembered by their location and read where they are, as LNS-16 reads lens profiles: never copied.

Only file names are listed until a profile is needed: Adobe's folder holds a profile for every camera Adobe supports. A folder's file is read once, and again when its modification date changes. A DCP belongs to a camera when its UniqueCameraModel names the photo's make and model, compared as LCP lens profiles compare them (LNS-04): case, spaces and a repeated make set aside.

## Identity, and DEC-85's terms

A profile's look is `local/adobe/<profile>` for a DCP and `local/adobe/<profile>/<look>` for an XMP look over a DCP, each part 16 hex digits of a SHA-256 over what renders (the matrices, tables, curve and offsets; not names or copyright). The same files on another Mac give the same id. The reference's `version` is the bake's version, and it carries no `contentHash`: the id already pins the content, and nothing of the profile is stored anywhere.

Only a camera's own profiles calibrate its photos. An edit synced or pasted onto a photo from another camera keeps naming the first camera's profile, and renders over the second camera's own: an XMP look over its profile of the same name with the same look hash, a DCP look as its profile of the same name, as Lightroom applies Adobe Color over each camera's Adobe Standard. A look the second camera has no profile for (a camera-matching look made for the first) is missing there, and Redlamp's look stands in.

- Nothing of Adobe's is written by Redlamp: not in sidecars (the edit names the profile and its id), exported recipes, `.cube` exports, or Redlamp's Looks store. `BaseLookReference.staysOnThisMac` covers `local/adobe/`, so the paths that refuse DEC-73's looks refuse these too.
- A profile renders only while its files are on the Mac, read where Adobe or the photographer put them.
- ProfileEmbedPolicy says whether a profile may be copied or embedded in other files. Redlamp does neither, whatever the policy, so every policy allows the use described here; the menu's help names the policy.

## Calibration

An Adobe look brings its profile's calibration, as Lightroom's profiles do: its ColorMatrix and ForwardMatrix pairs, interpolated by the edit's colour temperature, in place of the camera's matrix, and its HueSatMap in place of a DNG's own, blended the same way (`HueSatMaps`). The develop kernel already applies both (process 4); only their source changes, at any process version, since no existing edit names an Adobe look. Redlamp's own looks keep the camera's calibration. TON-51's row asked for a Calibration choice the edit pins: the Base Look reference is that choice, since its id names the profile.

For a DNG, the profile's matrices replace the file's, and the file's AnalogBalance stays. A profile's DefaultBlackRender is ignored, as TON-09 ignores it, and a ProfileGainTableMap applies only with the DNG's own look.

## The look

A DCP's look is baked as TON-09 bakes an embedded profile's (`EmbeddedLook`): scene light scaled by BaselineExposureOffset, the LookTable in linear ProPhoto, then the tone curve with the DNG SDK's hue-preserving RGB method. A profile without a tone curve gets Redlamp's own, as the embedded Adobe Standard of the Pixel fixture does: Adobe's default curve is Adobe's data.

An XMP look goes over its base DCP, Adobe Standard unless it names another (`crs:CameraProfile`); creative looks name none and go over the camera's Adobe Standard. The bake is the base's LookTable, the look's HSV table, the base's tone curve, the look's curve (ToneCurvePV2012, on sRGB-encoded values with the same hue-preserving method), and the look's RGB table. In Camera Raw the RGB table applies after the user's colour controls; baked into the Base Look it applies before Redlamp's, which is the same while those controls are at zero.

### Adobe's encoding

A look's tables are `crs:Table_<md5>` attributes named by `crs:LookTable` and `crs:RGBTable`: base 85 in Adobe's alphabet, least significant digit first, over a zlib stream whose expanded length comes first, as RAWmakase's MIT reader documents. An HSV table is a version (1 or 2), its divisions, hue shift and scales per point in the DCP's order, an encoding (linear or sRGB) and, in version 2, the amounts it may be applied at. An RGB table is 1D or 3D (up to 64 divisions), 16-bit differences from the identity, its primaries (sRGB, Adobe RGB or ProPhoto), its encoding (linear, sRGB, 1.8 or 2.2), whether it clips or extends colours outside it, and its amounts. 3D tables interpolate tetrahedrally.

### Amount

The Base Look Amount runs from 0 to 200, as Lightroom's Profile Amount does.

- **XMP looks** follow Camera Raw's rules over their base: the HSV table's shifts and scales grow with the Amount, within the bounds a version 2 table stores (a version 1 table stays at 100); the curve is mixed in up to 100 and applied again at the excess above (200 applies it twice); the RGB table applies at `RGBTableAmount` times the Amount within its bounds. Amount 0 is the base profile. Lightroom gives the Adobe Raw looks no Amount; Redlamp applies the same rules to them, with bounds of 0 to 200. The bake depends on the Amount, so it is made for each whole Amount an edit uses, and the last few are kept.
- **DCP looks** mix with Redlamp's tone curve by Amount, as embedded looks do: 0 is the profile's calibration under Redlamp's curve.

### Settings inside a look

A few looks carry develop settings (Exposure, Shadows, Clarity, the colour mixer, split toning, a vignette, the black-and-white mix). Redlamp's sliders aren't Lightroom's (EDT-24 fits them), so these are left out and named in the look's help in the menu. A look that converts to black and white (`crs:ConvertToGrayscale`) sets the Monochrome treatment, as Redlamp Monochrome does. Looks that need the photo's own RGB tables (`crs:RequiresRGBTables`) and Fujifilm's camera-matching XMPs, whose tables Camera Raw keeps elsewhere, are refused with a reason.

## Stand-ins

By name: Adobe Color, Portrait, Landscape, Neutral, Vivid and Monochrome to Redlamp's look of that name; Adobe Standard to Redlamp Color; camera-matching and creative profiles by the words in their names (a B&W or Monochrome look to Monochrome, Neutral or Flat to Neutral, Vivid or Velvia to Vivid, Portrait or Astia to Portrait, Landscape to Landscape), else Redlamp Color. The Lightroom edits design maps names the same way, and EDT-33 uses this table.

## Tests

Synthetic profiles only: Adobe's files are never committed. DCPs are written as TIFF tags, XMP looks with tables encoded by the test's own base-85 and zlib writer. The bake is checked against a CPU reference of each step, the calibration against the develop kernel's output, the Amount's rules at 0, 50, 100 and 200, and the process-stability gate keeps every existing reference unchanged.
