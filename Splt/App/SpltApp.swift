import SwiftUI

@main
struct SpltApp: App {
    @State private var router = Router()
    @State private var services = LaunchServices.make()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(\.dataServices, services)
                .onOpenURL { router.open($0) }
                .groupSpotlight(services: services, router: router)
        }
    }
}
