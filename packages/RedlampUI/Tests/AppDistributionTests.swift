import Foundation
import Testing
@testable import RedlampUI

/// A bundle on disk whose Info.plist holds `info`, read as the app's own is.
private func bundle(_ info: [String: Any]) throws -> Bundle {
    let url = FileManager.default.temporaryDirectory.appending(path: "AppDistribution-\(UUID().uuidString).app")
    let contents = url.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
        fromPropertyList: info.merging(["CFBundleIdentifier": "app.redlamp.tests.\(UUID().uuidString)"]) { $1 },
        format: .xml, options: 0,
    )
    try plist.write(to: contents.appending(path: "Info.plist"))
    return try #require(Bundle(url: url))
}

struct AppDistributionTests {
    @Test(arguments: [
        ("app-store", AppDistribution.appStore),
        ("developer-id", .developerID),
        ("", .source),
    ])
    func `each build's Info.plist value names its distribution`(value: String, expected: AppDistribution) throws {
        #expect(try AppDistribution(bundle: bundle(["RedlampDistribution": value])) == expected)
    }

    @Test func `a bundle without the key, or with a value it doesn't know, is a build from source`() throws {
        #expect(try AppDistribution(bundle: bundle([:])) == .source)
        #expect(try AppDistribution(bundle: bundle(["RedlampDistribution": "testflight"])) == .source)
        #expect(try AppDistribution(bundle: bundle(["RedlampDistribution": "$(REDLAMP_DISTRIBUTION)"])) == .source)
        #expect(AppDistribution(value: true) == .source)
    }
}
