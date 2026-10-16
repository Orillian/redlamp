import RedlampDesign
import SwiftUI

/// Review, once the catalog is read and before anything is written: the headline counts, the root folders and where
/// each is, a bar for each field that comes across, the edits, and what stays behind.
struct LightroomImportReviewView: View {
    let screen: LightroomImportScreen
    let actions: LightroomImportActions

    var body: some View {
        if let review = screen.review {
            LightroomSection("At a glance") {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(review.headline.enumerated()), id: \.offset) { _, item in
                        LightroomFigure(figure: item.figure, label: item.label)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            roots(review)
            HStack(alignment: .top, spacing: 10) {
                fields(review)
                VStack(spacing: 10) {
                    if let edits = review.edits {
                        LightroomSection("Edits") {
                            EditsBar(edits: edits)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    left(review)
                }
                .frame(width: 220)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func roots(_ review: LightroomImportScreen.Review) -> some View {
        LightroomSection("Root folders") {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(review.roots) { root in
                    GridRow {
                        Text(root.place)
                            .font(Typography.label.font)
                            .foregroundStyle(Theme.value)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(root.place)
                        Text(root.stateText)
                            .font(Typography.label.font)
                            .foregroundStyle(root.action == nil ? Theme.secondaryLabel : Theme.label)
                            .lineLimit(1)
                            .help(root.stateText)
                        if let action = root.action {
                            Button(action.title) { actions.root(root.id, action) }
                                .controlSize(.small)
                                .gridColumnAlignment(.trailing)
                        } else {
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let disks = review.disks {
                Text(disks)
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.top, 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func fields(_ review: LightroomImportScreen.Review) -> some View {
        LightroomSection("What comes across") {
            if review.fields.isEmpty {
                Text("No ratings, labels, keywords or collections for the photos the library has.")
                    .font(Typography.label.font)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(review.fields, id: \.name) { field in
                    FieldBar(
                        name: field.name, count: field.count, replacing: field.replacing, scale: review.fieldsCounted,
                        figures: field.figures, accessibilityValue: field.accessibilityValue,
                    )
                }
            }
            ForEach([review.lists, review.fieldsNote].compactMap(\.self), id: \.self) { note in
                Text(note)
                    .font(Typography.caption.font)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func left(_ review: LightroomImportScreen.Review) -> some View {
        LightroomSection("Stays behind") {
            if review.left.isEmpty {
                Text("Nothing: everything the catalog holds comes across.")
                    .font(Typography.label.font)
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(review.left.prefix(4), id: \.self) { item in
                        Text(item.line)
                            .font(Typography.label.font)
                            .foregroundStyle(Theme.label)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(item.why)
                    }
                    Text(review.left.count > 4 ? "And \(review.left.count - 4) more; why, for each, in Details"
                        : "Why, for each, in Details")
                        .font(Typography.caption.font)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
    }
}

/// Step 9's Edits section as one bar: edits that convert fully, with approximations, and with settings left out.
struct EditsBar: View {
    let edits: LightroomImportScreen.Edits

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShareBar(shares: [
                ShareBar.Share(id: "fully", count: edits.fully, color: Theme.value),
                ShareBar.Share(id: "approximated", count: edits.approximated, color: Theme.trackFill),
                ShareBar.Share(id: "left out", count: edits.leftOut, color: Theme.track),
            ])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Edits")
            .accessibilityValue(edits.summary)
            Text(edits.summary)
                .font(Typography.caption.font)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }
}
