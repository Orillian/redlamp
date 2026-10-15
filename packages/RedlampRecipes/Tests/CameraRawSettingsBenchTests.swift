import Foundation
import Testing
@testable import RedlampRecipes

/// A catalog's develop settings read at size (EDT-23): a report of 100,000 edited photos has about 4.9 s, twice
/// LIB-29's 2.45 s, and reading each photo's settings is part of it. The full size runs with
/// `REDLAMP_LIGHTROOM_BENCH=1` (`TEST_RUNNER_REDLAMP_LIGHTROOM_BENCH=1` through `xcodebuild`),
/// `REDLAMP_LIGHTROOM_BENCH_PHOTOS` setting how many; every run measures 5,000.
struct CameraRawSettingsBenchTests {
    /// Each photo's settings as the catalog keeps them: a fifth with a mask, a tenth with spots and a tenth
    /// with Guided Upright.
    static func texts(_ count: Int) async -> [String] {
        let parts = ProcessInfo.processInfo.activeProcessorCount * 4
        return await withTaskGroup(of: (Int, [String]).self) { group in
            for part in 0 ..< parts {
                group.addTask {
                    let photos = count * part / parts ..< count * (part + 1) / parts
                    return (part, photos.map { photo in
                        DevelopSettings.lua(DevelopSettings.photo(
                            photo, masks: photo % 5 == 0 ? 1 : 0, spots: photo % 10 == 0, upright: photo % 10 == 3,
                        ))
                    })
                }
            }
            var texts = [[String]](repeating: [], count: parts)
            for await (part, photos) in group {
                texts[part] = photos
            }
            return texts.flatMap(\.self)
        }
    }

    struct Measured {
        var read: Duration
        var settings: Int
        var failures: Int
    }

    /// `read` over `texts` on every core: how long it took, how many settings it found and how many texts it
    /// couldn't read.
    static func time(_ texts: [String], _ read: @escaping @Sendable (String) -> Int?) async -> Measured {
        let parts = ProcessInfo.processInfo.activeProcessorCount * 4
        let clock = ContinuousClock()
        let started = clock.now
        let (settings, failures) = await withTaskGroup(of: (Int, Int).self) { group in
            for part in 0 ..< parts {
                group.addTask {
                    var settings = 0
                    var failures = 0
                    for index in stride(from: part, to: texts.count, by: parts) {
                        if let count = read(texts[index]) {
                            settings += count
                        } else {
                            failures += 1
                        }
                    }
                    return (settings, failures)
                }
            }
            return await group.reduce((0, 0)) { ($0.0 + $1.0, $0.1 + $1.1) }
        }
        return Measured(read: clock.now - started, settings: settings, failures: failures)
    }

    /// The photos' settings read on every core, as Camera Raw settings and, for comparison, as Lua tables only.
    static func measure(photos count: Int) async -> Measured {
        let texts = await texts(count)
        let tables = await time(texts) { (try? LuaTable(parsing: $0))?.fields.count }
        let measured = await time(texts) { (try? CameraRawSettings(lua: $0))?.values.count }
        let sizes = texts.map(\.utf8.count)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        print("CAMERA-RAW-BENCH \(count) photos' develop settings, \(sizes.min() ?? 0) to \(sizes.max() ?? 0) bytes "
            + "(\(sizes.reduce(0, +) / max(count, 1)) on average): read in \(measured.read) on \(cores) cores "
            + "(\(measured.read * cores / max(count, 1)) a photo on one core), Lua tables alone in \(tables.read)")
        return measured
    }

    @Test(.measuresSpeed)
    func `5,000 photos' develop settings are read in a fraction of a second`() async {
        let measured = await Self.measure(photos: 5000)
        #expect(measured.failures == 0 && measured.settings >= 5000 * 140)
        #expect(measured.read < .milliseconds(500))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH"] == "1"), .measuresSpeed)
    func `100,000 photos' develop settings are read within half the report's budget`() async {
        let photos = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_BENCH_PHOTOS"].flatMap { Int($0) }
            ?? 100_000
        let measured = await Self.measure(photos: photos)
        #expect(measured.failures == 0 && measured.settings >= photos * 140)
        #expect(measured.read < .milliseconds(2450))
    }
}
