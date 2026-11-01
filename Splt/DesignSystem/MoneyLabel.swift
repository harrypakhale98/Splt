import SpltCore
import SwiftUI

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
        guard style == .balance else { return .primary }
        if money.minorUnits > 0 { return .green }
        if money.minorUnits < 0 { return .red }
        return .secondary
    }

    private var accessibilityText: String {
        let amount = MoneyFormatting.string(money.magnitude, locale: locale, showsSign: false)
        guard style == .balance else { return amount }
        if money.minorUnits > 0 { return String(localized: "You are owed \(amount)") }
        if money.minorUnits < 0 { return String(localized: "You owe \(amount)") }
        return String(localized: "Settled up")
    }
}

enum MoneyFormatting {
    /// Display only. Stored amounts stay in integer minor units.
    static func string(_ money: Money, locale: Locale = .current, showsSign: Bool = false) -> String {
        let digits = fractionDigits(for: money.currencyCode, locale: locale)
        let magnitude = Decimal(sign: .plus, exponent: -digits, significand: Decimal(money.minorUnits.magnitude))
        let style = Decimal.FormatStyle.Currency(code: money.currencyCode, locale: locale)
        let text = magnitude.formatted(style)
        guard showsSign, money.minorUnits != 0 else { return text }
        let sign = money.minorUnits > 0 ? "+" : "-"
        return sign + text
    }

    static func fractionDigits(for currencyCode: String, locale: Locale = .current) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }
}

private extension Money {
    var magnitude: Money {
        Money(minorUnits: Int64(minorUnits.magnitude), currencyCode: currencyCode)
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
