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
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.body)
                    .lineLimit(2)
                Text("Paid by \(payerName) \u{00B7} \(expense.date.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.footnote)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize { amounts }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var amounts: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(MoneyFormatting.magnitudeString(expense.total, locale: locale))
                .font(Typeface.figure)
            if let myNet, !myNet.isZero {
                Text(myNet.isPositive ? "you lent \(magnitude(myNet))" : "you owe \(magnitude(myNet))")
                    .font(.caption)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func magnitude(_ money: Money) -> String {
        MoneyFormatting.magnitudeString(money, locale: locale)
    }
}
