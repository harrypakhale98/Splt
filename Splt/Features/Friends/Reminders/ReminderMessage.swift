import Foundation
import SpltCore

/// The plain text for asking someone to pay you back, and the note you get as a reminder.
enum ReminderMessage {
    /// A message to send to the friend. Mentions every currency they owe in.
    static func shareText(
        friendName: String, amounts: [Money], groupNames: [String] = [], locale: Locale = .current
    ) -> String {
        let first = firstName(friendName)
        let owed = list(amounts, locale: locale)
        if groupNames.count == 1, let group = groupNames.first {
            return String(localized: "Hi \(first), a reminder that I'm owed \(owed) for \(group). Thanks.")
        }
        return String(localized: "Hi \(first), a reminder that I'm owed \(owed) from our shared expenses. Thanks.")
    }

    static func notificationTitle(friendName: String) -> String {
        String(localized: "Reminder about \(firstName(friendName))")
    }

    static func notificationBody(friendName: String, amounts: [Money], locale: Locale = .current) -> String {
        let owed = list(amounts, locale: locale)
        let first = firstName(friendName)
        return String(localized: "\(first) may still owe you \(owed). Send \(first) a reminder.")
    }

    static func firstName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }

    private static func list(_ amounts: [Money], locale: Locale) -> String {
        let parts = amounts.filter(\.isPositive).map { MoneyFormatting.magnitudeString($0, locale: locale) }
        return ListFormatter.localizedString(byJoining: parts)
    }
}
