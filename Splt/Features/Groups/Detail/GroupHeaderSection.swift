import SpltCore
import SwiftUI

/// The group's name, your total balance and the Settle Up button.
struct GroupHeaderSection: View {
    let group: SplitGroup
    let memberCount: Int
    let totals: BalanceTotals
    let canSettle: Bool
    let onSettleUp: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                identity
                balance
                Button(action: onSettleUp) {
                    Text("Settle Up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSettle)
            }
            .padding(.vertical, 4)
        }
    }

    /// The icon beside the name, or above it when the name needs the whole width.
    private var identity: some View {
        let icon = GroupIconView(symbol: group.symbol, color: GroupAppearance.color(for: group.id), size: 52)
        let text = VStack(alignment: .leading) {
            Text(group.name)
                .font(.title2.bold())
            Text("^[\(memberCount) member](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                icon
                text
            }
            VStack(alignment: .leading, spacing: 8) {
                icon
                text
            }
        }
    }

    @ViewBuilder
    private var balance: some View {
        if totals.isSettled {
            Label("You are all settled up", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(totals.owedToYou, id: \.currencyCode) { amount in
                    line("You are owed", money: amount, sign: 1)
                }
                ForEach(totals.youOwe, id: \.currencyCode) { amount in
                    line("You owe", money: amount, sign: -1)
                }
            }
        }
    }

    private func line(_ title: LocalizedStringKey, money: Money, sign: Int64) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            MoneyLabel(
                money: Money(minorUnits: money.minorUnits * sign, currencyCode: money.currencyCode),
                style: .balance
            )
            .font(.title.bold())
        }
        .accessibilityElement(children: .combine)
    }
}
