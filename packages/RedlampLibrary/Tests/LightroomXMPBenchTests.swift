import Foundation
import RedlampDocument
import RedlampEngineAPI
import RedlampRecipes
import Testing
import UniformTypeIdentifiers
@testable import RedlampLibrary

/// Convert Lightroom Edits… at a library's scale, with `REDLAMP_LIGHTROOM_XMP_BENCH=1` (which xcodebuild hands to
/// the tests from `TEST_RUNNER_REDLAMP_LIGHTROOM_XMP_BENCH=1`): `REDLAMP_LIGHTROOM_XMP_BENCH_PHOTOS` photos (10,000),
/// half JPEGs holding their develop settings in their own XMP and half raws, clones of a fixture raw on its own
/// volume, with an `.xmp` beside each. It times the scan behind the report on every core, and the sidecars written
/// one after another as the batch writes them.
struct LightroomXMPBenchTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_XMP_BENCH"] == "1"))
    func `Convert Lightroom Edits on ten thousand photos`() throws {
        let count = ProcessInfo.processInfo.environment["REDLAMP_LIGHTROOM_XMP_BENCH_PHOTOS"]
            .flatMap { Int($0) } ?? 10000
        let raw = try #require(
            try FileManager.default.contentsOfDirectory(at: FixtureTests.rawFolder, includingPropertiesForKeys: nil)
                .filter { LightroomPhotoXMP.isCameraRaw($0) && LightroomPhotoXMP.context(of: $0) != nil }
                .min { $0.lastPathComponent < $1.lastPathComponent },
            "a raw ImageIO reads in tests/fixtures/raw",
        )
        let folder = FixtureTests.rawFolder.deletingLastPathComponent()
            .appending(path: "lightroom-xmp-bench-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let template = folder.appending(path: "template.jpg")
        try LightroomXMPFixture.image(template, type: .jpeg, xmp: LightroomXMPFixture.packet(rawFileName: nil))
        let jpeg = try Data(contentsOf: template)
        try FileManager.default.removeItem(at: template)
        let sidecar = Data(LightroomXMPFixture.packet(rawFileName: nil, masks: false).utf8)
        var photos: [URL] = []
        for index in 0 ..< count {
            let name = String(format: "IMG_%05d", index)
            if index.isMultiple(of: 2) {
                let photo = folder.appending(path: "\(name).jpg")
                try jpeg.write(to: photo)
                photos.append(photo)
            } else {
                let photo = folder.appending(path: "\(name).\(raw.pathExtension)")
                try FileManager.default.copyItem(at: raw, to: photo)
                try sidecar.write(to: folder.appending(path: "\(name).xmp"))
                photos.append(photo)
            }
        }

        let store = SidecarStore()
        let scanStart = ContinuousClock.now
        let scan = LightroomXMPScan.scan(photos) { LightroomPhotoXMP.redlampEdit(of: $0, in: store) }
        let scanned = ContinuousClock.now - scanStart
        #expect(scan.conversions.count == count && scan.found == count)

        let writeStart = ContinuousClock.now
        for conversion in scan.conversions {
            let recipe = conversion.imported.recipe
            var written = Sidecar(recipe: recipe)
            written.session = HistorySession(steps: [
                HistoryStep(action: .open, title: "Import", recipe: EditRecipe()),
                HistoryStep(action: .recipe, title: "Convert Lightroom Edits", recipe: recipe),
            ])
            _ = try store.loadThrowing(for: conversion.photo)
            try store.save(written, for: conversion.photo)
        }
        let wrote = ContinuousClock.now - writeStart
        #expect(store.load(for: photos[1])?.recipe.provenance?.source == .xmpSidecar)

        func seconds(_ duration: Duration) -> String {
            String(
                format: "%.2f s",
                Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18,
            )
        }
        let cores = ProcessInfo.processInfo.activeProcessorCount
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        print("LIGHTROOM-XMP-BENCH \(count) photos (\(count / 2) JPEGs, \(count / 2) \(raw.pathExtension) with .xmp)")
        print("LIGHTROOM-XMP-BENCH report (read, convert, check each sidecar) on \(cores) cores: \(seconds(scanned))")
        print("LIGHTROOM-XMP-BENCH sidecars written one after another: \(seconds(wrote))")
        print("LIGHTROOM-XMP-BENCH load average \(String(format: "%.1f %.1f %.1f", load[0], load[1], load[2]))")
    }
}
