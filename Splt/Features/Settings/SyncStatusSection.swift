import SwiftUI

/// What the iCloud row says for each sync state.
enum SyncStatusPresentation {
    static func detail(for status: SyncStatus) -> String {
        switch status {
        case .noAccount:
            String(localized: "To share groups with friends, open the Settings app, tap your name, choose iCloud and turn it on. Until then your groups stay on this device.")
        case .unavailable:
            String(localized: "iCloud sync isn't available in this build. Your groups stay on this device.")
        default:
            status.detail
        }
    }

    /// Whether the status is a problem worth marking outside Account. Having no iCloud is a choice, not a problem.
    static func needsAttention(_ status: SyncStatus) -> Bool {
        if case .error = status { true } else { false }
    }

    static func tint(for status: SyncStatus) -> Color {
        switch status {
        case .error: Ink.owe
        case .idle, .offline, .noAccount, .restricted, .unavailable, .syncing: Ink.secondary
        }
    }
}

/// The Sync section of Settings, showing the live state of iCloud sync.
struct SyncStatusSection: View {
    private let runtime = SyncRuntime.shared

    var body: some View {
        SyncStatusSectionContent(status: runtime.status)
    }
}

struct SyncStatusSectionContent: View {
    let status: SyncStatus

    var body: some View {
        Section {
            LabeledContent {
                Text(status.title)
            } label: {
                Label {
                    Text("iCloud Sync")
                } icon: {
                    Image(systemName: status.symbolName)
                        .foregroundStyle(SyncStatusPresentation.tint(for: status))
                }
            }
            .accessibilityElement(children: .combine)
            .raisedRow()
        } header: {
            SectionHeader("Sync")
        } footer: {
            Text(SyncStatusPresentation.detail(for: status))
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
        }
        .paperSection()
    }
}

#Preview("Up to date") {
    Form { SyncStatusSectionContent(status: .idle) }
}

#Preview("No account") {
    Form { SyncStatusSectionContent(status: .noAccount) }
}

#Preview("Unavailable") {
    Form { SyncStatusSectionContent(status: .unavailable) }
}

#Preview("Error") {
    Form { SyncStatusSectionContent(status: .error("iCloud storage is full.")) }
}
