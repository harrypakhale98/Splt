import Foundation
import SpltCore
import UserNotifications

/// When a reminder should fire, counted from now.
enum ReminderDelay: String, CaseIterable, Identifiable, Sendable {
    case tomorrow
    case inThreeDays
    case inAWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tomorrow: String(localized: "Tomorrow")
        case .inThreeDays: String(localized: "In 3 Days")
        case .inAWeek: String(localized: "In a Week")
        }
    }

    var days: Int {
        switch self {
        case .tomorrow: 1
        case .inThreeDays: 3
        case .inAWeek: 7
        }
    }

    /// Reminders arrive mid morning, a time people can act on them.
    func fireDate(from now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: now) ?? now
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }
}

struct ReminderRequest: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
    var fireDate: Date
    /// The `splt://` address that opens when the reminder is tapped.
    var link: URL
}

/// The part of the notification center that reminders need, so tests do not touch the system.
@MainActor
protocol ReminderCenter {
    func isAuthorized() async -> Bool
    func requestAuthorization() async -> Bool
    func add(_ request: ReminderRequest) async throws
    func remove(identifier: String) async
    /// Removes every pending request whose identifier starts with `prefix`.
    func removeAll(withPrefix prefix: String) async
}

struct SystemReminderCenter: ReminderCenter {
    nonisolated static let linkKey = "link"

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ original: ReminderRequest) async throws {
        let request = NotificationPrivacy.apply(to: original)
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [Self.linkKey: request.link.absoluteString]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: request.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
        )
    }

    func remove(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func removeAll(withPrefix prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Schedules one gentle local reminder per friend who owes you. Reminders are opt in: nothing is
/// scheduled until Notifications is turned on in Settings, and a person asks for each one.
@MainActor
struct ReminderScheduler {
    enum Outcome: Equatable, Sendable {
        case scheduled(Date)
        /// Notifications is off in Splt's Settings.
        case turnedOffInSettings
        /// The system permission was refused.
        case notAllowed
        case nothingOwed
        case blocked
    }

    var center: any ReminderCenter = SystemReminderCenter()
    var notificationsEnabled: @MainActor () -> Bool = {
        UserDefaults.standard.bool(forKey: Preferences.Key.notificationsEnabled)
    }
    var visibility = FriendVisibilityStore()
    var now: @Sendable () -> Date = { Date() }
    var calendar: Calendar = .current

    static let identifierPrefix = "reminder."

    static func identifier(for friend: PersonID) -> String {
        identifierPrefix + friend.description
    }

    func schedule(for friend: Person, owed amounts: [Money], after delay: ReminderDelay) async -> Outcome {
        guard amounts.contains(where: \.isPositive) else { return .nothingOwed }
        guard visibility.state(of: friend.id) != .blocked else { return .blocked }
        guard notificationsEnabled() else { return .turnedOffInSettings }
        if await !center.isAuthorized(), await !center.requestAuthorization() { return .notAllowed }
        let fire = delay.fireDate(from: now(), calendar: calendar)
        let request = ReminderRequest(
            identifier: Self.identifier(for: friend.id),
            title: ReminderMessage.notificationTitle(friendName: friend.name),
            body: ReminderMessage.notificationBody(friendName: friend.name, amounts: amounts),
            fireDate: fire,
            link: DeepLink.friend(friend.id.rawValue).url
        )
        do {
            try await center.add(request)
            return .scheduled(fire)
        } catch {
            return .notAllowed
        }
    }

    func cancel(for friend: PersonID) async {
        await center.remove(identifier: Self.identifier(for: friend))
    }

    /// Drops every scheduled reminder, for when Notifications is turned off in Settings.
    func cancelAll() async {
        await center.removeAll(withPrefix: Self.identifierPrefix)
    }
}
