import Foundation
import RedlampEngineAPI

/// A photo's develop settings from Lightroom, read from its catalog's Lua or the photo's XMP
/// (`CameraRawSettings`), converted to the photo's whole edit (EDT-23, EDT-12), masks and spots aside. Every
/// global setting goes through EDT-11's table (`LightroomPreset.rules`), as a preset's does, so a conversion
/// fitted there reaches presets, sidecars and catalogs alike; what a photo's edit holds and a recipe doesn't
/// (the profile, crop, lens and Transform corrections, calibration) is carried as the Lightroom edits design
/// (`docs/plans/2026-10-13-lightroom-edits-design.md`) maps it. What only files Lightroom made can settle is
/// left out and reported as not yet checked.
public enum LightroomPhoto {
    /// `settings` as the photo's edit, at the current process version, with the report of how each setting was
    /// carried over and the provenance the edit is to record.
    public static func convert(
        _ settings: CameraRawSettings,
        photo: LightroomPhotoContext,
        source: LightroomProvenance.Source,
        date: Date = Date(),
    ) -> LightroomPhotoImport {
        let converter = LightroomConverter(settings, photo: photo)
        let edit = LightroomPhotoImport.Edit(
            values: converter.values, treatment: converter.treatment ?? .color,
            baseLook: converter.baseLook ?? BuiltInBaseLook.color.reference,
            whiteBalanceMode: converter.whiteBalanceMode ?? .asShot,
            pointCurve: converter.pointCurve ?? EditRecipe.linearPointCurve, channelCurves: converter.channelCurves,
            crop: converter.crop, orientation: photo.orientation ?? .identity,
        )
        let report = LightroomImportReport(
            processVersion: settings.text("ProcessVersion"), entries: converter.entries, profile: converter.profile,
        )
        let provenance = LightroomProvenance(
            source: source, date: date, approximated: report.entries(.approximated).map(\.setting),
            leftOut: report.entries(.ignored).map(\.setting),
        )
        return LightroomPhotoImport(report: report, provenance: provenance, edit: edit)
    }

    /// The Lightroom process a photo's `crs:ProcessVersion` names: Process 2003, Process 2010, or Process 2012
    /// for 2012 and every version since.
    public static func processName(_ version: String?) -> String {
        Process(version).name
    }

    /// Whether `version` is Process 2003's or 2010's, whose tone waits on EDT-31.
    public static func isEarlierProcess(_ version: String?) -> Bool {
        Process(version).isEarlier
    }

    /// Whether `settings` hold a photo's edit: develop settings that aren't a preset's, and which Lightroom
    /// doesn't mark as unset (`crs:HasSettings`), as a photo's XMP can hold only its metadata.
    public static func holdsEdit(_ settings: CameraRawSettings) -> Bool {
        !settings.isPreset && settings.flag("HasSettings") != false
            && LightroomPreset.orderedSettings(settings).contains { $0.rule?.isMetadata != true }
    }
}

/// What converting a photo's settings needs to know of the photo, which the library's index or a read of its
/// metadata gives without decoding it.
public struct LightroomPhotoContext: Sendable, Hashable {
    /// The photo's size in pixels as its file stores it, before the camera's orientation.
    public var size: PixelSize
    /// The camera's orientation, as `LightroomCrop.redlampCrop` takes it.
    public var cameraOrientation: ImageOrientation
    /// A raw, whose white balance is Temperature and Tint, rather than a rendered photo (JPEG, TIFF, HEIC),
    /// whose white balance Lightroom shifts from the file's (`IncrementalTemperature`).
    public var isRaw: Bool
    /// The rotation and flip the catalog gives the photo after the camera's orientation, as the edit holds it
    /// (`EditRecipe.orientation`); nil while Lightroom's codes aren't known, which a census of a real catalog
    /// settles.
    public var orientation: ImageOrientation?
    /// Lightroom's own code for the photo's rotation (`Adobe_images.orientation`), reported as not yet checked
    /// while `orientation` is nil.
    public var orientationCode: String?
    /// The photo's size as the catalog records it (`Adobe_images.fileWidth` and `fileHeight`), which
    /// Lightroom's crop is a fraction of; nil for a sidecar.
    public var catalogSize: PixelSize?
    /// Whether the file carries a lens correction Redlamp applies (`ImageInfo.lensCorrection`).
    public var hasLensCorrection: Bool
    /// The Base Look made from the camera profile the file embeds (TON-09), when it embeds one.
    public var embeddedLook: BaseLookReference?
    /// The looks that fill film slots on this Mac in place of Redlamp's (`RecipeLibrary.filledSlots`), which
    /// Fujifilm's film simulations take first.
    public var slotLooks: [FilmSlot: BaseLookReference]
    /// The photographer's Adobe camera profiles on this Mac that can render the photo (TON-51, TON-52), as
    /// `EditingEngine.cameraProfileLooks(make:model:)` lists them for its camera. A raw's edit names the one
    /// Lightroom used, and where it isn't among them, Redlamp's look of the same name stands in; the report
    /// says which (EDT-33). Nil where the caller doesn't say, which takes Redlamp's looks without the report
    /// saying whether the profiles are on this Mac.
    public var adobeProfiles: [CameraProfileLook]?

    public init(
        size: PixelSize,
        cameraOrientation: ImageOrientation = .identity,
        isRaw: Bool = true,
        orientation: ImageOrientation? = nil,
        orientationCode: String? = nil,
        catalogSize: PixelSize? = nil,
        hasLensCorrection: Bool = false,
        embeddedLook: BaseLookReference? = nil,
        slotLooks: [FilmSlot: BaseLookReference] = [:],
        adobeProfiles: [CameraProfileLook]? = nil,
    ) {
        self.size = size
        self.cameraOrientation = cameraOrientation
        self.isRaw = isRaw
        self.orientation = orientation
        self.orientationCode = orientationCode
        self.catalogSize = catalogSize
        self.hasLensCorrection = hasLensCorrection
        self.embeddedLook = embeddedLook
        self.slotLooks = slotLooks
        self.adobeProfiles = adobeProfiles
    }
}

/// A photo's develop settings converted: how each setting was carried over, where they came from, and the edit.
public struct LightroomPhotoImport: Sendable {
    public var report: LightroomImportReport
    public var provenance: LightroomProvenance
    let edit: Edit

    /// The photo's edit, at the current process version, with its provenance. It's made each time it's read,
    /// which takes longer than converting the settings, so a report of many photos needn't make their edits.
    public var recipe: EditRecipe {
        var recipe = edit.recipe
        recipe.provenance = provenance.recorded
        return recipe
    }

    /// What the edit is made of.
    struct Edit: Sendable {
        var values: [ParameterID: Double]
        var treatment: Treatment
        var baseLook: BaseLookReference
        var whiteBalanceMode: WhiteBalanceMode
        var pointCurve: [CurvePoint]
        var channelCurves: [CurveChannel: [CurvePoint]]
        var crop: (rect: CropRect, angle: Double)?
        var orientation: ImageOrientation

        var recipe: EditRecipe {
            var recipe = EditRecipe()
            recipe.treatment = treatment
            recipe.baseLook = baseLook
            recipe.whiteBalanceMode = whiteBalanceMode
            recipe.pointCurve = pointCurve
            for channel in CurveChannel.colors {
                recipe[curve: channel] = channelCurves[channel] ?? EditRecipe.linearPointCurve
            }
            for (parameter, value) in values {
                recipe[parameter] = value
            }
            if let crop {
                recipe.crop = crop.rect
                recipe[.cropAngle] = crop.angle
            }
            recipe.orientation = orientation
            return recipe
        }
    }
}

/// Where a photo's converted edit came from (EDT-23), which its recipe records (`recorded`).
public struct LightroomProvenance: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// A Lightroom Classic catalog, with Lightroom's photo or virtual copy in it (`Adobe_images.id_local`)
        /// and its settings' digest (`Adobe_imageDevelopSettings.digest`), when the caller has them.
        case catalog(URL, photo: Int64?, digest: String?)
        /// An XMP sidecar beside the photo (`IMG_1234.xmp`).
        case sidecar(URL)
        /// XMP inside the photo's own file (a DNG, JPEG, TIFF or HEIC).
        case embedded(URL)
    }

    public var source: Source
    /// When the settings were converted.
    public var date: Date
    /// The settings approximated and those left out, by name, in the report's order.
    public var approximated: [String]
    public var leftOut: [String]

    public init(source: Source, date: Date, approximated: [String] = [], leftOut: [String] = []) {
        self.source = source
        self.date = date
        self.approximated = approximated
        self.leftOut = leftOut
    }

    /// As the recipe records it (`EditRecipe.provenance`).
    public var recorded: EditProvenance {
        switch source {
        case let .catalog(url, photo, digest):
            EditProvenance(
                source: .lightroomCatalog, path: url.path, photo: photo, digest: digest, date: date,
                approximated: approximated, leftOut: leftOut,
            )
        case let .sidecar(url):
            EditProvenance(
                source: .xmpSidecar, path: url.path, date: date, approximated: approximated, leftOut: leftOut,
            )
        case let .embedded(url):
            EditProvenance(
                source: .embeddedXMP, path: url.path, date: date, approximated: approximated, leftOut: leftOut,
            )
        }
    }
}
