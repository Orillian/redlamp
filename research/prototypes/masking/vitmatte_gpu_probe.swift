import CoreML
import CoreVideo
import Darwin
import Foundation
import MetalPerformanceShadersGraph
import ObjectiveC

/// How many times MPS Graph has run its optimisation passes on an executable, where the abort
/// happens (`-[MPSGraphExecutable applyOptimizationPassesWithDevice:…]`, in the crash's stack).
nonisolated(unsafe) var passRuns = 0
let passLock = NSLock()

func countPassRuns() {
    let selector = NSSelectorFromString(
        "applyOptimizationPassesWithDevice:module:compilationID:compilationDescriptor:perEntryPointFuncOpMLIRName:",
    )
    guard let method = class_getInstanceMethod(MPSGraphExecutable.self, selector) else {
        print("NOPASSES no \(NSStringFromSelector(selector))")
        return
    }
    typealias Original = @convention(c) (
        AnyObject, Selector, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?,
        UnsafeRawPointer?,
    ) -> UnsafeRawPointer?
    let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
    let counted: @convention(block) (
        AnyObject, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?,
    ) -> UnsafeRawPointer? = { executable, a, b, c, d, e in
        passLock.withLock { passRuns += 1 }
        return original(executable, selector, a, b, c, d, e)
    }
    method_setImplementation(method, imp_implementationWithBlock(counted))
}

func passCount() -> Int {
    passLock.withLock { passRuns }
}

/// How often a ViTMatte prediction on the GPU aborts in Metal Performance Shaders Graph on macOS 27
/// (MSK-33), and with which Core ML options or model it doesn't. Each trial loads the compiled model
/// afresh and predicts: the first prediction specialises the model's MPS Graph executable for the
/// GPU, where the abort happens. An abort ends the process with status 77 after its trial's BEGIN
/// line, so no crash report is written; `vitmatte_gpu_probe.py` runs the processes and counts.
///
///     xcrun swiftc -O -parse-as-library -o vitmatte-gpu-probe vitmatte_gpu_probe.swift
///     vitmatte-gpu-probe <model.mlmodelc> [loads=10] [predictions=2] [units=gpu|all|cpu|ane]
///         [strategy=default|fast] [reshape=frequent|infrequent] [lowprec=0|1] [fresh=0|1]
///         [scratch=<folder>] [warm=<model.mlmodelc>,…] [dump=<file>]
///     vitmatte-gpu-probe <model.mlpackage> engine=mpsgraph [level=0|1] [loads=…] [predictions=…]
///     vitmatte-gpu-probe <model.mlpackage> compile=<model.mlmodelc>
///
/// fresh=1 clones the compiled model to a new path for each trial, so Core ML compiles it again
/// rather than finding it in its cache, as each test run did before ede2351ea. warm= loads other
/// models and predicts once with each on the GPU first, as a test process does before ViTMatte.
/// engine=mpsgraph runs the package with MPS Graph itself rather than Core ML. Each TRIAL line
/// counts the times MPS Graph ran its optimisation passes, at the load and at the predictions.
///
/// On the build Mac's macOS 27.0.1 (M4 Max) every trial of the shipped model runs the passes once,
/// at its first prediction, whatever the options; the abort comes in about 0.1% of trials with two
/// to four probes at once and 2% with eight to ten. Core ML's options (fastPrediction, infrequent
/// reshapes, low-precision accumulation, `.all`) and MPS Graph run directly abort too; the models
/// `decompress_vitmatte.py` writes, whose relative-position tables are float16, don't.
@main
enum Probe {
    /// Ends the process on an abort without a crash report. Installed again before each prediction,
    /// since loading a model can install a handler of its own.
    static func catchAbort() {
        signal(SIGABRT) { _ in
            let text: StaticString = "PROBE-ABORT\n"
            _ = write(2, text.utf8Start, text.utf8CodeUnitCount)
            _exit(77)
        }
    }

    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)
        catchAbort()
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            print("usage: vitmatte-gpu-probe <model.mlmodelc> [key=value…]")
            exit(2)
        }
        let model = URL(fileURLWithPath: arguments[1])
        var options: [String: String] = [:]
        for argument in arguments.dropFirst(2) {
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            options[parts[0]] = parts.count > 1 ? parts[1] : "1"
        }
        if let destination = options["compile"] {
            let compiled = try MLModel.compileModel(at: model)
            try FileManager.default.moveItem(at: compiled, to: URL(fileURLWithPath: destination))
            print("COMPILED \(destination)")
            return
        }
        let loads = Int(options["loads"] ?? "10") ?? 10
        let predictions = max(Int(options["predictions"] ?? "2") ?? 2, 1)
        let configuration = try configuration(options)
        let fresh = options["fresh"] == "1"
        let scratch = URL(fileURLWithPath: options["scratch"] ?? NSTemporaryDirectory())
        print("CONFIG units=\(configuration.computeUnits.rawValue) strategy=\(options["strategy"] ?? "-") "
            + "reshape=\(options["reshape"] ?? "-") lowprec=\(configuration.allowLowPrecisionAccumulationOnGPU) "
            + "fresh=\(fresh) model=\(model.lastPathComponent) pid=\(getpid())")

        for path in (options["warm"] ?? "").split(separator: ",") where !path.isEmpty {
            let other = MLModelConfiguration()
            other.computeUnits = .cpuAndGPU
            let started = Date()
            let loaded = try MLModel(contentsOf: URL(fileURLWithPath: String(path)), configuration: other)
            _ = try loaded.prediction(from: zeros(for: loaded))
            print(String(
                format: "WARM %@ %.3f",
                (path as NSString).lastPathComponent,
                Date().timeIntervalSince(started),
            ))
        }

        countPassRuns()
        let input = try tile()
        if options["engine"] == "mpsgraph" {
            try mpsGraphTrials(package: model, options: options, loads: loads, predictions: predictions, input: input)
            print("DONE \(loads)")
            return
        }
        for trial in 0 ..< loads {
            var url = model
            if fresh {
                url = scratch.appending(path: "probe-\(getpid())-\(trial)-\(UUID().uuidString).mlmodelc")
                try FileManager.default.copyItem(at: model, to: url)
            }
            defer {
                if fresh {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            print("BEGIN \(trial)")
            let before = passCount()
            var started = Date()
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            let load = Date().timeIntervalSince(started)
            let atLoad = passCount() - before
            var times: [Double] = []
            var alpha: MLMultiArray?
            for _ in 0 ..< predictions {
                catchAbort()
                started = Date()
                let output = try loaded.prediction(from: input.features)
                times.append(Date().timeIntervalSince(started))
                alpha = output.featureValue(for: "alpha")?.multiArrayValue
            }
            let values = alpha.map(floats) ?? []
            let band = input.band.isEmpty || values.isEmpty ? 0 : input.band.map { values[$0] }.reduce(0, +)
                / Float(input.band.count)
            let next = times.count > 1 ? times.dropFirst().sorted()[(times.count - 1) / 2] : 0
            print(String(
                format: "TRIAL %d load=%.3f first=%.3f next=%.3f band=%.5f passes=%d+%d", trial, load, times[0], next,
                band,
                atLoad, passCount() - before - atLoad,
            ))
            if trial == 0, let path = options["dump"], !values.isEmpty {
                try values.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: URL(fileURLWithPath: path))
            }
        }
        print("DONE \(loads)")
    }

    /// engine=mpsgraph: the package run by MPS Graph itself rather than Core ML, at optimisation
    /// level= 0 or 1 (MPSGraphCompilationDescriptor's), each trial a new executable.
    static func mpsGraphTrials(
        package: URL, options: [String: String], loads: Int, predictions: Int,
        input: (features: MLFeatureProvider, band: [Int]),
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw CocoaError(.featureUnsupported) }
        let graphDevice = MPSGraphDevice(mtlDevice: device)
        func feed(_ name: String) throws -> MPSGraphTensorData {
            guard let array = input.features.featureValue(for: name)?.multiArrayValue
            else { throw CocoaError(.featureUnsupported) }
            // The package's executable takes the inputs as float16: its first ops cast them so.
            let halves = UnsafeBufferPointer(
                start: array.dataPointer.assumingMemoryBound(to: Float.self),
                count: array.count,
            )
            .map(Float16.init)
            let bytes = halves.withUnsafeBytes { Data($0) }
            return MPSGraphTensorData(device: graphDevice, data: bytes, shape: array.shape, dataType: .float16)
        }
        let feeds = try [feed("image"), feed("trimap")]
        for trial in 0 ..< loads {
            print("BEGIN \(trial)")
            let before = passCount()
            var started = Date()
            let descriptor = MPSGraphCompilationDescriptor()
            descriptor.optimizationLevel = options["level"] == "0" ? .level0 : .level1
            let executable = MPSGraphExecutable(coreMLPackageAtURL: package, descriptor: descriptor)
            let load = Date().timeIntervalSince(started)
            let atLoad = passCount() - before
            if trial == 0 {
                print("FEEDS \(executable.feedTensors?.map { "\($0.shape ?? [])" } ?? ["none"])")
            }
            var times: [Double] = []
            var output: MPSGraphTensorData?
            for _ in 0 ..< predictions {
                catchAbort()
                started = Date()
                output = executable.run(with: queue, inputs: feeds, results: nil, executionDescriptor: nil).first
                times.append(Date().timeIntervalSince(started))
            }
            var values: [Float] = []
            if let output {
                let count = output.shape.reduce(1) { $0 * $1.intValue }
                if output.dataType == .float16 {
                    var halves = [Float16](repeating: 0, count: count)
                    halves.withUnsafeMutableBytes { output.mpsndarray().readBytes($0.baseAddress!, strideBytes: nil) }
                    values = halves.map(Float.init)
                } else {
                    values = [Float](repeating: 0, count: count)
                    values.withUnsafeMutableBytes { output.mpsndarray().readBytes($0.baseAddress!, strideBytes: nil) }
                }
            }
            let band = values.count < 1024 * 1024 ? 0 : input.band.map { values[$0] }
                .reduce(0, +) / Float(input.band.count)
            let next = times.count > 1 ? times.dropFirst().sorted()[(times.count - 1) / 2] : 0
            print(String(
                format: "TRIAL %d load=%.3f first=%.3f next=%.3f band=%.5f passes=%d+%d", trial, load, times[0], next,
                band,
                atLoad, passCount() - before - atLoad,
            ))
        }
    }

    static func configuration(_ options: [String: String]) throws -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = switch options["units"] ?? "gpu" {
        case "gpu": .cpuAndGPU
        case "all": .all
        case "cpu": .cpuOnly
        case "ane": .cpuAndNeuralEngine
        default: throw CocoaError(.featureUnsupported)
        }
        var hints = configuration.optimizationHints
        switch options["strategy"] {
        case nil, "-": break
        case "default": hints.specializationStrategy = .default
        case "fast": hints.specializationStrategy = .fastPrediction
        default: throw CocoaError(.featureUnsupported)
        }
        switch options["reshape"] {
        case nil, "-": break
        case "frequent": hints.reshapeFrequency = .frequent
        case "infrequent": hints.reshapeFrequency = .infrequent
        default: throw CocoaError(.featureUnsupported)
        }
        configuration.optimizationHints = hints
        configuration.allowLowPrecisionAccumulationOnGPU = options["lowprec"] == "1"
        return configuration
    }

    /// A dark disc on a light ground with an unsure ring around its edge, and the ring's pixels.
    static func tile() throws -> (features: MLFeatureProvider, band: [Int]) {
        let side = 1024
        let image = try MLMultiArray(shape: [1, 3, side as NSNumber, side as NSNumber], dataType: .float32)
        let trimap = try MLMultiArray(shape: [1, 1, side as NSNumber, side as NSNumber], dataType: .float32)
        let pixels = image.dataPointer.assumingMemoryBound(to: Float.self)
        let tri = trimap.dataPointer.assumingMemoryBound(to: Float.self)
        var band: [Int] = []
        for y in 0 ..< side {
            for x in 0 ..< side {
                let index = y * side + x
                let r = Float((x - 512) * (x - 512) + (y - 600) * (y - 600)).squareRoot()
                pixels[index] = r < 300 ? 0.2 : 0.8
                pixels[side * side + index] = r < 300 ? 0.15 : 0.75
                pixels[2 * side * side + index] = r < 300 ? 0.1 : 0.7
                tri[index] = r < 280 ? 1 : r < 340 ? 0.5 : 0
                if tri[index] == 0.5 {
                    band.append(index)
                }
            }
        }
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(multiArray: image), "trimap": MLFeatureValue(multiArray: trimap),
        ])
        return (features, band)
    }

    static func floats(_ array: MLMultiArray) -> [Float] {
        switch array.dataType {
        case .float32:
            Array(UnsafeBufferPointer(start: array.dataPointer.assumingMemoryBound(to: Float.self), count: array.count))
        case .float16:
            UnsafeBufferPointer(start: array.dataPointer.assumingMemoryBound(to: Float16.self), count: array.count)
                .map(Float.init)
        default:
            (0 ..< array.count).map { array[$0].floatValue }
        }
    }

    /// Zeros of the shapes and types `model` takes.
    static func zeros(for model: MLModel) throws -> MLFeatureProvider {
        var features: [String: MLFeatureValue] = [:]
        for (name, description) in model.modelDescription.inputDescriptionsByName {
            if let constraint = description.multiArrayConstraint {
                let array = try MLMultiArray(shape: constraint.shape, dataType: constraint.dataType)
                let width = switch constraint.dataType {
                case .float16: 2
                case .double: 8
                default: 4
                }
                memset(array.dataPointer, 0, array.count * width)
                features[name] = MLFeatureValue(multiArray: array)
            } else if let constraint = description.imageConstraint {
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(
                    nil,
                    constraint.pixelsWide,
                    constraint.pixelsHigh,
                    constraint.pixelFormatType,
                    nil,
                    &buffer,
                )
                if let buffer {
                    features[name] = MLFeatureValue(pixelBuffer: buffer)
                }
            }
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }
}
