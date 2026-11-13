import Foundation
import UserNotifications

struct LocalNotificationContent: Equatable, Sendable {
    /// Stable, so the same change never notifies twice.
    var identifier: String
    var title: String
    var body: String
}

/// Where local notifications go, so tests do not need the system notification center.
@MainActor
protocol LocalNotificationPosting {
    func isAuthorized() async -> Bool
    func requestAuthorization() async -> Bool
    func post(_ content: LocalNotificationContent) async
}

struct SystemNotificationPoster: LocalNotificationPosting {
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func post(_ original: LocalNotificationContent) async {
        let content = NotificationPrivacy.apply(to: original)
        let message = UNMutableNotificationContent()
        message.title = content.title
        message.body = content.body
        message.sound = .default
        let request = UNNotificationRequest(identifier: content.identifier, content: message, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
