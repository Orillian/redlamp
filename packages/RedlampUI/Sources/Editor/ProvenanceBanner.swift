import SwiftUI

/// Over the canvas, for an edit converted from Lightroom (EDT-12, EDT-23): where it came from and how fully it
/// converted, with the settings approximated and left out in Details, and Convert Again for an edit from XMP. Hidden
/// for the photo once closed.
struct ProvenanceBanner: View {
    @Environment(EditorModel.self) private var model
    @State private var closedFor: URL?
    @State private var showsDetails = false

    var body: some View {
        if let notice = model.provenanceNotice, let url = model.selection, closedFor != url {
            HStack(spacing: 10) {
                Text(notice.title)
                    .foregroundStyle(.secondary)
                    .automationIdentifier("provenance.title")
                if !notice.leftOut.isEmpty || !notice.approximated.isEmpty || notice.canConvertAgain {
                    Button("Details") { showsDetails = true }
                        .buttonStyle(.borderless)
                        .automationIdentifier("provenance.details")
                        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                            details(notice)
                        }
                }
                Button {
                    closedFor = url
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide for this photo")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .contain)
            .automationIdentifier("provenance.notice")
        }
    }

    private func details(_ notice: ProvenanceNotice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !notice.leftOut.isEmpty {
                section("Left out", notice.leftOut)
            }
            if !notice.approximated.isEmpty {
                section("Approximated", notice.approximated)
            }
            if notice.canConvertAgain {
                Divider()
                Text(
                    "Convert Again replaces this edit with a new conversion of the photo’s XMP, keeping this edit as a snapshot.",
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Convert Again") {
                    showsDetails = false
                    model.convertLightroomEditAgain()
                }
                .disabled(model.isReadOnly)
                .automationIdentifier("provenance.convertAgain")
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .focusEffectDisabled()
    }

    private func section(_ title: String, _ settings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold))
            ForEach(settings, id: \.self) { setting in
                Text(setting).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
}
