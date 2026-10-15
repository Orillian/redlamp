import Foundation
import RedlampEngineAPI
import Testing
@testable import RedlampRecipes

/// A catalog's photos' develop settings read and converted to their edits at size (EDT-23): a report of 100,000
/// edited photos has about 4.9 s, twice LIB-29's 2.45 s, and reading and converting each photo's settings is
/// the part edits add. The full size runs with `REDLAMP_LIGHTROOM_BENCH=1`
/// (`TEST_RUNNER_REDLAMP_LIGHTROOM_BENCH=1` through `xcodebuild`), `REDLAMP_LIGHTROOM_BENCH_PHOTOS` setting how
/// many; every run measures 5,000.
struct LightroomPhotoBenchTests {
    struct Measured {
        var read: Duration
        var readAndConverted: Duration
        var conversions: [LightroomImportReport.Conversion: Int]
    }

    static let photo = LightroomPhotoContext(size: PixelSize(width: 6000, height: 4000))

    /// The photos' settings read, then read and converted, on every core.
    static func measure(photos count: Int) async -> Measured {
        let texts = await CameraRawSettingsBenchTests.texts(count)
        let read = await CameraRawSettingsBenchTests.time(texts) { (try? CameraRawSettings(lua: $0))?.values.count }
        let parts = ProcessInfo.processInfo.activeProcessorCount * 4
        let clock = ContinuousClock()
        let started = clock.now
        let conversions = await withTaskGroup(of: [LightroomImportReport.Conversion: Int].self) { group in
            for part in 0 ..< parts {
                group.addTask {
                    var conversions: [LightroomImportReport.Conversion: Int] = [:]
                    for index in stride(from: part, to: texts.count, by: parts) {
                        guard let settings = try? CameraRawSettings(lua: texts[index]) else { continue }
                        let imported = LightroomPhoto.convert(
                            settings, photo: photo, source: .catalog(
                                URL(filePath: "/Catalog.lrcat"),
                                photo: nil,
                                digest: nil,
                            ),
                        )
                        conversions[imported.report.conversion, default: 0] += 1
                    }
                    return conversions
                }
            }
            return await group.reduce(into: [:]) { total, part in total.merge(part, uniquingKeysWith: +) }
        }
        let measured = Measured(read: read.read, readAndConverted: clock.now - started, conversions: conversions)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        print("LIGHTROOM-PHOTO-BENCH \(count) photos' develop settings read in \(measured.read), read and converted "
            + "in \(measured.readAndConverted) on \(cores) cores: \(conversions[.full] ?? 0) convert fully, "
            +
            "\(conversions[.approximated] ?? 0) with approximations, \(conversions[.leftOut] ?? 0) with settings left out")
        return measured
    }

    @Test(.measuresSpeed)
    func `5,000 photos' develop settings are read and converted in a fraction of a second`() async {
        let measured = await Self.measure(photos: 5000)
        #expect(measured.conversions.values.reduce(0, +) == 5000)
        #expect(measured.readAndConverted < .seconds(1))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH"] == "1"), .measuresSpeed)
    func `100,000 photos' develop settings are read and converted within half the report's budget`() async {
        let photos = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH_PHOTOS"].flatMap { Int($0) }
            ?? 100_000
        let measured = await Self.measure(photos: photos)
        #expect(measured.conversions.values.reduce(0, +) == photos)
        #expect(measured.readAndConverted < .milliseconds(2450))
    }
}
