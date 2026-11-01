import SpltCore
import SwiftUI

/// One group in the list: symbol, name, who is in it and your balance.
struct GroupRowView: View {
    let summary: GroupSummary

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let lines = BalanceLine.lines(for: summary.myBalance)
        HStack(spacing: 12) {
            GroupIconView(symbol: summary.group.symbol, color: GroupAppearance.color(for: summary.group.id))
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    details
                    balance(lines)
                }
            } else {
                details
                Spacer(minLength: 8)
                balance(lines)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.group.name)
                .font(.headline)
            Text("^[\(summary.memberCount) member](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func balance(_ lines: [BalanceLine]) -> some View {
        if lines.isEmpty {
            Text("Settled up")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                ForEach(lines) { line in
                    MoneyLabel(money: line.money, style: .balance)
                        .font(.body.weight(.semibold))
                    Text(line.direction.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
