import RedlampDesign
import SwiftUI

/// Photos a second over time, newest at the right, stretches the Mac paused shaded: a stalled import looks stalled,
/// a slow one steady. Bins before the work started are left empty.
struct ThroughputChart: View {
    let bins: [ThroughputBin]
    var height: CGFloat = 46

    var body: some View {
        let top = Self.scale(bins.compactMap(\.perSecond).max() ?? 0)
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing) {
                Text(ProgressText.count(Int(top)))
                Spacer(minLength: 0)
                Text("0")
            }
            .font(Typography.badge.font)
            .foregroundStyle(Theme.tertiaryLabel)
            .frame(width: 26, alignment: .trailing)
            ZStack {
                PauseShading(bins: bins)
                    .fill(Theme.selection)
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                ThroughputLine(bins: bins, top: top)
                    .stroke(Theme.trackFill, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }

    /// A round number above the highest rate, so the line never touches the top: 1, 2 or 5 times a power of ten.
    static func scale(_ highest: Double) -> Double {
        let target = max(highest * 1.15, 1)
        let power = pow(10, floor(log10(target)))
        return [1.0, 2, 5, 10].map { $0 * power }.first { $0 >= target } ?? 10 * power
    }
}

/// The rates as a line through the middle of each bin, broken where there's no data.
private struct ThroughputLine: Shape {
    let bins: [ThroughputBin]
    let top: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !bins.isEmpty, top > 0 else { return path }
        let step = rect.width / CGFloat(bins.count)
        var drawing = false
        for (index, bin) in bins.enumerated() {
            guard let rate = bin.perSecond else {
                drawing = false
                continue
            }
            let point = CGPoint(
                x: rect.minX + step * (CGFloat(index) + 0.5),
                y: rect.maxY - rect.height * CGFloat(min(rate / top, 1)),
            )
            if drawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                drawing = true
            }
        }
        return path
    }
}

/// The bins the Mac paused the work in, as rectangles the chart's height.
private struct PauseShading: Shape {
    let bins: [ThroughputBin]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !bins.isEmpty else { return path }
        let step = rect.width / CGFloat(bins.count)
        for (index, bin) in bins.enumerated() where bin.paused != nil {
            path.addRect(CGRect(x: rect.minX + step * CGFloat(index), y: rect.minY, width: step, height: rect.height))
        }
        return path
    }
}
