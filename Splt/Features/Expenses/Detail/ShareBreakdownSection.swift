import SpltCore
import SwiftUI

/// Each person's share. Itemized bills open up to show items, tax, tip and discount.
struct ShareBreakdownSection: View {
    let model: ExpenseDetailModel
    let expense: Expense
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            if let data = model.splitBarData {
                SplitBarView(
                    data: data, members: model.memberIDs, currentPerson: model.me?.id, stepHint: "",
                    onDrag: { _, _ in nil }, onStep: { _, _ in }, onTap: { _ in }
                )
                .accessibilityHidden(true)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            }
            ForEach(model.shareLines) { line in
                if let breakdown = line.breakdown {
                    DisclosureGroup {
                        breakdownRows(breakdown)
                    } label: {
                        row(line)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.spokenText(locale: locale))
                    .accessibilityHint("Shows the breakdown")
                } else {
                    row(line)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(line.spokenText(locale: locale))
                }
            }
        } header: {
            Text("Split")
        } footer: {
            Text(SplitMethod(expense.split).title)
        }
    }

    private func row(_ line: ShareLine) -> some View {
        HStack {
            AvatarView(person: line.person, members: model.memberIDs, size: 32)
            Text(line.name)
            Spacer(minLength: 8)
            MoneyLabel(money: line.share)
        }
    }

    @ViewBuilder
    private func breakdownRows(_ breakdown: ShareBreakdown) -> some View {
        LabeledContent("Items") { MoneyLabel(money: breakdown.items) }
        if !breakdown.tax.isZero { LabeledContent("Tax") { MoneyLabel(money: breakdown.tax) } }
        if !breakdown.tip.isZero { LabeledContent("Tip") { MoneyLabel(money: breakdown.tip) } }
        if !breakdown.discount.isZero { LabeledContent("Discount") { MoneyLabel(money: breakdown.discount) } }
    }
}
