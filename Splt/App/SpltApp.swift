import SwiftUI

@main
struct SpltApp: App {
    @State private var router = Router()
    @State private var services = LaunchServices.make()
    @UIApplicationDelegateAdaptor(SyncAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.dataServices, services)
                .onOpenURL { router.open($0) }
                .syncLifecycle(services: services, router: router)
                .groupSpotlight(services: services, router: router)
                .friendSpotlight(services: services, router: router)
                .reminderNotifications(router: router)
        }
    }
}
