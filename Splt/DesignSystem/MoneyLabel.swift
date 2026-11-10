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
        style == .balance ? Self.balanceTint(for: money) : Ink.text
    }

    /// The one rule for money you owe or are owed in a row: green when you are owed, red when you owe,
    /// quiet when settled. Heroes use the primary color and write the sign. Person colors never
    /// color an amount, only avatars and bars.
    static func balanceTint(for money: Money) -> Color {
        if money.minorUnits > 0 { return Ink.owed }
        if money.minorUnits < 0 { return Ink.owe }
        return Ink.secondary
    }

    private var accessibilityText: String {
        let amount = MoneyFormatting.magnitudeString(money, locale: locale)
        guard style == .balance else { return amount }
        if money.minorUnits > 0 { return String(localized: "You are owed \(amount)") }
        if money.minorUnits < 0 { return String(localized: "You owe \(amount)") }
        return String(localized: "Settled up")
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
        let digits = fractionDigits(for: money.currencyCode, locale: locale)
        let value = Decimal(sign: .plus, exponent: -digits, significand: Decimal(money.minorUnits.magnitude))
        return value.formatted(Decimal.FormatStyle.Currency(code: money.currencyCode, locale: locale))
    }

    static func fractionDigits(for currencyCode: String, locale: Locale = .current) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
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
