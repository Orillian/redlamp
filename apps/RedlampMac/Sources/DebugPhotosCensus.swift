#if DEBUG || REDLAMP_PROFILING
    import AppKit
    import RedlampLibrary
    import RedlampUI
    import Synchronization

    /// `--photos-census <step>`: the census of this Mac's Photos library (LIB-57) in place of the editor, which
    /// `scripts/photos-census-kit.sh` makes a kit of for the Mac whose library it measures. It opens no library and no
    /// window, so a Redlamp installed there is left alone: it says what it does on standard output and in
    /// `census.log`, writes the report beside it, and quits. The step is `measure`, `recovered`, `offline` or `week`
    /// (`PhotoKitCensus.Step`). `--photos-census-folder <path>` keeps the report and the state elsewhere than
    /// `~/Library/Application Support/Redlamp Photos Census`, `--photos-census-simulated <manifest>` reads a simulated
    /// library in place of Photos, for a dry run, and `--photos-census-sample <n>` samples fewer photos.
    @MainActor
    enum DebugPhotosCensus {
        static func isRequested(_ arguments: [String]) -> Bool {
            arguments.contains("--photos-census")
        }

        /// Runs the census as an app of its own, so Photos asks for its access as it would for Redlamp, then exits.
        static func run(arguments: [String]) -> Never {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = Delegate(arguments: arguments)
            app.delegate = delegate
            withExtendedLifetime(delegate) {
                app.run()
            }
            exit(0)
        }

        private final class Delegate: NSObject, NSApplicationDelegate {
            let arguments: [String]

            init(arguments: [String]) {
                self.arguments = arguments
            }

            func applicationDidFinishLaunching(_: Notification) {
                NSApp.activate()
                // App Nap would slow the census's timers and requests while no window shows.
                let activity = ProcessInfo.processInfo.beginActivity(
                    options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
                    reason: "Measuring this Mac's Photos library",
                )
                let arguments = arguments
                Task {
                    let status = await DebugPhotosCensus.census(arguments)
                    ProcessInfo.processInfo.endActivity(activity)
                    exit(status)
                }
            }
        }

        static let standardFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Redlamp Photos Census", directoryHint: .isDirectory)

        static func census(_ arguments: [String]) async -> Int32 {
            func value(after flag: String) -> String? {
                guard let at = arguments.firstIndex(of: flag), at + 1 < arguments.count,
                      !arguments[at + 1].hasPrefix("--") else { return nil }
                return arguments[at + 1]
            }
            let folder = value(after: "--photos-census-folder")
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ??
                standardFolder
            let log = Log(folder.appending(path: "census.log"))
            var step = PhotoKitCensus.Step.measure
            if let named = value(after: "--photos-census") {
                guard let found = PhotoKitCensus.Step(rawValue: named) else {
                    log.say("There's no census step \(named): it's measure, recovered, offline or week.")
                    return 2
                }
                step = found
            }
            var plan = PhotoKitCensus.Plan()
            if let sample = value(after: "--photos-census-sample").flatMap(Int.init) {
                plan.sample = sample
            }
            let census: PhotoKitCensus
            if let manifest = value(after: "--photos-census-simulated") {
                do {
                    let library = try SimulatedPhotosLibrary(manifest: URL(fileURLWithPath: manifest))
                    census = PhotoKitCensus(
                        photos: library, images: library, probe: library, network: SystemNetwork.shared,
                        folder: folder, say: log.say,
                    )
                } catch {
                    log.say("The simulated library can't be read: \(error)")
                    return 2
                }
            } else {
                census = PhotoKitCensus(
                    photos: PhotoKitLibrary(), images: PhotoKitCensusPhotos.images, probe: PhotoKitCensusPhotos.probe,
                    network: SystemNetwork.shared, folder: folder, say: log.say,
                )
            }
            log.say("Redlamp's census of this Mac's Photos library, its \(step.rawValue) step.")
            do {
                let report = try await census.run(step, plan: plan)
                report.lines().forEach(log.say)
                log.say("Done. The report is \(census.reportURL.path), and as text \(census.textURL.path).")
                return 0
            } catch let error as PhotoKitCensus.NotMeasured {
                log.say("The \(step.rawValue) step can't run: \(error)")
                return 1
            } catch {
                log.say("The \(step.rawValue) step failed: \(PhotoKitCensus.name(of: error))")
                return 1
            }
        }

        /// What the census says, on standard output and appended to its log, each line with its time.
        final class Log: Sendable {
            private let url: URL
            private let writing = Mutex(())

            init(_ url: URL) {
                self.url = url
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                )
            }

            func say(_ line: String) {
                let stamped = "\(Date.now.ISO8601Format()) \(line)\n"
                writing.withLock { _ in
                    FileHandle.standardOutput.write(Data(stamped.utf8))
                    if let handle = FileHandle(forWritingAtPath: url.path) {
                        handle.seekToEndOfFile()
                        handle.write(Data(stamped.utf8))
                        try? handle.close()
                    } else {
                        try? Data(stamped.utf8).write(to: url)
                    }
                }
            }
        }
    }
#endif
