import Foundation

/// Gives App Intents the same data the app window uses. Intents run inside the app process, so
/// they must share one store with the screens instead of opening a second one.
@MainActor
final class IntentServices {
    static let shared = IntentServices()

    private var cached: DataServices?

    /// Makes the app's data on first use and hands out the same services afterwards.
    func live() -> DataServices? {
        if let cached { return cached }
        cached = try? DataServices.live()
        return cached
    }

    /// Uses these services for intents, for tests and for builds that start on other data.
    func use(_ services: DataServices?) {
        cached = services
    }
}
