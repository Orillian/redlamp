import RedlampLibrary
import SwiftUI

/// Library › Convert Lightroom Edits… (EDT-12): what the photos' Lightroom edits hold, before anything is written,
/// then the batch, and Undo once it's done.
struct LightroomConversionSheet: View {
    let presented: LightroomConversion
    @Environment(EditorModel.self) private var model

    private var conversion: LightroomConversion {
        model.lightroomConversion ?? presented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Convert Lightroom Edits").font(.headline)
            switch conversion.stage {
            case .reading:
                ProgressView("Reading the Lightroom edits of \(conversion.subject)…")
                buttons { cancel }
            case let .report(scan):
                report(scan)
            case .converting:
                let progress = model.settingsSync.progress
                ProgressView(value: Double(progress?.done ?? 0), total: Double(max(progress?.total ?? 1, 1))) {
                    Text("Converting…")
                }
                buttons {
                    Button("Stop") { model.settingsSync.cancel() }
                }
            case let .done(converted, report):
                Text("\(converted) photo\(converted == 1 ? "’s" : "s’") Lightroom edit converted.")
                    .automationIdentifier("lightroomEdits.done")
                if let report {
                    Text(report).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                buttons {
                    Button("Undo") { model.undoLightroomConversion() }
                        .disabled(!model.settingsSync.canUndo)
                        .automationIdentifier("lightroomEdits.undo")
                    Button("Done") { model.closeLightroomConversion() }
                        .keyboardShortcut(.defaultAction)
                        .automationIdentifier("lightroomEdits.close")
                }
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .focusEffectDisabled()
        .automationIdentifier("lightroomEdits.sheet")
    }

    private var cancel: some View {
        Button("Cancel", role: .cancel) { model.closeLightroomConversion() }
            .keyboardShortcut(.cancelAction)
            .automationIdentifier("lightroomEdits.cancel")
    }

    @ViewBuilder
    private func report(_ scan: LightroomXMPScan) -> some View {
        if scan.found == 0 {
            Text("None of \(conversion.subject) has a Lightroom edit in its XMP.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Of \(conversion.subject):").foregroundStyle(.secondary)
                    ForEach(Array(scan.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(scan.reasons.enumerated()), id: \.offset) { _, reason in
                        names(LightroomXMPScan.title(of: reason.reason), reason.photos)
                    }
                    if !scan.edited.isEmpty {
                        names("Already edited in Redlamp", scan.edited)
                    }
                    Text("Nothing of Lightroom’s is written: the photos and their XMP stay as they are.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .automationIdentifier("lightroomEdits.report")
        }
        buttons {
            cancel
            Button(scan.conversions.count == 1 ? "Convert 1 Photo" : "Convert \(scan.conversions.count) Photos") {
                model.confirmLightroomConversion()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(scan.conversions.isEmpty)
            .automationIdentifier("lightroomEdits.convert")
        }
    }

    private func names(_ title: String, _ photos: [URL]) -> some View {
        DisclosureGroup("\(title): \(photos.count)") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(photos.prefix(200), id: \.self) { photo in
                    Text(photo.lastPathComponent).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if photos.count > 200 {
                    Text("and \(photos.count - 200) more").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
    }

    private func buttons(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
        }
    }
}
