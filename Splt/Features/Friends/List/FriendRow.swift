import SpltCore
import SwiftUI

/// A friend with what they owe you or what you owe them, one line per currency.
struct FriendRow: View {
    let summary: FriendSummary

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        let lines = BalanceLine.lines(for: summary.balance)
        HStack(spacing: 12) {
            AvatarView(person: summary.person, size: 44)
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    nameBlock
                    balanceBlock(lines)
                }
            } else {
                nameBlock
                    // keeps a word readable: past this the amount scales down instead of taking more width
                    .frame(minWidth: 110, alignment: .leading)
                Spacer(minLength: 8)
                balanceBlock(lines)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.person.name)
                .font(.body)
            if summary.person.isPlaceholder {
                Text("Not on Splt yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func balanceBlock(_ lines: [BalanceLine]) -> some View {
        if lines.isEmpty {
            Text("Settled up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(lines) { line in
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(MoneyFormatting.string(line.money, locale: locale, showsSign: true))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MoneyLabel.balanceTint(for: line.money))
                            // an amount never breaks across lines, as in MoneyLabel: the name wraps first
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityLabel(spoken(line))
                        Text(caption(for: line.direction))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .layoutPriority(1)
        }
    }

    private func spoken(_ line: BalanceLine) -> String {
        let amount = MoneyFormatting.magnitudeString(line.money, locale: locale)
        return line.direction == .owed
            ? String(localized: "owes you \(amount)") : String(localized: "you owe \(amount)")
    }

    private func caption(for direction: BalanceDirection) -> String {
        switch direction {
        case .owed: String(localized: "owes you")
        case .owes: String(localized: "you owe")
        case .settled: String(localized: "settled up")
        }
    }
}
