import SpltCore
import SwiftUI

/// One shared expense on the timeline: a marker in the color of whoever paid, joined to its neighbors by a line.
struct FriendTimelineRow: View {
    let expense: Expense
    let payerID: PersonID?
    let payerName: String
    let members: [PersonID]
    let myNet: Money?
    var isFirst = false
    var isLast = false

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    private let rail: CGFloat = 32

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            marker
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text("Paid by \(payerText) \u{00B7} \(expense.date.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize { amounts }
        }
        .padding(.vertical, 12)
        .background(alignment: .leading) {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2)
                .padding(.leading, rail / 2 - 1)
                .padding(.top, isFirst ? 28 : 0)
                .padding(.bottom, isLast ? 28 : 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var payerText: String { payerName }

    private var marker: some View {
        Group {
            if let payerID {
                AvatarView(name: payerName, id: payerID, members: members, size: rail - 4, showsInitials: false)
            } else {
                Circle().fill(Color(.tertiaryLabel)).frame(width: rail - 4, height: rail - 4)
            }
        }
        .frame(width: rail, height: rail)
        .background(Color(.secondarySystemGroupedBackground), in: .circle)
    }

    private var amounts: some View {
        VStack(alignment: .trailing, spacing: 2) {
            MoneyLabel(money: expense.total)
                .font(.body.weight(.semibold))
            if let myNet, !myNet.isZero {
                Text(myNet.isPositive ? "you lent \(magnitude(myNet))" : "you owe \(magnitude(myNet))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func magnitude(_ money: Money) -> String {
        MoneyFormatting.magnitudeString(money, locale: locale)
    }
}
