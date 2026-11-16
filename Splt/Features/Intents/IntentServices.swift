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
        if let cached { BalanceWidgetPublisher.start(services: cached) }
        return cached
    }

    /// Sends what an intent just saved to iCloud. Siri and Shortcuts can run Splt in the background, where no
    /// screen ever starts sync, so the change would otherwise wait until the app is next opened. Without an
    /// iCloud account the engine does nothing, and starting is skipped when sync is already running.
    func sendChanges(runtime: SyncRuntime = .shared) async {
        guard let services = live() else { return }
        await runtime.start(services: services)
        try? await runtime.engine.sendChanges()
    }

    /// Uses these services for intents, for tests and for builds that start on other data.
    func use(_ services: DataServices?) {
        cached = services
    }
}
