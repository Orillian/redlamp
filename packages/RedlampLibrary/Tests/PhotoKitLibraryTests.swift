import Foundation
import Photos
import Testing
@testable import RedlampLibrary

/// What of `PhotoKitLibrary` runs without access to Photos (LIB-54, LIB-58).
struct PhotoKitLibraryTests {
    @Test func `a cloud identifier is recorded through archivalStringValue, which this macOS has`() {
        let string = "7B1F0C7E-2A4D-4F1B-9C55-1D2E3F405060:001:AbCdEfGhIjKlMnOpQrStUvWxYz01"
        let cloud = PHCloudIdentifier(stringValue: string)
        #expect(cloud.responds(to: NSSelectorFromString("archivalStringValue")))
        #expect(PhotoKitLibrary.archivalString(of: cloud) == string)
    }
}
