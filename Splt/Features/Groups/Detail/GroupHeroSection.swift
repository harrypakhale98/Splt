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
                .font(.system(.title, design: .serif))
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
            Text("You are all settled up")
                .font(Typeface.heading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(totals.owedToYou, id: \.currencyCode) { amount in
                    line("You are owed", money: amount)
                }
                ForEach(totals.youOwe, id: \.currencyCode) { amount in
                    line("You owe", money: amount)
                }
            }
        }
    }

    private func line(_ caption: LocalizedStringKey, money: Money) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
            HeroAmount(money, showsSign: false)
        }
        .accessibilityElement(children: .combine)
    }
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
