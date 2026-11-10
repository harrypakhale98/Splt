import SpltCore
import SwiftUI

/// The top of a friend's screen, on paper: who they are, the net balance in one big ink number with
/// a sentence that says which way it goes, and the one thing to do next. Settle up is left out when you are square.
struct FriendHero: View {
    let friend: Person
    let balance: [Money]
    let canSettle: Bool
    let onSettle: () -> Void
    let onAdd: () -> Void

    @Environment(\.locale) private var locale

    private var position: NetPosition {
        NetPosition(totals: BalanceTotals(amounts: balance))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AvatarView(person: friend, size: 36)
                Text(friend.name)
                    .font(.headline)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            figure
            VStack(spacing: 4) {
                if canSettle {
                    Button("Settle Up", action: onSettle)
                        .buttonStyle(PrimaryButtonStyle())
                }
                Button("Add Expense", action: onAdd)
                    .font(.body)
                    .foregroundStyle(Ink.text)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private var figure: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let amount = position.primary {
                HeroAmount(amount, showsSign: false)
                Text(sentence(for: amount))
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
                if !position.others.isEmpty {
                    Text("Also \(otherAmounts)")
                        .font(Typeface.figure)
                        .foregroundStyle(Ink.secondary)
                        .accessibilityLabel(Text("Also \(spokenOthers)"))
                }
            } else {
                Text("Settled up")
                    .font(Typeface.hero(size: 44))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .letterpress()
                Text("Nothing owed between you and \(ReminderMessage.firstName(friend.name)).")
                    .font(.subheadline)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sentence(for amount: Money) -> String {
        let first = ReminderMessage.firstName(friend.name)
        return amount.isPositive
            ? String(localized: "\(first) owes you")
            : String(localized: "You owe \(first)")
    }

    private var otherAmounts: String {
        ListFormatter.localizedString(
            byJoining: position.others.map { MoneyFormatting.string($0, locale: locale, showsSign: true) }
        )
    }

    private var spokenOthers: String {
        ListFormatter.localizedString(byJoining: position.others.map { MoneyLabel.spokenBalance($0, locale: locale) })
    }
}
