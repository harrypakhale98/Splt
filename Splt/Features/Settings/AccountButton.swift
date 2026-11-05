import SwiftUI

/// Your avatar in a tab's top bar. It opens the Account screen and marks a sync problem, which lives there.
struct AccountButton: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @State private var profile = AccountProfile.shared
    @State private var summary = AccountSummary()
    private let runtime = SyncRuntime.shared

    var body: some View {
        Button {
            router.openAccount()
        } label: {
            AccountAvatar(profile: profile, summary: summary, size: 32)
                .overlay(alignment: .topTrailing) {
                    if needsAttention {
                        Circle()
                            .fill(Ink.owe)
                            .frame(width: 10, height: 10)
                            .accessibilityIdentifier("account.syncBadge")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(needsAttention ? "Account, iCloud sync needs attention" : "Account")
        .accessibilityIdentifier("account.button")
        // the sheet is where your name changes, so read it again each time that closes
        .task(id: router.sheet) { summary = AccountSummary.load(from: services) }
    }

    private var needsAttention: Bool {
        SyncStatusPresentation.needsAttention(runtime.status)
    }
}

/// The leading top bar item that opens Account, shared by the main tabs.
struct AccountToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AccountButton()
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

#Preview {
    NavigationStack {
        Text("Groups")
            .toolbar { AccountToolbarItem() }
    }
    .environment(Router())
}
