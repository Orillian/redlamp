import SwiftUI

/// Develop's photo downloading its original from iCloud (LIB-60), over its preview: the download's ring, what it says
/// (Downloading from iCloud, 18 of 42 MB) and Cancel; once it stopped, Download Again, or Try Again after a failure.
struct OriginalDownloadStatus: View {
    let download: OriginalDownload
    let cancel: () -> Void
    let again: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if download.isDownloading {
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                Image(systemName: download.state == .cancelled ? "icloud.and.arrow.down" : "exclamationmark.icloud")
            }
            Text(download.text)
                .monospacedDigit()
            if download.isDownloading {
                Button("Cancel", action: cancel)
                    .buttonStyle(.borderless)
                    .automationIdentifier("develop.download.cancel")
                    .help("Stop downloading this photo's original: it stays on its preview")
            } else {
                Button(download.state == .cancelled ? "Download Again" : "Try Again", action: again)
                    .buttonStyle(.borderless)
                    .automationIdentifier("develop.download.again")
                    .help("Download this photo's original from iCloud to edit it")
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
