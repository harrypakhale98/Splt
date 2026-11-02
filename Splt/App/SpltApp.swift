import SwiftUI

@main
struct SpltApp: App {
    @State private var router = Router()
    @State private var services: DataServices?
    @State private var isReady = false
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) private var appDelegate

    init() {
        NotificationCoordinator.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    RootView()
                        .environment(router)
                        .environment(\.dataServices, services)
                        .syncLifecycle(services: services, router: router)
                        .groupSpotlight(services: services, router: router)
                        .friendSpotlight(services: services, router: router)
                        .notificationRouting(router: router)
                .onboardingTour(router: router)
                .tint(Color("AccentColor"))
                } else {
                    Color(.systemBackground).ignoresSafeArea()
                }
            }
            .onOpenURL { router.open($0) }
            .preferredColorScheme(LaunchAppearance.scheme())
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
