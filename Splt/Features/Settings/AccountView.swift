import SpltCore
import SwiftUI

/// The Account tab: who you are, then how Splt behaves.
struct AccountView: View {
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var services
    @State private var profile = AccountProfile.shared
    @State private var meID: PersonID?

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.accountPath) {
            List {
                Section {
                    NavigationLink {
                        ProfileEditorView(profile: profile)
                    } label: {
                        ProfileHeader(profile: profile, meID: meID)
                    }
                }

                SettingsSections()
            }
            .navigationTitle("Account")
            .settingsBehavior()
            .routeDestinations()
            .task { meID = (try? services?.people.me())?.id }
        }
    }
}

private struct ProfileHeader: View {
    let profile: AccountProfile
    let meID: PersonID?

    @ViewBuilder
    private var avatar: some View {
        if let meID {
            AvatarView(name: profile.effectiveName, id: meID, size: 60)
        } else {
            AvatarView(name: profile.effectiveName, size: 60)
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            avatar
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
