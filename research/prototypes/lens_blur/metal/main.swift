// Times the gather renderer's kernels (render_gather.py) in Metal, standalone (OTH-03, #138).
//
//     swiftc -O main.swift -o <binary>
//     <binary> check <dir>                 renders <dir>/colour.f32 and logz.f32 with params.json to metal.f32
//     <binary> time <dir> [--sizes WxH,...] [--fractions 0.02,0.04] [--kappa 16] [--dense-max 1000000]
//
// time resamples the check scene to each size, scales its CoC so the largest diameter is the
// fraction of the long edge, and reports the GPU time (command buffers' GPUStartTime to GPUEndTime,
// summed over a frame's buffers; the median of several frames after a warm-up) and the memory the
// frame's textures and buffers take. --kappa 0 is the dense lattice (every pixel within the CoC),
// timed only where pixels x samples stays under --dense-max million.

import Foundation
import Metal

struct Sample {
    var offset: SIMD2<Float>
    var rho: Float
    var spacing: Float
    var area: Float
    var gFront: Float
    var gBack: Float
    var unused: Float = 0
}

struct Params {
    var size: SIMD2<Int32>
    var sampleCount: Int32
    var lutCount: Int32
    var lutStep: Float
    var tile: Int32
    var tiles: SIMD2<Int32>
    var window: Int32
    var rowStart: Int32
    var unused: SIMD2<Float> = .zero
}

struct Aperture: Decodable {
    let blades: Int
    let rotation: Double
    let ratio: Double
}

struct CheckParams: Decodable {
    let width: Int
    let height: Int
    let aperture: Aperture
    let kappa: Double
}

let lutStep: Float = 8
let tile = 16

func gauge(_ ux: Double, _ uy: Double, _ ap: Aperture, front: Bool) -> Double {
    let sign: Double = front ? 1 : -1
    let ax = sign * ux, ay = -sign * uy
    if ap.blades == 0 {
        return hypot(ax * ap.ratio, ay)
    }
    let apothem = cos(Double.pi / Double(ap.blades))
    var g = -Double.infinity
    for k in 0 ..< ap.blades {
        let mid = ap.rotation + 2 * Double.pi * Double(k) / Double(ap.blades)
        g = max(g, (ax * cos(mid) + ay * sin(mid)) / apothem)
    }
    return g
}

/// The same set as render_gather.sample_set; kappa 0 is the dense lattice out to the radius.
func sampleSet(radius: Double, kappa: Double, aperture: Aperture) -> [Sample] {
    var points: [SIMD2<Int>: (area: Double, spacing: Double)] = [:]
    let k = kappa > 0 ? kappa : radius + 2
    let dense = min(k, radius)
    let n = Int(ceil(dense))
    for oy in -n ... n {
        for ox in -n ... n where hypot(Double(ox), Double(oy)) <= dense + 0.5 {
            points[SIMD2(ox, oy)] = (1, 1)
        }
    }
    var rho = dense + 1, ring = 0
    while rho <= radius + 1.5, k < radius {
        let s = max(rho / k, 1)
        let count = max(Int((2 * Double.pi * rho / s).rounded()), 8)
        let phase = (Double(ring) * 0.6180339887).truncatingRemainder(dividingBy: 1)
        for i in 0 ..< count {
            let t = 2 * Double.pi * (Double(i) + phase) / Double(count)
            let key = SIMD2(Int((rho * cos(t)).rounded()), Int((rho * sin(t)).rounded()))
            let area = 2 * Double.pi * rho * s / Double(count)
            if let old = points[key] {
                points[key] = (old.area + area, old.spacing)
            } else {
                points[key] = (area, s)
            }
        }
        rho += s
        ring += 1
    }
    return points.map { key, value in
        let r = hypot(Double(key.x), Double(key.y))
        let ux = r > 0 ? Double(key.x) / r : 0, uy = r > 0 ? Double(key.y) / r : 0
        return Sample(
            offset: SIMD2(Float(key.x), Float(key.y)),
            rho: Float(r),
            spacing: Float(value.spacing),
            area: Float(value.area),
            gFront: Float(gauge(ux, uy, aperture, front: true)),
            gBack: Float(gauge(ux, uy, aperture, front: false)),
        )
    }.sorted { $0.rho < $1.rho }
}

func normaliser(_ samples: [Sample], top: Double, front: Bool) -> [Float] {
    let count = Int(top * Double(lutStep)) + 2
    return (0 ..< count).map { i in
        let r = Float(i) / lutStep
        var sum: Float = 0
        for s in samples {
            sum += s.area * min(max(0.5 + (r - s.rho * (front ? s.gFront : s.gBack)) / s.spacing, 0), 1)
        }
        return sum
    }
}

let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let library = try device.makeLibrary(
    source: String(contentsOf: here.appendingPathComponent("Gather.metal"), encoding: .utf8),
    options: nil,
)
func pipeline(_ name: String) -> MTLComputePipelineState {
    try! device.makeComputePipelineState(function: library.makeFunction(name: name)!)
}

let resample = pipeline("lb_resample"), tileMax = pipeline("lb_tile_max"), tileReach = pipeline("lb_tile_reach")
let pullBase = pipeline("lb_pull_base"), pull = pipeline("lb_pull"), push = pipeline("lb_push"),
    gatherKernel = pipeline("lb_gather")

func texture(_ w: Int, _ h: Int, _ format: MTLPixelFormat) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]
    d.storageMode = .private
    return device.makeTexture(descriptor: d)!
}

func dispatch(_ encoder: MTLComputeCommandEncoder, _ state: MTLComputePipelineState, _ w: Int, _ h: Int) {
    encoder.setComputePipelineState(state)
    encoder.dispatchThreads(
        MTLSize(width: w, height: h, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1),
    )
}

final class Frame {
    let width: Int, height: Int
    let colour: MTLTexture, logz: MTLTexture, out: MTLTexture
    let tiles: MTLTexture, reach: MTLTexture
    var levels: [MTLTexture] = [], filled: [MTLTexture] = []
    let samples: MTLBuffer, lutFront: MTLBuffer, lutBack: MTLBuffer
    var params: Params

    init(width: Int, height: Int, radius: Double, kappa: Double, aperture: Aperture) {
        self.width = width
        self.height = height
        colour = texture(width, height, .rgba16Float)
        logz = texture(width, height, .r16Float)
        out = texture(width, height, .rgba32Float)
        let tx = (width + tile - 1) / tile, ty = (height + tile - 1) / tile
        tiles = texture(tx, ty, .r32Float)
        reach = texture(tx, ty, .r32Float)
        var w = width, h = height
        while true {
            levels.append(texture(w, h, .rgba32Float))
            filled.append(texture(w, h, .rgba32Float))
            if w == 1, h == 1 {
                break
            }
            w = (w + 1) / 2
            h = (h + 1) / 2
        }
        let set = sampleSet(radius: radius + 1, kappa: kappa, aperture: aperture)
        let front = normaliser(set, top: radius + 1, front: true), back = normaliser(set, top: radius + 1, front: false)
        samples = device.makeBuffer(bytes: set, length: set.count * MemoryLayout<Sample>.stride)!
        lutFront = device.makeBuffer(bytes: front, length: front.count * 4)!
        lutBack = device.makeBuffer(bytes: back, length: back.count * 4)!
        params = Params(
            size: SIMD2(Int32(width), Int32(height)),
            sampleCount: Int32(set.count),
            lutCount: Int32(front.count),
            lutStep: lutStep,
            tile: Int32(tile),
            tiles: SIMD2(Int32(tx), Int32(ty)),
            window: Int32(ceil((radius + 2) * 1.07 / Double(tile))) + 1,
            rowStart: 0,
        )
    }

    var bytes: Int {
        ([colour, logz, out, tiles, reach] + levels + filled).map(\.allocatedSize).reduce(0, +)
            + samples.length + lutFront.length + lutBack.length
    }

    /// Encodes one frame; returns the GPU seconds of its prepare and gather passes.
    func run(bandRows: Int) -> (prepare: Double, gather: Double) {
        let prep = queue.makeCommandBuffer()!
        let e = prep.makeComputeCommandEncoder()!
        e.setTexture(colour, index: 0)
        e.setTexture(tiles, index: 1)
        e.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        dispatch(e, tileMax, Int(params.tiles.x), Int(params.tiles.y))
        e.setTexture(tiles, index: 0)
        e.setTexture(reach, index: 1)
        dispatch(e, tileReach, Int(params.tiles.x), Int(params.tiles.y))
        e.setTexture(colour, index: 0)
        e.setTexture(levels[0], index: 1)
        dispatch(e, pullBase, width, height)
        for i in 1 ..< levels.count {
            e.setTexture(levels[i - 1], index: 0)
            e.setTexture(levels[i], index: 1)
            dispatch(e, pull, levels[i].width, levels[i].height)
        }
        for i in stride(from: levels.count - 1, through: 0, by: -1) {
            var coarsest: Int32 = i == levels.count - 1 ? 1 : 0
            e.setTexture(levels[i], index: 0)
            e.setTexture(filled[min(i + 1, levels.count - 1)], index: 1)
            e.setTexture(filled[i], index: 2)
            e.setBytes(&coarsest, length: 4, index: 0)
            dispatch(e, push, levels[i].width, levels[i].height)
        }
        e.endEncoding()
        prep.commit()
        var buffers: [MTLCommandBuffer] = []
        for start in stride(from: 0, to: height, by: bandRows) {
            let cb = queue.makeCommandBuffer()!
            let g = cb.makeComputeCommandEncoder()!
            var p = params
            p.rowStart = Int32(start)
            g.setTextures([colour, logz, reach, filled[0], out], range: 0 ..< 5)
            g.setBuffer(samples, offset: 0, index: 0)
            g.setBuffer(lutFront, offset: 0, index: 1)
            g.setBuffer(lutBack, offset: 0, index: 2)
            g.setBytes(&p, length: MemoryLayout<Params>.stride, index: 3)
            dispatch(g, gatherKernel, width, min(bandRows, height - start))
            g.endEncoding()
            cb.commit()
            buffers.append(cb)
        }
        buffers.last!.waitUntilCompleted()
        prep.waitUntilCompleted()
        for b in buffers + [prep] where b.status == .error {
            fatalError("command buffer failed: \(String(describing: b.error))")
        }
        return (prep.gpuEndTime - prep.gpuStartTime, buffers.map { $0.gpuEndTime - $0.gpuStartTime }.reduce(0, +))
    }
}

func readFloats(_ url: URL) -> [Float] {
    let data = try! Data(contentsOf: url)
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

/// The check scene as float textures at its own size (rgb + signed radius, log depth).
func sourceTextures(_ dir: URL, _ p: CheckParams) -> (MTLTexture, MTLTexture) {
    func upload(_ values: [Float], _ format: MTLPixelFormat, _ channels: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: p.width,
            height: p.height,
            mipmapped: false,
        )
        d.usage = [.shaderRead]
        let t = device.makeTexture(descriptor: d)!
        values.withUnsafeBytes {
            t.replace(
                region: MTLRegionMake2D(0, 0, p.width, p.height),
                mipmapLevel: 0,
                withBytes: $0.baseAddress!,
                bytesPerRow: p.width * channels * 4,
            )
        }
        return t
    }
    return (
        upload(readFloats(dir.appendingPathComponent("colour.f32")), .rgba32Float, 4),
        upload(readFloats(dir.appendingPathComponent("logz.f32")), .r32Float, 1),
    )
}

func fillFrame(_ frame: Frame, from source: (MTLTexture, MTLTexture), radiusScale: Float) {
    let cb = queue.makeCommandBuffer()!
    let e = cb.makeComputeCommandEncoder()!
    e.setTextures([source.0, source.1, frame.colour, frame.logz], range: 0 ..< 4)
    var scale = radiusScale
    e.setBytes(&scale, length: 4, index: 0)
    dispatch(e, resample, frame.width, frame.height)
    e.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
}

func maxRadius(_ dir: URL) -> Float {
    let c = readFloats(dir.appendingPathComponent("colour.f32"))
    return stride(from: 3, to: c.count, by: 4).map { abs(c[$0]) }.max()!
}

let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[2])
let check = try JSONDecoder().decode(
    CheckParams.self,
    from: Data(contentsOf: dir.appendingPathComponent("params.json")),
)
func option(_ name: String) -> String? {
    args.firstIndex(of: name).map { args[$0 + 1] }
}

if args[1] == "check" {
    let source = sourceTextures(dir, check)
    let frame = Frame(
        width: check.width,
        height: check.height,
        radius: Double(maxRadius(dir)),
        kappa: check.kappa,
        aperture: check.aperture,
    )
    fillFrame(frame, from: source, radiusScale: 1)
    let times = frame.run(bandRows: 256)
    let readable = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba32Float,
        width: check.width,
        height: check.height,
        mipmapped: false,
    )
    readable.storageMode = .shared
    let copy = device.makeTexture(descriptor: readable)!
    let cb = queue.makeCommandBuffer()!
    let blit = cb.makeBlitCommandEncoder()!
    blit.copy(from: frame.out, to: copy)
    blit.endEncoding()
    cb.commit()
    cb.waitUntilCompleted()
    var out = [Float](repeating: 0, count: check.width * check.height * 4)
    out.withUnsafeMutableBytes {
        copy.getBytes(
            $0.baseAddress!,
            bytesPerRow: check.width * 16,
            from: MTLRegionMake2D(0, 0, check.width, check.height),
            mipmapLevel: 0,
        )
    }
    try out.withUnsafeBytes { try Data($0).write(to: dir.appendingPathComponent("metal.f32")) }
    print(String(
        format: "check: %d samples, prepare %.2f ms, gather %.2f ms",
        frame.params.sampleCount,
        times.prepare * 1000,
        times.gather * 1000,
    ))
} else {
    let sizes = (option("--sizes") ?? "2560x1600,3000x2000,6000x4000,8064x6048,11648x8736").split(separator: ",").map {
        let p = $0.split(separator: "x").map { Int($0)! }
        return (p[0], p[1])
    }
    let fractions = (option("--fractions") ?? "0.02,0.04").split(separator: ",").map { Double($0)! }
    let kappas = (option("--kappa") ?? "16").split(separator: ",").map { Double($0)! }
    let denseMax = Double(option("--dense-max") ?? "1000000")!
    let source = sourceTextures(dir, check)
    let native = maxRadius(dir)
    print("size,megapixels,coc_fraction,max_coc_px,kappa,samples,prepare_ms,gather_ms,total_ms,runs,memory_mb")
    for (w, h) in sizes {
        for fraction in fractions {
            for kappa in kappas {
                let radius = fraction * Double(max(w, h)) / 2
                let samples = sampleSet(radius: radius + 1, kappa: kappa, aperture: check.aperture).count
                if kappa == 0, Double(w * h) * Double(samples) / 1e6 > denseMax {
                    continue
                }
                autoreleasepool {
                    let frame = Frame(width: w, height: h, radius: radius, kappa: kappa, aperture: check.aperture)
                    fillFrame(frame, from: source, radiusScale: Float(radius) / native)
                    let megapixels = Double(w * h) / 1e6
                    let runs = megapixels > 30 ? 3 : 5
                    let bandRows = max(64, Int(2e8 / Double(w * samples)))
                    _ = frame.run(bandRows: bandRows)
                    let times = (0 ..< runs).map { _ in frame.run(bandRows: bandRows) }
                    let prep = times.map(\.prepare).sorted()[runs / 2], gather = times.map(\.gather).sorted()[runs / 2]
                    let total = times.map { $0.prepare + $0.gather }.sorted()[runs / 2]
                    print(String(
                        format: "%dx%d,%.1f,%.2f,%.0f,%.0f,%d,%.1f,%.1f,%.1f,%d,%.0f",
                        w,
                        h,
                        megapixels,
                        fraction,
                        2 * radius,
                        kappa,
                        samples,
                        prep * 1000,
                        gather * 1000,
                        total * 1000,
                        runs,
                        Double(frame.bytes) / 1_048_576,
                    ))
                    fflush(stdout)
                }
            }
        }
    }
}
