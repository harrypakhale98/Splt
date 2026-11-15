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
            // an amount never breaks across lines: neighbors wrap first, then it shrinks a little
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .layoutPriority(1)
            .accessibilityLabel(accessibilityText)
    }

    private var color: Color {
        style == .balance ? Self.balanceTint(for: money) : Ink.text
    }

    /// Green when you are owed, red when you owe, plain ink when settled: `Ink.direction`, the one rule
    /// every amount follows. Person colors never color an amount, only avatars and bars.
    static func balanceTint(for money: Money) -> Color {
        Ink.direction(of: money.minorUnits)
    }

    private var accessibilityText: String {
        style == .balance ? Self.spokenBalance(money, locale: locale) : MoneyFormatting.magnitudeString(money, locale: locale)
    }

    /// A signed balance in words, so VoiceOver says who owes whom instead of "plus" or "minus".
    static func spokenBalance(_ money: Money, locale: Locale) -> String {
        MoneyFormatting.spokenBalance(money, locale: locale)
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
