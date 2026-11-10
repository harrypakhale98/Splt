import SpltCore
import SwiftUI

/// Your net position across currencies: the currency with the biggest swing leads, the rest follow.
struct NetPosition: Equatable, Sendable {
    /// Signed net in the currency where it is largest. Nil when you are square everywhere.
    var primary: Money?
    /// Signed net in every other currency, by currency code.
    var others: [Money]

    var isSettled: Bool { primary == nil }

    init(totals: BalanceTotals) {
        var net: [String: Int64] = [:]
        for amount in totals.owedToYou { net[amount.currencyCode, default: 0] &+= amount.minorUnits }
        for amount in totals.youOwe { net[amount.currencyCode, default: 0] &-= amount.minorUnits }
        var signed: [Money] = []
        for (code, value) in net where value != 0 {
            signed.append(Money(minorUnits: value, currencyCode: code))
        }
        signed.sort { (lhs: Money, rhs: Money) -> Bool in
            let left = lhs.minorUnits.magnitude, right = rhs.minorUnits.magnitude
            if left != right { return left > right }
            return lhs.currencyCode < rhs.currencyCode
        }
        primary = signed.first
        others = Array(signed.dropFirst()).sorted { $0.currencyCode < $1.currencyCode }
    }
}

/// The hero of the Groups and Friends tabs: one big number for where you stand, a quiet sentence,
/// and a strip of who the money is between.
struct NetPositionHero: View {
    /// What the number covers, such as "Across all groups" or "With friends".
    var scope: LocalizedStringKey = "Your balance"
    let totals: BalanceTotals
    var owedBy: [Person] = []
    var owedTo: [Person] = []

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = HeroAmount.baseSize

    private var position: NetPosition { NetPosition(totals: totals) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(scope)
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
            figure
            Text(sentence)
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let everyone = owedBy + owedTo
            if !everyone.isEmpty {
                ShareStrip(people: everyone.map(\.id), isGrooved: true)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var figure: some View {
        if let primary = position.primary {
            HeroAmount(primary)
            if !position.others.isEmpty {
                Text("Also \(otherAmounts)")
                    .font(.subheadline)
                    .monospacedDigit()
            }
        } else {
            Text("All settled up")
                .font(Typeface.hero(size: min(heroSize, HeroAmount.maxSize)))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .letterpress()
        }
    }

    private var otherAmounts: String {
        ListFormatter.localizedString(
            byJoining: position.others.map { MoneyFormatting.string($0, locale: locale, showsSign: true) }
        )
    }

    private var sentence: String {
        let owed = ListFormatter.localizedString(byJoining: totals.owedToYou.map { MoneyFormatting.magnitudeString($0, locale: locale) })
        let owe = ListFormatter.localizedString(byJoining: totals.youOwe.map { MoneyFormatting.magnitudeString($0, locale: locale) })
        switch (totals.owedToYou.isEmpty, totals.youOwe.isEmpty) {
        case (true, true): return String(localized: "Nobody owes anything.")
        case (false, true): return String(localized: "You're owed \(owed).")
        case (true, false): return String(localized: "You owe \(owe).")
        case (false, false): return String(localized: "You're owed \(owed) and you owe \(owe).")
        }
    }
}

#if DEBUG
#Preview {
    let people = ["Sam Rivera", "Priya Nair", "Alex Chen", "Jo Park"].map { Person(name: $0) }
    ScrollView {
        NetPositionHero(
            totals: BalanceTotals(
                owedToYou: [Money(minorUnits: 60_000, currencyCode: "EUR")],
                youOwe: [Money(minorUnits: 8_815, currencyCode: "EUR"), Money(minorUnits: 1_500, currencyCode: "USD")]
            ),
            owedBy: Array(people.prefix(3)), owedTo: [people[3]]
        )
        .padding()
    }
    .background(Ink.paper)
}
#endif
