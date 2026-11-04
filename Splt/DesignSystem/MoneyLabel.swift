import SpltCore
import SwiftUI
import UIKit

/// Shows an amount with tabular digits.
///
/// As a balance, positive means you are owed (green) and negative means you owe (red).
/// The sign is part of the text and VoiceOver reads the meaning, so color is never the only cue.
struct MoneyLabel: View {
    enum Style {
        case plain
        case balance
    }

    let money: Money
    var style: Style = .plain

    @Environment(\.locale) private var locale

    var body: some View {
        Text(MoneyFormatting.string(money, locale: locale, showsSign: style == .balance))
            .monospacedDigit()
            .foregroundStyle(color)
            .accessibilityLabel(accessibilityText)
    }

    private var color: Color {
        style == .balance ? Self.balanceTint(for: money) : .primary
    }

    /// The one rule for money you owe or are owed in a row: green when you are owed, red when you owe,
    /// quiet when settled. Heroes use the primary color and write the sign. Person colors never
    /// color an amount, only avatars and bars.
    static func balanceTint(for money: Money) -> Color {
        if money.minorUnits > 0 { return MoneyTint.owed }
        if money.minorUnits < 0 { return MoneyTint.owes }
        return .secondary
    }

    private var accessibilityText: String {
        style == .balance ? Self.spokenBalance(money, locale: locale) : MoneyFormatting.magnitudeString(money, locale: locale)
    }

    /// A signed balance in words, so VoiceOver says who owes whom instead of "plus" or "minus".
    static func spokenBalance(_ money: Money, locale: Locale) -> String {
        let amount = MoneyFormatting.magnitudeString(money, locale: locale)
        if money.minorUnits > 0 { return String(localized: "You are owed \(amount)") }
        if money.minorUnits < 0 { return String(localized: "You owe \(amount)") }
        return String(localized: "Settled up")
    }
}

/// Green and red for money text. Darker than the system colors in light mode and lighter in dark
/// mode, so text reaches 4.5 to 1 on the system backgrounds. Use the system colors for shapes.
enum MoneyTint {
    static let owedHex: (light: UInt32, dark: UInt32) = (0x1F7A33, 0x4CD964)
    static let owesHex: (light: UInt32, dark: UInt32) = (0xC62828, 0xFF6B6B)

    static let owed = adaptive(owedHex)
    static let owes = adaptive(owesHex)

    private static func adaptive(_ pair: (light: UInt32, dark: UInt32)) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: pair.dark) : UIColor(hex: pair.light) })
    }
}

enum MoneyFormatting {
    /// Display only. Stored amounts stay in integer minor units.
    static func string(_ money: Money, locale: Locale = .current, showsSign: Bool = false) -> String {
        let text = magnitudeString(money, locale: locale)
        guard showsSign, money.minorUnits != 0 else { return text }
        return (money.minorUnits > 0 ? "+" : "-") + text
    }

    /// The amount without any sign.
    static func magnitudeString(_ money: Money, locale: Locale = .current) -> String {
        money.formattedMagnitude(locale: locale)
    }
}

#Preview {
    List {
        LabeledContent("Sam owes you") { MoneyLabel(money: Money(minorUnits: 1250, currencyCode: "USD"), style: .balance) }
        LabeledContent("You owe Priya") { MoneyLabel(money: Money(minorUnits: -4075, currencyCode: "USD"), style: .balance) }
        LabeledContent("Settled") { MoneyLabel(money: Money(minorUnits: 0, currencyCode: "USD"), style: .balance) }
        LabeledContent("Dinner") { MoneyLabel(money: Money(minorUnits: 6000, currencyCode: "EUR")) }
        LabeledContent("Train") { MoneyLabel(money: Money(minorUnits: 2800, currencyCode: "JPY")) }
    }
}
