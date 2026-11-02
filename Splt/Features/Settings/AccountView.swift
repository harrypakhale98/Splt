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
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                SettingsSections()
            }
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

/// You at the center of the people you split with.
struct AccountHero: View {
    let profile: AccountProfile
    let summary: AccountSummary
    var onEdit: () -> Void = {}

    private let preferences = Preferences()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 18) {
            OrbitMotif(
                names: summary.orbitNames.isEmpty ? ["Sam", "Priya", "Alex"] : summary.orbitNames,
                hues: summary.orbitHues, size: 176
            ) {
                avatar
            }
            VStack(spacing: 4) {
                Text(summary.displayName(for: profile))
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                if !profile.hasName, summary.meName == nil || summary.meName == String(localized: "You") {
                    Text("Add your name so friends know it is you")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            chips
            Button(action: onEdit) {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.headline)
                    .foregroundStyle(PersonPalette.onColor)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier("account.editProfile")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                GroupGradient(members: summary.friendIDs + [summary.meID].compactMap { $0 })
                    .opacity(0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var avatar: some View {
        let name = summary.displayName(for: profile)
        if let meID = summary.meID {
            AvatarView(name: name, id: meID, size: 84)
        } else {
            AvatarView(name: name, hue: PersonPalette.meIndex, size: 84)
        }
    }

    private var chips: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout { chipItems }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chipItems: some View {
        chip("^[\(summary.groupCount) group](inflect: true)")
        chip("^[\(summary.friendCount) friend](inflect: true)")
        chip(LocalizedStringKey(preferences.defaultCurrencyCode))
    }

    private func chip(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: .capsule)
    }
}

#Preview {
    AccountView()
        .environment(Router())
}
