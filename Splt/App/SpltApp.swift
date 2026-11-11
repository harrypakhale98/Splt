import SwiftUI

@main
struct SpltApp: App {
    @State private var router = Router()
    @State private var services: DataServices?
    @State private var isReady = false
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
                        .environment(router)
                        .environment(\.dataServices, services)
                        .personColors(services: services)
                        .syncLifecycle(services: services, router: router)
                        .groupSpotlight(services: services, router: router)
                        .friendSpotlight(services: services, router: router)
                        .notificationRouting(router: router)
                        .onboardingTour(router: router)
                        .tint(Ink.text)
                } else {
                    Ink.paper.ignoresSafeArea()
                }
            }
            .onOpenURL { router.open($0) }
            .preferredColorScheme(LaunchAppearance.scheme())
            .appAppearance()
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
