import SpltCore
import SwiftUI

extension NetPosition {
    init(totals: BalanceTotals) {
        self.init(owedToYou: totals.owedToYou, youOwe: totals.youOwe)
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
    @Environment(\.dataServices) private var services
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = HeroAmount.baseSize

    private var position: NetPosition {
        NetPosition(owedToYou: totals.owedToYou, youOwe: totals.youOwe, unitValues: services?.rates.snapshot.unitValues() ?? [:])
    }

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
                    .accessibilityLabel(Text("Also \(spokenOthers)"))
            }
        } else {
            Text(position.settledTitle)
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

    private var spokenOthers: String {
        ListFormatter.localizedString(byJoining: position.others.map { MoneyLabel.spokenBalance($0, locale: locale) })
    }

    private var sentence: String {
        NetPosition.sentence(owedToYou: totals.owedToYou, youOwe: totals.youOwe, locale: locale)
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
