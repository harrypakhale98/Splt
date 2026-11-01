import SwiftUI
import UserNotifications

/// Shows reminders while the app is open and opens the friend when one is tapped.
@MainActor
final class ReminderNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    private let open: @MainActor (URL) -> Void

    init(open: @escaping @MainActor (URL) -> Void) {
        self.open = open
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let link = response.notification.request.content.userInfo[SystemReminderCenter.linkKey] as? String
        guard let url = link.flatMap(URL.init(string:)) else { return }
        await open(url)
    }
}

extension View {
    /// Lets a tapped reminder open the matching screen.
    func reminderNotifications(router: Router) -> some View {
        modifier(ReminderNotificationModifier(router: router))
    }
}

private struct ReminderNotificationModifier: ViewModifier {
    let router: Router
    @State private var handler: ReminderNotificationHandler?

    func body(content: Content) -> some View {
        content.task {
            guard handler == nil else { return }
            let made = ReminderNotificationHandler { router.open($0) }
            handler = made
            UNUserNotificationCenter.current().delegate = made
        }
    }
}
