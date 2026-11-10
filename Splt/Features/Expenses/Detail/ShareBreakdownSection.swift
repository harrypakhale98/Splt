import SpltCore
import SwiftUI

/// Each person's share. Itemized bills open up to show items, tax, tip and discount.
struct ShareBreakdownSection: View {
    let model: ExpenseDetailModel
    let expense: Expense
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            RaisedRows {
                ForEach(model.shareLines) { line in
                    if let breakdown = line.breakdown {
                        ExpandableShareRow(model: model, line: line, breakdown: breakdown)
                    } else {
                        ShareLineRow(model: model, line: line)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(line.spokenText(locale: locale))
                    }
                }
            }
        } header: {
            SectionHeader("Split")
        } footer: {
            Text(SplitMethod(expense.split).title)
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
        }
        // a plain list draws a section footer on white, not on the paper behind it
        .listRowBackground(Ink.paper)
    }
}

private struct ShareLineRow: View {
    let model: ExpenseDetailModel
    let line: ShareLine

    var body: some View {
        HStack {
            AvatarView(person: line.person, members: model.memberIDs, size: 28)
            Text(line.name)
            Spacer(minLength: 8)
            MoneyLabel(money: line.share).font(Typeface.figure)
        }
    }
}

/// A share that opens in place to show its breakdown. A List's DisclosureGroup would put the
/// breakdown in rows of its own, outside the card.
private struct ExpandableShareRow: View {
    let model: ExpenseDetailModel
    let line: ShareLine
    let breakdown: ShareBreakdown
    @State private var isExpanded = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Motion.perform(Motion.quick) { isExpanded.toggle() }
            } label: {
                HStack {
                    ShareLineRow(model: model, line: line)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Ink.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.spokenText(locale: locale))
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
            .accessibilityHint("Shows the breakdown")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                VStack(spacing: 6) {
                    LabeledContent("Items") { MoneyLabel(money: breakdown.items) }
                    if !breakdown.tax.isZero { LabeledContent("Tax") { MoneyLabel(money: breakdown.tax) } }
                    if !breakdown.tip.isZero { LabeledContent("Tip") { MoneyLabel(money: breakdown.tip) } }
                    if !breakdown.discount.isZero {
                        LabeledContent("Discount") { MoneyLabel(money: breakdown.discount) }
                    }
                }
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
                .padding(.leading, 36)
            }
        }
    }
}
