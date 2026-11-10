import SpltCore
import SwiftUI

/// One shared expense on the timeline: what it was, who paid, and what it came to.
struct FriendTimelineRow: View {
    let expense: Expense
    let payerName: String
    let myNet: Money?

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Large text has no room beside the title, so the amounts go underneath it.
                VStack(alignment: .leading, spacing: 4) {
                    details
                    amounts(alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    details
                    Spacer(minLength: 8)
                    amounts(alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(expense.title)
                .font(.body)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            Text("Paid by \(payerName) \u{00B7} \(expense.date.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.footnote)
                .foregroundStyle(Ink.secondary)
        }
    }

    private func amounts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(MoneyFormatting.magnitudeString(expense.total, locale: locale))
                .font(Typeface.figure)
            if let myNet, !myNet.isZero {
                Text(myNet.isPositive ? "you lent \(magnitude(myNet))" : "you owe \(magnitude(myNet))")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func magnitude(_ money: Money) -> String {
        MoneyFormatting.magnitudeString(money, locale: locale)
    }
}
