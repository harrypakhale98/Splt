import SpltCore
import SwiftUI

/// The one big number of a screen: rounded numerals that roll when the value changes.
struct HeroAmount: View {
    let money: Money
    var showsSign = true
    /// Defaults to the primary text color. Never use color as the only sign of direction.
    var tint: Color?

    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 52
    @Environment(\.locale) private var locale

    init(_ money: Money, showsSign: Bool = true, tint: Color? = nil) {
        self.money = money
        self.showsSign = showsSign
        self.tint = tint
    }

    var body: some View {
        Text(MoneyFormatting.string(money, locale: locale, showsSign: showsSign))
            .font(.system(size: min(size, 80), weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint ?? .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText(value: Double(money.minorUnits)))
            .motion(.smooth, value: money)
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
