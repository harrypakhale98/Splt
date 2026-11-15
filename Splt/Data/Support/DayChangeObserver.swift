import Foundation
import UIKit

/// Calls a handler on the main actor when the day changes under an open app: at midnight, and when the clock or
/// time zone is changed. Screens that say "Today" or "This month" use it to stay true without waiting for a save.
@MainActor
final class DayChangeObserver {
    nonisolated(unsafe) private var tokens: [any NSObjectProtocol] = []

    init(handler: @escaping @MainActor () -> Void) {
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            })
        }
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
