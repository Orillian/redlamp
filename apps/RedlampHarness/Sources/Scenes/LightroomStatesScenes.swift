import AppKit
import Observation
import RedlampDesign
@_spi(Harness) import RedlampUI
import SwiftUI

extension HarnessScene {
    static var libraryLightroomStates: HarnessScene {
        HarnessScene(
            id: "library-lightroom-states",
            title: "Lightroom Classic: states",
            symbol: "square.grid.2x2",
            synopsis: "The Lightroom import window's Review, progress and result in every state, from made-up values",
            section: .library,
        ) {
            LightroomStatesScene()
        }
    }

    static var libraryLightroomPlayground: HarnessScene {
        HarnessScene(
            id: "library-lightroom-playground",
            title: "Lightroom Classic: playground",
            symbol: "play.circle",
            synopsis: "A simulated import of 48,212 photos on a disk of your choice, with Low Power Mode",
            section: .library,
        ) {
            LightroomPlaygroundScene()
        } inspector: {
            LightroomPlaygroundInspector()
        }
    }
}

// MARK: - States

/// `--lightroom-state <id>` shows only that state; with `--lightroom-capture`, a list of them separated by commas.
private struct LightroomStatesScene: View {
    private let only = HarnessLaunch.value(after: "--lightroom-capture") == nil
        ? HarnessLaunch.value(after: "--lightroom-state") : nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LightroomImportSamples.states.filter { only == nil || $0.id == only }) { state in
                SpecimenGroup(title: state.title, note: "\(state.note) (\(state.id))") {
                    LightroomWindowSpecimen(screen: state.screen, size: state.size, detailsOpen: state.detailsOpen)
                }
            }
        }
        .task { await LightroomCapture.runIfRequested() }
    }
}

/// `--lightroom-capture <folder>`: each state, and the playground at three moments, in a window of its own in dark and
/// light, captured from the window server as `<folder>/<state>-<appearance>.png`; then the harness quits. The
/// harness's `--snapshot` draws SwiftUI blank on macOS 26, and an app may capture its own windows without Screen
/// Recording.
@MainActor
private enum LightroomCapture {
    static func runIfRequested() async {
        guard let folder = HarnessLaunch.value(after: "--lightroom-capture") else { return }
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        typealias Shot = (
            id: String, size: LightroomImportSamples.State.Size, detailsOpen: Bool,
            screen: @MainActor () -> LightroomImportScreen,
        )
        var shots: [Shot] = LightroomImportSamples.states.map { state in
            (state.id, state.size, state.detailsOpen, { state.screen })
        }
        let playground = LightroomPlayground.shared
        for (id, disk, lowPower, ticks) in [
            ("playground-indexing-paused", PlaygroundDisk.spinning, true, 40),
            ("playground-writing", PlaygroundDisk.spinning, false, 130),
            ("playground-ssd-done", PlaygroundDisk.externalSSD, false, 60),
        ] {
            shots.append((id, .standard, false, {
                playground.choose(disk)
                playground.lowPower = false
                playground.advance(lowPower ? 30 : ticks)
                if lowPower {
                    playground.lowPower = true
                    playground.advance(ticks - 30)
                }
                return playground.screen
            }))
        }
        if let only = HarnessLaunch.value(after: "--lightroom-state")?.split(separator: ",").map(String.init) {
            shots = shots.filter { only.contains($0.id) }
        }
        for appearance in [ThemeAppearance.dark, .light] {
            NSApp.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            Palette.current = ThemeSelection(appearance: appearance).tokens
            for (id, size, detailsOpen, screen) in shots {
                let specimen = LightroomWindowSpecimen(screen: screen(), size: size, detailsOpen: detailsOpen)
                let frame = size == .minimum ? LightroomWindowSpecimen.minimum : LightroomWindowSpecimen.standard
                await capture(specimen, frame: frame, to: out.appending(path: "\(id)-\(appearance.rawValue).png"))
            }
        }
        NSApp.terminate(nil)
    }

    private static func capture(_ specimen: LightroomWindowSpecimen, frame: CGSize, to url: URL) async {
        let screen = NSScreen.screens.first { $0.backingScaleFactor > 1 } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let window = NSWindow(
            contentRect: NSRect(
                x: area.midX - frame.width / 2,
                y: area.midY - frame.height / 2,
                width: frame.width,
                height: frame.height,
            ),
            styleMask: [.borderless], backing: .buffered, defer: false,
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: specimen.focusEffectDisabled())
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(700))
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        // Obsoleted in the macOS 15 SDK, still there at run time: ScreenCaptureKit asks for Screen Recording.
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let create = unsafeBitCast(symbol, to: CreateImage.self)
            let options = CGWindowImageOption([.boundsIgnoreFraming, .bestResolution]).rawValue
            if let image = create(
                .null, CGWindowListOption.optionIncludingWindow.rawValue, CGWindowID(window.windowNumber), options,
            )?.takeRetainedValue() {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            }
        }
        window.orderOut(nil)
    }
}

/// The window around the screen: its title bar, the screen, and a stand-in for its bottom bar, whose note and
/// buttons come from the screen but stay AppKit's in the app.
private struct LightroomWindowSpecimen: View {
    let screen: LightroomImportScreen
    let size: LightroomImportSamples.State.Size
    @State private var detailsOpen: Bool

    /// The window as it opens, within CI's 700-point screen, and at its smallest.
    static let standard = CGSize(width: 760, height: 640)
    static let minimum = CGSize(width: 600, height: 480)

    init(
        screen: LightroomImportScreen,
        size: LightroomImportSamples.State.Size = .standard,
        detailsOpen: Bool = false,
    ) {
        self.screen = screen
        self.size = size
        _detailsOpen = State(initialValue: detailsOpen)
    }

    var body: some View {
        let frame = size == .minimum ? Self.minimum : Self.standard
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 7) {
                    ForEach(0 ..< 3, id: \.self) { _ in
                        Circle().fill(Color(nsColor: .tertiaryLabelColor)).frame(width: 11, height: 11)
                    }
                    Spacer()
                }
                Text("Import from Lightroom Classic")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.bar)
            LightroomImportView(
                screen: screen,
                actions: LightroomImportActions(copy: { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }),
                detailsOpen: $detailsOpen,
            )
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 10) {
                Text(screen.barNote ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                ForEach(screen.buttons, id: \.self) { button in
                    if button.isDefault {
                        Button(button.title) {}
                            .buttonStyle(.borderedProminent)
                            .disabled(!button.isEnabled)
                    } else {
                        Button(button.title) {}
                            .disabled(!button.isEnabled)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
        .frame(width: frame.width, height: frame.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }
}

// MARK: - Playground

/// How fast each kind of disk indexes and writes, in photos a second: made up until LIB-53 measures them, to show
/// how the screen behaves rather than how fast Redlamp is.
private enum PlaygroundDisk: String, CaseIterable, Identifiable {
    case internalSSD = "Internal SSD"
    case externalSSD = "External SSD"
    case spinning = "2.5-inch spinning disk"

    var id: String {
        rawValue
    }

    var speeds: (index: Double, write: Double) {
        switch self {
        case .internalSSD: (900, 520)
        case .externalSSD: (420, 300)
        case .spinning: (19, 42)
        }
    }

    static var launched: PlaygroundDisk {
        switch HarnessLaunch.value(after: "--lightroom-disk") {
        case "internal": .internalSSD
        case "external": .externalSSD
        default: .spinning
        }
    }

    var disk: LightroomImportScreen.Disk {
        switch self {
        case .internalSSD: LightroomImportScreen.Disk("Macintosh HD", .internal)
        case .externalSSD: LightroomImportScreen.Disk("Samsung T7", .externalSSD)
        case .spinning: LightroomImportScreen.Disk("LaCie", .spinning)
        }
    }
}

/// A simulated import, ten simulated seconds a tick, five ticks a second. `--lightroom-play` starts it, with
/// `--lightroom-disk internal|external|spinning` and `--lightroom-low-power`.
@MainActor @Observable
private final class LightroomPlayground {
    static let shared = LightroomPlayground()

    static let step: TimeInterval = 10
    static let toIndex = 12400
    static let toWrite = 48212
    private static let folders: [(name: String, photos: Int)] = [
        ("Photos 2018", 9812), ("Photos 2019", 12400), ("2020 to 2024", 25000), ("Scans", 1000),
    ]

    private(set) var disk = PlaygroundDisk.launched

    var lowPower = HarnessLaunch.arguments.contains("--lightroom-low-power")
    var detailsOpen = false
    private(set) var running = false
    private(set) var time: TimeInterval = 0
    private(set) var indexed = 0.0
    private(set) var written = 0.0
    private var indexMeter = RateMeter(start: 0)
    private var writeMeter: RateMeter?
    private var indexTime: TimeInterval?
    private var log: [LightroomImportScreen.LogEntry] = []
    private var wasPaused = false
    private var random = UInt64(0x9E37_79B9_7F4A_7C15)
    private let started = Date()
    @ObservationIgnored private var ticker: Task<Void, Never>?

    private init() {
        if HarnessLaunch.arguments.contains("--lightroom-play") {
            toggle()
        }
    }

    var finished: Bool {
        Int(written) >= Self.toWrite
    }

    var playTitle: String {
        running ? "Pause" : finished ? "Finished" : time == 0 ? "Play" : "Carry On"
    }

    func toggle() {
        guard !finished else { return }
        running.toggle()
        if running, time == 0 {
            note(
                "Read “\(LightroomImportSamples.catalog)” (Lightroom Classic 13): 51,030 photos, 7 root folders, in 2.4 s",
            )
            note("Added 1 folder to Folders: \(disk.disk.name) › Photos 2019")
        }
        ticker?.cancel()
        guard running else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick()
            }
        }
    }

    /// Runs `ticks` ticks at once, as playing would.
    func advance(_ ticks: Int) {
        let wasRunning = running
        if time == 0 {
            toggle()
            ticker?.cancel()
        }
        running = true
        for _ in 0 ..< ticks where !finished {
            tick()
        }
        running = wasRunning && !finished
    }

    func choose(_ disk: PlaygroundDisk) {
        self.disk = disk
        reset()
    }

    func reset() {
        ticker?.cancel()
        running = false
        time = 0
        indexed = 0
        written = 0
        indexMeter = RateMeter(start: 0)
        writeMeter = nil
        indexTime = nil
        log = []
        wasPaused = false
    }

    private func jitter() -> Double {
        random = random &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return 0.85 + 0.3 * Double(random >> 11) / Double(1 << 53)
    }

    private func tick() {
        guard running, !finished else {
            running = false
            ticker?.cancel()
            return
        }
        time += Self.step
        if Int(indexed) < Self.toIndex {
            let paused = lowPower
            if paused != wasPaused {
                note(paused ? "Paused: Low Power Mode is on" : "Carried on: Low Power Mode is off")
                wasPaused = paused
            }
            indexed = min(Double(Self.toIndex), indexed + (paused ? 0 : disk.speeds.index * jitter() * Self.step))
            indexMeter.record(Int(indexed), at: time, pausedBy: paused ? .lowPower : nil)
            if Int(indexed) >= Self.toIndex {
                indexTime = time
                note("Indexed 12,400 photos in \(ProgressText.duration(time)) on \(disk.disk.name)")
                writeMeter = RateMeter(start: time)
            }
            return
        }
        let before = Int(written) / 10000
        written = min(Double(Self.toWrite), written + disk.speeds.write * jitter() * Self.step)
        writeMeter?.record(Int(written), at: time)
        let parts = (Self.toWrite + 9999) / 10000
        for part in before ..< min(Int(written) / 10000, parts) {
            note("Part \(part + 1) of \(parts) written")
        }
        if finished {
            note("Imported 48,212 photos in \(ProgressText.duration(time))")
            running = false
            ticker?.cancel()
        }
    }

    private func note(_ text: String) {
        log.append(.init(started.addingTimeInterval(time), text))
    }

    private var roots: [LightroomImportScreen.RootProgress] {
        let disk = disk.disk
        if Int(indexed) < Self.toIndex {
            return [.init("\(disk.name) › Photos 2019", disk: disk, .init(Int(indexed), of: Self.toIndex))]
        }
        var left = Int(written)
        return Self.folders.map { folder in
            let done = min(left, folder.photos)
            left -= done
            return .init("\(disk.name) › \(folder.name)", disk: disk, .init(done, of: folder.photos))
        }
    }

    var screen: LightroomImportScreen {
        let report = LightroomImportSamples.report()
        var screen = LightroomImportScreen(
            phase: .review, catalog: LightroomImportSamples.catalog, readTime: 2.4,
            review: .init(report, disks: LightroomImportSamples.disks, edits: LightroomImportSamples.edits),
            log: log, reportText: report.lines(),
        )
        guard time > 0 || running else { return screen }
        let indexing = Int(indexed) < Self.toIndex
        let meter = indexing ? indexMeter : writeMeter ?? RateMeter(start: time)
        let paused = indexing && lowPower ? PauseReason.lowPower : nil
        var notices: [LightroomImportScreen.Notice] = paused.map { [.paused($0)] } ?? []
        if disk == .spinning, !finished {
            notices.append(.spinning(disk: disk.disk.name))
        }
        screen.phase = indexing ? .adding : finished ? .done : .writing
        screen.run = LightroomImportScreen.Run(
            folders: 1, indexed: .init(Int(indexed), of: Self.toIndex), indexTime: indexTime,
            written: .init(Int(written), of: Self.toWrite), elapsed: time,
            pace: meter.pace(total: indexing ? Self.toIndex : Self.toWrite, now: time, pausedBy: paused),
            throughput: meter.throughput(now: time), roots: roots, notices: notices,
        )
        if finished {
            screen.result = .init(written: Self.toWrite, total: Self.toWrite, elapsed: time)
            screen.canUndo = true
        }
        return screen
    }
}

private struct LightroomPlaygroundScene: View {
    @State private var playground = LightroomPlayground.shared

    var body: some View {
        SpecimenGroup(
            title: "A simulated import",
            note: "48,212 photos, 12,400 of them in a folder the library doesn't have yet, ten simulated seconds a "
                + "tick. The rates are made up until LIB-53 measures them: they show how the screen behaves, not how "
                + "fast Redlamp is. Play, Low Power Mode and the disk are in the inspector.",
        ) {
            LightroomWindowSpecimen(screen: playground.screen, detailsOpen: playground.detailsOpen)
                .id(playground.detailsOpen)
        }
    }
}

private struct LightroomPlaygroundInspector: View {
    @State private var playground = LightroomPlayground.shared

    var body: some View {
        Form {
            Section("Simulation") {
                Picker("Disk", selection: Binding(get: { playground.disk }, set: { playground.choose($0) })) {
                    ForEach(PlaygroundDisk.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Low Power Mode", isOn: $playground.lowPower)
                Toggle("Details open", isOn: $playground.detailsOpen)
                HStack {
                    Button(playground.playTitle) { playground.toggle() }
                        .disabled(playground.finished)
                    Button("Reset") { playground.reset() }
                }
                LabeledContent("Simulated time", value: ProgressText.duration(playground.time))
            }
        }
        .formStyle(.grouped)
    }
}
