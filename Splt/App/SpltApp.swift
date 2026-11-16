import CoreSpotlight
import SwiftUI

@main
struct SpltApp: App {
    /// Knows from the start whether the welcome tour is due, so a file opened at first launch waits for it.
    @State private var router = Router(showsOnboarding: OnboardingGate.shouldShowAtLaunch())
    @State private var services: DataServices?
    @State private var isReady = false
    @State private var lock = AppLock()
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) private var appDelegate

    init() {
        NotificationCoordinator.shared.install()
        Typeface.installNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady, services == nil {
                    StoreUnavailableView { services = LaunchServices.make() }
                } else if isReady {
                    RootView()
                        .personColors(services: services)
                        .syncLifecycle(services: services, router: router)
                        .groupSpotlight(services: services)
                        .friendSpotlight(services: services)
                        .notificationRouting(router: router)
                        .paymentInboxRefresh(services: services)
                        .onboardingTour(router: router)
                        // last, so the welcome tour and the other screens these modifiers present get them too
                        .environment(router)
                        .environment(lock)
                        .environment(\.dataServices, services)
                        .tint(Ink.text)
                } else {
                    Ink.paper.ignoresSafeArea()
                }
            }
            .onOpenURL { router.open($0) }
            // here rather than on the tabs, so a result tapped while Splt was closed isn't lost before they exist
            .onContinueUserActivity(CSSearchableItemActionType) { router.open($0) }
            .preferredColorScheme(LaunchAppearance.scheme())
            .appAppearance()
            .appLock(lock)
            .task { await prepare() }
        }
    }

    /// Opens the store after the first frame is on screen, so launch never waits on it.
    private func prepare() async {
        guard !isReady else { return }
        await Task.yield()
        services = LaunchServices.make()
        isReady = true
    }
}

/// Shown when the store cannot be opened. Without it the app looks empty, as if the data were gone,
/// and deleting the app is what would then really lose it.
private struct StoreUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't Open Your Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your groups and expenses could not be opened. Restart your iPhone and try again. Don't delete Splt, because that would remove them.")
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}
