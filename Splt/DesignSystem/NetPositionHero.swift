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
/// and who the money is between.
struct NetPositionHero: View {
    let totals: BalanceTotals
    var owedBy: [Person] = []
    var owedTo: [Person] = []

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var position: NetPosition { NetPosition(totals: totals) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Balance")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            figure
            Text(sentence)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !owedBy.isEmpty || !owedTo.isEmpty {
                people
                    .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                GroupGradient(members: (owedBy + owedTo).map(\.id))
                    .opacity(0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var figure: some View {
        if let primary = position.primary {
            HeroAmount(primary)
            if !position.others.isEmpty {
                Text("Also \(otherAmounts)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        } else {
            Text("All Square")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
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
        case (true, true): return String(localized: "Nobody owes anybody. Enjoy it.")
        case (false, true): return String(localized: "You are owed \(owed).")
        case (true, false): return String(localized: "You owe \(owe).")
        case (false, false): return String(localized: "You are owed \(owed) and you owe \(owe).")
        }
    }

    @ViewBuilder
    private var people: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        layout {
            if !owedBy.isEmpty {
                stack(owedBy, caption: "Owe You")
            }
            if !owedTo.isEmpty {
                stack(owedTo, caption: "You Owe")
            }
        }
    }

    private func stack(_ people: [Person], caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AvatarStack(people, size: 30, limit: 3, ring: Color(.secondarySystemGroupedBackground))
            Text(caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Fades and shrinks a hero slightly as it scrolls away. Only a fade with Reduce Motion.
    func heroScrollTransition() -> some View {
        modifier(HeroScrollTransition())
    }
}

private struct HeroScrollTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scrollTransition(.animated(.smooth)) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(reduceMotion || phase.isIdentity ? 1 : 0.95)
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
    .background(Color(.systemGroupedBackground))
}
#endif
