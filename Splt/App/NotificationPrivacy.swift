import Foundation

/// With the Face ID lock on, a notification must not show names or amounts on a locked phone. The lock
/// can't hide a notification, so the text that would give something away is replaced.
enum NotificationPrivacy {
    static func isHidingDetails(store: UserDefaults = .standard) -> Bool {
        store.bool(forKey: Preferences.Key.biometricLockEnabled)
    }

    static var genericBody: String { String(localized: "Open Splt to see what changed.") }

    /// The notification as it should be posted: as written, or with its details taken out.
    static func apply(
        to content: LocalNotificationContent, store: UserDefaults = .standard
    ) -> LocalNotificationContent {
        guard isHidingDetails(store: store) else { return content }
        var hidden = content
        hidden.title = "Splt"
        hidden.body = genericBody
        return hidden
    }

    static func apply(to request: ReminderRequest, store: UserDefaults = .standard) -> ReminderRequest {
        guard isHidingDetails(store: store) else { return request }
        var hidden = request
        hidden.title = "Splt"
        hidden.body = genericBody
        return hidden
    }
}
