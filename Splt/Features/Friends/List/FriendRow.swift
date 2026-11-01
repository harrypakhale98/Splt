import SpltCore
import SwiftUI

/// A friend with what they owe you or what you owe them, one line per currency.
struct FriendRow: View {
    let summary: FriendSummary

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let lines = BalanceLine.lines(for: summary.balance)
        HStack(spacing: 12) {
            AvatarView(name: summary.person.name, size: 44)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    nameBlock
                    balanceBlock(lines)
                }
            } else {
                nameBlock
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
                        MoneyLabel(money: line.money, style: .balance)
                            .font(.body.weight(.semibold))
                        Text(caption(for: line.direction))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func caption(for direction: BalanceDirection) -> String {
        switch direction {
        case .owed: String(localized: "owes you")
        case .owes: String(localized: "you owe")
        case .settled: String(localized: "settled up")
        }
    }
}
