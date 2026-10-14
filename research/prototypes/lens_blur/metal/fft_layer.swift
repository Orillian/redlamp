// Times one layer of render_layers.py on the GPU: a premultiplied RGBA layer convolved with the
// aperture's kernel by FFT (MPSGraph's real-to-Hermitean FFT, a product, the inverse), standalone.
//
//     swiftc -O fft_layer.swift -o <binary>
//     <binary> [--sizes WxH,...] [--fractions 0.02,0.04]
//
// Each size is padded by the largest CoC (the fraction of the long edge) and up to a multiple of 64
// with no prime factor over 5.
// Reports the time of one layer (the median of five runs after a warm-up) and the memory of its
// tensors. The time is wall time from encoding to completion: MPSGraph commits command buffers of
// its own, so the one handed to it carries no GPU interval of the work.

import Foundation
import Metal
import MetalPerformanceShadersGraph

let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let args = CommandLine.arguments
func option(_ name: String) -> String? {
    args.firstIndex(of: name).map { args[$0 + 1] }
}

let sizes = (option("--sizes") ?? "2560x1600,3000x2000,6000x4000,8064x6048,11648x8736").split(separator: ",").map {
    let p = $0.split(separator: "x").map { Int($0)! }
    return (p[0], p[1])
}

let fractions = (option("--fractions") ?? "0.02,0.04").split(separator: ",").map { Double($0)! }

/// The next multiple of 64 with no prime factor over 5: the FFT slows several times on a large one.
func roundUp(_ x: Int) -> Int {
    var n = (x + 63) / 64 * 64
    func smooth(_ m: Int) -> Bool {
        var m = m
        for p in [2, 3, 5] {
            while m % p == 0 {
                m /= p
            }
        }
        return m == 1
    }
    while !smooth(n) {
        n += 64
    }
    return n
}

print("size,megapixels,coc_fraction,padded,layer_ms,memory_mb")
for (w, h) in sizes {
    for fraction in fractions {
        autoreleasepool {
            let coc = Int(ceil(fraction * Double(max(w, h))))
            let pw = roundUp(w + coc), ph = roundUp(h + coc)
            let graph = MPSGraph()
            let x = graph.placeholder(shape: [4, ph, pw].map { NSNumber(value: $0) }, dataType: .float32, name: nil)
            let k = graph.placeholder(
                shape: [1, ph, pw / 2 + 1].map { NSNumber(value: $0) },
                dataType: .complexFloat32,
                name: nil,
            )
            let forward = MPSGraphFFTDescriptor()
            forward.scalingMode = .none
            let inverse = MPSGraphFFTDescriptor()
            inverse.inverse = true
            inverse.scalingMode = .size
            let spectrum = graph.realToHermiteanFFT(x, axes: [1, 2], descriptor: forward, name: nil)
            let product = graph.multiplication(spectrum, k, name: nil)
            let y = graph.HermiteanToRealFFT(product, axes: [1, 2], descriptor: inverse, name: nil)
            let xBytes = 4 * ph * pw * 4, kBytes = ph * (pw / 2 + 1) * 8
            let xBuffer = device.makeBuffer(length: xBytes, options: .storageModePrivate)!
            let kBuffer = device.makeBuffer(length: kBytes, options: .storageModePrivate)!
            let feeds = [
                x: MPSGraphTensorData(xBuffer, shape: x.shape!, dataType: .float32),
                k: MPSGraphTensorData(kBuffer, shape: k.shape!, dataType: .complexFloat32),
            ]
            let executable = graph.compile(
                with: MPSGraphDevice(mtlDevice: device),
                feeds: feeds.mapValues { MPSGraphShapedType(
                    shape: $0.shape,
                    dataType: $0.dataType,
                ) },
                targetTensors: [y],
                targetOperations: nil,
                compilationDescriptor: nil,
            )
            let inputs = [xBuffer, kBuffer].enumerated().map { i, b in
                MPSGraphTensorData(
                    b,
                    shape: i == 0 ? x.shape! : k.shape!,
                    dataType: i == 0 ? .float32 : .complexFloat32,
                )
            }
            let output = MPSGraphTensorData(
                device.makeBuffer(length: xBytes, options: .storageModePrivate)!,
                shape: x.shape!,
                dataType: .float32,
            )
            var times: [Double] = []
            for run in 0 ..< 6 {
                let start = DispatchTime.now().uptimeNanoseconds
                let cb = MPSCommandBuffer(from: queue)
                _ = executable.encode(to: cb, inputs: inputs, results: [output], executionDescriptor: nil)
                cb.commit()
                cb.waitUntilCompleted()
                if cb.status == .error {
                    fatalError("\(String(describing: cb.error))")
                }
                if run > 0 {
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
                }
            }
            // The spectrum and the product are complex, each about the size of the input.
            let memory = Double(xBytes * 2 + kBytes + 2 * 4 * ph * (pw / 2 + 1) * 8) / 1_048_576
            print(String(
                format: "%dx%d,%.1f,%.2f,%dx%d,%.1f,%.0f",
                w,
                h,
                Double(w * h) / 1e6,
                fraction,
                pw,
                ph,
                times.sorted()[times.count / 2] * 1000,
                memory,
            ))
            fflush(stdout)
        }
    }
}
