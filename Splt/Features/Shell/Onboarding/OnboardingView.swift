import SpltCore
import SwiftUI

/// The welcome tour on first launch: what Splt is, your name and currency, then the real Split Bar on a
/// sample dinner. There is no sign in. It can be skipped and is reachable again from Account.
///
/// Pages change only with the buttons: a swipe between pages would fight the bar's dragging.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataServices) private var services
    @Environment(Router.self) private var router: Router?

    @State private var page = OnboardingPage.welcome
    /// Which way the pages slide, set before the page changes so the leaving page knows too.
    @State private var forward = true
    @State private var profile = AccountProfile.shared
    @State private var demo: OnboardingDemoModel
    private let preferences = Preferences()

    init() {
        let preferences = Preferences()
        _demo = State(initialValue: OnboardingDemoModel(
            currencyCode: preferences.defaultCurrencyCode, myName: AccountProfile.shared.effectiveName
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    pageView(page)
                        .id(page)
                        .motionTransition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading),
                            removal: .move(edge: forward ? .leading : .trailing)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Button(action: advance) {
                    Text(page.isLast ? "Start Splitting" : "Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, OnboardingLayout.margin)
                .padding(.vertical, 16)
                .accessibilityIdentifier("onboarding.continue")
            }
            .toolbar {
                if let previous = page.previous {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { go(to: previous) } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("onboarding.back")
                    }
                }
                if page.showsSkip {
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

    @ViewBuilder
    private func pageView(_ page: OnboardingPage) -> some View {
        Group {
            switch page {
            case .welcome: OnboardingWelcomePage(onInvite: join)
            case .profile: OnboardingProfilePage(profile: profile, preferences: preferences)
            case .demo: OnboardingDemoPage(demo: demo)
            }
        }
        .accessibilityIdentifier(page.identifier)
    }

    private func advance() {
        if let next = page.next {
            go(to: next)
        } else {
            finish()
        }
    }

    private func go(to next: OnboardingPage) {
        if next == .demo {
            // the sample split is in the currency just chosen, with your name on your avatar
            demo.currencyCode = preferences.defaultCurrencyCode
            demo.myName = profile.effectiveName
        }
        forward = next.rawValue > page.rawValue
        // a leaving page keeps the transition from its last update, so the direction lands first
        Task { @MainActor in
            Motion.perform(Motion.smooth) { page = next }
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    /// A pasted invite skips the rest of the tour: joining is what this person came for.
    private func join(_ invite: JoinInvite) {
        // the name page was skipped, so take the name the invite was made for over a guess from the device
        if let name = invite.name, !profile.hasChosenName { profile.displayName = name }
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
