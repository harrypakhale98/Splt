import SpltCore
import SwiftUI

/// Your total across every active group, at the top of the list.
struct OverallBalanceSection: View {
    let totals: BalanceTotals

    var body: some View {
        Section {
            if totals.isSettled {
                Label("You are all settled up", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                if !totals.owedToYou.isEmpty {
                    row("You are owed", amounts: totals.owedToYou, sign: 1)
                }
                if !totals.youOwe.isEmpty {
                    row("You owe", amounts: totals.youOwe, sign: -1)
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, amounts: [Money], sign: Int64) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing) {
                ForEach(amounts, id: \.currencyCode) { amount in
                    MoneyLabel(
                        money: Money(minorUnits: amount.minorUnits * sign, currencyCode: amount.currencyCode),
                        style: .balance
                    )
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    List {
        OverallBalanceSection(totals: BalanceTotals(
            owedToYou: [Money(minorUnits: 12_500, currencyCode: "EUR")],
            youOwe: [Money(minorUnits: 4_000, currencyCode: "USD")]
        ))
        OverallBalanceSection(totals: .zero)
    }
}
#endif
