import RedlampDesign
import SwiftUI

/// The large figures of a progress screen: photos done, a share. Typography has no size for them yet.
enum ProgressTypography {
    static let figure = FontSpec(size: 20, weight: .semibold, monospacedDigits: true)
}

/// A bar of `fraction` done, split into `parts` segments when the work goes in parts (an import's parts of 10,000,
/// at whose ends Stop takes effect).
struct PartsBar: View {
    let fraction: Double
    var parts = 1
    var height: CGFloat = 6
    var fill = Theme.accent

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< max(parts, 1), id: \.self) { part in
                let share = min(max(fraction * Double(max(parts, 1)) - Double(part), 0), 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.track)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(fill)
                                .frame(width: geometry.size.width * share)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .frame(height: height)
    }
}

/// A bar split into shares of a whole, each in its own colour, left to right: how the photos' edits convert.
struct ShareBar: View {
    struct Share: Identifiable {
        let id: String
        let count: Int
        let color: Color
    }

    let shares: [Share]
    var height: CGFloat = 8

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.count }, 1)
        GeometryReader { geometry in
            let visible = shares.filter { $0.count > 0 }
            let gaps = CGFloat(max(visible.count - 1, 0))
            HStack(spacing: 1) {
                ForEach(visible) { share in
                    Rectangle()
                        .fill(share.color)
                        .frame(width: max((geometry.size.width - gaps) * CGFloat(share.count) / CGFloat(total), 1))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// A field's bar on Review: the photos that have it, of `scale`, the part that replaces a value the library shows
/// drawn first and stronger, with the field's name before it and its figures after.
struct FieldBar: View {
    let name: String
    let count: Int
    let replacing: Int
    let scale: Int
    let figures: String
    let accessibilityValue: String
    var nameWidth: CGFloat = 92
    var figuresWidth: CGFloat = 132

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(Typography.label.font)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .trailing)
            GeometryReader { geometry in
                let whole = CGFloat(max(scale, count, 1))
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.value)
                        .frame(width: geometry.size.width * CGFloat(min(replacing, count)) / whole)
                    Rectangle()
                        .fill(Theme.trackFill)
                        .frame(width: geometry.size.width * CGFloat(max(count - replacing, 0)) / whole)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.track)
            }
            .frame(height: 7)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text(figures)
                .font(Typography.value.font)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
                .frame(width: figuresWidth, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(accessibilityValue)
    }
}
