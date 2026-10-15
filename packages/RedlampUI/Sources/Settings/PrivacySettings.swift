import SwiftUI

/// Settings › Privacy: whether Redlamp keeps an activity log (UX-52).
struct PrivacySettings: View {
    @Bindable var activityLog: ActivityLogSetting

    var body: some View {
        Form {
            Section {
                Toggle("Keep an activity log", isOn: $activityLog.isOn)
                    .accessibilityIdentifier("settings.privacy.activity-log")
            } header: {
                Text("Activity Log")
            } footer: {
                Text("""
                As you work, Redlamp notes the tools, panels and edits you use, the messages it shows, \
                and the photos and folders you open, so that a report can say what led to a problem. \
                The log stays on this Mac, and nothing leaves it unless you send a report that includes it \
                from Help › Report a Bug or Send Feedback. Turned off, Redlamp keeps no log and deletes \
                the one it has kept, and reports go without it.
                """)
                .formFooter()
            }
        }
        .overlayScrollers()
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
