import SpltCore
import SwiftUI

/// Two plain screens on first launch: what Splt is, then your name and currency.
/// There is no sign in. It can be skipped and is reachable again from Account.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataServices) private var services
    @Environment(Router.self) private var router: Router?

    @State private var page = 0
    @State private var profile = AccountProfile.shared
    private let preferences = Preferences()

    private let lastPage = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingBeat(onInvite: join)
                        .tag(0)
                    SetupBeat(profile: profile, preferences: preferences)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button(action: advance) {
                    Text(page == lastPage ? "Start Splitting" : "Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, OnboardingLayout.margin)
                .padding(.vertical, 16)
                .accessibilityIdentifier("onboarding.continue")
            }
            .toolbar {
                if page < lastPage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip", action: finish)
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
            }
            .paperBackground()
        }
        .accessibilityIdentifier("onboarding")
    }

    private func advance() {
        if page == lastPage {
            finish()
        } else {
            Motion.perform(.smooth) { page += 1 }
        }
    }

    /// A pasted invite skips the rest of the tour: joining is what this person came for.
    private func join(_ invite: JoinInvite) {
        finish()
        router?.open(.join(invite))
    }

    private func finish() {
        profile.save()
        if let services { try? profile.applyName(to: services.people) }
        preferences.onboardingCompleted = true
        dismiss()
    }
}

/// One edge for the whole tour, matching the cards and the rest of the app.
private enum OnboardingLayout {
    static let margin = Depth.pageMargin
}

private struct OnboardingBeat: View {
    var onInvite: (JoinInvite) -> Void = { _ in }
    @State private var notAnInvite = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShareStrip(colors: (0..<5).map { PersonPalette.color(at: $0 * 2) }, height: 4)
                Text("Split bills with friends")
                    .font(Typeface.display)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Add what you paid and see who owes whom.")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)
                inviteCard
                    .padding(.top, 8)
            }
            .padding(.horizontal, OnboardingLayout.margin)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension OnboardingBeat {
    /// Someone who installed Splt from an invite copied it on the way. Apple's Paste button reads
    /// the clipboard only when tapped, so there is no "Allow Paste" prompt.
    private var inviteCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Got an invite?")
                    .foregroundStyle(Ink.text)
                Text(notAnInvite ? "That isn't a Splt invite. Copy the whole link and try again." : "Paste the link you were sent.")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            PasteButton(payloadType: String.self) { strings in
                let invite = strings.lazy.compactMap { JoinInvite(text: $0) }.first
                Task { @MainActor in
                    if let invite {
                        notAnInvite = false
                        onInvite(invite)
                    } else {
                        notAnInvite = true
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            // the system draws its own white label, so the fill stays dark enough to read in both appearances
            .tint(Ink.whiteLabelFill)
            .accessibilityIdentifier("onboarding.paste")
        }
        .padding(Depth.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct SetupBeat: View {
    @Bindable var profile: AccountProfile
    let preferences: Preferences

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 24) {
                    ShareStrip(colors: [PersonPalette.color(at: PersonPalette.meIndex)], height: 4)
                    Text("Make it yours")
                        .font(Typeface.display)
                        .foregroundStyle(Ink.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your name is what friends see. You can change both later.")
                        .font(.title3)
                        .foregroundStyle(Ink.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 48, leading: OnboardingLayout.margin, bottom: 16, trailing: OnboardingLayout.margin))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                RaisedRows {
                    TextField("Your Name", text: $profile.displayName, prompt: Text("Your Name"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .accessibilityIdentifier("onboarding.name")
                    NavigationLink {
                        CurrencyPickerView()
                    } label: {
                        LabeledContent(
                            "Default Currency",
                            value: CurrencyCatalog.name(for: preferences.defaultCurrencyCode)
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Ink.hairline)
        .paperBackground()
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

extension View {
    /// Shows the welcome tour on first launch, and whenever the router asks for it.
    func onboardingTour(router: Router, arguments: [String] = ProcessInfo.processInfo.arguments) -> some View {
        modifier(OnboardingTour(router: router, arguments: arguments))
    }
}

private struct OnboardingTour: ViewModifier {
    @Bindable var router: Router
    let arguments: [String]
    private let preferences = Preferences()

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $router.showsOnboarding) { OnboardingView() }
            .task {
                if OnboardingGate.shouldShow(arguments: arguments, completed: preferences.onboardingCompleted) {
                    router.showsOnboarding = true
                }
            }
    }
}

#Preview {
    OnboardingView()
}
