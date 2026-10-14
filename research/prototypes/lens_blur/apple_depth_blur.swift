// Core Image's CIDepthBlurEffect on the lens blur benchmark, as a reference (OTH-03, #138).
//
//     swift research/prototypes/lens_blur/apple_depth_blur.swift <jobs.json> [--limit N] [--grid]
//
// Reads the jobs apple_depth_blur.py prep writes. Each job's input goes in as linear Rec.709
// (extended linear sRGB, Core Image's working space), its disparity (1/z, 1/m) and its subject matte
// as single-channel float images, with the focus rectangle normalised to the image in Core Image's
// coordinates (origin at the bottom left). inputAperture has no stated relation to an f-number
// (larger values blur less, as an f-number would, and 0 is a default), so for each job it is
// searched for the value whose render scores best against the truth (PSNR after score.py's tone
// map): a grid from 0.5 to 22, then a golden-section search around the best. The best render is
// written back as linear float RGBA, and results.json beside the jobs records each job's aperture,
// PSNR and render times. --grid writes the PSNR of every grid aperture too.

import CoreImage
import Foundation

struct Job: Decodable {
    let name: String
    let width: Int
    let height: Int
    let input: String
    let disparity: String
    let matte: String
    let truth: String
    let output: String
    let focusRect: [Double]
}

struct Result: Encodable {
    let name: String
    let aperture: Double
    let psnr: Double
    let renders: Int
    let medianRenderSeconds: Double
    let grid: [[Double]]?
}

let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let context = CIContext(options: [
    .workingColorSpace: linear,
    .workingFormat: CIFormat.RGBAf,
    .cacheIntermediates: false,
])

func floats(_ path: String) -> Data {
    FileManager.default.contents(atPath: path)!
}

func image(_ data: Data, _ width: Int, _ height: Int, channels: Int) -> CIImage {
    CIImage(
        bitmapData: data,
        bytesPerRow: width * channels * 4,
        size: CGSize(width: width, height: height),
        format: channels == 4 ? .RGBAf : .Lf,
        colorSpace: channels == 4 ? linear : nil,
    )
}

func toneMapped(_ x: Float) -> Float {
    let v = max(x, 0)
    let t = min(v * (1 + v / 256) / (1 + v), 1)
    return t <= 0.0031308 ? t * 12.92 : 1.055 * pow(t, 1 / 2.4) - 0.055
}

func psnr(_ rgba: [Float], _ truth: [Float], pixels: Int) -> Double {
    var sum = 0.0
    for i in 0 ..< pixels {
        for c in 0 ..< 3 {
            let d = Double(toneMapped(rgba[i * 4 + c]) - toneMapped(truth[i * 3 + c]))
            sum += d * d
        }
    }
    return 10 * log10(1 / max(sum / Double(pixels * 3), 1e-12))
}

func render(_ job: Job, inputs: (CIImage, CIImage, CIImage), aperture: Double) -> ([Float], Double) {
    let filter = CIFilter(name: "CIDepthBlurEffect")!
    filter.setValue(inputs.0, forKey: kCIInputImageKey)
    filter.setValue(inputs.1, forKey: "inputDisparityImage")
    filter.setValue(inputs.2, forKey: "inputMatteImage")
    filter.setValue(aperture, forKey: "inputAperture")
    filter.setValue(0.0, forKey: "inputLumaNoiseScale")
    // Normalised to the image: in pixels, the filter returns its input unchanged.
    let r = job.focusRect
    let w = Double(job.width), h = Double(job.height)
    let rect = CGRect(x: r[0] / w, y: (h - r[1] - r[3]) / h, width: r[2] / w, height: r[3] / h)
    filter.setValue(CIVector(cgRect: rect), forKey: "inputFocusRect")
    var out = [Float](repeating: 0, count: job.width * job.height * 4)
    let started = Date()
    out.withUnsafeMutableBytes { buffer in
        context.render(
            filter.outputImage!,
            toBitmap: buffer.baseAddress!,
            rowBytes: job.width * 16,
            bounds: CGRect(x: 0, y: 0, width: job.width, height: job.height),
            format: .RGBAf,
            colorSpace: linear,
        )
    }
    return (out, Date().timeIntervalSince(started))
}

let args = CommandLine.arguments
let jobsPath = args[1]
let limit = args.firstIndex(of: "--limit").map { Int(args[$0 + 1])! } ?? Int.max
let keepGrid = args.contains("--grid")
let jobs = try JSONDecoder().decode([Job].self, from: floats(jobsPath))
var results: [Result] = []
let grid: [Double] = [0.5, 1, 1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22]

for job in jobs.prefix(limit) {
    let inputs = (
        image(floats(job.input), job.width, job.height, channels: 4),
        image(floats(job.disparity), job.width, job.height, channels: 1),
        image(floats(job.matte), job.width, job.height, channels: 1),
    )
    let truth = floats(job.truth).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let pixels = job.width * job.height
    var times: [Double] = []
    var tried: [(Double, Double)] = []
    var best: (aperture: Double, psnr: Double, image: [Float]) = (0, -1, [])
    func evaluate(_ a: Double) -> Double {
        let (out, seconds) = render(job, inputs: inputs, aperture: a)
        times.append(seconds)
        let p = psnr(out, truth, pixels: pixels)
        tried.append((a, p))
        if p > best.psnr {
            best = (a, p, out)
        }
        return p
    }
    let scores = grid.map(evaluate)
    let i = scores.indices.max { scores[$0] < scores[$1] }!
    var lo = grid[max(i - 1, 0)], hi = grid[min(i + 1, grid.count - 1)]
    let golden = (sqrt(5.0) - 1) / 2
    var x1 = hi - golden * (hi - lo), x2 = lo + golden * (hi - lo)
    var f1 = evaluate(x1), f2 = evaluate(x2)
    for _ in 0 ..< 6 {
        if f1 > f2 {
            hi = x2; x2 = x1; f2 = f1; x1 = hi - golden * (hi - lo); f1 = evaluate(x1)
        } else {
            lo = x1; x1 = x2; f1 = f2; x2 = lo + golden * (hi - lo); f2 = evaluate(x2)
        }
    }
    best.image.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: job.output)) }
    let median = times.sorted()[times.count / 2]
    results.append(Result(
        name: job.name, aperture: best.aperture, psnr: best.psnr, renders: times.count,
        medianRenderSeconds: median, grid: keepGrid ? tried.sorted { $0.0 < $1.0 }.map { [$0.0, $0.1] } : nil,
    ))
    print(String(
        format: "%@: aperture %.2f, PSNR %.2f, %d renders, %.3f s each",
        job.name,
        best.aperture,
        best.psnr,
        times.count,
        median,
    ))
    fflush(stdout)
}

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
let resultsURL = URL(fileURLWithPath: jobsPath).deletingLastPathComponent().appendingPathComponent("results.json")
try encoder.encode(results).write(to: resultsURL)
print("wrote \(resultsURL.path)")
