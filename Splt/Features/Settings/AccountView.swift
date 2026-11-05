import SpltCore
import SwiftUI

/// The Account tab: who you are, then how Splt behaves.
struct AccountView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @State private var profile = AccountProfile.shared
    @State private var summary = AccountSummary()
    @State private var showsEditor = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.accountPath) {
            List {
                Section {
                    AccountHero(profile: profile, summary: summary) { showsEditor = true }
                }

                SettingsSections()
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Ink.hairline)
            .paperBackground()
            .navigationTitle("Account")
            .settingsBehavior()
            .routeDestinations()
            .navigationDestination(isPresented: $showsEditor) {
                ProfileEditorView(profile: profile)
            }
            .task { summary = AccountSummary.load(from: services) }
            .onAppear { summary = AccountSummary.load(from: services) }
        }
    }
}

/// You: a modest avatar, your name, and a plain way to edit it.
struct AccountHero: View {
    let profile: AccountProfile
    let summary: AccountSummary
    var onEdit: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName(for: profile))
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.text)
                Button("Edit Profile", action: onEdit)
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                    .buttonStyle(.plain)
                    .underline()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("account.editProfile")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var avatar: some View {
        let name = summary.displayName(for: profile)
        if let meID = summary.meID {
            AvatarView(name: name, id: meID, size: 44)
        } else {
            AvatarView(name: name, hue: PersonPalette.meIndex, size: 44)
        }
    }
}

#Preview {
    AccountView()
        .environment(Router())
}
