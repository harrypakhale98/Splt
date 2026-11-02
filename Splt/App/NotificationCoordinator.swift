import SwiftUI
import UserNotifications

/// The only delegate of the notification center, which accepts just one. It decides how a
/// notification shows while the app is open and which screen a tap opens, for every feature that
/// posts notifications: friend reminders and changes from friends.
@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    /// Opens a `splt://` address. The app sets it to the router, and a tap that arrived earlier,
    /// such as the one that launched the app, is delivered then.
    var open: (@MainActor (URL) -> Void)? {
        didSet {
            guard let open, let url = pending else { return }
            pending = nil
            open(url)
        }
    }

    private var pending: URL?

    /// Takes over as the delegate. Call once at launch, before the app finishes starting.
    func install(on center: UNUserNotificationCenter = .current()) {
        center.delegate = self
    }

    /// The screen a notification leads to, from what it carries.
    nonisolated static func destination(identifier: String, userInfo: [AnyHashable: Any]) -> URL? {
        if let link = userInfo[SystemReminderCenter.linkKey] as? String, let url = URL(string: link),
           DeepLink(url: url) != nil {
            return url
        }
        if identifier.hasPrefix("splt.activity.") || identifier.hasPrefix("splt.summary.") {
            return DeepLink.activity.url
        }
        return nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard let url = Self.destination(identifier: request.identifier, userInfo: request.content.userInfo) else { return }
        await handle(url)
    }

    private func handle(_ url: URL) {
        if let open {
            open(url)
        } else {
            pending = url
        }
    }
}

extension View {
    /// Lets a tapped notification open the matching screen.
    func notificationRouting(router: Router) -> some View {
        task {
            NotificationCoordinator.shared.open = { router.open($0) }
        }
    }
}
