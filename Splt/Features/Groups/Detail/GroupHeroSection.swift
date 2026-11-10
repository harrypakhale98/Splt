import SpltCore
import SwiftUI

/// The top of a group, straight on paper: its name, dates and people, your balance in big numerals,
/// a strip of its members and the Settle Up button when there is something to settle.
struct GroupHeroSection: View {
    let group: SplitGroup
    let members: [Person]
    let totals: BalanceTotals
    let canSettle: Bool
    let onSettleUp: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                identity
                balance
                if !members.isEmpty {
                    ShareStrip(colors: members.map { PersonPalette.color(for: $0.id) }, isGrooved: true)
                }
                if canSettle {
                    Button(action: onSettleUp) {
                        Text("Settle Up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name)
                .font(Typeface.title)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let count = members.count
        let people = String(AttributedString(localized: "^[\(count) person](inflect: true)").characters)
        if let start = group.tripStart, let end = group.tripEnd {
            let range = (start..<max(end, start.addingTimeInterval(1))).formatted(.interval.day().month(.abbreviated).locale(locale))
            return "\(range) · \(people)"
        }
        return "\(group.currencyCode) · \(people)"
    }

    @ViewBuilder
    private var balance: some View {
        if totals.isSettled {
            Text("All settled up")
                .font(Typeface.heading)
        } else {
            let lines = balanceLines
            let main = lines.first { $0.money.currencyCode == group.currencyCode } ?? lines[0]
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(main.caption)
                        .font(.subheadline)
                        .foregroundStyle(Ink.secondary)
                    HeroAmount(main.money, showsSign: false)
                }
                .accessibilityElement(children: .combine)
                // one big figure per screen: other currencies sit under it as quiet lines
                ForEach(lines.filter { $0.id != main.id }) { line in
                    HStack(spacing: 6) {
                        Text(line.caption)
                            .font(.subheadline)
                            .foregroundStyle(Ink.secondary)
                        Text(MoneyFormatting.string(line.money, locale: locale))
                            .font(Typeface.figure)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Every currency you are owed or owe, owed first. Not empty unless you are settled.
    private var balanceLines: [HeroLine] {
        totals.owedToYou.map { HeroLine(isOwed: true, money: $0) } + totals.youOwe.map { HeroLine(isOwed: false, money: $0) }
    }
}

private struct HeroLine: Identifiable {
    var isOwed: Bool
    var money: Money

    var id: String { "\(isOwed)-\(money.currencyCode)" }
    var caption: LocalizedStringKey { isOwed ? "You're owed" : "You owe" }
}

#if DEBUG
#Preview("Owed") {
    let services = SampleData.previewServices()
    let trip = (try? services.groups.groups(includeArchived: false).first { $0.kind == .trip }) ?? nil
    let members = trip.flatMap { try? services.people.people(ids: $0.memberIDs) } ?? []
    List {
        if let trip {
            GroupHeroSection(
                group: trip, members: members,
                totals: BalanceTotals(owedToYou: [Money(minorUnits: 21_460, currencyCode: "EUR")], youOwe: []),
                canSettle: true, onSettleUp: {}
            )
        }
    }
    .paperBackground()
}
#endif
