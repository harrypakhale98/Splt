import SpltCore
import SwiftUI

/// Two plain screens on first launch: what Splt is, then your name and currency.
/// There is no sign in. It can be skipped and is reachable again from Account.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataServices) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var profile = AccountProfile.shared
    private let preferences = Preferences()

    private let lastPage = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingBeat()
                        .tag(0)
                    SetupBeat(profile: profile, preferences: preferences)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .motion(.smooth, value: page)

                Button(action: advance) {
                    Text(page == lastPage ? "Start Splitting" : "Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
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

private struct OnboardingBeat: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShareStrip(colors: (0..<5).map { PersonPalette.color(at: $0 * 2) }, height: 4)
                Text("Split with people, not spreadsheets")
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Add what you paid, and Splt works out who owes whom.")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SetupBeat: View {
    @Bindable var profile: AccountProfile
    let preferences: Preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ShareStrip(colors: [PersonPalette.color(at: PersonPalette.meIndex)], height: 4)
                Text("Make it yours")
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Your name is what friends see. You can change both later.")
                    .font(.title3)
                    .foregroundStyle(Ink.secondary)

                VStack(spacing: 0) {
                    Divider().overlay(Ink.hairline)
                    TextField("Your name", text: $profile.displayName, prompt: Text("Your name"))
                        .font(.title3)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .frame(minHeight: 56)
                        .accessibilityIdentifier("onboarding.name")
                    Divider().overlay(Ink.hairline)
                    NavigationLink {
                        CurrencyPickerView()
                    } label: {
                        HStack {
                            Text("Default Currency")
                                .foregroundStyle(Ink.text)
                            Spacer()
                            Text(CurrencyCatalog.name(for: preferences.defaultCurrencyCode))
                                .foregroundStyle(Ink.secondary)
                                .multilineTextAlignment(.trailing)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Ink.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 56)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Ink.hairline)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
