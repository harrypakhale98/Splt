import SwiftUI

/// The Account tab: who you are, then how Splt behaves.
struct AccountView: View {
    @Environment(Router.self) private var router
    @State private var profile = AccountProfile.shared

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.accountPath) {
            List {
                Section {
                    NavigationLink {
                        ProfileEditorView(profile: profile)
                    } label: {
                        ProfileHeader(profile: profile)
                    }
                }

                SettingsSections()
            }
            .navigationTitle("Account")
            .settingsBehavior()
            .routeDestinations()
        }
    }
}

private struct ProfileHeader: View {
    let profile: AccountProfile

    var body: some View {
        HStack(spacing: 16) {
            AvatarView(name: profile.effectiveName, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.effectiveName)
                    .font(.title3.weight(.semibold))
                Group {
                    if profile.hasName {
                        Text("Name and payment details")
                    } else {
                        Text("Add your name and payment details")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    AccountView()
        .environment(Router())
}
