import SpltCore
import SwiftUI

/// One group in the list: its glyph or cover photo, name, one quiet line and your balance in a word and a figure.
struct GroupRowView: View {
    let summary: GroupSummary

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let lines = BalanceLine.lines(for: summary.myBalance)
        let glyph = GroupGlyph(symbol: summary.group.symbol, cover: summary.group.shownCoverFileName, size: 32)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    glyph
                    details
                    balance(lines)
                }
            } else {
                HStack(spacing: 14) {
                    glyph
                    details
                    Spacer(minLength: 8)
                    balance(lines)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.group.name)
                .font(.headline)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            Text("^[\(summary.memberCount) member](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
        }
    }

    @ViewBuilder
    private func balance(_ lines: [BalanceLine]) -> some View {
        if lines.isEmpty {
            Text(summary.isSettled ? "Settled up" : "Not settled up")
                .font(.subheadline)
                .foregroundStyle(Ink.secondary)
        } else {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                ForEach(lines) { line in
                    DirectionAmount(money: line.money, direction: line.direction)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Rows") {
    let services = SampleData.previewServices()
    List(services.groupsStore.summaries) { summary in
        GroupRowView(summary: summary)
    }
}

#Preview("Large text") {
    let services = SampleData.previewServices()
    List(services.groupsStore.summaries.prefix(2)) { summary in
        GroupRowView(summary: summary)
    }
    .dynamicTypeSize(.accessibility3)
}
#endif
