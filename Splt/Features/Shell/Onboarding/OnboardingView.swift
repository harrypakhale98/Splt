import SpltCore
import SwiftUI

/// Three short beats on first launch: what Splt is, what colors mean, then your name and currency.
/// There is no sign in. It can be skipped and is reachable again from Account.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataServices) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var profile = AccountProfile.shared
    private let preferences = Preferences()

    private let lastPage = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingBeat(
                        title: "Split with people, not spreadsheets",
                        message: "Add what you paid. Splt works out who owes whom, to the cent, and keeps it all in one place.",
                        symbol: "divide",
                        names: ["Sam", "Priya", "Alex", "Jo", "Mia"]
                    )
                    .tag(0)
                    OnboardingBeat(
                        title: "Everyone has a color",
                        message: "Each person keeps one color in every group, balance and split, so you can tell who is who at a glance.",
                        symbol: "paintpalette",
                        names: ["Ana", "Ben", "Cleo", "Dev", "Eli", "Fay", "Gus"]
                    )
                    .tag(1)
                    SetupBeat(profile: profile, preferences: preferences)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .motion(.smooth, value: page)

                PageDots(count: lastPage + 1, current: page)
                    .padding(.vertical, 16)

                Button(action: advance) {
                    Text(page == lastPage ? "Start Splitting" : "Continue")
                        .font(.headline)
                        .foregroundStyle(PersonPalette.onColor)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
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
            .background(Color(.systemGroupedBackground))
        }
        .interactiveDismissDisabled(page == lastPage)
        .accessibilityIdentifier("onboarding")
    }

    private func advance() {
        if page == lastPage {
            finish()
        } else {
            withAnimation(Motion.animation(.smooth, reduceMotion: reduceMotion)) { page += 1 }
        }
    }

    private func finish() {
        profile.save()
        if let services { try? profile.applyName(to: services.people) }
        preferences.onboardingCompleted = true
        dismiss()
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color(.tertiaryLabel))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .motion(.smooth, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

private struct OnboardingBeat: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String
    let names: [String]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                OrbitMotif(names: names, size: 240) {
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 24)
                VStack(spacing: 12) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SetupBeat: View {
    @Bindable var profile: AccountProfile
    let preferences: Preferences

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                OrbitMotif(names: ["Sam", "Priya", "Alex", "Jo", "Mia"], size: 240) {
                    ZStack {
                        AvatarView(
                            name: profile.displayName, hue: PersonPalette.meIndex, size: 88,
                            showsInitials: profile.hasName
                        )
                        if !profile.hasName {
                            Image(systemName: "person.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(PersonPalette.onColor(at: PersonPalette.meIndex))
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.top, 24)

                VStack(spacing: 12) {
                    Text("Make it yours")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your name is what friends see. You can change both later.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 0) {
                    TextField("Your name", text: $profile.displayName, prompt: Text("Your Name"))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .padding(18)
                        .frame(minHeight: 56)
                        .accessibilityIdentifier("onboarding.name")
                    Divider().padding(.leading, 18)
                    NavigationLink {
                        CurrencyPickerView()
                    } label: {
                        HStack {
                            Text("Default Currency")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(CurrencyCatalog.name(for: preferences.defaultCurrencyCode))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(18)
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                }
                .cardSurface(radius: 24)

                Text("Splt is free forever: no ads, no limits, no subscription, and nothing to sign up for. With iCloud on, your groups sync between your devices and the people you share them with. Without it, everything stays on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
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
