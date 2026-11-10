import SpltCore
import SwiftUI

/// The one big number of a screen: serif numerals that roll when the value changes.
struct HeroAmount: View {
    let money: Money
    var showsSign = true
    /// Defaults to the primary text color. Never use color as the only sign of direction.
    var tint: Color?

    /// The hero's size at the default text size, and the most it grows to with larger text.
    static let baseSize: CGFloat = 52
    static let maxSize: CGFloat = 80

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = HeroAmount.baseSize
    @Environment(\.locale) private var locale

    init(_ money: Money, showsSign: Bool = true, tint: Color? = nil) {
        self.money = money
        self.showsSign = showsSign
        self.tint = tint
    }

    var body: some View {
        Text(MoneyFormatting.string(money, locale: locale, showsSign: showsSign))
            .font(Typeface.hero(size: min(size, Self.maxSize)))
            .monospacedDigit()
            .foregroundStyle(tint ?? Ink.text)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .motion(.smooth, value: money)
            .letterpress()
            .accessibilityLabel(spokenText)
    }

    private var spokenText: String {
        let amount = MoneyFormatting.magnitudeString(money, locale: locale)
        guard showsSign else { return amount }
        if money.minorUnits > 0 { return String(localized: "You are owed \(amount)") }
        if money.minorUnits < 0 { return String(localized: "You owe \(amount)") }
        return String(localized: "Settled up")
    }
}

#Preview {
    VStack(spacing: 24) {
        HeroAmount(Money(minorUnits: 12_850, currencyCode: "USD"))
        HeroAmount(Money(minorUnits: -4_075, currencyCode: "EUR"))
        HeroAmount(Money(minorUnits: 0, currencyCode: "USD"))
    }
    .padding()
}
