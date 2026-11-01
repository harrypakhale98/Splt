import SwiftUI

struct AccountView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.accountPath) {
            List {
                Section {
                    HStack(spacing: 16) {
                        AvatarView(name: String(localized: "You"), size: 56)
                        VStack(alignment: .leading) {
                            Text("You")
                                .font(.headline)
                            Text("Your Apple Account identifies you. There is nothing to sign up for.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    NavigationLink(value: Route.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Account")
            .routeDestinations()
        }
    }
}

#Preview {
    AccountView()
        .environment(Router())
}
