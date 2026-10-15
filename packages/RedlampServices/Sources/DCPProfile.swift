import Foundation

/// A `.dcp` camera profile file (DNG specification, "Camera Profiles"): one camera model's
/// matrices, as `DNGColorCalibration` reads them, and the tables and curve `DNGProfile` reads, as
/// Camera Raw installs Adobe Standard and the Camera Matching profiles (TON-51). Read from the
/// photographer's own files, never shipped (DEC-85).
public struct DCPProfile: Sendable, Hashable {
    public var name: String
    /// UniqueCameraModel: the camera it was made for, as Adobe names it (`Canon EOS R5`).
    public var cameraModel: String
    /// ProfileEmbedPolicy: 0 allow copying, 1 embed if used, 2 never embed, 3 no restrictions.
    public var embedPolicy: Int?
    public var copyright: String?
    public var color: DNGColorCalibration
    /// The HueSatMaps, LookTable, tone curve and BaselineExposureOffset; empty for a profile of
    /// matrices alone.
    public var profile: DNGProfile

    public init(
        name: String, cameraModel: String, embedPolicy: Int?, copyright: String?, color: DNGColorCalibration,
        profile: DNGProfile,
    ) {
        self.name = name
        self.cameraModel = cameraModel
        self.embedPolicy = embedPolicy
        self.copyright = copyright
        self.color = color
        self.profile = profile
    }

    /// Larger files aren't camera profiles.
    public static let largestFile = 16 << 20

    /// Nil unless the data is a camera profile with a name, a camera model and its matrices, and
    /// tables of the sizes the specification allows.
    public init?(data: Data) {
        let url = URL(fileURLWithPath: "/profile.dcp")
        guard data.count <= Self.largestFile, let color = DNGColorCalibration.read(data, url: url), color.isValid,
              let profile = DNGProfile.read(data, url: url, keepingEmpty: true), profile.isValid,
              profile.hueSatMaps.count <= color.calibrations.count,
              let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let camera = profile.cameraModel?.trimmingCharacters(in: .whitespacesAndNewlines), !camera.isEmpty
        else { return nil }
        self.init(
            name: name, cameraModel: camera, embedPolicy: profile.embedPolicy, copyright: profile.copyright,
            color: color, profile: profile,
        )
    }

    /// 16 hex digits of a SHA-256 over what renders (the matrices, tables, curve and offset; not
    /// the names), so the same profile is one profile wherever its file is.
    public var identity: String {
        struct Rendering: Encodable {
            var calibrations: [DNGColorCalibration.Calibration]
            var hueSatMaps: [DNGProfile.HSVMap]
            var lookTable: DNGProfile.HSVMap?
            var toneCurve: [SIMD2<Float>]?
            var baselineExposureOffset: Double
        }
        return AdobeLook.digest(Rendering(
            calibrations: color.calibrations, hueSatMaps: profile.hueSatMaps, lookTable: profile.lookTable,
            toneCurve: profile.toneCurve, baselineExposureOffset: profile.baselineExposureOffset,
        ))
    }

    /// Whether it was made for this camera: its UniqueCameraModel names the photo's make and model,
    /// once case, spaces and the make set aside, as lens profiles compare them (LNS-04).
    public func matchesCamera(make: String?, model: String?) -> Bool {
        Self.names(cameraModel, camera: make, model)
    }

    /// Whether Adobe's name for a camera (`Canon EOS R5`, a folder's or a file's) is the photo's.
    /// The make is compared by its first word and whole (`OM Digital Solutions`).
    public static func names(_ adobeName: String, camera make: String?, _ model: String?) -> Bool {
        guard let make, let model else { return false }
        let theirs = LCPProfile.SubProfile.key(adobeName)
        let makes = [LCPProfile.SubProfile.makeKey(make), LCPProfile.SubProfile.key(make)].filter { !$0.isEmpty }
        let wanted = makes.map { LCPProfile.SubProfile.key(model, dropping: [$0]) }
        return makes.contains { make in
            theirs.hasPrefix(make) && wanted.contains(LCPProfile.SubProfile.key(adobeName, dropping: [make]))
        }
    }
}
