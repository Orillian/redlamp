import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampServices

/// The stops a raw was underexposed by for a setting its camera's JPEG brightens back (CAM-35):
/// a Fujifilm RAF's D-Range, from its maker note, or from its raw exposure bias where the maker
/// note has none.
struct ExposureShiftTests {
    /// The samples' shifts, as `tests/fixtures` holds them; nil where the file states none.
    static let expected: [String: Double?] = [
        // DR100, set by hand.
        "AFXT2720.RAF": 0, "Fujifilm_X-T5.RAF": 0,
        // DR200, chosen by the camera's Auto D-Range.
        "Fujifilm_GFX100-II.RAF": 1,
        // No D-Range in the maker note: the raw exposure bias, -1.72, is a stop below DR100's -0.72.
        "Fujifilm_X-E5.RAF": 1,
        "_DSC0009.ARW": nil, "IMG_1361.DNG": nil, "DSC_0750.NEF": nil,
    ]

    static let samples = (DecodeRegressionTests.fixtures + DecodeRegressionTests.cameras)
        .filter { expected[$0.lastPathComponent] != nil }

    @Test(.enabled(if: !samples.isEmpty), arguments: samples)
    func `each sample's shift`(url: URL) throws {
        let info = try ImageDecoder.decode(url).info
        #expect(info.exposureShift == Self.expected[url.lastPathComponent] ?? nil)
    }
}
