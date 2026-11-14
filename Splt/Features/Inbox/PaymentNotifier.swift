import Foundation
import SpltCore
import UserNotifications

/// Payment nudges, the evening summary and the trip wrap-up reminder. They follow the Notifications
/// switch, and with the Face ID lock on they say nothing about what was bought.
@MainActor
enum PaymentNotifier {
    nonisolated static let categoryPrefix = "splt.payment"
    nonisolated static let paymentKey = "paymentID"
    nonisolated static let groupKey = "groupID"
    static let digestID = "splt.payments.digest"
    /// Long enough that the nudge doesn't arrive at the till.
    static let pause: TimeInterval = 90 * 60
    static let digestHour = 21
    static let wrapUpHour = 20

    enum Action {
        nonisolated static let split = "splt.payment.split"
        nonisolated static let choose = "splt.payment.choose"
        nonisolated static let notShared = "splt.payment.notShared"
    }

    static func identifier(for id: UUID) -> String { "\(categoryPrefix).\(id.uuidString)" }

    private static var center: UNUserNotificationCenter { .current() }

    private static var isOn: Bool {
        UserDefaults.standard.bool(forKey: Preferences.Key.notificationsEnabled)
    }

    static func nudge(_ row: InboxReview.Row, delay: TimeInterval) async {
        guard isOn else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = categoryPrefix
        var info = [
            paymentKey: row.payment.id.uuidString,
            SystemReminderCenter.linkKey: DeepLink.payment(row.payment.id).url.absoluteString
        ]
        if NotificationPrivacy.isHidingDetails() {
            content.title = "Splt"
            content.body = String(localized: "A payment is waiting in To Split.")
            content.categoryIdentifier = await category(for: nil)
        } else {
            let amount = MoneyFormatting.magnitudeString(row.payment.amount)
            content.title = row.payment.merchant
            if let group = row.target {
                content.body = String(localized: "Split \(amount) with \(SettleLeg.displayName(of: group))?")
                info[groupKey] = group.id.rawValue.uuidString
            } else {
                content.body = String(localized: "Split \(amount)?")
            }
            content.categoryIdentifier = await category(for: row.target)
        }
        content.userInfo = info
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier(for: row.payment.id), content: content, trigger: trigger))
    }

    static func cancel(_ id: UUID) {
        let ids = [identifier(for: id)]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// One list at nine in the evening of what came in today, replaced whenever the inbox changes.
    static func refreshDigest(_ review: InboxReview, calendar: Calendar = .current) async {
        center.removePendingNotificationRequests(withIdentifiers: [digestID])
        let today = review.toSplit.filter { calendar.isDate($0.payment.date, inSameDayAs: review.now) }
        guard isOn, !today.isEmpty,
              let fire = calendar.date(bySettingHour: digestHour, minute: 0, second: 0, of: review.now),
              fire > review.now else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "To Split Today")
        if NotificationPrivacy.isHidingDetails() {
            content.body = String(localized: "Payments are waiting in To Split.")
        } else {
            let named = today.prefix(3).map { "\($0.payment.merchant) \(MoneyFormatting.magnitudeString($0.payment.amount))" }
            let rest = today.count - named.count
            content.body = rest > 0
                ? String(localized: "\(named.joined(separator: ", ")) and \(rest) more")
                : named.joined(separator: ", ")
        }
        content.userInfo = [SystemReminderCenter.linkKey: DeepLink.activity.url.absoluteString]
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: digestID, content: content, trigger: trigger))
    }

    /// On the evening a trip ends, one reminder to split what was paid on it.
    static func scheduleWrapUp(_ review: InboxReview, calendar: Calendar = .current) async {
        guard isOn, let trip = review.activeTrip, review.rows.contains(where: \.isInActiveTrip),
              let end = trip.tripEnd,
              let fire = calendar.date(bySettingHour: wrapUpHour, minute: 0, second: 0, of: end),
              fire > review.now else { return }
        let content = UNMutableNotificationContent()
        if NotificationPrivacy.isHidingDetails() {
            content.title = "Splt"
            content.body = String(localized: "A trip is ready to wrap up.")
        } else {
            content.title = String(localized: "Wrap Up \(trip.name)")
            content.body = String(localized: "Split what you paid on the trip in one go.")
        }
        content.userInfo = [SystemReminderCenter.linkKey: DeepLink.activity.url.absoluteString]
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        let id = "splt.trip.wrapup.\(trip.id.rawValue.uuidString)"
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// The buttons that fit: "Split with <group>" only when there is a group to split into.
    private static func category(for group: SplitGroup?) async -> String {
        let choose = UNNotificationAction(identifier: Action.choose, title: String(localized: "Choose…"), options: [.foreground])
        let notShared = UNNotificationAction(identifier: Action.notShared, title: String(localized: "Not Shared"), options: [.destructive])
        var actions = [choose, notShared]
        var identifier = categoryPrefix
        if let group {
            identifier = "\(categoryPrefix).\(group.id.rawValue.uuidString)"
            let split = UNNotificationAction(
                identifier: Action.split,
                title: String(localized: "Split with \(SettleLeg.displayName(of: group))"),
                options: [.authenticationRequired]
            )
            actions.insert(split, at: 0)
        }
        var kept = await center.notificationCategories().filter { $0.identifier != identifier }
        // one category per group, so only a few are kept
        let perGroup = kept.filter { $0.identifier.hasPrefix("\(categoryPrefix).") }
        if perGroup.count >= 8 { kept.subtract(perGroup) }
        kept.insert(UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: []))
        center.setNotificationCategories(kept)
        return identifier
    }
}

/// What a payment notification's buttons do.
@MainActor
enum PaymentNotificationActions {
    /// Does what the button asked. Returns a link when the app should show something instead.
    static func handle(action: String, paymentID: String?, groupID: String?, inbox: PaymentInbox = .shared) -> URL? {
        inbox.reload()
        let quiet = action == PaymentNotifier.Action.split || action == PaymentNotifier.Action.notShared
        guard let id = paymentID.flatMap(UUID.init(uuidString:)), let payment = inbox.payment(id: id),
              payment.status == .pending else { return quiet ? nil : DeepLink.activity.url }
        let link = DeepLink.payment(id).url
        switch action {
        case PaymentNotifier.Action.notShared:
            inbox.dismiss(id)
            return nil
        case PaymentNotifier.Action.split:
            guard let services = inbox.services ?? IntentServices.shared.live(),
                  let groupID = groupID.flatMap(UUID.init(uuidString:)),
                  let group = try? services.groups.group(id: GroupID(rawValue: groupID)),
                  (try? inbox.split(payment, into: group, services: services)) != nil else { return link }
            return nil
        default:
            return link
        }
    }
}
