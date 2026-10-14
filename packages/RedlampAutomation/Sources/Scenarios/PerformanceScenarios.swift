#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampDesign
    import RedlampDocument
    import RedlampEngineAPI
    @_spi(Harness) import RedlampUI

    extension RunningApp {
        /// Adds `value` for `metric` (an ID in docs/performance/metrics.json) to the run's metrics.json.
        func record(_ metric: String, _ value: Double) {
            let url = runDirectory.appending(path: "metrics.json")
            var metrics = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Double] ?? [:]
            metrics[metric] = value
            if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys, .prettyPrinted]) {
                try? data.write(to: url, options: .atomic)
            }
            recorder.write("metric", ["metric": metric, "value": value])
        }

        /// How long `body` takes, in milliseconds.
        func milliseconds(_ body: () throws -> Void) rethrows -> Double {
            let start = Date()
            try body()
            return Date().timeIntervalSince(start) * 1000
        }

        /// Drags Exposure at 120 events a second for `duration` seconds: the frames delivered a second, and the slowest
        /// 1% of the main thread's iterations, in milliseconds.
        func dragExposure(for duration: Double = 3) throws -> (fps: Double, p99: Double?) {
            let monitor = try MainThread.run { () -> MainThreadMonitorBox in
                let monitor = MainThreadMonitor()
                monitor.start()
                return MainThreadMonitorBox(monitor)
            }
            let before = try frames()
            try main { $0.beginEdit(.exposure) }
            let start = Date()
            var step = 0
            while Date().timeIntervalSince(start) < duration {
                let value = sin(Double(step) / 20) * 2
                post { $0.setSliderValue(.exposure, value) }
                step += 1
                pause(1.0 / 120)
            }
            try main { $0.endEdit(name: nil) }
            let seconds = Date().timeIntervalSince(start)
            let summary = try MainThread.run { () -> MainThreadMonitor.Summary? in
                monitor.monitor.stop()
                return monitor.monitor.summary()
            }
            let delivered = try frames() - before
            return (Double(delivered) / seconds, summary?.p99)
        }

        /// Scrolls the filmstrip shown from one end to the other and back, a step every 1/120 s for `duration`
        /// seconds (2.1 s goes there and back once): the slowest 1% of the main thread's iterations, in milliseconds.
        func scrollFilmstrip(for duration: Double = 3) throws -> Double? {
            let strip = try main { _ in
                Views.editorWindow.flatMap { FilmstripViews.strip(in: $0) }.map { FilmstripBox($0) }
            }
            guard let strip, try main({ _ in FilmstripViews.scrollWidth(strip.view) }) > 0 else {
                throw ScenarioFailure("The filmstrip shown doesn't scroll")
            }
            let (summary, _) = try watchingMainThread("filmstrip") {
                let start = Date()
                var step = 0
                while Date().timeIntervalSince(start) < duration {
                    let fraction = (1 - cos(Double(step) / 40)) / 2
                    post { _ in FilmstripViews.scroll(strip.view, to: fraction) }
                    step += 1
                    pause(1.0 / 120)
                }
            }
            return summary?.p99
        }
    }

    /// The strip a scroll steps through; only touched on main.
    private final class FilmstripBox: @unchecked Sendable {
        let view: NSView
        init(_ view: NSView) {
            self.view = view
        }
    }

    /// `Memory.footprint()` every 100 ms, beside what the scenario does, until `stop()`.
    private final class FootprintSamples: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Double] = []
        private let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))

        init() {
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let footprint = Memory.footprint()
                lock.withLock { samples.append(footprint) }
            }
            timer.schedule(deadline: .now(), repeating: .milliseconds(100))
            timer.resume()
        }

        /// Stops sampling: the most sampled, in megabytes.
        func stop() -> Double {
            timer.cancel()
            return lock.withLock { samples.max() ?? 0 }
        }
    }

    enum PerformanceScenarios {
        static let all: [Scenario] = [openAndSwitch, drag, export, palette, batchExport]

        static let openAndSwitch = Scenario(
            "performance.open", "Opening each raw from the filmstrip to its first frame, and memory after all of them",
            tiers: [.performance], claims: [.feature("performance.slow-editing")],
        ) { app in
            let raws = ["arw", "raf", "cr3", "nef", "dng"]
            try app.showRunPhotos()
            let names = try app.photoNames().filter { raws.contains(($0 as NSString).pathExtension.lowercased()) }
            try app.expect(!names.isEmpty, "The run's folder shows no raws")
            var times: [Double] = []
            for name in names + names {
                try app.open(names.first { $0 != name } ?? name)
                try times.append(app.milliseconds { try app.open(name) })
            }
            let sorted = times.sorted()
            app.record("e2e-open", sorted[sorted.count / 2])
            app.record("e2e-footprint", Memory.footprint())
            app.covered(.feature("performance.slow-editing"), via: .key)
        }

        static let drag = Scenario(
            "performance.drag", "Dragging Exposure at 120 events a second: the main thread and the frames",
            tiers: [.performance], claims: [],
        ) { app in
            try app.openWorking()
            try app.main { $0.expandedPanels = Set(PanelID.allCases) }
            app.pause(0.5)
            let drag = try app.dragExposure()
            app.record("e2e-drag-fps", drag.fps)
            if let p99 = drag.p99 {
                app.record("e2e-drag-p99", p99)
            }
            try app.choose(.resetAll)
        }

        /// EDT-16 (#78): a batch export renders in an engine of its own, one photo at a time, and mustn't slow
        /// Develop's frames or the filmstrip. Each is measured before the batch and while it runs, every photo
        /// selected both times, and memory from before the batch to its end.
        static let batchExport = Scenario(
            "performance.batch-export",
            "Dragging Exposure and scrolling the filmstrip before and while every photo exports, and memory meanwhile",
            tiers: [.performance], claims: [],
        ) { app in
            try app.openWorking()
            // Each raw four more times, so the batch outlasts both measurements made while it runs.
            let shown = try app.main { $0.items.count }
            let raws = try FileManager.default.contentsOfDirectory(atPath: app.photos.path)
                .filter { ["arw", "raf", "cr3", "nef", "dng"].contains(($0 as NSString).pathExtension.lowercased()) }
                .sorted()
            var copies: [URL] = []
            defer {
                for copy in copies {
                    try? FileManager.default.removeItem(at: copy)
                }
                try? app.main { $0.open([app.photos]) }
                try? app.wait("the copies gone from the filmstrip", timeout: 60) { $0.items.count == shown }
                try? app.openWorking()
            }
            for number in 2 ... 5 {
                for raw in raws {
                    let name = raw as NSString
                    let copy = app.photos
                        .appending(path: "\(name.deletingPathExtension) \(number).\(name.pathExtension)")
                    try RenamePerformanceScratch.clone(app.photos.appending(path: raw), to: copy, ending: copies.count)
                    copies.append(copy)
                }
            }
            let total = shown + copies.count
            try app.main { $0.open([app.photos]) }
            try app.wait("the \(copies.count) copies in the filmstrip", timeout: 60) { $0.items.count == total }
            try app.openWorking()
            try app.settle()
            try app.main { model in
                model.expandedPanels = Set(PanelID.allCases)
                model.keepsFilmstripShown = true
            }
            defer { try? app.main { $0.keepsFilmstripShown = false } }
            try app.choose(Menus.title(of: .selectAllPhotos))
            try app.wait("several photos selected", timeout: 30) { $0.selectedCount > 1 && $0.info != nil }
            app.pause(0.5)
            // The first drag and scroll after opening pay once for what the ones during the batch find made.
            _ = try app.dragExposure(for: 1)
            _ = try app.scrollFilmstrip(for: 2.1)
            app.pause(0.5)
            let idle = try app.dragExposure()
            let idleStrip = try app.scrollFilmstrip()

            let count = try app.main { $0.selectedCount }
            let settings = try app.host.map { host in try app.main { _ in host.exports.initialSettings } }
                ?? ExportSettings()
            let folder = settings.destinationFolder ?? app.photos
            let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            @Sendable func written() -> Set<String> {
                Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).subtracting(before)
                    .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".redlamp") }
            }
            defer {
                for file in written() {
                    try? FileManager.default.removeItem(at: folder.appending(path: file))
                }
            }
            let footprint = Memory.footprint()
            let samples = FootprintSamples()
            try app.choose(Menus.title(of: .export))
            try app.waitForSheet("the Export dialog for \(count) photos")
            app.pause(0.5)
            try app.expect(
                try app.pressInSheet(KeyCombo(.character("\r"))),
                "The Export dialog's Export button didn't take Return",
            )
            try app.waitForNoSheet("the Export dialog")
            try app.wait("the batch to start") { $0.batchExport.progress != nil }
            let started = Date()
            let busy = try app.dragExposure()
            let afterDrag = try app.main { $0.batchExport.progress }
            let busyStrip = try app.scrollFilmstrip()
            let afterStrip = try app.main { $0.batchExport.progress }
            try app.wait("the \(count) exports", timeout: 300) { model in
                model.batchExport.progress == nil && written().count >= count
            }
            let peak = samples.stop()
            app.recorder.write("note", [
                "batchPhotos": count, "batchSeconds": Date().timeIntervalSince(started),
                "doneAfterDrag": afterDrag?.done ?? count, "doneAfterScroll": afterStrip?.done ?? count,
            ])

            app.record("e2e-batch-idle-drag-fps", idle.fps)
            app.record("e2e-batch-drag-fps", busy.fps)
            if let p99 = idle.p99 {
                app.record("e2e-batch-idle-drag-p99", p99)
            }
            if let p99 = busy.p99 {
                app.record("e2e-batch-drag-p99", p99)
            }
            if let p99 = idleStrip {
                app.record("e2e-batch-idle-strip-p99", p99)
            }
            if let p99 = busyStrip {
                app.record("e2e-batch-strip-p99", p99)
            }
            app.record("e2e-batch-footprint", peak)
            app.record("e2e-batch-footprint-rise", peak - footprint)
            try app.expect(afterDrag != nil, "The batch of \(count) photos finished before the drag did")
            try app.expect(
                afterStrip != nil,
                "The batch of \(count) photos finished before the filmstrip's scroll did, "
                    + "\(afterDrag?.done ?? 0) of them done when the drag ended",
            )
            try app.choose(.resetAll)
        }

        static let export = Scenario(
            "performance.export", "Exporting a full-size JPEG",
            tiers: [.performance], claims: [],
        ) { app in
            try app.openWorking()
            var settings = ExportSettings()
            settings.revealInFinder = false
            _ = try app.export(settings, as: "warm-up")
            let time = try app.milliseconds { _ = try app.export(settings, as: "full-size") }
            app.record("e2e-export", time)
        }

        static let palette = Scenario(
            "performance.palette", "⌘K to the command palette, and photo to photo",
            tiers: [.performance], claims: [],
        ) { app in
            try app.openWorking()
            var times: [Double] = []
            for _ in 0 ..< 5 {
                try times.append(app.milliseconds {
                    try app.press(.commandPalette)
                    try app.wait("the palette") { $0.commandPalette != nil }
                })
                try app.press(KeyCombo(.escape))
                try app.wait("the palette to close") { $0.commandPalette == nil }
            }
            app.record("e2e-palette", times.sorted()[times.count / 2])
        }
    }
#endif
