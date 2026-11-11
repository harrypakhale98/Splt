import SwiftUI

/// Asks once whether to turn on notifications, at a moment they start to matter: right after you
/// share a group or join one. Never at launch. Someone who has already set the toggle in Account,
/// either way, is not asked.
@MainActor
enum NotificationAsk {
    static let askedKey = "preferences.notificationsAsked"

    /// True when notifications are off because nobody ever chose, and this hasn't been asked before.
    static func shouldAsk(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Preferences.Key.notificationsEnabled) == nil && !defaults.bool(forKey: askedKey)
    }

    static func markAsked(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askedKey)
    }

    /// Turns the toggle on and asks the system. If the system says no, the toggle goes back off.
    static func turnOn(
        defaults: UserDefaults = .standard,
        requestAuthorization: @MainActor () async -> Bool = { await SyncRuntime.shared.requestNotificationAuthorization() }
    ) async {
        markAsked(defaults: defaults)
        defaults.set(true, forKey: Preferences.Key.notificationsEnabled)
        if await !requestAuthorization() {
            defaults.set(false, forKey: Preferences.Key.notificationsEnabled)
        }
    }
}

extension View {
    /// The one-time question about notifications. Set `isPresented` only when `NotificationAsk.shouldAsk()`.
    func notificationAsk(isPresented: Binding<Bool>) -> some View {
        alert("Turn On Notifications?", isPresented: isPresented) {
            Button("Turn On") { Task { await NotificationAsk.turnOn() } }
            Button("Not Now", role: .cancel) { NotificationAsk.markAsked() }
        } message: {
            Text("Splt can tell you when someone in a shared group adds an expense or reminds you to pay.")
        }
    }
}
