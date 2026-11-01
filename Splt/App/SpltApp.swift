import SwiftUI

@main
struct SpltApp: App {
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .onOpenURL { router.open($0) }
        }
    }
}
