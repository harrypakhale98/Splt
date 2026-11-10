import SpltCore
import SwiftUI

/// A friend with what they owe you or what you owe them, one line per currency. The section header
/// already says the direction, so a caption only appears when money goes both ways.
struct FriendRow: View {
    let summary: FriendSummary

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        let lines = BalanceLine.lines(for: summary.balance)
        HStack(spacing: 12) {
            AvatarView(person: summary.person, size: 28)
                .accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    nameText
                    balanceBlock(lines)
                }
            } else {
                nameText
                    // keeps a word readable: past this the amount scales down instead of taking more width
                    .frame(minWidth: 110, alignment: .leading)
                Spacer(minLength: 8)
                balanceBlock(lines)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(lines.isEmpty ? Text("Settled up") : Text(verbatim: ""))
    }

    private var nameText: some View {
        Text(summary.person.name)
            .font(.body)
            .lineLimit(2)
    }

    @ViewBuilder
    private func balanceBlock(_ lines: [BalanceLine]) -> some View {
        if !lines.isEmpty {
            let isMixed = lines.contains { $0.direction == .owed } && lines.contains { $0.direction == .owes }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                ForEach(lines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if isMixed {
                            Text(caption(for: line.direction))
                                .font(.footnote)
                                .foregroundStyle(Ink.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(MoneyFormatting.string(line.money, locale: locale, showsSign: false))
                            .font(Typeface.figure)
                            .foregroundStyle(Ink.direction(of: line.money.minorUnits))
                            // an amount never breaks across lines, as in MoneyLabel: the name wraps first
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityLabel(spoken(line))
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
