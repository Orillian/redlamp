# Sony white balance by body (CAM-34)

Whether two bodies of one Sony model render the same Temperature and Tint differently in Redlamp, and what each body's own calibration would take. Studied on 30 October 2026 against `main` at 865af66a3 (process 19), with LibRaw at Redlamp's fork `f4956c4`, [RAWmakase](https://github.com/pch/rawmakase) at `17b70e8a` (MIT, read from its clone; nothing copied) and raw.pixls.us's CC0 samples.

**In short:** they do. A Sony body stores a daylight white balance preset of its own in every raw, and Adobe's DNG Converter makes each body's calibration from it, so that Camera Raw gives one Temperature and Tint the same neutral on every body. Redlamp turns Temperature and Tint into a balance with the model's colour matrix alone, so two bodies of one model, shooting one grey card in one light, render it at one Temperature and Tint a median 1.9 ΔE2000 apart (115 pairs of bodies of 24 models; 41% of pairs above 2), and each body sits a median 2.7 ΔE2000 from Lightroom's rendering of that setting. As Shot renders are not affected. What remains to measure is whether the presets' differences are the bodies' real differences, on a grey card from two bodies of one model; that is the owner's to shoot.

## 1. Where an ARW keeps its own preset

A Sony ARW keeps its white balance presets in its SR2 private data: IFD0's DNGPrivateData (0xC634) points to the SR2Private directory, whose SR2SubIFDOffset (0x7200), SR2SubIFDLength (0x7201) and SR2SubIFDKey (0x7221) locate an encrypted directory. Its WB_RGBLevelsDaylight is tag 0x7820 on recent bodies and 0x7480 on older ones, three 16-bit levels (red, green, blue, green at 1024), beside Cloudy, Shade, Tungsten, Flash and the fluorescent presets, and a table of Kelvin presets (2500, 3200, 4500, 6000 and 8500 K).

- **LibRaw reads it.** `parseSonySR2` (`src/metadata/sony.cpp`) decrypts the directory and files the presets in `color.WB_Coeffs`, the daylight one at `LIBRAW_WBI_Daylight`, and the Kelvin table in `color.WBCT_Coeffs`. Redlamp's shim (`vendor/shims/redlamp_libraw.h`) doesn't expose either today; `RawDecoder` reads only the as-shot balance (`cam_mul`) and LibRaw's matrix-derived daylight (`pre_mul`).
- **It's near the start of the file.** An a7R III file gave the same presets, as-shot balance and serial from its first megabyte as from the whole file, and the presets the other files gave from their first megabyte agree with ExifTool's reading of the whole files (section 3).
- **The body's serial:** LibRaw's `shootinginfo.InternalBodySerial`, from Sony's encrypted 0x9050 data, and `BodySerial`, from EXIF's BodySerialNumber (0xA431), which recent bodies write (the a7 V). The compacts read (RX100 VI, RX1R II, RX1R III) give neither. The a9 III's internal serial changes from file to file of what is, by its date and preset, one body, and the a1 II's reads as `ffffffffffff`, so it identifies a body only on some models.

## 2. What Adobe makes of it

RAWmakase's audit of DNG Converter 18.7 (its commit 7986f86d and `docs/camera-parity.md`, 14 October 2026; 683 samples, 465 of them public raw.pixls.us files, several bodies of a model told apart by serial) found that DNG Converter's CameraCalibration for a Sony body is diagonal, the same for both illuminants, and equal to a reference for the model divided by the body's daylight preset, each normalised to green and rounded to four decimals. One integer reference per model reproduces DNG Converter's values exactly for every body: 50 Sony references, shared by models with one sensor (the a7R V and a7CR; the a7 IV, a7C II and FX2; the a7S III, FX3 and ZV-E1). Canon bodies divide by their Daylight preset (Shade for four), Fujifilm by the D65 entry of its illuminant table and Olympus and OM System by their 5300 K preset; Nikon, Panasonic and Pentax get no calibration.

In the DNG specification, XYZ to camera is AnalogBalance × CameraCalibration × ColorMatrix, so Camera Raw gives one Temperature and Tint each body's own neutral, and a body whose preset equals its model's reference is the body the matrix describes. RAWmakase applies the calibration to its Temperature and Tint since 0.2.2 (#361; two a7CR bodies' custom white balance at a median ΔE2000 of 0.45 to 1.01 from Camera Raw), and to Canon, Fujifilm, Olympus and OM System bodies since 14 October.

## 3. The public samples

The first megabyte of each of the 130 CC0 ARWs of the 30 Sony models with more than one sample on raw.pixls.us was read with LibRaw (the pinned fork, `libraw_open_file` without unpacking, on the megabyte padded with zeros to the file's length; nothing else was downloaded). 112 opened that way; the 18 that didn't are other recording modes of bodies read in another file. LibRaw's daylight preset agrees with the one ExifTool read for RAWmakase on all 38 files both read.

Within one body the preset is the same in every file, whatever its mode or ISO (the a7 V's six files differ by 1 in 2,362). Five models have two presets, four of them with two serials and two dates:

| Model | Body: last digits of the serial, date, firmware | Daylight preset | As Shot of daylight, by the model's matrix | The two at one Temperature and Tint |
| --- | --- | --- | --- | --- |
| a6300 | …130e, 7 January 2017, 1.00 | 2580, 1024, 1848 | 4676 K, Tint +4 | Red 4.9% apart, blue 1.3%; ΔE2000 2.84 |
| | …b80d, 26 January 2017, 1.00 | 2712, 1024, 1824 | 4957 K, Tint −5 | |
| a6400 | …b30c, 15 May 2019, 1.00 | 2524, 1024, 1880 | 4908 K, Tint −12 | Red 3.5%, blue 1.1%; ΔE2000 2.32 |
| | …560c, 19 September 2019, 2.00 | 2616, 1024, 1900 | 5023 K, Tint −21 | |
| a7 II | …d50a, 13 January 2017, 2.00 | 2488, 1024, 1496 | 4981 K, Tint −7 | Red 2.0%, blue 3.1%; ΔE2000 1.85 |
| | …7f0a, 24 January 2017, 1.21 | 2440, 1024, 1544 | 4797 K, Tint −8 | |
| a7R III | …4309, 6 December 2017, 1.00 | 2384, 1024, 1620 | 4931 K, Tint +2 | Red 4.3%, blue 2.6%; ΔE2000 3.54 |
| | …f408, 12 July 2019, 3.00 | 2492, 1024, 1664 | 5063 K, Tint −10 | |
| a6400A | No serial, 8 May 2025 | 2668, 1024, 1916 | 5077 K, Tint −25 | Red 0.9%, blue 0.8%; ΔE2000 0.90 |
| | No serial, 16 May 2025 | 2644, 1024, 1900 | 5066 K, Tint −22 | |

The owner's model, the a7R V, has one public body (2515, 1024, 1800), 2.0 ΔE2000 from the reference its sensor shares with the a7CR (2423, 1024, 1799); the public a7CR body (2599, 1024, 1718) is 3.4 from it, and 2.7 from the a7R V body.

**How the differences are measured.** Each body's preset makes the light it was set for neutral on that body, so in one light body A's raw over body B's is preset B over preset A, channel by channel. At the Temperature and Tint that make A's grey card neutral, B's balanced camera RGB is then preset A over preset B: that, through the model's matrix (LibRaw's `rgb_cam`, as `ImageSession` uses it), is compared with a neutral mid grey (0.18, linear sRGB, before the tone curve) by CIEDE2000. As Shot temperatures here are McCamy's approximation, and Tint −3000 times the distance from the Planckian locus in uv, as `ColorTemperature` scales it; Redlamp's own Robertson method gives slightly different values.

## 4. All the bodies DNG Converter has calibrated

RAWmakase's facts (`data/camera-calibration-facts.json`) hold DNG Converter's calibration for 107 Sony bodies with a reference and a matrix, 24 models of them with more than one body. Each calibration is the reference over the body's preset, so the same measure applies:

| | Median | 90th percentile | Largest | Share above 1 | Share above 2 |
| --- | --- | --- | --- | --- | --- |
| Two bodies of one model, one grey card at one Temperature and Tint (115 pairs) | 1.87 | 3.75 | 5.41 | 86% | 41% |
| Each body against its model's reference, which is how Camera Raw renders the setting (107 bodies) | 2.71 | 4.97 | 7.54 | 97% | |

The worst pairs by model: the A290 5.4, the a7 5.1, the a7R III 4.5, the a7R VI 4.4, the a9 4.2, the a6400 4.0, the a7R II 3.9, the a7 III 3.6, the a7 IV 3.5. The As Shot of one light reads a median 5.0 mired and 4.3 Tint apart on two bodies, up to 19.9 mired and 18.8 Tint. For comparison, a ΔE2000 of 1 is about the smallest difference seen side by side, and 2 is plain.

## 5. What it does in Redlamp today

`CameraColorModel` (`packages/RedlampColor/Sources/CameraColorModel.swift`) turns a Temperature and Tint into a camera neutral with the photo's XYZ-to-camera matrix, LibRaw's `cam_xyz` for an ARW, and back the other way; the matrix is the model's, the same for every body.

- **A custom white balance renders each body differently.** `ImageSession.whiteBalanceRatio(for:)` gives every body of a model the same multipliers for one Temperature and Tint, so the differences in sections 3 and 4 reach the render. That is what a shoot with two bodies meets when one setting is synced or pasted across them (Sync, Auto Sync, Copy Settings, a recipe with a white balance), and what Compare and Survey show side by side.
- **Lightroom's settings render as Lightroom's only on the reference body.** A custom Temperature and Tint brought from Lightroom (EDT-23, EDT-12, the preset importer) means the body's calibrated neutral there, so EDT-23's "same neutral for the same temperature and tint" holds only for a body whose preset is its model's reference.
- **The numbers shown differ from Lightroom's.** As Shot's Temperature and Tint (`SessionBuilder`, `info.asShotWhiteBalance`), Auto's and the eyedropper's are found with the model's matrix, so they differ from Camera Raw's for the same photo by the body's calibration.
- **As Shot renders are unchanged by any of this:** the pyramid is balanced by the camera's own as-shot multipliers, which already carry the body's calibration, and `whiteBalanceRatio` is 1 at As Shot. Auto and the eyedropper measure a neutral and turn it into a Temperature and Tint and back with one model, so they render the same neutral with or without a calibration; only their numbers would change.
- **DNGs too.** `DNGColorCalibration` reads a DNG's CameraCalibration and `cameraToWorking(temperature:)` applies it, but its Temperature and Tint go through `RawDecoder.dngColorMatrix`, AnalogBalance × ColorMatrix without it, so a DNG Converter DNG of a calibrated body has the same dependence on the body (the known gap "Temperature and Tint use one matrix for DNGs too", CAM-04).

## 6. Where a reference could come from

A body's calibration needs its model's reference. They aren't the model's matrix at one daylight: by each model's own matrix, the 50 Sony references are the neutrals of whites from 4098 to 5498 K, the middle half from 5026 to 5238 K, 1.1 to 3.9 × 10⁻³ above the Planckian locus. That spread is as wide as the differences between bodies, so a reference made from the matrix at one white would move every body of a model, the typical one included, and still not match Lightroom. Two sources remain:

- **Adobe's,** the references that reproduce DNG Converter's calibrations: RAWmakase's table (MIT, with attribution), or measured again with DNG Converter on the CC0 samples. They are numbers measured from DNG Converter's output on public files, as are the colour matrices Redlamp takes from LibRaw for every non-DNG raw ("All matrices are from Adobe DNG Converter unless otherwise noted", `src/tables/colordata.cpp`). Bodies of a model then agree with each other and with Lightroom.
- **Redlamp's own,** each model's typical body (the median preset of its public samples): bodies agree with each other but not with Lightroom, and a model with one sample is calibrated only relative to that body.

Which is acceptable under AGENTS.md's rule on Adobe's files, and under DEC-85, is the owner's decision.

## 7. What the grey card raws settle

Adobe's use of the presets, and RAWmakase's match with Camera Raw on two a7CR bodies, show that Lightroom renders this way; neither shows that a preset's difference between two bodies is their sensors' real difference, which is what makes one Temperature and Tint mean one neutral. One grey card in one light from two bodies of one model, rendered at one Temperature and Tint, gives the bodies' real difference beside their presets' (section 3), and the calibration's result, the two renders' difference with it applied.

**What to shoot.** Two or more bodies of one Sony model, from as many models as can be reached; an a7R V and an a7CR count as two bodies of one model, as they share a sensor, a matrix and a reference. For each pair: one grey card (an 18% grey card, a WhiBal or a ColorChecker's neutral patches) filling the middle of the frame, flat and evenly lit without glare; one steady light (overcast daylight through a window, or one lamp), the bodies shot one straight after the other from the same place; the same lens moved between them, at one focal length; manual exposure at ISO 100, f/5.6 to f/8, with the card at the middle of the histogram and nothing clipped; white balance set to Daylight with no fine-tuning (A-B and G-M at 0); uncompressed or lossless compressed raw at full size, not M or S; three frames each. A second light, a tungsten lamp, would also show whether one calibration holds across lights, as Adobe's model assumes.

## 8. Next

1. The owner's grey card raws, kept outside the repository unless they're his to publish under CC0, with the bodies called A and B here and their serials left in the files.
2. Their measurement: the bodies' rendered difference at one Temperature and Tint against their presets', and with the calibration applied.
3. If they confirm it, a design behind process 20, with its cost, for the owner to approve: the preset read in the decode, each model's reference, the calibration in `CameraColorModel` from that process, and what Auto, the eyedropper and As Shot's numbers do for edits made before it.
