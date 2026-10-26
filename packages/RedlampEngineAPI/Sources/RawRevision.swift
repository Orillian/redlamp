/// How the raw stages, from normalisation to the demosaic, develop a photo (`docs/raw-pipeline.md`).
///
/// A photo's pyramid is built when it opens, from the decoded file alone, before any edit is known.
/// So a raw-stage change that would render an existing edit differently adds a revision, the
/// process version it ships in maps to it, and an older edit renders from the photo built again at
/// its own revision.
public enum RawRevision: Int, Sendable, Hashable, Comparable {
    /// Processes 1 to 14.
    case first = 1
    /// Process 15: clipped highlights keep the colour of what's around them (CAM-31), as they do
    /// in every later revision.
    case second
    /// Processes 16 and 17: values below black are kept through the demosaic, for noise reduction
    /// to average, and clamped after it (DN-12), as they are in every later revision.
    case third
    /// Process 18 on: a linear raw the camera white-balanced (`DecodedImage.balancedInCamera`) is
    /// balanced once, as shot, and its noise measured before that balance (#480).
    case fourth

    public init(processVersion: Int) {
        self = switch processVersion {
        case 18...: .fourth
        case 16...: .third
        case 15: .second
        default: .first
        }
    }

    /// Whether the raw stages keep values below black, to be clamped after the detail stage.
    public var keepsBelowBlack: Bool {
        self >= .third
    }

    /// Whether a linear raw the camera white-balanced keeps that balance. Before, it was balanced
    /// again, which turned Sony's YCbCr ARWs and Nikon's sRAW NEFs pink.
    public var keepsCameraBalance: Bool {
        self >= .fourth
    }

    /// New edits'.
    public static let current = RawRevision(processVersion: EditRecipe.currentProcessVersion)

    public static func < (lhs: RawRevision, rhs: RawRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public extension EditRecipe {
    /// The raw revision the edit renders with.
    var rawRevision: RawRevision {
        RawRevision(processVersion: processVersion)
    }
}
