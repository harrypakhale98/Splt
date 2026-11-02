import SpltCore
import SwiftUI

/// A friend with what they owe you or what you owe them, one line per currency.
struct FriendRow: View {
    let summary: FriendSummary

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    /// What they owe you wears their own color. What you owe stays plain, with the sign written out.
    private var owedColor: Color {
        PersonPalette.textColor(at: PersonPalette.preferredIndex(for: summary.person.id))
    }

    var body: some View {
        let lines = BalanceLine.lines(for: summary.balance)
        HStack(spacing: 12) {
            AvatarView(person: summary.person, size: 44)
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
                        Text(MoneyFormatting.string(line.money, locale: locale, showsSign: true))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(line.direction == .owed ? owedColor : Color.primary)
                            .accessibilityLabel(spoken(line))
                        Text(caption(for: line.direction))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
